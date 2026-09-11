#!/usr/bin/env python3
"""Subset the ubuntu804 theme's DejaVu faces to what the themed pages use.

    makeFontSubset.py            write themes/ubuntu804/f/dejavu{,-bold}.woff2
    makeFontSubset.py --check    exit 1 if either is out of date, write nothing

Source is assetsBuild/fontsSrc/DejaVuSans{,-Bold}.ttf, which are NOT under
rootdomain/ and so are never served — same reasoning as cgi/ being a sibling of
the docroot rather than a child of it. Output is a committed artifact in
rootdomain/, like feed.xml and rss.xml: the deploy is a plain rsync with no
build step, so anything served has to exist in the repo.

382 kB -> ~44 kB across the two faces.

Approach: a codepoint census over the RAW bytes of every source the theme
renders, plus a fixed MARGIN of ranges the census cannot see (SSI clock text,
CSS content: injections, the window title). ubuntu804.css declares no
unicode-range, so a character in neither set just falls back to the next font
rather than turning into tofu. The census runs on every commit, so the subset
cannot drift from the content. Full rationale — why subsetting is safe, what
the margin is for — in ubuntu804theme.txt, "SUBSET FONTS SHIP".
"""

import subprocess
import sys
import tempfile
from pathlib import Path

from fontTools.ttLib import TTFont

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "assetsBuild" / "fontsSrc"
PERSONAL = ROOT / "rootdomain" / "personal"
OUT = PERSONAL / "themes" / "ubuntu804" / "f"

# The pages nginx serves with the chrome. KEEP THIS IN SYNC WITH theme.conf's
# location regex — a page in the regex but not here gets the theme without its
# characters. See ubuntu804theme.txt ("SUBSET FONTS SHIP").
THEMED = ["index", "blog", "hypnospace", "lanfalsehoods",
          "ntppool", "ntppost", "ntpuserinfo", "slowqotd", "gzipt"]

FACES = [
    ("DejaVuSans.ttf", "dejavu.woff2"),
    ("DejaVuSans-Bold.ttf", "dejavu-bold.woff2"),
]

# Everything the census might miss. Deliberately generous — see WHY THE MARGIN.
#
#   0020-007E  printable ASCII
#   00A0-00FF  Latin-1: accents, ×, ÷, £, °, the nbsp
#   2000-206F  General Punctuation: the curly quotes, dashes and thin spaces
#              that unicodePedanticism.txt requires throughout the site
#   20AC 2122  € ™
#   2190-2193  arrows, for nav affordances
#   2500-257F  box drawing, for anything that renders a frame in text
MARGIN = ("U+0020-007E,U+00A0-00FF,U+2000-206F,U+20AC,U+2122,"
          "U+2190-2193,U+2500-257F")


def census() -> set[str]:
    """Every character appearing in any source that the theme renders.

    Raw bytes, not extracted text: a stripped extraction has to parse HTML to
    decide what is content, and would miss anything a CSS content: rule
    injects. Over-inclusive by design — it picks up characters from comments
    and attributes that are never painted, which costs a few glyphs and cannot
    cause a wrong result.

    It does NOT see SSI output; see WHY THE MARGIN in the module docstring.
    """
    chars: set[str] = set()
    sources = [PERSONAL / f"{n}.html" for n in THEMED]
    sources += sorted((PERSONAL / "chrome").glob("*.html"))
    sources += [PERSONAL / "themes" / "ubuntu804.css"]
    for path in sources:
        if not path.exists():
            print(f"makeFontSubset: WARNING: no such source {path}",
                  file=sys.stderr)
            continue
        chars |= set(path.read_text(encoding="utf-8"))
    return {c for c in chars if ord(c) >= 0x20}


def wanted(src: Path, chars: set[str]) -> set[int]:
    """Codepoints the output should carry: census + margin, less what DejaVu
    hasn't got. Intersected with the source cmap so the comparison in
    up_to_date() is against what pyftsubset can actually deliver, not against
    a wish list that would never compare equal and would rebuild every run."""
    have = set(TTFont(src).getBestCmap())
    want = {ord(c) for c in chars}
    for part in MARGIN.split(","):
        part = part.replace("U+", "")
        if "-" in part:
            lo, hi = part.split("-")
            want |= set(range(int(lo, 16), int(hi, 16) + 1))
        else:
            want.add(int(part, 16))
    return want & have


def up_to_date(dest: Path, want: set[int]) -> bool:
    """Compare the existing artifact's coverage against what is wanted.

    Coverage, not a recorded hash or the file's bytes: it needs no sidecar
    file to fall out of sync, and it is the property actually being asserted.
    pyftsubset output is not byte-reproducible across fontTools versions, so
    comparing bytes would rewrite these binaries on every toolchain bump and
    put the churn straight into git history.
    """
    if not dest.exists():
        return False
    try:
        return set(TTFont(dest).getBestCmap()) == want
    except Exception:
        return False


def build(src: Path, dest: Path, chars: set[str]) -> None:
    with tempfile.NamedTemporaryFile("w", suffix=".txt", encoding="utf-8",
                                     delete=False) as fh:
        fh.write("".join(sorted(chars)))
        textfile = fh.name
    try:
        err = subprocess.run([
            "pyftsubset", str(src),
            f"--text-file={textfile}",
            f"--unicodes={MARGIN}",
            "--flavor=woff2",
            # Layout features left at pyftsubset's defaults on purpose: keeps
            # GPOS kerning, so advance widths match the faces this theme's
            # spacing was measured against. See ubuntu804theme.txt.
            "--no-recalc-timestamp",
            f"--output-file={dest}",
        ], check=True, stdout=subprocess.DEVNULL,
            stderr=subprocess.PIPE, text=True, errors="replace").stderr
        # DejaVu's TTFs carry FontForge's FFTM table, which pyftsubset does not
        # know how to subset and drops with a warning. Dropping it is correct —
        # it is a FontForge build timestamp, not font data — but the warning is
        # noise on every commit, so only unexpected stderr is passed through.
        noise = [ln for ln in err.splitlines()
                 if ln.strip() and "FFTM NOT subset" not in ln]
        if noise:
            print("\n".join(noise), file=sys.stderr)
    finally:
        Path(textfile).unlink(missing_ok=True)


def main() -> int:
    check = "--check" in sys.argv
    chars = census()
    stale = []

    for src_name, out_name in FACES:
        src, dest = SRC / src_name, OUT / out_name
        if not src.exists():
            print(f"makeFontSubset: missing source {src}", file=sys.stderr)
            return 1
        want = wanted(src, chars)
        if up_to_date(dest, want):
            continue
        stale.append(dest)
        if not check:
            OUT.mkdir(parents=True, exist_ok=True)
            build(src, dest, chars)
            kb = dest.stat().st_size / 1024
            print(f"makeFontSubset: {out_name} "
                  f"({len(want)} codepoints, {kb:.1f} kB)")

    if check and stale:
        for dest in stale:
            print(f"makeFontSubset: out of date: "
                  f"{dest.relative_to(ROOT)}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())

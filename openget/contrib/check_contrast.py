#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
# Copyright (C) 2026 robinpie
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; version 2 of the License.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.

"""WCAG 2.2 AA contrast check for every OpenGET skin.

Reads each palette straight out of the stylesheet that ships it, so it
cannot drift from what is actually served. Run after touching any colour
in any theme:

    python3 contrib/check_contrast.py

Exits non-zero on any failure. See openget.txt (ACCESSIBILITY) for what
the pair lists encode and why.
"""

import pathlib
import re
import sys

STATIC = pathlib.Path(__file__).resolve().parent.parent / "internal/web/static"


def srgb(c):
    c /= 255.0
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def lum(h):
    h = h.lstrip("#")
    if len(h) == 3:
        h = "".join(x * 2 for x in h)
    r, g, b = (int(h[i:i + 2], 16) for i in (0, 2, 4))
    return 0.2126 * srgb(r) + 0.7152 * srgb(g) + 0.0722 * srgb(b)


def cr(a, b):
    l1, l2 = lum(a), lum(b)
    if l1 < l2:
        l1, l2 = l2, l1
    return (l1 + 0.05) / (l2 + 0.05)


def blend(fg, alpha, bg):
    """Composite fg over bg at alpha. Needed for the rgba() row tints, which
    are what the eye actually sees behind table text."""
    f, b = fg.lstrip("#"), bg.lstrip("#")
    return "#" + "".join(
        "%02x" % round(int(f[i:i + 2], 16) * alpha + int(b[i:i + 2], 16) * (1 - alpha))
        for i in (0, 2, 4)
    )


# Which @media preference block, if any, to merge over the base palette. Set by
# main() so the theme functions below need to know nothing about variants.
VARIANT = None


def _props(block):
    return dict(re.findall(r"--([a-z0-9-]+):\s*(#[0-9a-fA-F]{3,6})\s*;", block))


def palette(name):
    """Pull --name: #hex; pairs out of the first :root block of a stylesheet,
    then merge the :root overrides from the VARIANT media block over the top.
    Both skins redefine part of their palette under prefers-contrast: more
    (and OSRS also under prefers-color-scheme: light) — skip that merge and
    those readers get a palette nothing has measured. See openget.txt
    (ACCESSIBILITY).
    """
    css = STATIC / name
    text = css.read_text(encoding="utf-8")
    start = text.index(":root {")
    p = _props(text[start:text.index("\n}", start)])
    if not p:
        sys.exit(f"no custom properties found in {css}")
    if VARIANT:
        m = re.search(r"@media \(" + re.escape(VARIANT) + r"\)\s*\{(.*?)\n\}",
                      text, re.S)
        if m:
            r = re.search(r":root\s*\{(.*?)\}", m.group(1), re.S)
            if r:
                p.update(_props(r.group(1)))
    return p


# ---------------------------------------------------------------------------
# Old School RuneScape — the default skin
# ---------------------------------------------------------------------------

def osrs():
    """Three grounds, and every pair below names which one it's on: SHEET
    (parchment, dark ink; --scroll is the flat, unlit worst case), FURNITURE
    (black panels + <pre>, light text), and STONE (masthead + footer, light
    text; the masthead uses --stone-lit, its one composite — see
    openget.txt LOOK AND FEEL).
    """
    p = palette("openget-osrs.css")
    parch = p["parch-0"]                      # a table, one shade above the sheet
    scroll = p["scroll"]
    even = blend("#78541e", 0.10, parch)      # tbody tr:nth-child(even)
    hover = blend("#ffbb22", 0.20, parch)     # tbody tr:hover
    stone = p["stone-lit"]
    grid = blend(p["wood-pale"], 0.22, p["void"])
    edge = blend("#3a260c", 0.38, scroll)     # the sheet's torn edge, 8px wide

    text_pairs = [
        # -- SHEET ----------------------------------------------------------
        ("body --ink on --scroll",             p["ink"],       scroll,        4.5),
        (".muted/.subtitle --ink-dim on --scroll", p["ink-dim"], scroll,      4.5),
        ("caption --ink-dim on --scroll",      p["ink-dim"],   scroll,        4.5),
        # h3 is 18px regular, which is NOT large text, so the heading colour is
        # held to 4.5 rather than the 3.0 h1 and h2 could have claimed.
        ("h1/h2/h3 --scroll-h on --scroll",    p["scroll-h"],  scroll,        4.5),
        ("link --link-ink on --scroll",        p["link-ink"],  scroll,        4.5),
        ("link hover --link-ink-hov on --scroll", p["link-ink-hov"], scroll,  4.5),
        ("code --code-ink on --scroll",        p["code-ink"],  scroll,        4.5),
        # -- SHEET, table on top of it --------------------------------------
        ("td --ink on parchment",              p["ink"],       parch,         4.5),
        ("td --ink on even row",               p["ink"],       even,          4.5),
        ("td.good --good-ink on parchment",    p["good-ink"],  parch,         4.5),
        ("td.good --good-ink on even row",     p["good-ink"],  even,          4.5),
        ("td.bad --bad-ink on parchment",      p["bad-ink"],   parch,         4.5),
        ("td.bad --bad-ink on even row",       p["bad-ink"],   even,          4.5),
        ("td link --link-ink on parchment",    p["link-ink"],  parch,         4.5),
        ("td link --link-ink on even row",     p["link-ink"],  even,          4.5),
        ("td link --link-ink on hover row",    p["link-ink"],  hover,         4.5),
        ("td link hover --link-ink-hov on hover row", p["link-ink-hov"], hover, 4.5),
        ("thead th --gold on --wood-mid",      p["gold"],      p["wood-mid"], 4.5),
        ("skip link --ink on --parch-0",       p["ink"],       p["parch-0"],  4.5),
        ("nav tab current --ink on --parch-0", p["ink"],       p["parch-0"],  4.5),
        # -- FURNITURE ------------------------------------------------------
        ("panel caption --text on --void",     p["text"],      p["void"],     4.5),
        ("facts dt --text-dim on --void",      p["text-dim"],  p["void"],     4.5),
        ("facts dd --parch-0 on --void",       p["parch-0"],   p["void"],     4.5),
        ("facts dd.good --good on --void",     p["good"],      p["void"],     4.5),
        ("facts dd.bad --bad on --void",       p["bad"],       p["void"],     4.5),
        ("notes li --text-dim on --void",      p["text-dim"],  p["void"],     4.5),
        ("status bar --text-dim on --void",    p["text-dim"],  p["void"],     4.5),
        ("panel link --link on --void",        p["link"],      p["void"],     4.5),
        ("panel visited --link-vis on --void", p["link-vis"],  p["void"],     4.5),
        ("panel code --amber on --void",       p["amber"],     p["void"],     4.5),
        ("field label --gold-dim on --void",   p["gold-dim"],  p["void"],     4.5),
        ("field hint --text-dim on --void",    p["text-dim"],  p["void"],     4.5),
        ("field input --text on --void",       p["text"],      p["void"],     4.5),
        ("pre --parch-1 on --void",            p["parch-1"],   p["void"],     4.5),
        ("chart ylab --text-dim on --void",    p["text-dim"],  p["void"],     4.5),
        ("chart legend --parch-1 on --void",   p["parch-1"],   p["void"],     4.5),
        # -- STONE ----------------------------------------------------------
        ("brand --gold on --stone-lit (large)", p["gold"],     stone,         3.0),
        ("brand small --text-dim on --stone-lit", p["text-dim"], stone,       4.5),
        ("toggle labels --parch-1 on --stone-lit", p["parch-1"], stone,       4.5),
        ("search field --text on --void",      p["text"],      p["void"],     4.5),
        ("search placeholder on --void",       "#7d745f",      p["void"],     4.5),
        ("nav tab --link on --void",           p["link"],      p["void"],     4.5),
        ("nav tab hover --link-hov on #150f07", p["link-hov"], "#150f07",     4.5),
        # The button fill is a gradient under two darkening cross-hatches, so
        # the flat --btn-hi end is the lightest pixel a label ever sits on.
        ("button --text on --btn-hi",          p["text"],      p["btn-hi"],   4.5),
        ("button --text on --btn-lo",          p["text"],      p["btn-lo"],   4.5),
        ("button hover --text on --btn-hov",   p["text"],      p["btn-hov"],  4.5),
        ("footer --text-dim on --stone-foot",  p["text-dim"],  p["stone-foot"], 4.5),
        ("footer link --link on --stone-foot", p["link"],      p["stone-foot"], 4.5),
        ("footer visited --link-vis on --stone-foot", p["link-vis"], p["stone-foot"], 4.5),
        ("footer code --amber on --stone-foot", p["amber"],    p["stone-foot"], 4.5),
    ]
    ui_pairs = [
        ("input border vs black fill",         p["wood-pale"], p["void"],     3.0),
        ("search border vs --stone-lit",       p["wood-pale"], stone,         3.0),
        ("tab border vs --stone-lit",          p["wood-pale"], stone,         3.0),
        ("button border vs --stone-lit",       p["wood-pale"], stone,         3.0),
        ("button border vs --void panel",      p["wood-pale"], p["void"],     3.0),
        ("checkbox accent --gold on --stone-lit", p["gold"],   stone,         3.0),
        ("focus ring --gold on --stone-lit",   p["gold"],      stone,         3.0),
        ("focus ring --gold on --void panel",  p["gold"],      p["void"],     3.0),
        ("focus ring --gold on --stone-foot",  p["gold"],      p["stone-foot"], 3.0),
        ("focus ring --gold on thead --wood-mid", p["gold"],   p["wood-mid"], 3.0),
        # main flips the ring to ink, because gold on the sheet is 1.2.
        ("focus ring --ink on --scroll",       p["ink"],       scroll,        3.0),
        ("focus ring --ink on parchment",      p["ink"],       parch,         3.0),
        ("focus ring --ink on even row",       p["ink"],       even,          3.0),
        ("chart sell #ffbb22 on --void",       "#ffbb22",      p["void"],     3.0),
        ("chart buy #78adff on --void",        "#78adff",      p["void"],     3.0),
    ]
    notes = [
        f"gridline vs --void is {cr(grid, p['void']):.2f} — decorative, "
        "the ylab text carries the numbers",
        f"the sheet's torn edge composites to {edge} (--ink {cr(p['ink'], edge):.2f}, "
        f"--scroll-h {cr(p['scroll-h'], edge):.2f}) and is the one gradient in this "
        "skin that darkens a surface carrying dark text. It is 8px wide against "
        "main's 16px padding, 10px at the narrow breakpoint, so no glyph is ever "
        "drawn on it. Widening it means owing this table two more rows",
        f"the olive rule under an h2 is {cr(p['olive'], scroll):.2f} on the sheet — "
        "decorative, and the heading beside it carries the section name",
        f"--parch-0 on --scroll is {cr(parch, scroll):.2f}: a table is meant to read "
        "as a lighter sheet laid on the roll, and its 2px --wood frame at "
        f"{cr(p['wood'], scroll):.2f} is what actually delimits it",
    ]
    return text_pairs, ui_pairs, notes


# ---------------------------------------------------------------------------
# Windows 7 — Aero. Palette spans openget-7.css and the vendored framework.
# ---------------------------------------------------------------------------

def seven():
    p = palette("openget-7.css")
    even, hover = "#f6f6f6", "#e6f2fb"
    head_lo = "#f0f0f0"                       # thead gradient, darker end
    btn_lo, btn_hi = "#cfcfcf", "#f2f2f2"     # framework button gradient ends
    btn_text = "#222222"                      # framework button colour
    heading = "#0b3c68"
    glass_text = p["og-glass-ink"]
    # The masthead lays a four-stop gradient over the glass, and the framework lays another over the panel title bars. Text has to clear the DARKEST stop of either, not the flat swatch underneath.
    glass_dark = blend("#000000", 0.12, p["og-glass"])

    text_pairs = [
        ("body --og-text on --og-surface",     p["og-text"],   p["og-surface"], 4.5),
        (".muted --og-dim on --og-surface",    p["og-dim"],    p["og-surface"], 4.5),
        ("h1 heading on --og-surface (large)", heading,        p["og-surface"], 3.0),
        ("h3 heading on --og-surface",         heading,        p["og-surface"], 4.5),
        ("code #8a3a00 on --og-surface",       "#8a3a00",      p["og-surface"], 4.5),
        ("link --w7-link-c on --og-surface",   p["w7-link-c"], p["og-surface"], 4.5),
        ("link --w7-link-c on --og-white",     p["w7-link-c"], p["og-white"],   4.5),
        ("link hover on --og-surface",         p["w7-link-c-h"], p["og-surface"], 4.5),
        ("link hover on --og-white",           p["w7-link-c-h"], p["og-white"], 4.5),
        ("visited #6a3ca0 on --og-surface",    "#6a3ca0",      p["og-surface"], 4.5),
        ("pre --og-text on --og-white",        p["og-text"],   p["og-white"],   4.5),
        ("nav tab #17364f on #e8e8e8",         "#17364f",      "#e8e8e8",       4.5),
        ("nav current on #68b3db",             glass_text,     "#68b3db",       4.5),
        ("nav hover on #a7d9f5",               glass_text,     "#a7d9f5",       4.5),
        ("brand on --og-glass",                glass_text,     p["og-glass"],   4.5),
        ("brand on glass, darkest gradient stop", glass_text,  glass_dark,      4.5),
        ("toggle labels on glass",             glass_text,     glass_dark,      4.5),
        ("search placeholder on --og-white",   "#6b6b6b",      p["og-white"],   4.5),
        ("thead th #23527c on gradient",       "#23527c",      head_lo,         4.5),
        ("caption --og-dim on --og-surface",   p["og-dim"],    p["og-surface"], 4.5),
        ("td --og-text on --og-white",         p["og-text"],   p["og-white"],   4.5),
        ("td --og-text on even row",           p["og-text"],   even,            4.5),
        ("td --og-text on hover row",          p["og-text"],   hover,           4.5),
        ("td.good --og-good on --og-white",    p["og-good"],   p["og-white"],   4.5),
        ("td.good --og-good on even row",      p["og-good"],   even,            4.5),
        ("td.good --og-good on hover row",     p["og-good"],   hover,           4.5),
        ("td.bad --og-bad on --og-white",      p["og-bad"],    p["og-white"],   4.5),
        ("td.bad --og-bad on even row",        p["og-bad"],    even,            4.5),
        ("td.bad --og-bad on hover row",       p["og-bad"],    hover,           4.5),
        ("td link on --og-white",              p["w7-link-c"], p["og-white"],   4.5),
        ("td link on even row",                p["w7-link-c"], even,            4.5),
        ("td link on hover row",               p["w7-link-c"], hover,           4.5),
        ("title bar text on --og-glass",       glass_text,     p["og-glass"],   4.5),
        ("facts dt --og-dim on --og-surface",  p["og-dim"],    p["og-surface"], 4.5),
        ("facts dd --og-text on --og-surface", p["og-text"],   p["og-surface"], 4.5),
        ("facts dd.good on --og-surface",      p["og-good"],   p["og-surface"], 4.5),
        ("facts dd.bad on --og-surface",       p["og-bad"],    p["og-surface"], 4.5),
        ("field label #23527c on --og-white",  "#23527c",      p["og-white"],   4.5),
        ("button #222 on gradient bottom",     btn_text,       btn_lo,          4.5),
        ("button #222 on gradient top",        btn_text,       btn_hi,          4.5),
        ("notes li --og-dim on --og-surface",  p["og-dim"],    p["og-surface"], 4.5),
        ("status bar --og-dim on --og-surface", p["og-dim"],   p["og-surface"], 4.5),
        ("chart ylab --og-dim on --og-white",  p["og-dim"],    p["og-white"],   4.5),
        ("chart legend --og-text on --og-white", p["og-text"], p["og-white"],   4.5),
        ("skip link --og-text on --og-white",  p["og-text"],   p["og-white"],   4.5),
        ("footer --og-dim on #e4e4e4",         p["og-dim"],    "#e4e4e4",       4.5),
        ("footer link on #e4e4e4",             p["w7-link-c"], "#e4e4e4",       4.5),
    ]
    ui_pairs = [
        # The whole reason --w7-el-bd is redefined in openget-7.css: upstream's
        # #8e8f8f is 2.85:1 here.
        ("control border --w7-el-bd vs surface", p["w7-el-bd"], p["og-surface"], 3.0),
        ("control border --w7-el-bd vs white",   p["w7-el-bd"], p["og-white"],   3.0),
        ("focus ring #003f80 on --og-surface",   "#003f80",     p["og-surface"], 3.0),
        ("focus ring #003f80 on --og-white",     "#003f80",     p["og-white"],   3.0),
        ("focus ring #003f80 on even row",       "#003f80",     even,            3.0),
        ("chart sell #a34a00 on --og-white",     "#a34a00",     p["og-white"],   3.0),
        ("chart buy #12507e on --og-white",      "#12507e",     p["og-white"],   3.0),
        # The masthead checkbox sits on the glass, not on a white form.
        ("checked box --og-accent on glass",     p["og-accent"], p["og-glass"],  3.0),
        ("checked box --og-accent on glass dark", p["og-accent"], glass_dark,    3.0),
        ("checked box --og-accent on --og-white", p["og-accent"], p["og-white"], 3.0),
    ]
    notes = ["table gridline #ececec on white is decorative; the row text carries the data"]
    return text_pairs, ui_pairs, notes


THEMES = [
    ("Old School RuneScape (openget-osrs.css)", osrs),
    ("Windows 7 (openget-7.css + vendor-7.css)", seven),
]


VARIANTS = [
    (None, "as shipped"),
    ("prefers-color-scheme: light", "reader prefers a light UI"),
    ("prefers-contrast: more", "reader asked for more contrast"),
]


def main():
    global VARIANT
    fails = []
    total = 0
    for VARIANT, why in VARIANTS:
        for name, build in THEMES:
            text_pairs, ui_pairs, notes = build()
            head = name if VARIANT is None else f"{name}  @media ({VARIANT})"
            print(f"\n{'=' * 72}\n{head}\n{why}\n{'=' * 72}")
            for title, pairs in (("text (1.4.3)", text_pairs),
                                 ("non-text (1.4.11)", ui_pairs)):
                print(f"\n--- {title} ---")
                for label, fg, bg, need in pairs:
                    r = cr(fg, bg)
                    ok = r >= need
                    total += 1
                    if not ok:
                        fails.append((head, label, r, need))
                    print(f"{'PASS' if ok else 'FAIL':4} {r:6.2f} (need {need})  {label}")
            if VARIANT is None:
                for n in notes:
                    print(f"\n({n})")

    print()
    if fails:
        print(f"{len(fails)} FAILURES out of {total} pairs")
        for name, label, r, need in fails:
            print(f"  {r:5.2f} < {need}  [{name.split(' (')[0]}] {label}")
        return 1
    print(f"All {total} pairs pass WCAG 2.2 AA: {len(THEMES)} themes "
          f"x {len(VARIANTS)} preference variants.")
    return 0


if __name__ == "__main__":
    sys.exit(main())

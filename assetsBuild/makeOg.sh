#!/bin/sh
# Renders the OpenGraph card for /professional/ as a 1200x630 PNG.
# Pure ImageMagick + Pango, no design tooling. Re-run after editing the text.
# Output: rootdomain/professional/ogimage.png
#
# The filename must stay ogimage.png (og:image points at it). Do not "tidy" it
# -- scrapers cache og:image URLs hard. See siteAssets.txt, OPENGRAPH.
set -eu

# Resolved from this script's own location, not hardcoded, so renaming the repo
# directory cannot silently point this at a stale path.
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

OUT="${1:-$ROOT/rootdomain/professional/ogimage.png}"
FONT="Noto Sans Mono"          # one of the few monos with U+2042 ASTERISM
BG="#000000"
FRAME="#ffffff"
PROMPT="#ffffff"
CMD="#ffffff"
NAME="#ffffff"
DIM="#ffffff"
BODY="#ffffff"
URL="#ffffff"

# Pango markup. size="…%" is relative to -pointsize below.
MARKUP=$(cat <<'PANGO'
<span foreground="@PROMPT@">robin@dreamstation:~$</span> <span foreground="@CMD@">finger robin@localhost</span>

<span foreground="@NAME@" size="205%" weight="bold">Robin Reel</span>
<span foreground="@DIM@">security-minded systems and infrastructure generalist</span>

<span foreground="@PROMPT@" size="118%">⁂</span> <span foreground="@BODY@">pool.ntp.org member, score 20/20</span>
<span foreground="@PROMPT@" size="118%">⁂</span> <span foreground="@BODY@">CVE pending · bug bounty awarded</span>
<span foreground="@PROMPT@" size="118%">⁂</span> <span foreground="@BODY@">open source contributor and developer</span>

<span foreground="@URL@">dreamstation.systems/professional</span>
PANGO
)

for v in PROMPT CMD NAME DIM BODY URL; do
  eval "val=\$$v"
  MARKUP=$(printf '%s' "$MARKUP" | sed "s|@$v@|$val|g")
done

# Render the text block on transparency, then centre it on the card.
magick -background none -fill white -font "$FONT" -pointsize 22 \
       -define pango:wrap=none pango:"$MARKUP" /tmp/og-text.png

magick -size 1200x630 "xc:$BG" \
       -stroke "$FRAME" -strokewidth 2 -fill none \
       -draw 'rectangle 20,20 1179,609' \
       /tmp/og-text.png -gravity center -geometry +0+0 -composite \
       -colorspace Gray -depth 8 -strip "$OUT"

echo "wrote $OUT"

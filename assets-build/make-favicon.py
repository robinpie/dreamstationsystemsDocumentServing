#!/usr/bin/env python3
"""Build favicon.ico (32px + 16px) and apple-touch-icon.png (180px) from the
same geometry as favicon.svg, drawn from primitives here (ImageMagick's SVG
renderer ignores stroke-width through <use>) rather than rasterised from the
SVG -- if you change the geometry in favicon.svg, change it here too.

Neither output format can be theme-aware like the SVG: the ICO uses a mid
grey legible on both light and dark chrome, and the apple-touch-icon is drawn
dark-on-white as an opaque tile (iOS composites transparency onto black).
Do not add rounded corners -- iOS applies its own mask.
"""
import subprocess, sys, os, tempfile

OUT = sys.argv[1] if len(sys.argv) > 1 else \
    "/home/robin/configNotes/http/rootdomain/favicon.ico"
TOUCH_OUT = os.path.join(os.path.dirname(OUT), "apple-touch-icon.png")
COLOR = "#666666"
TOUCH_FG, TOUCH_BG, TOUCH_PX = "#111111", "#ffffff", 180

S = 512 / 32.0                                  # SVG user units -> 512px render
STARS = [(16, 8.6), (8.2, 22.4), (23.8, 22.4)]  # asterism: one up, two down
ARMS = [((0, -5), (0, 5)),
        ((-4.35, -2.5), (4.35, 2.5)),
        ((-4.35, 2.5), (4.35, -2.5))]
STROKE = 3

draw = ["stroke-linecap round"]
for cx, cy in STARS:
    for (x1, y1), (x2, y2) in ARMS:
        draw.append("line %.2f,%.2f %.2f,%.2f"
                    % ((cx + x1) * S, (cy + y1) * S,
                       (cx + x2) * S, (cy + y2) * S))

tmp = tempfile.mkdtemp()
big, p32, p16 = (os.path.join(tmp, n) for n in ("big.png", "32.png", "16.png"))

subprocess.run(["magick", "-size", "512x512", "xc:none", "-stroke", COLOR,
                "-strokewidth", str(STROKE * S), "-fill", "none",
                "-draw", " ".join(draw), big], check=True)
for path, size in ((p32, 32), (p16, 16)):
    subprocess.run(["magick", big, "-resize", "%dx%d" % (size, size), path],
                   check=True)
subprocess.run(["magick", p32, p16, OUT], check=True)
print("wrote", OUT)

# Apple touch icon: same geometry, redrawn (not recoloured from big.png, which
# would leave grey fringing) opaque and dark-on-white. INNER leaves ~8% margin
# so the art doesn't look cramped edge-to-edge on the home screen.
INNER = int(TOUCH_PX * 0.84)
touch_big = os.path.join(tmp, "touch.png")
subprocess.run(["magick", "-size", "512x512", "xc:" + TOUCH_BG,
                "-stroke", TOUCH_FG, "-strokewidth", str(STROKE * S),
                "-fill", "none", "-draw", " ".join(draw), touch_big], check=True)
subprocess.run(["magick", touch_big,
                "-resize", "%dx%d" % (INNER, INNER),
                "-background", TOUCH_BG, "-gravity", "center",
                "-extent", "%dx%d" % (TOUCH_PX, TOUCH_PX),
                "-alpha", "off", TOUCH_OUT], check=True)
print("wrote", TOUCH_OUT)

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

"""Generate the OSRS skin's two drawn textures as SVG: a seamless cobblestone
wall tile (periodic Voronoi) and a repeat-y stone pillar with a vine.
Original drawings, not traced from any Jagex asset.

Deterministic (fixed seed), so a rerun reproduces the shipped files byte
for byte. Writes osrs-stone.svg and osrs-pillar.svg into
internal/web/static, or into the directory given as the first argument:

    python3 contrib/gen_osrs_textures.py

See openget.txt (LOOK AND FEEL)."""
import math, random, sys

out = sys.argv[1] if len(sys.argv) > 1 else str(__import__("pathlib").Path(__file__).resolve().parent.parent / "internal/web/static")
random.seed(20261024)

# ------------------------------------------------------------------ stone
W = H = 360
N = 25
pts = []
# jittered grid so cells stay roughly even (cobbles, not shards)
g = 5
for i in range(g):
    for j in range(g):
        if len(pts) >= N:
            break
        pts.append(((i + random.uniform(0.15, 0.85)) * W / g,
                    (j + random.uniform(0.15, 0.85)) * H / g))
allp = [(x + dx * W, y + dy * H) for (x, y) in pts for dx in (-1, 0, 1) for dy in (-1, 0, 1)]


def clip(poly, a, b):
    # keep the half-plane closer to a than b
    mx, my = (a[0] + b[0]) / 2, (a[1] + b[1]) / 2
    nx, ny = b[0] - a[0], b[1] - a[1]
    f = lambda p: (p[0] - mx) * nx + (p[1] - my) * ny
    res = []
    for i in range(len(poly)):
        p, q = poly[i], poly[(i + 1) % len(poly)]
        fp, fq = f(p), f(q)
        if fp <= 0:
            res.append(p)
        if (fp < 0) != (fq < 0) and fp != fq:
            t = fp / (fp - fq)
            res.append((p[0] + t * (q[0] - p[0]), p[1] + t * (q[1] - p[1])))
    return res


def rounded(poly, r=0.32):
    # a closed path with each corner replaced by a quadratic curve: cobbles, not crystals
    n = len(poly)
    d = ""
    for i in range(n):
        p0, p1, p2 = poly[i - 1], poly[i], poly[(i + 1) % n]
        a = (p1[0] + (p0[0] - p1[0]) * r, p1[1] + (p0[1] - p1[1]) * r)
        b = (p1[0] + (p2[0] - p1[0]) * r, p1[1] + (p2[1] - p1[1]) * r)
        d += ("M" if i == 0 else "L") + "%.1f %.1f" % a + "Q%.1f %.1f %.1f %.1f" % (p1[0], p1[1], b[0], b[1])
    return d + "Z"


cells = []
for (x, y) in pts:
    for dx in (-1, 0, 1):
        for dy in (-1, 0, 1):
            c = (x + dx * W, y + dy * H)
            poly = [(c[0] - 200, c[1] - 200), (c[0] + 200, c[1] - 200), (c[0] + 200, c[1] + 200), (c[0] - 200, c[1] + 200)]
            for o in allp:
                if o != c and abs(o[0] - c[0]) < 200 and abs(o[1] - c[1]) < 200:
                    poly = clip(poly, c, o)
            # only keep copies that touch the tile
            xs, ys = [p[0] for p in poly], [p[1] for p in poly]
            if max(xs) < 0 or min(xs) > W or max(ys) < 0 or min(ys) > H:
                continue
            # shrink toward centre to open the mortar gap
            cx, cy = sum(xs) / len(xs), sum(ys) / len(ys)
            poly = [(cx + (p[0] - cx) * 0.93, cy + (p[1] - cy) * 0.93) for p in poly]
            cells.append((pts.index((x, y)), poly, (cx, cy)))

shades = ["#1f1a11", "#221c12", "#251f14", "#1d1810", "#262015", "#201b12"]
s = ['<svg xmlns="http://www.w3.org/2000/svg" width="%d" height="%d" viewBox="0 0 %d %d">' % (W, H, W, H)]
s.append('<defs><radialGradient id="l" cx="38%" cy="32%" r="75%">'
         '<stop offset="0" stop-color="#433825" stop-opacity=".5"/>'
         '<stop offset=".6" stop-color="#4a3f2a" stop-opacity="0"/>'
         '<stop offset="1" stop-color="#000" stop-opacity=".45"/></radialGradient></defs>')
s.append('<rect width="%d" height="%d" fill="#0d0b07"/>' % (W, H))
for idx, poly, c in cells:
    d = rounded(poly)
    s.append('<path d="%s" fill="%s"/>' % (d, shades[idx % len(shades)]))
    s.append('<path d="%s" fill="url(#l)"/>' % d)
s.append('</svg>')
open(out + "/osrs-stone.svg", "w").write("".join(s))

# ----------------------------------------------------------------- pillar
PW, PH = 46, 120
p = ['<svg xmlns="http://www.w3.org/2000/svg" width="%d" height="%d" viewBox="0 0 %d %d">' % (PW, PH, PW, PH)]
p.append('<defs>'
         '<linearGradient id="b" x1="0" x2="1"><stop offset="0" stop-color="#2e2618"/>'
         '<stop offset=".3" stop-color="#5e4e35"/><stop offset=".5" stop-color="#76623f"/>'
         '<stop offset=".75" stop-color="#4a3d29"/><stop offset="1" stop-color="#231c12"/></linearGradient>'
         '<linearGradient id="v" x1="0" x2="0" y1="0" y2="1"><stop offset="0" stop-color="#000" stop-opacity=".55"/>'
         '<stop offset=".25" stop-color="#000" stop-opacity="0"/><stop offset=".75" stop-color="#000" stop-opacity="0"/>'
         '<stop offset="1" stop-color="#000" stop-opacity=".6"/></linearGradient>'
         '</defs>')
p.append('<rect width="%d" height="%d" fill="#0c0a06"/>' % (PW, PH))
# two barrel-shaped drums per tile and a thin collar between them
for y0 in (0, 60):
    p.append('<rect x="5" y="%d" width="36" height="52" rx="12" ry="9" fill="url(#b)"/>' % (y0 + 4))
    p.append('<rect x="5" y="%d" width="36" height="52" rx="12" ry="9" fill="url(#v)"/>' % (y0 + 4))
for yc in (-3, 57, 117):
    p.append('<rect x="10" y="%d" width="26" height="6" fill="#3a3021"/>' % yc)
# vine: a sine that completes whole periods over the tile height, so it tiles
vine = "M23 0" + "".join(
    "L%.1f %.1f" % (23 + 13 * math.sin(2 * math.pi * y / PH), y) for y in range(2, PH + 1, 2))
p.append('<path d="%s" fill="none" stroke="#1c3a0c" stroke-width="4" stroke-linecap="round"/>' % vine)
p.append('<path d="%s" fill="none" stroke="#5f9a2a" stroke-width="2" stroke-linecap="round"/>' % vine)
# leaves
for (y, side) in ((12, 1), (34, -1), (52, 1), (76, -1), (95, 1), (110, -1)):
    x = 23 + 13 * math.sin(2 * math.pi * y / PH)
    rot = 35 * side
    p.append('<ellipse cx="%.1f" cy="%.1f" rx="5" ry="2.6" transform="rotate(%d %.1f %.1f)" '
             'fill="#4f8a22" stroke="#173009" stroke-width=".8"/>' % (x + 5 * side, y, rot, x + 5 * side, y))
p.append('</svg>')
open(out + "/osrs-pillar.svg", "w").write("".join(p))
print("ok")

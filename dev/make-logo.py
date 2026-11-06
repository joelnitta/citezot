# Regenerates man/figures/logo.svg (text converted to outlines, using Menlo
# Bold on macOS). The PNG is a headless-Chrome screenshot of the SVG at 3x.
# Usage: python3 -I dev/make-logo.py man/figures/logo.svg
import sys
from fontTools.ttLib import TTCollection
from fontTools.pens.svgPathPen import SVGPathPen
from fontTools.pens.transformPen import TransformPen

font = TTCollection("/System/Library/Fonts/Menlo.ttc").fonts[1]
gs, cmap, upm = font.getGlyphSet(), font.getBestCmap(), font["head"].unitsPerEm

def outline(text, size, cx, baseline):
    adv = [font["hmtx"][cmap[ord(c)]][0] for c in text]
    x = cx - sum(adv) * size / upm / 2
    parts = []
    for c, a in zip(text, adv):
        pen = SVGPathPen(gs, lambda v: f"{v:.2f}".rstrip("0").rstrip("."))
        s = size / upm
        gs[cmap[ord(c)]].draw(TransformPen(pen, (s, 0, 0, -s, x, baseline)))
        parts.append(pen.getCommands())
        x += a * s
    return " ".join(parts)

# Regular pointy-top hexagon: half-width hw, so side = hw / cos(30 deg).
# 10 units of padding round the stroke (6 wide) so nothing is clipped.
from math import sqrt
def hexagon(cx, cy, hw):
    r = hw * 2 / sqrt(3)
    pts = [(cx, cy - r), (cx + hw, cy - r / 2), (cx + hw, cy + r / 2),
           (cx, cy + r), (cx - hw, cy + r / 2), (cx - hw, cy - r / 2)]
    return " ".join(f"{x:.2f},{y:.2f}" for x, y in pts)

hw = 87
r = hw * 2 / sqrt(3)
W, H = 200, round(2 * r + 26)
cy = H / 2
hexpts = hexagon(100, cy, hw)
inner = hexagon(100, cy, hw - 10)
dy = cy - 115.5  # text was laid out for a canvas centered at y = 115.5
svg = f'''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {W} {H}" width="{W}" height="{H}">
  <title>citezot hex sticker</title>
  <polygon points="{hexpts}" fill="#B3202C" stroke="#7A1119" stroke-width="6" stroke-linejoin="round"/>
  <polygon points="{inner}" fill="none" stroke="#fff" stroke-opacity=".35" stroke-width="1.5" stroke-linejoin="round"/>
  <path fill="#fff" d="{outline("[@]", 58, 100, 123 + dy)}"/>
  <path fill="#fff" d="{outline("citezot", 24, 100, 163 + dy)}"/>
</svg>
'''
open(sys.argv[1], "w").write(svg)

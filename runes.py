"""Golem Runes: Golem's own letters, like broken stone, readable as English.

Every letter is a few heavy blocks on a 4 x 6 grid, as if cut from a stone slab thousands of years old:
square and heavy, with chipped corners, a crack or two, and small pits worn into the face.
The damage is different for each letter but the same every time. Small letters are the same as capitals.
How it's made: each letter is drawn as a picture, damaged, then traced into straight-edged outlines
(potrace) and put into a font. Run:  python3 runes.py OUT.ttf   (the build does this; nothing is downloaded)
"""
import math, os, random, subprocess, sys, tempfile
from fontTools.fontBuilder import FontBuilder
from fontTools.pens.ttGlyphPen import TTGlyphPen
from fontTools.pens.transformPen import TransformPen
from fontTools.pens.cu2quPen import Cu2QuPen
from fontTools.svgLib import SVGPath
from PIL import Image, ImageDraw

# Each glyph: a list of cuts; each cut is a list of (x, y) points on the grid (x 0..4, y 0..6).
G = {
    "A": [[(0, 0), (2, 6), (4, 0)], [(0.9, 2), (3.1, 3)]],
    "B": [[(0, 0), (0, 6), (3.4, 4.6), (0, 3.1), (4, 1.5), (0, 0)]],
    "C": [[(3.8, 5.2), (2.6, 6), (0, 3), (2.6, 0), (3.8, 0.8)]],
    "D": [[(0, 0), (0, 6), (4, 3), (0, 0)]],
    "E": [[(4, 6), (0, 6), (0, 0), (4, 0)], [(0, 3), (3, 3.7)]],
    "F": [[(4, 6), (0, 6), (0, 0)], [(0, 3), (3, 3.7)]],
    "G": [[(3.8, 5.2), (2.6, 6), (0, 3), (2.6, 0), (3.8, 0.8), (3.8, 2.6), (2, 2.6)]],
    "H": [[(0, 0), (0, 6)], [(4, 0), (4, 6)], [(0, 3.6), (4, 2.4)]],
    "I": [[(2, 0), (2, 6)], [(1, 6), (3, 6)], [(1, 0), (3, 0)]],
    "J": [[(4, 6), (4, 1.2), (2, 0), (0, 1.4)]],
    "K": [[(0, 0), (0, 6)], [(3.8, 6), (0, 3), (3.8, 0)]],
    "L": [[(0, 6), (0, 0), (3.6, 1)]],
    "M": [[(0, 0), (0, 6), (2, 2.8), (4, 6), (4, 0)]],
    "N": [[(0, 0), (0, 6), (4, 0), (4, 6)]],
    "O": [[(2, 6), (4, 3), (2, 0), (0, 3), (2, 6)]],
    "P": [[(0, 0), (0, 6), (4, 4.5), (0, 3)]],
    "Q": [[(2, 6), (4, 3), (2, 0), (0, 3), (2, 6)], [(2.4, 1.4), (4, -0.6)]],
    "R": [[(0, 0), (0, 6), (4, 4.5), (0, 3), (4, 0)]],
    "S": [[(4, 6), (0, 4.2), (4, 1.8), (0, 0)]],
    "T": [[(0, 5), (2, 6), (4, 5)], [(2, 6), (2, 0)]],
    "U": [[(0, 6), (0, 1), (2, 0), (4, 1), (4, 6)]],
    "V": [[(0, 6), (2, 0), (4, 6)]],
    "W": [[(0, 6), (1, 0), (2, 4), (3, 0), (4, 6)]],
    "X": [[(0, 0), (4, 6)], [(0, 6), (4, 0)]],
    "Y": [[(0, 6), (2, 3), (4, 6)], [(2, 3), (2, 0)]],
    "Z": [[(0, 6), (4, 6), (0, 0), (4, 0)]],
    "0": [[(2, 6), (3.6, 3), (2, 0), (0.4, 3), (2, 6)], [(1, 1.5), (3, 4.5)]],
    "1": [[(0.8, 4.4), (2, 6), (2, 0)]],
    "2": [[(0, 4.8), (2, 6), (4, 4.4), (0, 0), (4, 0)]],
    "3": [[(0, 6), (4, 4.6), (1.2, 3), (4, 1.4), (0, 0)]],
    "4": [[(3, 0), (3, 6), (0, 2), (4, 2)]],
    "5": [[(4, 6), (0, 6), (0, 3.6), (4, 2), (0, 0)]],
    "6": [[(3.6, 6), (0, 2), (2, 0), (4, 1.8), (0.6, 3.4)]],
    "7": [[(0, 6), (4, 6), (1.2, 0)]],
    "8": [[(2, 6), (4, 4.5), (0, 1.5), (2, 0), (4, 1.5), (0, 4.5), (2, 6)]],
    "9": [[(0.4, 0), (4, 4), (2, 6), (0, 4.6), (3.4, 2.6)]],
    ".": [[(1.6, 0.2), (2, 0.7), (2.4, 0.2)]],
    ",": [[(2.2, 0.8), (1.4, -1)]],
    ":": [[(1.6, 0.2), (2, 0.7), (2.4, 0.2)], [(1.6, 3.4), (2, 3.9), (2.4, 3.4)]],
    ";": [[(1.6, 3.4), (2, 3.9), (2.4, 3.4)], [(2.2, 0.8), (1.4, -1)]],
    "-": [[(0.6, 2.8), (3.4, 3.2)]],
    "_": [[(0, -0.6), (4, -0.6)]],
    "+": [[(0.4, 3), (3.6, 3)], [(2, 1.4), (2, 4.6)]],
    "=": [[(0.4, 2.2), (3.6, 2.2)], [(0.4, 3.8), (3.6, 3.8)]],
    "/": [[(0.4, -0.4), (3.6, 6.4)]],
    "\\": [[(0.4, 6.4), (3.6, -0.4)]],
    "|": [[(2, -0.6), (2, 6.6)]],
    "(": [[(2.8, 6.6), (1.2, 3), (2.8, -0.6)]],
    ")": [[(1.2, 6.6), (2.8, 3), (1.2, -0.6)]],
    "[": [[(3, 6.6), (1.4, 6.6), (1.4, -0.6), (3, -0.6)]],
    "]": [[(1, 6.6), (2.6, 6.6), (2.6, -0.6), (1, -0.6)]],
    "<": [[(3.4, 5), (0.6, 3), (3.4, 1)]],
    ">": [[(0.6, 5), (3.4, 3), (0.6, 1)]],
    "!": [[(2, 6), (2, 2)], [(1.6, 0.2), (2, 0.7), (2.4, 0.2)]],
    "?": [[(0.2, 4.8), (2, 6), (3.8, 4.6), (2, 2.4), (2, 1.6)], [(1.6, 0.2), (2, 0.7), (2.4, 0.2)]],
    "'": [[(2, 6.2), (1.7, 4.6)]],
    '"': [[(1.4, 6.2), (1.1, 4.6)], [(2.8, 6.2), (2.5, 4.6)]],
    "*": [[(2, 5.4), (2, 2.6)], [(0.8, 4.7), (3.2, 3.3)], [(0.8, 3.3), (3.2, 4.7)]],
    "%": [[(0.4, 0), (3.6, 6)], [(0.4, 5.6), (1, 4.8), (0.4, 4)], [(3.6, 2), (3, 1.2), (3.6, 0.4)]],
    "#": [[(1.2, 0), (1.8, 6)], [(2.4, 0), (3, 6)], [(0.2, 2), (3.8, 2)], [(0.2, 4), (3.8, 4)]],
    "&": [[(4, 0), (0.6, 4.6), (2, 6), (3, 4.6), (0, 1.4), (1.4, 0), (4, 2.6)]],
    "@": [[(4, 1), (2, 0), (0, 3), (2, 6), (4, 3), (2.8, 1.6), (1.4, 3), (2.6, 4.2), (3.2, 2)]],
    "~": [[(0.2, 2.6), (1.4, 3.6), (2.6, 2.4), (3.8, 3.4)]],
    "^": [[(0.8, 4), (2, 6), (3.2, 4)]],
    "$": [[(3.6, 5), (0.4, 3.8), (3.6, 2.2), (0.4, 1)], [(2, 6.4), (2, -0.4)]],
}

UNIT = 116           # one grid step, in font units (cap height 6 steps = 696)
SIDE = 70            # space on each side of a letter
ADV = 4 * UNIT + 2 * SIDE
PX = 30              # one grid step in the drawing
THICK = 40           # how heavy a stroke of stone is, in the drawing
PAD = 60             # room around the letter in the drawing


def block(d, a, b):
    """One heavy stroke from a to b, square at both ends (ends reach past the points so corners are solid)."""
    (x0, y0), (x1, y1) = a, b
    L = math.hypot(x1 - x0, y1 - y0) or 1
    dx, dy = (x1 - x0) / L, (y1 - y0) / L
    h = THICK / 2
    px, py = -dy * h, dx * h
    x0, y0, x1, y1 = x0 - dx * h, y0 - dy * h, x1 + dx * h, y1 + dy * h
    corners = [(x0 + px, y0 + py), (x1 + px, y1 + py), (x1 - px, y1 - py), (x0 - px, y0 - py)]
    d.polygon(corners, fill=0)
    return corners, (dx, dy)


def damage(d, blocks, rng, w, h):
    """Chipped corners, a crack, and a few pits: age."""
    # chips: a few outside corners lose a wedge of stone
    for corners, (dx, dy) in rng.sample(blocks, min(len(blocks), 3)):
        cx, cy = corners[rng.randrange(4)]
        a, b = rng.uniform(8, 17), rng.uniform(8, 17)
        ang = rng.uniform(0, math.tau)
        d.polygon([(cx + math.cos(ang) * 30, cy + math.sin(ang) * 30),
                   (cx + math.cos(ang + 2.2) * a, cy + math.sin(ang + 2.2) * a),
                   (cx + math.cos(ang - 2.2) * b, cy + math.sin(ang - 2.2) * b)], fill=255)
    # a crack: from one edge of a stroke, zigzagging part way across it
    corners, (dx, dy) = rng.choice(blocks)
    (ax, ay), (bx, by) = corners[0], corners[1]
    t = rng.uniform(0.25, 0.75)
    x, y = ax + (bx - ax) * t, ay + (by - ay) * t
    nx, ny = dy, -dx                                       # into the stroke
    pts = [(x - nx * 4, y - ny * 4)]
    for _ in range(3):
        x += nx * THICK * 0.22 + dx * rng.uniform(-6, 6)
        y += ny * THICK * 0.22 + dy * rng.uniform(-6, 6)
        pts.append((x, y))
    d.line(pts, fill=255, width=3)
    # pits worn into the face
    for corners, _ in rng.sample(blocks, min(len(blocks), 2)):
        cx = sum(c[0] for c in corners) / 4 + rng.uniform(-8, 8)
        cy = sum(c[1] for c in corners) / 4 + rng.uniform(-8, 8)
        r = rng.uniform(2.5, 4.5)
        d.polygon([(cx + r * math.cos(k * 1.3 + rng.random()), cy + r * math.sin(k * 1.3 + rng.random())) for k in range(5)], fill=255)


def glyph(cuts, seed, tmp):
    """The glyph, and how wide it is."""
    rng = random.Random(seed)
    left = min(x for line in cuts for x, _ in line)
    right = max(x for line in cuts for x, _ in line)
    top, bottom = max(y for line in cuts for _, y in line), min(y for line in cuts for _, y in line)
    w = int((right - left) * PX + 2 * PAD)
    h = int((max(top, 6) - min(bottom, 0)) * PX + 2 * PAD)
    base = PAD + max(top, 6) * PX                          # where y = 0 is in the drawing
    im = Image.new("L", (w, h), 255)
    d = ImageDraw.Draw(im)
    blocks = []
    for line in cuts:
        pts = [(PAD + (x - left) * PX, base - y * PX) for x, y in line]
        for i in range(len(pts) - 1):
            blocks.append(block(d, pts[i], pts[i + 1]))
    damage(d, blocks, rng, w, h)
    pbm, svg = os.path.join(tmp, "g.pbm"), os.path.join(tmp, "g.svg")
    im.point(lambda v: 255 if v > 127 else 0).convert("1").save(pbm)
    subprocess.run(["potrace", "-s", "--alphamax", "0", "--opttolerance", "0.3", "--turdsize", "6", "-o", svg, pbm], check=True)
    k = UNIT / PX
    pen = TTGlyphPen(None)
    # potrace writes tenths of a pixel with y going up from the bottom of the drawing; to font units (baseline at 0)
    SVGPath(svg).draw(TransformPen(Cu2QuPen(pen, 1.0), (0.1 * k, 0, 0, 0.1 * k, SIDE - PAD * k, (base - h) * k)))
    return pen.glyph(), round((max(right - left, 1.2)) * UNIT + 2 * SIDE + THICK * k * 0.6)


def build(out):
    names = {ch: ("space" if ch == " " else "g%04X" % ord(ch)) for ch in G}
    order = [".notdef", "space"] + [names[c] for c in G]
    fb = FontBuilder(1000, isTTF=True)
    fb.setupGlyphOrder(order)
    cmap = {32: "space", 0xA0: "space"}
    for ch, n in names.items():
        cmap[ord(ch)] = n
        if ch.isalpha():
            cmap[ord(ch.lower())] = n          # small letters are the same stones
    fb.setupCharacterMap(cmap)
    glyphs = {".notdef": TTGlyphPen(None).glyph(), "space": TTGlyphPen(None).glyph()}
    widths = {".notdef": ADV, "space": round(ADV * 0.7)}
    with tempfile.TemporaryDirectory() as tmp:
        for ch, n in names.items():
            glyphs[n], widths[n] = glyph(G[ch], ord(ch), tmp)
    fb.setupGlyf(glyphs)
    fb.setupHorizontalMetrics({n: (widths[n], 0) for n in order})
    fb.setupHorizontalHeader(ascent=900, descent=-220)
    fb.setupNameTable({"familyName": "Golem Runes", "styleName": "Regular"})
    fb.setupOS2(sTypoAscender=900, sTypoDescender=-220, usWinAscent=960, usWinDescent=260, sCapHeight=6 * UNIT, sxHeight=6 * UNIT)
    fb.setupPost()
    fb.save(out)


if __name__ == "__main__":
    build(sys.argv[1] if len(sys.argv) > 1 else "GolemRunes.ttf")

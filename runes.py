"""Golem Runes: Golem's own carved letters, readable as English.

Every letter is a few straight cuts on a 4 x 6 grid, like letters cut into stone with a knife:
no curves, pointed ends where the blade went in and out. Small letters are the same as capitals.
Run:  python3 runes.py OUT.ttf   (the build does this; nothing is downloaded)
"""
import math, sys
from fontTools.fontBuilder import FontBuilder
from fontTools.pens.ttGlyphPen import TTGlyphPen

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
CUT = 80             # how wide a cut is
SIDE = 90            # space on each side of a letter
ADV = 4 * UNIT + 2 * SIDE


def P(x, y, left=0):
    return (SIDE + (x - left) * UNIT, y * UNIT)


def ring(points):
    """Clockwise, as TrueType wants the outside of a shape."""
    a = sum(x0 * y1 - x1 * y0 for (x0, y0), (x1, y1) in zip(points, points[1:] + points[:1]))
    return points[::-1] if a > 0 else points


def cut(pen, a, b, start_tip, end_tip):
    """One straight cut from a to b: pointed where the blade enters or leaves, square inside a letter."""
    (x0, y0), (x1, y1) = a, b
    L = math.hypot(x1 - x0, y1 - y0) or 1
    dx, dy = (x1 - x0) / L, (y1 - y0) / L
    nx, ny = -dy * CUT / 2, dx * CUT / 2
    e = CUT / 2
    pts = []
    if start_tip:
        pts += [(x0 - dx * e * 0.2, y0 - dy * e * 0.2)]
        sx, sy = x0 + dx * e * 0.9, y0 + dy * e * 0.9
    else:
        sx, sy = x0 - dx * e * 0.5, y0 - dy * e * 0.5
    pts += [(sx + nx, sy + ny)]
    if end_tip:
        ex, ey = x1 - dx * e * 0.9, y1 - dy * e * 0.9
        pts += [(ex + nx, ey + ny), (x1 + dx * e * 0.2, y1 + dy * e * 0.2), (ex - nx, ey - ny)]
    else:
        ex, ey = x1 + dx * e * 0.5, y1 + dy * e * 0.5
        pts += [(ex + nx, ey + ny), (ex - nx, ey - ny)]
    pts += [(sx - nx, sy - ny)]
    draw(pen, pts)


def knot(pen, p):
    """Where two cuts meet: a small diamond so the corner is solid."""
    x, y = p
    r = CUT * 0.55
    draw(pen, [(x, y + r), (x + r, y), (x, y - r), (x - r, y)])


def draw(pen, pts):
    pts = ring([(round(x), round(y)) for x, y in pts])
    pen.moveTo(pts[0])
    for q in pts[1:]:
        pen.lineTo(q)
    pen.closePath()


def glyph(cuts):
    """The glyph, and how wide it is (narrow letters like I take less room)."""
    left = min(x for line in cuts for x, _ in line)
    right = max(x for line in cuts for x, _ in line)
    pen = TTGlyphPen(None)
    for line in cuts:
        pts = [P(x, y, left) for x, y in line]
        closed = pts[0] == pts[-1]
        for i in range(len(pts) - 1):
            cut(pen, pts[i], pts[i + 1], i == 0 and not closed, i == len(pts) - 2 and not closed)
        for q in (pts if closed else pts[1:-1]):
            knot(pen, q)
    return pen.glyph(), round((max(right - left, 1.2)) * UNIT + 2 * SIDE)


def build(out):
    names = {ch: ("space" if ch == " " else "g%04X" % ord(ch)) for ch in G}
    order = [".notdef", "space"] + [names[c] for c in G]
    fb = FontBuilder(1000, isTTF=True)
    fb.setupGlyphOrder(order)
    cmap = {32: "space", 0xA0: "space"}
    for ch, n in names.items():
        cmap[ord(ch)] = n
        if ch.isalpha():
            cmap[ord(ch.lower())] = n          # small letters are the same runes
    fb.setupCharacterMap(cmap)
    glyphs = {".notdef": TTGlyphPen(None).glyph(), "space": TTGlyphPen(None).glyph()}
    widths = {".notdef": ADV, "space": round(ADV * 0.7)}
    for ch, n in names.items():
        glyphs[n], widths[n] = glyph(G[ch])
    fb.setupGlyf(glyphs)
    fb.setupHorizontalMetrics({n: (widths[n], 0) for n in order})
    fb.setupHorizontalHeader(ascent=860, descent=-200)
    fb.setupNameTable({"familyName": "Golem Runes", "styleName": "Regular"})
    fb.setupOS2(sTypoAscender=860, sTypoDescender=-200, usWinAscent=900, usWinDescent=240, sCapHeight=6 * UNIT, sxHeight=6 * UNIT)
    fb.setupPost()
    fb.save(out)


if __name__ == "__main__":
    build(sys.argv[1] if len(sys.argv) > 1 else "GolemRunes.ttf")

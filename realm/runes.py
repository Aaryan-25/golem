# Part of Golem: the shadow realm and the desktop; MAP.md section 5.5.
"""Golem Runes: Golem's letters. Cambria's shapes (through Caladea, its free twin), cut as ancient stone.

Each letter of Caladea Bold (a free font made to match Microsoft's Cambria letter for letter; Apache 2.0,
(c) 2012 The Caladea Project Authors) is drawn large, then aged like a stone carving: corners chipped off,
a crack running in from an edge, small pits worn into the face. Then it is traced back into outlines made
only of straight cuts (potrace), so every curve becomes chiselled facets. The damage is different for each
letter but the same every time. Nothing is downloaded: the build gives the Caladea file.
Run:  python3 runes.py Caladea-Bold.ttf OUT.ttf
"""
import math, os, random, subprocess, sys, tempfile
import numpy as np
from fontTools.fontBuilder import FontBuilder
from fontTools.pens.ttGlyphPen import TTGlyphPen
from fontTools.pens.transformPen import TransformPen
from fontTools.pens.cu2quPen import Cu2QuPen
from fontTools.svgLib import SVGPath
from fontTools.ttLib import TTFont
from PIL import Image, ImageDraw, ImageFont

SIZE = 170            # pixels per em while carving (small, so the traced curves become broad chisel cuts)
F = SIZE / 360        # damage scales with it
PAD = 30
CHARS = [chr(c) for c in range(33, 127)] + list("©°±×÷–—‘’“”…·•")


def edges(ink):
    inner = ink.copy()
    inner[1:, :] &= ink[:-1, :]
    inner[:-1, :] &= ink[1:, :]
    inner[:, 1:] &= ink[:, :-1]
    inner[:, :-1] &= ink[:, 1:]
    return ink & ~inner


def shrink(ink, n):
    for _ in range(n):
        ink = ink & ~edges(ink)
    return ink


def age(im, rng):
    """Chips, a crack, pits."""
    ink = np.asarray(im) < 128
    if ink.sum() < 50 * F * F:
        return im
    d = ImageDraw.Draw(im)
    ey, ex = np.nonzero(edges(ink))
    cy, cx = np.nonzero(ink)
    my, mx = cy.mean(), cx.mean()
    big = ink.sum() > 2500 * F * F
    for _ in range(rng.randint(3, 5) if big else 2):             # chips off the edges
        i = rng.randrange(len(ex))
        x, y = ex[i], ey[i]
        r = rng.uniform(9, 20) * F
        a = rng.uniform(0, math.tau)
        d.polygon([(x + r * math.cos(a + k * 2.1 + rng.uniform(-0.4, 0.4)), y + r * math.sin(a + k * 2.1 + rng.uniform(-0.4, 0.4)))
                   for k in range(3)], fill=255)
    if big:                                                      # a crack, from an edge inwards
        i = rng.randrange(len(ex))
        x, y = float(ex[i]), float(ey[i])
        vx, vy = mx - x, my - y
        L = math.hypot(vx, vy) or 1
        vx, vy = vx / L, vy / L
        pts = [(x, y)]
        for _ in range(4):
            x += vx * 11 * F + rng.uniform(-6, 6) * F
            y += vy * 11 * F + rng.uniform(-6, 6) * F
            pts.append((x, y))
        d.line(pts, fill=255, width=max(2, round(4 * F)))
        deep = shrink(ink, max(2, round(9 * F)))                                    # pits, well inside the strokes
        py, px = np.nonzero(deep)
        for _ in range(min(3, len(px))):
            i = rng.randrange(len(px))
            r = rng.uniform(3.5, 6.5) * F + 0.6
            d.polygon([(px[i] + r * math.cos(k * 1.26 + rng.random()), py[i] + r * math.sin(k * 1.26 + rng.random()))
                       for k in range(5)], fill=255)
    return im


def carve(src_font, ch, rng, tmp, upm):
    asc = int(SIZE * 1.1)
    w = int(SIZE * 1.6) + 2 * PAD
    h = asc + int(SIZE * 0.45) + 2 * PAD
    base = PAD + asc
    im = Image.new("L", (w, h), 255)
    ImageDraw.Draw(im).text((PAD, base), ch, font=src_font, fill=0, anchor="ls")
    im = age(im, rng)
    pbm, svg = os.path.join(tmp, "g.pbm"), os.path.join(tmp, "g.svg")
    im.point(lambda v: 255 if v > 127 else 0).convert("1").save(pbm)
    subprocess.run(["potrace", "-s", "--alphamax", "0", "--opttolerance", "0.5", "--turdsize", "3", "-o", svg, pbm], check=True)
    k = upm / SIZE
    pen = TTGlyphPen(None)
    # potrace: tenths of a pixel, y up from the bottom of the drawing  ->  font units, baseline at 0
    SVGPath(svg).draw(TransformPen(Cu2QuPen(pen, 1.0), (0.1 * k, 0, 0, 0.1 * k, -PAD * k, (base - h) * k)))
    return pen.glyph()


def build(src, out):
    t = TTFont(src)
    upm = t["head"].unitsPerEm
    cmap = t.getBestCmap()
    hmtx = t["hmtx"]
    font = ImageFont.truetype(src, SIZE)
    order, glyphs, widths, cm = [".notdef", "space"], {}, {}, {32: "space", 0xA0: "space"}
    glyphs[".notdef"] = TTGlyphPen(None).glyph()
    glyphs["space"] = TTGlyphPen(None).glyph()
    widths[".notdef"] = (upm // 2, 0)
    widths["space"] = hmtx[cmap[32]] if 32 in cmap else (upm // 4, 0)
    with tempfile.TemporaryDirectory() as tmp:
        for ch in CHARS:
            if ord(ch) not in cmap:
                continue
            n = "g%04X" % ord(ch)
            glyphs[n] = carve(font, ch, random.Random(ord(ch) * 7919), tmp, upm)
            widths[n] = (hmtx[cmap[ord(ch)]][0], 0)
            order.append(n)
            cm[ord(ch)] = n
    fb = FontBuilder(upm, isTTF=True)
    fb.setupGlyphOrder(order)
    fb.setupCharacterMap(cm)
    fb.setupGlyf(glyphs)
    fb.setupHorizontalMetrics(widths)
    hh = t["hhea"]
    fb.setupHorizontalHeader(ascent=hh.ascent, descent=hh.descent)
    fb.setupNameTable({"familyName": "Golem Runes", "styleName": "Regular",
                       "copyright": "Golem Runes: Caladea Bold (c) 2012 The Caladea Project Authors, Apache License 2.0, carved as stone by Golem"})
    os2 = t["OS/2"]
    fb.setupOS2(sTypoAscender=os2.sTypoAscender, sTypoDescender=os2.sTypoDescender, sTypoLineGap=os2.sTypoLineGap,
                usWinAscent=os2.usWinAscent, usWinDescent=os2.usWinDescent, sCapHeight=getattr(os2, "sCapHeight", upm * 2 // 3),
                sxHeight=getattr(os2, "sxHeight", upm // 2))
    fb.setupPost()
    fb.save(out)


if __name__ == "__main__":
    build(sys.argv[1], sys.argv[2])

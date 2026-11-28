#!/usr/bin/env python3
"""Draw the skill icons (stdlib only, original art) and bake them for the client.

Every element skill (A and B of each element x role), the four weapons, the weapon skills
and dodge get a round glossy icon: an element-coloured disc with a light rim and a cream
motif with a dark outline. Shapes are rasterised at 4x and box-filtered down, so edges are
smooth. Output:

  src/shared/SkillIconData/<Group>.luau   base64 RGBA, 64 x 64 per icon
  art/skill_icons/sheet.png               contact sheet for review

Run: python3 -I scripts/make_skill_icons.py
"""
import base64
import math
import os
import struct
import zlib

N = 64          # output size
SS = 4          # supersampling
H = N * SS      # working size
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

PAL = {  # base, dark, light
    'Fire': ((255, 112, 88), (120, 28, 20), (255, 206, 130)),
    'Water': ((80, 160, 255), (18, 50, 128), (186, 228, 255)),
    'Wind': ((70, 200, 140), (16, 90, 56), (200, 248, 200)),
    'Light': ((255, 196, 56), (150, 96, 16), (255, 248, 210)),
    'Dark': ((150, 104, 230), (34, 16, 66), (206, 172, 250)),
    'Gear': ((255, 150, 110), (110, 50, 34), (255, 224, 190)),
    'Move': ((110, 190, 255), (24, 70, 140), (210, 238, 255)),
}
CREAM = (255, 251, 238)


# ------------------------------------------------------------------------------------------
# canvas

class Canvas:
    def __init__(self):
        self.px = [[0.0, 0.0, 0.0, 0.0] for _ in range(H * H)]

    def blend(self, i, c, a):
        p = self.px[i]
        if a <= 0:
            return
        na = a + p[3] * (1 - a)
        if na <= 0:
            return
        for k in range(3):
            p[k] = (c[k] * a + p[k] * p[3] * (1 - a)) / na
        p[3] = na

    def paint(self, mask, color, alpha=1.0):
        """mask: bytearray H*H; color: rgb or fn(x, y) -> rgb (unit coords)."""
        for i in range(H * H):
            if mask[i]:
                if callable(color):
                    c = color((i % H + 0.5) / H, (i // H + 0.5) / H)
                else:
                    c = color
                self.blend(i, c, alpha)

    def out(self):
        res = bytearray(N * N * 4)
        for y in range(N):
            for x in range(N):
                r = g = b = a = 0.0
                for dy in range(SS):
                    row = (y * SS + dy) * H + x * SS
                    for dx in range(SS):
                        p = self.px[row + dx]
                        r += p[0] * p[3]
                        g += p[1] * p[3]
                        b += p[2] * p[3]
                        a += p[3]
                o = (y * N + x) * 4
                if a > 0:
                    res[o] = int(min(255, r / a))
                    res[o + 1] = int(min(255, g / a))
                    res[o + 2] = int(min(255, b / a))
                res[o + 3] = int(min(255, a / (SS * SS) * 255))
        return bytes(res)


def mask_of(inside, box=(0, 0, 1, 1)):
    m = bytearray(H * H)
    x0, y0 = max(0, int(box[0] * H) - 1), max(0, int(box[1] * H) - 1)
    x1, y1 = min(H, int(box[2] * H) + 2), min(H, int(box[3] * H) + 2)
    for py in range(y0, y1):
        y = (py + 0.5) / H
        for px in range(x0, x1):
            if inside((px + 0.5) / H, y):
                m[py * H + px] = 1
    return m


def dilate(m, k):
    for _ in range(k):
        n = bytearray(m)
        for i in range(H * H):
            if not m[i]:
                x, y = i % H, i // H
                if (x > 0 and m[i - 1]) or (x < H - 1 and m[i + 1]) or (y > 0 and m[i - H]) or (y < H - 1 and m[i + H]):
                    n[i] = 1
        m = n
    return m


def union(*ms):
    out = bytearray(H * H)
    for m in ms:
        for i in range(H * H):
            if m[i]:
                out[i] = 1
    return out


def minus(a, b):
    return bytearray(1 if a[i] and not b[i] else 0 for i in range(H * H))


# ------------------------------------------------------------------------------------------
# shape tests (unit coordinates, y down)

def circle(cx, cy, r):
    return lambda x, y: (x - cx) ** 2 + (y - cy) ** 2 <= r * r


def ellipse(cx, cy, rx, ry, rot=0.0):
    c, s = math.cos(rot), math.sin(rot)
    def f(x, y):
        dx, dy = x - cx, y - cy
        u, v = dx * c + dy * s, -dx * s + dy * c
        return (u / rx) ** 2 + (v / ry) ** 2 <= 1
    return f


def ring(cx, cy, r0, r1):
    return lambda x, y: r0 * r0 <= (x - cx) ** 2 + (y - cy) ** 2 <= r1 * r1


def poly(pts):
    n = len(pts)
    def f(x, y):
        inside = False
        j = n - 1
        for i in range(n):
            xi, yi = pts[i]
            xj, yj = pts[j]
            if (yi > y) != (yj > y) and x < (xj - xi) * (y - yi) / (yj - yi + 1e-12) + xi:
                inside = not inside
            j = i
        return inside
    return f


def capsule(x0, y0, x1, y1, w):
    def f(x, y):
        dx, dy = x1 - x0, y1 - y0
        L = dx * dx + dy * dy
        t = 0 if L == 0 else max(0, min(1, ((x - x0) * dx + (y - y0) * dy) / L))
        px, py = x0 + t * dx, y0 + t * dy
        return (x - px) ** 2 + (y - py) ** 2 <= (w / 2) ** 2
    return f


def arc(cx, cy, r, w, a0, a1):
    """Thick arc from angle a0 to a1 (radians, 0 = right, clockwise because y is down)."""
    def f(x, y):
        d = math.hypot(x - cx, y - cy)
        if abs(d - r) > w / 2:
            return False
        a = math.atan2(y - cy, x - cx)
        lo, hi = min(a0, a1), max(a0, a1)
        for k in (-2, 0, 2):
            if lo <= a + k * math.pi <= hi:
                return True
        return False
    return f


def any_of(*fs):
    return lambda x, y: any(f(x, y) for f in fs)


def tr(pts, cx, cy, s, rot=0.0):
    c, sn = math.cos(rot), math.sin(rot)
    return [(cx + (px * c - py * sn) * s, cy + (px * sn + py * c) * s) for px, py in pts]


def star_pts(n, r0, r1, rot=-math.pi / 2):
    pts = []
    for i in range(n * 2):
        r = r1 if i % 2 == 0 else r0
        a = rot + i * math.pi / n
        pts.append((math.cos(a) * r, math.sin(a) * r))
    return pts


FLAME = [(0, -1), (0.22, -0.62), (0.5, -0.32), (0.66, 0.08), (0.6, 0.45), (0.36, 0.74), (0, 0.84),
         (-0.36, 0.74), (-0.6, 0.45), (-0.64, 0.06), (-0.5, -0.22), (-0.36, 0.0), (-0.3, -0.42)]
SHIELD = [(-0.72, -0.8), (0, -0.95), (0.72, -0.8), (0.72, -0.05), (0.5, 0.45), (0, 0.92), (-0.5, 0.45), (-0.72, -0.05)]
DROP = [(0, -0.95), (0.3, -0.45), (0.55, -0.05), (0.62, 0.3), (0.5, 0.62), (0.25, 0.82), (0, 0.88),
        (-0.25, 0.82), (-0.5, 0.62), (-0.62, 0.3), (-0.55, -0.05), (-0.3, -0.45)]
ARROW = [(0, -1), (0.75, -0.15), (0.3, -0.15), (0.3, 0.9), (-0.3, 0.9), (-0.3, -0.15), (-0.75, -0.15)]
WING = [(0, 0), (0.25, -0.5), (0.6, -0.8), (1.0, -0.85), (0.92, -0.55), (1.0, -0.42), (0.86, -0.22),
        (0.92, -0.05), (0.74, 0.08), (0.76, 0.26), (0.5, 0.3), (0.22, 0.3)]


# ------------------------------------------------------------------------------------------
# icon drawing

class Icon:
    def __init__(self, group):
        self.c = Canvas()
        base, dark, light = PAL[group]
        self.base, self.dark, self.light = base, dark, light
        # disc: radial gradient, light from the top left
        def grad(x, y):
            t = min(1, math.hypot(x - 0.38, y - 0.32) / 0.62)
            return tuple(int(light[k] * (1 - t) * 0.35 + base[k] * (1 - abs(t - 0.45)) * 0.75 + dark[k] * t * 0.7) for k in range(3))
        self.c.paint(mask_of(circle(0.5, 0.5, 0.47)), lambda x, y: tuple(min(255, v) for v in grad(x, y)))
        self.c.paint(mask_of(ring(0.5, 0.5, 0.43, 0.48)), lambda x, y: mix(light, base, (y - 0.02) / 0.96))
        self.c.paint(mask_of(ring(0.5, 0.5, 0.47, 0.49)), dark, 0.9)

    def shape(self, inside, fill=None, outline=3, box=(0.04, 0.04, 0.96, 0.96)):
        m = mask_of(inside, box)
        if outline:
            self.c.paint(dilate(m, outline * SS // 2 + 1), self.dark, 0.95)
        self.c.paint(m, fill or self.cream_grad())
        return m

    def cream_grad(self):
        light = self.light
        return lambda x, y: mix(CREAM, light, max(0, min(1, (y - 0.2) / 0.7)) * 0.7)

    def accent(self):
        base, light = self.base, self.light
        return lambda x, y: mix(light, base, max(0, min(1, (y - 0.25) / 0.6)))

    def gloss(self):
        self.c.paint(mask_of(ellipse(0.42, 0.2, 0.26, 0.1, -0.35)), (255, 255, 255), 0.22)

    def done(self):
        self.gloss()
        return self.c.out()


def mix(a, b, t):
    t = max(0.0, min(1.0, t))
    return tuple(int(a[k] + (b[k] - a[k]) * t) for k in range(3))


# motifs: each takes an Icon and draws on it
def m_flame(ic, cx=0.5, cy=0.52, s=0.3, inner=True):
    ic.shape(poly(tr(FLAME, cx, cy, s)))
    if inner:
        ic.shape(poly(tr(FLAME, cx, cy + s * 0.32, s * 0.5)), ic.accent(), outline=0)


def m_shield(ic, cx=0.5, cy=0.52, s=0.3):
    ic.shape(poly(tr(SHIELD, cx, cy, s)))


def m_plus(ic, cx, cy, s, fill=None):
    ic.shape(any_of(capsule(cx - s, cy, cx + s, cy, s * 0.7), capsule(cx, cy - s, cx, cy + s, s * 0.7)), fill or ((120, 240, 150)), outline=2)


def m_star(ic, cx, cy, n, r0, r1, fill=None, outline=3, rot=-math.pi / 2):
    ic.shape(poly(tr(star_pts(n, r0, r1, rot), cx, cy, 1)), fill, outline)


def m_crescent(ic, cx, cy, r, off, rot, fill=None, outline=3):
    ox, oy = math.cos(rot) * off, math.sin(rot) * off
    big, small = circle(cx, cy, r), circle(cx + ox, cy + oy, r * 0.92)
    ic.shape(lambda x, y: big(x, y) and not small(x, y), fill, outline)


def m_wings(ic, cy=0.5, s=0.36):
    ic.shape(any_of(poly(tr(WING, 0.5 + 0.03, cy, s)), poly([(1 - x, y) for x, y in tr(WING, 0.5 + 0.03, cy, s)])))


def m_wave(ic, cx=0.5, cy=0.56, s=0.34):
    band = []
    for i in range(21):
        t = i / 20
        x = -1 + 2 * t
        band.append((x, 0.1 + 0.18 * math.sin(t * math.pi * 3)))
    band += [(1, 0.75), (-1, 0.75)]
    curl_outer = circle(cx + s * 0.05, cy - s * 0.35, s * 0.62)
    curl_inner = circle(cx + s * 0.32, cy - s * 0.3, s * 0.4)
    ic.shape(any_of(poly(tr(band, cx, cy, s)), lambda x, y: curl_outer(x, y) and not curl_inner(x, y) and y > cy - s * 0.95))


def m_cloud(ic, cx=0.5, cy=0.42, s=0.3):
    ic.shape(any_of(circle(cx - s * 0.45, cy + s * 0.1, s * 0.38), circle(cx, cy - s * 0.12, s * 0.5), circle(cx + s * 0.5, cy + s * 0.12, s * 0.36),
                    capsule(cx - s * 0.6, cy + s * 0.3, cx + s * 0.6, cy + s * 0.3, s * 0.42)))


def m_tornado(ic):
    fs = []
    for i, (w, y) in enumerate(((0.3, 0.28), (0.24, 0.4), (0.18, 0.52), (0.12, 0.63), (0.07, 0.73))):
        fs.append(ellipse(0.5 + (i - 2) * 0.02, y, w, 0.055))
    ic.shape(any_of(*fs))
    for i, (w, y) in enumerate(((0.22, 0.28), (0.16, 0.4), (0.11, 0.52))):
        ic.shape(arc(0.5 + (i - 2) * 0.02, y + 0.06, w, 0.025, math.pi * 1.15, math.pi * 1.85), ic.accent(), outline=0)


def m_leaf(ic, cx=0.5, cy=0.5, s=0.32, rot=-0.7):
    a, b = ellipse(cx, cy, s, s * 0.48, rot), None
    ic.shape(a, (190, 250, 190))
    ic.shape(capsule(cx - math.cos(rot) * s * 0.85, cy - math.sin(rot) * s * 0.85, cx + math.cos(rot) * s * 0.7, cy + math.sin(rot) * s * 0.7, 0.025), ic.dark, outline=0)


def m_speed(ic, cx=0.5, cy=0.5):
    for dy, l in ((-0.16, 0.36), (0, 0.46), (0.16, 0.32)):
        ic.shape(capsule(cx - l / 2 - 0.06, cy + dy, cx + l / 2 - 0.06, cy + dy, 0.075))
    chev = [(0.0, -0.5), (0.45, 0), (0.0, 0.5), (-0.12, 0.38), (0.22, 0), (-0.12, -0.38)]
    ic.shape(poly(tr(chev, cx + 0.2, cy, 0.4)), ic.accent())


def m_sun(ic, cx=0.5, cy=0.5, r=0.14, rays=8, rl=0.26):
    rs = []
    for i in range(rays):
        a = i * math.pi * 2 / rays
        tip = (cx + math.cos(a) * rl, cy + math.sin(a) * rl)
        l = (cx + math.cos(a - 0.22) * r * 1.1, cy + math.sin(a - 0.22) * r * 1.1)
        rr = (cx + math.cos(a + 0.22) * r * 1.1, cy + math.sin(a + 0.22) * r * 1.1)
        rs.append(poly([tip, l, rr]))
    ic.shape(any_of(circle(cx, cy, r), *rs))
    ic.shape(circle(cx, cy, r * 0.62), ic.accent(), outline=0)


def m_sword(ic, cx=0.5, cy=0.5, s=0.36, rot=math.pi / 4):
    blade = [(-0.12, -1), (0.0, -1.15), (0.12, -1), (0.12, 0.25), (-0.12, 0.25)]
    guard = [(-0.42, 0.25), (0.42, 0.25), (0.42, 0.4), (-0.42, 0.4)]
    grip = [(-0.08, 0.4), (0.08, 0.4), (0.08, 0.8), (-0.08, 0.8)]
    ic.shape(any_of(poly(tr(blade, cx, cy, s, rot)), poly(tr(guard, cx, cy, s, rot)), poly(tr(grip, cx, cy, s, rot)), circle(*tr([(0, 0.88)], cx, cy, s, rot)[0], s * 0.12)))


def m_eye(ic, cx=0.5, cy=0.5, s=0.3):
    up, dn = circle(cx, cy + s * 0.9, s * 1.25), circle(cx, cy - s * 0.9, s * 1.25)
    ic.shape(lambda x, y: up(x, y) and dn(x, y))
    ic.shape(circle(cx, cy, s * 0.36), ic.accent(), outline=2)
    ic.shape(ellipse(cx, cy, s * 0.1, s * 0.28), ic.dark, outline=0)


def m_claw(ic):
    for i, dx in enumerate((-0.14, 0.0, 0.14)):
        m_crescent(ic, 0.5 + dx + 0.12, 0.5 - 0.06 * (i == 1), 0.3, 0.07, math.pi * 0.85, outline=2)


def m_hex(ic):
    hexp = [(math.cos(i * math.pi / 3 - math.pi / 2) * 0.28 + 0.5, math.sin(i * math.pi / 3 - math.pi / 2) * 0.28 + 0.5) for i in range(6)]
    inner = [(math.cos(i * math.pi / 3 - math.pi / 2) * 0.21 + 0.5, math.sin(i * math.pi / 3 - math.pi / 2) * 0.21 + 0.5) for i in range(6)]
    o, n = poly(hexp), poly(inner)
    ic.shape(lambda x, y: o(x, y) and not n(x, y))
    tri = [hexp[0], hexp[2], hexp[4]]
    for i in range(3):
        a, b = tri[i], tri[(i + 1) % 3]
        ic.shape(capsule(a[0], a[1], b[0], b[1], 0.035), outline=1)
    ic.shape(circle(0.5, 0.5, 0.06), ic.accent(), outline=2)


def m_eclipse(ic):
    ic.shape(circle(0.5, 0.5, 0.25), (255, 236, 200))
    ic.c.paint(mask_of(circle(0.56, 0.47, 0.22)), (30, 14, 54))
    ic.shape(ring(0.5, 0.5, 0.29, 0.31), ic.accent(), outline=0)


def m_skull(ic):
    ic.shape(any_of(circle(0.5, 0.45, 0.22), poly([(0.36, 0.55), (0.64, 0.55), (0.6, 0.75), (0.4, 0.75)])))
    for ex in (0.42, 0.58):
        ic.c.paint(mask_of(ellipse(ex, 0.48, 0.055, 0.07)), ic.dark)
    ic.c.paint(mask_of(poly([(0.5, 0.56), (0.53, 0.62), (0.47, 0.62)])), ic.dark)
    for tx in (0.44, 0.5, 0.56):
        ic.c.paint(mask_of(capsule(tx, 0.66, tx, 0.73, 0.012)), ic.dark)


def m_moon(ic):
    m_crescent(ic, 0.46, 0.52, 0.26, 0.14, -0.6)
    m_star(ic, 0.7, 0.32, 4, 0.025, 0.08, outline=2)
    m_star(ic, 0.74, 0.6, 4, 0.02, 0.06, outline=2)


def m_bubbles(ic):
    for cx, cy, r in ((0.42, 0.56, 0.17), (0.64, 0.4, 0.12), (0.62, 0.66, 0.08)):
        ic.shape(ring(cx, cy, r * 0.78, r), outline=2)
        ic.c.paint(mask_of(circle(cx, cy, r * 0.78)), ic.light, 0.35)
        ic.c.paint(mask_of(ellipse(cx - r * 0.35, cy - r * 0.35, r * 0.22, r * 0.12, -0.7)), (255, 255, 255))


def m_comet(ic):
    tail = [(0.2, 0.86), (0.52, 0.38), (0.66, 0.5)]
    ic.shape(any_of(poly(tail), poly([(0.3, 0.8), (0.48, 0.34), (0.6, 0.42)])), ic.accent())
    ic.shape(circle(0.62, 0.4, 0.14))
    m_flame(ic, 0.62, 0.36, 0.12, inner=False)


def m_beam(ic):
    ic.shape(poly([(0.2, 0.78), (0.74, 0.24), (0.84, 0.34), (0.3, 0.88)]), ic.accent())
    ic.shape(poly([(0.26, 0.76), (0.76, 0.27), (0.8, 0.31), (0.3, 0.8)]), CREAM, outline=0)
    m_star(ic, 0.76, 0.3, 4, 0.04, 0.15)


def m_pillars(ic):
    for x in (0.34, 0.5, 0.66):
        ic.shape(poly([(x - 0.05, 0.42), (x + 0.05, 0.42), (x + 0.05, 0.74), (x - 0.05, 0.74)]), outline=2)
    ic.shape(poly([(0.24, 0.42), (0.5, 0.24), (0.76, 0.42)]), outline=2)
    ic.shape(poly([(0.22, 0.74), (0.78, 0.74), (0.78, 0.8), (0.22, 0.8)]), outline=2)


def m_up2(ic):
    ic.shape(poly(tr(ARROW, 0.4, 0.55, 0.2)))
    ic.shape(poly(tr(ARROW, 0.62, 0.45, 0.24)), ic.accent())


def m_hammer(ic, rot=math.pi / 4):
    head = [(-0.55, -0.95), (0.55, -0.95), (0.55, -0.45), (-0.55, -0.45)]
    grip = [(-0.1, -0.45), (0.1, -0.45), (0.1, 0.9), (-0.1, 0.9)]
    ic.shape(any_of(poly(tr(head, 0.5, 0.5, 0.34, rot)), poly(tr(grip, 0.5, 0.5, 0.34, rot))))


def m_staff(ic):
    ic.shape(capsule(0.3, 0.8, 0.62, 0.36, 0.06))
    ic.shape(circle(0.66, 0.32, 0.1), ic.accent())
    m_star(ic, 0.66, 0.32, 4, 0.03, 0.17, outline=2)


def m_bow(ic):
    ic.shape(arc(0.62, 0.5, 0.3, 0.06, math.pi * 0.62, math.pi * 1.38))
    ic.shape(capsule(0.48, 0.23, 0.48, 0.77, 0.018), outline=1)
    ic.shape(capsule(0.28, 0.5, 0.7, 0.5, 0.035), outline=2)
    ic.shape(poly([(0.78, 0.5), (0.68, 0.43), (0.68, 0.57)]), outline=2)


def m_swoosh(ic):
    ic.shape(arc(0.48, 0.58, 0.24, 0.09, math.pi * 0.95, math.pi * 1.85))
    ic.shape(poly([(0.8, 0.44), (0.62, 0.28), (0.6, 0.5)]))
    for dy in (0.14, 0.24):
        ic.shape(capsule(0.22, 0.62 + dy * 0.5, 0.4, 0.62 + dy * 0.5, 0.035), ic.accent(), outline=1)


def m_burst(ic, inner=None):
    m_star(ic, 0.5, 0.5, 8, 0.15, 0.33, ic.accent(), rot=-math.pi / 8)
    if inner:
        inner(ic)


# name -> (group, draw)
ICONS = {
    # Fire
    'Ember Guard': ('Fire', lambda ic: (m_shield(ic), m_flame(ic, 0.5, 0.5, 0.15))),
    'Magma Slam': ('Fire', lambda ic: m_burst(ic, lambda i: m_flame(i, 0.5, 0.52, 0.17))),
    'Kindle': ('Fire', lambda ic: (m_flame(ic, 0.45, 0.54, 0.28), ic.shape(poly(tr(ARROW, 0.7, 0.36, 0.13)), (130, 240, 150), 2))),
    'Phoenix Warmth': ('Fire', lambda ic: (m_wings(ic, 0.52, 0.34), m_flame(ic, 0.5, 0.5, 0.17))),
    'Flare Strike': ('Fire', m_comet),
    'Inferno': ('Fire', lambda ic: (m_flame(ic, 0.34, 0.58, 0.17, False), m_flame(ic, 0.66, 0.58, 0.17, False), m_flame(ic, 0.5, 0.5, 0.27))),
    # Water
    'Bubble Shell': ('Water', m_bubbles),
    'Riptide Wall': ('Water', lambda ic: (m_shield(ic), m_wave(ic, 0.5, 0.56, 0.16))),
    'Mend': ('Water', lambda ic: (ic.shape(poly(tr(DROP, 0.46, 0.5, 0.3))), m_plus(ic, 0.66, 0.66, 0.08))),
    'Healing Rain': ('Water', lambda ic: (m_cloud(ic), [ic.shape(poly(tr(DROP, x, y, 0.07)), ic.accent(), 2) for x, y in ((0.36, 0.7), (0.5, 0.76), (0.64, 0.7))])),
    'Tidal Lash': ('Water', lambda ic: (m_crescent(ic, 0.52, 0.52, 0.28, 0.1, math.pi * 0.8), m_crescent(ic, 0.6, 0.48, 0.18, 0.07, math.pi * 0.8, ic.accent(), 2))),
    'Tsunami': ('Water', m_wave),
    # Wind
    'Updraft': ('Wind', m_up2),
    'Storm Wall': ('Wind', lambda ic: (m_shield(ic), [ic.shape(capsule(0.38, y, 0.62, y, 0.04), ic.accent(), 1) for y in (0.42, 0.52, 0.62)])),
    'Tailwind': ('Wind', m_speed),
    'Zephyr Blessing': ('Wind', lambda ic: (m_leaf(ic), m_plus(ic, 0.68, 0.68, 0.08))),
    'Gale Flurry': ('Wind', lambda ic: [m_crescent(ic, 0.42 + i * 0.07, 0.42 + i * 0.07, 0.22, 0.06, math.pi * 0.75, None if i % 2 == 0 else ic.accent(), 2) for i in range(3)]),
    'Cyclone': ('Wind', m_tornado),
    # Light
    'Halo Guard': ('Light', lambda ic: (m_shield(ic, 0.5, 0.58, 0.25), ic.shape(ring(0.5, 0.24, 0.07, 0.1), ic.accent(), 2))),
    'Sanctuary': ('Light', m_pillars),
    'Dawn Heal': ('Light', lambda ic: (m_sun(ic, 0.46, 0.46, 0.12, 8, 0.24), m_plus(ic, 0.68, 0.68, 0.08))),
    'Revival Light': ('Light', lambda ic: (m_wings(ic, 0.54, 0.34), m_sun(ic, 0.5, 0.48, 0.1, 8, 0.18))),
    'Radiant Ray': ('Light', m_beam),
    'Judgement': ('Light', lambda ic: m_burst(ic, lambda i: m_sword(i, 0.5, 0.5, 0.3, 0))),
    # Dark
    'Shadow Bulwark': ('Dark', lambda ic: (m_shield(ic), m_eye(ic, 0.5, 0.5, 0.13))),
    'Abyss Grasp': ('Dark', m_claw),
    'Hex': ('Dark', m_hex),
    'Eclipse': ('Dark', m_eclipse),
    'Soul Drain': ('Dark', m_skull),
    'Nightfall': ('Dark', m_moon),
    # weapons and moves
    'Blade': ('Gear', lambda ic: m_sword(ic)),
    'Hammer': ('Gear', m_hammer),
    'Staff': ('Gear', m_staff),
    'Bow': ('Gear', m_bow),
    'Spin Slash': ('Gear', lambda ic: (ic.shape(arc(0.5, 0.5, 0.27, 0.06, -math.pi * 0.9, math.pi * 0.6), ic.accent()), m_sword(ic, 0.5, 0.5, 0.26))),
    'Healing Pulse': ('Gear', lambda ic: (ic.shape(ring(0.5, 0.5, 0.25, 0.3), ic.accent(), 2), m_plus(ic, 0.5, 0.5, 0.13))),
    'Ground Slam': ('Gear', lambda ic: m_burst(ic, lambda i: m_hammer(i, 0))),
    'Volley': ('Gear', lambda ic: [(ic.shape(capsule(x, 0.28, x, 0.66, 0.03), None, 2), ic.shape(poly([(x, 0.78), (x - 0.06, 0.64), (x + 0.06, 0.64)]), None, 2)) for x in (0.36, 0.5, 0.64)]),
    'Dodge': ('Move', m_swoosh),
}


def png(path, w, h, rgba):
    raw = b''.join(b'\x00' + rgba[y * w * 4:(y + 1) * w * 4] for y in range(h))
    def chunk(t, d):
        c = struct.pack('>I', len(d)) + t + d
        return c + struct.pack('>I', zlib.crc32(t + d) & 0xffffffff)
    data = b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', w, h, 8, 6, 0, 0, 0)) + chunk(b'IDAT', zlib.compress(raw, 9)) + chunk(b'IEND', b'')
    with open(path, 'wb') as f:
        f.write(data)


def main():
    out = {}
    for name, (group, draw) in ICONS.items():
        ic = Icon(group)
        draw(ic)
        out[name] = (group, ic.done())
        print('drew', name)
    # bake per group (Studio caps a script's source at ~200k chars)
    ddir = os.path.join(ROOT, 'src', 'shared', 'SkillIconData')
    os.makedirs(ddir, exist_ok=True)
    groups = {}
    for name, (group, px) in out.items():
        groups.setdefault(group, []).append((name, px))
    for group, items in groups.items():
        lines = ['-- Generated by scripts/make_skill_icons.py. Do not edit.', '-- RGBA8 skill icons, %d x %d, base64.' % (N, N), 'return {']
        for name, px in items:
            lines.append('\t["%s"] = "%s",' % (name, base64.b64encode(px).decode()))
        lines.append('}')
        with open(os.path.join(ddir, group + '.luau'), 'w') as f:
            f.write('\n'.join(lines) + '\n')
    # contact sheet on a grey background
    cols = 8
    names = list(out)
    rows = (len(names) + cols - 1) // cols
    W, Hh = cols * (N + 8), rows * (N + 8)
    sheet = bytearray([60, 62, 74, 255] * (W * Hh))
    for k, name in enumerate(names):
        px = out[name][1]
        ox, oy = (k % cols) * (N + 8) + 4, (k // cols) * (N + 8) + 4
        for y in range(N):
            for x in range(N):
                s = (y * N + x) * 4
                a = px[s + 3] / 255
                d = ((oy + y) * W + ox + x) * 4
                for c in range(3):
                    sheet[d + c] = int(px[s + c] * a + sheet[d + c] * (1 - a))
    os.makedirs(os.path.join(ROOT, 'art', 'skill_icons'), exist_ok=True)
    png(os.path.join(ROOT, 'art', 'skill_icons', 'sheet.png'), W, Hh, bytes(sheet))
    print('wrote', len(out), 'icons')


if __name__ == '__main__':
    main()

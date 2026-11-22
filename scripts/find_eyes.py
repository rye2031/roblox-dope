#!/usr/bin/env python3
"""Render a front orthographic view of a Meshy GLB (same transform as mesh_to_luau.py), find the
two eye whites, and print Luau eye data (normalized coords) plus a preview PNG.

Usage: python3 -I scripts/find_eyes.py <model.glb> <out_preview.png>
"""
import math
import os
import struct
import sys
import zlib

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import mesh_to_luau as M  # noqa: E402

RES = 256


def write_png(path, w, h, rgb):
    raw = b''.join(b'\x00' + bytes(rgb[y * w * 3:(y + 1) * w * 3]) for y in range(h))

    def chunk(t, d):
        c = struct.pack('>I', len(d)) + t + d
        return c + struct.pack('>I', zlib.crc32(t + d) & 0xffffffff)
    png = b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', w, h, 8, 2, 0, 0, 0))
    png += chunk(b'IDAT', zlib.compress(raw, 6)) + chunk(b'IEND', b'')
    open(path, 'wb').write(png)


def main():
    glb, out = sys.argv[1], sys.argv[2]
    js, binchunk = M.read_glb(glb)
    prim = js['meshes'][0]['primitives'][0]
    at = prim['attributes']
    pos = M.accessor(js, binchunk, at['POSITION'])
    uv = M.accessor(js, binchunk, at['TEXCOORD_0'])
    idx = M.accessor(js, binchunk, prim['indices'])
    m = M.node_matrix(js)
    ca, sa = math.cos(math.pi), math.sin(math.pi)

    def xf(p):
        x = m[0] * p[0] + m[4] * p[1] + m[8] * p[2] + m[12]
        y = m[1] * p[0] + m[5] * p[1] + m[9] * p[2] + m[13]
        z = m[2] * p[0] + m[6] * p[1] + m[10] * p[2] + m[14]
        return (ca * x + sa * z, y, -sa * x + ca * z)
    pos = [xf(p) for p in pos]
    mn = [min(p[i] for p in pos) for i in range(3)]
    mx = [max(p[i] for p in pos) for i in range(3)]
    ctr = [(mn[i] + mx[i]) / 2 for i in range(3)]
    H = mx[1] - mn[1]
    pos = [tuple((p[i] - ctr[i]) / H for i in range(3)) for p in pos]
    tw, th, tex = M.texture(js, binchunk, 512)

    # Roblox front is -Z; camera looks from -Z toward +Z. Screen x = -X (viewer's right is -X? no):
    # viewer at -Z looking +Z with +Y up has +X on their LEFT, so screen_x = -x.
    span = 1.4
    def proj(p):
        return ((-p[0] / span + 0.5) * RES, (0.5 - p[1] / span) * RES, p[2])
    zbuf = [1e9] * (RES * RES)
    img = [40] * (RES * RES * 3)
    for t in range(0, len(idx), 3):
        a, b, c = idx[t], idx[t + 1], idx[t + 2]
        P = [proj(pos[a]), proj(pos[b]), proj(pos[c])]
        U = [uv[a], uv[b], uv[c]]
        x0 = max(0, int(min(q[0] for q in P))); x1 = min(RES - 1, int(max(q[0] for q in P)) + 1)
        y0 = max(0, int(min(q[1] for q in P))); y1 = min(RES - 1, int(max(q[1] for q in P)) + 1)
        (ax, ay, az), (bx, by, bz), (cx, cy, cz) = P
        den = (by - cy) * (ax - cx) + (cx - bx) * (ay - cy)
        if abs(den) < 1e-9:
            continue
        for y in range(y0, y1 + 1):
            for x in range(x0, x1 + 1):
                px, py = x + 0.5, y + 0.5
                w0 = ((by - cy) * (px - cx) + (cx - bx) * (py - cy)) / den
                w1 = ((cy - ay) * (px - cx) + (ax - cx) * (py - cy)) / den
                w2 = 1 - w0 - w1
                if w0 < 0 or w1 < 0 or w2 < 0:
                    continue
                z = w0 * az + w1 * bz + w2 * cz
                i = y * RES + x
                if z < zbuf[i]:
                    zbuf[i] = z
                    u = w0 * U[0][0] + w1 * U[1][0] + w2 * U[2][0]
                    v = w0 * U[0][1] + w1 * U[1][1] + w2 * U[2][1]
                    tx = min(tw - 1, max(0, int(u * tw))); ty = min(th - 1, max(0, int(v * th)))
                    o = (ty * tw + tx) * 4
                    img[i * 3:i * 3 + 3] = tex[o:o + 3]
    # eye whites: bright, low saturation, in the upper 75% of the figure
    white = [False] * (RES * RES)
    for i in range(RES * RES):
        r, g, b = img[i * 3:i * 3 + 3]
        if zbuf[i] < 1e8 and min(r, g, b) > 200 and max(r, g, b) - min(r, g, b) < 40:
            white[i] = True
    seen = [False] * (RES * RES)
    blobs = []
    for i in range(RES * RES):
        if white[i] and not seen[i]:
            stack = [i]; seen[i] = True; pts = []
            while stack:
                j = stack.pop(); pts.append(j)
                y, x = divmod(j, RES)
                for nj in (j - 1, j + 1, j - RES, j + RES):
                    if 0 <= nj < RES * RES and white[nj] and not seen[nj] and abs((nj % RES) - x) <= 1:
                        seen[nj] = True; stack.append(nj)
            if len(pts) > 12:
                blobs.append(pts)
    def stats(pts):
        xs = [p % RES for p in pts]; ys = [p // RES for p in pts]
        return sum(xs) / len(xs), sum(ys) / len(ys), len(pts), min(ys), max(ys), min(xs), max(xs)
    cands = sorted([stats(b) + (b,) for b in blobs if stats(b)[1] < RES * 0.48], key=lambda s: -s[2])
    # pick the largest pair at similar height, mirrored about the centre
    best = None
    for i in range(len(cands)):
        for j in range(i + 1, len(cands)):
            a, b = cands[i], cands[j]
            if abs(a[1] - b[1]) < 18 and (a[0] - RES / 2) * (b[0] - RES / 2) < 0:
                sc = a[2] + b[2] - abs(a[2] - b[2])
                if best is None or sc > best[0]:
                    best = (sc, a, b)
    eyes = []
    if best:
        for e in (best[1], best[2]):
            cx, cy, n, ymin, ymax, xmin, xmax = e[:7]
            r = max(ymax - ymin, xmax - xmin) / 2 + 1.5
            zi = int(cy) * RES + int(cx)
            z = zbuf[zi]
            # surrounding skin colour: ring just outside the eye
            ring = []
            for k in range(36):
                ang = k / 36 * math.tau
                xx = int(cx + math.cos(ang) * (r + 4)); yy = int(cy + math.sin(ang) * (r + 4))
                if 0 <= xx < RES and 0 <= yy < RES and zbuf[yy * RES + xx] < 1e8:
                    ring.append(img[(yy * RES + xx) * 3:(yy * RES + xx) * 3 + 3])
            ring.sort(key=lambda c: sum(c))
            col = ring[len(ring) // 2] if ring else [200, 150, 80]
            X = -((cx / RES) - 0.5) * span
            Y = (0.5 - cy / RES) * span
            eyes.append((X, Y, z, r / RES * span, col))
            for k in range(60):
                ang = k / 60 * math.tau
                xx = int(cx + math.cos(ang) * r); yy = int(cy + math.sin(ang) * r)
                if 0 <= xx < RES and 0 <= yy < RES:
                    img[(yy * RES + xx) * 3:(yy * RES + xx) * 3 + 3] = [255, 0, 255]
    write_png(out, RES, RES, img)
    print('\tEyes = {')
    for X, Y, Z, R, col in sorted(eyes):
        print('\t\t{ Pos = Vector3.new(%.3f, %.3f, %.3f), Radius = %.3f, Lid = Color3.fromRGB(%d, %d, %d) },' % (X, Y, Z, R, col[0], col[1], col[2]))
    print('\t},')


if __name__ == '__main__':
    main()

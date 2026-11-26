#!/usr/bin/env python3
"""Render a Meshy GLB into a small shaded RGBA portrait (front three-quarter view, transparent
background) and write it as a Luau module the client turns into an EditableImage.

Portraits are used by the Index and the reveal card. Images have their own Editable memory
budget, so this keeps those screens off the client's ~8 EditableMesh limit.

Usage: python3 -I scripts/render_portrait.py <model.glb> <Name> [--size 160] [--yaw -0.45]
Output: src/shared/PortraitData/<Name>.luau (+ <Name>_<n>.luau chunks when large)
"""
import base64
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import mesh_to_luau as M  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CHUNK = 180_000


def main():
    args = sys.argv[1:]
    glb, name = args[0], args[1]
    size = int(args[args.index('--size') + 1]) if '--size' in args else 160
    yaw = float(args[args.index('--yaw') + 1]) if '--yaw' in args else -0.45
    ss = 2
    R = size * ss

    js, binchunk = M.read_glb(glb)
    prim = js['meshes'][0]['primitives'][0]
    at = prim['attributes']
    pos = M.accessor(js, binchunk, at['POSITION'])
    nor = M.accessor(js, binchunk, at['NORMAL']) if 'NORMAL' in at else None
    uv = M.accessor(js, binchunk, at['TEXCOORD_0'])
    idx = M.accessor(js, binchunk, prim['indices'])
    m = M.node_matrix(js)

    # Same placement as mesh_to_luau (rotate 180 about Y so the model faces -Z), then the
    # in-game viewport yaw, then look from -Z.
    ca, sa = math.cos(math.pi), math.sin(math.pi)
    cy, sy = math.cos(yaw), math.sin(yaw)

    def xf(p, w=1.0):
        x = m[0] * p[0] + m[4] * p[1] + m[8] * p[2] + m[12] * w
        y = m[1] * p[0] + m[5] * p[1] + m[9] * p[2] + m[13] * w
        z = m[2] * p[0] + m[6] * p[1] + m[10] * p[2] + m[14] * w
        x, z = ca * x + sa * z, -sa * x + ca * z
        # Roblox CFrame.Angles(0, yaw, 0): x' = cos*x + sin*z, z' = -sin*x + cos*z
        return (cy * x + sy * z, y, -sy * x + cy * z)

    P = [xf(p) for p in pos]
    N = None
    if nor:
        N = []
        for n in nor:
            v = xf(n, 0.0)
            ln = math.sqrt(v[0] ** 2 + v[1] ** 2 + v[2] ** 2) or 1
            N.append((v[0] / ln, v[1] / ln, v[2] / ln))
    mn = [min(p[i] for p in P) for i in range(3)]
    mx = [max(p[i] for p in P) for i in range(3)]
    ctr = [(mn[i] + mx[i]) / 2 for i in range(3)]
    span = max(mx[0] - mn[0], mx[1] - mn[1]) * 1.08
    tw, th, tex = M.texture(js, binchunk, 512)

    # light from the camera side, upper left (camera at -Z looking +Z; viewer's left is +X)
    L = (0.35, 0.55, -0.76)

    def proj(p):
        return ((-(p[0] - ctr[0]) / span + 0.5) * R, (0.5 - (p[1] - ctr[1]) / span) * R, p[2])

    zbuf = [1e9] * (R * R)
    img = [0.0] * (R * R * 4)
    PP = [proj(p) for p in P]
    for t in range(0, len(idx), 3):
        a, b, c = idx[t], idx[t + 1], idx[t + 2]
        (ax, ay, az), (bx, by, bz), (cx, cy2, cz) = PP[a], PP[b], PP[c]
        den = (by - cy2) * (ax - cx) + (cx - bx) * (ay - cy2)
        if abs(den) < 1e-9:
            continue
        x0 = max(0, int(min(ax, bx, cx))); x1 = min(R - 1, int(max(ax, bx, cx)) + 1)
        y0 = max(0, int(min(ay, by, cy2))); y1 = min(R - 1, int(max(ay, by, cy2)) + 1)
        ua, ub, uc = uv[a], uv[b], uv[c]
        na = N[a] if N else None
        nb = N[b] if N else None
        nc = N[c] if N else None
        for y in range(y0, y1 + 1):
            py = y + 0.5
            for x in range(x0, x1 + 1):
                px = x + 0.5
                w0 = ((by - cy2) * (px - cx) + (cx - bx) * (py - cy2)) / den
                w1 = ((cy2 - ay) * (px - cx) + (ax - cx) * (py - cy2)) / den
                w2 = 1 - w0 - w1
                if w0 < 0 or w1 < 0 or w2 < 0:
                    continue
                z = w0 * az + w1 * bz + w2 * cz
                i = y * R + x
                if z >= zbuf[i]:
                    continue
                zbuf[i] = z
                u = w0 * ua[0] + w1 * ub[0] + w2 * uc[0]
                v = w0 * ua[1] + w1 * ub[1] + w2 * uc[1]
                tx = min(tw - 1, max(0, int(u * tw))); ty = min(th - 1, max(0, int(v * th)))
                o = (ty * tw + tx) * 4
                r, g, bb = tex[o], tex[o + 1], tex[o + 2]
                shade = 1.0
                if na:
                    nx = w0 * na[0] + w1 * nb[0] + w2 * nc[0]
                    ny = w0 * na[1] + w1 * nb[1] + w2 * nc[1]
                    nz = w0 * na[2] + w1 * nb[2] + w2 * nc[2]
                    ln = math.sqrt(nx * nx + ny * ny + nz * nz) or 1
                    d = (nx * L[0] + ny * L[1] + nz * L[2]) / ln
                    shade = 0.72 + 0.38 * max(0.0, d)
                k = i * 4
                img[k] = min(255.0, r * shade)
                img[k + 1] = min(255.0, g * shade)
                img[k + 2] = min(255.0, bb * shade)
                img[k + 3] = 255.0

    # 2x2 supersample down to size, premultiplied so edges stay clean
    out = bytearray(size * size * 4)
    for y in range(size):
        for x in range(size):
            acc = [0.0, 0.0, 0.0, 0.0]
            for dy in range(ss):
                for dx in range(ss):
                    k = ((y * ss + dy) * R + (x * ss + dx)) * 4
                    al = img[k + 3] / 255.0
                    acc[0] += img[k] * al
                    acc[1] += img[k + 1] * al
                    acc[2] += img[k + 2] * al
                    acc[3] += img[k + 3]
            n = ss * ss
            alpha = acc[3] / n
            o = (y * size + x) * 4
            if alpha > 0:
                cov = alpha / 255.0
                out[o] = int(acc[0] / n / cov)
                out[o + 1] = int(acc[1] / n / cov)
                out[o + 2] = int(acc[2] / n / cov)
            out[o + 3] = int(alpha)

    if '--preview' in args:
        import find_eyes
        rgb = bytearray(size * size * 3)
        for i in range(size * size):
            al = out[i * 4 + 3] / 255.0
            for ch in range(3):
                rgb[i * 3 + ch] = int(out[i * 4 + ch] * al + 246 * (1 - al))
        find_eyes.write_png(args[args.index('--preview') + 1], size, size, rgb)

    b64 = base64.b64encode(bytes(out)).decode()
    d = os.path.join(ROOT, 'src', 'shared', 'PortraitData')
    os.makedirs(d, exist_ok=True)
    for f in os.listdir(d):
        if f == name + '.luau' or (f.startswith(name + '_') and f[len(name) + 1:-5].isdigit()):
            os.remove(os.path.join(d, f))
    chunks = [b64[i:i + CHUNK] for i in range(0, len(b64), CHUNK)]
    parts = []
    for n, ch in enumerate(chunks, 1):
        mod = f'{name}_{n}'
        open(os.path.join(d, mod + '.luau'), 'w').write(f'-- Generated by scripts/render_portrait.py. Do not edit.\nreturn "{ch}"\n')
        parts.append(f'require(script.Parent.{mod})')
    open(os.path.join(d, name + '.luau'), 'w').write(
        '-- Generated by scripts/render_portrait.py from %s. Do not edit.\n'
        '-- RGBA8 portrait, front three-quarter view, transparent background.\n'
        'return {\n\tSize = { %d, %d },\n\tPixels = %s,\n}\n' % (os.path.relpath(glb, ROOT), size, size, ' .. '.join(parts)))
    print(f'{name}: {size}x{size} portrait, {len(b64) // 1024} KB base64 in {len(chunks)} chunk(s)')


if __name__ == '__main__':
    main()

#!/usr/bin/env python3
"""Convert a Meshy GLB into a Luau module the game rebuilds with EditableMesh/EditableImage.

Stdlib only (plus macOS `sips` for texture resizing). Nothing is uploaded anywhere.

Usage: python3 -I scripts/mesh_to_luau.py <model.glb> <ModuleName> [--tex 256] [--yaw 0]

Output: src/shared/MeshData/<ModuleName>.luau

Coordinates: glTF is Y-up with the model facing +Z; Roblox faces -Z, so we rotate 180 deg
about Y (plus an optional extra --yaw in degrees). Positions are centred on the bounding box
and divided by the bounding-box height, so height == 1 and the client scales by species height.
"""
import base64
import json
import os
import struct
import subprocess
import sys
import tempfile
import math

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

COMP = {5120: ('b', 1), 5121: ('B', 1), 5122: ('h', 2), 5123: ('H', 2), 5125: ('I', 4), 5126: ('f', 4)}
NCOMP = {'SCALAR': 1, 'VEC2': 2, 'VEC3': 3, 'VEC4': 4}


def read_glb(path):
    data = open(path, 'rb').read()
    magic, _ver, _len = struct.unpack_from('<4sII', data, 0)
    assert magic == b'glTF', 'not a GLB'
    off = 12
    js, binchunk = None, None
    while off < len(data):
        clen, ctype = struct.unpack_from('<I4s', data, off)
        chunk = data[off + 8: off + 8 + clen]
        if ctype == b'JSON':
            js = json.loads(chunk)
        elif ctype == b'BIN\x00':
            binchunk = chunk
        off += 8 + clen
    return js, binchunk


def accessor(js, binchunk, idx):
    a = js['accessors'][idx]
    bv = js['bufferViews'][a['bufferView']]
    fmt, size = COMP[a['componentType']]
    n = NCOMP[a['type']]
    stride = bv.get('byteStride') or size * n
    base = bv.get('byteOffset', 0) + a.get('byteOffset', 0)
    out = []
    for i in range(a['count']):
        vals = struct.unpack_from('<' + fmt * n, binchunk, base + i * stride)
        out.append(vals if n > 1 else vals[0])
    return out


def node_matrix(js):
    # Meshy exports one node; honour its matrix if not identity.
    node = js['nodes'][0]
    m = node.get('matrix')
    if m:
        return m
    return [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1]


def read_bmp(path):
    d = open(path, 'rb').read()
    assert d[:2] == b'BM'
    pix_off = struct.unpack_from('<I', d, 10)[0]
    w, h = struct.unpack_from('<ii', d, 18)
    bpp = struct.unpack_from('<H', d, 28)[0]
    top_down = h < 0
    h = abs(h)
    bpr = bpp // 8
    row = (w * bpr + 3) & ~3
    out = bytearray(w * h * 4)
    for y in range(h):
        sy = y if top_down else h - 1 - y
        ro = pix_off + sy * row
        for x in range(w):
            p = ro + x * bpr
            b, g, r = d[p], d[p + 1], d[p + 2]
            o = (y * w + x) * 4
            out[o:o + 4] = bytes((r, g, b, 255))
    return w, h, bytes(out)


def texture(js, binchunk, size):
    if not js.get('images'):
        return None
    img = js['images'][0]
    bv = js['bufferViews'][img['bufferView']]
    raw = binchunk[bv.get('byteOffset', 0): bv.get('byteOffset', 0) + bv['byteLength']]
    ext = '.jpg' if 'jpeg' in img.get('mimeType', '') else '.png'
    with tempfile.TemporaryDirectory() as td:
        src = os.path.join(td, 'tex' + ext)
        dst = os.path.join(td, 'tex.bmp')
        open(src, 'wb').write(raw)
        subprocess.run(['/usr/bin/sips', '-s', 'format', 'bmp', '-z', str(size), str(size), src, '--out', dst],
                       check=True, capture_output=True)
        return read_bmp(dst)


def main():
    args = sys.argv[1:]
    glb, name = args[0], args[1]
    tex = 256
    yaw = 0.0
    if '--tex' in args:
        tex = int(args[args.index('--tex') + 1])
    if '--yaw' in args:
        yaw = float(args[args.index('--yaw') + 1])

    js, binchunk = read_glb(glb)
    prim = js['meshes'][0]['primitives'][0]
    at = prim['attributes']
    pos = accessor(js, binchunk, at['POSITION'])
    nrm = accessor(js, binchunk, at['NORMAL']) if 'NORMAL' in at else None
    uv = accessor(js, binchunk, at['TEXCOORD_0']) if 'TEXCOORD_0' in at else None
    idx = accessor(js, binchunk, prim['indices'])
    m = node_matrix(js)

    # apply node matrix (column-major), then rotate 180 + yaw about Y
    ang = math.radians(180 + yaw)
    ca, sa = math.cos(ang), math.sin(ang)

    def xf(p, w):
        x = m[0] * p[0] + m[4] * p[1] + m[8] * p[2] + (m[12] if w else 0)
        y = m[1] * p[0] + m[5] * p[1] + m[9] * p[2] + (m[13] if w else 0)
        z = m[2] * p[0] + m[6] * p[1] + m[10] * p[2] + (m[14] if w else 0)
        return (ca * x + sa * z, y, -sa * x + ca * z)

    pos = [xf(p, True) for p in pos]
    if nrm:
        nrm = [xf(n, False) for n in nrm]
    mn = [min(p[i] for p in pos) for i in range(3)]
    mx = [max(p[i] for p in pos) for i in range(3)]
    ctr = [(mn[i] + mx[i]) / 2 for i in range(3)]
    height = mx[1] - mn[1]
    pos = [tuple((p[i] - ctr[i]) / height for i in range(3)) for p in pos]
    ext = [(mx[i] - mn[i]) / height for i in range(3)]
    q = max(max(abs(c) for c in p) for p in pos)

    nv = len(pos)
    assert nv < 65536, 'too many vertices for uint16 indices'
    vb = bytearray()
    for i in range(nv):
        p = pos[i]
        vb += struct.pack('<hhh', *[int(round(c / q * 32767)) for c in p])
        n = nrm[i] if nrm else (0, 1, 0)
        ln = math.sqrt(sum(c * c for c in n)) or 1
        vb += struct.pack('<bbb', *[max(-127, min(127, int(round(c / ln * 127)))) for c in n])
        u = uv[i] if uv else (0, 0)
        vb += struct.pack('<HH', int(round(max(0, min(1, u[0])) * 65535)), int(round(max(0, min(1, u[1])) * 65535)))
    ib = bytearray()
    for i in idx:
        ib += struct.pack('<H', i)

    t = texture(js, binchunk, tex)
    out_dir = os.path.join(ROOT, 'src', 'shared', 'MeshData')
    os.makedirs(out_dir, exist_ok=True)
    for old in os.listdir(out_dir):
        if old == name + '.luau' or (old.startswith(name + '_') and old[len(name) + 1:-5].isdigit()):
            os.remove(os.path.join(out_dir, old))
    # Studio caps Script.Source at ~200k characters, so big strings live in chunk modules.
    CHUNK = 150_000
    chunks = []

    def chunked(b64):
        parts = []
        for i in range(0, len(b64), CHUNK):
            chunks.append(b64[i:i + CHUNK])
            parts.append('require(script.Parent.%s_%d)' % (name, len(chunks)))
        return ' .. '.join(parts) if parts else '""'

    out = os.path.join(out_dir, name + '.luau')
    vb64 = base64.b64encode(bytes(vb)).decode()
    ib64 = base64.b64encode(bytes(ib)).decode()
    with open(out, 'w') as f:
        f.write('-- Generated by scripts/mesh_to_luau.py from %s. Do not edit.\n' % os.path.relpath(glb, ROOT))
        f.write('-- Vertex: int16 pos x3 (scaled by Quant), int8 normal x3, uint16 uv x2. Index: uint16.\n')
        f.write('-- Base64 payloads are split across %s_<n> modules.\n' % name)
        f.write('return {\n')
        f.write('\tVertexCount = %d,\n\tTriangleCount = %d,\n' % (nv, len(idx) // 3))
        f.write('\tQuant = %r,\n' % q)
        f.write('\tExtents = { %r, %r, %r },\n' % tuple(ext))
        f.write('\tVertices = %s,\n' % chunked(vb64))
        f.write('\tIndices = %s,\n' % chunked(ib64))
        if t:
            w, h, px = t
            f.write('\tTextureSize = { %d, %d },\n' % (w, h))
            f.write('\tTexture = %s,\n' % chunked(base64.b64encode(px).decode()))
        f.write('}\n')
    for i, c in enumerate(chunks, 1):
        with open(os.path.join(out_dir, '%s_%d.luau' % (name, i)), 'w') as f:
            f.write('-- Generated chunk %d of %s. Do not edit.\nreturn "%s"\n' % (i, name, c))
    size_kb = sum(os.path.getsize(os.path.join(out_dir, x)) for x in os.listdir(out_dir) if x.startswith(name)) // 1024
    print('%s: %d verts, %d tris, extents %.2f x %.2f x %.2f, tex %s, %d KB' % (
        name, nv, len(idx) // 3, ext[0], ext[1], ext[2], t and '%dx%d' % (t[0], t[1]), size_kb))


if __name__ == '__main__':
    main()

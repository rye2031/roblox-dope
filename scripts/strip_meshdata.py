#!/usr/bin/env python3
"""Drop baked mesh geometry for species that are uploaded to Roblox.

Once a species is in src/shared/CreatureAssets.luau its model comes from
ReplicatedStorage/CreatureModels, so the client only needs the baked texture
(the base for element recolouring). This rewrites src/shared/MeshData/<Name>.luau
to keep TextureSize/Texture and deletes the vertex and index chunk modules,
which roughly halves what every client downloads at join.

Usage: python3 -I scripts/strip_meshdata.py [--dry-run]
"""
import os, re, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MD = os.path.join(ROOT, 'src', 'shared', 'MeshData')
dry = '--dry-run' in sys.argv

assets = open(os.path.join(ROOT, 'src', 'shared', 'CreatureAssets.luau')).read()
uploaded = re.findall(r'^\t(\w+) = \{ Model = \d+', assets, re.M)
saved = 0
for name in uploaded:
    main = os.path.join(MD, name + '.luau')
    if not os.path.exists(main):
        continue
    src = open(main).read()
    if 'Vertices =' not in src:
        continue
    def chunks(field):
        m = re.search(r'^\t' + field + r' = (.+),$', src, re.M)
        return re.findall(r'script\.Parent\.(\w+)\)', m.group(1)) if m else []
    drop = chunks('Vertices') + chunks('Indices')
    tex = re.search(r'^\tTexture = .+,$', src, re.M).group(0)
    size = re.search(r'^\tTextureSize = .+,$', src, re.M).group(0)
    header = src.split('return {')[0].rstrip('\n')
    new = (header + '\n-- Geometry removed by scripts/strip_meshdata.py: this species is uploaded (CreatureAssets),\n'
           '-- so only the base texture for element recolouring is kept.\nreturn {\n\tTextureOnly = true,\n'
           + size + '\n' + tex + '\n}\n')
    for c in drop:
        f = os.path.join(MD, c + '.luau')
        if os.path.exists(f):
            saved += os.path.getsize(f)
            if not dry:
                os.remove(f)
    if not dry:
        open(main, 'w').write(new)
    print(f'{name}: dropped {len(drop)} chunk modules')
print(f'{"would remove" if dry else "removed"} {saved / 1e6:.1f} MB of geometry')

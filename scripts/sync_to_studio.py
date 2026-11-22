#!/usr/bin/env python3
"""Push src/ into the open Studio place through Studio's built-in MCP (execute_luau in Edit mode).

A fallback for when the Rojo plugin isn't connected. Mirrors the default.project.json mapping:
  src/server -> ServerScriptService.Server, src/client -> StarterPlayer.StarterPlayerScripts.Client,
  src/shared -> ReplicatedStorage.Shared
*.server.luau -> Script, *.client.luau -> LocalScript, other .luau -> ModuleScript.
Instances under those folders that no longer exist in src/ are removed.

Usage: python3 -I scripts/sync_to_studio.py [--only <substring>]
"""
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import studio_mcp as S  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MAP = [
    ('src/server', 'game:GetService("ServerScriptService")', 'Server'),
    ('src/client', 'game:GetService("StarterPlayer"):WaitForChild("StarterPlayerScripts")', 'Client'),
    ('src/shared', 'game:GetService("ReplicatedStorage")', 'Shared'),
]


def long_string(s):
    level = 0
    while (']' + '=' * level + ']') in s:
        level += 1
    eq = '=' * level
    return '[' + eq + '[\n' + s + ']' + eq + ']'


def classify(fn):
    if fn.endswith('.server.luau'):
        return fn[:-len('.server.luau')], 'Script'
    if fn.endswith('.client.luau'):
        return fn[:-len('.client.luau')], 'LocalScript'
    return fn[:-len('.luau')], 'ModuleScript'


def collect():
    items = []  # (parent_expr, folder_name, rel_dirs, name, class, source)
    for src, parent, folder in MAP:
        base = os.path.join(ROOT, src)
        for dp, _dn, files in os.walk(base):
            rel = os.path.relpath(dp, base)
            dirs = [] if rel == '.' else rel.split(os.sep)
            for fn in sorted(files):
                if not fn.endswith('.luau'):
                    continue
                name, cls = classify(fn)
                items.append((parent, folder, dirs, name, cls, open(os.path.join(dp, fn)).read()))
    return items


PRELUDE = '''
local function ensure(parent, name, class)
	local c = parent:FindFirstChild(name)
	if c and c.ClassName ~= class then c:Destroy() c = nil end
	if not c then c = Instance.new(class) c.Name = name c.Parent = parent end
	return c
end
'''


def item_code(it):
    parent, folder, dirs, name, cls, src = it
    lines = ['do', '\tlocal p = ensure(%s, %s, "Folder")' % (parent, json.dumps(folder))]
    for d in dirs:
        lines.append('\tp = ensure(p, %s, "Folder")' % json.dumps(d))
    lines.append('\tlocal s = ensure(p, %s, %s)' % (json.dumps(name), json.dumps(cls)))
    lines.append('\ts.Source = %s' % long_string(src))
    lines.append('end')
    return '\n'.join(lines)


def prune_code(items):
    keep = {}
    for parent, folder, dirs, name, cls, _ in items:
        keep.setdefault(folder, set()).add('/'.join(dirs + [name]))
    out = [PRELUDE]
    out.append('local removed = {}')
    for src, parent, folder in MAP:
        names = sorted(keep.get(folder, set()))
        out.append('do')
        out.append('\tlocal root = %s:FindFirstChild(%s)' % (parent, json.dumps(folder)))
        out.append('\tlocal keep = {%s}' % ', '.join('[%s]=true' % json.dumps(n) for n in names))
        out.append('''	if root then
		for _, d in root:GetDescendants() do
			if d:IsA("LuaSourceContainer") then
				local path = {}
				local x = d
				while x ~= root do table.insert(path, 1, x.Name) x = x.Parent end
				local key = table.concat(path, "/")
				if not keep[key] then table.insert(removed, key) d:Destroy() end
			end
		end
	end''')
        out.append('end')
    out.append('''for _, n in {"Baseplate", "SpawnLocation"} do local o = workspace:FindFirstChild(n) if o then o:Destroy() end end''')
    out.append('return "pruned: " .. table.concat(removed, ", ")')
    return '\n'.join(out)


def main():
    only = None
    if '--only' in sys.argv:
        only = sys.argv[sys.argv.index('--only') + 1]
    items = collect()
    c = S.Client()
    if not c.studio:
        print('No Studio connected')
        return 1
    try:
        batch, size = [], 0
        sent = 0

        def flush():
            nonlocal batch, size, sent
            if not batch:
                return
            code = PRELUDE + '\n'.join(item_code(i) for i in batch) + '\nreturn "ok"'
            r = c.req('tools/call', {"name": "execute_luau", "arguments": {"code": code, "datamodel_type": "Edit", "studio_id": c.studio}}, 120)
            txt = json.dumps(r.get('result', r))[:300]
            names = ', '.join(i[3] for i in batch)
            print('synced [%s] -> %s' % (names, txt))
            sent += len(batch)
            batch, size = [], 0

        for it in items:
            if only and only not in it[3]:
                continue
            n = len(it[5])
            if size + n > 300_000:
                flush()
            batch.append(it)
            size += n
        flush()
        if not only:
            r = c.req('tools/call', {"name": "execute_luau", "arguments": {"code": prune_code(items), "datamodel_type": "Edit", "studio_id": c.studio}}, 60)
            print(json.dumps(r.get('result', r))[:400])
        print('done: %d scripts' % sent)
    finally:
        c.close()


if __name__ == '__main__':
    sys.exit(main() or 0)

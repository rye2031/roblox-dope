#!/usr/bin/env python3
"""Tiny stdio client for Roblox Studio's built-in MCP proxy (StudioMCP ships inside
RobloxStudio.app). Lets a running agent call Studio tools without reloading its own MCP config.

Usage:
  python3 -I scripts/studio_mcp.py list
  python3 -I scripts/studio_mcp.py call <tool> '<json args>' [timeout_s]
  python3 -I scripts/studio_mcp.py luau execute_luau <file.luau> [Edit|Server|Client] [timeout_s]
"""
import json, select, subprocess, sys, time

BIN = '/Applications/RobloxStudio.app/Contents/MacOS/StudioMCP'


class Client:
    def __init__(self):
        self.p = subprocess.Popen([BIN, '--stdio'], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
        self.n = 0
        self.req('initialize', {"protocolVersion": "2025-06-18", "capabilities": {}, "clientInfo": {"name": "roblox-game-cli", "version": "1"}})
        self.send({"jsonrpc": "2.0", "method": "notifications/initialized"})
        time.sleep(1.0)
        self.studio = None
        for _ in range(10):
            r = self.req('tools/call', {"name": "list_roblox_studios", "arguments": {}})
            try:
                txt = r['result']['content'][0]['text']
                studios = json.loads(txt).get('studios', [])
            except Exception:
                studios = []
            if studios:
                self.studio = studios[0]['id']
                break
            time.sleep(1.5)

    def send(self, m):
        self.p.stdin.write((json.dumps(m) + '\n').encode())
        self.p.stdin.flush()

    def req(self, method, params, timeout=20):
        self.n += 1
        rid = self.n
        self.send({"jsonrpc": "2.0", "id": rid, "method": method, "params": params})
        end = time.time() + timeout
        while time.time() < end:
            r, _, _ = select.select([self.p.stdout], [], [], 0.5)
            if r:
                line = self.p.stdout.readline()
                if not line:
                    break
                msg = json.loads(line)
                if msg.get('id') == rid:
                    return msg
        return {"error": "timeout"}

    def close(self):
        self.p.kill()


def main():
    c = Client()
    try:
        cmd = sys.argv[1]
        if cmd == 'list':
            r = c.req('tools/list', {})
            for t in r.get('result', {}).get('tools', []):
                print('##', t['name'])
                print(t.get('description', '').strip()[:600])
                print(json.dumps(t.get('inputSchema', {}).get('properties', {}))[:600])
                print()
            if 'error' in r:
                print(r)
        else:
            tool = sys.argv[2]
            if cmd == 'luau':
                args = {"code": open(sys.argv[3]).read(), "datamodel_type": sys.argv[4] if len(sys.argv) > 4 else "Edit"}
                timeout = float(sys.argv[5]) if len(sys.argv) > 5 else 60
            else:
                args = json.loads(sys.argv[3]) if len(sys.argv) > 3 else {}
                timeout = float(sys.argv[4]) if len(sys.argv) > 4 else 60
            if c.studio and 'studio_id' not in args and tool != 'list_roblox_studios':
                args['studio_id'] = c.studio
            r = c.req('tools/call', {"name": tool, "arguments": args}, timeout)
            res = r.get('result', r)
            for item in res.get('content', []) if isinstance(res, dict) else []:
                if item.get('type') == 'text':
                    print(item['text'])
                elif item.get('type') == 'image':
                    import base64, os
                    out = os.environ.get('MCP_IMG', '/tmp/studio_mcp.png')
                    open(out, 'wb').write(base64.b64decode(item['data']))
                    print('[image saved to %s]' % out)
            if not (isinstance(res, dict) and res.get('content')):
                print(json.dumps(r)[:4000])
    finally:
        c.close()


if __name__ == '__main__':
    main()

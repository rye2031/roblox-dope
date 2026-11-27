#!/usr/bin/env python3
"""Scripted playtest helpers over Studio's built-in MCP. Import and drive from a scenario:

  python3 -I scripts/playtest.py <scenario.py>

The scenario file runs with these names in scope: srv(cmd, *args), cli(cmd, *args), nav(x,y,z),
navto(instance_path), keys([...]), hold(key, seconds), press(key), shot(name, cam=None, at=None),
luau(code, dm), log(msg), wait(s), state().
"""
import json
import os
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import studio_mcp as S  # noqa: E402

SHOTS = os.environ.get('SHOTS', '/tmp')
c = S.Client()
T0 = time.time()


def call(tool, args, timeout=90):
    args = dict(args)
    args.setdefault('studio_id', c.studio)
    r = c.req('tools/call', {"name": tool, "arguments": args}, timeout)
    res = r.get('result', r)
    out = []
    for item in res.get('content', []) if isinstance(res, dict) else []:
        if item.get('type') == 'text':
            out.append(item['text'])
        elif item.get('type') == 'image':
            out.append(item)
    return out if out else [json.dumps(r)[:500]]


def lua_val(v):
    if isinstance(v, bool):
        return 'true' if v else 'false'
    if isinstance(v, (int, float)):
        return repr(v)
    if v is None:
        return 'nil'
    if isinstance(v, (list, tuple)) and len(v) == 3 and all(isinstance(x, (int, float)) for x in v):
        return 'Vector3.new(%r, %r, %r)' % tuple(v)
    if isinstance(v, (list, tuple)):
        return '{' + ', '.join(lua_val(x) for x in v) + '}'
    return json.dumps(v)


def luau(code, dm='Server'):
    return '\n'.join(x for x in call('execute_luau', {"code": code, "datamodel_type": dm}) if isinstance(x, str))


def srv(cmd, *args):
    a = ', '.join([json.dumps(cmd)] + [lua_val(x) for x in args])
    return luau('return game:GetService("ServerStorage").WildDebug:Invoke(%s)' % a, 'Server')


def cli(cmd, *args):
    a = ', '.join([json.dumps(cmd)] + [lua_val(x) for x in args])
    return luau('return game:GetService("ReplicatedStorage"):WaitForChild("WildClientDebug"):Invoke(%s)' % a, 'Client')


def state():
    txt = srv('state')
    try:
        return json.loads(txt)
    except Exception:
        print('state parse failed:', txt[:400])
        return {}


def me():
    return state().get('player')


def nav(x, y, z, speed=None, timeout=90):
    a = {"datamodel_type": "Client", "x": x, "y": y, "z": z}
    if speed:
        a['speed_multiplier'] = speed
    return call('character_navigation', a, timeout)


def navto(path, timeout=60):
    return call('character_navigation', {"datamodel_type": "Client", "instance_path": path}, timeout)


def keys(actions):
    return call('user_keyboard_input', {"actions": actions, "datamodel_type": "Client"})


def press(key):
    return keys([{"action": "keyPress", "key_code": key}])


def hold(key, seconds):
    return keys([{"action": "keyDown", "key_code": key}, {"action": "wait", "wait_time_ms": int(seconds * 1000)}, {"action": "keyUp", "key_code": key}])


def shot(name, cam=None, at=None):
    args = {"capture_id": name}
    if cam:
        args['camera_position'] = cam
        args['look_at_position'] = at
    out = call('screen_capture', args, 60)
    import base64
    for item in out:
        if isinstance(item, dict) and item.get('type') == 'image':
            p = os.path.join(SHOTS, name + '.png')
            open(p, 'wb').write(base64.b64decode(item['data']))
            log('shot ' + p)
            return p
    log('shot failed: %s' % str(out)[:200])


def face(x, y, z):
    """Point the player's camera at a world point (as a player would by turning to look)."""
    return luau('''
local cam = workspace.CurrentCamera
local hrp = game.Players.LocalPlayer.Character.HumanoidRootPart
local target = Vector3.new(%r, %r, %r)
local flat = (target - hrp.Position) * Vector3.new(1, 0, 1)
local from = hrp.Position - flat.Unit * 10 + Vector3.new(0, 5, 0)
cam.CFrame = CFrame.lookAt(from, target)
return "ok"''' % (x, y, z), 'Client')


def click(path):
    return call('user_mouse_input', {"datamodel_type": "Client", "actions": [{"action": "moveTo", "instance_path": path}, {"action": "mouseButtonClick", "mouse_button": "left"}]})


def tap_gui(path):
    """Tap a ScreenGui button at its on-screen centre (works in touch emulation)."""
    xy = luau('''
local g = game.Players.LocalPlayer.PlayerGui
local obj = g
for part in string.gmatch(%s, "[^%%.]+") do obj = obj:FindFirstChild(part) end
local p, sz = obj.AbsolutePosition, obj.AbsoluteSize
return string.format("%%d,%%d", p.X + sz.X / 2, p.Y + sz.Y / 2)''' % json.dumps(path), 'Client')
    x, y = [int(float(a)) for a in xy.split(',')]
    return call('user_mouse_input', {"datamodel_type": "Client", "actions": [{"action": "moveTo", "x": x, "y": y}, {"action": "mouseButtonClick", "mouse_button": "left"}]})


def tap_world(x, y, z, hold_ms=500):
    xy = luau('''
local v = workspace.CurrentCamera:WorldToViewportPoint(Vector3.new(%r, %r, %r))
local inset = game:GetService("GuiService"):GetGuiInset()
return string.format("%%d,%%d", v.X, v.Y - inset.Y)''' % (x, y, z), 'Client')
    px, py = [int(float(a)) for a in xy.split(',')]
    return call('user_mouse_input', {"datamodel_type": "Client", "actions": [{"action": "moveTo", "x": px, "y": py}, {"action": "mouseButtonDown", "mouse_button": "left"}, {"action": "wait", "wait_time_ms": hold_ms}, {"action": "mouseButtonUp", "mouse_button": "left"}]})


def log(msg):
    print('[%6.1fs] %s' % (time.time() - T0, msg), flush=True)


# Every sound in the test client goes into a muted SoundGroup (game SFX, footsteps, anything
# added later), so nothing from a background playtest plays through the owner's speakers.
MUTE_LUAU = """
local SS = game:GetService("SoundService")
local g = SS:FindFirstChild("TestMute") or Instance.new("SoundGroup")
g.Name = "TestMute"
g.Volume = 0
g.Parent = SS
local n = 0
for _, d in game:GetDescendants() do
    pcall(function()
        if d:IsA("Sound") and d.SoundGroup ~= g then d.SoundGroup = g n += 1 end
        if d:IsA("SoundGroup") and d ~= g then d.Volume = 0 end
    end)
end
if not _G.__wildMuteHook then
    _G.__wildMuteHook = game.DescendantAdded:Connect(function(d)
        pcall(function()
            if d:IsA("Sound") then d.SoundGroup = g end
            if d:IsA("SoundGroup") and d ~= g then d.Volume = 0 end
        end)
    end)
end
return n
"""
_last_mute = [0.0]


def mute():
    _last_mute[0] = time.time()
    try:
        return luau(MUTE_LUAU, 'Client')
    except Exception as e:
        return 'mute failed: %s' % e


def wait(s):
    # re-apply the mute every few seconds while a test waits (cheap; catches new sounds even
    # if the client's hook was lost)
    end = time.time() + s
    while True:
        if time.time() - _last_mute[0] > 4:
            mute()
        left = end - time.time()
        if left <= 0:
            break
        time.sleep(min(left, 1.0))


if __name__ == '__main__':
    try:
        mute()
        exec(open(sys.argv[1]).read(), globals())
    finally:
        c.close()

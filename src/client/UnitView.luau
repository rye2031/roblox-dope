-- Draws every combat unit (team followers and wild monsters) on top of the server's invisible
-- unit parts: recoloured model, nameplate with HP/shield/effects, element aura, and animations.
-- Also turns the server's combat events into readable feedback: attack animations (windup,
-- lunge, recoil, ultimate charge), projectiles, impacts, damage numbers, hit flashes and
-- knockback, red telegraph circles for incoming ultimates, death collapses.
--
-- The server applies damage the moment a skill fires; the client plays a short windup first,
-- so hit numbers, flashes and the HP bar wait for the strike (or the projectile) to land.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Monsters = require(Shared.Monsters)
local Theme = require(Shared.Theme)
local Models = require(script.Parent.Models)
local CombatFx = require(script.Parent.CombatFx)
local TamerAnim = require(script.Parent.TamerAnim)

local player = Players.LocalPlayer
local C = Theme.C
local UnitView = {}

local holder = Instance.new("Folder")
holder.Name = "UnitViews"
holder.Parent = workspace

type Anim = { kind: string, t0: number, dur: number, tier: number, dir: Vector3, pre: number, ranged: boolean }
type View = {
	part: BasePart,
	body: BasePart,
	release: () -> (),
	bb: BillboardGui,
	hp: Frame,
	trail: Frame,
	shield: Frame,
	fx: TextLabel,
	title: TextLabel,
	cf: CFrame?,
	seed: number,
	aura: ParticleEmitter?,
	auraRate: number,
	hl: Highlight?,
	hlFill: number,
	baseSize: Vector3,
	lastScale: Vector3,
	lastTransp: number,
	anim: Anim?,
	knock: Vector3,
	shake: number,
	born: number,
	deadAt: number?,
	faintAt: number?,
	hpShown: number,
	trailW: number,
	dropAt: number,
	holdUntil: number,
}
local views: { [BasePart]: View } = {}
UnitView.views = views

local STAR = "★"
local rad = math.rad

local function smooth(x: number): number
	x = math.clamp(x, 0, 1)
	return x * x * (3 - 2 * x)
end
local function outQuad(x: number): number
	x = math.clamp(x, 0, 1)
	return 1 - (1 - x) * (1 - x)
end
local function backOut(x: number): number
	x = math.clamp(x, 0, 1)
	local c1 = 1.9
	return 1 + (c1 + 1) * (x - 1) ^ 3 + c1 * (x - 1) ^ 2
end
local function lerp(a: number, b: number, k: number): number
	return a + (b - a) * k
end
local function flat(v: Vector3): Vector3
	local f = Vector3.new(v.X, 0, v.Z)
	return f.Magnitude > 0.01 and f.Unit or Vector3.new(0, 0, -1)
end

local function hpColor(side: string, mine: boolean): Color3
	if side == "wild" then
		return C.Coral
	end
	return mine and C.Mint or C.Sky
end

local function makePlate(part: BasePart, mine: boolean): (BillboardGui, Frame, Frame, TextLabel, TextLabel)
	local side = part:GetAttribute("Side")
	local sp = Monsters.Species[part:GetAttribute("Species")]
	local el = part:GetAttribute("Element")
	local info = Config.ElementInfo[el]
	local boss = part:GetAttribute("Boss")
	local bb = Instance.new("BillboardGui")
	bb.Size = UDim2.fromOffset(boss and 260 or 170, boss and 58 or 46)
	bb.StudsOffset = Vector3.new(0, part.Size.Y / 2 + 1.6, 0)
	bb.MaxDistance = boss and 220 or 90
	bb.LightInfluence = 0
	bb.AlwaysOnTop = false
	bb.Adornee = part
	local title = Theme.text({
		Name = "Title",
		Size = UDim2.new(1, 0, 0.45, 0),
		Text = string.format("%s%s Lv%d", boss and "👑 " or part:GetAttribute("Elite") and "★ " or "", sp.Name, part:GetAttribute("Level")),
		TextColor3 = side == "wild" and C.Ink or (mine and Color3.fromRGB(30, 120, 90) or C.Ink),
		TextStrokeTransparency = 0.4,
		TextStrokeColor3 = Color3.new(1, 1, 1),
		Parent = bb,
	}, "Title")
	local stars = Theme.text({ Size = UDim2.new(1, 0, 0.22, 0), Position = UDim2.fromScale(0, 0.42), Text = info.Icon .. " " .. string.rep(STAR, sp.Stars), TextColor3 = info.Color, TextStrokeTransparency = 0.5, TextStrokeColor3 = Color3.new(1, 1, 1), Parent = bb }, "Title")
	local _ = stars
	local back = Theme.new("Frame", { Position = UDim2.new(0.1, 0, 0.68, 0), Size = UDim2.new(0.8, 0, 0.16, 0), BackgroundColor3 = Color3.fromRGB(255, 255, 255), BackgroundTransparency = 0.1, ZIndex = 1, Parent = bb }, { Theme.new("UICorner", { CornerRadius = UDim.new(0.5, 0) }), Theme.new("UIStroke", { Color = C.Line, Thickness = 1 }) })
	-- the trail shows the chunk just lost, then drains to the new value
	local trail = Theme.new("Frame", { Name = "Trail", Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromRGB(255, 236, 170), ZIndex = 2, Parent = back }, { Theme.new("UICorner", { CornerRadius = UDim.new(0.5, 0) }) })
	local hp = Theme.new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = hpColor(side, mine), ZIndex = 3, Parent = back }, { Theme.new("UICorner", { CornerRadius = UDim.new(0.5, 0) }) })
	local shield = Theme.new("Frame", { Size = UDim2.fromScale(0, 1), BackgroundColor3 = Color3.fromRGB(150, 200, 255), BackgroundTransparency = 0.2, ZIndex = 4, Parent = back }, { Theme.new("UICorner", { CornerRadius = UDim.new(0.5, 0) }) })
	local _ = trail
	local fxl = Theme.text({ Size = UDim2.new(1, 0, 0.16, 0), Position = UDim2.fromScale(0, 0.86), Text = "", TextColor3 = C.Sub, TextStrokeTransparency = 0.5, TextStrokeColor3 = Color3.new(1, 1, 1), Parent = bb }, "Bold")
	bb.Parent = part
	return bb, hp, shield, fxl, title
end

local function addView(part: BasePart)
	if views[part] then
		return
	end
	local sp = part:GetAttribute("Species")
	local el = part:GetAttribute("Element")
	if not sp or not el or not Monsters.Species[sp] then
		return
	end
	local mine = part:GetAttribute("Owner") == player.UserId
	local body, release = Models.get(sp, el, part.Size.Y)
	if views[part] or not part.Parent then
		-- added twice while the model loaded, or the unit left meanwhile
		body:Destroy()
		release()
		return
	end
	body.Name = part.Name
	body.Parent = holder
	local bb, hp, shield, fxl, title = makePlate(part, mine)
	local trail = (hp.Parent :: Frame):FindFirstChild("Trail") :: Frame
	local v: View = {
		part = part,
		body = body,
		release = release,
		bb = bb,
		hp = hp,
		trail = trail,
		shield = shield,
		fx = fxl,
		title = title,
		cf = nil,
		seed = math.random() * 10,
		aura = nil,
		auraRate = 3,
		hl = nil,
		hlFill = 0.85,
		baseSize = body.Size,
		lastScale = Vector3.one,
		lastTransp = 0,
		anim = nil,
		knock = Vector3.zero,
		shake = 0,
		born = os.clock(),
		deadAt = nil,
		faintAt = nil,
		hpShown = 1,
		trailW = 1,
		dropAt = 0,
		holdUntil = 0,
	}
	local hp0, max0 = part:GetAttribute("HP") or 0, part:GetAttribute("MaxHP") or 1
	v.hpShown = math.clamp(hp0 / max0, 0, 1)
	v.trailW = v.hpShown
	-- element aura: subtle for the triangle, strong for Light/Dark, big for elites and bosses
	local info = Config.ElementInfo[el]
	local strong = el == "Light" or el == "Dark" or part:GetAttribute("Elite") or part:GetAttribute("Boss")
	local e = Instance.new("ParticleEmitter")
	e.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	e.Color = ColorSequence.new(info.Color, info.Light)
	v.auraRate = strong and 14 or 3
	e.Rate = v.auraRate
	e.Lifetime = NumberRange.new(0.8, 1.4)
	e.Speed = NumberRange.new(0.5, 2)
	e.SpreadAngle = Vector2.new(180, 180)
	e.Size = NumberSequence.new(strong and 0.6 or 0.35, 0)
	e.LightEmission = 0.6
	e.Parent = body
	v.aura = e
	if part:GetAttribute("Boss") or part:GetAttribute("Elite") then
		local hl = Instance.new("Highlight")
		hl.FillTransparency = 0.85
		hl.FillColor = info.Color
		hl.OutlineColor = part:GetAttribute("Boss") and Color3.fromRGB(255, 210, 80) or info.Color
		hl.DepthMode = Enum.HighlightDepthMode.Occluded
		hl.Adornee = body
		hl.Parent = body
		v.hl = hl
	end
	views[part] = v
end

local function removeView(part: BasePart)
	local v = views[part]
	if not v then
		return
	end
	views[part] = nil
	v.bb:Destroy()
	local dying = v.deadAt ~= nil
	if dying then
		-- finish the collapse instead of popping out
		local body = v.body
		TweenService:Create(body, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Size = body.Size * 0.2, Transparency = 1 }):Play()
		task.delay(0.32, function()
			body:Destroy()
			v.release()
		end)
	else
		v.body:Destroy()
		v.release()
	end
end

----------------------------------------------------------------------------------------------
-- Body animation

-- Offset (in the unit's own space) and scale (fwd, up) for the current attack animation.
local function attackPose(v: View, now: number, h: number): (CFrame, number, number)
	local a = v.anim
	if not a then
		return CFrame.identity, 1, 1
	end
	local t = now - a.t0
	if t >= a.dur then
		if a.kind ~= "charge" then
			v.anim = nil
		end
		if a.kind == "charge" and t > a.dur + 1.2 then
			v.anim = nil -- the ultimate never came (target died, unit stunned)
		end
		if v.aura then
			v.aura.Rate = v.auraRate
		end
		if a.kind ~= "charge" then
			return CFrame.identity, 1, 1
		end
		t = a.dur
	end
	local ld = flat((v.cf :: CFrame):VectorToObjectSpace(a.dir))
	local axis = Vector3.yAxis:Cross(ld)
	local fwd, up, lean, sF, sU = 0, 0, 0, 1, 1
	local jitter = Vector3.zero

	local function charge(k: number)
		-- swelling, trembling, rising: power gathering
		local e = smooth(k)
		up = 0.1 * h * e
		lean = -0.14 * e
		sU = 1 + 0.12 * e + 0.03 * math.sin(now * 32)
		sF = 1 + 0.06 * e
		jitter = Vector3.new(math.noise(now * 30, v.seed), 0, math.noise(v.seed, now * 30)) * 0.08 * h * e
	end

	if a.kind == "charge" then
		charge(t / math.max(a.dur, 0.01))
	elseif a.kind == "ult" and t < a.pre then
		charge(t / a.pre)
	elseif a.kind == "ult" then
		local q = (t - a.pre) / (a.dur - a.pre)
		if a.ranged then
			-- blast: huge recoil
			local r = outQuad(q / 0.15) * (1 - smooth((q - 0.3) / 0.7))
			fwd = -0.35 * h * r
			lean = -0.35 * r
			sU = 1 - 0.15 * r
			sF = 1 + 0.1 * r
			up = 0.05 * h * (1 - smooth(q / 0.5))
		else
			-- leap and slam onto the target
			local air = math.clamp(q / 0.45, 0, 1)
			local rc = smooth((q - 0.55) / 0.45)
			fwd = outQuad(air) * 1.0 * h * (1 - rc)
			up = math.sin(air * math.pi) * 0.85 * h
			lean = lerp(-0.25, 0.4, air) * (1 - rc)
			local land = math.sin(math.clamp((q - 0.45) / 0.25, 0, 1) * math.pi)
			sU = 1 - 0.25 * land + 0.08 * math.sin(air * math.pi)
			sF = 1 + 0.15 * land
		end
	elseif a.kind == "ranged" then
		local p = t / a.dur
		local wu = smooth(p / 0.38)
		local rel = outQuad((p - 0.38) / 0.1) * (1 - smooth((p - 0.48) / 0.52))
		up = 0.08 * h * wu * (1 - rel)
		lean = -0.12 * wu * (1 - rel) - 0.22 * rel
		fwd = -0.18 * h * rel
		sU = 1 + 0.07 * wu * (1 - rel) - 0.08 * rel
		sF = 1 + 0.05 * rel
	else -- melee lunge
		local p = t / a.dur
		local tier2 = a.tier >= 2
		local wu = smooth(p / 0.32)
		local st = outQuad((p - 0.32) / 0.16)
		local rc = smooth((p - 0.5) / 0.5)
		local reach = (tier2 and 0.8 or 0.55) * h
		fwd = lerp(lerp(0, -0.18 * h, wu), reach, st) * (1 - rc)
		if tier2 then
			up = math.sin(math.clamp((p - 0.22) / 0.3, 0, 1) * math.pi) * 0.35 * h
		else
			up = math.sin(math.clamp((p - 0.3) / 0.22, 0, 1) * math.pi) * 0.06 * h
		end
		lean = lerp(lerp(0, -0.2, wu), 0.35, st) * (1 - rc)
		sU = 1 - 0.12 * wu * (1 - st) - 0.06 * st * (1 - rc)
		sF = 1 + 0.05 * wu * (1 - st) + 0.14 * st * (1 - rc)
	end
	local rot = axis.Magnitude > 0.01 and CFrame.fromAxisAngle(axis.Unit, lean) or CFrame.identity
	return CFrame.new(ld * fwd + Vector3.new(0, up, 0) + jitter) * rot, sF, sU
end

local function setScale(v: View, ld: Vector3?, sF: number, sU: number, uniform: number)
	-- stretch along the attack direction, squash/stretch vertically, keep rough volume
	local side = 1 / math.sqrt(math.max(0.5, sU * sF)) ^ 0.5
	local fx, fz = side, side
	if ld then
		fx = lerp(side, sF, math.abs(ld.X))
		fz = lerp(side, sF, math.abs(ld.Z))
	end
	local s = Vector3.new(fx, sU, fz) * uniform
	if (s - v.lastScale).Magnitude > 0.002 then
		v.lastScale = s
		v.body.Size = v.baseSize * s
	end
end

local function updateView(v: View, dt: number, now: number)
	local part = v.part
	local state = part:GetAttribute("State")
	local hp, max = part:GetAttribute("HP") or 0, part:GetAttribute("MaxHP") or 1
	local frac = math.clamp(hp / max, 0, 1)
	-- HP bar waits for the strike to land, then a light chunk drains behind it
	if frac < v.hpShown then
		if now >= v.holdUntil then
			v.hpShown = frac
			v.dropAt = now
		end
	else
		v.hpShown = frac
	end
	if v.trailW < v.hpShown then
		v.trailW = v.hpShown
	elseif v.trailW > v.hpShown and now - v.dropAt > 0.35 then
		v.trailW = math.max(v.hpShown, v.trailW - dt * 1.2)
	end
	v.hp.Size = UDim2.fromScale(v.hpShown, 1)
	v.trail.Size = UDim2.fromScale(v.trailW, 1)
	v.shield.Size = UDim2.fromScale(math.clamp((part:GetAttribute("Shield") or 0) / max, 0, 1), 1)
	local fx = part:GetAttribute("Effects") or ""
	v.fx.Text = fx ~= "" and fx:gsub(",", " · ") or ""
	v.title.Text = string.format("%s%s Lv%d", part:GetAttribute("Boss") and "👑 " or part:GetAttribute("Elite") and "★ " or "", Monsters.Species[part:GetAttribute("Species")].Name, part:GetAttribute("Level") or 1)

	-- follow the server part smoothly (it moves at 10 Hz)
	local target = part.CFrame * CFrame.new(0, (v.baseSize.Y - part.Size.Y) / 2, 0)
	if not v.cf or (v.cf.Position - target.Position).Magnitude > 30 then
		v.cf = target
	else
		v.cf = v.cf:Lerp(target, 1 - math.exp(-14 * dt))
	end
	local cf = v.cf :: CFrame
	local h = v.baseSize.Y
	local off = CFrame.identity
	local transp = 0
	local uniform = 1
	local sF, sU = 1, 1
	local ld: Vector3? = nil

	-- the die/faint event may set these slightly ahead (to wait for the killing blow)
	if state == "dead" and not v.deadAt then
		v.deadAt = now
	elseif state ~= "dead" and v.deadAt and now - v.deadAt > 1 then
		v.deadAt = nil
	end
	if state == "fainted" and not v.faintAt then
		v.faintAt = now
	elseif state ~= "fainted" and v.faintAt and now - v.faintAt > 1 then
		v.faintAt = nil
	end

	if v.deadAt and now >= v.deadAt then
		-- collapse: tip over, sink, shrink, fade
		local k = smooth((now - v.deadAt) / 0.7)
		off = CFrame.new(0, -0.3 * h * k, 0) * CFrame.Angles(0, 0, rad(75) * k)
		uniform = 1 - 0.45 * k
		transp = 0.15 + 0.85 * k
		v.anim = nil
	elseif v.faintAt then
		local k = smooth((now - v.faintAt) / 0.35)
		off = CFrame.new(0, -h * 0.3 * k, 0) * CFrame.Angles(0, 0, rad(80) * k)
		transp = 0.35 * k
		v.anim = nil
	else
		if state == "move" then
			off = CFrame.new(0, math.abs(math.sin(now * 10 + v.seed)) * 0.12 * h, 0) * CFrame.Angles(rad(-4), 0, math.sin(now * 10 + v.seed) * 0.08)
		elseif state == "stunned" then
			off = CFrame.Angles(0, math.sin(now * 20) * 0.2, 0) * CFrame.Angles(0, 0, math.sin(now * 13) * 0.08)
		else
			-- idle: slow breathing
			local b = math.sin(now * 2.4 + v.seed)
			off = CFrame.new(0, b * 0.03 * h, 0)
			sU = 1 + b * 0.02
		end
		if v.anim then
			local aoff, f, u = attackPose(v, now, h)
			off = aoff * off
			sF, sU = f, sU * u
			if v.anim then
				ld = flat(cf:VectorToObjectSpace(v.anim.dir))
			end
		end
	end

	-- spawn pop-in
	local age = now - v.born
	if age < 0.4 then
		uniform *= lerp(0.2, 1, backOut(age / 0.4))
	end
	-- knockback (decays) and hit shake
	if v.knock.Magnitude > 0.01 then
		off = CFrame.new(v.knock) * off
		v.knock *= math.exp(-9 * dt)
	end
	if v.shake > 0 then
		v.shake = math.max(0, v.shake - dt * 6)
		off = CFrame.new((math.random() - 0.5) * 0.3 * v.shake, 0, (math.random() - 0.5) * 0.3 * v.shake) * off
	end
	setScale(v, ld, sF, sU, uniform)
	if math.abs(transp - v.lastTransp) > 0.01 then
		v.lastTransp = transp
		v.body.Transparency = transp
	end
	-- keep the feet on the ground while squashing
	v.body.CFrame = cf * CFrame.new(0, (v.lastScale.Y - 1) * h / 2, 0) * off
end

----------------------------------------------------------------------------------------------
-- Combat feedback

local function viewByKey(key: string): View?
	local units = workspace:FindFirstChild("Units")
	local part = units and units:FindFirstChild(key)
	return part and views[part :: BasePart] or nil
end

local function positionOf(key: string): Vector3?
	if string.sub(key, 1, 1) == "p" then
		local id = tonumber(string.sub(key, 2))
		local plr = id and Players:GetPlayerByUserId(id)
		local hrp = plr and plr.Character and plr.Character:FindFirstChild("HumanoidRootPart")
		return hrp and (hrp :: BasePart).Position + Vector3.new(0, 1.5, 0)
	end
	local v = viewByKey(key)
	if v then
		return v.body.Position + Vector3.new(0, v.baseSize.Y * 0.15, 0)
	end
	local units = workspace:FindFirstChild("Units")
	local part = units and units:FindFirstChild(key) :: BasePart?
	return part and part.Position + Vector3.new(0, part.Size.Y / 2, 0)
end

local function playerOfKey(key: any): Player?
	if type(key) ~= "string" or string.sub(key, 1, 1) ~= "p" then
		return nil
	end
	local id = tonumber(string.sub(key, 2))
	return id and Players:GetPlayerByUserId(id) or nil
end

function UnitView.popText(pos: Vector3, msg: string, color: Color3, big: boolean?)
	local side = (math.random() - 0.5) * 2.4
	local a = CombatFx.anchor(pos + Vector3.new(side * 0.4, 0, 0), 1.3)
	local bb = Instance.new("BillboardGui")
	bb.Size = UDim2.fromOffset(big and 160 or 110, big and 50 or 34)
	bb.AlwaysOnTop = true
	bb.LightInfluence = 0
	bb.MaxDistance = 120
	bb.Parent = a
	local l = Theme.text({ Size = UDim2.fromScale(1, 1), Text = msg, TextColor3 = color, TextStrokeTransparency = 0, TextStrokeColor3 = Color3.new(1, 1, 1), Rotation = big and (math.random() - 0.5) * 16 or 0, Parent = bb }, "Title")
	local sc = Instance.new("UIScale")
	sc.Scale = big and 2.1 or 1.6
	sc.Parent = l
	TweenService:Create(sc, TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	TweenService:Create(bb, TweenInfo.new(1.1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { StudsOffset = Vector3.new(side, big and 3.6 or 2.8, 0) }):Play()
	task.delay(0.65, function()
		TweenService:Create(l, TweenInfo.new(0.45), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
		TweenService:Create(sc, TweenInfo.new(0.45), { Scale = 0.7 }):Play()
	end)
end

local activeFlashes = 0
local function flashView(v: View, color: Color3)
	if v.hl then
		local hl = v.hl
		hl.FillColor = color
		hl.FillTransparency = 0.25
		TweenService:Create(hl, TweenInfo.new(0.2), { FillTransparency = v.hlFill }):Play()
		task.delay(0.2, function()
			if hl.Parent then
				hl.FillColor = Config.ElementInfo[v.part:GetAttribute("Element")].Color
			end
		end)
		return
	end
	if activeFlashes >= 10 then
		return
	end
	activeFlashes += 1
	local hl = Instance.new("Highlight")
	hl.FillColor = color
	hl.FillTransparency = 0.2
	hl.OutlineTransparency = 1
	hl.DepthMode = Enum.HighlightDepthMode.Occluded
	hl.Adornee = v.body
	hl.Parent = v.body
	TweenService:Create(hl, TweenInfo.new(0.16), { FillTransparency = 1 }):Play()
	task.delay(0.17, function()
		activeFlashes -= 1
		hl:Destroy()
	end)
end

local charFlash: { [Model]: Highlight } = {}
local function flashCharacter(plr: Player)
	local char = plr.Character
	if not char then
		return
	end
	local hl = charFlash[char]
	if not hl or not hl.Parent then
		hl = Instance.new("Highlight")
		hl.FillColor = Color3.fromRGB(255, 70, 70)
		hl.OutlineTransparency = 1
		hl.FillTransparency = 1
		hl.DepthMode = Enum.HighlightDepthMode.Occluded
		hl.Parent = char
		charFlash[char] = hl
	end
	hl.FillTransparency = 0.45
	TweenService:Create(hl, TweenInfo.new(0.22), { FillTransparency = 1 }):Play()
end

-- Hit feedback on a unit or player, `from` = where the blow came from (for knockback).
local function showHit(e, from: Vector3?)
	local key = e[2]
	local pos = positionOf(key)
	if not pos then
		return
	end
	local adv = e[6] or 1
	local crit = e[4]
	local plr = playerOfKey(key)
	local v = viewByKey(key)
	local ally = plr ~= nil or (v ~= nil and v.part:GetAttribute("Side") == "team")
	local color = crit and Color3.fromRGB(255, 120, 60) or (adv > 1 and Color3.fromRGB(255, 80, 80) or adv < 1 and C.Sub or C.Ink)
	if ally then
		color = Color3.fromRGB(230, 70, 70)
	end
	UnitView.popText(pos, (crit and "CRIT " or "") .. tostring(e[3]) .. (adv > 1 and not ally and "!" or ""), color, crit)
	local el = e[5]
	local hitAt = pos
	if from then
		-- spark on the side facing the attacker
		local d = flat(from - pos)
		hitAt = pos + d * (v and v.baseSize.X * 0.3 or 0.8)
	end
	CombatFx.impact(hitAt, el ~= "None" and el or nil, crit and 1.3 or 0.8)
	if v then
		flashView(v, crit and Color3.fromRGB(255, 220, 160) or Color3.new(1, 1, 1))
		v.shake = crit and 1 or 0.6
		if from and v.cf then
			local away = flat(pos - from)
			local push = (v.part:GetAttribute("Boss") and 0.08 or 0.22) * v.baseSize.Y * (crit and 1.6 or 1)
			v.knock += (v.cf :: CFrame):VectorToObjectSpace(away) * push
		end
	elseif plr then
		flashCharacter(plr)
		if plr == player then
			CombatFx.shake(crit and 1.2 or 0.55, 0.2)
		end
	end
end

-- Starts a unit's attack animation. Returns (seconds to impact, seconds to projectile release).
local function startCast(v: View, tier: number, at: Vector3?, ranged: boolean): (number, number)
	local now = os.clock()
	local dir = flat(((at or v.part.Position) - v.part.Position))
	local prev = v.anim
	if tier == 3 then
		local charged = prev and prev.kind == "charge"
		local pre = charged and 0 or 0.3
		local rel = ranged and 0.45 or 0.6
		v.anim = { kind = "ult", t0 = now, dur = pre + rel, tier = 3, dir = dir, pre = pre, ranged = ranged }
		if v.aura then
			v.aura.Rate = 50
		end
		if ranged then
			return pre + 0.05, pre + 0.05
		end
		return pre + rel * 0.45, pre + rel * 0.45
	end
	if ranged then
		local dur = tier == 2 and 0.6 or 0.5
		v.anim = { kind = "ranged", t0 = now, dur = dur, tier = tier, dir = dir, pre = 0, ranged = true }
		return dur * 0.38, dur * 0.38
	end
	local dur = tier == 2 and 0.55 or 0.42
	v.anim = { kind = "melee", t0 = now, dur = dur, tier = tier, dir = dir, pre = 0, ranged = false }
	return dur * 0.42, dur * 0.42
end

-- Effects where a unit's skill lands.
local function landCast(tier: number, at: Vector3, el: string, radius: number, from: Vector3, ranged: boolean, size: number)
	local color = CombatFx.color(el)
	if radius > 0 then
		CombatFx.shockwave(at, radius, color, tier == 3 and 0.55 or 0.4)
		CombatFx.impact(at + Vector3.new(0, 1, 0), el, tier == 3 and 2.4 or 1.5)
		CombatFx.shakeAt(at, tier == 3 and 1.8 or 0.6, tier == 3 and 0.35 or 0.2, 45)
		if tier == 3 and not ranged then
			CombatFx.debris(at, Color3.fromRGB(150, 140, 125), 10, radius * 0.6)
		end
	elseif tier == 3 then
		CombatFx.impact(at, el, 2.2)
		CombatFx.shockwave(at, 5, color, 0.4)
		CombatFx.shakeAt(at, 1.2, 0.3, 40)
	elseif not ranged then
		-- claw / bite swipe across the target
		local d = flat(at - from)
		local cf = CFrame.lookAt(at - d * 1.5, at) * CFrame.new(0, 0.3, 0)
		local r = math.clamp(size * 0.45, 1.6, 4.5)
		local tilt = (math.random() < 0.5 and -1 or 1) * rad(35 + math.random() * 25)
		CombatFx.slash(cf, r, CombatFx.light(el), rad(-55), rad(55), 0.06, tilt, tier == 2 and 0.9 or 0.6)
	end
end

function UnitView.onEvents(list)
	local now = os.clock()
	-- the latest attack in this batch; hits that follow it (near its target) wait for its strike
	local ctx: { delay: number, from: Vector3?, at: Vector3?, reach: number }? = nil
	local hitDelay: { [string]: number } = {}

	local function later(d: number, fn: () -> ())
		if d > 0.01 then
			task.delay(d, fn)
		else
			fn()
		end
	end

	local function ctxFor(key: string): (number, Vector3?)
		if not ctx then
			return 0, nil
		end
		local c = ctx
		if c.at then
			local p = positionOf(key)
			if p and (Vector3.new(p.X, 0, p.Z) - Vector3.new(c.at.X, 0, c.at.Z)).Magnitude > c.reach then
				return 0, nil
			end
		end
		return c.delay, c.from
	end

	for _, e in list do
		local kind = e[1]
		if kind == "cast" then
			local v = viewByKey(e[2])
			local tier, at, el, radius = e[3], e[5] :: Vector3?, e[6], e[7] or 0
			local info = Config.ElementInfo[el] or Config.ElementInfo.Fire
			if v and at then
				local sp = Monsters.Species[v.part:GetAttribute("Species")]
				local ranged = sp ~= nil and sp.Range == "ranged"
				local impact, release = startCast(v, tier, at, ranged)
				local from = v.part.Position
				local delay = impact
				if ranged then
					local h = v.baseSize.Y
					local d = flat(at - from)
					local muzzle = v.body.Position + d * (v.baseSize.Z * 0.4) + Vector3.new(0, h * 0.15, 0)
					local size = tier == 3 and 2.4 or tier == 2 and 1.4 or 0.9
					local tt = math.clamp((at - muzzle).Magnitude / 95, 0.08, 0.45)
					delay = release + tt
					task.delay(release, function()
						CombatFx.flash(muzzle, info.Light, size * 1.4)
						CombatFx.projectile(muzzle, at, info.Color, size, "orb", tier == 3 and 0 or nil, function()
							landCast(tier, at, el, radius, from, true, v.baseSize.Y)
						end)
					end)
				else
					task.delay(impact, function()
						landCast(tier, at, el, radius, from, false, v.baseSize.Y)
					end)
				end
				if tier == 3 then
					UnitView.popText(v.part.Position + Vector3.new(0, v.part.Size.Y + 1, 0), e[4], info.Color, true)
				end
				ctx = { delay = delay, from = from, at = at, reach = radius + 8 }
			else
				-- caster not drawn (far away): show where it lands, right away
				if at and radius > 0 then
					CombatFx.shockwave(at, radius, info.Color, 0.4)
				end
				ctx = nil
			end
		elseif kind == "telegraph" then
			CombatFx.telegraph(e[3], e[4], e[5])
			local v = viewByKey(e[2])
			if v then
				v.anim = { kind = "charge", t0 = now, dur = e[5], tier = 3, dir = flat(e[3] - v.part.Position), pre = 0, ranged = false }
				if v.aura then
					v.aura.Rate = 50
				end
			end
		elseif kind == "swing" or kind == "shot" or kind == "wskill" then
			local plr = playerOfKey(e[2])
			local d = TamerAnim.effects(plr, e)
			local at, reach
			if kind == "swing" then
				local w = Config.Tuning.Weapons[e[5]] or Config.Tuning.Weapons.Blade
				at, reach = e[3] + e[4] * (w.Range / 2), w.Range + 6
			elseif kind == "shot" then
				at, reach = e[4], 8
			else
				at, reach = e[3], (e[5] or 10) + 6
			end
			ctx = { delay = d, from = e[3], at = at, reach = reach }
		elseif kind == "hit" then
			local d, from = ctxFor(e[2])
			hitDelay[e[2]] = math.max(hitDelay[e[2]] or 0, d)
			local v = viewByKey(e[2])
			if v and d > 0 then
				v.holdUntil = math.max(v.holdUntil, now + d)
			end
			later(d, function()
				showHit(e, from)
			end)
		elseif kind == "heal" then
			local d = ctxFor(e[2])
			later(d, function()
				local pos = positionOf(e[2])
				if pos then
					UnitView.popText(pos, "+" .. tostring(e[3]), Color3.fromRGB(40, 170, 110))
					CombatFx.burst(pos, Color3.fromRGB(120, 230, 170), 6, 4, { size = 0.5, life = 0.7, gravity = 6 })
				end
			end)
		elseif kind == "miss" then
			local d = ctxFor(e[2])
			later(d, function()
				local pos = positionOf(e[2])
				if pos then
					UnitView.popText(pos, "Dodged!", C.Sky)
				end
			end)
		elseif kind == "faint" or kind == "die" then
			local d = hitDelay[e[2]] or 0
			local v = viewByKey(e[2])
			if v then
				v.deadAt = kind == "die" and now + d or v.deadAt
				v.faintAt = kind == "faint" and now + d or v.faintAt
			end
			later(d, function()
				local pos = positionOf(e[2])
				if pos then
					local el = v and v.part:GetAttribute("Element")
					CombatFx.burst(pos, Color3.fromRGB(235, 235, 245), 16, 7, { texture = "smoke", size = 2, life = 0.8, emission = 0, gravity = 3 })
					CombatFx.burst(pos, CombatFx.light(el), 12, 5, { size = 0.6, life = 1.2, gravity = 9, spread = Vector2.new(30, 30) })
				end
			end)
		elseif kind == "revive" then
			local pos = positionOf(e[2])
			if pos then
				CombatFx.pillar(pos, C.Mint, 2, 10)
				UnitView.popText(pos, "Back up!", C.Mint)
			end
		end
	end
end

----------------------------------------------------------------------------------------------

function UnitView.start()
	local folder = workspace:WaitForChild("Units")
	local known: { [BasePart]: boolean } = {}
	for _, p in folder:GetChildren() do
		known[p] = true
	end
	folder.ChildAdded:Connect(function(p)
		known[p] = true
	end)
	folder.ChildRemoved:Connect(function(p)
		known[p] = nil
		removeView(p)
	end)
	-- level of detail: only nearby units get a model (keeps the runtime mesh pool small)
	task.spawn(function()
		while true do
			local cam = workspace.CurrentCamera
			local char = player.Character
			local hrp = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
			local focus = hrp and hrp.Position or (cam and cam.CFrame.Position) or Vector3.zero
			for p in known do
				local d = (p.Position - focus).Magnitude
				local mine = p:GetAttribute("Owner") == player.UserId
				local want = mine or d < (p:GetAttribute("Boss") and 260 or 170)
				if want and not views[p] then
					task.spawn(addView, p)
				elseif not want and views[p] and d > 200 then
					local v = views[p]
					v.deadAt = nil
					removeView(p)
				end
			end
			task.wait(0.4)
		end
	end)
	RunService.RenderStepped:Connect(function(dt)
		local t = os.clock()
		for part, v in views do
			if part.Parent then
				updateView(v, dt, t)
			end
		end
	end)
end

-- Kept for other modules.
UnitView.ring = function(pos: Vector3, radius: number, color: Color3, life: number, grow: boolean?)
	if grow then
		CombatFx.telegraph(pos, radius, life)
	else
		CombatFx.shockwave(pos, radius, color, life)
	end
end
UnitView.burst = function(pos: Vector3, color: Color3, n: number, speed: number)
	CombatFx.burst(pos, color, n, speed)
end
UnitView.bolt = function(from: Vector3, to: Vector3, color: Color3, size: number)
	CombatFx.projectile(from, to, color, size, "orb")
end
UnitView.positionOf = positionOf
return UnitView

-- Reusable combat visuals: element impacts, projectiles with trails, slash arcs, shockwaves,
-- telegraph discs, ground debris and a gentle camera shake. Everything is client-only and
-- cleans itself up with Debris.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local CombatFx = {}

local folder = workspace:FindFirstChild("CombatFx") or Instance.new("Folder")
folder.Name = "CombatFx"
folder.Parent = workspace
CombatFx.folder = folder

local TEX = {
	sparkle = "rbxasset://textures/particles/sparkles_main.dds",
	fire = "rbxasset://textures/particles/fire_main.dds",
	smoke = "rbxasset://textures/particles/smoke_main.dds",
}

local function ease(x: number): number -- out quad
	return 1 - (1 - x) * (1 - x)
end

function CombatFx.color(el: string?): Color3
	local info = el and Config.ElementInfo[el]
	return info and info.Color or Color3.fromRGB(235, 238, 248)
end

function CombatFx.light(el: string?): Color3
	local info = el and Config.ElementInfo[el]
	return info and info.Light or Color3.new(1, 1, 1)
end

local function fxPart(props): BasePart
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Material = Enum.Material.Neon
	for k, v in props do
		(p :: any)[k] = v
	end
	p.Parent = folder
	return p
end

function CombatFx.anchor(pos: Vector3, life: number): BasePart
	local p = fxPart({ Transparency = 1, Size = Vector3.new(0.2, 0.2, 0.2), Position = pos })
	Debris:AddItem(p, life)
	return p
end

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
function CombatFx.groundY(pos: Vector3): number
	local skip = { folder }
	for _, n in { "Units", "UnitViews" } do
		local f = workspace:FindFirstChild(n)
		if f then
			table.insert(skip, f)
		end
	end
	for _, plr in Players:GetPlayers() do
		if plr.Character then
			table.insert(skip, plr.Character)
		end
	end
	rayParams.FilterDescendantsInstances = skip
	local hit = workspace:Raycast(pos + Vector3.new(0, 8, 0), Vector3.new(0, -30, 0), rayParams)
	return hit and hit.Position.Y or pos.Y - 2
end

-- Particles thrown out from a point. opts: texture, size, life, gravity, spread, drag, emission
function CombatFx.burst(pos: Vector3, color: Color3, n: number, speed: number, opts: { [string]: any }?)
	local o = opts or {}
	local a = CombatFx.anchor(pos, 3)
	local e = Instance.new("ParticleEmitter")
	e.Texture = TEX[o.texture or "sparkle"] or TEX.sparkle
	e.Color = ColorSequence.new(color, o.color2 or color)
	e.Speed = NumberRange.new(speed * 0.45, speed)
	e.SpreadAngle = o.spread or Vector2.new(180, 180)
	e.Lifetime = NumberRange.new((o.life or 0.6) * 0.6, o.life or 0.6)
	e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, o.size or 0.7), NumberSequenceKeypoint.new(1, 0) })
	e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 1) })
	e.LightEmission = o.emission or 0.6
	e.Drag = o.drag or 3
	e.Acceleration = Vector3.new(0, o.gravity or 0, 0)
	e.Rotation = NumberRange.new(0, 360)
	e.RotSpeed = NumberRange.new(-180, 180)
	e.EmissionDirection = o.dir or Enum.NormalId.Top
	e.Rate = 0
	e.Parent = a
	e:Emit(n)
end

-- A bright ball that pops and fades (hit spark), with a short light.
function CombatFx.flash(pos: Vector3, color: Color3, size: number)
	local b = fxPart({ Shape = Enum.PartType.Ball, Color = color, Size = Vector3.one * size * 0.4, Position = pos, Transparency = 0.05 })
	local l = Instance.new("PointLight")
	l.Color = color
	l.Range = size * 4
	l.Brightness = 3
	l.Parent = b
	TweenService:Create(b, TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = Vector3.one * size, Transparency = 1 }):Play()
	TweenService:Create(l, TweenInfo.new(0.2), { Brightness = 0 }):Play()
	Debris:AddItem(b, 0.25)
end

-- Thin ring that races outward from the centre and fades (shockwave), hugging the ground,
-- with a quick faint fill so the area reads for a moment.
function CombatFx.shockwave(pos: Vector3, radius: number, color: Color3, life: number?)
	local life2 = life or 0.45
	local y = CombatFx.groundY(pos) + 0.25
	local centre = Vector3.new(pos.X, y, pos.Z)
	local n = math.clamp(math.floor(radius * 2.2), 14, 36)
	local segs = {}
	for i = 1, n do
		segs[i] = fxPart({ Color = color, Transparency = 0.1, Size = Vector3.new(0.2, 0.35, 1) })
	end
	local fill = fxPart({
		Shape = Enum.PartType.Cylinder,
		Color = color,
		Transparency = 0.7,
		Size = Vector3.new(0.08, radius * 2, radius * 2),
		CFrame = CFrame.new(centre - Vector3.new(0, 0.18, 0)) * CFrame.Angles(0, 0, math.rad(90)),
	})
	TweenService:Create(fill, TweenInfo.new(life2 * 0.6), { Transparency = 1 }):Play()
	Debris:AddItem(fill, life2)
	local start = os.clock()
	local conn
	conn = RunService.RenderStepped:Connect(function()
		local t = (os.clock() - start) / life2
		if t >= 1 then
			conn:Disconnect()
			for _, p in segs do
				p:Destroy()
			end
			return
		end
		local k = 1 - (1 - t) ^ 4
		local r = radius * (0.15 + 0.9 * k)
		local chord = 2 * math.pi * r / n * 1.08
		local thick = 0.7 * (1 - t) + 0.15
		local tr = 0.1 + 0.9 * t * t
		for i, p in segs do
			local a = (i / n) * math.pi * 2
			p.Size = Vector3.new(thick, 0.3 + 0.5 * (1 - t), chord)
			p.CFrame = CFrame.new(centre) * CFrame.Angles(0, a, 0) * CFrame.new(r, 0, 0)
			p.Transparency = tr
		end
	end)
end

-- Danger zone for an incoming ultimate: a faint disc at full size plus a fill that grows
-- to the edge exactly when the hit lands.
function CombatFx.telegraph(pos: Vector3, radius: number, time: number)
	local y = CombatFx.groundY(pos) + 0.12
	local cf = CFrame.new(pos.X, y, pos.Z) * CFrame.Angles(0, 0, math.rad(90))
	local red = Color3.fromRGB(255, 70, 70)
	local zone = fxPart({ Shape = Enum.PartType.Cylinder, Color = red, Transparency = 0.82, Size = Vector3.new(0.1, radius * 2, radius * 2), CFrame = cf })
	local fill = fxPart({ Shape = Enum.PartType.Cylinder, Color = red, Transparency = 0.45, Size = Vector3.new(0.14, 0.5, 0.5), CFrame = cf + Vector3.new(0, 0.03, 0) })
	TweenService:Create(fill, TweenInfo.new(time, Enum.EasingStyle.Linear), { Size = Vector3.new(0.14, radius * 2, radius * 2) }):Play()
	-- thin border so the edge is obvious
	local n = math.clamp(math.floor(radius * 2.4), 16, 40)
	local chord = 2 * math.pi * radius / n * 1.06
	local border = {}
	for i = 1, n do
		local a = (i / n) * math.pi * 2
		border[i] = fxPart({ Color = Color3.fromRGB(255, 90, 90), Transparency = 0.15, Size = Vector3.new(0.35, 0.18, chord), CFrame = CFrame.new(pos.X, y + 0.06, pos.Z) * CFrame.Angles(0, a, 0) * CFrame.new(radius, 0, 0) })
		Debris:AddItem(border[i], time + 0.05)
	end
	local edge = border[1]
	-- pulse the zone so it reads as a warning
	local start = os.clock()
	local conn
	conn = RunService.RenderStepped:Connect(function()
		local k = os.clock() - start
		if k > time or not zone.Parent then
			conn:Disconnect()
			return
		end
		zone.Transparency = 0.78 + 0.07 * math.sin(k * 14)
	end)
	local _ = edge
	zone.Name = "Telegraph"
	for _, p in { zone, fill } do
		Debris:AddItem(p, time + 0.05)
	end
end

-- Crescent slash: segments appear along an arc around `cf` (centre, facing its LookVector),
-- sweeping from angle a0 to a1 (radians, 0 = straight ahead, + = to the left), then fade.
-- tilt rolls the arc plane (0 = flat, pi/2 = vertical).
function CombatFx.slash(cf: CFrame, radius: number, color: Color3, a0: number, a1: number, dur: number, tilt: number?, width: number?)
	local n = 11
	local base = cf * CFrame.Angles(0, 0, tilt or 0)
	local seg = math.abs(a1 - a0) / n * radius * 1.25
	local w = width or 0.9
	for i = 0, n - 1 do
		local k = i / (n - 1)
		local a = a0 + (a1 - a0) * k
		local taper = math.sin(k * math.pi) * 0.8 + 0.2
		task.delay(dur * k, function()
			local pcf = base * CFrame.Angles(0, a, 0) * CFrame.new(0, 0, -radius)
			local p = fxPart({ Color = color, Transparency = 0.15, Size = Vector3.new(seg, w * taper, 0.12), CFrame = pcf })
			TweenService:Create(p, TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Transparency = 1, Size = Vector3.new(seg, 0.05, 0.12) }):Play()
			Debris:AddItem(p, 0.25)
		end)
	end
end

-- Small chips of ground kicked up (hammer slams, monster landings), coloured like the ground.
function CombatFx.debris(pos: Vector3, color: Color3, n: number, spread: number)
	local y = CombatFx.groundY(pos)
	local hit = workspace:Raycast(Vector3.new(pos.X, y + 2, pos.Z), Vector3.new(0, -5, 0), rayParams)
	local ground = color
	local mat = Enum.Material.Slate
	if hit and hit.Instance then
		if hit.Instance:IsA("Terrain") then
			ground = (hit.Instance :: Terrain):GetMaterialColor(hit.Material)
		else
			ground = hit.Instance.Color
		end
		mat = hit.Material
	end
	for _ = 1, n do
		local s = 0.15 + math.random() * 0.25
		local p = Instance.new("Part")
		p.Size = Vector3.new(s, s * 0.7, s)
		p.Color = ground:Lerp(Color3.new(0, 0, 0), 0.15)
		p.Material = mat
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.Anchored = true
		p.CastShadow = false
		local ang = math.random() * math.pi * 2
		local r = math.random() * spread * 0.3
		local from = Vector3.new(pos.X + math.cos(ang) * r, y + 0.1, pos.Z + math.sin(ang) * r)
		local out = Vector3.new(math.cos(ang), 0, math.sin(ang)) * (spread * (0.25 + math.random() * 0.35))
		local up = 1.5 + math.random() * 2.5
		local life = 0.45 + math.random() * 0.15
		p.Position = from
		p.Parent = folder
		local start = os.clock()
		local spin = CFrame.Angles(math.random() * 6, math.random() * 6, 0)
		local conn
		conn = RunService.RenderStepped:Connect(function()
			local t = (os.clock() - start) / life
			if t >= 1 or not p.Parent then
				conn:Disconnect()
				p:Destroy()
				return
			end
			local h = up * 4 * t * (1 - t)
			p.CFrame = CFrame.new(from + out * t + Vector3.new(0, h, 0)) * spin:Lerp(CFrame.identity, 1 - t)
			p.Transparency = math.max(0, (t - 0.75) / 0.25)
		end)
	end
	CombatFx.burst(Vector3.new(pos.X, y + 0.4, pos.Z), ground:Lerp(Color3.new(1, 1, 1), 0.5), 10, spread * 1.2, { texture = "smoke", size = 1.6, life = 0.6, emission = 0, gravity = 2, spread = Vector2.new(75, 75) })
end

-- Element-flavoured impact at a point. scale ~1 for normal hits, 2+ for ultimates.
function CombatFx.impact(pos: Vector3, el: string?, scale: number)
	local c, l = CombatFx.color(el), CombatFx.light(el)
	CombatFx.flash(pos, l, 1.6 * scale)
	if el == "Fire" then
		CombatFx.burst(pos, c, math.floor(10 * scale), 9 * scale, { texture = "fire", color2 = Color3.fromRGB(255, 220, 120), size = 1.2 * scale, life = 0.45, gravity = 8 })
	elseif el == "Water" then
		CombatFx.burst(pos, l, math.floor(12 * scale), 12 * scale, { size = 0.5 * scale, life = 0.6, gravity = -40, drag = 1, spread = Vector2.new(60, 60) })
	elseif el == "Wind" then
		CombatFx.burst(pos, l, math.floor(10 * scale), 14 * scale, { size = 0.6 * scale, life = 0.45, drag = 6, spread = Vector2.new(180, 20) })
	elseif el == "Light" then
		CombatFx.burst(pos, Color3.new(1, 1, 0.9), math.floor(14 * scale), 12 * scale, { size = 0.9 * scale, life = 0.5, emission = 1 })
	elseif el == "Dark" then
		CombatFx.burst(pos, c, math.floor(8 * scale), 6 * scale, { texture = "smoke", color2 = Color3.fromRGB(40, 20, 70), size = 1.8 * scale, life = 0.6, emission = 0.3 })
	else
		CombatFx.burst(pos, Color3.new(1, 1, 1), math.floor(8 * scale), 9 * scale, { size = 0.6 * scale, life = 0.35 })
	end
end

-- Projectile from `from` to `to`. kind: "orb" (element ball with trail) or "arrow".
-- Calls onHit when it lands. Returns the travel time.
function CombatFx.projectile(from: Vector3, to: Vector3, color: Color3, size: number, kind: string?, arc: number?, onHit: (() -> ())?): number
	local dist = (to - from).Magnitude
	local tt = math.clamp(dist / (kind == "arrow" and 150 or 95), 0.08, 0.45)
	local p
	if kind == "arrow" then
		p = fxPart({ Color = Color3.fromRGB(245, 240, 225), Material = Enum.Material.SmoothPlastic, Size = Vector3.new(0.12, 0.12, 2.2), CFrame = CFrame.lookAt(from, to) })
		local tip = fxPart({ Color = color, Size = Vector3.new(0.25, 0.25, 0.45), CFrame = p.CFrame * CFrame.new(0, 0, -1.2) })
		local w = Instance.new("WeldConstraint")
		w.Part0 = p
		w.Part1 = tip
		w.Parent = p
		tip.Anchored = false
		tip.Parent = p
	else
		p = fxPart({ Shape = Enum.PartType.Ball, Color = color, Size = Vector3.one * size, Position = from })
		local l = Instance.new("PointLight")
		l.Color = color
		l.Range = size * 5
		l.Brightness = 2
		l.Parent = p
		local e = Instance.new("ParticleEmitter")
		e.Texture = TEX.sparkle
		e.Color = ColorSequence.new(color)
		e.Size = NumberSequence.new(size * 0.6, 0)
		e.Lifetime = NumberRange.new(0.2, 0.35)
		e.Speed = NumberRange.new(0.5, 1.5)
		e.Rate = 60
		e.LightEmission = 0.7
		e.Parent = p
	end
	local a0 = Instance.new("Attachment")
	a0.Position = Vector3.new(0, size * 0.35, 0)
	a0.Parent = p
	local a1 = Instance.new("Attachment")
	a1.Position = Vector3.new(0, -size * 0.35, 0)
	a1.Parent = p
	local tr = Instance.new("Trail")
	tr.Attachment0 = a0
	tr.Attachment1 = a1
	tr.Color = ColorSequence.new(color)
	tr.Transparency = NumberSequence.new(0.15, 1)
	tr.Lifetime = 0.18
	tr.LightEmission = 0.7
	tr.FaceCamera = true
	tr.WidthScale = NumberSequence.new(1, 0)
	tr.Parent = p
	local h = arc or dist * 0.06
	local start = os.clock()
	local conn
	conn = RunService.RenderStepped:Connect(function()
		local t = math.min(1, (os.clock() - start) / tt)
		local pos = from:Lerp(to, t) + Vector3.new(0, h * 4 * t * (1 - t), 0)
		local ahead = from:Lerp(to, math.min(1, t + 0.05)) + Vector3.new(0, h * 4 * math.min(1, t + 0.05) * (1 - math.min(1, t + 0.05)), 0)
		if (ahead - pos).Magnitude > 0.01 then
			p.CFrame = CFrame.lookAt(pos, ahead)
		else
			p.Position = pos
		end
		if t >= 1 then
			conn:Disconnect()
			p.Transparency = 1
			for _, d in p:GetDescendants() do
				if d:IsA("BasePart") then
					d.Transparency = 1
				elseif d:IsA("ParticleEmitter") then
					d.Enabled = false
				end
			end
			Debris:AddItem(p, 0.3)
			if onHit then
				onHit()
			end
		end
	end)
	return tt
end

-- Rising column of light (heals, revives).
function CombatFx.pillar(pos: Vector3, color: Color3, radius: number, height: number)
	local y = CombatFx.groundY(pos)
	local c = fxPart({ Shape = Enum.PartType.Cylinder, Color = color, Transparency = 0.35, Size = Vector3.new(0.5, radius * 2, radius * 2), CFrame = CFrame.new(pos.X, y + 0.25, pos.Z) * CFrame.Angles(0, 0, math.rad(90)) })
	TweenService:Create(c, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = Vector3.new(height, radius * 1.4, radius * 1.4), CFrame = CFrame.new(pos.X, y + height / 2, pos.Z) * CFrame.Angles(0, 0, math.rad(90)), Transparency = 1 }):Play()
	Debris:AddItem(c, 0.55)
	CombatFx.burst(Vector3.new(pos.X, y + 1, pos.Z), color, 20, 6, { size = 0.6, life = 1.0, gravity = 10, spread = Vector2.new(25, 25) })
end

----------------------------------------------------------------------------------------------
-- Camera shake (offset is removed before the camera scripts run, so it never drifts)

local shakeAmp, shakeUntil, shakeLen = 0, 0, 1
local applied = CFrame.identity
local seed = math.random() * 100

function CombatFx.shake(amp: number, dur: number)
	local now = os.clock()
	local left = math.max(0, shakeUntil - now) / shakeLen * shakeAmp
	if amp >= left then
		shakeAmp, shakeLen, shakeUntil = amp, dur, now + dur
	end
end

-- Shake scaled by distance from the local player's character.
function CombatFx.shakeAt(pos: Vector3, amp: number, dur: number, range: number?)
	local char = Players.LocalPlayer.Character
	local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return
	end
	local r = range or 40
	local k = 1 - math.clamp((root.Position - pos).Magnitude / r, 0, 1)
	if k > 0 then
		CombatFx.shake(amp * k, dur)
	end
end

RunService:BindToRenderStep("WildShakeUndo", Enum.RenderPriority.First.Value, function()
	local cam = workspace.CurrentCamera
	if cam and applied ~= CFrame.identity then
		cam.CFrame = cam.CFrame * applied:Inverse()
		applied = CFrame.identity
	end
end)
RunService:BindToRenderStep("WildShake", Enum.RenderPriority.Camera.Value + 1, function()
	local cam = workspace.CurrentCamera
	local now = os.clock()
	if not cam or now >= shakeUntil then
		return
	end
	local k = (shakeUntil - now) / shakeLen
	local a = math.rad(shakeAmp) * k * k
	local t = now * 28
	applied = CFrame.Angles(math.noise(t, seed) * a * 2, math.noise(seed, t) * a * 2, math.noise(t, t + seed) * a)
	cam.CFrame = cam.CFrame * applied
end)

CombatFx.ease = ease
return CombatFx

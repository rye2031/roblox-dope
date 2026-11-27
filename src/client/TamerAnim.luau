-- Tamer weapons and attack animations, for every player in view.
-- Weapons are simple parts on the right hand. Attacks are procedural: the shoulder, left arm
-- and waist Motor6D C0s are rotated on top of the default walk/idle animation, so nothing is
-- uploaded. Each attack has a windup, a fast strike and a recovery; `play` returns how long
-- until the strike lands so hit numbers and impacts can wait for it.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local CombatFx = require(script.Parent.CombatFx)

local T = Config.Tuning
local player = Players.LocalPlayer
local TamerAnim = {}

local rad = math.rad
local function smooth(x: number): number
	x = math.clamp(x, 0, 1)
	return x * x * (3 - 2 * x)
end
local function outQuad(x: number): number
	x = math.clamp(x, 0, 1)
	return 1 - (1 - x) * (1 - x)
end
local function lerp(a: number, b: number, k: number): number
	return a + (b - a) * k
end

local WEAPON_COLOR = {
	Blade = Color3.fromRGB(225, 236, 255),
	Staff = Color3.fromRGB(176, 150, 255),
	Hammer = Color3.fromRGB(255, 196, 140),
	Bow = Color3.fromRGB(170, 235, 190),
}
TamerAnim.color = WEAPON_COLOR

----------------------------------------------------------------------------------------------
-- Weapon models

local function weaponModel(kind: string): (Model, { Trail })
	local m = Instance.new("Model")
	m.Name = "TamerWeapon"
	local function piece(name, size, cf, color, material, shape)
		local p = Instance.new("Part")
		p.Name = name
		p.Size = size
		p.CFrame = cf
		p.Color = color
		p.Material = material or Enum.Material.SmoothPlastic
		if shape then
			p.Shape = shape
		end
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.Massless = true
		p.CastShadow = false
		p.Parent = m
		return p
	end
	local trails = {}
	local function trail(part: BasePart, a: Vector3, b: Vector3, color: Color3, life: number)
		local a0 = Instance.new("Attachment")
		a0.Position = a
		a0.Parent = part
		local a1 = Instance.new("Attachment")
		a1.Position = b
		a1.Parent = part
		local t = Instance.new("Trail")
		t.Attachment0 = a0
		t.Attachment1 = a1
		t.Color = ColorSequence.new(color)
		t.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(1, 1) })
		t.Lifetime = life
		t.LightEmission = 0.6
		t.MinLength = 0.05
		t.Enabled = false
		t.Parent = part
		table.insert(trails, t)
	end
	local grip
	if kind == "Blade" then
		grip = piece("Grip", Vector3.new(0.3, 1, 0.3), CFrame.new(), Color3.fromRGB(90, 70, 60))
		piece("Guard", Vector3.new(1.1, 0.2, 0.35), CFrame.new(0, 0.55, 0), Color3.fromRGB(230, 190, 90), Enum.Material.Metal)
		local blade = piece("Blade", Vector3.new(0.35, 3.2, 0.12), CFrame.new(0, 2.25, 0), Color3.fromRGB(225, 232, 245), Enum.Material.Metal)
		trail(blade, Vector3.new(0, -1.2, 0), Vector3.new(0, 1.6, 0), WEAPON_COLOR.Blade, 0.16)
	elseif kind == "Staff" then
		grip = piece("Grip", Vector3.new(0.3, 4.6, 0.3), CFrame.new(0, 1.2, 0), Color3.fromRGB(120, 90, 70), Enum.Material.Wood)
		local orb = piece("Orb", Vector3.new(0.8, 0.8, 0.8), CFrame.new(0, 3.8, 0), WEAPON_COLOR.Staff, Enum.Material.Neon, Enum.PartType.Ball)
		local l = Instance.new("PointLight")
		l.Name = "Glow"
		l.Color = WEAPON_COLOR.Staff
		l.Range = 6
		l.Brightness = 0.6
		l.Parent = orb
		trail(orb, Vector3.new(0, -0.3, 0), Vector3.new(0, 0.3, 0), WEAPON_COLOR.Staff, 0.2)
	elseif kind == "Hammer" then
		grip = piece("Grip", Vector3.new(0.3, 3, 0.3), CFrame.new(0, 0.9, 0), Color3.fromRGB(110, 80, 60), Enum.Material.Wood)
		local head = piece("Head", Vector3.new(1.8, 1.1, 1.1), CFrame.new(0, 2.6, 0), Color3.fromRGB(150, 155, 170), Enum.Material.Metal)
		trail(head, Vector3.new(-0.8, 0, 0), Vector3.new(0.8, 0, 0), WEAPON_COLOR.Hammer, 0.2)
	else -- Bow
		grip = piece("Grip", Vector3.new(0.3, 0.8, 0.3), CFrame.new(), Color3.fromRGB(110, 80, 60), Enum.Material.Wood)
		piece("LimbTop", Vector3.new(0.22, 1.8, 0.22), CFrame.new(0, 1.15, -0.35) * CFrame.Angles(rad(-22), 0, 0), Color3.fromRGB(130, 170, 90), Enum.Material.Wood)
		piece("LimbBottom", Vector3.new(0.22, 1.8, 0.22), CFrame.new(0, -1.15, -0.35) * CFrame.Angles(rad(22), 0, 0), Color3.fromRGB(130, 170, 90), Enum.Material.Wood)
		piece("String", Vector3.new(0.05, 3.9, 0.05), CFrame.new(0, 0, -0.95), Color3.fromRGB(240, 240, 240))
	end
	-- Fixed welds (offset from the grip, set now). A WeldConstraint captures the offset when it
	-- becomes active, which raced the hand motor and left the hammer head floating.
	for _, p in m:GetChildren() do
		if p ~= grip and p:IsA("BasePart") then
			local w = Instance.new("Weld")
			w.Part0 = grip
			w.Part1 = p
			w.C0 = grip.CFrame:ToObjectSpace(p.CFrame)
			w.Parent = p
		end
	end
	m.PrimaryPart = grip
	return m, trails
end

-- A body joint we can bend: classic Motor6D (bend C0) or the newer AnimationConstraint
-- avatar joints (bend the parent-side Attachment0). Both rotate in the parent part's space.
type Joint = { inst: Instance, base: CFrame, set: (CFrame, Vector3?) -> () }
type Rig = { char: Model, rs: Joint?, ls: Joint?, waist: Joint?, root: Joint? }
type Equip = { model: Model, weld: Motor6D, kind: string, trails: { Trail }, base: CFrame }
type Swing = { kind: string, skill: boolean, variant: number, t0: number, dur: number, impact: number, release: number }

local function joint(inst: Instance?): Joint?
	if not inst then
		return nil
	end
	if inst:IsA("Motor6D") then
		local m = inst :: Motor6D
		local base = m.C0
		return { inst = m, base = base, set = function(rot: CFrame, off: Vector3?)
			m.C0 = CFrame.new(base.Position + (off or Vector3.zero)) * rot * base.Rotation
		end }
	elseif inst:IsA("AnimationConstraint") then
		local a0 = (inst :: AnimationConstraint).Attachment0
		if not a0 then
			return nil
		end
		local base = a0.CFrame
		return { inst = inst, base = base, set = function(rot: CFrame, off: Vector3?)
			a0.CFrame = CFrame.new(base.Position + (off or Vector3.zero)) * rot * base.Rotation
		end }
	end
	return nil
end

local equipped: { [Player]: Equip } = {}
local rigs: { [Player]: Rig } = {}
local swings: { [Player]: Swing } = {}
local combo: { [Player]: { n: number, at: number } } = {}
local localStart: { [string]: number } = {}
local dodges: { [Player]: { t0: number, dur: number } } = {} -- "attack"/"skill" -> os.clock() of the predicted local swing

local function rigOf(plr: Player): Rig?
	local char = plr.Character
	if not char then
		return nil
	end
	local r = rigs[plr]
	if r and r.char == char and r.rs and r.rs.inst.Parent then
		return r
	end
	local function find(...): Joint?
		for _, n in { ... } do
			for _, d in char:GetDescendants() do
				if d.Name == n and (d:IsA("Motor6D") or d:IsA("AnimationConstraint")) then
					return joint(d)
				end
			end
		end
		return nil
	end
	local rs = find("RightShoulder", "Right Shoulder")
	if not rs then
		return nil
	end
	r = { char = char, rs = rs, ls = find("LeftShoulder", "Left Shoulder"), waist = find("Waist"), root = find("Root", "RootJoint") }
	rigs[plr] = r
	return r
end

local function gripBase(hand: BasePart, kind: string): CFrame
	local down = hand.Name == "Right Arm" and -1 or -0.15
	if kind == "Bow" then
		return CFrame.new(0, down, -0.1)
	end
	return CFrame.new(0, down, -0.2) * CFrame.Angles(rad(-90), 0, 0)
end

local function equip(plr: Player)
	local char = plr.Character
	local hand = char and (char:FindFirstChild("RightHand") or char:FindFirstChild("Right Arm")) :: BasePart?
	local kind = plr:GetAttribute("Weapon") or "Blade"
	local cur = equipped[plr]
	if cur and cur.kind == kind and cur.model.Parent == char then
		return
	end
	if cur then
		cur.model:Destroy()
		equipped[plr] = nil
	end
	if not hand then
		return
	end
	local m, trails = weaponModel(kind)
	local grip = m.PrimaryPart :: BasePart
	local motor = Instance.new("Motor6D")
	motor.Part0 = hand
	motor.Part1 = grip
	local base = gripBase(hand, kind)
	motor.C0 = base
	motor.Parent = grip
	m:PivotTo(hand.CFrame)
	m.Parent = char
	equipped[plr] = { model = m, weld = motor, kind = kind, trails = trails, base = base }
end

local function watchPlayer(plr: Player)
	plr.CharacterAdded:Connect(function(char)
		char:WaitForChild("HumanoidRootPart", 10)
		char:WaitForChild("RightHand", 3)
		rigs[plr] = nil
		swings[plr] = nil
		equip(plr)
	end)
	plr:GetAttributeChangedSignal("Weapon"):Connect(function()
		equip(plr)
	end)
	if plr.Character then
		task.spawn(equip, plr)
	end
end

----------------------------------------------------------------------------------------------
-- Attack timing. dur = whole move; impact = when the hit lands; release = when a projectile
-- leaves (ranged). All in seconds.

local TIMING = {
	Blade = { dur = 0.36, impact = 0.13 },
	Hammer = { dur = 0.62, impact = 0.3 },
	Staff = { dur = 0.4, impact = 0.12, release = 0.12 },
	Bow = { dur = 0.46, impact = 0.2, release = 0.2 },
}
local SKILL_TIMING = {
	Blade = { dur = 0.6, impact = 0.24 },
	Hammer = { dur = 0.8, impact = 0.42 },
	Staff = { dur = 0.7, impact = 0.3 },
	Bow = { dur = 0.7, impact = 0.25, release = 0.22 },
}

-- Start (or confirm) an attack animation. Returns the seconds left until the strike lands.
-- For the local player the client starts the swing on input; the server's echo then only
-- asks for the remaining time.
function TamerAnim.play(plr: Player, kind: string, skill: boolean, predicted: boolean?): Swing
	local now = os.clock()
	local key = skill and "skill" or "attack"
	if plr == player and not predicted then
		local s = swings[plr]
		local started = localStart[key]
		if s and started and now - started < 0.6 and s.skill == skill then
			localStart[key] = nil
			return s
		end
	end
	local tm = (skill and SKILL_TIMING or TIMING)[kind] or TIMING.Blade
	local variant = 1
	if not skill and kind == "Blade" then
		local c = combo[plr]
		if c and now - c.at < 0.9 then
			c.n = c.n % 3 + 1
		else
			c = { n = 1, at = now }
			combo[plr] = c
		end
		c.at = now
		variant = c.n
	end
	local s: Swing = { kind = kind, skill = skill, variant = variant, t0 = now, dur = tm.dur, impact = tm.impact, release = tm.release or tm.impact }
	swings[plr] = s
	if plr == player and predicted then
		localStart[key] = now
	end
	return s
end

-- Seconds until a swing's impact / release moment (0 if already passed).
function TamerAnim.untilImpact(s: Swing): number
	return math.max(0, s.t0 + s.impact - os.clock())
end
function TamerAnim.untilRelease(s: Swing): number
	return math.max(0, s.t0 + s.release - os.clock())
end

-- Where a projectile leaves from: the staff orb or bow, else the hand.
function TamerAnim.muzzle(plr: Player): Vector3?
	local eq = equipped[plr]
	if eq and eq.model.Parent then
		local tip = eq.model:FindFirstChild("Orb") or eq.model:FindFirstChild("String") or eq.model.PrimaryPart
		return tip and (tip :: BasePart).Position
	end
	return nil
end

----------------------------------------------------------------------------------------------
-- Poses. Returns shoulder rotation (right, left), waist rotation and extra weapon rotation,
-- all in the parent part's space, plus whether trails show.

local function armRot(pitch: number, yaw: number, roll: number?): CFrame
	return CFrame.Angles(0, yaw, 0) * CFrame.Angles(pitch, 0, roll or 0)
end

local function pose(s: Swing, p: number): (CFrame, CFrame?, CFrame, CFrame, boolean)
	local I = CFrame.identity
	local kind = s.kind
	if s.skill then
		if kind == "Blade" then
			-- spin slash: arm out to the side, upper body whirls a full turn
			local out = smooth(p / 0.15) * (1 - smooth((p - 0.8) / 0.2))
			local spin = outQuad((p - 0.12) / 0.55) * math.pi * 2
			return armRot(rad(85) * out, rad(-80) * out), nil, CFrame.Angles(0, spin, 0), CFrame.Angles(rad(-90) * out, 0, 0), p > 0.1 and p < 0.72
		elseif kind == "Hammer" then
			-- big overhead slam
			local up = smooth(p / 0.45)
			local down = outQuad((p - 0.45) / 0.1)
			local back = 1 - smooth((p - 0.7) / 0.3)
			local pitch = lerp(lerp(0, rad(215), up), rad(40), down) * back
			local lean = lerp(rad(12) * up, rad(-30), down) * back
			return armRot(pitch, rad(-8)), armRot(pitch * 0.9, rad(8)), CFrame.Angles(lean, 0, 0), I, p > 0.42 and p < 0.62
		elseif kind == "Staff" then
			-- staff raised high for the healing pulse
			local up = smooth(p / 0.35) * (1 - smooth((p - 0.75) / 0.25))
			return armRot(rad(170) * up, 0), armRot(rad(40) * up, 0), CFrame.Angles(rad(8) * up, 0, 0), I, false
		else -- Bow volley: aim high
			local up = smooth(p / 0.25) * (1 - smooth((p - 0.7) / 0.3))
			local draw = smooth((p - 0.05) / 0.17) * (1 - outQuad((p - 0.22) / 0.06))
			return armRot(rad(135) * up, rad(10) * up), armRot(rad(125) * up - rad(25) * draw, rad(-20) * up), CFrame.Angles(rad(10) * up, 0, 0), CFrame.Angles(rad(-90) * up, 0, 0), false
		end
	end
	if kind == "Blade" then
		local w = smooth(p / 0.3) -- windup
		local st = outQuad((p - 0.3) / 0.22) -- strike
		local rec = smooth((p - 0.55) / 0.45) -- recover
		local env = smooth(p / 0.2) * (1 - rec)
		local trailOn = p > 0.26 and p < 0.6
		if s.variant == 3 then
			-- overhead chop
			local pitch = lerp(lerp(0, rad(165), w), rad(25), st) * (1 - rec)
			local lean = lerp(rad(6) * w, rad(-18), st) * (1 - rec)
			return armRot(pitch, rad(-10)), nil, CFrame.Angles(lean, 0, 0), CFrame.Angles(rad(-60) * env, 0, 0), trailOn
		end
		local dir = s.variant == 1 and 1 or -1
		local yaw0, yaw1 = rad(-80) * dir, rad(70) * dir
		local yaw = lerp(lerp(0, yaw0, w), yaw1, st) * (1 - rec)
		local pitch = rad(82) * env
		local twist = lerp(lerp(0, rad(-25) * dir, w), rad(30) * dir, st) * (1 - rec)
		return armRot(pitch, yaw), nil, CFrame.Angles(0, twist, 0), CFrame.Angles(rad(-90) * env, 0, 0), trailOn
	elseif kind == "Hammer" then
		local up = smooth(p / 0.48)
		local down = outQuad((p - 0.48) / 0.12)
		local back = 1 - smooth((p - 0.68) / 0.32)
		local pitch = lerp(lerp(0, rad(195), up), rad(55), down) * back
		local lean = lerp(rad(10) * up, rad(-24), down) * back
		return armRot(pitch, rad(-6)), armRot(pitch * 0.85, rad(10)), CFrame.Angles(lean, 0, 0), I, p > 0.45 and p < 0.64
	elseif kind == "Staff" then
		local pull = smooth(p / 0.25)
		local thrust = outQuad((p - 0.25) / 0.15)
		local rec = smooth((p - 0.55) / 0.45)
		local pitch = lerp(lerp(0, rad(45), pull), rad(95), thrust) * (1 - rec)
		local twist = lerp(rad(-18) * pull, rad(12), thrust) * (1 - rec)
		return armRot(pitch, rad(8)), nil, CFrame.Angles(0, twist, 0), CFrame.Angles(rad(-90) * thrust * (1 - rec), 0, 0), p > 0.25 and p < 0.5
	else -- Bow: raise, draw, release with a kick
		local up = smooth(p / 0.25) * (1 - smooth((p - 0.7) / 0.3))
		local draw = smooth((p - 0.1) / 0.3)
		local rel = outQuad((p - 0.43) / 0.08)
		local kick = math.sin(math.clamp((p - 0.43) / 0.2, 0, 1) * math.pi) * rad(8)
		local leftPitch = rad(88) * up
		local leftYaw = lerp(rad(-30), rad(-55), draw * (1 - rel)) * up
		return armRot(rad(88) * up + kick, rad(18) * up), armRot(leftPitch, leftYaw), CFrame.Angles(0, rad(-12) * up, 0), CFrame.Angles(rad(-90) * up, 0, 0), false
	end
end

----------------------------------------------------------------------------------------------

function TamerAnim.start()
	for _, plr in Players:GetPlayers() do
		watchPlayer(plr)
	end
	Players.PlayerAdded:Connect(watchPlayer)
	Players.PlayerRemoving:Connect(function(plr)
		equipped[plr] = nil
		swings[plr] = nil
		rigs[plr] = nil
		combo[plr] = nil
		dodges[plr] = nil
	end)

	RunService.RenderStepped:Connect(function()
		local now = os.clock()
		for plr, eq in equipped do
			local s = swings[plr]
			local rig = rigOf(plr)
			local rR, lR, wR, weap, trailOn = CFrame.identity, nil, CFrame.identity, CFrame.identity, false
			if s then
				local p = (now - s.t0) / s.dur
				if p >= 1 then
					swings[plr] = nil
				else
					rR, lR, wR, weap, trailOn = pose(s, p)
				end
			end
			-- dodge: a tucked forward roll through the root joint (the root part stays upright)
			local d = dodges[plr]
			local rollRot, rollOff = CFrame.identity, Vector3.zero
			if d then
				local k = (now - d.t0) / d.dur
				if k >= 1 then
					dodges[plr] = nil
				else
					local e = k * k * (3 - 2 * k)
					local tuck = math.sin(k * math.pi)
					rollRot = CFrame.Angles(-math.pi * 2 * e, 0, 0)
					-- spin about the middle of the body, dipped toward the ground
					local c = Vector3.new(0, 0.9, 0)
					rollOff = (c - rollRot:VectorToWorldSpace(c)) + Vector3.new(0, -1.6 * tuck, 0)
					rR = CFrame.Angles(rad(140) * tuck, 0, 0)
					lR = CFrame.Angles(rad(140) * tuck, 0, 0)
					wR = CFrame.Angles(rad(-35) * tuck, 0, 0)
					trailOn = false
				end
			end
			if rig then
				if rig.root then
					rig.root.set(rollRot, rollOff)
				end
				-- rotate about the joint, in the parent part's space
				if rig.rs then
					rig.rs.set(rR)
				end
				if rig.ls then
					rig.ls.set(lR or CFrame.identity)
				end
				if rig.waist then
					rig.waist.set(wR)
				end
			end
			eq.weld.C0 = eq.base * weap
			for _, t in eq.trails do
				if t.Enabled ~= trailOn then
					t.Enabled = trailOn
				end
			end
		end
	end)
end

-- Dodge roll for any player (the local player calls this on input; others from the server event).
function TamerAnim.dodge(plr: Player)
	dodges[plr] = { t0 = os.clock(), dur = T.Tamer.DodgeTime + 0.08 }
	swings[plr] = nil
	local root = plr.Character and plr.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if root then
		local feet = root.Position - Vector3.new(0, 2.6, 0)
		CombatFx.burst(feet, Color3.fromRGB(225, 220, 205), 10, 7, { texture = "smoke", size = 1.6, life = 0.5, emission = 0, gravity = 2, spread = Vector2.new(80, 80) })
		task.delay(T.Tamer.DodgeTime, function()
			if root.Parent then
				CombatFx.burst(root.Position - Vector3.new(0, 2.6, 0), Color3.fromRGB(225, 220, 205), 8, 5, { texture = "smoke", size = 1.4, life = 0.45, emission = 0, gravity = 2, spread = Vector2.new(80, 80) })
			end
		end)
	end
end

-- Studio debug: what the animator currently sees for a player.
function TamerAnim.debugState(plr: Player): string
	local s = swings[plr]
	local r = rigOf(plr)
	local eq = equipped[plr]
	return string.format("swing=%s rig=%s rs=%s eq=%s", s and (s.kind .. (s.skill and "*" or "") .. string.format("@%.2f", os.clock() - s.t0)) or "none", tostring(r ~= nil), r and r.rs and (r.rs.inst:GetFullName() .. ":" .. r.rs.inst.ClassName) or "-", eq and eq.kind or "none")
end

-- Effects for a tamer's attack or skill, timed to the animation's strike.
-- e is the server event: {"swing", key, origin, dir, weapon} / {"shot", key, from, to, weapon}
-- / {"wskill", key, centre, kind, radius}. Returns the delay until hits should show.
function TamerAnim.effects(plr: Player?, e): number
	local kind = e[1]
	local weaponKind = kind == "wskill" and e[4] or e[5]
	local s = plr and TamerAnim.play(plr, weaponKind, kind == "wskill") or nil
	local wait = s and TamerAnim.untilImpact(s) or 0
	local color = WEAPON_COLOR[weaponKind] or Color3.new(1, 1, 1)
	local mine = plr == player
	if kind == "swing" then
		local origin, dir = e[3] :: Vector3, e[4] :: Vector3
		local w = T.Weapons[weaponKind] or T.Weapons.Blade
		task.delay(wait, function()
			local cf = CFrame.lookAt(origin, origin + dir)
			if weaponKind == "Hammer" then
				local at = origin + dir * (w.Range * 0.6)
				CombatFx.shockwave(at, 5, color, 0.35)
				CombatFx.debris(at, Color3.fromRGB(150, 140, 125), 6, 6)
				if mine then
					CombatFx.shake(0.9, 0.22)
				end
			else
				local v = s and s.variant or 1
				local half = rad((w.Arc or 110) / 2)
				if v == 3 then
					CombatFx.slash(cf * CFrame.new(0, 0.6, 0), w.Range * 0.65, color, -0.25, 0.25, 0.08, math.pi / 2, 1.1)
				elseif v == 2 then
					CombatFx.slash(cf * CFrame.new(0, 0.4, 0), w.Range * 0.7, color, half, -half, 0.09, rad(-12))
				else
					CombatFx.slash(cf * CFrame.new(0, 0.4, 0), w.Range * 0.7, color, -half, half, 0.09, rad(12))
				end
			end
		end)
		return wait
	elseif kind == "shot" then
		local from, to = e[3] :: Vector3, e[4] :: Vector3
		local rel = s and TamerAnim.untilRelease(s) or 0
		local arrived = rel
		local proj = weaponKind == "Bow" and "arrow" or "orb"
		local muzzleFrom = (plr and TamerAnim.muzzle(plr)) or (from + Vector3.new(0, 1, 0))
		local tt = math.clamp((to - muzzleFrom).Magnitude / (proj == "arrow" and 150 or 95), 0.08, 0.45)
		arrived += tt
		task.delay(rel, function()
			local start = (plr and TamerAnim.muzzle(plr)) or muzzleFrom
			CombatFx.projectile(start, to + Vector3.new(0, 1, 0), color, proj == "arrow" and 0.5 or 0.9, proj, proj == "arrow" and 1.2 or 0.6, function()
				CombatFx.flash(to + Vector3.new(0, 1, 0), color, 1.6)
				CombatFx.burst(to + Vector3.new(0, 1, 0), color, 8, 8, { size = 0.5, life = 0.35 })
			end)
		end)
		return arrived
	elseif kind == "wskill" then
		local centre, radius = e[3] :: Vector3, e[5] :: number
		if weaponKind == "Bow" then
			-- volley: a fan of arrows rains onto the circle, the hit lands with the first wave
			local rel = s and TamerAnim.untilRelease(s) or 0
			local root = plr and plr.Character and plr.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
			local sky = (root and root.Position or centre) + Vector3.new(0, 24, 0)
			local fall = 0.35
			task.delay(rel, function()
				for i = 1, 12 do
					task.delay((i - 1) * 0.035, function()
						local a = math.random() * math.pi * 2
						local r = math.sqrt(math.random()) * radius
						local land = centre + Vector3.new(math.cos(a) * r, 0, math.sin(a) * r)
						land = Vector3.new(land.X, CombatFx.groundY(land) + 0.3, land.Z)
						CombatFx.projectile(sky:Lerp(land, 0.35) + Vector3.new(0, 12, 0), land, color, 0.5, "arrow", 0.5, function()
							CombatFx.burst(land, color, 4, 6, { size = 0.4, life = 0.3 })
						end)
					end)
				end
				task.delay(fall, function()
					CombatFx.shockwave(centre, radius, color, 0.4)
				end)
			end)
			return rel + fall
		end
		task.delay(wait, function()
			if weaponKind == "Staff" then
				local healColor = Color3.fromRGB(120, 230, 170)
				CombatFx.pillar(centre, healColor, 3, 14)
				CombatFx.shockwave(centre, radius, healColor, 0.6)
			elseif weaponKind == "Hammer" then
				CombatFx.shockwave(centre, radius, color, 0.45)
				task.delay(0.08, function()
					CombatFx.shockwave(centre, radius * 0.6, Color3.new(1, 1, 1), 0.35)
				end)
				CombatFx.debris(centre, Color3.fromRGB(150, 140, 125), 14, radius * 0.7)
				CombatFx.shakeAt(centre, 2.2, 0.4, 45)
			else -- Blade spin
				local cf = CFrame.new(centre)
				CombatFx.slash(cf * CFrame.new(0, 0.6, 0), radius * 0.75, color, 0, math.pi * 2, 0.22, 0, 1.2)
				CombatFx.shockwave(centre, radius, color, 0.35)
				if mine then
					CombatFx.shake(0.8, 0.2)
				end
			end
		end)
		return wait
	end
	return 0
end

return TamerAnim

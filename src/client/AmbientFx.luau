-- Ambient life around the player, by region (client only, cheap):
--   Haven / Sprout Meadow: butterflies that flutter and wander
--   Ember Canyon: embers drifting up from the ground
--   Tide Coast: seagulls circling overhead
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local AmbientFx = {}
local player = Players.LocalPlayer

local folder = Instance.new("Folder")
folder.Name = "Ambient"
folder.Parent = workspace

local function piece(size: Vector3, color: Color3, material: Enum.Material?): BasePart
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Size = size
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.Parent = folder
	return p
end

----------------------------------------------------------------------------------------------
-- butterflies

local BUTTERFLY_COLORS = { Color3.fromRGB(255, 200, 90), Color3.fromRGB(255, 150, 190), Color3.fromRGB(150, 200, 255), Color3.fromRGB(200, 160, 255), Color3.fromRGB(255, 255, 255) }
type Fly = { l: BasePart, r: BasePart, pos: Vector3, goal: Vector3, t: number, speed: number }
local flies: { Fly } = {}

local function newFly(around: Vector3): Fly
	local c = BUTTERFLY_COLORS[math.random(1, #BUTTERFLY_COLORS)]
	local l = piece(Vector3.new(0.7, 0.05, 0.55), c)
	local r = piece(Vector3.new(0.7, 0.05, 0.55), c)
	local a = math.random() * math.pi * 2
	local pos = around + Vector3.new(math.cos(a) * math.random(8, 40), math.random(2, 6), math.sin(a) * math.random(8, 40))
	return { l = l, r = r, pos = pos, goal = pos, t = math.random() * 10, speed = 3 + math.random() * 3 }
end

local function clearFlies()
	for _, f in flies do
		f.l:Destroy()
		f.r:Destroy()
	end
	flies = {}
end

----------------------------------------------------------------------------------------------
-- embers (one emitter that follows the player)

local emberAnchor = piece(Vector3.new(60, 1, 60), Color3.new(1, 1, 1))
emberAnchor.Transparency = 1
local embers = Instance.new("ParticleEmitter")
embers.Texture = "rbxasset://textures/particles/sparkles_main.dds"
embers.Color = ColorSequence.new(Color3.fromRGB(255, 170, 70), Color3.fromRGB(255, 90, 40))
embers.LightEmission = 1
embers.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 0) })
embers.Lifetime = NumberRange.new(3, 5)
embers.Speed = NumberRange.new(2, 4)
embers.SpreadAngle = Vector2.new(25, 25)
embers.Acceleration = Vector3.new(0.6, 1.2, 0)
embers.Rate = 0
embers.EmissionDirection = Enum.NormalId.Top
embers.Parent = emberAnchor

----------------------------------------------------------------------------------------------
-- seagulls

type Gull = { parts: { BasePart }, centre: Vector3, radius: number, height: number, phase: number, speed: number }
local gulls: { Gull } = {}

local function newGull(around: Vector3): Gull
	local body = piece(Vector3.new(0.5, 0.4, 1.4), Color3.fromRGB(250, 250, 250))
	local wl = piece(Vector3.new(2.2, 0.08, 0.7), Color3.fromRGB(240, 240, 245))
	local wr = piece(Vector3.new(2.2, 0.08, 0.7), Color3.fromRGB(240, 240, 245))
	return { parts = { body, wl, wr }, centre = around + Vector3.new(math.random(-40, 40), 0, math.random(-40, 40)), radius = math.random(14, 30), height = math.random(26, 40), phase = math.random() * 6, speed = 0.25 + math.random() * 0.2 }
end

local function clearGulls()
	for _, g in gulls do
		for _, p in g.parts do
			p:Destroy()
		end
	end
	gulls = {}
end

----------------------------------------------------------------------------------------------

function AmbientFx.start()
	local region = nil
	RunService.RenderStepped:Connect(function(dt)
		local char = player.Character
		local hrp = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not hrp then
			return
		end
		local here = player:GetAttribute("Region") or "Haven"
		local pos = hrp.Position
		if here ~= region then
			region = here
			clearFlies()
			clearGulls()
			embers.Rate = 0
		end
		local t = os.clock()
		if here == "Haven" or here == "SproutMeadow" then
			local want = here == "Haven" and 8 or 14
			while #flies < want do
				table.insert(flies, newFly(pos))
			end
			for _, f in flies do
				f.t += dt
				if (f.goal - f.pos).Magnitude < 1.5 or (f.pos - pos).Magnitude > 70 then
					local a = math.random() * math.pi * 2
					local base = (f.pos - pos).Magnitude > 70 and pos or f.pos
					f.goal = Vector3.new(base.X + math.cos(a) * math.random(6, 18), pos.Y + math.random(0, 5), base.Z + math.sin(a) * math.random(6, 18))
				end
				local dir = (f.goal - f.pos)
				f.pos += dir.Unit * math.min(dir.Magnitude, f.speed * dt) + Vector3.new(0, math.sin(f.t * 6) * 0.03, 0)
				local look = CFrame.lookAt(f.pos, f.pos + Vector3.new(dir.X, 0, dir.Z) + Vector3.new(0.001, 0, 0))
				local flap = math.sin(f.t * 22) * 0.9
				f.l.CFrame = look * CFrame.Angles(0, 0, flap) * CFrame.new(-0.35, 0, 0)
				f.r.CFrame = look * CFrame.Angles(0, 0, -flap) * CFrame.new(0.35, 0, 0)
			end
		elseif #flies > 0 then
			clearFlies()
		end
		if here == "EmberCanyon" then
			emberAnchor.CFrame = CFrame.new(pos.X, pos.Y - 2.5, pos.Z)
			embers.Rate = 14
		else
			embers.Rate = 0
		end
		if here == "TideCoast" then
			while #gulls < 5 do
				table.insert(gulls, newGull(pos))
			end
			for _, g in gulls do
				if (Vector3.new(g.centre.X, pos.Y, g.centre.Z) - pos).Magnitude > 120 then
					g.centre = pos + Vector3.new(math.random(-40, 40), 0, math.random(-40, 40))
				end
				local a = g.phase + t * g.speed
				local at = Vector3.new(g.centre.X + math.cos(a) * g.radius, pos.Y + g.height + math.sin(t * 0.7 + g.phase) * 2, g.centre.Z + math.sin(a) * g.radius)
				local ahead = Vector3.new(g.centre.X + math.cos(a + 0.1) * g.radius, at.Y, g.centre.Z + math.sin(a + 0.1) * g.radius)
				local cf = CFrame.lookAt(at, ahead) * CFrame.Angles(0, 0, -0.25)
				local flap = math.sin(t * 5 + g.phase) * 0.35
				g.parts[1].CFrame = cf
				g.parts[2].CFrame = cf * CFrame.Angles(0, 0, flap) * CFrame.new(-1.2, 0, 0)
				g.parts[3].CFrame = cf * CFrame.Angles(0, 0, -flap) * CFrame.new(1.2, 0, 0)
			end
		elseif #gulls > 0 then
			clearGulls()
		end
	end)
end

return AmbientFx

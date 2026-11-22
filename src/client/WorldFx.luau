-- Local world dressing: Meshy props, escalator rattle lights/audio, and server Fx events.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Noise = require(Shared.Noise)
local MeshLoader = require(Shared.MeshLoader)
local Creatures = require(Shared.Creatures)
local CreatureView = require(script.Parent.CreatureView)

local WorldFx = {}

local propFolder = Instance.new("Folder")
propFolder.Name = "Props"
propFolder.Parent = workspace

local function prop(name: string, height: number, cf: CFrame, collide: Vector3?): BasePart?
	local mp = MeshLoader.get(name, height)
	if not mp then
		return nil
	end
	mp.CFrame = cf * CFrame.new(0, height / 2, 0)
	mp.Parent = propFolder
	if collide then
		local box = Instance.new("Part")
		box.Name = name .. "Collision"
		box.Size = collide
		box.CFrame = cf * CFrame.new(0, collide.Y / 2, 0)
		box.Anchored = true
		box.Transparency = 1
		box.CanQuery = false
		box.Parent = propFolder
	end
	return mp
end

-- Sleepers nap against an oversized takeout bag; the bag stays put as a landmark.
function CreatureView.bagFor(part: BasePart, height: number)
	if part:GetAttribute("Rarity") == "Rare" then
		return nil
	end
	local pos = part.Position - Vector3.new(0, part.Size.Y / 2, 0)
	local look = part.CFrame.LookVector * Vector3.new(1, 0, 1)
	local cf = CFrame.lookAt(pos - look * (height * 0.55), pos - look * (height * 0.55) - look) * CFrame.Angles(0, 0, math.rad(-8))
	local bag = MeshLoader.get("PropTakeoutBag", height * 1.6)
	if not bag then
		return nil
	end
	bag.CFrame = cf * CFrame.new(0, height * 0.8, 0)
	bag.Parent = propFolder
	return bag
end

local function placeProps(map: Instance)
	local hideout = map:WaitForChild("Hideout")
	local pad = hideout:WaitForChild("StationPad") :: BasePart
	local padPos = pad.Position - Vector3.new(0, pad.Size.X / 2, 0)
	-- Rescue station fort behind the pad, facing the hideout mouth (+Z)
	prop("PropRescueStation", 10, CFrame.new(padPos + Vector3.new(0, 0, -9)) * CFrame.Angles(0, math.pi, 0), Vector3.new(10, 9, 7))
	-- Fountain centrepiece in the basin
	local basin = map:WaitForChild("FountainBasin") :: BasePart
	local spout = map:FindFirstChild("FountainSpout") :: BasePart?
	local f = prop("PropFountain", 9, CFrame.new(basin.Position.X, 0.2, basin.Position.Z) * CFrame.Angles(0, math.rad(30), 0), nil)
	if f and spout then
		spout.Transparency = 1
	end
end

-- Escalator rattle: lights, step jitter, audio and a timing sign.
local rattleLights, rattleSteps, rattleSounds = {}, {}, {}
local timingSigns = {}

local function setupEscalators(map: Instance)
	local esc = map:WaitForChild("Escalators")
	for _, d in esc:GetDescendants() do
		if d:IsA("BasePart") and d:GetAttribute("RattleLight") then
			table.insert(rattleLights, d)
		elseif d:IsA("BasePart") and d:GetAttribute("RattleStep") then
			table.insert(rattleSteps, d)
		elseif d:IsA("Sound") and d.Name == "Rattle" then
			table.insert(rattleSounds, d)
			d:Play()
		end
	end
	-- timing lamps at both escalator feet, readable from a distance
	for _, z in { 36, 130 } do
		local p = Instance.new("Part")
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.Transparency = 1
		p.Size = Vector3.new(1, 1, 1)
		p.Position = Vector3.new(26, 9, z)
		p.Parent = propFolder
		local bb = Instance.new("BillboardGui")
		bb.Size = UDim2.fromOffset(170, 46)
		bb.MaxDistance = 90
		bb.LightInfluence = 0
		bb.Parent = p
		local lbl = Instance.new("TextLabel")
		lbl.Size = UDim2.fromScale(1, 1)
		lbl.BackgroundColor3 = Color3.fromRGB(40, 20, 20)
		lbl.BackgroundTransparency = 0.1
		lbl.Font = Enum.Font.FredokaOne
		lbl.TextScaled = true
		lbl.TextColor3 = Color3.new(1, 1, 1)
		lbl.Parent = bb
		Instance.new("UICorner").Parent = lbl
		local bar = Instance.new("Frame")
		bar.Size = UDim2.new(1, 0, 0, 6)
		bar.Position = UDim2.new(0, 0, 1, -6)
		bar.BorderSizePixel = 0
		bar.Parent = lbl
		table.insert(timingSigns, { label = lbl, bar = bar })
	end
end

local function updateEscalators()
	local t = workspace:GetServerTimeNow()
	local loud = Noise.rattleLoud(t)
	local phase = Noise.rattlePhase(t)
	local n = require(Shared.Config).Tuning.Noise
	for _, l in rattleLights do
		l.Color = loud and Color3.fromRGB(255, 40 + math.random(0, 40), 30) or Color3.fromRGB(80, 200, 120)
		local pl = l:FindFirstChildOfClass("PointLight")
		if pl then
			pl.Color = l.Color
			pl.Brightness = loud and (1.4 + math.random() * 0.8) or 0.6
		end
	end
	for _, s in rattleSteps do
		local base: CFrame = s:GetAttribute("BaseCFrame")
		if loud then
			s.CFrame = base * CFrame.new((math.random() - 0.5) * 0.15, (math.random() - 0.5) * 0.12, 0)
			s.Color = Color3.fromRGB(255, 196, 40)
		else
			s.CFrame = base
			s.Color = Color3.fromRGB(120, 210, 140)
		end
	end
	for _, s in rattleSounds do
		s.Volume = loud and 0.9 or 0.08
		s.PlaybackSpeed = loud and (0.5 + math.random() * 0.15) or 0.4
	end
	for _, sgn in timingSigns do
		if loud then
			sgn.label.Text = "⚠️ RATTLING!"
			sgn.label.BackgroundColor3 = Color3.fromRGB(150, 25, 20)
			sgn.bar.BackgroundColor3 = Color3.fromRGB(255, 200, 60)
			sgn.bar.Size = UDim2.new(1 - phase / n.RattleLoudPortion, 0, 0, 6)
		else
			sgn.label.Text = "😴 quiet… GO"
			sgn.label.BackgroundColor3 = Color3.fromRGB(25, 110, 60)
			sgn.bar.BackgroundColor3 = Color3.fromRGB(200, 255, 200)
			sgn.bar.Size = UDim2.new(1 - (phase - n.RattleLoudPortion) / (1 - n.RattleLoudPortion), 0, 0, 6)
		end
	end
end

local function burst(pos: Vector3, color: Color3, count: number, speed: number)
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.Transparency = 1
	p.Size = Vector3.new(1, 1, 1)
	p.Position = pos
	p.Parent = propFolder
	local e = Instance.new("ParticleEmitter")
	e.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	e.Color = ColorSequence.new(color)
	e.Speed = NumberRange.new(speed * 0.6, speed)
	e.SpreadAngle = Vector2.new(180, 180)
	e.Lifetime = NumberRange.new(0.6, 1.1)
	e.Size = NumberSequence.new(0.9, 0)
	e.Acceleration = Vector3.new(0, -20, 0)
	e.Rate = 0
	e.Parent = p
	e:Emit(count)
	task.delay(2, function()
		p:Destroy()
	end)
	return p
end
WorldFx.burst = burst

-- A banked creature pops out of the station for everyone to see.
local function bankPop(pos: Vector3, species: string)
	local sp = Creatures.Species[species]
	if not sp then
		return
	end
	local c = CreatureView.build(species, sp.Height)
	for _, l in c.lids do
		l.lid.Transparency = 1
		l.line.Transparency = 1
	end
	local start = CFrame.new(pos + Vector3.new(0, 1, 0)) * CFrame.Angles(0, math.pi, 0)
	c.body.CFrame = start
	local t0 = os.clock()
	local conn
	conn = RunService.RenderStepped:Connect(function()
		local k = (os.clock() - t0) / 1.6
		if k >= 1 then
			conn:Disconnect()
			c.model:Destroy()
			return
		end
		local y = math.sin(math.min(k * 1.6, 1) * math.pi * 0.5) * 6 - math.max(0, k - 0.75) * 24
		c.body.CFrame = start * CFrame.new(0, y, 0) * CFrame.Angles(0, k * math.pi * 3, 0)
	end)
end

function WorldFx.onFx(kind: string, pos: Vector3, a, b, c)
	if kind == "Wake" then
		local p = burst(pos, Color3.fromRGB(255, 120, 80), 30, 14)
		CreatureView.playAt(p, CreatureView.SOUNDS.Pop, 0.5, 2.2)
		CreatureView.playAt(p, CreatureView.SOUNDS.Squirm, 0.8, 2.6)
	elseif kind == "Grab" then
		local p = burst(pos, Color3.fromRGB(200, 220, 255), 8, 6)
		CreatureView.playAt(p, "rbxasset://sounds/action_jump.mp3", 0.4, 1.4)
	elseif kind == "Bank" then
		local p = burst(pos + Vector3.new(0, 3, 0), Color3.fromRGB(255, 140, 210), 50, 20)
		burst(pos + Vector3.new(0, 3, 0), Color3.fromRGB(255, 230, 120), 30, 16)
		CreatureView.playAt(p, CreatureView.SOUNDS.Pop, 0.6, 1.4)
		bankPop(pos, a)
	elseif kind == "Poof" or kind == "Drop" then
		burst(pos, Color3.fromRGB(230, 230, 230), 16, 6)
	elseif kind == "VentOpen" then
		local p = burst(pos, Color3.fromRGB(140, 255, 160), 16, 8)
		CreatureView.playAt(p, "rbxasset://sounds/action_jump_land.mp3", 0.9, 0.7)
		CreatureView.buddyPry(a, pos)
	end
end

function WorldFx.start()
	local map = workspace:WaitForChild("Map")
	task.spawn(placeProps, map)
	setupEscalators(map)
	RunService.RenderStepped:Connect(updateEscalators)
	-- rare beam pulse
	local beam
	for _, d in map:GetDescendants() do
		if d:IsA("BasePart") and d:GetAttribute("RareBeam") then
			beam = d
		end
	end
	if beam then
		TweenService:Create(beam, TweenInfo.new(1.2, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Size = beam.Size + Vector3.new(0, 1.5, 1.5) }):Play()
	end
end

return WorldFx

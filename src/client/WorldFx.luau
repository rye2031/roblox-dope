-- Local world dressing: Meshy props, escalator rattle lights/audio, and server Fx events.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Noise = require(Shared.Noise)
local MeshLoader = require(Shared.MeshLoader)
local Creatures = require(Shared.Creatures)
local Theme = require(Shared.Theme)
local Config = require(Shared.Config)
local Portraits = require(Shared.Portraits)
local CreatureView = require(script.Parent.CreatureView)
local Players = game:GetService("Players")
local player = Players.LocalPlayer

local WorldFx = {}

local propFolder = Instance.new("Folder")
propFolder.Name = "Props"
propFolder.Parent = workspace

local function prop(name: string, height: number, cf: CFrame, collide: Vector3?, optional: boolean?): BasePart?
	local mp = MeshLoader.get(name, height, { optional = optional })
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
	if part:GetAttribute("Rarity") == "Rare" or part:GetAttribute("Wing") ~= "FoodCourt" then
		return nil -- arcade sleepers nap without a takeout bag
	end
	local pos = part.Position - Vector3.new(0, part.Size.Y / 2, 0)
	local look = part.CFrame.LookVector * Vector3.new(1, 0, 1)
	local cf = CFrame.lookAt(pos - look * (height * 0.55), pos - look * (height * 0.55) - look) * CFrame.Angles(0, 0, math.rad(-8))
	local bag = MeshLoader.get("PropTakeoutBag", height * 1.6, { optional = true })
	if not bag then
		return nil
	end
	bag.CFrame = cf * CFrame.new(0, height * 0.8, 0)
	bag.Parent = propFolder
	return bag
end

-- Hideout station + fountain props. They hold mesh slots, so they only load while the player
-- is in the Food Court (the client has room for about 8 meshes in total).
local placed: { [string]: { BasePart } } = {}
local function placeProps(map: Instance, want: boolean)
	local function drop(name: string)
		local list = placed[name]
		if list then
			for _, p in list do
				p:Destroy()
			end
			placed[name] = nil
			MeshLoader.release(name)
		end
	end
	if not want then
		drop("PropRescueStation")
		drop("PropFountain")
		return
	end
	local hideout = map:WaitForChild("Hideout")
	local pad = hideout:WaitForChild("StationPad") :: BasePart
	local padPos = pad.Position - Vector3.new(0, pad.Size.X / 2, 0)
	if not placed.PropRescueStation then
		-- Rescue station fort behind the pad, facing the hideout mouth (+Z)
		local st = prop("PropRescueStation", 10, CFrame.new(padPos + Vector3.new(0, 0, -9)) * CFrame.Angles(0, math.pi, 0), Vector3.new(10, 9, 7))
		if st then
			placed.PropRescueStation = { st, propFolder:FindFirstChild("PropRescueStationCollision") }
		end
	end
	if not placed.PropFountain then
		local basin = map:WaitForChild("FountainBasin") :: BasePart
		local spout = map:FindFirstChild("FountainSpout") :: BasePart?
		local f = prop("PropFountain", 9, CFrame.new(basin.Position.X, 0.2, basin.Position.Z) * CFrame.Angles(0, math.rad(30), 0), nil, true)
		if f then
			placed.PropFountain = { f }
		end
		if spout then
			spout.Transparency = f and 1 or 0
		end
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
	-- timing lamps at both escalator feet and the dance floor, readable from a distance
	for _, spot in { { Vector3.new(26, 9, 36), "Loud" }, { Vector3.new(26, 9, 130), "Loud" }, { Vector3.new(137, 7, 70), "Dance" }, { Vector3.new(137, 7, 122), "Dance" } } do
		local p = Instance.new("Part")
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.Transparency = 1
		p.Size = Vector3.new(1, 1, 1)
		p.Position = spot[1]
		p.Parent = propFolder
		local bb = Instance.new("BillboardGui")
		bb.Size = UDim2.fromOffset(112, 30)
		bb.MaxDistance = 70
		bb.LightInfluence = 0
		bb.Parent = p
		local pill = Instance.new("Frame")
		pill.Size = UDim2.fromScale(1, 1)
		pill.BackgroundColor3 = Color3.new(1, 1, 1)
		pill.Parent = bb
		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(0.5, 0)
		c.Parent = pill
		local st = Instance.new("UIStroke")
		st.Thickness = 3
		st.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		st.Parent = pill
		local lbl = Instance.new("TextLabel")
		lbl.Size = UDim2.new(1, -16, 1, -10)
		lbl.Position = UDim2.fromOffset(8, 3)
		lbl.BackgroundTransparency = 1
		lbl.FontFace = Theme.Font.Title
		lbl.TextScaled = true
		lbl.TextColor3 = Theme.C.Ink
		lbl.Parent = pill
		local bar = Instance.new("Frame")
		bar.Size = UDim2.new(1, 0, 0, 4)
		bar.Position = UDim2.new(0, 0, 1, -6)
		bar.BorderSizePixel = 0
		bar.Parent = pill
		table.insert(timingSigns, { label = lbl, bar = bar, stroke = st, surface = spot[2] })
	end
end

local danceTiles = {}
local danceThump: Sound? = nil
local lastDanceLoud = -1
local screens = {}
local floatLabels = {}
local gateParts = {}

local LOUD_COL = Color3.fromRGB(255, 120, 104)
local CALM_COL = Color3.fromRGB(110, 214, 160)

local function updateEscalators()
	local t = workspace:GetServerTimeNow()
	local loud = Noise.rattleLoud(t)
	for _, l in rattleLights do
		l.Color = loud and LOUD_COL:Lerp(Color3.fromRGB(255, 200, 120), math.random() * 0.3) or CALM_COL
	end
	for _, s in rattleSteps do
		local base: CFrame = s:GetAttribute("BaseCFrame")
		if loud then
			s.CFrame = base * CFrame.new((math.random() - 0.5) * 0.15, (math.random() - 0.5) * 0.12, 0)
			s.Color = Color3.fromRGB(255, 208, 96)
		else
			s.CFrame = base
			s.Color = CALM_COL
		end
	end
	for _, s in rattleSounds do
		s.Volume = loud and 0.9 or 0.08
		s.PlaybackSpeed = loud and (0.5 + math.random() * 0.15) or 0.4
	end
	-- dance floor: tiles flash on the beat while loud, calm pastel otherwise
	local dLoud = Noise.loudNow("Dance", t)
	local dPhase = Noise.phase("Dance", t)
	local beat = math.floor(t * 4) % 2
	for _, d in danceTiles do
		if dLoud then
			d.part.Color = (d.parity == beat) and Color3.fromHSV((t * 0.3 + d.hue) % 1, 0.6, 1) or Color3.fromRGB(255, 236, 244)
		else
			d.part.Color = Color3.fromRGB(190, 236, 214)
		end
	end
	if danceThump and dLoud and math.floor(t * 4) ~= lastDanceLoud then
		lastDanceLoud = math.floor(t * 4)
		danceThump.PlaybackSpeed = 0.45 + beat * 0.1
		danceThump:Play()
	end
	for _, sgn in timingSigns do
		local surf = sgn.surface
		local isLoud = Noise.loudNow(surf, t)
		local phase = Noise.phase(surf, t)
		local _, portion = Noise.cycleOf(surf)
		if isLoud then
			sgn.label.Text = surf == "Dance" and "LOUD BEAT" or "RATTLING"
			sgn.stroke.Color = LOUD_COL
			sgn.bar.BackgroundColor3 = LOUD_COL
			sgn.bar.Size = UDim2.new(1 - phase / portion, 0, 0, 4)
		else
			sgn.label.Text = "quiet · GO"
			sgn.stroke.Color = CALM_COL
			sgn.bar.BackgroundColor3 = CALM_COL
			sgn.bar.Size = UDim2.new(1 - (phase - portion) / (1 - portion), 0, 0, 4)
		end
	end
	local _ = dPhase
	-- floating labels bob gently
	local now = os.clock()
	for _, f in floatLabels do
		f.gui.StudsOffset = Vector3.new(0, math.sin(now * 1.3 + f.seed) * 0.35, 0)
	end
	-- wing gates: see-through and labelled "open" once you've unlocked them
	local pass = player:GetAttribute("PassWing")
	local passOrder = pass and Config.Wings[pass] and Config.Wings[pass].Order or 0
	for _, g in gateParts do
		local open = passOrder >= (Config.Wings[g.wing] and Config.Wings[g.wing].Order or 99)
		g.part.LocalTransparencyModifier = open and 0.85 or 0
		if g.sub then
			g.sub.Text = open and "open · walk through" or g.locked
		end
		if g.prompt then
			g.prompt.Enabled = not open
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
	local c = CreatureView.build(species, sp.Height, nil, { optional = true })
	if c.temp then
		CreatureView.destroy(c)
		return -- no spare mesh slot right now; the burst and reveal card still play
	end
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
			CreatureView.destroy(c)
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
	elseif kind == "Collect" then
		local p = burst(pos + Vector3.new(0, 4, 0), Theme.C.Sun, math.clamp(math.floor((a or 10) / 4), 10, 60), 14)
		CreatureView.playAt(p, "rbxasset://sounds/electronicpingshort.wav", 0.5, 1.4)
	elseif kind == "Nudge" then
		local p = burst(pos + Vector3.new(0, 1, 0), Theme.C.Peach, 18, 10)
		CreatureView.playAt(p, "rbxasset://sounds/action_jump.mp3", 0.8, 0.7)
		CreatureView.playAt(p, CreatureView.SOUNDS.Twitch, 0.6, 1.6)
	elseif kind == "Squeak" then
		local p = burst(pos + Vector3.new(0, 2, 0), Theme.C.Rose, 8, 6)
		CreatureView.playAt(p, "rbxasset://sounds/electronicpingshort.wav", 0.7, 2.6)
	elseif kind == "Unlock" then
		local p = burst(pos + Vector3.new(0, 4, 0), Theme.C.Lilac, 60, 22)
		burst(pos + Vector3.new(0, 4, 0), Theme.C.Sun, 30, 16)
		CreatureView.playAt(p, CreatureView.SOUNDS.Pop, 0.7, 1.2)
	elseif kind == "VentOpen" then
		local p = burst(pos, Color3.fromRGB(140, 255, 160), 16, 8)
		CreatureView.playAt(p, "rbxasset://sounds/action_jump_land.mp3", 0.9, 0.7)
		CreatureView.buddyPry(a, pos)
	end
end

-- Wanted poster on the hideout wall: this hour's creature, condition and countdown.
local function setupPoster(map: Instance)
	local poster = map:WaitForChild("Hideout"):WaitForChild("WantedPoster") :: BasePart
	local C = Theme.C
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 50
	gui.LightInfluence = 0
	gui.Parent = poster
	local bg = Theme.new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromRGB(255, 250, 238), Parent = gui }, {
		Theme.new("UIStroke", { Thickness = 10, Color = C.Coral, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }),
	})
	Theme.text({ Size = UDim2.new(1, -30, 0.12, 0), Position = UDim2.new(0, 15, 0.03, 0), Text = "WANTED", TextColor3 = C.Coral, Parent = bg }, "Title")
	local img = Theme.new("ImageLabel", { Size = UDim2.new(1, -40, 0.44, 0), Position = UDim2.new(0, 20, 0.16, 0), BackgroundTransparency = 1, ScaleType = Enum.ScaleType.Fit, Parent = bg })
	local name = Theme.text({ Size = UDim2.new(1, -30, 0.09, 0), Position = UDim2.new(0, 15, 0.61, 0), Text = "", Parent = bg }, "Title")
	local cond = Theme.text({ Size = UDim2.new(1, -30, 0.065, 0), Position = UDim2.new(0, 15, 0.71, 0), Text = "", TextColor3 = C.Sub, Parent = bg }, "Bold")
	local Hud = nil
	local function deepestWing(): string
		Hud = Hud or require(script.Parent.Hud)
		local p = Hud.getProfile()
		local best = "FoodCourt"
		if p then
			for _, w in Config.wingList() do
				if p.wings[w.Id] then
					best = w.Id
				end
			end
		end
		return best
	end
	Theme.text({ Size = UDim2.new(1, -30, 0.08, 0), Position = UDim2.new(0, 15, 0.79, 0), Text = "pays " .. Config.Tuning.Events.WantedMult .. "x coins", TextColor3 = Color3.fromRGB(40, 160, 110), Parent = bg }, "Title")
	local timer = Theme.text({ Size = UDim2.new(1, -30, 0.06, 0), Position = UDim2.new(0, 15, 0.9, 0), Text = "", TextColor3 = C.Sub, Parent = bg }, "Bold")
	local shown = nil
	task.spawn(function()
		while true do
			local wing = deepestWing()
			local sp = workspace:GetAttribute("WantedSpecies_" .. wing)
			local form = workspace:GetAttribute("WantedForm_" .. wing)
			local key = tostring(sp) .. tostring(form)
			if sp and key ~= shown then
				shown = key
				local def = Creatures.Species[sp]
				Portraits.apply(img, sp)
				name.Text = def and def.Name or sp
				cond.Text = (form == "Fancy" and "Glazed or Jumbo" or "any form") .. " · " .. Config.Wings[wing].Name
			end
			local left = math.max(0, (workspace:GetAttribute("WantedUntil") or 0) - workspace:GetServerTimeNow())
			timer.Text = string.format("new poster in %d:%02d", left // 60, left % 60)
			task.wait(0.5)
		end
	end)
end

-- Top Keepers board: global top 10 by Overtime and by rescues (published by the server).
local function setupLeaderboard(map: Instance)
	local board = map:WaitForChild("Hideout"):WaitForChild("LeaderBoard") :: BasePart
	local data = ReplicatedStorage:WaitForChild("Leaderboard") :: StringValue
	local C = Theme.C
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 50
	gui.LightInfluence = 0
	gui.Parent = board
	local bg = Theme.new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromRGB(250, 248, 255), Parent = gui }, {
		Theme.new("UIStroke", { Thickness = 10, Color = C.Lilac, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }),
	})
	Theme.text({ Size = UDim2.new(1, -30, 0.11, 0), Position = UDim2.new(0, 15, 0.03, 0), Text = "TOP KEEPERS", TextColor3 = C.Lilac, Parent = bg }, "Title")
	local cols = {}
	for i, spec in { { "Overtime", "HIGHEST OVERTIME" }, { "Rescues", "MOST RESCUES" } } do
		local col = Theme.new("Frame", { Size = UDim2.new(0.5, -22, 0.8, 0), Position = UDim2.new((i - 1) * 0.5, 15, 0.16, 0), BackgroundTransparency = 1, Parent = bg })
		Theme.text({ Size = UDim2.new(1, 0, 0.09, 0), Text = spec[2], TextColor3 = C.Sub, Parent = col }, "Title")
		local rows = {}
		for r = 1, 10 do
			local lbl = Theme.text({ Size = UDim2.new(1, 0, 0.083, 0), Position = UDim2.new(0, 0, 0.1 + (r - 1) * 0.09, 0), Text = "", TextXAlignment = Enum.TextXAlignment.Left, Parent = col }, "Bold")
			rows[r] = lbl
		end
		cols[spec[1]] = rows
	end
	local function fmtN(n: number): string
		local s = tostring(math.floor(n))
		return (s:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", ""))
	end
	local function render()
		local ok, t = pcall(function()
			return game:GetService("HttpService"):JSONDecode(data.Value)
		end)
		t = ok and t or {}
		for board2, rows in cols do
			local list = {}
			for _, e in t[board2] or {} do
				if board2 ~= "Overtime" or (e.ot or 0) > 0 then
					table.insert(list, e)
				end
			end
			for r, lbl in rows do
				local e = list[r]
				if e then
					local value = board2 == "Overtime" and string.format("OT %d · %s", e.ot, fmtN(e.r)) or fmtN(e.r)
					lbl.Text = string.format("%d.  %s   %s", r, e.n or "?", value)
					lbl.TextColor3 = e.id == player.UserId and Color3.fromRGB(40, 160, 110) or C.Ink
				else
					lbl.Text = r == 1 and #list == 0 and "no scores yet" or ""
					lbl.TextColor3 = C.Sub
				end
			end
		end
	end
	data:GetPropertyChangedSignal("Value"):Connect(render)
	render()
end

function WorldFx.start()
	local map = workspace:WaitForChild("Map")
	task.spawn(setupPoster, map)
	task.spawn(setupLeaderboard, map)
	task.spawn(function()
		local last = nil
		while true do
			local char = player.Character
			local hrp = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
			local inFood = not hrp or Config.wingAt(hrp.Position) == "FoodCourt"
			if inFood ~= last then
				last = inFood
				placeProps(map, inFood)
			end
			task.wait(0.5)
		end
	end)
	setupEscalators(map)
	local arcade = map:WaitForChild("Arcade")
	local floor = arcade:WaitForChild("DanceFloor")
	for _, t in floor:GetChildren() do
		if t:IsA("BasePart") then
			table.insert(danceTiles, { part = t, parity = t:GetAttribute("DanceTile") or 0, hue = math.random() })
		end
	end
	danceThump = floor:FindFirstChild("Thump", true) :: Sound?
	for _, d in map:GetDescendants() do
		if d:IsA("BillboardGui") and d:GetAttribute("FloatLabel") then
			table.insert(floatLabels, { gui = d, seed = math.random() * 6 })
		elseif d:IsA("BasePart") and d:GetAttribute("Gate") then
			local wing = d:GetAttribute("Gate")
			local label = map:FindFirstChild("Labels") and map.Labels:FindFirstChild("Label_" .. wing .. "Gate")
			local sub = label and label:FindFirstChild("Sub", true) :: TextLabel?
			table.insert(gateParts, { part = d, wing = wing, sub = sub, locked = sub and sub.Text, prompt = d:FindFirstChild("GatePrompt") })
		elseif d:IsA("BasePart") and d:GetAttribute("ArcadeScreen") then
			table.insert(screens, d)
		end
	end
	RunService.RenderStepped:Connect(updateEscalators)
	-- squeaky toys squeak under anyone's feet (local feedback; carried creatures also hear it server-side)
	local toys = {}
	for _, d in map:GetDescendants() do
		if d:IsA("BasePart") and d:GetAttribute("SqueakToy") then
			table.insert(toys, d)
		end
	end
	local onToy = nil
	RunService.Heartbeat:Connect(function()
		local char = player.Character
		local hrp = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not hrp or hrp.Position.X > -100 or hrp.Position.X < -160 then
			onToy = nil
			return
		end
		local hit = nil
		for _, t in toys do
			local dx, dz = t.Position.X - hrp.Position.X, t.Position.Z - hrp.Position.Z
			if math.abs(dx) < 1.8 and math.abs(dz) < 1.8 then
				hit = t
				break
			end
		end
		if hit and hit ~= onToy and not player:GetAttribute("Carrying") then
			CreatureView.playAt(hit, "rbxasset://sounds/electronicpingshort.wav", 0.5, 2.6)
			TweenService:Create(hit, TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, 0, true), { Size = hit.Size * Vector3.new(1.15, 0.6, 1.15) }):Play()
		end
		onToy = hit
	end)
	-- arcade screens drift through pastel colours
	task.spawn(function()
		while true do
			for _, sc in screens do
				if math.random() < 0.3 then
					TweenService:Create(sc, TweenInfo.new(0.8), { Color = Color3.fromHSV(math.random(), 0.5, 0.95) }):Play()
				end
			end
			task.wait(1)
		end
	end)
	-- rare beams pulse
	for _, d in map:GetDescendants() do
		if d:IsA("BasePart") and d:GetAttribute("RareBeam") then
			TweenService:Create(d, TweenInfo.new(1.2, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Size = d.Size + Vector3.new(0, 1.5, 1.5) }):Play()
		end
	end
end

return WorldFx

-- Builds the Wildbound world at runtime: terrain, the Haven hub town and the regions, plus the
-- data the combat system needs (camps, campfires, region bounds).
--
-- Layout (studs, +Z is north, ground at Y = 0):
--   Haven (hub)        around (0, 0, 0), radius ~95; exit arch north at Z 95
--   Sprout Meadow      X -230..230, Z 110..560 (levels 1-9), boss arena at (0, 0, 520)
--   Ember Canyon       east of the meadow (M5), Tide Coast west (M5)
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Theme = require(ReplicatedStorage.Shared.Theme)
local Config = require(ReplicatedStorage.Shared.Config)

local TC = Theme.C
local World = {}

local root: Folder
local labels: Folder
local terrain = workspace.Terrain

World.Points = {
	Spawn = Vector3.new(0, 0, -16),
	Storage = Vector3.new(-48, 0, 14),
	Shrine = Vector3.new(48, 0, 14),
	Smith = Vector3.new(-34, 0, -46),
	QuestBoard = Vector3.new(34, 0, -46),
	Board = Vector3.new(0, 0, -66),
}

World.Regions = {} -- id -> { Name, Bounds = {x0, x1, z0, z1}, Levels = {min, max}, Elements = {weights}, Pool = {species weights}, Campfire, Boss }
World.Camps = {} -- { id, region, pos, radius, count, lv = {min, max} }
World.Campfires = {} -- { region, pos, part }

----------------------------------------------------------------------------------------------
-- helpers

local function part(props: { [string]: any }, parent: Instance?): BasePart
	local p = Instance.new(props.ClassName or "Part")
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Material = Enum.Material.SmoothPlastic
	for k, v in props do
		if k ~= "ClassName" then
			(p :: any)[k] = v
		end
	end
	p.Parent = parent or root
	return p :: BasePart
end

local function box(name, x0, y0, z0, x1, y1, z1, color, parent)
	return part({
		Name = name,
		Size = Vector3.new(math.abs(x1 - x0), math.abs(y1 - y0), math.abs(z1 - z0)),
		Position = Vector3.new((x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2),
		Color = color,
	}, parent)
end

local function decor(p: BasePart): BasePart
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	return p
end

local function float(name: string, pos: Vector3, text: string, accent: Color3, width: number, opts: { [string]: any }?)
	local anchor = part({ Name = "Label_" .. name, Size = Vector3.new(1, 1, 1), Position = pos, Transparency = 1, CanCollide = false, CanQuery = false, CanTouch = false }, labels)
	Theme.floatLabel(anchor, text, accent, width, opts)
	return anchor
end
World.float = float

-- Ground height at (x, z) from terrain and world parts.
local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Include
function World.groundY(x: number, z: number): number
	local hit = workspace:Raycast(Vector3.new(x, 200, z), Vector3.new(0, -400, 0), rayParams)
	return hit and hit.Position.Y or 0
end

local function tree(x: number, z: number, scale: number, parent: Instance)
	local y = World.groundY(x, z)
	local h = 7 * scale
	part({ Name = "Trunk", Shape = Enum.PartType.Cylinder, Size = Vector3.new(h, 1.6 * scale, 1.6 * scale), CFrame = CFrame.new(x, y + h / 2, z) * CFrame.Angles(0, 0, math.rad(90)), Color = Color3.fromRGB(150, 110, 86) }, parent)
	local leaf = Color3.fromHSV(0.28 + math.random() * 0.08, 0.38, 0.86)
	for i = 1, 3 do
		local r = (5 - i) * 1.6 * scale
		local o = Vector3.new((math.random() - 0.5) * 2 * scale, h + (i - 1) * 2.2 * scale, (math.random() - 0.5) * 2 * scale)
		part({ Name = "Leaves", Shape = Enum.PartType.Ball, Size = Vector3.new(r, r, r), Position = Vector3.new(x, y, z) + o, Color = leaf, CanCollide = i == 1 }, parent)
	end
end

local function rock(x: number, z: number, s: number, parent: Instance)
	local y = World.groundY(x, z)
	part({ Name = "Rock", Shape = Enum.PartType.Ball, Size = Vector3.new(s * 1.4, s, s * 1.2), Position = Vector3.new(x, y + s * 0.25, z), Color = Color3.fromRGB(196, 198, 210) }, parent)
end

local function flowers(x0, z0, x1, z1, n, parent: Instance)
	local pal = { TC.Rose, TC.Sun, TC.Lilac, TC.Sky, Color3.new(1, 1, 1) }
	for i = 1, n do
		local x, z = x0 + math.random() * (x1 - x0), z0 + math.random() * (z1 - z0)
		local y = World.groundY(x, z)
		decor(part({ Name = "Flower", Shape = Enum.PartType.Ball, Size = Vector3.new(0.7, 0.5, 0.7), Position = Vector3.new(x, y + 0.3, z), Color = pal[i % #pal + 1] }, parent))
	end
end

-- Glowing pad that opens a panel on the client.
local function pad(name: string, pos: Vector3, accent: Color3, parent: Instance)
	local p = part({
		Name = name .. "Pad",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.3, 7, 7),
		CFrame = CFrame.new(pos + Vector3.new(0, 0.15, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		Color = accent,
		Material = Enum.Material.Neon,
		CanCollide = false,
		CanQuery = false,
	}, parent)
	p:SetAttribute("Pad", name)
	return p
end

-- A campfire checkpoint: a spawn location that heals and becomes your respawn point.
local function campfire(region: string, pos: Vector3, parent: Instance)
	local y = World.groundY(pos.X, pos.Z)
	local p = Vector3.new(pos.X, y, pos.Z)
	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "Campfire_" .. region
	spawn.Anchored = true
	spawn.Size = Vector3.new(8, 0.4, 8)
	spawn.CFrame = CFrame.new(p + Vector3.new(0, 0.2, 0))
	spawn.Color = Color3.fromRGB(226, 210, 190)
	spawn.Material = Enum.Material.SmoothPlastic
	spawn.Duration = 0
	-- Haven is the default spawn; the others only become your spawn once you light them
	spawn.Neutral = region == "Haven"
	spawn.Enabled = true
	spawn.Parent = parent
	for i = 0, 4 do
		local a = i / 5 * math.pi * 2
		part({ Name = "Log", Size = Vector3.new(0.6, 0.6, 3), CFrame = CFrame.new(p + Vector3.new(math.cos(a) * 1, 0.6, math.sin(a) * 1)) * CFrame.Angles(0.5, a, 0), Color = Color3.fromRGB(150, 104, 78), CanCollide = false }, parent)
	end
	local flame = decor(part({ Name = "Flame", Shape = Enum.PartType.Ball, Size = Vector3.new(1.6, 2.4, 1.6), Position = p + Vector3.new(0, 1.6, 0), Color = Color3.fromRGB(255, 170, 80), Material = Enum.Material.Neon }, parent))
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 190, 120)
	light.Range = 16
	light.Brightness = 1.2
	light.Parent = flame
	local fire = Instance.new("Fire")
	fire.Heat = 4
	fire.Size = 3
	fire.Parent = flame
	spawn:SetAttribute("Campfire", region)
	table.insert(World.Campfires, { region = region, pos = p, part = spawn })
	float("Camp_" .. region, p + Vector3.new(0, 9, 0), "CAMPFIRE", TC.Peach, 7, { Icon = "🔥", Sub = "heals your team · respawn here", Height = 2.2 })
	return spawn
end

----------------------------------------------------------------------------------------------
-- terrain

local function terrainBase()
	terrain:Clear()
	-- one big grass field; regions paint their own materials on top
	terrain:FillBlock(CFrame.new(0, -8, 200), Vector3.new(1600, 16, 1000), Enum.Material.Grass)
	terrain:FillBlock(CFrame.new(0, -24, 200), Vector3.new(1600, 16, 1000), Enum.Material.Ground)
end

local function hill(x: number, z: number, r: number, h: number, material: Enum.Material?)
	terrain:FillBall(Vector3.new(x, h - r, z), r, material or Enum.Material.Grass)
end

local function pathStrip(a: Vector3, b: Vector3, width: number)
	local mid = (a + b) / 2
	local len = (b - a).Magnitude
	terrain:FillBlock(CFrame.lookAt(Vector3.new(mid.X, -1.5, mid.Z), Vector3.new(b.X, -1.5, b.Z)), Vector3.new(width, 3, len), Enum.Material.Ground)
end

----------------------------------------------------------------------------------------------
-- Haven (hub)

local function building(name: string, pos: Vector3, accent: Color3, w: number, d: number, h: number, parent: Instance)
	local f = Instance.new("Folder")
	f.Name = name
	f.Parent = parent
	local x, z = pos.X, pos.Z
	box("Walls", x - w / 2, 0, z - d / 2, x + w / 2, h, z + d / 2, Color3.fromRGB(252, 248, 242), f)
	box("Trim", x - w / 2 - 0.2, 0, z - d / 2 - 0.2, x + w / 2 + 0.2, 1.2, z + d / 2 + 0.2, Theme.tint(accent, 0.4), f)
	-- simple pitched roof from two wedges
	for _, side in { -1, 1 } do
		part({
			ClassName = "WedgePart",
			Name = "Roof",
			Size = Vector3.new(w + 2, h * 0.5, d / 2 + 1),
			CFrame = CFrame.new(x, h + h * 0.25, z + side * (d / 4 + 0.5)) * CFrame.Angles(0, side > 0 and 0 or math.pi, 0),
			Color = accent,
		}, f)
	end
	-- door facing the plaza (toward the centre)
	local toCentre = (Vector3.new(0, 0, 0) - Vector3.new(x, 0, z)).Unit
	local doorPos = Vector3.new(x, 0, z) + toCentre * (math.abs(toCentre.X) > math.abs(toCentre.Z) and w / 2 or d / 2)
	decor(part({ Name = "Door", Size = Vector3.new(4, 7, 0.4), CFrame = CFrame.lookAt(doorPos + Vector3.new(0, 3.5, 0), doorPos + Vector3.new(0, 3.5, 0) + toCentre), Color = Theme.tint(accent, 0.25) }, f))
	return f, doorPos + toCentre * 6
end

local function buildHaven()
	local f = Instance.new("Folder")
	f.Name = "Haven"
	f.Parent = root
	-- plaza
	terrain:FillCylinder(CFrame.new(0, -1, 0), 2, 46, Enum.Material.Pavement)
	terrain:FillCylinder(CFrame.new(0, -1, 0), 2.2, 18, Enum.Material.Cobblestone)
	pathStrip(Vector3.new(0, 0, 40), Vector3.new(0, 0, 130), 14)
	float("Haven", Vector3.new(0, 26, 0), "HAVEN", TC.Mint, 16, { Icon = "🏡", Sub = "home of the Tamers", Height = 3.6 })
	-- fountain-ish centrepiece
	part({ Name = "Monument", Shape = Enum.PartType.Cylinder, Size = Vector3.new(2, 12, 12), CFrame = CFrame.new(0, 1, 18) * CFrame.Angles(0, 0, math.rad(90)), Color = Color3.fromRGB(236, 232, 246) }, f)
	decor(part({ Name = "Crystal", Size = Vector3.new(3, 6, 3), CFrame = CFrame.new(0, 6, 18) * CFrame.Angles(0, math.rad(45), math.rad(10)), Color = TC.Sky, Material = Enum.Material.Neon, Transparency = 0.15 }, f))

	local _, storageDoor = building("StorageHouse", Vector3.new(-62, 0, 14), TC.Lilac, 18, 16, 10, f)
	World.Points.Storage = Vector3.new(storageDoor.X, 0, storageDoor.Z)
	pad("Storage", World.Points.Storage, TC.Lilac, f)
	float("Storage", World.Points.Storage + Vector3.new(0, 14, 0), "MONSTERS", TC.Lilac, 9, { Icon = "📦", Sub = "team & storage", Height = 2.4 })

	-- Summoning Shrine: a ring of pillars around a floating scroll
	local sp = Vector3.new(60, 0, 14)
	part({ Name = "ShrineBase", Shape = Enum.PartType.Cylinder, Size = Vector3.new(1.2, 18, 18), CFrame = CFrame.new(sp + Vector3.new(0, 0.6, 0)) * CFrame.Angles(0, 0, math.rad(90)), Color = Color3.fromRGB(244, 240, 252) }, f)
	for i = 0, 5 do
		local a = i / 6 * math.pi * 2
		part({ Name = "Pillar", Shape = Enum.PartType.Cylinder, Size = Vector3.new(10, 1.6, 1.6), CFrame = CFrame.new(sp + Vector3.new(math.cos(a) * 8, 5.6, math.sin(a) * 8)) * CFrame.Angles(0, 0, math.rad(90)), Color = Color3.fromRGB(236, 230, 250) }, f)
		decor(part({ Name = "PillarGem", Shape = Enum.PartType.Ball, Size = Vector3.new(1.4, 1.4, 1.4), Position = sp + Vector3.new(math.cos(a) * 8, 11, math.sin(a) * 8), Color = TC.Lilac, Material = Enum.Material.Neon }, f))
	end
	local scroll = decor(part({ Name = "ShrineScroll", Shape = Enum.PartType.Cylinder, Size = Vector3.new(4, 1.2, 1.2), CFrame = CFrame.new(sp + Vector3.new(0, 7, 0)), Color = TC.Sun, Material = Enum.Material.Neon }, f))
	scroll:SetAttribute("Spin", true)
	World.Points.Shrine = sp + Vector3.new(-12, 0, 0)
	pad("Shrine", World.Points.Shrine, TC.Sun, f)
	float("Shrine", sp + Vector3.new(0, 17, 0), "SUMMONING SHRINE", TC.Sun, 12, { Icon = "📜", Sub = "open scrolls for monsters", Height = 3 })

	local _, smithDoor = building("Smithy", Vector3.new(-44, 0, -56), TC.Peach, 16, 14, 9, f)
	World.Points.Smith = Vector3.new(smithDoor.X, 0, smithDoor.Z)
	pad("Smith", World.Points.Smith, TC.Peach, f)
	float("Smith", World.Points.Smith + Vector3.new(0, 13, 0), "WEAPON SMITH", TC.Peach, 9, { Icon = "⚔", Sub = "weapons & upgrades", Height = 2.4 })

	-- quest board
	local qb = Vector3.new(36, 0, -50)
	box("QuestPostL", qb.X - 4, 0, qb.Z, qb.X - 3.4, 8, qb.Z + 0.6, Color3.fromRGB(170, 130, 100), f)
	box("QuestPostR", qb.X + 3.4, 0, qb.Z, qb.X + 4, 8, qb.Z + 0.6, Color3.fromRGB(170, 130, 100), f)
	box("QuestBoard", qb.X - 4, 3, qb.Z - 0.2, qb.X + 4, 7.5, qb.Z + 0.4, Color3.fromRGB(226, 196, 160), f)
	World.Points.QuestBoard = qb + Vector3.new(0, 0, 6)
	pad("Quests", World.Points.QuestBoard, TC.Sky, f)
	float("Quests", qb + Vector3.new(0, 12, 0), "QUEST BOARD", TC.Sky, 9, { Icon = "📋", Sub = "daily quests & rewards", Height = 2.4 })

	-- leaderboard (clients draw the scores)
	local bp = Vector3.new(0, 4.8, -70)
	local board = part({ Name = "LeaderBoard", Size = Vector3.new(14, 8, 0.4), CFrame = CFrame.lookAt(bp, bp + Vector3.new(0, 0, 1)), Color = Color3.fromRGB(250, 248, 255), CanCollide = false }, f)
	board:SetAttribute("LeaderBoard", true)
	float("TopTamers", Vector3.new(0, 14, -70), "TOP TAMERS", TC.Lilac, 10, { Icon = "★", Sub = "best in every server", Height = 2.4 })

	-- exit arch to the meadow
	for _, x in { -9, 9 } do
		box("ArchPost", x - 1, 0, 92, x + 1, 14, 94, Color3.fromRGB(236, 230, 250), f)
	end
	box("ArchTop", -10, 14, 92, 10, 16, 94, TC.Mint, f)
	float("ToMeadow", Vector3.new(0, 20, 93), "SPROUT MEADOW", TC.Mint, 11, { Icon = "🌱", Sub = "levels 1-9 · wild monsters", Height = 3 })

	-- town dressing
	for _, t in { { -80, -30 }, { 80, -30 }, { -86, 50 }, { 86, 50 }, { -30, 70 }, { 30, 70 }, { -70, -80 }, { 70, -80 } } do
		tree(t[1], t[2], 1.1, f)
	end
	flowers(-90, -90, 90, 90, 140, f)
	campfire("Haven", World.Points.Spawn, f)
end

----------------------------------------------------------------------------------------------
-- Sprout Meadow (levels 1-9)

local function buildSproutMeadow()
	local f = Instance.new("Folder")
	f.Name = "SproutMeadow"
	f.Parent = root
	World.Regions.SproutMeadow = {
		Id = "SproutMeadow",
		Name = "Sprout Meadow",
		Bounds = { -240, 240, 100, 570 },
		Elements = { Fire = 33, Water = 33, Wind = 33, Light = 0.5, Dark = 0.5 },
		-- wild species weights by stars: mostly filler, a little 3-star core
		StarWeights = { 55, 40, 5, 0, 0 },
	}
	-- rolling hills (kept off the main path)
	for _, h in { { -120, 200, 60, 10 }, { 140, 230, 70, 12 }, { -170, 360, 80, 16 }, { 170, 400, 70, 14 }, { -60, 450, 50, 8 }, { 90, 320, 40, 7 } } do
		hill(h[1], h[2], h[3], h[4])
	end
	pathStrip(Vector3.new(0, 0, 130), Vector3.new(0, 0, 300), 12)
	pathStrip(Vector3.new(0, 0, 300), Vector3.new(0, 0, 500), 12)
	float("Meadow", Vector3.new(0, 30, 200), "SPROUT MEADOW", TC.Mint, 20, { Icon = "🌱", Height = 4.2 })

	-- windmill landmark
	local wm = Vector3.new(-110, World.groundY(-110, 300), 300)
	part({ Name = "MillTower", Shape = Enum.PartType.Cylinder, Size = Vector3.new(22, 8, 8), CFrame = CFrame.new(wm + Vector3.new(0, 11, 0)) * CFrame.Angles(0, 0, math.rad(90)), Color = Color3.fromRGB(252, 246, 236) }, f)
	part({ Name = "MillCap", Shape = Enum.PartType.Ball, Size = Vector3.new(9, 6, 9), Position = wm + Vector3.new(0, 22, 0), Color = TC.Rose }, f)
	local hub = decor(part({ Name = "MillHub", Size = Vector3.new(1.5, 1.5, 1.5), Position = wm + Vector3.new(0, 19, -4.6), Color = Color3.fromRGB(170, 130, 100) }, f))
	hub:SetAttribute("MillHub", true)
	for i = 0, 3 do
		local blade = decor(part({ Name = "MillBlade", Size = Vector3.new(1.6, 9, 0.3), CFrame = CFrame.new(hub.Position) * CFrame.Angles(0, 0, i * math.pi / 2) * CFrame.new(0, 4.5, 0), Color = Color3.fromRGB(250, 250, 255) }, hub))
		local w = Instance.new("WeldConstraint")
		w.Part0 = hub
		w.Part1 = blade
		w.Parent = blade
		blade.Anchored = false
	end

	-- trees, rocks, flowers
	for i = 1, 70 do
		local x = (math.random() * 2 - 1) * 225
		local z = 120 + math.random() * 440
		if math.abs(x) > 20 then
			tree(x, z, 0.8 + math.random() * 0.7, f)
		end
	end
	for i = 1, 25 do
		local x = (math.random() * 2 - 1) * 220
		local z = 130 + math.random() * 420
		if math.abs(x) > 16 then
			rock(x, z, 2 + math.random() * 3, f)
		end
	end
	flowers(-220, 120, 220, 560, 500, f)

	campfire("SproutMeadow", Vector3.new(14, 0, 300), f)

	-- wild camps: levels rise as you head north
	local camps = {
		{ -40, 160, 1, 2 }, { 50, 170, 1, 2 }, { -100, 220, 2, 3 }, { 90, 240, 2, 3 },
		{ -60, 290, 3, 4 }, { 70, 300, 3, 5 }, { -150, 330, 4, 5 }, { 150, 350, 4, 6 },
		{ -70, 400, 5, 7 }, { 80, 420, 6, 7 }, { -140, 460, 7, 8 }, { 140, 470, 7, 9 },
	}
	for i, c in camps do
		table.insert(World.Camps, { id = "SM" .. i, region = "SproutMeadow", pos = Vector3.new(c[1], 0, c[2]), radius = 14, count = 3, lv = { c[3], c[4] } })
	end
	-- boss arena (the boss itself arrives in M5)
	local arena = Vector3.new(0, World.groundY(0, 520), 520)
	terrain:FillCylinder(CFrame.new(arena.X, -1, arena.Z), 2.2, 30, Enum.Material.Cobblestone)
	for i = 0, 7 do
		local a = i / 8 * math.pi * 2
		part({ Name = "ArenaStone", Size = Vector3.new(3, 10, 3), Position = arena + Vector3.new(math.cos(a) * 32, 5, math.sin(a) * 32), Color = Color3.fromRGB(226, 228, 238) }, f)
	end
	World.Regions.SproutMeadow.BossArena = arena
	float("MeadowBoss", arena + Vector3.new(0, 24, 0), "GUARDIAN'S RING", TC.Coral, 12, { Icon = "👑", Sub = "region boss", Height = 3 })
end

----------------------------------------------------------------------------------------------

-- Which region a position is in ("Haven" if none).
function World.regionAt(pos: Vector3): string
	for id, r in World.Regions do
		local b = r.Bounds
		if pos.X >= b[1] and pos.X <= b[2] and pos.Z >= b[3] and pos.Z <= b[4] then
			return id
		end
	end
	return "Haven"
end

function World.build(): Folder
	root = Instance.new("Folder")
	root.Name = "World"
	labels = Instance.new("Folder")
	labels.Name = "Labels"
	labels.Parent = root
	terrainBase()
	rayParams.FilterDescendantsInstances = { terrain }
	buildHaven()
	buildSproutMeadow()
	if World.extraRegions then
		World.extraRegions(World, { part = part, box = box, decor = decor, tree = tree, rock = rock, flowers = flowers, hill = hill, pathStrip = pathStrip, campfire = campfire, float = float, root = root })
	end
	root.Parent = workspace
	return root
end

function World.setupLighting()
	local Lighting = game:GetService("Lighting")
	Lighting.ClockTime = 13
	Lighting.GeographicLatitude = 35
	Lighting.Brightness = 2.2
	Lighting.Ambient = Color3.fromRGB(130, 132, 150)
	Lighting.OutdoorAmbient = Color3.fromRGB(150, 152, 170)
	Lighting.EnvironmentDiffuseScale = 1
	Lighting.EnvironmentSpecularScale = 0.4
	Lighting.GlobalShadows = true
	for _, c in Lighting:GetChildren() do
		if c:IsA("PostEffect") or c:IsA("Atmosphere") or c:IsA("Sky") then
			c:Destroy()
		end
	end
	local cc = Instance.new("ColorCorrectionEffect")
	cc.Saturation = 0.15
	cc.Contrast = 0.08
	cc.Parent = Lighting
	local atm = Instance.new("Atmosphere")
	atm.Density = 0.25
	atm.Offset = 0.15
	atm.Color = Color3.fromRGB(220, 232, 255)
	atm.Decay = Color3.fromRGB(180, 200, 240)
	atm.Haze = 0.6
	atm.Parent = Lighting
	local bloom = Instance.new("BloomEffect")
	bloom.Intensity = 0.25
	bloom.Threshold = 2
	bloom.Parent = Lighting
	terrain.WaterColor = Color3.fromRGB(110, 190, 240)
	terrain.WaterTransparency = 0.6
	terrain:SetMaterialColor(Enum.Material.Grass, Color3.fromRGB(140, 206, 120))
	terrain:SetMaterialColor(Enum.Material.Ground, Color3.fromRGB(214, 190, 150))
	terrain:SetMaterialColor(Enum.Material.Pavement, Color3.fromRGB(230, 226, 220))
	terrain:SetMaterialColor(Enum.Material.Cobblestone, Color3.fromRGB(210, 206, 214))
end

return World

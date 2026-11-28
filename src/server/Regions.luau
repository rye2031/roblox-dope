-- Regions beyond Sprout Meadow, region bosses, gates, elites and the world boss (M5).
--
--   Sprout Meadow (1-9, boss Lv 10)  ->  Ember Canyon (east, 9-16, Fire 60%, boss Lv 18)
--                                     ->  Tide Coast  (west, 15-24, Water 60%, boss Lv 26)
-- A region opens when you beat the previous region's boss, or when one of your monsters is
-- over-levelled for it (PassLevel). Gates are walls in collision group Gate_<region>; a
-- character in Pass_<n> walks through the first n gates (regions open in order).
-- World boss: every 30 min (UTC-aligned) a 5-star titan appears at the Titan Field east of
-- Haven for 6 minutes; everyone who helps gets boss loot.
local Players = game:GetService("Players")
local PhysicsService = game:GetService("PhysicsService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Monsters = require(ReplicatedStorage.Shared.Monsters)
local Theme = require(ReplicatedStorage.Shared.Theme)
local PlayerData = require(script.Parent.PlayerData)
local Story = require(script.Parent.Story)
local Places = require(ReplicatedStorage.Shared.Places)

local TC = Theme.C
local Regions = {}

local World
local Combat
local remotes

-- Order matters: each region needs the previous one's boss.
Regions.Order = { "SproutMeadow", "EmberCanyon", "TideCoast", "GaleHighlands", "TwilightVale" }
Regions.Info = {
	SproutMeadow = { Name = "Sprout Meadow", Boss = { sp = "Sproutknight", el = "Wind", lv = 10, title = "Meadow Guardian" } },
	EmberCanyon = { Name = "Ember Canyon", PassLevel = 14, Boss = { sp = "Drakoryn", el = "Fire", lv = 18, title = "Canyon Tyrant" } },
	TideCoast = { Name = "Tide Coast", PassLevel = 22, Boss = { sp = "Shellotl", el = "Water", lv = 26, title = "Tide Monarch" } },
	GaleHighlands = { Name = "Gale Highlands", PassLevel = 30, Boss = { sp = "Zephyrion", el = "Wind", lv = 34, title = "Sky Sovereign" } },
	-- the Warden is Light by day and Dark by night
	TwilightVale = { Name = "Twilight Vale", PassLevel = 38, Boss = { sp = "Solmora", el = "Light", lv = 42, title = "Eclipse Warden" } },
}
local BOSS_HP = 8 -- region bosses: x8 a normal wild monster (soloable by a ready team)
local BOSS_RESPAWN = 120
-- Titan: a group fight. Lv 28 and x36 HP (it also gains +60% HP per extra player hitting it),
-- so a mid-level team can't solo it in a minute (owner, 2026-11-27: Lv 11 teams did).
local WORLD_EVERY, WORLD_LASTS, WORLD_LEVEL, WORLD_HP = 30 * 60, 6 * 60, 28, 36
local WORLD_POS = Vector3.new(170, 0, -10)

local bossCamps: { [string]: any } = {}
local worldCamp: any = nil
local worldActive = false

----------------------------------------------------------------------------------------------
-- Building

local terrain = workspace.Terrain

-- Region borders are mountain ranges now (closed valleys, 2026-11-27); gaps are gone because
-- portals carry you between places. `ridgeLook` is set by each region builder.
local ridgeLook: { material: Enum.Material?, cap: Enum.Material?, height: number? } = {}
local function ridge(h, a: Vector3, b: Vector3, _gapAt: Vector3?, _gapWidth: number?)
	World.mountainRange(a, b, { material = ridgeLook.material, cap = ridgeLook.cap, height = ridgeLook.height })
end

local function gate(h, region: string, pos: Vector3, facing: Vector3, width: number, accent: Color3, text: string, sub: string)
	local cf = CFrame.lookAt(pos, pos + facing)
	local wall = h.part({ Name = "Gate_" .. region, Size = Vector3.new(width, 40, 2), CFrame = cf * CFrame.new(0, 20, 0), Color = accent, Material = Enum.Material.ForceField, Transparency = 0.2, CollisionGroup = "Gate_" .. region })
	wall:SetAttribute("Gate", region)
	for _, side in { -1, 1 } do
		h.part({ Name = "GatePost", Size = Vector3.new(4, 26, 4), CFrame = cf * CFrame.new(side * (width / 2 + 2), 13, 0), Color = Color3.fromRGB(236, 230, 250) })
	end
	h.part({ Name = "GateTop", Size = Vector3.new(width + 8, 3, 4), CFrame = cf * CFrame.new(0, 27.5, 0), Color = accent })
	h.float("Gate_" .. region, pos + Vector3.new(0, 34, 0), text, accent, 13, { Icon = "🚪", Sub = sub, Height = 3 })
	return wall
end

local function arena(h, region: string, centre: Vector3, accent: Color3, stone: Color3, title: string)
	terrain:FillCylinder(CFrame.new(centre.X, -1, centre.Z), 2.2, 30, Enum.Material.Cobblestone)
	for i = 0, 7 do
		local a = i / 8 * math.pi * 2
		h.part({ Name = "ArenaStone", Size = Vector3.new(3, 10, 3), Position = centre + Vector3.new(math.cos(a) * 32, 5, math.sin(a) * 32), Color = stone })
	end
	h.float("Boss_" .. region, centre + Vector3.new(0, 24, 0), title:upper(), accent, 12, { Icon = "👑", Sub = "region boss", Height = 3 })
end

local function addCamps(region: string, prefix: string, list)
	for i, c in list do
		table.insert(World.Camps, { id = prefix .. i, region = region, pos = Vector3.new(c[1], 0, c[2]), radius = 14, count = 3, lv = { c[3], c[4] } })
	end
end

local function bossCamp(region: string, pos: Vector3)
	local b = Regions.Info[region].Boss
	local camp = { id = region .. "Boss", region = region, pos = pos, radius = 2, count = 1, lv = { b.lv, b.lv }, boss = true, species = b.sp, element = b.el, hpMult = BOSS_HP }
	table.insert(World.Camps, camp)
	bossCamps[region] = camp
end

local function palm(h, x: number, z: number, s: number)
	local y = World.groundY(x, z)
	local hgt = 10 * s
	h.part({ Name = "PalmTrunk", Shape = Enum.PartType.Cylinder, Size = Vector3.new(hgt, 1.2 * s, 1.2 * s), CFrame = CFrame.new(x, y + hgt / 2, z) * CFrame.Angles(0, 0, math.rad(84)), Color = Color3.fromRGB(196, 160, 120) })
	for i = 0, 4 do
		local a = i / 5 * math.pi * 2
		h.decor(h.part({ Name = "Frond", Size = Vector3.new(1.4 * s, 0.3, 6 * s), CFrame = CFrame.new(x, y + hgt, z) * CFrame.Angles(0, a, 0) * CFrame.new(0, -0.6 * s, 3 * s) * CFrame.Angles(math.rad(-20), 0, 0), Color = Color3.fromRGB(120, 196, 120) }))
	end
end

local function buildEmberCanyon(h)
	local f = Instance.new("Folder")
	f.Name = "EmberCanyon"
	f.Parent = h.root
	local function P(props)
		return h.part(props, f)
	end
	local x0, x1, z0, z1 = 260, 700, 100, 570
	World.Regions.EmberCanyon = {
		Id = "EmberCanyon",
		Name = "Ember Canyon",
		Bounds = { x0, x1, z0, z1 },
		Elements = { Fire = 60, Water = 17, Wind = 22, Light = 0.5, Dark = 0.5 },
		StarWeights = { 30, 45, 21, 4, 0 },
		EliteChance = 0.06,
	}
	terrain:SetMaterialColor(Enum.Material.Sandstone, Color3.fromRGB(232, 150, 112))
	terrain:SetMaterialColor(Enum.Material.Rock, Color3.fromRGB(190, 170, 176))
	terrain:ReplaceMaterial(Region3.new(Vector3.new(x0 - 20, -20, z0 - 20), Vector3.new(x1 + 20, 40, z1 + 20)):ExpandToGrid(4), 4, Enum.Material.Grass, Enum.Material.Sandstone)
	for _, m in { { 360, 200, 50, 14 }, { 600, 250, 70, 20 }, { 420, 420, 60, 16 }, { 640, 480, 50, 12 } } do
		terrain:FillBall(Vector3.new(m[1], m[4] - m[3], m[2]), m[3], Enum.Material.Sandstone)
	end
	h.pathStrip(Vector3.new(250, 0, 330), Vector3.new(480, 0, 330), 12)
	h.pathStrip(Vector3.new(480, 0, 330), Vector3.new(560, 0, 520), 12)
	-- rock spires and lava rivers
	for i = 1, 26 do
		local x, z = x0 + 20 + math.random() * (x1 - x0 - 40), z0 + 20 + math.random() * (z1 - z0 - 40)
		if math.abs(z - 330) > 18 then
			local y = World.groundY(x, z)
			local hgt = 10 + math.random() * 22
			P({ Name = "Spire", Size = Vector3.new(5 + math.random() * 5, hgt, 5 + math.random() * 5), CFrame = CFrame.new(x, y + hgt / 2 - 1, z) * CFrame.Angles(0, math.random() * 6, (math.random() - 0.5) * 0.2), Color = Color3.fromRGB(214, 120, 96) })
		end
	end
	for _, r in { { 300, 160, 460, 250 }, { 520, 140, 690, 210 }, { 300, 430, 420, 540 } } do
		local a, b = Vector3.new(r[1], 0, r[2]), Vector3.new(r[3], 0, r[4])
		local mid, len = (a + b) / 2, (b - a).Magnitude
		h.decor(P({ Name = "Lava", Size = Vector3.new(10, 0.4, len), CFrame = CFrame.lookAt(Vector3.new(mid.X, World.groundY(mid.X, mid.Z) + 0.25, mid.Z), Vector3.new(b.X, World.groundY(mid.X, mid.Z) + 0.25, b.Z)), Color = Color3.fromRGB(255, 120, 50), Material = Enum.Material.Neon }))
	end
	-- geysers
	for _, g in { { 330, 300 }, { 560, 380 }, { 470, 180 } } do
		local y = World.groundY(g[1], g[2])
		local base = P({ Name = "Geyser", Shape = Enum.PartType.Cylinder, Size = Vector3.new(1.2, 6, 6), CFrame = CFrame.new(g[1], y + 0.4, g[2]) * CFrame.Angles(0, 0, math.rad(90)), Color = Color3.fromRGB(180, 110, 90) })
		local e = Instance.new("ParticleEmitter")
		e.Texture = "rbxasset://textures/particles/smoke_main.dds"
		e.Color = ColorSequence.new(Color3.fromRGB(255, 240, 230))
		e.Rate = 12
		e.Lifetime = NumberRange.new(1.5, 2.5)
		e.Speed = NumberRange.new(18, 26)
		e.SpreadAngle = Vector2.new(8, 8)
		e.Size = NumberSequence.new(2, 5)
		e.Transparency = NumberSequence.new(0.3, 1)
		e.EmissionDirection = Enum.NormalId.Right
		e.Parent = base
	end
	h.float("Ember", Vector3.new(480, 34, 330), "EMBER CANYON", TC.Coral, 20, { Icon = "🔥", Sub = "levels 9-16 · Fire 60%", Height = 4.2 })
	h.campfire("EmberCanyon", Vector3.new(290, 0, 345), f)
	addCamps("EmberCanyon", "EC", {
		{ 320, 220, 9, 10 }, { 330, 440, 9, 11 }, { 400, 280, 10, 11 }, { 410, 380, 10, 12 },
		{ 480, 200, 11, 13 }, { 500, 460, 12, 13 }, { 580, 300, 13, 14 }, { 620, 400, 13, 15 },
		{ 640, 160, 14, 16 }, { 660, 540, 15, 16 },
	})
	local ac = Vector3.new(600, World.groundY(600, 520), 520)
	arena({ part = P, float = h.float }, "EmberCanyon", ac, TC.Coral, Color3.fromRGB(230, 170, 150), Regions.Info.EmberCanyon.Boss.title)
	World.Regions.EmberCanyon.BossArena = ac
	bossCamp("EmberCanyon", ac)
	-- walls: enclose the canyon; the only way in is the gate on the meadow side
	ridgeLook = { material = Enum.Material.Sandstone }
	local hh = { part = P }
	ridge(hh, Vector3.new(250, 0, z0 - 10), Vector3.new(250, 0, z1 + 10), Vector3.new(250, 0, 330), 24)
	ridge(hh, Vector3.new(250, 0, z0 - 10), Vector3.new(x1 + 10, 0, z0 - 10))
	ridge(hh, Vector3.new(250, 0, z1 + 10), Vector3.new(x1 + 10, 0, z1 + 10))
	ridge(hh, Vector3.new(x1 + 10, 0, z0 - 10), Vector3.new(x1 + 10, 0, z1 + 10))
end

local function buildTideCoast(h)
	local f = Instance.new("Folder")
	f.Name = "TideCoast"
	f.Parent = h.root
	local function P(props)
		return h.part(props, f)
	end
	local x0, x1, z0, z1 = -700, -260, 100, 570
	World.Regions.TideCoast = {
		Id = "TideCoast",
		Name = "Tide Coast",
		Bounds = { x0, x1, z0, z1 },
		Elements = { Water = 60, Fire = 17, Wind = 22, Light = 0.5, Dark = 0.5 },
		StarWeights = { 20, 45, 28, 7, 0 },
		EliteChance = 0.08,
	}
	terrain:SetMaterialColor(Enum.Material.Sand, Color3.fromRGB(244, 228, 190))
	terrain:ReplaceMaterial(Region3.new(Vector3.new(x0 - 20, -20, z0 - 20), Vector3.new(x1 + 20, 40, z1 + 20)):ExpandToGrid(4), 4, Enum.Material.Grass, Enum.Material.Sand)
	-- the sea along the west edge, plus tide pools
	terrain:FillBlock(CFrame.new(-650, -3, 335), Vector3.new(100, 6, 470), Enum.Material.Water)
	for _, t in { { -420, 200, 9 }, { -520, 300, 12 }, { -380, 470, 10 }, { -560, 520, 8 } } do
		terrain:FillCylinder(CFrame.new(t[1], -1.5, t[2]), 3, t[3], Enum.Material.Water)
		h.rock(t[1] + t[3], t[2], 3, f)
	end
	h.pathStrip(Vector3.new(-250, 0, 330), Vector3.new(-470, 0, 330), 12)
	h.pathStrip(Vector3.new(-470, 0, 330), Vector3.new(-540, 0, 500), 12)
	for i = 1, 34 do
		local x, z = x0 + 120 + math.random() * (x1 - x0 - 140), z0 + 20 + math.random() * (z1 - z0 - 40)
		if math.abs(z - 330) > 14 then
			palm({ part = P, decor = h.decor }, x, z, 0.8 + math.random() * 0.5)
		end
	end
	-- shipwreck
	local sw = Vector3.new(-590, World.groundY(-590, 230), 230)
	local cf = CFrame.new(sw) * CFrame.Angles(0, math.rad(30), math.rad(12))
	P({ Name = "Hull", Size = Vector3.new(12, 7, 34), CFrame = cf * CFrame.new(0, 2.5, 0), Color = Color3.fromRGB(150, 110, 86) })
	P({ ClassName = "WedgePart", Name = "Bow", Size = Vector3.new(12, 7, 10), CFrame = cf * CFrame.new(0, 2.5, 22) * CFrame.Angles(0, math.pi, 0), Color = Color3.fromRGB(150, 110, 86) })
	P({ Name = "Mast", Shape = Enum.PartType.Cylinder, Size = Vector3.new(24, 1.4, 1.4), CFrame = cf * CFrame.new(0, 16, 2) * CFrame.Angles(0, 0, math.rad(80)), Color = Color3.fromRGB(170, 130, 100) })
	h.decor(P({ Name = "Sail", Size = Vector3.new(0.3, 10, 12), CFrame = cf * CFrame.new(1, 17, 2) * CFrame.Angles(0, math.rad(90), 0), Color = Color3.fromRGB(250, 246, 236) }))
	h.float("Tide", Vector3.new(-470, 34, 330), "TIDE COAST", TC.Sky, 20, { Icon = "🌊", Sub = "levels 15-24 · Water 60%", Height = 4.2 })
	h.campfire("TideCoast", Vector3.new(-290, 0, 345), f)
	addCamps("TideCoast", "TC", {
		{ -320, 220, 15, 16 }, { -330, 440, 15, 17 }, { -400, 280, 16, 17 }, { -410, 400, 16, 18 },
		{ -470, 190, 17, 19 }, { -480, 470, 18, 19 }, { -540, 340, 19, 21 }, { -560, 420, 20, 22 },
		{ -520, 150, 21, 23 }, { -400, 540, 22, 24 },
	})
	local ac = Vector3.new(-560, World.groundY(-560, 520), 520)
	arena({ part = P, float = h.float }, "TideCoast", ac, TC.Sky, Color3.fromRGB(200, 226, 240), Regions.Info.TideCoast.Boss.title)
	World.Regions.TideCoast.BossArena = ac
	bossCamp("TideCoast", ac)
	ridgeLook = { material = Enum.Material.Rock, cap = Enum.Material.Grass }
	local hh = { part = P }
	ridge(hh, Vector3.new(-250, 0, z0 - 10), Vector3.new(-250, 0, z1 + 10), Vector3.new(-250, 0, 330), 24)
	ridge(hh, Vector3.new(-250, 0, z0 - 10), Vector3.new(x0 - 10, 0, z0 - 10))
	ridge(hh, Vector3.new(-250, 0, z1 + 10), Vector3.new(x0 - 10, 0, z1 + 10))
	ridge(hh, Vector3.new(x0 - 10, 0, z0 - 10), Vector3.new(x0 - 10, 0, z1 + 10))
end

-- Gale Highlands (M8): windswept uplands south of Haven, levels 24-32, Wind 60%.
local function buildGaleHighlands(h)
	local f = Instance.new("Folder")
	f.Name = "GaleHighlands"
	f.Parent = h.root
	local function P(props)
		return h.part(props, f)
	end
	local x0, x1, z0, z1 = -240, 240, -570, -110
	World.Regions.GaleHighlands = {
		Id = "GaleHighlands",
		Name = "Gale Highlands",
		Bounds = { x0, x1, z0, z1 },
		Elements = { Wind = 60, Fire = 17, Water = 22, Light = 0.5, Dark = 0.5 },
		StarWeights = { 10, 35, 40, 13, 2 },
		EliteChance = 0.1,
	}
	terrain:SetMaterialColor(Enum.Material.LeafyGrass, Color3.fromRGB(150, 205, 170))
	terrain:SetMaterialColor(Enum.Material.Slate, Color3.fromRGB(150, 160, 186))
	terrain:ReplaceMaterial(Region3.new(Vector3.new(x0 - 20, -20, z0 - 20), Vector3.new(x1 + 20, 60, z1 + 20)):ExpandToGrid(4), 4, Enum.Material.Grass, Enum.Material.LeafyGrass)
	-- big rolling uplands and slate bluffs (kept off the road)
	for _, m in { { -150, -220, 70, 18 }, { 150, -260, 80, 22 }, { -170, -420, 90, 26 }, { 170, -450, 80, 24 }, { -60, -330, 40, 10 }, { 80, -380, 45, 12 } } do
		terrain:FillBall(Vector3.new(m[1], m[4] - m[3], m[2]), m[3], Enum.Material.LeafyGrass)
	end
	for _, b in { { -200, -160, 18 }, { 210, -340, 22 }, { -210, -500, 20 }, { 120, -540, 16 } } do
		terrain:FillBlock(CFrame.new(b[1], b[3] / 2, b[2]) * CFrame.Angles(0, math.random() * 3, 0), Vector3.new(30, b[3], 24), Enum.Material.Slate)
	end
	h.pathStrip(Vector3.new(0, 0, -95), Vector3.new(0, 0, -330), 12)
	h.pathStrip(Vector3.new(0, 0, -330), Vector3.new(0, 0, -490), 12)
	-- standing stones and floating isles of rock (the wind holds them up)
	for i = 1, 18 do
		local x, z = x0 + 20 + math.random() * (x1 - x0 - 40), z0 + 20 + math.random() * (z1 - z0 - 40)
		if math.abs(x) > 16 then
			local y = World.groundY(x, z)
			local hgt = 6 + math.random() * 10
			P({ Name = "Menhir", Size = Vector3.new(3 + math.random() * 2, hgt, 2.5 + math.random() * 2), CFrame = CFrame.new(x, y + hgt / 2 - 1, z) * CFrame.Angles(0, math.random() * 6, (math.random() - 0.5) * 0.25), Color = Color3.fromRGB(176, 184, 206), Material = Enum.Material.Slate })
		end
	end
	for _, fl in { { -90, -200, 34 }, { 110, -310, 42 }, { -120, -380, 38 }, { 60, -470, 46 } } do
		local isle = P({ Name = "FloatingIsle", Shape = Enum.PartType.Ball, Size = Vector3.new(16, 9, 14), CFrame = CFrame.new(fl[1], fl[3], fl[2]), Color = Color3.fromRGB(150, 160, 186), Material = Enum.Material.Slate })
		isle:SetAttribute("Bob", true)
		h.decor(P({ Name = "IsleGrass", Shape = Enum.PartType.Cylinder, Size = Vector3.new(1.4, 15, 15), CFrame = CFrame.new(fl[1], fl[3] + 4.2, fl[2]) * CFrame.Angles(0, 0, math.rad(90)), Color = Color3.fromRGB(150, 205, 170) }))
	end
	h.float("Gale", Vector3.new(0, 36, -230), "GALE HIGHLANDS", TC.Mint, 20, { Icon = "🍃", Sub = "levels 24-32 · Wind 60%", Height = 4.2 })
	h.campfire("GaleHighlands", Vector3.new(20, 0, -140), f)
	addCamps("GaleHighlands", "GH", {
		{ -60, -170, 24, 25 }, { 70, -180, 24, 26 }, { -130, -260, 25, 26 }, { 130, -230, 25, 27 },
		{ -60, -320, 26, 28 }, { 80, -340, 27, 28 }, { -170, -380, 28, 29 }, { 160, -390, 28, 30 },
		{ -100, -470, 29, 31 }, { 120, -500, 30, 32 },
	})
	local ac = Vector3.new(0, World.groundY(0, -520), -520)
	arena({ part = P, float = h.float }, "GaleHighlands", ac, TC.Mint, Color3.fromRGB(200, 214, 230), Regions.Info.GaleHighlands.Boss.title)
	World.Regions.GaleHighlands.BossArena = ac
	bossCamp("GaleHighlands", ac)
	-- walls: ridges all round; the way in is the south gate of Haven
	ridgeLook = { material = Enum.Material.Slate, cap = Enum.Material.Snow }
	local hh = { part = P }
	ridge(hh, Vector3.new(x0 - 10, 0, -100), Vector3.new(x1 + 10, 0, -100), Vector3.new(0, 0, -100), 24)
	ridge(hh, Vector3.new(x0 - 10, 0, -100), Vector3.new(x0 - 10, 0, z0 - 10))
	-- east ridge: the Twilight Vale gate sits in it
	ridge(hh, Vector3.new(x1 + 10, 0, -100), Vector3.new(x1 + 10, 0, z0 - 10), Vector3.new(x1 + 10, 0, -200), 24)
	ridge(hh, Vector3.new(x0 - 10, 0, z0 - 10), Vector3.new(x1 + 10, 0, z0 - 10))
end

-- Twilight Vale (M8.2): south-east, through the Gale Highlands' east gate. The north half is
-- the sunlit Dawnfield (Light 45% camps, white-and-gold ruins), the south half the Gloamwood
-- (Dark 45%, violet crystals, glowing mushrooms); arches mark the seam. Boss: the Eclipse
-- Warden, Light by day and Dark by night.
Regions.TwilightSeamZ = -340
local function buildTwilightVale(h)
	local f = Instance.new("Folder")
	f.Name = "TwilightVale"
	f.Parent = h.root
	local function P(props)
		return h.part(props, f)
	end
	local x0, x1, z0, z1 = 260, 700, -570, -110
	local seam = Regions.TwilightSeamZ
	World.Regions.TwilightVale = {
		Id = "TwilightVale",
		Name = "Twilight Vale",
		Bounds = { x0, x1, z0, z1 },
		Elements = { Light = 30, Dark = 30, Fire = 13, Water = 13, Wind = 14 },
		StarWeights = { 5, 25, 45, 20, 5 },
		EliteChance = 0.12,
		Seam = seam,
	}
	-- ground: pale gold limestone in the Dawnfield, violet mud in the Gloamwood
	terrain:SetMaterialColor(Enum.Material.Limestone, Color3.fromRGB(206, 194, 150))
	terrain:SetMaterialColor(Enum.Material.Mud, Color3.fromRGB(70, 62, 82))
	terrain:ReplaceMaterial(Region3.new(Vector3.new(x0 - 4, -20, seam), Vector3.new(x1 + 20, 60, z1 + 20)):ExpandToGrid(4), 4, Enum.Material.Grass, Enum.Material.Limestone)
	terrain:ReplaceMaterial(Region3.new(Vector3.new(x0 - 4, -20, z0 - 20), Vector3.new(x1 + 20, 60, seam)):ExpandToGrid(4), 4, Enum.Material.Grass, Enum.Material.Mud)
	for _, m in { { 360, -190, 60, 14 }, { 620, -260, 70, 18 }, { 650, -150, 50, 10 }, { 320, -470, 60, 16 }, { 520, -420, 50, 10 }, { 680, -560, 60, 18 } } do
		terrain:FillBall(Vector3.new(m[1], m[4] - m[3], m[2]), m[3], m[2] > seam and Enum.Material.Limestone or Enum.Material.Mud)
	end
	h.pathStrip(Vector3.new(250, 0, -200), Vector3.new(480, 0, -200), 12)
	h.pathStrip(Vector3.new(480, 0, -200), Vector3.new(480, 0, -460), 12)
	h.pathStrip(Vector3.new(480, 0, -460), Vector3.new(600, 0, -500), 12)
	local gold, marble = Color3.fromRGB(255, 206, 90), Color3.fromRGB(248, 246, 255)
	local violet, crystal = Color3.fromRGB(70, 58, 104), Color3.fromRGB(176, 120, 255)
	-- Dawnfield: marble columns with gold caps, sun-shafts, golden blooms
	for i = 1, 16 do
		local x, z = x0 + 20 + math.random() * (x1 - x0 - 40), seam + 20 + math.random() * (z1 - seam - 40)
		if math.abs(z + 200) > 14 and math.abs(x - 480) > 14 then
			local y = World.groundY(x, z)
			local hgt = 8 + math.random() * 10
			local broken = math.random() < 0.4
			P({ Name = "SunColumn", Shape = Enum.PartType.Cylinder, Size = Vector3.new(hgt, 2.6, 2.6), CFrame = CFrame.new(x, y + hgt / 2, z) * CFrame.Angles(0, 0, math.rad(90)) * CFrame.Angles(broken and 0.12 or 0, 0, 0), Color = marble, Material = Enum.Material.Marble })
			if not broken then
				P({ Name = "SunCap", Size = Vector3.new(3.6, 1, 3.6), CFrame = CFrame.new(x, y + hgt + 0.5, z), Color = gold, Material = Enum.Material.SmoothPlastic })
			end
		end
	end
	for i = 1, 7 do
		local x, z = x0 + 40 + math.random() * (x1 - x0 - 80), seam + 30 + math.random() * (z1 - seam - 60)
		local beam = P({ Name = "SunShaft", Size = Vector3.new(6, 60, 6), CFrame = CFrame.new(x, 30, z) * CFrame.Angles(0, math.random() * 3, math.rad(8)), Color = Color3.fromRGB(255, 236, 170), Material = Enum.Material.Neon, Transparency = 0.86, CanCollide = false, CanQuery = false, CastShadow = false })
		h.decor(beam)
	end
	for i = 1, 90 do
		local x, z = x0 + 10 + math.random() * (x1 - x0 - 20), seam + 6 + math.random() * (z1 - seam - 12)
		local y = World.groundY(x, z)
		h.decor(P({ Name = "GoldBloom", Shape = Enum.PartType.Ball, Size = Vector3.new(0.8, 0.6, 0.8), Position = Vector3.new(x, y + 0.3, z), Color = i % 3 == 0 and Color3.new(1, 1, 1) or gold }))
	end
	-- Gloamwood: twisted trees with violet crowns, crystal clusters, glowing mushrooms
	for i = 1, 22 do
		local x, z = x0 + 16 + math.random() * (x1 - x0 - 32), z0 + 16 + math.random() * (seam - z0 - 32)
		if math.abs(x - 480) > 14 and (Vector3.new(x, 0, z) - Vector3.new(600, 0, -500)).Magnitude > 44 then
			local y = World.groundY(x, z)
			local hgt = 9 + math.random() * 6
			P({ Name = "GloamTrunk", Shape = Enum.PartType.Cylinder, Size = Vector3.new(hgt, 1.6, 1.6), CFrame = CFrame.new(x, y + hgt / 2, z) * CFrame.Angles(0, math.random() * 6, math.rad(90 + (math.random() - 0.5) * 16)), Color = Color3.fromRGB(60, 48, 70) })
			for k = 1, 2 do
				local r = 7 - k * 1.6
				P({ Name = "GloamCrown", Shape = Enum.PartType.Ball, Size = Vector3.new(r, r * 0.8, r), Position = Vector3.new(x + (math.random() - 0.5) * 2, y + hgt + (k - 1) * 2.4, z + (math.random() - 0.5) * 2), Color = Color3.fromRGB(120, 96, 170), CanCollide = k == 1 })
			end
		end
	end
	for i = 1, 14 do
		local x, z = x0 + 20 + math.random() * (x1 - x0 - 40), z0 + 20 + math.random() * (seam - z0 - 40)
		if math.abs(x - 480) > 12 then
			local y = World.groundY(x, z)
			for k = 1, 3 do
				local hgt = 3 + math.random() * 5
				local c = P({ Name = "GloamCrystal", Size = Vector3.new(1.4, hgt, 1.4), CFrame = CFrame.new(x + (k - 2) * 1.4, y + hgt / 2 - 0.5, z) * CFrame.Angles(math.rad((k - 2) * 14), math.random() * 3, math.rad((math.random() - 0.5) * 20)), Color = crystal, Material = Enum.Material.Neon, Transparency = 0.15 })
				c:SetAttribute("NoLod", true)
			end
		end
	end
	for i = 1, 40 do
		local x, z = x0 + 10 + math.random() * (x1 - x0 - 20), z0 + 10 + math.random() * (seam - z0 - 20)
		local y = World.groundY(x, z)
		local s = 0.8 + math.random() * 1.2
		h.decor(P({ Name = "GlowStem", Size = Vector3.new(0.3 * s, 1 * s, 0.3 * s), Position = Vector3.new(x, y + 0.5 * s, z), Color = Color3.fromRGB(230, 224, 240) }))
		h.decor(P({ Name = "GlowCap", Shape = Enum.PartType.Ball, Size = Vector3.new(1.4 * s, 0.7 * s, 1.4 * s), Position = Vector3.new(x, y + 1.1 * s, z), Color = i % 2 == 0 and Color3.fromRGB(120, 220, 255) or Color3.fromRGB(200, 140, 255), Material = Enum.Material.Neon }))
	end
	-- the seam: a row of marble arches, half gold, half violet
	for i = 0, 4 do
		local x = x0 + 50 + i * (x1 - x0 - 100) / 4
		if math.abs(x - 480) > 20 then
			local y = World.groundY(x, seam)
			for _, side in { -1, 1 } do
				P({ Name = "SeamPillar", Size = Vector3.new(2.4, 12, 2.4), CFrame = CFrame.new(x + side * 5, y + 6, seam), Color = side < 0 and marble or Color3.fromRGB(150, 136, 190), Material = Enum.Material.Marble })
			end
			P({ Name = "SeamLintel", Size = Vector3.new(13, 1.8, 2.8), CFrame = CFrame.new(x, y + 12.6, seam), Color = Color3.fromRGB(214, 200, 240), Material = Enum.Material.Marble })
		end
	end
	h.float("Twilight", Vector3.new(480, 40, -230), "TWILIGHT VALE", TC.Lilac, 20, { Icon = "🌗", Sub = "levels 32-40 · Light and Dark", Height = 4.2 })
	h.float("Dawnfield", Vector3.new(380, 22, -290), "DAWNFIELD", TC.Sun, 12, { Icon = "☀", Sub = "Light 45%", Height = 2.6 })
	h.float("Gloamwood", Vector3.new(380, 22, -390), "GLOAMWOOD", TC.Lilac, 12, { Icon = "🌙", Sub = "Dark 45%", Height = 2.6 })
	h.campfire("TwilightVale", Vector3.new(290, 0, -222), f)
	local LIGHT = { Light = 45, Fire = 18, Water = 18, Wind = 19 }
	local DARK = { Dark = 45, Fire = 18, Water = 18, Wind = 19 }
	local camps = {
		{ 330, -160, 32, 33 }, { 420, -140, 32, 34 }, { 560, -160, 33, 34 }, { 650, -230, 33, 35 }, { 360, -270, 34, 35 }, { 560, -290, 34, 36 },
		{ 330, -400, 35, 37 }, { 430, -400, 36, 37 }, { 630, -400, 36, 38 }, { 330, -520, 37, 39 }, { 440, -530, 38, 40 },
	}
	for i, c in camps do
		local zoneLight = c[2] > seam
		table.insert(World.Camps, { id = "TV" .. i, region = "TwilightVale", pos = Vector3.new(c[1], 0, c[2]), radius = 14, count = 3, lv = { c[3], c[4] }, elements = zoneLight and LIGHT or DARK, zone = zoneLight and "Light" or "Dark" })
	end
	local ac = Vector3.new(600, World.groundY(600, -500), -500)
	arena({ part = P, float = h.float }, "TwilightVale", ac, TC.Lilac, Color3.fromRGB(214, 200, 240), Regions.Info.TwilightVale.Boss.title)
	World.Regions.TwilightVale.BossArena = ac
	bossCamp("TwilightVale", ac)
	bossCamps.TwilightVale.elementFn = function()
		return workspace:GetAttribute("IsNight") and "Dark" or "Light"
	end
	-- walls (the west side is the Gale Highlands' east ridge, gate in it)
	ridgeLook = { material = Enum.Material.Basalt }
	terrain:SetMaterialColor(Enum.Material.Basalt, Color3.fromRGB(104, 92, 130))
	local hh = { part = P }
	ridge(hh, Vector3.new(x0 - 10, 0, -100), Vector3.new(x1 + 10, 0, -100))
	ridge(hh, Vector3.new(x1 + 10, 0, -100), Vector3.new(x1 + 10, 0, z0 - 10))
	ridge(hh, Vector3.new(x0 - 10, 0, z0 - 10), Vector3.new(x1 + 10, 0, z0 - 10))
end

-- Haven's own valley (north toward the Meadow, east and west) and the Meadow's far end.
local function buildValleys()
	-- Haven's hills are lower so the hub feels open (still hides the regions' ground)
	ridgeLook = { material = Enum.Material.Rock, cap = Enum.Material.Grass, height = 44 }
	ridge(nil, Vector3.new(-250, 0, 112), Vector3.new(250, 0, 112))
	ridge(nil, Vector3.new(-250, 0, -100), Vector3.new(-250, 0, 112))
	ridge(nil, Vector3.new(250, 0, -100), Vector3.new(250, 0, 90))
	ridge(nil, Vector3.new(-250, 0, 580), Vector3.new(250, 0, 580))
end

-- Portals (Shared/Places.Links): a stone frame with a glowing disc on each side of a mountain
-- range. Walking in fades you to the other side (Regions.portalLoop).
local PORTAL_ACCENT = { Haven = TC.Sun, SproutMeadow = TC.Mint, EmberCanyon = TC.Coral, TideCoast = TC.Sky, GaleHighlands = TC.Mint, TwilightVale = TC.Lilac }
local PORTAL_ICON = { Haven = "🏡", SproutMeadow = "🌱", EmberCanyon = "🔥", TideCoast = "🌊", GaleHighlands = "🍃", TwilightVale = "🌗" }
Regions.portals = {} -- { pos, face, to = other side, needs?, label }
local function buildPortals(h)
	local f = Instance.new("Folder")
	f.Name = "Portals"
	f.Parent = h.root
	local function side(link, here, there, needs)
		local y = 2
		local base = Vector3.new(here.pos.X, y, here.pos.Z)
		local look = CFrame.lookAt(base, base + here.face)
		local accent = PORTAL_ACCENT[there.place] or TC.Mint
		if here.frame ~= false then
			for _, sx in { -1, 1 } do
				h.part({ Name = "PortalPillar", Size = Vector3.new(2.6, 15, 2.6), CFrame = look * CFrame.new(sx * 8, 7.5, 0), Color = Color3.fromRGB(236, 230, 250) }, f)
				h.part({ Name = "PortalCap", Size = Vector3.new(3.4, 1.2, 3.4), CFrame = look * CFrame.new(sx * 8, 15.4, 0), Color = accent }, f)
			end
			h.part({ Name = "PortalLintel", Size = Vector3.new(19, 2, 3), CFrame = look * CFrame.new(0, 16, 0), Color = Color3.fromRGB(236, 230, 250) }, f)
		end
		local disc = h.part({ Name = "PortalDisc", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.4, 13, 13), CFrame = look * CFrame.new(0, 7.4, 0) * CFrame.Angles(0, math.rad(90), 0), Color = accent, Material = Enum.Material.Neon, Transparency = 0.5, CanCollide = false, CanQuery = false }, f)
		disc:SetAttribute("NoLod", true)
		local sparks = Instance.new("ParticleEmitter")
		sparks.Texture = "rbxasset://textures/particles/sparkles_main.dds"
		sparks.Color = ColorSequence.new(accent, Color3.new(1, 1, 1))
		sparks.Rate = 10
		sparks.Lifetime = NumberRange.new(1, 1.6)
		sparks.Speed = NumberRange.new(1, 3)
		sparks.Size = NumberSequence.new(0.45, 0)
		sparks.LightEmission = 0.7
		sparks.Parent = disc
		local name = Places.Names[there.place]
		local sub = "walk in to travel"
		if needs then
			local info = Regions.Info[needs]
			local i = table.find(Regions.Order, needs) or 2
			local prev = Regions.Info[Regions.Order[i - 1]]
			sub = "opens: beat the " .. prev.Boss.title .. " or reach Lv " .. tostring(info.PassLevel)
		end
		h.float("Portal_" .. link.id .. "_" .. here.place, base + Vector3.new(0, 22, 0), string.upper(name), accent, 11, { Icon = PORTAL_ICON[there.place], Sub = sub, Height = 3 })
		table.insert(Regions.portals, { pos = base, face = here.face, place = here.place, to = there, needs = needs, name = name })
	end
	for _, link in Places.Links do
		side(link, link.a, link.b, link.needs)
		side(link, link.b, link.a, nil)
	end
end

local function buildTitanField(h)
	local f = Instance.new("Folder")
	f.Name = "TitanField"
	f.Parent = h.root
	local c = Vector3.new(WORLD_POS.X, World.groundY(WORLD_POS.X, WORLD_POS.Z), WORLD_POS.Z)
	terrain:FillCylinder(CFrame.new(c.X, -1, c.Z), 2.2, 40, Enum.Material.Cobblestone)
	for i = 0, 11 do
		local a = i / 12 * math.pi * 2
		h.part({ Name = "TitanStone", Size = Vector3.new(3, 14, 3), Position = c + Vector3.new(math.cos(a) * 42, 7, math.sin(a) * 42), Color = Color3.fromRGB(226, 220, 246) }, f)
	end
	h.pathStrip(Vector3.new(60, 0, -4), Vector3.new(130, 0, -8), 10)
	h.float("Titan", c + Vector3.new(0, 30, 0), "TITAN FIELD", TC.Lilac, 14, { Icon = "⚡", Sub = "world boss every 30 minutes", Height = 3.2 })
	worldCamp = { id = "WorldBoss", region = "SproutMeadow", pos = c, radius = 2, count = 1, lv = { WORLD_LEVEL, WORLD_LEVEL }, boss = true, world = true }
end

----------------------------------------------------------------------------------------------
-- Gates and passes

local function setupGroups()
	-- Gate_<region i> is passable for Pass_n with n >= i - 1 (regions open in order)
	local count = #Regions.Order - 1
	for i = 2, #Regions.Order do
		pcall(function()
			PhysicsService:RegisterCollisionGroup("Gate_" .. Regions.Order[i])
		end)
	end
	for n = 1, count do
		pcall(function()
			PhysicsService:RegisterCollisionGroup("Pass_" .. n)
		end)
	end
	for i = 2, #Regions.Order do
		for n = i - 1, count do
			PhysicsService:CollisionGroupSetCollidable("Gate_" .. Regions.Order[i], "Pass_" .. n, false)
		end
	end
end

local function maxLevel(p): number
	local best = 0
	for _, m in p.monsters do
		best = math.max(best, m.lv)
	end
	return best
end

-- Opens regions you've earned (boss of the previous region, or an over-levelled monster).
-- Returns the names of regions that just opened.
local function unlock(p): { string }
	local opened = {}
	for i = 2, #Regions.Order do
		local id, prev = Regions.Order[i], Regions.Order[i - 1]
		if not p.regions[id] and (p.bosses[prev] or maxLevel(p) >= (Regions.Info[id].PassLevel or math.huge)) then
			p.regions[id] = true
			table.insert(opened, Regions.Info[id].Name)
		end
	end
	return opened
end

local function passIndex(p): number
	local n = 0
	for i = 2, #Regions.Order do
		if p.regions[Regions.Order[i]] then
			n = i - 1
		end
	end
	return n
end

local applied: { [Player]: { char: Model?, n: number } } = {}
function Regions.applyPass(player: Player)
	local p = PlayerData.get(player)
	local char = player.Character
	if not p or not char then
		return
	end
	local opened = unlock(p)
	for _, name in opened do
		remotes.Toast:FireClient(player, name .. " is open! Its gate will let you through", "good")
	end
	if #opened > 0 then
		PlayerData.saveSoon(player)
	end
	local n = passIndex(p)
	local a = applied[player]
	if a and a.char == char and a.n == n then
		return
	end
	applied[player] = { char = char, n = n }
	local group = n > 0 and ("Pass_" .. n) or "Default"
	for _, d in char:GetDescendants() do
		if d:IsA("BasePart") then
			d.CollisionGroup = group
		end
	end
end

function Regions.refreshRegions(player: Player)
	Regions.applyPass(player)
end

----------------------------------------------------------------------------------------------
-- Bosses

local function onBossDefeated(player: Player, u)
	local p = PlayerData.get(player)
	if not p then
		return
	end
	if u.camp == worldCamp then
		Story.event(player, "titan")
		return
	end
	local region = u.camp and u.camp.region
	if region and not p.bosses[region] then
		p.bosses[region] = true
		p.scrolls.Legendary += 1
		p.coins += 500
		remotes.Toast:FireClient(player, `First clear: {Regions.Info[region].Boss.title}! +1 Legendary Egg, +500 coins`, "good")
		PlayerData.saveSoon(player)
		task.defer(Regions.applyPass, player)
	end
end

local function onBossDied(u)
	if u.camp == worldCamp then
		worldActive = false
		workspace:SetAttribute("WorldBossUntil", 0)
		remotes.Toast:FireAllClients("The titan has fallen! Thanks for the help, Tamers", "good")
		return
	end
	local camp = u.camp
	task.delay(BOSS_RESPAWN, function()
		Combat.spawnWild(camp)
	end)
end

local function nextWorldBoss(): number
	local t = os.time()
	return t - t % WORLD_EVERY + WORLD_EVERY
end

local function spawnWorldBoss()
	if worldActive or not worldCamp then
		return false
	end
	local pool = Monsters.byStars(5)
	worldCamp.species = pool[math.random(1, #pool)]
	local r = math.random()
	worldCamp.element = r < 0.05 and "Light" or r < 0.1 and "Dark" or ({ "Fire", "Water", "Wind" })[math.random(1, 3)]
	worldCamp.hpMult = WORLD_HP
	Combat.spawnWild(worldCamp)
	worldActive = true
	local untilT = os.time() + WORLD_LASTS
	workspace:SetAttribute("WorldBossUntil", untilT)
	workspace:SetAttribute("WorldBossName", Monsters.Species[worldCamp.species].Name)
	remotes.Toast:FireAllClients(`A titan {Monsters.Species[worldCamp.species].Name} appeared at the Titan Field! Team up to beat it`, "alert")
	task.delay(WORLD_LASTS, function()
		if worldActive and os.time() >= untilT - 1 then
			-- Tamers who really fought it (5% of its HP) still get the story step
			for _, u in Combat.campUnits(worldCamp) do
				for pl, dmg in u.contrib or {} do
					if pl.Parent and dmg >= u.maxHp * 0.05 then
						Story.event(pl, "titan")
					end
				end
			end
			Combat.despawnCamp(worldCamp)
			worldActive = false
			workspace:SetAttribute("WorldBossUntil", 0)
			remotes.Toast:FireAllClients("The titan wandered off. Next one in a while!", "info")
		end
	end)
	return true
end

----------------------------------------------------------------------------------------------

function Regions.register(w)
	World = w
	World.extraRegions = function(_, h)
		local meadow = World.Regions.SproutMeadow
		meadow.EliteChance = 0.04
		bossCamp("SproutMeadow", meadow.BossArena)
		buildEmberCanyon(h)
		buildTideCoast(h)
		buildGaleHighlands(h)
		buildTwilightVale(h)
		buildTitanField(h)
		buildValleys()
		buildPortals(h)
		require(script.Parent.Landmarks).build(h)
		require(script.Parent.Rifts).build(h, World)
	end
end

-- Carry a player (and their team) through a portal to the far side, behind a fade.
function Regions.travel(pl: Player, there, name: string)
	remotes.Portal:FireClient(pl, { kind = "go", name = name })
	task.delay(0.35, function()
		local hrp = pl.Character and pl.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not hrp then
			return
		end
		local at = Vector3.new(there.arrive.X, 2, there.arrive.Z)
		pcall(function()
			pl:RequestStreamAroundAsync(at)
		end)
		hrp.AssemblyLinearVelocity = Vector3.zero
		hrp.CFrame = CFrame.lookAt(at + Vector3.new(0, 3.5, 0), at + Vector3.new(0, 3.5, 0) - there.face)
		Combat.warpTeam(pl, at)
		pl:SetAttribute("Region", Places.regionAt(at))
		remotes.Portal:FireClient(pl, { kind = "arrive", name = name })
	end)
end

function Regions.portalLoop()
	local cooldown: { [Player]: number } = {}
	local warned: { [Player]: number } = {}
	while true do
		task.wait(0.15)
		for _, pl in Players:GetPlayers() do
			local hrp = pl.Character and pl.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
			if hrp and os.clock() >= (cooldown[pl] or 0) and not pl:GetAttribute("Dungeon") then
				for _, pt in Regions.portals do
					local d = hrp.Position - pt.pos
					if Vector3.new(d.X, 0, d.Z).Magnitude < 4.5 and d.Y > -4 and d.Y < 14 then
						local p = PlayerData.get(pl)
						if pt.needs and (not p or not p.regions[pt.needs]) then
							if os.clock() - (warned[pl] or 0) > 3 then
								warned[pl] = os.clock()
								local i = table.find(Regions.Order, pt.needs) or 2
								local prev = Regions.Info[Regions.Order[i - 1]]
								remotes.Toast:FireClient(pl, `{pt.name} is locked: beat the {prev.Boss.title} in {prev.Name}, or get a monster to Lv {Regions.Info[pt.needs].PassLevel}`, "warn")
							end
							local back = pt.pos - pt.face * 9
							hrp.CFrame = CFrame.lookAt(back + Vector3.new(0, 3.5, 0), back + Vector3.new(0, 3.5, 0) - pt.face)
							cooldown[pl] = os.clock() + 0.6
						else
							cooldown[pl] = os.clock() + 2.5
							Regions.travel(pl, pt.to, pt.name)
						end
						break
					end
				end
			end
		end
	end
end

function Regions.init(r, c)
	remotes = r
	Combat = c
	setupGroups()
	task.spawn(Regions.portalLoop)
	Combat.onBossDefeated = onBossDefeated
	Combat.onBossDied = onBossDied
	-- the Eclipse Warden changes with the sky: at nightfall and dawn an idle Warden swaps
	-- element (one in a fight keeps going until it falls)
	workspace:GetAttributeChangedSignal("IsNight"):Connect(function()
		local camp = bossCamps.TwilightVale
		if not camp then
			return
		end
		local list = Combat.campUnits(camp)
		local u = list[1]
		local want = camp.elementFn and camp.elementFn()
		if u and want and u.el ~= want and not u.target and u.hp >= u.maxHp * 0.99 then
			Combat.despawnCamp(camp)
			Combat.spawnWild(camp)
		end
	end)
	Combat.onLegendDied = function(u)
		Regions.onLegendDied(u)
	end
	workspace:SetAttribute("LegendUntil", 0)
	task.spawn(function()
		Regions.legendLoop()
	end)
	workspace:SetAttribute("WorldBossAt", nextWorldBoss())
	workspace:SetAttribute("WorldBossUntil", 0)

	local function hook(player: Player)
		player.CharacterAdded:Connect(function(char)
			applied[player] = nil
			char:WaitForChild("HumanoidRootPart", 10)
			task.wait(0.5)
			Regions.applyPass(player)
		end)
	end
	for _, pl in Players:GetPlayers() do
		hook(pl)
	end
	Players.PlayerAdded:Connect(hook)
	Players.PlayerRemoving:Connect(function(pl)
		applied[pl] = nil
	end)

	-- Gate bump: tell the player what opens it.
	local bumped: { [Player]: number } = {}
	for _, d in workspace:GetDescendants() do
		if d:IsA("BasePart") and d:GetAttribute("Gate") then
			local region = d:GetAttribute("Gate")
			d.Touched:Connect(function(hit)
				local pl = Players:GetPlayerFromCharacter(hit.Parent)
				local p = pl and PlayerData.get(pl)
				if not p or p.regions[region] or os.clock() - (bumped[pl] or 0) < 4 then
					return
				end
				bumped[pl] = os.clock()
				local i = table.find(Regions.Order, region) or 2
				local prev = Regions.Info[Regions.Order[i - 1]]
				remotes.Toast:FireClient(pl, `Locked: beat the {prev.Boss.title} in {prev.Name}, or get a monster to Lv {Regions.Info[region].PassLevel}`, "warn")
			end)
		end
	end

	-- Region banner: the client shows a toast when this changes.
	task.spawn(function()
		while true do
			task.wait(1)
			for _, pl in Players:GetPlayers() do
				local hrp = pl.Character and pl.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
				if hrp then
					local id = World.regionAt(hrp.Position)
					if math.abs(hrp.Position.X - WORLD_POS.X) < 50 and math.abs(hrp.Position.Z - WORLD_POS.Z) < 50 then
						id = "TitanField"
					end
					if pl:GetAttribute("Region") ~= id then
						pl:SetAttribute("Region", id)
					end
				end
			end
			-- world boss schedule
			local at = workspace:GetAttribute("WorldBossAt") or 0
			if os.time() >= at then
				workspace:SetAttribute("WorldBossAt", nextWorldBoss())
				spawnWorldBoss()
			elseif at - os.time() == 60 then
				remotes.Toast:FireAllClients("A titan arrives at the Titan Field (east of Haven) in 1 minute!", "warn")
			end
		end
	end)
end

----------------------------------------------------------------------------------------------
-- Wandering Legends: every 6-14 minutes (random) a glowing rare 4-5 star appears somewhere in a
-- region someone in the server has unlocked, for 3 minutes. The whole server is told where.

local LEGEND_LASTS = 180
local LEGEND_TITLE = { Light = "Radiant", Dark = "Shadow", Fire = "Blazing", Water = "Tidal", Wind = "Tempest" }
local legendCamp: any = nil

local function clearLegend()
	legendCamp = nil
	workspace:SetAttribute("LegendUntil", 0)
end

function Regions.spawnLegend(region: string?)
	if legendCamp then
		Combat.despawnCamp(legendCamp)
		clearLegend()
	end
	-- a region somebody here can reach
	local options = {}
	for _, id in Regions.Order do
		for _, pl in Players:GetPlayers() do
			local p = PlayerData.get(pl)
			if p and p.regions[id] then
				table.insert(options, id)
				break
			end
		end
	end
	region = region or options[math.random(1, math.max(1, #options))]
	local r = region and World.Regions[region]
	if not r then
		return nil
	end
	local camps = {}
	for _, c in World.Camps do
		if c.region == region and not c.boss then
			table.insert(camps, c)
		end
	end
	if #camps == 0 then
		return nil
	end
	local c = camps[math.random(1, #camps)]
	local a = math.random() * math.pi * 2
	local pos = c.pos + Vector3.new(math.cos(a) * 22, 0, math.sin(a) * 22)
	local stars = math.random() < 0.4 and 5 or 4
	local pool = Monsters.byStars(stars)
	local sp = pool[math.random(1, #pool)]
	local roll = math.random()
	local el = roll < 0.15 and "Light" or roll < 0.3 and "Dark" or Config.pickWeighted({ Fire = r.Elements.Fire or 1, Water = r.Elements.Water or 1, Wind = r.Elements.Wind or 1 }, math.random())
	local top = 1
	for _, cc in camps do
		top = math.max(top, cc.lv[2])
	end
	local lv = top + 3
	legendCamp = { id = "Legend", region = region, pos = pos, radius = 2, count = 1, lv = { lv, lv }, species = sp, element = el, elite = true, hpMult = 6, legend = true }
	Combat.spawnWild(legendCamp)
	local name = LEGEND_TITLE[el] .. " " .. Monsters.Species[sp].Name
	local untilT = os.time() + LEGEND_LASTS
	workspace:SetAttribute("LegendName", name)
	workspace:SetAttribute("LegendPos", pos)
	workspace:SetAttribute("LegendRegion", region)
	workspace:SetAttribute("LegendUntil", untilT)
	remotes.Toast:FireAllClients(string.format("✨ A %s (Lv %d) appeared in %s! 3 minutes to find it", name, lv, Regions.Info[region].Name), "good")
	local mine = legendCamp
	task.delay(LEGEND_LASTS, function()
		if legendCamp == mine then
			Combat.despawnCamp(mine)
			clearLegend()
			remotes.Toast:FireAllClients("The " .. name .. " slipped away...", "info")
		end
	end)
	return name
end

function Regions.onLegendDied(u)
	if legendCamp and u.camp == legendCamp then
		local name = workspace:GetAttribute("LegendName") or "Legend"
		clearLegend()
		remotes.Toast:FireAllClients("✨ The " .. name .. " was defeated! Everyone who helped shares the loot", "good")
	end
end

function Regions.legendLoop()
	task.wait(math.random(180, 360))
	while true do
		if #Players:GetPlayers() > 0 then
			pcall(Regions.spawnLegend)
		end
		task.wait(math.random(360, 840))
	end
end

function Regions.debugSpawnBoss(region: string?)
	local camp = bossCamps[region or "SproutMeadow"]
	if not camp then
		return false
	end
	if #Combat.campUnits(camp) == 0 then
		Combat.spawnWild(camp)
	end
	return true
end

function Regions.debugWorldBoss()
	return spawnWorldBoss()
end

local _ = Config
return Regions

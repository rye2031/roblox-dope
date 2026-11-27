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

local TC = Theme.C
local Regions = {}

local World
local Combat
local remotes

-- Order matters: each region needs the previous one's boss.
Regions.Order = { "SproutMeadow", "EmberCanyon", "TideCoast" }
Regions.Info = {
	SproutMeadow = { Name = "Sprout Meadow", Boss = { sp = "Sproutknight", el = "Wind", lv = 10, title = "Meadow Guardian" } },
	EmberCanyon = { Name = "Ember Canyon", PassLevel = 14, Boss = { sp = "Drakoryn", el = "Fire", lv = 18, title = "Canyon Tyrant" } },
	TideCoast = { Name = "Tide Coast", PassLevel = 22, Boss = { sp = "Shellotl", el = "Water", lv = 26, title = "Tide Monarch" } },
}
local BOSS_HP = 8 -- region bosses: x8 a normal wild monster (soloable by a ready team)
local BOSS_RESPAWN = 120
local WORLD_EVERY, WORLD_LASTS, WORLD_LEVEL = 30 * 60, 6 * 60, 20
local WORLD_POS = Vector3.new(170, 0, -10)

local bossCamps: { [string]: any } = {}
local worldCamp: any = nil
local worldActive = false

----------------------------------------------------------------------------------------------
-- Building

local terrain = workspace.Terrain

-- A rectangular ridge of rock with an invisible wall on top (players can't hop over).
local function ridge(h, a: Vector3, b: Vector3, gapAt: Vector3?, gapWidth: number?)
	local function segment(p0: Vector3, p1: Vector3)
		local mid = (p0 + p1) / 2
		local len = (p1 - p0).Magnitude
		if len < 1 then
			return
		end
		local cf = CFrame.lookAt(Vector3.new(mid.X, 0, mid.Z), Vector3.new(p1.X, 0, p1.Z))
		terrain:FillBlock(cf * CFrame.new(0, 10, 0), Vector3.new(14, 24, len + 14), Enum.Material.Rock)
		h.part({ Name = "RegionWall", Size = Vector3.new(4, 160, len + 6), CFrame = cf * CFrame.new(0, 80, 0), Transparency = 1, CanQuery = false })
	end
	if gapAt then
		local dir = (b - a).Unit
		local t = (gapAt - a):Dot(dir)
		segment(a, a + dir * (t - gapWidth / 2))
		segment(a + dir * (t + gapWidth / 2), b)
	else
		segment(a, b)
	end
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
	local hh = { part = P }
	ridge(hh, Vector3.new(250, 0, z0 - 10), Vector3.new(250, 0, z1 + 10), Vector3.new(250, 0, 330), 24)
	ridge(hh, Vector3.new(250, 0, z0 - 10), Vector3.new(x1 + 10, 0, z0 - 10))
	ridge(hh, Vector3.new(250, 0, z1 + 10), Vector3.new(x1 + 10, 0, z1 + 10))
	ridge(hh, Vector3.new(x1 + 10, 0, z0 - 10), Vector3.new(x1 + 10, 0, z1 + 10))
	gate({ part = P, float = h.float }, "EmberCanyon", Vector3.new(250, World.groundY(250, 330), 330), Vector3.new(1, 0, 0), 24, TC.Coral, "EMBER CANYON", "beat the Meadow Guardian or reach Lv 14")
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
	local hh = { part = P }
	ridge(hh, Vector3.new(-250, 0, z0 - 10), Vector3.new(-250, 0, z1 + 10), Vector3.new(-250, 0, 330), 24)
	ridge(hh, Vector3.new(-250, 0, z0 - 10), Vector3.new(x0 - 10, 0, z0 - 10))
	ridge(hh, Vector3.new(-250, 0, z1 + 10), Vector3.new(x0 - 10, 0, z1 + 10))
	ridge(hh, Vector3.new(x0 - 10, 0, z0 - 10), Vector3.new(x0 - 10, 0, z1 + 10))
	gate({ part = P, float = h.float }, "TideCoast", Vector3.new(-250, World.groundY(-250, 330), 330), Vector3.new(-1, 0, 0), 24, TC.Sky, "TIDE COAST", "beat the Canyon Tyrant or reach Lv 22")
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
	for _, g in { "Gate_EmberCanyon", "Gate_TideCoast", "Pass_1", "Pass_2" } do
		pcall(function()
			PhysicsService:RegisterCollisionGroup(g)
		end)
	end
	PhysicsService:CollisionGroupSetCollidable("Gate_EmberCanyon", "Pass_1", false)
	PhysicsService:CollisionGroupSetCollidable("Gate_EmberCanyon", "Pass_2", false)
	PhysicsService:CollisionGroupSetCollidable("Gate_TideCoast", "Pass_2", false)
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
		remotes.Toast:FireClient(player, `First clear: {Regions.Info[region].Boss.title}! +1 Legendary scroll, +500 coins`, "good")
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
	worldCamp.hpMult = 22
	Combat.spawnWild(worldCamp)
	worldActive = true
	local untilT = os.time() + WORLD_LASTS
	workspace:SetAttribute("WorldBossUntil", untilT)
	workspace:SetAttribute("WorldBossName", Monsters.Species[worldCamp.species].Name)
	remotes.Toast:FireAllClients(`A titan {Monsters.Species[worldCamp.species].Name} appeared at the Titan Field! Team up to beat it`, "alert")
	task.delay(WORLD_LASTS, function()
		if worldActive and os.time() >= untilT - 1 then
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
		buildTitanField(h)
	end
end

function Regions.init(r, c)
	remotes = r
	Combat = c
	setupGroups()
	Combat.onBossDefeated = onBossDefeated
	Combat.onBossDied = onBossDied
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

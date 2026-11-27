-- Landmarks (2026-11-27, owner: more character in every region) and the hidden discoveries
-- tucked into them (Shared/Discoveries). Built from parts and terrain, no new art:
--   Sprout Meadow   the Elder Tree (spiral steps up the trunk to a crown platform)
--   Ember Canyon    a volcano rising out of the east range (glowing crater) and a lava river
--                   with a wooden bridge
--   Tide Coast      a shipwreck on the beach and a sea arch reached by stepping stones
--   Gale Highlands  windmills on the bluffs (stairs up one) and two sky islands joined by a
--                   bridge, reached with a wind-lift pad
--   Twilight Vale   the Temple of Sun and Moon on the seam and a singing crystal grove
--   Haven           one glowing Titan Stone
-- Client Landmarks.luau spins the windmills, runs the lift pads and shows discovery glints.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Discoveries = require(ReplicatedStorage.Shared.Discoveries)
local Theme = require(ReplicatedStorage.Shared.Theme)
local PlayerData = require(script.Parent.PlayerData)

local TC = Theme.C
local Landmarks = {}
local terrain = workspace.Terrain
local Y = 2 -- terrain surface after the world settles
local remotes

local WOOD, WOOD_DARK = Color3.fromRGB(170, 124, 86), Color3.fromRGB(118, 82, 58)
local STONE = Color3.fromRGB(214, 208, 226)

----------------------------------------------------------------------------------------------

local function elderTree(h, f)
	local c = Vector3.new(175, Y, 210)
	local H = 52
	h.part({ Name = "ElderTrunk", Shape = Enum.PartType.Cylinder, Size = Vector3.new(H, 9, 9), CFrame = CFrame.new(c + Vector3.new(0, H / 2, 0)) * CFrame.Angles(0, 0, math.rad(90)), Color = Color3.fromRGB(140, 100, 72), Material = Enum.Material.Wood }, f)
	for _, r in { 0, 1.6, 3.2, 4.8 } do -- roots
		h.part({ Name = "ElderRoot", Size = Vector3.new(3, 3, 14), CFrame = CFrame.new(c + Vector3.new(0, 1, 0)) * CFrame.Angles(0, r, 0) * CFrame.new(0, 0, 7) * CFrame.Angles(math.rad(-18), 0, 0), Color = Color3.fromRGB(130, 92, 66), Material = Enum.Material.Wood }, f)
	end
	-- spiral steps (walkable: 1.1 studs up per step)
	local steps = 46
	for i = 0, steps do
		local a = i * math.rad(18)
		local y = 1.5 + i * 1.1
		h.part({ Name = "ElderStep", Size = Vector3.new(5, 0.8, 3.4), CFrame = CFrame.new(c) * CFrame.Angles(0, a, 0) * CFrame.new(6.6, y, 0), Color = i % 2 == 0 and WOOD or WOOD_DARK, Material = Enum.Material.Wood }, f)
	end
	-- crown platform and leaves
	local top = c + Vector3.new(0, H + 1.5, 0)
	h.part({ Name = "ElderDeck", Shape = Enum.PartType.Cylinder, Size = Vector3.new(1.2, 26, 26), CFrame = CFrame.new(top) * CFrame.Angles(0, 0, math.rad(90)), Color = WOOD, Material = Enum.Material.WoodPlanks }, f)
	for i = 0, 7 do
		local a = i / 8 * math.pi * 2
		h.decor(h.part({ Name = "ElderLeaves", Shape = Enum.PartType.Ball, Size = Vector3.new(16, 11, 16), Position = top + Vector3.new(math.cos(a) * 14, 4 + (i % 2) * 3, math.sin(a) * 14), Color = Color3.fromRGB(120 + (i % 3) * 12, 200, 130), CanCollide = false }, f))
	end
	h.decor(h.part({ Name = "ElderCanopy", Shape = Enum.PartType.Ball, Size = Vector3.new(30, 14, 30), Position = top + Vector3.new(0, 14, 0), Color = Color3.fromRGB(132, 212, 140), CanCollide = false }, f))
	h.float("ElderTree", c + Vector3.new(0, H + 26, 0), "ELDER TREE", TC.Mint, 10, { Icon = "🌳", Sub = "climb to the crown", Height = 2.6 })
	-- old mill nook
	h.part({ Name = "MillCrate", Size = Vector3.new(3, 3, 3), Position = Vector3.new(-104, Y + 1.5, 314), Color = WOOD, Material = Enum.Material.WoodPlanks }, f)
	h.part({ Name = "MillCrate", Size = Vector3.new(2.4, 2.4, 2.4), Position = Vector3.new(-115, Y + 1.2, 316), Color = WOOD_DARK, Material = Enum.Material.WoodPlanks }, f)
end

local function volcano(h, f)
	local c = Vector3.new(700, 0, 300)
	terrain:SetMaterialColor(Enum.Material.Asphalt, Color3.fromRGB(84, 70, 70))
	terrain:SetMaterialColor(Enum.Material.CrackedLava, Color3.fromRGB(255, 120, 50))
	for i = 0, 11 do
		local r = 64 - i * 5
		terrain:FillCylinder(CFrame.new(c.X, 2 + i * 5.5, c.Z), 5.6, r, i >= 10 and Enum.Material.CrackedLava or Enum.Material.Asphalt)
	end
	-- crater: carve the top and fill a lava pool
	terrain:FillCylinder(CFrame.new(c.X, 64, c.Z), 14, 7, Enum.Material.Air)
	terrain:FillCylinder(CFrame.new(c.X, 56, c.Z), 2, 7, Enum.Material.CrackedLava)
	local glow = h.part({ Name = "CraterGlow", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.4, 13, 13), CFrame = CFrame.new(c.X, 57.4, c.Z) * CFrame.Angles(0, 0, math.rad(90)), Color = Color3.fromRGB(255, 140, 60), Material = Enum.Material.Neon, CanCollide = false, CanQuery = false }, f)
	local smoke = Instance.new("ParticleEmitter")
	smoke.Texture = "rbxasset://textures/particles/smoke_main.dds"
	smoke.Color = ColorSequence.new(Color3.fromRGB(120, 110, 110))
	smoke.Transparency = NumberSequence.new(0.4, 1)
	smoke.Size = NumberSequence.new(6, 18)
	smoke.Lifetime = NumberRange.new(5, 8)
	smoke.Speed = NumberRange.new(6, 10)
	smoke.Rate = 4
	smoke.Parent = glow
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 140, 60)
	light.Range = 40
	light.Brightness = 3
	light.Parent = glow
	h.float("Volcano", Vector3.new(c.X - 20, 84, c.Z), "MOUNT CINDER", TC.Coral, 11, { Icon = "🌋", Sub = "climb to the crater", Height = 2.8 })
	-- lava river with a bridge
	terrain:FillBlock(CFrame.new(595, -0.6, 250), Vector3.new(110, 3.6, 12), Enum.Material.CrackedLava)
	h.decor(h.part({ Name = "LavaSheen", Size = Vector3.new(110, 0.2, 10), Position = Vector3.new(595, 1.1, 250), Color = Color3.fromRGB(255, 120, 50), Material = Enum.Material.Neon, Transparency = 0.35, CanCollide = false, CanQuery = false }, f))
	for i = -6, 6 do
		local z = 250 + i * 1.6
		local y = Y + 3.2 - (i / 6) ^ 2 * 2.4
		h.part({ Name = "BridgePlank", Size = Vector3.new(6, 0.5, 1.5), CFrame = CFrame.new(590, y, z), Color = i % 2 == 0 and WOOD or WOOD_DARK, Material = Enum.Material.WoodPlanks }, f)
	end
	for _, sx in { -1, 1 } do
		h.part({ Name = "BridgeRail", Size = Vector3.new(0.4, 0.4, 20), CFrame = CFrame.new(590 + sx * 3, Y + 4.6, 250), Color = WOOD_DARK, Material = Enum.Material.Wood }, f)
		for _, z in { 240, 260 } do
			h.part({ Name = "BridgePost", Size = Vector3.new(0.6, 4, 0.6), CFrame = CFrame.new(590 + sx * 3, Y + 2.5, z), Color = WOOD_DARK, Material = Enum.Material.Wood }, f)
		end
	end
end

local function shipwreck(h, f)
	local c = CFrame.new(-592, Y + 1, 250) * CFrame.Angles(0, math.rad(20), math.rad(-14))
	local HULL = Color3.fromRGB(128, 90, 64)
	h.part({ Name = "WreckKeel", Size = Vector3.new(9, 1.2, 30), CFrame = c, Color = HULL, Material = Enum.Material.WoodPlanks }, f)
	for _, sx in { -1, 1 } do
		h.part({ Name = "WreckSide", Size = Vector3.new(1, 7, 30), CFrame = c * CFrame.new(sx * 4.6, 3.4, 0) * CFrame.Angles(0, 0, math.rad(sx * 12)), Color = HULL, Material = Enum.Material.WoodPlanks }, f)
	end
	h.part({ Name = "WreckBow", Size = Vector3.new(9, 7, 6), CFrame = c * CFrame.new(0, 3.4, -17) * CFrame.Angles(math.rad(-30), 0, 0), Color = HULL, Material = Enum.Material.WoodPlanks }, f)
	h.part({ Name = "WreckDeck", Size = Vector3.new(9, 0.6, 12), CFrame = c * CFrame.new(0, 6.8, 9), Color = WOOD, Material = Enum.Material.WoodPlanks }, f)
	h.part({ Name = "WreckMast", Shape = Enum.PartType.Cylinder, Size = Vector3.new(22, 1.2, 1.2), CFrame = c * CFrame.new(0, 12, -2) * CFrame.Angles(0, 0, math.rad(80)), Color = WOOD_DARK, Material = Enum.Material.Wood }, f)
	h.decor(h.part({ Name = "WreckSail", Size = Vector3.new(0.2, 9, 11), CFrame = c * CFrame.new(1.2, 13, -2) * CFrame.Angles(0, 0, math.rad(-6)), Color = Color3.fromRGB(240, 232, 214), Material = Enum.Material.Fabric, CanCollide = false }, f))
	for i, o in { Vector3.new(-1.5, 1.6, 4), Vector3.new(1.8, 1.6, 7), Vector3.new(0, 1.6, -6) } do
		h.part({ Name = "WreckCrate", Size = Vector3.new(2.2, 2.2, 2.2), CFrame = c * CFrame.new(o) * CFrame.Angles(0, i, 0), Color = WOOD, Material = Enum.Material.WoodPlanks }, f)
	end
	h.float("Wreck", Vector3.new(-592, 26, 250), "THE OLD WRECK", TC.Sky, 10, { Icon = "⚓", Sub = "something's still aboard", Height = 2.6 })
	-- sea arch in the water, stepping stones from the beach
	terrain:FillBlock(CFrame.new(-662, 15, 457), Vector3.new(9, 34, 9), Enum.Material.Rock)
	terrain:FillBlock(CFrame.new(-662, 15, 483), Vector3.new(9, 34, 9), Enum.Material.Rock)
	terrain:FillBlock(CFrame.new(-662, 31, 470), Vector3.new(10, 6, 34), Enum.Material.Rock)
	for i = 1, 6 do
		h.part({ Name = "SeaStone", Size = Vector3.new(5, 2, 5), Position = Vector3.new(-606 - i * 7.2, Y + i * 4.6, 470 + (i % 2) * 3), Color = Color3.fromRGB(170, 176, 196), Material = Enum.Material.Slate }, f)
	end
end

local function windmill(h, f, base: Vector3, withStairs: boolean)
	h.part({ Name = "WindmillTower", Shape = Enum.PartType.Cylinder, Size = Vector3.new(16, 6, 6), CFrame = CFrame.new(base + Vector3.new(4, 8, 4)) * CFrame.Angles(0, 0, math.rad(90)), Color = Color3.fromRGB(250, 246, 238) }, f)
	h.part({ Name = "WindmillCap", Shape = Enum.PartType.Ball, Size = Vector3.new(7, 5, 7), Position = base + Vector3.new(4, 17, 4), Color = TC.Mint }, f)
	local hub = h.part({ Name = "WindmillHub", Size = Vector3.new(1.4, 1.4, 1.4), Position = base + Vector3.new(4, 14, 0.4), Color = WOOD_DARK }, f)
	hub:SetAttribute("Windmill", true)
	for i = 0, 3 do
		local blade = h.part({ Name = "WindmillBlade", Size = Vector3.new(1.4, 8, 0.3), CFrame = CFrame.new(hub.Position) * CFrame.Angles(0, 0, i * math.pi / 2) * CFrame.new(0, 4.4, 0), Color = Color3.fromRGB(250, 250, 255), CanCollide = false }, f)
		blade:SetAttribute("Blade", true)
		local wv = Instance.new("ObjectValue")
		wv.Name = "Hub"
		wv.Value = hub
		wv.Parent = blade
	end
	if withStairs then
		for i = 0, 11 do
			h.part({ Name = "BluffStair", Size = Vector3.new(4, 1, 3), Position = base + Vector3.new(-6 - i * 0, -16.5 + i * 1.5, 18 - i * 2.6), Color = STONE, Material = Enum.Material.Slate }, f)
		end
	end
end

local function skyIslands(h, f)
	local a, b = Vector3.new(-30, 28, -410), Vector3.new(40, 32, -430)
	for _, p in { a, b } do
		h.part({ Name = "SkyIsle", Shape = Enum.PartType.Cylinder, Size = Vector3.new(2, 16, 16), CFrame = CFrame.new(p) * CFrame.Angles(0, 0, math.rad(90)), Color = Color3.fromRGB(150, 205, 170), Material = Enum.Material.Grass }, f)
		h.part({ Name = "SkyIsleRock", Shape = Enum.PartType.Ball, Size = Vector3.new(14, 10, 14), Position = p - Vector3.new(0, 5, 0), Color = Color3.fromRGB(150, 160, 186), Material = Enum.Material.Slate, CanCollide = false }, f)
	end
	-- plank bridge between the two islands
	local s, e = a + Vector3.new(7, 1, -2), b + Vector3.new(-7, 1, 2)
	local n = 14
	for i = 0, n do
		local p = s:Lerp(e, i / n) - Vector3.new(0, math.sin(i / n * math.pi) * 1.5, 0)
		h.part({ Name = "SkyPlank", Size = Vector3.new(4, 0.4, 1.6), CFrame = CFrame.lookAt(p, p + (e - s)) * CFrame.Angles(0, math.rad(90), 0), Color = i % 2 == 0 and WOOD or WOOD_DARK, Material = Enum.Material.WoodPlanks }, f)
	end
	-- the wind lift: step on it and the wind throws you up to the first island
	local pad = h.part({ Name = "WindLift", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.4, 8, 8), CFrame = CFrame.new(-30, Y + 0.2, -386) * CFrame.Angles(0, 0, math.rad(90)), Color = Color3.fromRGB(196, 246, 226), Material = Enum.Material.Neon, Transparency = 0.2, CanCollide = false }, f)
	pad:SetAttribute("Lift", a + Vector3.new(0, 4, 0))
	local swirl = Instance.new("ParticleEmitter")
	swirl.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	swirl.Color = ColorSequence.new(Color3.fromRGB(220, 255, 240))
	swirl.Rate = 16
	swirl.Lifetime = NumberRange.new(1, 1.6)
	swirl.Speed = NumberRange.new(8, 14)
	swirl.EmissionDirection = Enum.NormalId.Right
	swirl.Size = NumberSequence.new(0.5, 0)
	swirl.Parent = pad
	h.float("WindLift", Vector3.new(-30, 14, -386), "WIND LIFT", TC.Mint, 8, { Icon = "🌬", Sub = "step on to fly up", Height = 2.2 })
end

local function temple(h, f)
	local c = Vector3.new(620, Y, -340)
	h.part({ Name = "TempleFloor", Shape = Enum.PartType.Cylinder, Size = Vector3.new(1.6, 34, 34), CFrame = CFrame.new(c + Vector3.new(0, 0.6, 0)) * CFrame.Angles(0, 0, math.rad(90)), Color = Color3.fromRGB(240, 236, 250), Material = Enum.Material.Marble }, f)
	for i = 0, 9 do
		local a = i / 10 * math.pi * 2
		local p = c + Vector3.new(math.cos(a) * 14, 0, math.sin(a) * 14)
		local sun = p.Z > c.Z
		h.part({ Name = "TemplePillar", Shape = Enum.PartType.Cylinder, Size = Vector3.new(14, 2.4, 2.4), CFrame = CFrame.new(p + Vector3.new(0, 8, 0)) * CFrame.Angles(0, 0, math.rad(90)), Color = sun and Color3.fromRGB(250, 244, 224) or Color3.fromRGB(150, 132, 196), Material = Enum.Material.Marble }, f)
		h.part({ Name = "TempleCap", Size = Vector3.new(3.2, 1, 3.2), Position = p + Vector3.new(0, 15.5, 0), Color = sun and Color3.fromRGB(255, 206, 90) or Color3.fromRGB(176, 120, 255) }, f)
	end
	h.part({ Name = "TempleRing", Shape = Enum.PartType.Cylinder, Size = Vector3.new(1.4, 32, 32), CFrame = CFrame.new(c + Vector3.new(0, 16.5, 0)) * CFrame.Angles(0, 0, math.rad(90)), Color = Color3.fromRGB(226, 216, 246), Material = Enum.Material.Marble, Transparency = 0 }, f)
	h.part({ Name = "TempleAltar", Size = Vector3.new(4, 3, 4), Position = c + Vector3.new(0, 2.5, 0), Color = STONE, Material = Enum.Material.Marble }, f)
	local orb = h.part({ Name = "TempleSun", Shape = Enum.PartType.Ball, Size = Vector3.new(3.4, 3.4, 3.4), Position = c + Vector3.new(0, 6.4, 0.9), Color = Color3.fromRGB(255, 210, 90), Material = Enum.Material.Neon }, f)
	orb:SetAttribute("Spin", true)
	local moon = h.part({ Name = "TempleMoon", Shape = Enum.PartType.Ball, Size = Vector3.new(3.4, 3.4, 3.4), Position = c + Vector3.new(0, 6.4, -0.9), Color = Color3.fromRGB(170, 120, 255), Material = Enum.Material.Neon }, f)
	moon:SetAttribute("Spin", true)
	h.float("Temple", c + Vector3.new(0, 26, 0), "TEMPLE OF SUN AND MOON", TC.Lilac, 13, { Icon = "🌗", Sub = "half day, half night", Height = 2.8 })
	-- the crystal grove deep in the Gloamwood
	local g = Vector3.new(312, Y, -556)
	for i = 0, 8 do
		local a = i / 9 * math.pi * 2
		local hgt = 6 + (i % 3) * 3
		local cr = h.part({ Name = "GroveCrystal", Size = Vector3.new(2, hgt, 2), CFrame = CFrame.new(g + Vector3.new(math.cos(a) * 9, hgt / 2 - 0.5, math.sin(a) * 9)) * CFrame.Angles(math.rad(math.cos(a) * 14), a, math.rad(math.sin(a) * 14)), Color = i % 2 == 0 and Color3.fromRGB(176, 120, 255) or Color3.fromRGB(120, 210, 255), Material = Enum.Material.Neon, Transparency = 0.15 }, f)
		cr:SetAttribute("NoLod", true)
	end
end

local function titanStone(h, f)
	local p = Vector3.new(170, Y, 32)
	local rune = h.part({ Name = "TitanRune", Size = Vector3.new(3.2, 3.2, 0.3), CFrame = CFrame.new(p + Vector3.new(0, 9, -1.7)), Color = Color3.fromRGB(176, 140, 255), Material = Enum.Material.Neon }, f)
	rune:SetAttribute("NoLod", true)
end

function Landmarks.build(h)
	local f = Instance.new("Folder")
	f.Name = "Landmarks"
	f.Parent = h.root
	elderTree(h, f)
	volcano(h, f)
	shipwreck(h, f)
	windmill(h, f, Vector3.new(-200, 18, -160), true)
	windmill(h, f, Vector3.new(210, 22, -340), false)
	skyIslands(h, f)
	temple(h, f)
	titanStone(h, f)
end

----------------------------------------------------------------------------------------------
-- discoveries

local function found(player: Player, d)
	local p = PlayerData.get(player)
	if not p or p.found[d.id] then
		return
	end
	p.found[d.id] = true
	p.coins += d.coins
	p.scrolls.Regular += Discoveries.ScrollEach
	local n = 0
	for _ in p.found do
		n += 1
	end
	local all = n >= #Discoveries.List
	if all then
		p.scrolls.Legendary += Discoveries.AllReward.legendary or 0
	end
	PlayerData.push(player)
	PlayerData.saveSoon(player)
	remotes.Discovery:FireClient(player, { id = d.id, name = d.name, coins = d.coins, scrolls = Discoveries.ScrollEach, n = n, total = #Discoveries.List, all = all })
	if Landmarks.onFound then
		Landmarks.onFound(player, d.id, n)
	end
end

function Landmarks.init(r)
	remotes = r
	task.spawn(function()
		while true do
			task.wait(0.5)
			for _, pl in Players:GetPlayers() do
				local p = PlayerData.get(pl)
				local hrp = pl.Character and pl.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
				if p and hrp and p.found then
					for _, d in Discoveries.List do
						if not p.found[d.id] and (hrp.Position - d.pos).Magnitude <= Discoveries.Radius then
							found(pl, d)
						end
					end
				end
			end
		end
	end)
end

return Landmarks

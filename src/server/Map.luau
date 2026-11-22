-- Builds the food court with Studio geometry. Everything walkable or collision-critical is a
-- plain Part/WedgePart with exact dimensions; Meshy props are dressing only (see Props.luau).
--
-- Layout (studs, +Z is north, ground top at Y = 0):
--   Hideout            Z -24..8   (rescue station at 0,0,-4)
--   South plaza        Z 8..74    (fountain at -18,0,40; route fork at 0,0,22)
--   Wok Wall block     Z 74..92   X -44..60, 14 high. Crossed three ways:
--     quiet:  Cozy Corner gap   X -60..-44 (sheltered, drains the meter)
--     vent:   duct              X -40..-34 (Crab Rangoon buddy opens it)
--     loud:   escalator bridge  X 14..22   (rattles on a cycle)
--   North hall         Z 92..160  (rare stage at 20,0,146)
local Map = {}

local HALL_X = 60
local HALL_Z0, HALL_Z1 = -24, 160
local WALL_H = 30
local BLOCK_Z0, BLOCK_Z1, BLOCK_H = 74, 92, 14
local ESC_X0, ESC_X1 = 14, 22
local ESC_RUN = 30
local VENT_X0, VENT_X1, VENT_H = -40, -34, 7
local GAP_X1 = -44

Map.Points = {
	Station = Vector3.new(0, 0, -4),
	Spawn = Vector3.new(-10, 0, -15),
	Fork = Vector3.new(0, 0, 22),
	Fountain = Vector3.new(-18, 0, 40),
	RareStage = Vector3.new(20, 0, 146),
	VentSouth = Vector3.new((VENT_X0 + VENT_X1) / 2, 0, BLOCK_Z0),
	VentNorth = Vector3.new((VENT_X0 + VENT_X1) / 2, 0, BLOCK_Z1),
	CommonSpawns = {
		Vector3.new(8, 0, 30), -- in sight of the hideout
		Vector3.new(-52, 0, 54), -- on the quiet route
		Vector3.new(42, 0, 50), -- by the escalator foot
		Vector3.new(-30, 0, 128), -- north-west
		Vector3.new(46, 0, 128), -- north-east
	},
}

-- Ground nav graph for bolting creatures: node positions and links.
Map.Nav = {
	nodes = {
		Vector3.new(0, 0, 14), -- 1 hideout mouth
		Vector3.new(0, 0, 30), -- 2 fork
		Vector3.new(-36, 0, 30), -- 3 west of fountain
		Vector3.new(-18, 0, 60), -- 4 north of fountain
		Vector3.new(-52, 0, 50), -- 5 quiet corridor south
		Vector3.new(-52, 0, 83), -- 6 cozy corner
		Vector3.new(-52, 0, 104), -- 7 quiet corridor north
		Vector3.new(30, 0, 30), -- 8 east plaza
		Vector3.new(40, 0, 60), -- 9 escalator area east
		Vector3.new(18, 0, 40), -- 10 escalator foot
		Vector3.new(18, 14, 74), -- 11 bridge south
		Vector3.new(18, 14, 92), -- 12 bridge north
		Vector3.new(18, 0, 126), -- 13 north escalator foot
		Vector3.new(-20, 0, 116), -- 14 north-west hall
		Vector3.new(0, 0, 140), -- 15 north centre
		Vector3.new(44, 0, 112), -- 16 north-east hall
		Vector3.new(44, 0, 146), -- 17 north-east corner
		Vector3.new(-40, 0, 146), -- 18 north-west corner
		Vector3.new(-37, 0, 66), -- 19 vent south mouth
		Vector3.new(-37, 0, 100), -- 20 vent north mouth
	},
	links = {
		{ 1, 2 }, { 2, 3 }, { 2, 8 }, { 2, 10 }, { 3, 4 }, { 3, 5 }, { 4, 19 }, { 4, 10 },
		{ 5, 6 }, { 6, 7 }, { 7, 14 }, { 7, 20 }, { 8, 9 }, { 8, 10 }, { 9, 10 }, { 10, 11 },
		{ 11, 12 }, { 12, 13 }, { 13, 14 }, { 13, 15 }, { 13, 16 }, { 14, 15 }, { 14, 18 },
		{ 15, 17 }, { 15, 18 }, { 16, 17 }, { 19, 5 }, { 20, 14 },
	},
}

local C = {
	Floor = Color3.fromRGB(214, 206, 196),
	FloorDark = Color3.fromRGB(176, 166, 158),
	Wall = Color3.fromRGB(64, 58, 92),
	Cardboard = Color3.fromRGB(196, 150, 96),
	Quiet = Color3.fromRGB(86, 170, 255),
	QuietCarpet = Color3.fromRGB(56, 92, 168),
	Loud = Color3.fromRGB(255, 70, 50),
	Hazard = Color3.fromRGB(255, 196, 40),
	Metal = Color3.fromRGB(120, 124, 134),
	Block = Color3.fromRGB(150, 70, 70),
	Pink = Color3.fromRGB(255, 120, 190),
	Gold = Color3.fromRGB(255, 200, 70),
	Vent = Color3.fromRGB(110, 200, 120),
}

local root: Folder
local zones: Folder

local function part(props: { [string]: any }, parent: Instance?): BasePart
	local className = props.ClassName or "Part"
	local p = Instance.new(className)
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	for k, v in props do
		if k ~= "ClassName" then
			(p :: any)[k] = v
		end
	end
	p.Parent = parent or root
	return p :: BasePart
end

-- A box from min/max corners.
local function box(name, x0, y0, z0, x1, y1, z1, color, material, parent)
	return part({
		Name = name,
		Size = Vector3.new(math.abs(x1 - x0), math.abs(y1 - y0), math.abs(z1 - z0)),
		Position = Vector3.new((x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2),
		Color = color,
		Material = material or Enum.Material.SmoothPlastic,
	}, parent)
end

local function zone(kind: string, x0, z0, x1, z1, y0, y1)
	local z = box("Zone_" .. kind, x0, y0 or -1, z0, x1, y1 or 10, z1, Color3.new(1, 1, 1), nil, zones)
	z.Transparency = 1
	z.CanCollide = false
	z.CanQuery = false
	z.CanTouch = false
	z:SetAttribute("Kind", kind)
	return z
end

-- Big readable sign on one face of a part.
local function sign(
	name: string,
	cf: CFrame,
	size: Vector2,
	text: string,
	bg: Color3,
	fg: Color3?,
	opts: { [string]: any }?
): BasePart
	opts = opts or {}
	local p = part({
		Name = name,
		Size = Vector3.new(size.X, size.Y, 0.4),
		CFrame = cf,
		Color = bg,
		Material = Enum.Material.Neon,
		CanCollide = false,
	})
	local function face(f)
		local gui = Instance.new("SurfaceGui")
		gui.Face = f
		gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		gui.PixelsPerStud = 40
		gui.LightInfluence = 0
		gui.Brightness = 1.2
		gui.Parent = p
		local frame = Instance.new("Frame")
		frame.Size = UDim2.fromScale(1, 1)
		frame.BackgroundColor3 = bg
		frame.BorderSizePixel = 0
		frame.Parent = gui
		local stroke = Instance.new("UIStroke")
		stroke.Thickness = 10
		stroke.Color = fg or Color3.new(1, 1, 1)
		stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		stroke.Parent = frame
		local label = Instance.new("TextLabel")
		label.Size = UDim2.new(1, -40, 1, -30)
		label.Position = UDim2.fromOffset(20, 15)
		label.BackgroundTransparency = 1
		label.Text = text
		label.TextScaled = true
		label.Font = Enum.Font.FredokaOne
		label.TextColor3 = fg or Color3.new(1, 1, 1)
		label.RichText = true
		label.Parent = frame
		local outline = Instance.new("UIStroke")
		outline.Thickness = 4
		outline.Color = Color3.new(0, 0, 0)
		outline.Transparency = 0.3
		outline.Parent = label
	end
	face(Enum.NormalId.Front)
	if opts.TwoSided then
		face(Enum.NormalId.Back)
	end
	local light = Instance.new("SurfaceLight")
	light.Face = Enum.NormalId.Front
	light.Color = bg
	light.Range = math.min(opts.LightRange or 10, 12)
	light.Brightness = opts.LightBrightness or 0.5
	light.Parent = p
	return p
end

local function pointLight(pos: Vector3, color: Color3, range: number, brightness: number, parent: Instance?)
	local holder = part({
		Name = "Lamp",
		Size = Vector3.new(1.2, 1.2, 1.2),
		Shape = Enum.PartType.Ball,
		Position = pos,
		Color = color,
		Material = Enum.Material.Neon,
		CanCollide = false,
		CanQuery = false,
	}, parent)
	local l = Instance.new("PointLight")
	l.Color = color
	l.Range = range
	l.Brightness = brightness
	l.Shadows = false
	l.Parent = holder
	return holder
end

local function sound(parent: Instance, id: string, volume: number, pitch: number, maxDist: number?)
	local s = Instance.new("Sound")
	s.SoundId = id
	s.Volume = volume
	s.Looped = true
	s.PlaybackSpeed = pitch
	s.RollOffMaxDistance = maxDist or 70
	s.RollOffMinDistance = 6
	s.RollOffMode = Enum.RollOffMode.InverseTapered
	s.Parent = parent
	return s
end

local function table_(x, z, color)
	local top = part({
		Name = "TableTop",
		ClassName = "Part",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.5, 5, 5),
		CFrame = CFrame.new(x, 3, z) * CFrame.Angles(0, 0, math.rad(90)),
		Color = color,
		Material = Enum.Material.SmoothPlastic,
	})
	top.Parent = root.Decor
	local leg = box("TableLeg", x - 0.3, 0, z - 0.3, x + 0.3, 3, z + 0.3, C.Metal, Enum.Material.Metal, root.Decor)
	leg.CanCollide = false
	for i = 0, 2 do
		local a = i * math.pi * 2 / 3 + 0.4
		local sx, sz = x + math.cos(a) * 3.6, z + math.sin(a) * 3.6
		local seat = part({
			Name = "Stool",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(1.6, 1.8, 1.8),
			CFrame = CFrame.new(sx, 0.8, sz) * CFrame.Angles(0, 0, math.rad(90)),
			Color = Color3.fromHSV((i * 0.17 + x * 0.01) % 1, 0.55, 0.95),
			Material = Enum.Material.SmoothPlastic,
		}, root.Decor)
		seat.CanCollide = false
	end
end

local function stall(name: string, x0: number, x1: number, z: number, facing: number, color: Color3, text: string)
	-- Storefront set into a wall. facing = +1 means the sign faces +Z.
	local depth = 1
	local front = box(name, x0, 0, z - depth, x1, 12, z + depth, color, Enum.Material.SmoothPlastic, root.Decor)
	front.CanCollide = false
	local w = math.abs(x1 - x0)
	local cf = CFrame.new((x0 + x1) / 2, 10, z + facing * 1.3) * CFrame.Angles(0, facing > 0 and math.pi or 0, 0)
	local s = sign(name .. "Sign", cf, Vector2.new(w - 2, 3), text, color:Lerp(Color3.new(0, 0, 0), 0.25), Color3.new(1, 1, 1), { LightRange = 10 })
	s.Parent = root.Decor
	-- shutter (closed for the night)
	local shutter = box(name .. "Shutter", x0 + 1, 0.2, z + facing * 1.1 - 0.1, x1 - 1, 7.5, z + facing * 1.1 + 0.1, Color3.fromRGB(150, 150, 160), Enum.Material.DiamondPlate, root.Decor)
	shutter.CanCollide = false
end

-- Slanted part between two points, used for escalator rails and step strips.
local function slab(name, a: Vector3, b: Vector3, width: number, thickness: number, color, material, parent)
	local mid = (a + b) / 2
	local len = (b - a).Magnitude
	return part({
		Name = name,
		Size = Vector3.new(width, thickness, len),
		CFrame = CFrame.lookAt(mid, b),
		Color = color,
		Material = material or Enum.Material.SmoothPlastic,
	}, parent)
end

local function buildShell()
	local floor = box("Floor", -HALL_X, -2, HALL_Z0, HALL_X, 0, HALL_Z1, C.Floor, Enum.Material.Marble)
	floor:SetAttribute("Surface", "Quiet")
	-- checker inlays
	for z = HALL_Z0 + 8, HALL_Z1 - 8, 16 do
		for x = -HALL_X + 8, HALL_X - 8, 16 do
			if ((x + z) / 16) % 2 == 0 then
				local t = box("Tile", x - 8, 0, z - 8, x + 8, 0.02, z + 8, C.FloorDark, Enum.Material.Marble, root.Decor)
				t.CanCollide = false
				t.CanQuery = false
			end
		end
	end
	-- outer walls
	box("WallW", -HALL_X - 2, 0, HALL_Z0, -HALL_X, WALL_H, HALL_Z1, C.Wall)
	box("WallE", HALL_X, 0, HALL_Z0, HALL_X + 2, WALL_H, HALL_Z1, C.Wall)
	box("WallS", -HALL_X - 2, 0, HALL_Z0 - 2, HALL_X + 2, WALL_H, HALL_Z0, C.Wall)
	box("WallN", -HALL_X - 2, 0, HALL_Z1, HALL_X + 2, WALL_H, HALL_Z1 + 2, C.Wall)
	-- glass roof with frame, keeps the night sky visible
	local roof = box("Roof", -HALL_X - 2, WALL_H, HALL_Z0 - 2, HALL_X + 2, WALL_H + 1, HALL_Z1 + 2, Color3.fromRGB(80, 90, 140), Enum.Material.Glass, root.Decor)
	roof.Transparency = 0.75
	roof.CastShadow = false
	for z = HALL_Z0, HALL_Z1, 24 do
		box("RoofBeam", -HALL_X, WALL_H - 1.5, z - 0.5, HALL_X, WALL_H, z + 0.5, C.Wall, nil, root.Decor)
	end
	-- after-hours ceiling lamps: neutral, even light so the routes read on a phone
	for z = 0, HALL_Z1 - 10, 30 do
		for x = -40, 40, 40 do
			local lamp = pointLight(Vector3.new(x, WALL_H - 3, z), Color3.fromRGB(235, 232, 255), 45, 0.45, root.Decor)
			lamp.Size = Vector3.new(3, 0.6, 3)
			lamp.Shape = Enum.PartType.Block
		end
	end
end

local function buildHideout()
	local f = Instance.new("Folder")
	f.Name = "Hideout"
	f.Parent = root
	-- cardboard fort walls with a wide mouth facing the plaza
	box("FortW", -24, 0, HALL_Z0, -22, 9, 8, C.Cardboard, Enum.Material.Cardboard, f)
	box("FortE", 22, 0, HALL_Z0, 24, 9, 8, C.Cardboard, Enum.Material.Cardboard, f)
	box("FortNW", -24, 0, 6, -9, 9, 8, C.Cardboard, Enum.Material.Cardboard, f)
	box("FortNE", 9, 0, 6, 24, 9, 8, C.Cardboard, Enum.Material.Cardboard, f)
	-- crenellations
	for x = -22, 20, 6 do
		if math.abs(x + 1.5) > 10 then
			box("Crenel", x, 9, 6, x + 3, 11, 8, C.Cardboard, Enum.Material.Cardboard, f)
		end
	end
	local rug = part({
		Name = "Rug",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.1, 30, 30),
		CFrame = CFrame.new(0, 0.05, -8) * CFrame.Angles(0, 0, math.rad(90)),
		Color = Color3.fromRGB(120, 60, 140),
		Material = Enum.Material.Fabric,
		CanCollide = false,
	}, f)
	rug.CanQuery = false
	-- rescue station pad (Meshy prop sits on top when available)
	local pad = part({
		Name = "StationPad",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.6, 12, 12),
		CFrame = CFrame.new(Map.Points.Station + Vector3.new(0, 0.3, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		Color = C.Pink,
		Material = Enum.Material.Neon,
	}, f)
	pad:SetAttribute("Station", true)
	local ring = Instance.new("PointLight")
	ring.Color = C.Pink
	ring.Range = 14
	ring.Brightness = 0.8
	ring.Parent = pad
	sign("HideoutSign", CFrame.new(0, 12.5, 7.6) * CFrame.Angles(0, math.pi, 0), Vector2.new(18, 4.5), "🛏️ HIDEOUT", C.Pink, Color3.new(1, 1, 1), { TwoSided = true, LightRange = 24 }).Parent = f
	sign("StationSign", CFrame.new(0, 7, -15.5) * CFrame.Angles(0, math.pi, 0), Vector2.new(14, 3), "BRING SLEEPERS HERE", Color3.fromRGB(120, 60, 140), Color3.new(1, 1, 1), { TwoSided = true }).Parent = f
	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "SpawnLocation"
	spawn.Anchored = true
	spawn.Size = Vector3.new(8, 0.4, 8)
	spawn.Position = Map.Points.Spawn + Vector3.new(0, 0.2, 0)
	spawn.CFrame = CFrame.lookAt(spawn.Position, spawn.Position + Vector3.new(0.4, 0, 1))
	spawn.Color = C.Cardboard
	spawn.Material = Enum.Material.Cardboard
	spawn.Duration = 0
	spawn.Neutral = true
	spawn.Parent = f
	-- stacked boxes for flavour
	for i, p in { Vector3.new(-18, 0, -20), Vector3.new(-14, 0, -21), Vector3.new(17, 0, -19), Vector3.new(18, 4, -19), Vector3.new(12, 0, -21) } do
		local s = 3.5 + (i % 2)
		box("Box", p.X - s / 2, p.Y, p.Z - s / 2, p.X + s / 2, p.Y + s, p.Z + s / 2, C.Cardboard, Enum.Material.Cardboard, f)
	end
	zone("Hideout", -22, HALL_Z0, 22, 6)
end

local function buildPlaza()
	-- Fountain collision (the Meshy fountain prop dresses it)
	local fp = Map.Points.Fountain
	local basin = part({
		Name = "FountainBasin",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(2.4, 20, 20),
		CFrame = CFrame.new(fp + Vector3.new(0, 1.2, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		Color = Color3.fromRGB(90, 190, 190),
		Material = Enum.Material.SmoothPlastic,
	})
	basin:SetAttribute("PropSlot", "Fountain")
	local water = part({
		Name = "FountainWater",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.4, 18, 18),
		CFrame = CFrame.new(fp + Vector3.new(0, 2.3, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		Color = Color3.fromRGB(80, 200, 255),
		Material = Enum.Material.Glass,
		Transparency = 0.3,
		CanCollide = false,
	}, root.Decor)
	local spout = part({
		Name = "FountainSpout",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(7, 2.4, 2.4),
		CFrame = CFrame.new(fp + Vector3.new(0, 4.5, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		Color = Color3.fromRGB(240, 230, 210),
		Material = Enum.Material.SmoothPlastic,
	})
	spout:SetAttribute("PropSlot", "FountainSpout")
	local splash = Instance.new("ParticleEmitter")
	splash.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	splash.Color = ColorSequence.new(Color3.fromRGB(170, 230, 255))
	splash.Rate = 30
	splash.Lifetime = NumberRange.new(0.8, 1.2)
	splash.Speed = NumberRange.new(8, 11)
	splash.SpreadAngle = Vector2.new(18, 18)
	splash.Acceleration = Vector3.new(0, -24, 0)
	splash.Size = NumberSequence.new(0.6)
	splash.Parent = spout
	local att = Instance.new("Attachment")
	att.Parent = water
	sound(water, "rbxasset://sounds/impact_water.mp3", 0.35, 0.55, 60)
	pointLight(fp + Vector3.new(0, 1, 0), Color3.fromRGB(110, 220, 255), 26, 1.2, root.Decor)

	-- Route fork sign post, visible from the hideout mouth
	local fork = Map.Points.Fork
	box("ForkPost", fork.X - 0.4, 0, fork.Z - 0.4, fork.X + 0.4, 17, fork.Z + 0.4, C.Metal, Enum.Material.Metal, root.Decor)
	sign("SignQuiet", CFrame.new(fork.X - 5.2, 15.2, fork.Z - 0.5), Vector2.new(10, 3), "◀ QUIET WAY  🤫", C.Quiet, Color3.new(1, 1, 1), { LightRange = 18 })
	sign("SignLoud", CFrame.new(fork.X + 5.2, 11.6, fork.Z - 0.5), Vector2.new(10, 3), "LOUD SHORTCUT ▶ ⚠️", C.Loud, Color3.new(1, 1, 1), { LightRange = 18 })

	-- Food court tables and stalls
	for _, t in { { 20, 26 }, { 28, 40 }, { -4, 52 }, { 6, 62 }, { -34, 18 }, { 34, 18 }, { -6, 104 }, { 6, 116 }, { 30, 140 }, { -18, 140 } } do
		table_(t[1], t[2], Color3.fromRGB(250, 250, 245))
	end
	stall("WokRoll", -30, -8, BLOCK_Z0 - 1, -1, Color3.fromRGB(200, 60, 60), "WOK & ROLL")
	stall("SoupBowl", 24, 44, BLOCK_Z0 - 1, -1, Color3.fromRGB(240, 140, 40), "SOUP-ER BOWL")
	stall("Pretzel", 46, 59, BLOCK_Z0 - 1, -1, Color3.fromRGB(150, 90, 200), "PRETZELS")
	stall("Smoothie", -30, -6, BLOCK_Z1 + 1, 1, Color3.fromRGB(60, 170, 120), "SMOOTHIE MOON")
	stall("Taco", 26, 56, BLOCK_Z1 + 1, 1, Color3.fromRGB(220, 80, 140), "TACO TORNADO")
	-- side-wall stores
	for i, s in { { 28, "ARCADE" }, { 52, "TOY BARN" }, { 124, "SOCK SHACK" }, { 148, "PHONE CASES" } } do
		local z = s[1]
		local col = Color3.fromHSV((i * 0.21) % 1, 0.6, 0.85)
		box("StoreE" .. i, HALL_X - 1, 0, z - 9, HALL_X, 14, z + 9, col, nil, root.Decor).CanCollide = false
		sign("StoreSignE" .. i, CFrame.new(HALL_X - 1.4, 11, z) * CFrame.Angles(0, math.rad(90), 0), Vector2.new(16, 3), s[2], col:Lerp(Color3.new(0, 0, 0), 0.3), nil, { LightRange = 10 }).Parent = root.Decor
	end
	for i, s in { { 128, "CANDLE CORNER" }, { 150, "GAME GURU" } } do
		local z = s[1]
		local col = Color3.fromHSV((i * 0.33 + 0.5) % 1, 0.6, 0.85)
		box("StoreW" .. i, -HALL_X, 0, z - 8, -HALL_X + 1, 14, z + 8, col, nil, root.Decor).CanCollide = false
		sign("StoreSignW" .. i, CFrame.new(-HALL_X + 1.4, 11, z) * CFrame.Angles(0, math.rad(-90), 0), Vector2.new(14, 3), s[2], col:Lerp(Color3.new(0, 0, 0), 0.3), nil, { LightRange = 10 }).Parent = root.Decor
	end
	-- planters
	for _, p in { Vector3.new(-10, 0, 14), Vector3.new(10, 0, 14), Vector3.new(-44, 0, 64), Vector3.new(52, 0, 96), Vector3.new(-8, 0, 96) } do
		box("Planter", p.X - 2, 0, p.Z - 2, p.X + 2, 2.5, p.Z + 2, Color3.fromRGB(120, 90, 70), Enum.Material.Wood, root.Decor)
		local bush = part({
			Name = "Bush",
			Shape = Enum.PartType.Ball,
			Size = Vector3.new(4.5, 4.5, 4.5),
			Position = p + Vector3.new(0, 4, 0),
			Color = Color3.fromRGB(70, 160, 90),
			Material = Enum.Material.Grass,
			CanCollide = false,
		}, root.Decor)
		bush.CanQuery = false
	end
end

local function buildQuietRoute()
	-- Blue carpet runner from the fork round the fountain, up the west side, through the
	-- Cozy Corner and into the north hall. Purely visual: the floor is already quiet.
	local runner = {
		{ -2, 20, -40, 26 },
		{ -60 + 4, 20, -44, 120 },
		{ -56, 112, -10, 120 },
	}
	for _, r in runner do
		local x0, z0, x1, z1 = r[1], r[2], r[3], r[4]
		local c = box("QuietCarpet", math.min(x0, x1), 0, math.min(z0, z1), math.max(x0, x1), 0.06, math.max(z0, z1), C.QuietCarpet, Enum.Material.Fabric, root.Decor)
		c.CanCollide = false
		c.CanQuery = false
	end
	for z = 30, 118, 16 do
		pointLight(Vector3.new(-58, 8, z), C.Quiet, 22, 1.4, root.Decor)
	end
	for _, z in { 40, 64 } do
		sign("QuietArrow", CFrame.new(-59.6, 6, z) * CFrame.Angles(0, math.rad(-90), 0), Vector2.new(8, 2.4), "🤫 QUIET WAY ▲", C.Quiet, nil, { LightRange = 12 }).Parent = root.Decor
	end

	-- Cozy Corner: the sheltered gap at the west end of the Wok Wall.
	local canopy = box("CozyCanopy", -HALL_X, 10, BLOCK_Z0, GAP_X1, 11, BLOCK_Z1, Color3.fromRGB(70, 110, 190), Enum.Material.Fabric, root.Decor)
	canopy.CanCollide = false
	canopy.CanQuery = false
	for _, z in { BLOCK_Z0 + 0.5, BLOCK_Z1 - 0.5 } do
		for x = -HALL_X + 1, GAP_X1 - 1, 3 do
			local fringe = box("Fringe", x - 0.6, 9, z - 0.2, x + 0.6, 10, z + 0.2, Color3.fromRGB(250, 220, 120), Enum.Material.Fabric, root.Decor)
			fringe.CanCollide = false
			fringe.CanQuery = false
		end
	end
	local couch = box("CozyCouch", -HALL_X, 0, BLOCK_Z0 + 3, -HALL_X + 3, 2.5, BLOCK_Z1 - 3, Color3.fromRGB(240, 130, 160), Enum.Material.Fabric, root.Decor)
	couch.CanCollide = false
	for z = BLOCK_Z0 + 3, BLOCK_Z1 - 3, 4 do
		part({ Name = "Cushion", Shape = Enum.PartType.Ball, Size = Vector3.new(2.6, 2.6, 2.6), Position = Vector3.new(-HALL_X + 2, 3, z + 2), Color = Color3.fromRGB(255, 220, 140), Material = Enum.Material.Fabric, CanCollide = false, CanQuery = false }, root.Decor)
	end
	local rug = box("CozyRug", -HALL_X + 3, 0, BLOCK_Z0, GAP_X1, 0.08, BLOCK_Z1, Color3.fromRGB(110, 150, 230), Enum.Material.Fabric, root.Decor)
	rug.CanCollide = false
	rug.CanQuery = false
	pointLight(Vector3.new(-52, 8.5, (BLOCK_Z0 + BLOCK_Z1) / 2), Color3.fromRGB(255, 200, 140), 20, 1.6, root.Decor)
	sign("CozySign", CFrame.new(-52, 12.8, BLOCK_Z0 - 0.3), Vector2.new(14, 3.2), "💤 COZY CORNER", Color3.fromRGB(70, 110, 190), nil, { TwoSided = true, LightRange = 16 }).Parent = root.Decor
	sign("CozyHint", CFrame.new(-52, 7, BLOCK_Z1 + 0.3) * CFrame.Angles(0, math.pi, 0), Vector2.new(13, 2.2), "sleepers settle down here", Color3.fromRGB(70, 110, 190), nil, { LightRange = 10 }).Parent = root.Decor
	local shelter = zone("Shelter", -HALL_X, BLOCK_Z0 - 2, GAP_X1, BLOCK_Z1 + 2)
	sound(shelter, "rbxasset://sounds/action_swim.mp3", 0.12, 0.35, 30)
end

local function buildBlock()
	-- Wok Wall: solid kitchen block with the vent duct and the escalator bridge through it.
	local f = Instance.new("Folder")
	f.Name = "WokWall"
	f.Parent = root
	box("BlockW", GAP_X1, 0, BLOCK_Z0, VENT_X0, BLOCK_H, BLOCK_Z1, C.Block, nil, f)
	box("VentRoof", VENT_X0, VENT_H, BLOCK_Z0, VENT_X1, BLOCK_H, BLOCK_Z1, C.Block, nil, f)
	box("BlockMid", VENT_X1, 0, BLOCK_Z0, ESC_X0, BLOCK_H, BLOCK_Z1, C.Block, nil, f)
	box("BlockUnderBridge", ESC_X0, 0, BLOCK_Z0, ESC_X1, BLOCK_H, BLOCK_Z1, C.Metal, Enum.Material.Metal, f)
	box("BlockE", ESC_X1, 0, BLOCK_Z0, HALL_X, BLOCK_H, BLOCK_Z1, C.Block, nil, f)
	-- tall parapets so the bridge is the only way over the top
	box("RoofW", GAP_X1, BLOCK_H, BLOCK_Z0, ESC_X0 - 0.5, BLOCK_H + 9, BLOCK_Z1, Color3.fromRGB(120, 55, 55), nil, f)
	box("RoofE", ESC_X1 + 0.5, BLOCK_H, BLOCK_Z0, HALL_X, BLOCK_H + 9, BLOCK_Z1, Color3.fromRGB(120, 55, 55), nil, f)
	-- vent duct interior
	local duct = box("DuctFloor", VENT_X0, 0, BLOCK_Z0, VENT_X1, 0.1, BLOCK_Z1, Color3.fromRGB(150, 160, 160), Enum.Material.DiamondPlate, f)
	duct.CanCollide = false
	for z = BLOCK_Z0 + 3, BLOCK_Z1 - 3, 6 do
		pointLight(Vector3.new((VENT_X0 + VENT_X1) / 2, VENT_H - 0.8, z), C.Vent, 10, 1.2, f)
	end
	zone("Vent", VENT_X0, BLOCK_Z0, VENT_X1, BLOCK_Z1)
	-- vent doors (one each side, opened together by a Crab Rangoon buddy)
	for i, zFace in { BLOCK_Z0 - 0.4, BLOCK_Z1 + 0.4 } do
		local door = box("VentDoor" .. i, VENT_X0, 0, zFace - 0.3, VENT_X1, VENT_H, zFace + 0.3, C.Vent, Enum.Material.DiamondPlate, f)
		door:SetAttribute("VentDoor", true)
		door:SetAttribute("ClosedCFrame", door.CFrame)
		for y = 1, VENT_H - 1, 1.2 do
			local slat = box("Slat", VENT_X0 + 0.3, y, zFace - 0.5, VENT_X1 - 0.3, y + 0.4, zFace + 0.5, Color3.fromRGB(60, 120, 70), Enum.Material.Metal, door)
			slat.CanCollide = false
			slat.CanQuery = false
			local w = Instance.new("WeldConstraint")
			w.Part0 = door
			w.Part1 = slat
			w.Parent = slat
			slat.Anchored = false
			slat.Massless = true
		end
		local facing = i == 1 and 0 or math.pi
		local s = sign("VentSign" .. i, CFrame.new((VENT_X0 + VENT_X1) / 2, VENT_H + 2.2, zFace + (i == 1 and -0.2 or 0.2)) * CFrame.Angles(0, facing, 0), Vector2.new(9, 2.6), "🦀 VENT — buddy opens", C.Vent, Color3.new(1, 1, 1), { LightRange = 12 })
		s.Parent = f
		local prompt = Instance.new("ProximityPrompt")
		prompt.Name = "VentPrompt"
		prompt.ActionText = "Pry open"
		prompt.ObjectText = "Vent (needs Crab Rangoon buddy)"
		prompt.HoldDuration = 0.4
		prompt.MaxActivationDistance = 10
		prompt.RequiresLineOfSight = false
		prompt.Parent = door
	end
end

local function buildLoudRoute()
	local f = Instance.new("Folder")
	f.Name = "Escalators"
	f.Parent = root
	local cx = (ESC_X0 + ESC_X1) / 2
	local w = ESC_X1 - ESC_X0
	-- South escalator rises toward +Z, north escalator falls toward +Z.
	local runs = {
		{ z0 = BLOCK_Z0 - ESC_RUN, z1 = BLOCK_Z0, up = true },
		{ z0 = BLOCK_Z1, z1 = BLOCK_Z1 + ESC_RUN, up = false },
	}
	for i, r in runs do
		local wedge = part({
			ClassName = "WedgePart",
			Name = "Escalator" .. i,
			Size = Vector3.new(w, BLOCK_H, ESC_RUN),
			CFrame = CFrame.new(cx, BLOCK_H / 2, (r.z0 + r.z1) / 2) * CFrame.Angles(0, r.up and 0 or math.pi, 0),
			Color = Color3.fromRGB(70, 70, 80),
			Material = Enum.Material.Metal,
		}, f)
		wedge:SetAttribute("Surface", "Loud")
		local low = Vector3.new(0, 0, r.up and r.z0 or r.z1)
		local high = Vector3.new(0, BLOCK_H, r.up and r.z1 or r.z0)
		-- step strips
		local steps = 14
		for s = 1, steps - 1 do
			local t = s / steps
			local p = low:Lerp(high, t)
			local strip = part({
				Name = "Step",
				Size = Vector3.new(w - 0.6, 0.25, 0.5),
				CFrame = CFrame.lookAt(Vector3.new(cx, p.Y + 0.1, p.Z), Vector3.new(cx, high.Y + 0.1, high.Z)),
				Color = C.Hazard,
				Material = Enum.Material.Neon,
				CanCollide = false,
				CanQuery = false,
			}, f)
			strip:SetAttribute("RattleStep", true)
			strip:SetAttribute("BaseCFrame", strip.CFrame)
		end
		-- glass side rails with neon strips that flash with the rattle cycle
		for _, x in { ESC_X0 - 0.5, ESC_X1 + 0.5 } do
			local a = Vector3.new(x, low.Y + 3, low.Z)
			local b = Vector3.new(x, high.Y + 3, high.Z)
			local rail = slab("Rail", a, b, 1, 6, Color3.fromRGB(150, 200, 230), Enum.Material.Glass, f)
			rail.Transparency = 0.5
			local strip = slab("RattleLight", a + Vector3.new(0, 3.2, 0), b + Vector3.new(0, 3.2, 0), 1.2, 0.5, C.Loud, Enum.Material.Neon, f)
			strip.CanCollide = false
			strip:SetAttribute("RattleLight", true)
			local l = Instance.new("PointLight")
			l.Color = C.Loud
			l.Range = 16
			l.Brightness = 1.5
			l.Parent = strip
		end
		-- hazard grate at the foot
		local footZ = r.up and r.z0 - 4 or r.z1 + 4
		local grate = box("LoudGrate", ESC_X0 - 1, 0, footZ - 4, ESC_X1 + 1, 0.08, footZ + 4, C.Hazard, Enum.Material.DiamondPlate, f)
		grate.CanCollide = false
		grate.CanQuery = false
		-- loud zone covers the escalator and its foot grate
		zone("Loud", ESC_X0 - 1, math.min(r.z0, footZ - 4), ESC_X1 + 1, math.max(r.z1, footZ + 4), -1, BLOCK_H + 8)
		local rattle = sound(wedge, "rbxasset://sounds/action_footsteps_plastic.mp3", 0.5, 0.55, 80)
		rattle.Name = "Rattle"
	end
	-- bridge over the Wok Wall
	local bridge = box("Bridge", ESC_X0, BLOCK_H, BLOCK_Z0, ESC_X1, BLOCK_H + 0.3, BLOCK_Z1, C.Metal, Enum.Material.DiamondPlate, f)
	bridge:SetAttribute("Surface", "Loud")
	for _, x in { ESC_X0 - 0.5, ESC_X1 + 0.5 } do
		local rail = box("BridgeRail", x - 0.5, BLOCK_H, BLOCK_Z0, x + 0.5, BLOCK_H + 6, BLOCK_Z1, Color3.fromRGB(150, 200, 230), Enum.Material.Glass, f)
		rail.Transparency = 0.5
	end
	zone("Loud", ESC_X0 - 1, BLOCK_Z0, ESC_X1 + 1, BLOCK_Z1, BLOCK_H - 1, BLOCK_H + 8)
	-- warnings, readable from the plaza
	-- warnings stand beside the lane (not in it) so they never block the camera
	local wx = ESC_X0 - 6
	local zs, zn = BLOCK_Z0 - ESC_RUN - 6, BLOCK_Z1 + ESC_RUN + 6
	box("EscWarnPost", wx - 0.3, 0, zs - 0.3, wx + 0.3, 12, zs + 0.3, C.Metal, Enum.Material.Metal, f)
	sign("EscWarn", CFrame.new(wx, 12.5, zs - 0.4), Vector2.new(10, 3), "⚠️ RATTLING ESCALATOR", C.Loud, Color3.new(1, 1, 1), { TwoSided = true }).Parent = f
	sign("EscWarn2", CFrame.new(wx, 10.2, zs - 0.4), Vector2.new(9, 1.6), "walk… or time the rattle", Color3.fromRGB(120, 30, 30), Color3.fromRGB(255, 220, 120), { TwoSided = true }).Parent = f
	box("EscWarnPostN", wx - 0.3, 0, zn - 0.3, wx + 0.3, 12, zn + 0.3, C.Metal, Enum.Material.Metal, f)
	sign("EscWarnN", CFrame.new(wx, 12.5, zn + 0.4) * CFrame.Angles(0, math.pi, 0), Vector2.new(10, 3), "⚠️ LOUD SHORTCUT HOME", C.Loud, Color3.new(1, 1, 1), { TwoSided = true }).Parent = f
	-- red lighting along the loud lane
	for _, z in { 30, 44, 128 } do
		pointLight(Vector3.new(cx + 8, 9, z), Color3.fromRGB(255, 110, 70), 22, 1.3, f)
	end
	local lane = box("LoudLane", ESC_X0 - 1, 0, 26, ESC_X1 + 1, 0.05, BLOCK_Z0 - ESC_RUN - 8, Color3.fromRGB(150, 50, 40), Enum.Material.DiamondPlate, root.Decor)
	lane.CanCollide = false
	lane.CanQuery = false
end

local function buildNorth()
	local p = Map.Points.RareStage
	local stage = part({
		Name = "RareStage",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(1, 14, 14),
		CFrame = CFrame.new(p + Vector3.new(0, 0.5, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		Color = C.Gold,
		Material = Enum.Material.Neon,
	})
	stage.Name = "RareStage"
	local beam = part({
		Name = "RareBeam",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(90, 7, 7),
		CFrame = CFrame.new(p + Vector3.new(0, 45, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		Color = C.Gold,
		Material = Enum.Material.Neon,
		Transparency = 1,
		CanCollide = false,
		CanQuery = false,
		CastShadow = false,
	})
	beam:SetAttribute("RareBeam", true)
	Map.beam = beam
	local l = Instance.new("PointLight")
	l.Color = C.Gold
	l.Range = 30
	l.Brightness = 2
	l.Parent = stage
	sign("RareSign", CFrame.new(p.X, 12, HALL_Z1 - 0.5), Vector2.new(20, 4), "⭐ RARE SNORING ZONE ⭐", Color3.fromRGB(150, 100, 20), C.Gold, { LightRange = 22 }).Parent = root.Decor
	for _, x in { -40, 0, 40 } do
		pointLight(Vector3.new(x, 10, 120), Color3.fromRGB(200, 160, 255), 30, 1.1, root.Decor)
	end
end

function Map.build(): Folder
	root = Instance.new("Folder")
	root.Name = "Map"
	local decor = Instance.new("Folder")
	decor.Name = "Decor"
	decor.Parent = root
	zones = Instance.new("Folder")
	zones.Name = "Zones"
	zones.Parent = root

	buildShell()
	buildHideout()
	buildPlaza()
	buildQuietRoute()
	buildBlock()
	buildLoudRoute()
	buildNorth()

	root.Parent = workspace
	return root
end

-- Point-in-zone test against the Zones folder. Returns the most specific zone kind.
local PRIORITY = { Shelter = 4, Vent = 3, Loud = 2, Hideout = 1 }
function Map.surfaceAt(pos: Vector3): string
	local best, bestP = "Quiet", 0
	for _, z in zones:GetChildren() do
		local rel = z.CFrame:PointToObjectSpace(pos)
		local h = z.Size / 2
		if math.abs(rel.X) <= h.X and math.abs(rel.Y) <= h.Y and math.abs(rel.Z) <= h.Z then
			local kind = z:GetAttribute("Kind")
			local pr = PRIORITY[kind] or 0
			if pr > bestP then
				best, bestP = kind, pr
			end
		end
	end
	if best == "Hideout" then
		return "Quiet"
	end
	return best
end

function Map.setupLighting()
	local Lighting = game:GetService("Lighting")
	Lighting.ClockTime = 21.5
	Lighting.Brightness = 1.6
	Lighting.Ambient = Color3.fromRGB(120, 118, 140)
	Lighting.OutdoorAmbient = Color3.fromRGB(130, 128, 150)
	Lighting.EnvironmentDiffuseScale = 0.4
	Lighting.EnvironmentSpecularScale = 0.3
	Lighting.GlobalShadows = true
	for _, c in Lighting:GetChildren() do
		if c:IsA("PostEffect") or c:IsA("Atmosphere") then
			c:Destroy()
		end
	end
	local cc = Instance.new("ColorCorrectionEffect")
	cc.Saturation = 0.05
	cc.Contrast = 0.08
	cc.TintColor = Color3.fromRGB(240, 235, 255)
	cc.Parent = Lighting
	local bloom = Instance.new("BloomEffect")
	bloom.Intensity = 0.6
	bloom.Size = 20
	bloom.Threshold = 1.4
	bloom.Parent = Lighting
end

return Map

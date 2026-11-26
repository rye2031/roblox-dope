-- Builds the mall with Studio geometry. Everything walkable or collision-critical is a plain
-- Part/WedgePart with exact dimensions; Meshy props are dressing only (see WorldFx).
--
-- Layout (studs, +Z is north, ground top at Y = 0):
--   FOOD COURT (hall X -60..60, Z -24..160)
--     Hideout            Z -24..8   (rescue station 0,0,-4; Shop + Index kiosks either side)
--     South plaza        Z 8..74    (fountain at -18,0,40; route fork at 0,0,22)
--     Wok Wall block     Z 74..92   X -44..60, 14 high. Crossed three ways:
--       quiet:  Cozy Corner gap   X -60..-44 (sheltered, drains the meter)
--       vent:   duct              X -40..-34 (Crab Rangoon buddy opens it)
--       loud:   escalator bridge  X 14..22   (rattles on a cycle)
--     North hall         Z 92..160  (rare stage at 20,0,146)
--   ARCADE (wing X 62..210, Z -30..150), through a paid gate in the hall's east wall (Z 16..40)
--     South floor        Z -30..92  (cabinet clusters, claw machines)
--     Cabinet Row        Z 92..100  crossed two ways:
--       loud:   dance floor gap  X 124..150 (thumps on a beat)
--       quiet:  ball pit         X 186..210 (sheltered, drains the meter; Ticketoad evolution route)
--     North floor        Z 100..150 (Prize Stage at 100,0,134)
local PhysicsService = game:GetService("PhysicsService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Theme = require(ReplicatedStorage.Shared.Theme)
local Config = require(ReplicatedStorage.Shared.Config)

local Map = {}

local HALL_X = 60
local HALL_Z0, HALL_Z1 = -24, 160
local WALL_H = 30
local BLOCK_Z0, BLOCK_Z1, BLOCK_H = 74, 92, 14
local ESC_X0, ESC_X1 = 14, 22
local ESC_RUN = 30
local VENT_X0, VENT_X1, VENT_H = -40, -34, 7
local GAP_X1 = -44

-- Arcade wing
local AX0, AX1 = HALL_X + 2, 210
local AZ0, AZ1 = -30, 150
local A_WALL_H = 22
local GATE_Z0, GATE_Z1, GATE_H = 16, 40, 14
local ROW_Z0, ROW_Z1, ROW_H = 92, 100, 12
local DANCE_X0, DANCE_X1 = 124, 150
local PIT_X0 = 186

Map.Points = {
	Station = Vector3.new(0, 0, -4),
	Spawn = Vector3.new(-9, 0, 1),
	Fork = Vector3.new(0, 0, 22),
	Fountain = Vector3.new(-18, 0, 40),
	RareStage = Vector3.new(20, 0, 146),
	VentSouth = Vector3.new((VENT_X0 + VENT_X1) / 2, 0, BLOCK_Z0),
	VentNorth = Vector3.new((VENT_X0 + VENT_X1) / 2, 0, BLOCK_Z1),
	ShopPad = Vector3.new(16, 0, -5),
	IndexPad = Vector3.new(-16, 0, -5),
	ArcadeGate = Vector3.new(HALL_X + 1, 0, (GATE_Z0 + GATE_Z1) / 2),
	RareStages = {
		FoodCourt = Vector3.new(20, 0, 146),
		Arcade = Vector3.new(100, 0, 134),
	},
	-- Common sleeper spots. The first one is in sight of the hideout.
	Spawns = {
		{ pos = Vector3.new(8, 0, 30), wing = "FoodCourt" },
		{ pos = Vector3.new(-52, 0, 54), wing = "FoodCourt" }, -- on the quiet route
		{ pos = Vector3.new(42, 0, 50), wing = "FoodCourt" }, -- by the escalator foot
		{ pos = Vector3.new(-30, 0, 128), wing = "FoodCourt" },
		{ pos = Vector3.new(46, 0, 128), wing = "FoodCourt" },
		{ pos = Vector3.new(90, 0, -18), wing = "Arcade" },
		{ pos = Vector3.new(138, 0, 14), wing = "Arcade" },
		{ pos = Vector3.new(196, 0, 30), wing = "Arcade" },
		{ pos = Vector3.new(108, 0, 72), wing = "Arcade" },
		{ pos = Vector3.new(80, 0, 124), wing = "Arcade" }, -- north: dance floor or ball pit home
		{ pos = Vector3.new(176, 0, 130), wing = "Arcade" },
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
		-- Arcade
		Vector3.new(52, 0, 28), -- 21 hall side of the gate
		Vector3.new(72, 0, 28), -- 22 arcade side of the gate
		Vector3.new(100, 0, 24), -- 23 south lane west
		Vector3.new(138, 0, 14), -- 24 south centre
		Vector3.new(196, 0, 20), -- 25 south-east
		Vector3.new(196, 0, 62), -- 26 east lane
		Vector3.new(137, 0, 68), -- 27 south of the dance floor
		Vector3.new(137, 0, 96), -- 28 dance floor
		Vector3.new(137, 0, 118), -- 29 north of the dance floor
		Vector3.new(198, 0, 96), -- 30 ball pit
		Vector3.new(198, 0, 124), -- 31 north-east
		Vector3.new(80, 0, 118), -- 32 north-west
		Vector3.new(88, 0, -18), -- 33 south-west corner
		Vector3.new(100, 0, 68), -- 34 south of cabinet row, west
	},
	links = {
		{ 1, 2 }, { 2, 3 }, { 2, 8 }, { 2, 10 }, { 3, 4 }, { 3, 5 }, { 4, 19 }, { 4, 10 },
		{ 5, 6 }, { 6, 7 }, { 7, 14 }, { 7, 20 }, { 8, 9 }, { 8, 10 }, { 9, 10 }, { 10, 11 },
		{ 11, 12 }, { 12, 13 }, { 13, 14 }, { 13, 15 }, { 13, 16 }, { 14, 15 }, { 14, 18 },
		{ 15, 17 }, { 15, 18 }, { 16, 17 }, { 19, 5 }, { 20, 14 },
		{ 8, 21 }, { 21, 22 }, { 22, 23 }, { 22, 33 }, { 33, 23 }, { 23, 24 }, { 24, 25 },
		{ 25, 26 }, { 24, 27 }, { 23, 34 }, { 34, 27 }, { 26, 27 }, { 26, 30 }, { 27, 28 },
		{ 28, 29 }, { 29, 32 }, { 29, 31 }, { 30, 31 }, { 31, 32 },
	},
}

local C = {
	Floor = Color3.fromRGB(244, 238, 230),
	FloorDark = Color3.fromRGB(226, 218, 242),
	Wall = Color3.fromRGB(238, 234, 246),
	Trim = Color3.fromRGB(214, 206, 236),
	Cardboard = Color3.fromRGB(236, 200, 150),
	Fort = Color3.fromRGB(255, 214, 226),
	FortTop = Color3.fromRGB(255, 160, 190),
	Quiet = Color3.fromRGB(100, 170, 255),
	QuietCarpet = Color3.fromRGB(184, 214, 255),
	Loud = Color3.fromRGB(255, 112, 96),
	Hazard = Color3.fromRGB(255, 208, 96),
	Metal = Color3.fromRGB(196, 200, 214),
	Block = Color3.fromRGB(255, 184, 164),
	BlockTop = Color3.fromRGB(246, 158, 140),
	Pink = Color3.fromRGB(255, 140, 196),
	Gold = Color3.fromRGB(255, 205, 90),
	Vent = Color3.fromRGB(130, 215, 160),
	Lilac = Color3.fromRGB(170, 146, 255),
	Arcade = Color3.fromRGB(226, 218, 250),
	ArcadeTile = Color3.fromRGB(202, 190, 246),
}
local TC = Theme.C

local root: Folder
local zones: Folder
local labels: Folder

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

local function decor(p: BasePart): BasePart
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	return p
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

-- Floating place label in the sky above a spot (same style everywhere; WorldFx bobs them).
local function float(name: string, pos: Vector3, text: string, accent: Color3, width: number, opts: { [string]: any }?)
	local anchor = part({
		Name = "Label_" .. name,
		Size = Vector3.new(1, 1, 1),
		Position = pos,
		Transparency = 1,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
	}, labels)
	local bb = Theme.floatLabel(anchor, text, accent, width, opts)
	return anchor, bb
end
Map.float = float

-- Flat sign on one face of a part, in the light house style: white board, ink text, an accent
-- border (or a solid accent board with white text when opts.Solid).
local function sign(
	name: string,
	cf: CFrame,
	size: Vector2,
	text: string,
	accent: Color3,
	_fg: Color3?,
	opts: { [string]: any }?
): BasePart
	opts = opts or {}
	local solid = opts.Solid == true
	local p = part({
		Name = name,
		Size = Vector3.new(size.X, size.Y, 0.4),
		CFrame = cf,
		Color = solid and accent or Color3.new(1, 1, 1),
		Material = Enum.Material.SmoothPlastic,
		CanCollide = false,
	})
	local function face(f)
		local gui = Instance.new("SurfaceGui")
		gui.Face = f
		gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		gui.PixelsPerStud = 40
		gui.LightInfluence = 0
		gui.Brightness = 1
		gui.Parent = p
		local frame = Instance.new("Frame")
		frame.Size = UDim2.fromScale(1, 1)
		frame.BackgroundColor3 = solid and accent or Color3.new(1, 1, 1)
		frame.BorderSizePixel = 0
		frame.Parent = gui
		local stroke = Instance.new("UIStroke")
		stroke.Thickness = 12
		stroke.Color = solid and Color3.new(1, 1, 1) or accent
		stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		stroke.Parent = frame
		local label = Instance.new("TextLabel")
		label.Size = UDim2.new(1, -48, 1, -34)
		label.Position = UDim2.fromOffset(24, 17)
		label.BackgroundTransparency = 1
		label.Text = text
		label.TextScaled = true
		label.FontFace = Theme.Font.Title
		label.TextColor3 = solid and Color3.new(1, 1, 1) or TC.Ink
		label.RichText = true
		label.Parent = frame
	end
	face(Enum.NormalId.Front)
	if opts.TwoSided then
		face(Enum.NormalId.Back)
	end
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
	local leg = box("TableLeg", x - 0.3, 0, z - 0.3, x + 0.3, 3, z + 0.3, C.Metal, Enum.Material.SmoothPlastic, root.Decor)
	leg.CanCollide = false
	for i = 0, 2 do
		local a = i * math.pi * 2 / 3 + 0.4
		local sx, sz = x + math.cos(a) * 3.6, z + math.sin(a) * 3.6
		local seat = part({
			Name = "Stool",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(1.6, 1.8, 1.8),
			CFrame = CFrame.new(sx, 0.8, sz) * CFrame.Angles(0, 0, math.rad(90)),
			Color = Color3.fromHSV((i * 0.17 + x * 0.01) % 1, 0.32, 1),
			Material = Enum.Material.SmoothPlastic,
		}, root.Decor)
		seat.CanCollide = false
	end
end

local function stall(name: string, x0: number, x1: number, z: number, facing: number, color: Color3, text: string)
	-- Storefront set into a wall. facing = +1 means the sign faces +Z.
	local depth = 1
	local front = box(name, x0, 0, z - depth, x1, 12, z + depth, Theme.tint(color, 0.55), Enum.Material.SmoothPlastic, root.Decor)
	front.CanCollide = false
	local w = math.abs(x1 - x0)
	local cf = CFrame.new((x0 + x1) / 2, 10, z + facing * 1.3) * CFrame.Angles(0, facing > 0 and math.pi or 0, 0)
	sign(name .. "Sign", cf, Vector2.new(w - 2, 3), text, color, nil, { Solid = true }).Parent = root.Decor
	-- shutter (still closed: the mall hasn't opened yet)
	local shutter = box(name .. "Shutter", x0 + 1, 0.2, z + facing * 1.1 - 0.1, x1 - 1, 7.5, z + facing * 1.1 + 0.1, Color3.fromRGB(228, 230, 238), Enum.Material.DiamondPlate, root.Decor)
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

-- Glass roof with beams over a rectangle.
local function roof(x0, x1, z0, z1, h)
	local r = box("Roof", x0, h, z0, x1, h + 1, z1, Color3.fromRGB(220, 235, 255), Enum.Material.Glass, root.Decor)
	r.Transparency = 0.82
	r.CastShadow = false
	for z = z0, z1, 24 do
		box("RoofBeam", x0, h - 1.2, z - 0.5, x1, h, z + 0.5, Color3.fromRGB(250, 250, 255), nil, root.Decor).CanQuery = false
	end
end

local function buildShell()
	local floor = box("Floor", -HALL_X, -2, HALL_Z0, HALL_X, 0, HALL_Z1, C.Floor, Enum.Material.SmoothPlastic)
	floor:SetAttribute("Surface", "Quiet")
	-- soft checker inlays
	for z = HALL_Z0 + 8, HALL_Z1 - 8, 16 do
		for x = -HALL_X + 8, HALL_X - 8, 16 do
			if ((x + z) / 16) % 2 == 0 then
				decor(box("Tile", x - 8, 0, z - 8, x + 8, 0.02, z + 8, C.FloorDark, Enum.Material.SmoothPlastic, root.Decor))
			end
		end
	end
	-- outer walls (the east wall has the Arcade gate in it)
	box("WallW", -HALL_X - 2, 0, HALL_Z0, -HALL_X, WALL_H, HALL_Z1, C.Wall)
	box("WallE_S", HALL_X, 0, HALL_Z0, HALL_X + 2, WALL_H, GATE_Z0, C.Wall)
	box("WallE_N", HALL_X, 0, GATE_Z1, HALL_X + 2, WALL_H, HALL_Z1, C.Wall)
	box("WallE_Lintel", HALL_X, GATE_H, GATE_Z0, HALL_X + 2, WALL_H, GATE_Z1, C.Wall)
	box("WallS", -HALL_X - 2, 0, HALL_Z0 - 2, HALL_X + 2, WALL_H, HALL_Z0, C.Wall)
	box("WallN", -HALL_X - 2, 0, HALL_Z1, HALL_X + 2, WALL_H, HALL_Z1 + 2, C.Wall)
	-- skirting trim along the base of the walls
	for _, w in { { -HALL_X, HALL_Z0, -HALL_X + 0.3, HALL_Z1 }, { HALL_X - 0.3, HALL_Z0, HALL_X, HALL_Z1 } } do
		decor(box("Skirting", w[1], 0, w[2], w[3], 1.2, w[4], C.Trim, nil, root.Decor))
	end
	roof(-HALL_X - 2, HALL_X + 2, HALL_Z0 - 2, HALL_Z1 + 2, WALL_H)
end

-- Walk-in kiosk: a white counter under a striped awning, a glowing pad in front and a
-- floating label above. Stepping on the pad opens the matching panel (client side).
local function kiosk(name: string, x: number, z: number, accent: Color3, text: string, icon: string, padPos: Vector3, parent: Instance)
	local f = Instance.new("Folder")
	f.Name = name .. "Kiosk"
	f.Parent = parent
	box("Counter", x - 4, 0, z - 1, x + 4, 3.4, z + 1.5, Color3.new(1, 1, 1), nil, f)
	decor(box("CounterStripe", x - 4.05, 1.2, z + 1.45, x + 4.05, 2.2, z + 1.6, accent, nil, f))
	box("Back", x - 4.5, 0, z - 3, x + 4.5, 10, z - 2, Theme.tint(accent, 0.7), nil, f)
	for i = 0, 5 do
		local x0 = x - 4.5 + i * 1.5
		decor(box("Awning", x0, 9, z - 2, x0 + 1.5, 9.6, z + 2.4, i % 2 == 0 and accent or Color3.new(1, 1, 1), nil, f))
	end
	local pad = part({
		Name = name .. "Pad",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.3, 6.5, 6.5),
		CFrame = CFrame.new(padPos + Vector3.new(0, 0.15, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		Color = accent,
		Material = Enum.Material.Neon,
		CanCollide = false,
		CanQuery = false,
	}, f)
	pad:SetAttribute("Pad", name)
	float(name, Vector3.new(x, 15, z), text, accent, 9, { Icon = icon, Sub = "step on the pad", Height = 2.6 })
end

local function buildHideout()
	local f = Instance.new("Folder")
	f.Name = "Hideout"
	f.Parent = root
	-- cardboard fort walls with a wide mouth facing the plaza
	box("FortW", -24, 0, HALL_Z0, -22, 9, 8, C.Fort, nil, f)
	box("FortE", 22, 0, HALL_Z0, 24, 9, 8, C.Fort, nil, f)
	box("FortNW", -24, 0, 6, -9, 9, 8, C.Fort, nil, f)
	box("FortNE", 9, 0, 6, 24, 9, 8, C.Fort, nil, f)
	for x = -22, 20, 6 do
		if math.abs(x + 1.5) > 10 then
			box("Crenel", x, 9, 6, x + 3, 11, 8, C.FortTop, nil, f)
		end
	end
	local rug = part({
		Name = "Rug",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.1, 30, 30),
		CFrame = CFrame.new(0, 0.05, -8) * CFrame.Angles(0, 0, math.rad(90)),
		Color = Color3.fromRGB(232, 220, 255),
		Material = Enum.Material.SmoothPlastic,
		CanCollide = false,
	}, f)
	rug.CanQuery = false
	-- rescue station pad (Meshy prop sits behind it)
	local pad = part({
		Name = "StationPad",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.6, 12, 12),
		CFrame = CFrame.new(Map.Points.Station + Vector3.new(0, 0.3, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		Color = C.Pink,
		Material = Enum.Material.Neon,
	}, f)
	pad:SetAttribute("Station", true)
	float("Hideout", Vector3.new(0, 19, -4), "HIDEOUT", TC.Rose, 14, { Icon = "🏠", Sub = "bring sleepers to the pink pad", Height = 3.4 })
	kiosk("Shop", 16, -13, TC.Peach, "SHOP", "🛍", Map.Points.ShopPad, f)
	kiosk("Index", -16, -13, TC.Lilac, "INDEX", "📖", Map.Points.IndexPad, f)
	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "SpawnLocation"
	spawn.Anchored = true
	spawn.Size = Vector3.new(6, 0.4, 6)
	spawn.Position = Map.Points.Spawn + Vector3.new(0, 0.2, 0)
	spawn.CFrame = CFrame.lookAt(spawn.Position, spawn.Position + Vector3.new(0.3, 0, 1))
	spawn.Color = C.Fort
	spawn.Material = Enum.Material.SmoothPlastic
	spawn.Duration = 0
	spawn.Neutral = true
	spawn.Parent = f
	-- stacked boxes for flavour
	for i, p in { Vector3.new(-19, 0, -21), Vector3.new(19, 0, -21), Vector3.new(19, 4, -21) } do
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
		Color = Color3.fromRGB(150, 220, 220),
		Material = Enum.Material.SmoothPlastic,
	})
	basin:SetAttribute("PropSlot", "Fountain")
	part({
		Name = "FountainWater",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.4, 18, 18),
		CFrame = CFrame.new(fp + Vector3.new(0, 2.3, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		Color = Color3.fromRGB(130, 210, 255),
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
	sound(root.Decor:FindFirstChild("FountainWater"), "rbxasset://sounds/impact_water.mp3", 0.35, 0.55, 60)

	-- Route fork sign post, visible from the hideout mouth
	local fork = Map.Points.Fork
	box("ForkPost", fork.X - 0.4, 0, fork.Z - 0.4, fork.X + 0.4, 17, fork.Z + 0.4, C.Metal, nil, root.Decor)
	sign("SignQuiet", CFrame.new(fork.X - 5.2, 15.2, fork.Z - 0.5), Vector2.new(10, 3), "◀  QUIET WAY", TC.Sky, nil, { Solid = true })
	sign("SignLoud", CFrame.new(fork.X + 5.2, 11.6, fork.Z - 0.5), Vector2.new(10, 3), "LOUD SHORTCUT  ▶", TC.Coral, nil, { Solid = true })
	float("FoodCourt", Vector3.new(0, 25, 54), "FOOD COURT", TC.Sun, 22, { Icon = "🍜", Height = 4.4 })

	-- Food court tables and stalls
	for _, t in { { 20, 26 }, { 28, 40 }, { -4, 52 }, { 6, 62 }, { -34, 18 }, { 34, 18 }, { -6, 104 }, { 6, 116 }, { 30, 140 }, { -18, 140 } } do
		table_(t[1], t[2], Color3.fromRGB(255, 255, 255))
	end
	stall("WokRoll", -30, -8, BLOCK_Z0 - 1, -1, Color3.fromRGB(240, 110, 110), "WOK & ROLL")
	stall("SoupBowl", 24, 44, BLOCK_Z0 - 1, -1, Color3.fromRGB(255, 160, 80), "SOUP-ER BOWL")
	stall("Pretzel", 46, 59, BLOCK_Z0 - 1, -1, Color3.fromRGB(170, 130, 230), "PRETZELS")
	stall("Smoothie", -30, -6, BLOCK_Z1 + 1, 1, Color3.fromRGB(90, 200, 150), "SMOOTHIE MOON")
	stall("Taco", 26, 56, BLOCK_Z1 + 1, 1, Color3.fromRGB(240, 110, 170), "TACO TORNADO")
	-- side-wall stores (the Arcade is through the east gate now)
	for i, s in { { 60, "PHONE CASES" }, { 124, "SOCK SHACK" }, { 148, "GAME GURU" } } do
		local z = s[1]
		local col = Color3.fromHSV((i * 0.21) % 1, 0.45, 0.95)
		box("StoreE" .. i, HALL_X - 1, 0, z - 9, HALL_X, 14, z + 9, Theme.tint(col, 0.5), nil, root.Decor).CanCollide = false
		sign("StoreSignE" .. i, CFrame.new(HALL_X - 1.4, 11, z) * CFrame.Angles(0, math.rad(90), 0), Vector2.new(16, 3), s[2], col, nil, { Solid = true }).Parent = root.Decor
	end
	-- the next wing, shuttered: a visible goal for later
	local tz = 140
	box("ToyBarnFront", -HALL_X, 0, tz - 10, -HALL_X + 1, 16, tz + 10, Color3.fromRGB(255, 226, 170), nil, root.Decor).CanCollide = false
	decor(box("ToyBarnShutter", -HALL_X + 1, 0.2, tz - 8, -HALL_X + 1.3, 12, tz + 8, Color3.fromRGB(228, 230, 238), Enum.Material.DiamondPlate, root.Decor))
	float("ToyBarn", Vector3.new(-HALL_X + 6, 17, tz), "TOY BARN", TC.Mute, 11, { Icon = "🧸", Sub = "coming soon", Height = 3 })
	-- planters
	for _, p in { Vector3.new(-10, 0, 14), Vector3.new(10, 0, 14), Vector3.new(-44, 0, 64), Vector3.new(52, 0, 96), Vector3.new(-8, 0, 96) } do
		box("Planter", p.X - 2, 0, p.Z - 2, p.X + 2, 2.5, p.Z + 2, Color3.fromRGB(255, 255, 255), nil, root.Decor)
		decor(part({
			Name = "Bush",
			Shape = Enum.PartType.Ball,
			Size = Vector3.new(4.5, 4.5, 4.5),
			Position = p + Vector3.new(0, 4, 0),
			Color = Color3.fromRGB(130, 210, 140),
			Material = Enum.Material.SmoothPlastic,
		}, root.Decor))
	end
end

local function buildQuietRoute()
	-- Pale blue carpet runner from the fork round the fountain, up the west side, through the
	-- Cozy Corner and into the north hall. Purely visual: the floor is already quiet.
	for _, r in { { -2, 20, -40, 26 }, { -60 + 4, 20, -44, 120 }, { -56, 112, -10, 120 } } do
		local x0, z0, x1, z1 = r[1], r[2], r[3], r[4]
		decor(box("QuietCarpet", math.min(x0, x1), 0, math.min(z0, z1), math.max(x0, x1), 0.06, math.max(z0, z1), C.QuietCarpet, Enum.Material.SmoothPlastic, root.Decor))
	end
	for _, z in { 40, 64 } do
		sign("QuietArrow", CFrame.new(-59.6, 6, z) * CFrame.Angles(0, math.rad(-90), 0), Vector2.new(8, 2.4), "QUIET WAY  ▲", TC.Sky, nil, { Solid = true }).Parent = root.Decor
	end

	-- Cozy Corner: the sheltered gap at the west end of the Wok Wall.
	decor(box("CozyCanopy", -HALL_X, 10, BLOCK_Z0, GAP_X1, 11, BLOCK_Z1, Color3.fromRGB(170, 200, 255), Enum.Material.SmoothPlastic, root.Decor))
	for _, z in { BLOCK_Z0 + 0.5, BLOCK_Z1 - 0.5 } do
		for x = -HALL_X + 1, GAP_X1 - 1, 3 do
			decor(box("Fringe", x - 0.6, 9, z - 0.2, x + 0.6, 10, z + 0.2, Color3.fromRGB(255, 236, 170), Enum.Material.SmoothPlastic, root.Decor))
		end
	end
	box("CozyCouch", -HALL_X, 0, BLOCK_Z0 + 3, -HALL_X + 3, 2.5, BLOCK_Z1 - 3, Color3.fromRGB(255, 180, 200), Enum.Material.SmoothPlastic, root.Decor).CanCollide = false
	for z = BLOCK_Z0 + 3, BLOCK_Z1 - 3, 4 do
		part({ Name = "Cushion", Shape = Enum.PartType.Ball, Size = Vector3.new(2.6, 2.6, 2.6), Position = Vector3.new(-HALL_X + 2, 3, z + 2), Color = Color3.fromRGB(255, 232, 170), Material = Enum.Material.SmoothPlastic, CanCollide = false, CanQuery = false }, root.Decor)
	end
	decor(box("CozyRug", -HALL_X + 3, 0, BLOCK_Z0, GAP_X1, 0.08, BLOCK_Z1, Color3.fromRGB(200, 220, 255), Enum.Material.SmoothPlastic, root.Decor))
	float("Cozy", Vector3.new(-52, 17, (BLOCK_Z0 + BLOCK_Z1) / 2), "COZY CORNER", TC.Sky, 12, { Icon = "💤", Sub = "quiet way · calms sleepers", Height = 3.2 })
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
	box("BlockUnderBridge", ESC_X0, 0, BLOCK_Z0, ESC_X1, BLOCK_H, BLOCK_Z1, C.Metal, nil, f)
	box("BlockE", ESC_X1, 0, BLOCK_Z0, HALL_X, BLOCK_H, BLOCK_Z1, C.Block, nil, f)
	-- tall parapets so the bridge is the only way over the top
	box("RoofW", GAP_X1, BLOCK_H, BLOCK_Z0, ESC_X0 - 0.5, BLOCK_H + 9, BLOCK_Z1, C.BlockTop, nil, f)
	box("RoofE", ESC_X1 + 0.5, BLOCK_H, BLOCK_Z0, HALL_X, BLOCK_H + 9, BLOCK_Z1, C.BlockTop, nil, f)
	-- vent duct interior
	local duct = box("DuctFloor", VENT_X0, 0, BLOCK_Z0, VENT_X1, 0.1, BLOCK_Z1, Color3.fromRGB(200, 210, 210), Enum.Material.DiamondPlate, f)
	duct.CanCollide = false
	for z = BLOCK_Z0 + 3, BLOCK_Z1 - 3, 6 do
		pointLight(Vector3.new((VENT_X0 + VENT_X1) / 2, VENT_H - 0.8, z), C.Vent, 10, 1, f)
	end
	local vz = zone("Vent", VENT_X0, BLOCK_Z0, VENT_X1, BLOCK_Z1)
	vz:SetAttribute("Route", "Vent")
	-- vent doors (one each side, opened together by a Crab Rangoon buddy)
	for i, zFace in { BLOCK_Z0 - 0.4, BLOCK_Z1 + 0.4 } do
		local door = box("VentDoor" .. i, VENT_X0, 0, zFace - 0.3, VENT_X1, VENT_H, zFace + 0.3, C.Vent, Enum.Material.DiamondPlate, f)
		door:SetAttribute("VentDoor", true)
		door:SetAttribute("ClosedCFrame", door.CFrame)
		for y = 1, VENT_H - 1, 1.2 do
			local slat = box("Slat", VENT_X0 + 0.3, y, zFace - 0.5, VENT_X1 - 0.3, y + 0.4, zFace + 0.5, Color3.fromRGB(90, 170, 120), Enum.Material.Metal, door)
			slat.CanCollide = false
			slat.CanQuery = false
			local w = Instance.new("WeldConstraint")
			w.Part0 = door
			w.Part1 = slat
			w.Parent = slat
			slat.Anchored = false
			slat.Massless = true
		end
		local prompt = Instance.new("ProximityPrompt")
		prompt.Name = "VentPrompt"
		prompt.ActionText = "Pry open"
		prompt.ObjectText = "Vent (needs Crab Rangoon buddy)"
		prompt.HoldDuration = 0.4
		prompt.MaxActivationDistance = 10
		prompt.RequiresLineOfSight = false
		prompt.Parent = door
	end
	float("VentS", Vector3.new((VENT_X0 + VENT_X1) / 2, 11, BLOCK_Z0 - 3), "VENT", TC.Mint, 8, { Icon = "🦀", Sub = "a Crab Rangoon buddy opens it", Height = 2.4 })
	float("VentN", Vector3.new((VENT_X0 + VENT_X1) / 2, 11, BLOCK_Z1 + 3), "VENT", TC.Mint, 8, { Icon = "🦀", Sub = "muffled way home", Height = 2.4 })
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
			Color = Color3.fromRGB(176, 180, 196),
			Material = Enum.Material.Metal,
		}, f)
		wedge:SetAttribute("Surface", "Loud")
		local low = Vector3.new(0, 0, r.up and r.z0 or r.z1)
		local high = Vector3.new(0, BLOCK_H, r.up and r.z1 or r.z0)
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
		for _, x in { ESC_X0 - 0.5, ESC_X1 + 0.5 } do
			local a = Vector3.new(x, low.Y + 3, low.Z)
			local b = Vector3.new(x, high.Y + 3, high.Z)
			local rail = slab("Rail", a, b, 1, 6, Color3.fromRGB(200, 225, 245), Enum.Material.Glass, f)
			rail.Transparency = 0.5
			local strip = slab("RattleLight", a + Vector3.new(0, 3.2, 0), b + Vector3.new(0, 3.2, 0), 1.2, 0.5, C.Loud, Enum.Material.Neon, f)
			strip.CanCollide = false
			strip:SetAttribute("RattleLight", true)
		end
		local footZ = r.up and r.z0 - 4 or r.z1 + 4
		decor(box("LoudGrate", ESC_X0 - 1, 0, footZ - 4, ESC_X1 + 1, 0.08, footZ + 4, C.Hazard, Enum.Material.DiamondPlate, f))
		zone("Loud", ESC_X0 - 1, math.min(r.z0, footZ - 4), ESC_X1 + 1, math.max(r.z1, footZ + 4), -1, BLOCK_H + 8)
		local rattle = sound(wedge, "rbxasset://sounds/action_footsteps_plastic.mp3", 0.5, 0.55, 80)
		rattle.Name = "Rattle"
	end
	local bridge = box("Bridge", ESC_X0, BLOCK_H, BLOCK_Z0, ESC_X1, BLOCK_H + 0.3, BLOCK_Z1, C.Metal, Enum.Material.DiamondPlate, f)
	bridge:SetAttribute("Surface", "Loud")
	for _, x in { ESC_X0 - 0.5, ESC_X1 + 0.5 } do
		local rail = box("BridgeRail", x - 0.5, BLOCK_H, BLOCK_Z0, x + 0.5, BLOCK_H + 6, BLOCK_Z1, Color3.fromRGB(200, 225, 245), Enum.Material.Glass, f)
		rail.Transparency = 0.5
	end
	zone("Loud", ESC_X0 - 1, BLOCK_Z0, ESC_X1 + 1, BLOCK_Z1, BLOCK_H - 1, BLOCK_H + 8)
	float("Escalator", Vector3.new(ESC_X0 - 8, 21, BLOCK_Z0 - ESC_RUN + 2), "ESCALATOR", TC.Coral, 12, { Icon = "⚠", Sub = "loud shortcut · walk or time it", Height = 3.2 })
	decor(box("LoudLane", ESC_X0 - 1, 0, 26, ESC_X1 + 1, 0.05, BLOCK_Z0 - ESC_RUN - 8, Color3.fromRGB(255, 200, 190), Enum.Material.SmoothPlastic, root.Decor))
end

-- Rare stage + beam for one wing.
local function rareStage(wing: string, p: Vector3, title: string)
	local stage = part({
		Name = "RareStage_" .. wing,
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(1, 14, 14),
		CFrame = CFrame.new(p + Vector3.new(0, 0.5, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		Color = C.Gold,
		Material = Enum.Material.Neon,
	})
	local beam = part({
		Name = "RareBeam_" .. wing,
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
	beam:SetAttribute("RareBeam", wing)
	Map.beams[wing] = beam
	stage:SetAttribute("RareStage", wing)
	float("Rare_" .. wing, p + Vector3.new(0, 14, 0), title, TC.Sun, 11, { Icon = "⭐", Sub = "rare sleepers nap here", Height = 3 })
end

local function buildNorth()
	rareStage("FoodCourt", Map.Points.RareStages.FoodCourt, "RARE STAGE")
end

----------------------------------------------------------------------------------------------
-- Arcade wing

local function cabinet(x: number, z: number, facing: number, color: Color3, parent: Instance)
	-- facing = +1: screen faces +Z
	local body = box("Cabinet", x - 1.8, 0, z - 1.5, x + 1.8, 7, z + 1.5, Theme.tint(color, 0.35), nil, parent)
	decor(box("Marquee", x - 1.8, 7, z - 1.5, x + 1.8, 8, z + 1.5, color, Enum.Material.Neon, parent))
	local screen = decor(box("Screen", x - 1.3, 3.6, z + facing * 1.5 - 0.1, x + 1.3, 6.2, z + facing * 1.5 + 0.1, Color3.fromHSV(math.random(), 0.5, 0.95), nil, parent))
	screen:SetAttribute("ArcadeScreen", true)
	decor(box("Panel", x - 1.6, 2.6, z + facing * 1.5, x + 1.6, 3.1, z + facing * 2.3, Color3.fromRGB(255, 255, 255), nil, parent))
	return body
end

local function clawMachine(x: number, z: number, color: Color3, parent: Instance)
	box("ClawBase", x - 2.5, 0, z - 2.5, x + 2.5, 3, z + 2.5, color, nil, parent)
	local glass = box("ClawGlass", x - 2.5, 3, z - 2.5, x + 2.5, 8.5, z + 2.5, Color3.fromRGB(230, 245, 255), Enum.Material.Glass, parent)
	glass.Transparency = 0.6
	decor(box("ClawTop", x - 2.6, 8.5, z - 2.6, x + 2.6, 9.3, z + 2.6, color, nil, parent))
	for i = 1, 10 do
		decor(part({
			Name = "Plushie",
			Shape = Enum.PartType.Ball,
			Size = Vector3.new(1.4, 1.4, 1.4),
			Position = Vector3.new(x + (math.random() - 0.5) * 3.6, 3.7 + math.random() * 0.8, z + (math.random() - 0.5) * 3.6),
			Color = Color3.fromHSV(math.random(), 0.4, 1),
		}, parent))
	end
end

local function buildArcade()
	local f = Instance.new("Folder")
	f.Name = "Arcade"
	f.Parent = root
	local d = Instance.new("Folder")
	d.Name = "ArcadeDecor"
	d.Parent = f

	local floor = box("ArcadeFloor", AX0 - 2, -2, AZ0, AX1, 0, AZ1, C.Arcade, nil, f)
	floor:SetAttribute("Surface", "Quiet")
	for z = AZ0 + 6, AZ1 - 6, 12 do
		for x = AX0 + 6, AX1 - 6, 12 do
			if ((x - AX0 + z) / 12) % 2 == 0 then
				decor(box("Tile", x - 6, 0, z - 6, x + 6, 0.02, z + 6, C.ArcadeTile, nil, d))
			end
		end
	end
	-- walls (the west side shares the food court's east wall; close the bit south of the hall)
	box("ArcWallS", AX0 - 2, 0, AZ0 - 2, AX1 + 2, A_WALL_H, AZ0, C.Wall, nil, f)
	box("ArcWallN", AX0 - 2, 0, AZ1, AX1 + 2, A_WALL_H, AZ1 + 2, C.Wall, nil, f)
	box("ArcWallE", AX1, 0, AZ0, AX1 + 2, A_WALL_H, AZ1, C.Wall, nil, f)
	box("ArcWallSW", HALL_X, 0, AZ0, HALL_X + 2, A_WALL_H, HALL_Z0, C.Wall, nil, f)
	roof(AX0 - 2, AX1 + 2, AZ0 - 2, AZ1 + 2, A_WALL_H)
	-- pastel trim stripes on the walls
	for _, w in { { AX0, AZ0, AX1, AZ0 + 0.3 }, { AX0, AZ1 - 0.3, AX1, AZ1 }, { AX1 - 0.3, AZ0, AX1, AZ1 } } do
		decor(box("Stripe", w[1], 8, w[2], w[3], 9, w[4], TC.Lilac, Enum.Material.Neon, d))
		decor(box("Stripe2", w[1], 10, w[2], w[3], 10.6, w[4], TC.Sky, Enum.Material.Neon, d))
	end

	-- the paid gate: glass barrier only players who unlocked the Arcade can pass
	local gate = box("ArcadeGate", HALL_X + 0.2, 0, GATE_Z0, HALL_X + 1.8, GATE_H, GATE_Z1, Theme.tint(TC.Lilac, 0.5), Enum.Material.Glass, f)
	gate.Transparency = 0.45
	gate.CollisionGroup = "Gate_Arcade"
	gate:SetAttribute("Gate", "Arcade")
	Map.Gates.Arcade = gate
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "GatePrompt"
	prompt.ActionText = "Unlock for 💰 " .. Config.Wings.Arcade.Price
	prompt.ObjectText = "Arcade"
	prompt.HoldDuration = 0.3
	prompt.MaxActivationDistance = 14
	prompt.RequiresLineOfSight = false
	prompt.Parent = gate
	for _, side in { -1, 1 } do
		decor(box("GatePost", HALL_X - 0.5 + side * 0, 0, side < 0 and GATE_Z0 - 1 or GATE_Z1, HALL_X + 2.5, GATE_H + 1, side < 0 and GATE_Z0 or GATE_Z1 + 1, TC.Lilac, Enum.Material.Neon, d))
	end
	float("ArcadeGate", Vector3.new(HALL_X - 6, 19, (GATE_Z0 + GATE_Z1) / 2), "ARCADE", TC.Lilac, 12, { Icon = "🕹", Sub = "unlock for 💰 " .. Config.Wings.Arcade.Price, Height = 3.4 })
	float("Arcade", Vector3.new(136, 18, 40), "ARCADE", TC.Lilac, 22, { Icon = "🕹", Height = 4.4 })

	-- cabinet clusters (back-to-back rows) make lanes on the south floor
	local cabColors = { TC.Rose, TC.Sky, TC.Mint, TC.Lilac, TC.Peach, TC.Sun }
	local n = 0
	for _, cl in { { 96, 120, 40 }, { 154, 178, -10 + 50 }, { 100, 124, -6 }, { 152, 176, -6 } } do
		for x = cl[1], cl[2], 4 do
			n += 1
			cabinet(x, cl[3] - 1.6, -1, cabColors[n % #cabColors + 1], d)
			cabinet(x, cl[3] + 1.6, 1, cabColors[(n + 2) % #cabColors + 1], d)
		end
	end
	clawMachine(80, 2, TC.Rose, d)
	clawMachine(80, 54, TC.Sky, d)
	clawMachine(170, 70, TC.Mint, d)

	-- Cabinet Row: the long divider, crossed at the dance floor or the ball pit
	box("RowW", AX0, 0, ROW_Z0, DANCE_X0, ROW_H, ROW_Z1, Theme.tint(TC.Lilac, 0.55), nil, f)
	box("RowE", DANCE_X1, 0, ROW_Z0, PIT_X0, ROW_H, ROW_Z1, Theme.tint(TC.Lilac, 0.55), nil, f)
	for x = AX0 + 4, PIT_X0 - 4, 6 do
		if x < DANCE_X0 - 2 or x > DANCE_X1 + 2 then
			local s = decor(box("RowScreen", x - 2, 6, ROW_Z0 - 0.15, x + 2, 9, ROW_Z0, Color3.fromHSV((x * 0.013) % 1, 0.5, 0.95), nil, d))
			s:SetAttribute("ArcadeScreen", true)
		end
	end

	-- Dance floor (loud: thumps on a beat)
	local tiles = Instance.new("Folder")
	tiles.Name = "DanceFloor"
	tiles.Parent = f
	local tz0, tz1 = 76, 116
	local i = 0
	for z = tz0, tz1 - 4, 4 do
		for x = DANCE_X0 - 2, DANCE_X1 - 2, 4 do
			i += 1
			local t = decor(box("DanceTile", x + 0.15, 0, z + 0.15, x + 3.85, 0.12, z + 3.85, Color3.fromRGB(190, 236, 214), nil, tiles))
			t:SetAttribute("DanceTile", (x // 4 + z // 4) % 2)
		end
	end
	zone("Dance", DANCE_X0 - 2, tz0, DANCE_X1 + 2, tz1)
	local thump = sound(tiles:GetChildren()[1], "rbxasset://sounds/action_jump_land.mp3", 0.6, 0.5, 90)
	thump.Name = "Thump"
	thump.Looped = false
	float("Dance", Vector3.new((DANCE_X0 + DANCE_X1) / 2, 17, 96), "DANCE FLOOR", TC.Coral, 12, { Icon = "🎵", Sub = "loud shortcut · cross on the quiet beat", Height = 3.2 })

	-- Ball pit (quiet, sheltered: drains the meter, and the Ticketoad evolution route)
	local pit = Instance.new("Folder")
	pit.Name = "BallPit"
	pit.Parent = f
	local pz0, pz1 = 82, 112
	decor(box("PitFloor", PIT_X0, 0, pz0, AX1, 0.1, pz1, Color3.fromRGB(210, 230, 255), nil, pit))
	for _, rz in { pz0, pz1 } do
		decor(box("PitRim", PIT_X0, 0, rz - 0.5, AX1, 1.4, rz + 0.5, TC.Sky, nil, pit))
	end
	local pal = { TC.Rose, TC.Sky, TC.Mint, TC.Sun, TC.Lilac, TC.Peach }
	for k = 1, 170 do
		decor(part({
			Name = "Ball",
			Shape = Enum.PartType.Ball,
			Size = Vector3.new(1.3, 1.3, 1.3),
			Position = Vector3.new(PIT_X0 + 1 + math.random() * (AX1 - PIT_X0 - 2), 0.5 + math.random() * 0.9, pz0 + 1 + math.random() * (pz1 - pz0 - 2)),
			Color = pal[k % #pal + 1],
		}, pit))
	end
	decor(box("PitCanopy", PIT_X0, 11, pz0, AX1, 11.6, pz1, Theme.tint(TC.Sky, 0.5), Enum.Material.SmoothPlastic, pit))
	local pz = zone("Shelter", PIT_X0, pz0, AX1, pz1)
	pz:SetAttribute("Route", "BallPit")
	sound(pz, "rbxasset://sounds/action_swim.mp3", 0.12, 0.45, 30)
	float("BallPit", Vector3.new((PIT_X0 + AX1) / 2, 16, 96), "BALL PIT", TC.Sky, 11, { Icon = "🔵", Sub = "quiet way · calms sleepers", Height = 3.2 })

	-- North floor: prize counter along the wall + Prize Stage
	box("PrizeCounter", 130, 0, AZ1 - 6, 200, 3.5, AZ1, Color3.new(1, 1, 1), nil, f)
	decor(box("PrizeStripe", 130, 1.2, AZ1 - 6.1, 200, 2.2, AZ1 - 5.9, TC.Sun, nil, d))
	for x = 134, 196, 5 do
		decor(part({
			Name = "Prize",
			Shape = Enum.PartType.Ball,
			Size = Vector3.new(2.2, 2.2, 2.2),
			Position = Vector3.new(x, 4.6, AZ1 - 3),
			Color = Color3.fromHSV((x * 0.03) % 1, 0.35, 1),
		}, d))
	end
	sign("PrizeSign", CFrame.new(165, 12, AZ1 - 0.3) * CFrame.Angles(0, math.pi, 0), Vector2.new(24, 4), "PRIZE COUNTER", TC.Sun, nil, { Solid = true }).Parent = d
	rareStage("Arcade", Map.Points.RareStages.Arcade, "PRIZE STAGE")
	-- soft coloured lights
	for _, p in { Vector3.new(100, 12, 20), Vector3.new(170, 12, 20), Vector3.new(137, 12, 96), Vector3.new(100, 12, 130), Vector3.new(170, 12, 120) } do
		local l = pointLight(p, Color3.fromRGB(230, 220, 255), 40, 0.5, d)
		l.Transparency = 1
	end
end

function Map.build(): Folder
	root = Instance.new("Folder")
	root.Name = "Map"
	local decorF = Instance.new("Folder")
	decorF.Name = "Decor"
	decorF.Parent = root
	zones = Instance.new("Folder")
	zones.Name = "Zones"
	zones.Parent = root
	labels = Instance.new("Folder")
	labels.Name = "Labels"
	labels.Parent = root
	Map.beams = {}
	Map.Gates = {}

	-- Gate collision groups: an unlocked player's character is put in Pass_<Wing>.
	-- Wings unlock in order, so Pass_<wing> also passes every earlier gate.
	local gated = {}
	for _, w in Config.wingList() do
		if w.Price > 0 then
			table.insert(gated, w.Id)
			PhysicsService:RegisterCollisionGroup("Gate_" .. w.Id)
			PhysicsService:RegisterCollisionGroup("Pass_" .. w.Id)
		end
	end
	for i, g in gated do
		for j = i, #gated do
			PhysicsService:CollisionGroupSetCollidable("Gate_" .. g, "Pass_" .. gated[j], false)
		end
	end

	buildShell()
	buildHideout()
	buildPlaza()
	buildQuietRoute()
	buildBlock()
	buildLoudRoute()
	buildNorth()
	buildArcade()

	Map.beam = Map.beams.FoodCourt
	root.Parent = workspace
	return root
end

-- Point-in-zone test against the Zones folder. Returns the most specific surface kind, and the
-- route tag of the zone (e.g. "Vent", "BallPit") if any.
local PRIORITY = { Shelter = 5, Vent = 4, Dance = 3, Loud = 2, Hideout = 1 }
function Map.surfaceAt(pos: Vector3): (string, string?)
	local best, bestP, route = "Quiet", 0, nil
	for _, z in zones:GetChildren() do
		local rel = z.CFrame:PointToObjectSpace(pos)
		local h = z.Size / 2
		if math.abs(rel.X) <= h.X and math.abs(rel.Y) <= h.Y and math.abs(rel.Z) <= h.Z then
			local kind = z:GetAttribute("Kind")
			local pr = PRIORITY[kind] or 0
			if pr > bestP then
				best, bestP = kind, pr
				route = z:GetAttribute("Route")
			end
		end
	end
	if best == "Hideout" then
		return "Quiet", nil
	end
	return best, route
end

function Map.wingAt(pos: Vector3): string
	return pos.X > HALL_X + 1 and "Arcade" or "FoodCourt"
end

-- Bright morning before opening: sunlight through the glass roofs, soft and airy.
function Map.setupLighting()
	local Lighting = game:GetService("Lighting")
	Lighting.ClockTime = 10.5
	Lighting.GeographicLatitude = 30
	Lighting.Brightness = 2
	Lighting.Ambient = Color3.fromRGB(140, 140, 158)
	Lighting.OutdoorAmbient = Color3.fromRGB(150, 150, 168)
	Lighting.EnvironmentDiffuseScale = 1
	Lighting.EnvironmentSpecularScale = 0.4
	Lighting.GlobalShadows = true
	Lighting.ShadowSoftness = 0.6
	for _, c in Lighting:GetChildren() do
		if c:IsA("PostEffect") or c:IsA("Atmosphere") or c:IsA("Sky") then
			c:Destroy()
		end
	end
	local cc = Instance.new("ColorCorrectionEffect")
	cc.Brightness = 0
	cc.Saturation = 0.18
	cc.Contrast = 0.12
	cc.TintColor = Color3.fromRGB(255, 252, 248)
	cc.Parent = Lighting
	local bloom = Instance.new("BloomEffect")
	bloom.Intensity = 0.25
	bloom.Size = 18
	bloom.Threshold = 2
	bloom.Parent = Lighting
	local atm = Instance.new("Atmosphere")
	atm.Density = 0.08
	atm.Offset = 0
	atm.Color = Color3.fromRGB(235, 240, 255)
	atm.Decay = Color3.fromRGB(200, 210, 240)
	atm.Glare = 0
	atm.Haze = 0.15
	atm.Parent = Lighting
end

return Map

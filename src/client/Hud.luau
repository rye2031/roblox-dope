-- Wildbound's always-on HUD: minimap, wallet, top-right menus + the Menu popover, your HP and
-- team column with the active monster's skills, attack/weapon skill/dodge, target frame,
-- reward pops, pads that open menus, the How to play card, the Top Tamers board and small
-- world animations.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Monsters = require(Shared.Monsters)
local Ui = require(script.Parent.Ui)
local Panels = require(script.Parent.Panels)
local TweenService = game:GetService("TweenService")
local Controls = require(script.Parent.Controls)
local Unlocks = require(script.Parent.Unlocks)
local UnitView = require(script.Parent.UnitView)

local T = Config.Tuning
local C = Ui.C
local EI = Config.ElementInfo
local new, corner, text, button, px = Ui.new, Ui.corner, Ui.text, Ui.button, Ui.px
local player = Players.LocalPlayer
local gui = Ui.gui

local Hud = {}

local function label(parent: Instance, props: { [string]: any }, weight: string?)
	props.TextScaled = props.TextScaled or false
	props.TextSize = props.TextSize or px(15)
	props.ZIndex = props.ZIndex or 3
	props.Parent = parent
	return text(props, weight)
end

local function bar(parent: Instance, pos: UDim2, size: UDim2, color: Color3, z: number?): (Frame, Frame)
	local back = new("Frame", { Position = pos, Size = size, BackgroundColor3 = C.Line, ZIndex = z or 3, Parent = parent }, { new("UICorner", { CornerRadius = UDim.new(0.5, 0) }) })
	local fill = new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = color, ZIndex = (z or 3) + 1, Parent = back }, { new("UICorner", { CornerRadius = UDim.new(0.5, 0) }) })
	return back, fill
end

----------------------------------------------------------------------------------------------
-- HUD layout (2026-11-27 redesign from the owner's reference shot of a mobile action RPG;
-- phone and PC share it):
--   top-left      minimap (tap: fast travel; off by default on phones, Menu > Map), Auto + Ride
--   top-centre    target card
--   top-right     wallet, then Quests, Shrine, Monsters and the ⊞ Menu (every other menu,
--                 map, sound, help)
--   right edge    your avatar + HP, the two waiting monsters, then the active monster with
--                 its two skills beside it (tap a waiting portrait to make it active)
--   bottom-left   tips and the quest tracker (Tips.luau, Journey.luau)
--   bottom-right  attack, weapon skill and dodge around Roblox's jump button
-- Everything is placed in phone points inside Ui.hud, which scales up on big screens. The
-- top-right row sits in Ui.hudTop (inside Roblox's top bar when there is room) and the right column in Ui.hudRM, which reach past the notch
-- padding on the side away from the notch (Ui.luau).

local hud = Ui.hud
local keys = not Ui.mobile and not Controls.touch -- show keyboard hints on PC
local SkillIcons = require(Shared.SkillIcons)
local Sfx = require(script.Parent.Sfx)
local WHITE = Color3.new(1, 1, 1)
local GOLD = Color3.fromRGB(255, 214, 90)
local GREY = Color3.fromRGB(120, 120, 140)

local function roundCorner(): UICorner
	return new("UICorner", { CornerRadius = UDim.new(0.5, 0) })
end

-- a small dark pill with a key name (PC only)
local function keyBadge(parent: GuiObject, k: string, pos: UDim2?): Frame?
	if not keys then
		return nil
	end
	local b = new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = pos or UDim2.new(0, 4, 0, 4), Size = UDim2.fromOffset(math.max(16, #k * 7 + 8), 15), BackgroundColor3 = Color3.fromRGB(30, 30, 44), BackgroundTransparency = 0.15, ZIndex = 9, Parent = parent }, { roundCorner() })
	label(b, { Size = UDim2.fromScale(1, 1), Text = k, TextSize = 10, TextColor3 = WHITE, TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 10 }, "Title")
	return b
end

-- white text with a dark edge, readable over the world
local function worldLabel(parent: GuiObject, props: { [string]: any })
	props.TextColor3 = props.TextColor3 or WHITE
	props.TextStrokeTransparency = 0.35
	props.TextStrokeColor3 = Color3.fromRGB(20, 20, 30)
	props.TextXAlignment = props.TextXAlignment or Enum.TextXAlignment.Center
	return label(parent, props, "Title")
end

-- a round icon button centred on `pos`: a baked icon (SkillIcons) or a glyph
local function iconButton(name: string, pos: UDim2, size: number, icon: string?, glyph: string?, bg: Color3?): (ImageButton, ImageLabel, Frame, TextLabel, UIStroke, UIScale)
	local b = new("ImageButton", { Name = name, AnchorPoint = Vector2.new(0.5, 0.5), Position = pos, Size = UDim2.fromOffset(size, size), BackgroundColor3 = bg or Color3.fromRGB(40, 40, 56), BackgroundTransparency = bg and 0 or 0.3, AutoButtonColor = false, ZIndex = 3, Parent = hud }, { roundCorner() })
	local img = new("ImageLabel", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 4, Parent = b })
	if icon then
		task.spawn(SkillIcons.apply, img, icon)
	end
	if glyph then
		label(b, { Size = UDim2.fromScale(1, 1), Text = glyph, TextSize = math.floor(size * 0.46), TextColor3 = WHITE, TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 5 }, "Title")
	end
	local ring = Ui.stroke(GREY, 2)
	ring.Parent = b
	local shade = new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromRGB(16, 16, 28), BackgroundTransparency = 0.4, Visible = false, ZIndex = 6, Parent = b }, { roundCorner() })
	local cd = worldLabel(b, { Size = UDim2.fromScale(1, 1), Text = "", TextSize = math.floor(size * 0.36), ZIndex = 7 })
	local sc = new("UIScale", { Parent = b })
	return b, img, shade, cd, ring, sc
end

----------------------------------------------------------------------------------------------
-- Wallet (top right, left of the round buttons; placed every frame by how many are showing)

local wallet = Ui.card({ Name = "Wallet", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -184, 0, 9), Size = UDim2.fromOffset(0, 30), ZIndex = 2, Shadow = false, Parent = Ui.hudTop }, 15)
new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, VerticalAlignment = Enum.VerticalAlignment.Center, Padding = UDim.new(0, 10), Parent = wallet })
Ui.pad(0, 10, 0, 10).Parent = wallet
local coinL = label(wallet, { LayoutOrder = 1, AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.new(0, 0, 1, 0), Text = "💰 0", TextSize = 14 }, "Title")
local regL = label(wallet, { LayoutOrder = 2, AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.new(0, 0, 1, 0), Text = "🥚 0", TextSize = 14 }, "Title")
local legL = label(wallet, { LayoutOrder = 3, AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.new(0, 0, 1, 0), Text = "🌟 0", TextSize = 14 }, "Title")
local eclL = label(wallet, { LayoutOrder = 4, AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.new(0, 0, 1, 0), Text = "🌑 1", TextSize = 14, Visible = false }, "Title")
wallet.AutomaticSize = Enum.AutomaticSize.X

local REGION_NAMES = { Haven = "Haven", SproutMeadow = "Sprout Meadow", EmberCanyon = "Ember Canyon", TideCoast = "Tide Coast", GaleHighlands = "Gale Highlands", TwilightVale = "Twilight Vale", TitanField = "Titan Field" }

----------------------------------------------------------------------------------------------
-- Top right: Quests, Shrine, Monsters, Menu

local function topBtn(i: number, glyph: string, name: string): TextButton
	local b = button({ Name = "Top" .. name, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -8 - (i - 1) * 44, 0, 6), Size = UDim2.fromOffset(36, 36), BackgroundColor3 = C.Card, TextColor3 = C.Ink, Text = glyph, TextScaled = false, TextSize = 17, ZIndex = 2, Parent = Ui.hudTop, Radius = 18 })
	Ui.stroke(C.Line, 1.5).Parent = b
	worldLabel(b, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 1, 1), Size = UDim2.fromOffset(60, 11), Text = name, TextSize = 9 })
	return b
end
local function dotOn(b: GuiObject, color: Color3): Frame
	return new("Frame", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 2, 0, -2), Size = UDim2.fromOffset(11, 11), BackgroundColor3 = color, Visible = false, ZIndex = 6, Parent = b }, { roundCorner() })
end
local menuB = topBtn(1, "", "Menu")
do -- a 2 x 2 grid of little squares
	for k = 0, 3 do
		new("Frame", { Position = UDim2.new(0.5, (k % 2 == 0) and -8 or 1, 0.5, (k < 2) and -8 or 1), Size = UDim2.fromOffset(7, 7), BackgroundColor3 = C.Ink, ZIndex = 3, Parent = menuB }, { new("UICorner", { CornerRadius = UDim.new(0, 2) }) })
	end
end
local monQ = topBtn(2, "🐾", "Monsters")
local shrineQ = topBtn(3, "🥚", "Shrine")
local questQ = topBtn(4, "📜", "Quests")
local menuDot, monQDot, shrineQDot, questQDot = dotOn(menuB, C.Coral), dotOn(monQ, C.Peach), dotOn(shrineQ, C.Sun), dotOn(questQ, C.Coral)
for b, name in { [monQ] = "Monsters", [shrineQ] = "Shrine", [questQ] = "Quests" } do
	b.Activated:Connect(function()
		Ui.open(Ui.isOpen(name) and nil or name)
	end)
end

----------------------------------------------------------------------------------------------
-- The ⊞ Menu: a popover grid under the top-right buttons with every other menu

local menuP, menuBody = Ui.panel("Menu", "Menu", "Everything in one place.", C.Lilac, "▦")
menuP.AnchorPoint = Vector2.new(1, 0)
menuP.Size = UDim2.fromOffset(448, 226)
for _, c in menuP:GetChildren() do
	if c:IsA("UISizeConstraint") then
		c:Destroy()
	end
end
local menuScale = new("UIScale", { Parent = menuP })
Ui.onOpen.Menu = function()
	local k = Ui.hudScale or 1
	menuScale.Scale = k
	-- just under the top-right row, wherever it sits (in the top bar or below it)
	menuP.Position = UDim2.new(1, Ui.edge - 8 * k, 0, math.max(6, 52 - Ui.topLift) * k)
end
local grid = new("Frame", { LayoutOrder = 1, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, ZIndex = 12, Parent = menuBody }, {
	new("UIGridLayout", { CellSize = UDim2.fromOffset(60, 60), CellPadding = UDim2.fromOffset(8, 8), SortOrder = Enum.SortOrder.LayoutOrder }),
})
local function tile(order: number, glyph: string, name: string, color: Color3): TextButton
	local b = button({ Name = name, LayoutOrder = order, BackgroundColor3 = C.Card, Text = "", ZIndex = 13, Parent = grid, Radius = 16 })
	Ui.stroke(Ui.Theme.tint(color, 0.4), 2).Parent = b
	label(b, { Name = "Glyph", Position = UDim2.fromOffset(0, 5), Size = UDim2.new(1, 0, 0, 28), Text = glyph, TextSize = 22, TextColor3 = color, TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 14 }, "Title")
	label(b, { Position = UDim2.new(0, 0, 1, -20), Size = UDim2.new(1, 0, 0, 14), Text = name, TextSize = 11, TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 14 }, "Title")
	return b
end

local RAIL = {
	{ "Monsters", "🐾", C.Lilac },
	{ "Shrine", "🥚", C.Sun },
	{ "Index", "📖", C.Mint },
	{ "Quests", "✓", C.Sky },
	{ "Weapons", "⚔", C.Peach },
	{ "Expeditions", "🧭", C.Sun },
	{ "Runes", "💠", C.Sky },
	{ "Pass", "🎖", C.Sun },
}
local questDot: Frame
local monDot: Frame -- overflow waiting
local expDot: Frame -- an expedition is back
local shrineDot: Frame -- a sealed scroll is ready
local passDot: Frame -- a Tamer Pass reward is ready
local lastCoins: number? = nil
local railButtons: { [string]: TextButton } = {}
local newBadges: { [string]: Frame } = {}
local tileDots: { Frame } = {}
for i, r in RAIL do
	local b = tile(i, r[2], r[1], r[3])
	railButtons[r[1]] = b
	b.Visible = r[1] == "Monsters" or r[1] == "Shrine"
	newBadges[r[1]] = new("Frame", { Name = "New", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(1, -4, 0, 5), Size = UDim2.fromOffset(34, 15), BackgroundColor3 = C.Coral, Visible = false, ZIndex = 16, Parent = b }, {
		roundCorner(),
		Ui.text({ Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, TextScaled = false, TextSize = 9, TextColor3 = WHITE, Text = "NEW!", ZIndex = 17 }, "Title"),
	})
	b.Activated:Connect(function()
		if newBadges[r[1]].Visible then
			newBadges[r[1]].Visible = false
			task.spawn(Ui.call, "Tutorial", "unl_" .. r[1])
		end
		Ui.open(Ui.isOpen(r[1]) and nil or r[1])
	end)
	local dotColor = ({ Shrine = C.Sun, Pass = C.Coral, Expeditions = C.Mint, Monsters = C.Peach, Quests = C.Coral })[r[1]]
	if dotColor then
		local d = new("Frame", { AnchorPoint = Vector2.new(0, 0), Position = UDim2.new(0, -2, 0, -2), Size = UDim2.fromOffset(12, 12), BackgroundColor3 = dotColor, Visible = false, ZIndex = 16, Parent = b }, { roundCorner() })
		table.insert(tileDots, d)
		if r[1] == "Shrine" then
			shrineDot = d
		elseif r[1] == "Pass" then
			passDot = d
		elseif r[1] == "Expeditions" then
			expDot = d
		elseif r[1] == "Monsters" then
			monDot = d
		else
			questDot = d
		end
	end
end
local travelT = tile(50, "🔥", "Travel", C.Peach)
travelT.Activated:Connect(function()
	Ui.open("Travel")
end)
local muteB = tile(60, "🔊", "Sound", C.Sky)
muteB.Visible = Sfx.enabled
muteB.Activated:Connect(function()
	Sfx.setMuted(not Sfx.isMuted())
	local g = muteB:FindFirstChild("Glyph") :: TextLabel
	g.Text = Sfx.isMuted() and "🔇" or "🔊"
end)
local mapT = tile(65, "🗺", "Map", C.Mint)
local help = tile(70, "?", "Help", C.Mint)
menuB.Activated:Connect(function()
	Ui.open(Ui.isOpen("Menu") and nil or "Menu")
end)

----------------------------------------------------------------------------------------------
-- Minimap (top left): heading-up radar of what's around you. Tap it to fast travel.

local MAP_W, MAP_H, MAP_R = 112, 84, 110 -- size in points; studs from centre to the top edge
local mini = Ui.card({ Name = "Minimap", Position = UDim2.fromOffset(8, 6), Size = UDim2.fromOffset(MAP_W, MAP_H), BackgroundColor3 = Color3.fromRGB(28, 36, 48), BackgroundTransparency = 0.22, ClipsDescendants = true, ZIndex = 2, Shadow = false, Parent = hud }, 12)
new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(MAP_H * 0.9, MAP_H * 0.9), BackgroundTransparency = 1, ZIndex = 3, Parent = mini }, { roundCorner(), new("UIStroke", { Color = WHITE, Transparency = 0.82, Thickness = 1 }) })
local miniName = worldLabel(mini, { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -2), Size = UDim2.new(1, -8, 0, 12), Text = "", TextSize = 9, ZIndex = 6 })
worldLabel(mini, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(14, 14), Text = "▲", TextSize = 11, TextColor3 = GOLD, ZIndex = 7 })
local miniBtn = new("TextButton", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Text = "", ZIndex = 8, Parent = mini })
miniBtn.Activated:Connect(function()
	if Ui.profile and Unlocks.open(Ui.profile, "Travel") then
		Ui.open("Travel")
	else
		Ui.toast("Light 2 campfires to fast travel between them 🔥", "info")
	end
end)
-- shown or hidden from Menu > Map; phones start without it (small screen), PCs with it.
-- The left column (Auto, then Ride from Pace.luau) moves up into its place when it's off:
-- Ui.hud's "LeftTop" attribute is where that column starts.
local mapOn = not Ui.mobile
local mapGlyph = mapT:FindFirstChild("Glyph") :: TextLabel
local mapName: TextLabel? = nil
for _, c in mapT:GetChildren() do
	if c:IsA("TextLabel") and c ~= mapGlyph then
		mapName = c
	end
end
local function setMap(on: boolean)
	mapOn = on
	mini.Visible = on
	mapGlyph.TextTransparency = on and 0 or 0.55
	if mapName then
		mapName.Text = on and "Map: on" or "Map: off"
	end
	hud:SetAttribute("LeftTop", on and 98 or 6)
end
mapT.Activated:Connect(function()
	setMap(not mapOn)
	Sfx.play("select")
end)
local miniDots: { Frame } = {}
local function miniDot(i: number): Frame
	local d = miniDots[i]
	if not d then
		d = new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), BackgroundColor3 = WHITE, ZIndex = 4, Parent = mini }, { roundCorner() })
		miniDots[i] = d
	end
	d.Visible = true
	return d
end
local campfires: { BasePart } = {}
local portals: { BasePart } = {}
task.spawn(function()
	task.wait(3)
	for _, d in workspace:GetDescendants() do
		if d:IsA("BasePart") then
			if d:GetAttribute("Campfire") then
				table.insert(campfires, d)
			elseif d.Name == "PortalDisc" then
				table.insert(portals, d)
			end
		end
	end
end)
local function drawMinimap()
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not hrp then
		return
	end
	local cam = workspace.CurrentCamera
	local r = cam.CFrame.RightVector
	local f = cam.CFrame.LookVector
	local right = Vector3.new(r.X, 0, r.Z).Unit
	local fwd = Vector3.new(f.X, 0, f.Z).Unit
	local k = (MAP_H / 2) / MAP_R
	local n = 0
	local function put(pos: Vector3, color: Color3, size: number, clampEdge: boolean?)
		local d = pos - hrp.Position
		local x, y = d:Dot(right) * k, -d:Dot(fwd) * k
		local hw, hh = MAP_W / 2 - 4, MAP_H / 2 - 4
		if math.abs(x) > hw or math.abs(y) > hh then
			if not clampEdge then
				return
			end
			local s = math.min(hw / math.max(math.abs(x), 1e-3), hh / math.max(math.abs(y), 1e-3))
			x, y = x * s, y * s
		end
		n += 1
		local dot = miniDot(n)
		dot.Position = UDim2.new(0.5, x, 0.5, y)
		dot.Size = UDim2.fromOffset(size, size)
		dot.BackgroundColor3 = color
	end
	for _, c in campfires do
		put(c.Position, Color3.fromRGB(255, 150, 60), 6)
	end
	for _, p in portals do
		put(p.Position, Color3.fromRGB(190, 130, 255), 6)
	end
	local units = workspace:FindFirstChild("Units")
	for _, u in units and units:GetChildren() or {} do
		if u:IsA("BasePart") and u:GetAttribute("State") ~= "dead" then
			if u:GetAttribute("Owner") == player.UserId then
				put(u.Position, C.Mint, 4)
			elseif u:GetAttribute("Side") == "wild" then
				local big = u:GetAttribute("Boss") or u:GetAttribute("Legend")
				put(u.Position, big and Color3.fromRGB(200, 120, 255) or u:GetAttribute("Elite") and GOLD or Color3.fromRGB(255, 96, 86), big and 7 or 4)
			end
		end
	end
	local marker = workspace:FindFirstChild("JourneyMarker") :: BasePart?
	local bb = marker and marker:FindFirstChildOfClass("BillboardGui")
	if marker and bb and bb.Enabled then
		put(marker.Position, Color3.fromRGB(120, 240, 150), 8, true)
	end
	for i = n + 1, #miniDots do
		miniDots[i].Visible = false
	end
	miniName.Text = REGION_NAMES[player:GetAttribute("Region") or ""] or ""
end

----------------------------------------------------------------------------------------------
-- Auto-Hunt (left column, under the minimap; Ride sits under it, from Pace.luau)

local AutoHunt = require(script.Parent.AutoHunt)
local autoB = button({ Name = "Auto", Position = UDim2.fromOffset(8, 98), Size = UDim2.fromOffset(36, 36), BackgroundColor3 = C.Card, TextColor3 = C.Ink, Text = "🤖", TextScaled = false, TextSize = 18, ZIndex = 3, Parent = hud, Radius = 18 })
Ui.stroke(C.Line, 1.5).Parent = autoB
local autoL = worldLabel(autoB, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 1, 1), Size = UDim2.fromOffset(60, 11), Text = "Auto", TextSize = 9 })
keyBadge(autoB, "R", UDim2.new(1, -2, 0, 2))
autoB.Activated:Connect(function()
	AutoHunt.toggle()
end)
local function paintAuto(state: boolean)
	autoB.BackgroundColor3 = state and C.Mint or C.Card
	autoL.Text = state and "Auto ON" or "Auto"
end
AutoHunt.onChanged(paintAuto)
setMap(mapOn)
local function placeLeft()
	autoB.Position = UDim2.fromOffset(8, hud:GetAttribute("LeftTop") or 98)
end
hud:GetAttributeChangedSignal("LeftTop"):Connect(placeLeft)
placeLeft()
Ui.onProfile(function(p)
	local open = p.kills >= 1 or (p.bosses and p.bosses[Config.AutoHunt.UnlockBoss])
	autoB.Visible = Unlocks.open(p, "Auto")
	if not open then
		autoL.Text = "🔒 Auto"
	elseif not AutoHunt.isOn() then
		paintAuto(false)
	end
end)

----------------------------------------------------------------------------------------------
-- Right edge: you, the team, and the active monster's skills

local function teamUnit(slot: number): BasePart?
	local units = workspace:FindFirstChild("Units")
	if not units then
		return nil
	end
	for _, u in units:GetChildren() do
		if u:GetAttribute("Owner") == player.UserId and u:GetAttribute("Slot") == slot then
			return u :: BasePart
		end
	end
	return nil
end

-- you: avatar headshot + HP
local meAv = new("ImageLabel", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -8, 0, 58), Size = UDim2.fromOffset(34, 34), BackgroundColor3 = C.Card, ZIndex = 3, Parent = Ui.hudRM }, { roundCorner() })
local meRing = Ui.stroke(WHITE, 2)
meRing.Parent = meAv
task.spawn(function()
	local ok, img = pcall(function()
		return Players:GetUserThumbnailAsync(player.UserId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size100x100)
	end)
	if ok then
		meAv.Image = img
	end
end)
local hpLabel = worldLabel(Ui.hudRM, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -48, 0, 60), Size = UDim2.fromOffset(110, 12), Text = "", TextSize = 10, TextXAlignment = Enum.TextXAlignment.Right })
local hpBack, hpFill = bar(Ui.hudRM, UDim2.new(1, -158, 0, 75), UDim2.fromOffset(110, 8), C.Mint)
hpBack.BackgroundColor3 = Color3.fromRGB(40, 40, 56)

-- three portrait spots: two waiting (small), the active one at the bottom (big). Each team
-- slot keeps its own bubble; switching glides the bubbles to their new spots (the new active
-- one grows into the gold-ringed spot), so you can see who moved where.
type Spot = { b: ImageButton, ring: UIStroke, hp: Frame, faint: TextLabel, auto: TextLabel, portrait: Frame?, key: string?, slot: number?, at: number? }
local SPOTS = { { y = 98, size = 34 }, { y = 142, size = 34 }, { y = 186, size = 44 } }
local spots: { Spot } = {} -- by team slot
for slot = 1, 3 do
	local s = SPOTS[slot]
	local b = new("ImageButton", { Name = "Party" .. slot, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(1, -8 - s.size / 2, 0, s.y + s.size / 2), Size = UDim2.fromOffset(s.size, s.size), BackgroundColor3 = C.Card, AutoButtonColor = false, Visible = false, ZIndex = 3, Parent = Ui.hudRM }, { roundCorner() })
	local ring = Ui.stroke(GREY, 2)
	ring.Parent = b
	local back = new("Frame", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 1, 2), Size = UDim2.new(1, -4, 0, 4), BackgroundColor3 = Color3.fromRGB(40, 40, 56), ZIndex = 3, Parent = b }, { roundCorner() })
	local hp = new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = C.Mint, ZIndex = 4, Parent = back }, { roundCorner() })
	local faint = worldLabel(b, { Size = UDim2.fromScale(1, 1), Text = "💤", TextSize = 16, Visible = false, ZIndex = 8 })
	local auto = worldLabel(b, { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(0, -3, 0.5, 0), Size = UDim2.fromOffset(30, 10), Text = "AUTO", TextSize = 8, TextColor3 = Color3.fromRGB(210, 220, 235), TextXAlignment = Enum.TextXAlignment.Right })
	spots[slot] = { b = b, ring = ring, hp = hp, faint = faint, auto = auto }
	b.Activated:Connect(function()
		local sp = spots[slot]
		if not sp.slot then
			return
		end
		if slot == (player:GetAttribute("ActiveSlot") or 1) then
			local uid = Ui.profile and Ui.profile.team[slot]
			if uid and uid ~= "" then
				Panels.showMonster(uid)
			end
		else
			Controls.setActive(slot)
			Sfx.play("select")
		end
	end)
end
local xBadge = keyBadge(spots[1].b, "X", UDim2.new(0, 0, 0, 0))
-- move a bubble to spot `at` (1-2 waiting, 3 active), gliding unless it's the first placement
local function moveSpot(sp: Spot, at: number)
	if sp.at == at then
		return
	end
	local s = SPOTS[at]
	local goal = { Position = UDim2.new(1, -8 - s.size / 2, 0, s.y + s.size / 2), Size = UDim2.fromOffset(s.size, s.size) }
	if sp.at == nil then
		sp.b.Position, sp.b.Size = goal.Position, goal.Size
		sp.ring.Thickness = at == 3 and 3 or 2
	else
		local promoted = at == 3
		TweenService:Create(sp.b, TweenInfo.new(promoted and 0.42 or 0.32, promoted and Enum.EasingStyle.Back or Enum.EasingStyle.Quad, Enum.EasingDirection.Out), goal):Play()
		if promoted then
			-- a gold flash as it lands in the active spot
			sp.ring.Thickness = 6
			TweenService:Create(sp.ring, TweenInfo.new(0.5, Enum.EasingStyle.Quad), { Thickness = 3 }):Play()
		end
	end
	sp.at = at
	sp.b.ZIndex = at == 3 and 5 or 3
end

-- the active monster's two skills, left of its portrait
type SkillBtn = { b: ImageButton, img: ImageLabel, shade: Frame, cd: TextLabel, ring: UIStroke, sc: UIScale, name: string? }
local skillBtns: { [number]: SkillBtn } = {}
for i, x in { [2] = -128, [3] = -78 } do
	local b, img, shade, cd, ring, sc = iconButton("Skill" .. (i - 1), UDim2.new(1, x, 0, 208), 46)
	b.Parent = Ui.hudRM
	skillBtns[i] = { b = b, img = img, shade = shade, cd = cd, ring = ring, sc = sc }
	keyBadge(b, tostring(i - 1), UDim2.new(0, 4, 0, 4))
	b.Activated:Connect(function()
		Controls.skillOf(i)
	end)
end
local skillName = worldLabel(Ui.hudRM, { AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -56, 0, 184), Size = UDim2.fromOffset(150, 11), Text = "", TextSize = 9, TextXAlignment = Enum.TextXAlignment.Right })

local function renderTeam(p)
	local active = player:GetAttribute("ActiveSlot") or 1
	local at = {}
	local n = 0
	for slot = 1, 3 do
		if slot ~= active then
			n += 1
			at[slot] = n
		end
	end
	at[active] = 3
	for slot, sp in spots do
		local uid = p.team[slot]
		local m = uid and uid ~= "" and p.monsters[uid] or nil
		sp.slot = m and slot or nil
		sp.b.Visible = m ~= nil
		moveSpot(sp, at[slot])
		sp.auto.Visible = at[slot] ~= 3
		if xBadge and at[slot] == 1 then
			xBadge.Parent = sp.b
		end
		local key = m and (uid .. ":" .. m.el) or nil
		if key ~= sp.key then
			if sp.portrait then
				sp.portrait:Destroy()
				sp.portrait = nil
			end
			if m then
				local back = Ui.portrait(sp.b, m.sp, m.el, UDim2.fromScale(1, 1), UDim2.new(), 4)
				local cr = back:FindFirstChildOfClass("UICorner")
				if cr then
					cr.CornerRadius = UDim.new(0.5, 0)
				end
				sp.portrait = back
			end
			sp.key = key
		end
		if m then
			sp.ring.Color = at[slot] == 3 and GOLD or EI[m.el].Color
			if at[slot] ~= 3 then
				sp.ring.Thickness = 2
			end
		end
	end
	-- skill icons for the active monster
	local uid = p.team[active]
	local m = uid and uid ~= "" and p.monsters[uid] or nil
	for i, s in skillBtns do
		s.b.Visible = m ~= nil
		if m then
			local skill = Monsters.skills(m.sp, m.el)[i]
			if s.name ~= skill.Name then
				s.name = skill.Name
				task.spawn(SkillIcons.apply, s.img, skill.Name)
			end
		end
	end
	skillName.Text = m and Monsters.Species[m.sp].Name or ""
end
player:GetAttributeChangedSignal("ActiveSlot"):Connect(function()
	if Ui.profile then
		renderTeam(Ui.profile)
	end
end)

----------------------------------------------------------------------------------------------
-- Target frame (top centre)

local targetCard = Ui.card({ AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 6), Size = UDim2.fromOffset(230, 38), Visible = false, ZIndex = 2, Parent = hud }, 12)
local tName = label(targetCard, { Position = UDim2.fromOffset(10, 3), Size = UDim2.new(1, -20, 0, 15), Text = "", TextSize = 12, TextXAlignment = Enum.TextXAlignment.Left }, "Title")
local tFx = label(targetCard, { Position = UDim2.fromOffset(10, 3), Size = UDim2.new(1, -20, 0, 15), Text = "", TextSize = 10, TextColor3 = C.Sub, TextXAlignment = Enum.TextXAlignment.Right, Visible = not Ui.mobile }, "Bold")
local _, tHp = bar(targetCard, UDim2.fromOffset(10, 21), UDim2.new(1, -20, 0, 10), C.Coral)
local tHpText = label(targetCard, { Position = UDim2.fromOffset(10, 19), Size = UDim2.new(1, -20, 0, 14), Text = "", TextSize = 9, TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 6 }, "Title")

----------------------------------------------------------------------------------------------
-- Bottom right: attack, weapon skill, dodge (Roblox's jump button sits right of attack)

-- (no jump button without touch controls: the cluster moves into that corner)
local jx = (Controls.touch or Ui.mobile) and 0 or 70
local atkB, atkImg = iconButton("Attack", UDim2.new(1, -160 + jx, 1, -58), 74, "Blade", nil, C.Coral)
local skillB, skillImg, skillShade, skillCd = iconButton("WeaponSkill", UDim2.new(1, -248 + jx, 1, -46), 50, "Spin Slash")
local dodgeB, _, dodgeShade = iconButton("Dodge", UDim2.new(1, -240 + jx, 1, -118), 44, "Dodge")
keyBadge(atkB, "Click", UDim2.new(0.5, 0, 0, 2))
keyBadge(skillB, "Q", UDim2.new(0, 4, 0, 4))
keyBadge(dodgeB, "Shift", UDim2.new(0.5, 0, 0, 0))
do
	local holding = false
	atkB.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
			holding = true
			Controls.attack()
		end
	end)
	atkB.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
			holding = false
		end
	end)
	RunService.Heartbeat:Connect(function()
		if holding then
			Controls.attack()
		end
	end)
end
skillB.Activated:Connect(function()
	Controls.skill()
end)
dodgeB.Activated:Connect(Controls.dodge)
local shownWeapon = ""
-- the gold ground ring under the active monster: an invisible anchor part carrying a
-- cylinder adornment with an inner radius (a real ring, no texture needed)
local activeRing = new("Part", { Name = "ActiveRing", Anchored = true, CanCollide = false, CanQuery = false, CanTouch = false, CastShadow = false, Transparency = 1, Size = Vector3.new(1, 1, 1) })
local ringAd = new("CylinderHandleAdornment", { Adornee = activeRing, Height = 0.15, Radius = 3, InnerRadius = 2.5, Color3 = Color3.fromRGB(255, 210, 80), CFrame = CFrame.Angles(math.rad(90), 0, 0), ZIndex = 0, Parent = activeRing })

----------------------------------------------------------------------------------------------
-- How to play

local howTo = Ui.card({ AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(px(520), px(430)), Visible = false, ZIndex = 30, Parent = gui }, 24)
do
	label(howTo, { Position = UDim2.fromOffset(24, 20), Size = UDim2.new(1, -48, 0, px(30)), Text = "Welcome to " .. Config.GameName .. "!", TextSize = px(26), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 31 }, "Title")
	local steps = {
		{ "🐾", "Your team", "Up to 3 monsters follow you and fight on their own. Manage them in Monsters." },
		{ "⚔", "Fight", Ui.mobile and "Tap the big button to attack. Your active monster's skills glow gold when ready: tap them. Tap another monster on the right to switch." or "Click to attack (hold to keep swinging). Q: weapon skill. Shift: dodge. 1, 2: your active monster's skills. X: switch monster." },
		{ "🌱", "Explore", "Walk through the portal in the north arch to Sprout Meadow. Wild monsters give XP, coins, Crystals and sometimes eggs. Team up with others on big ones!" },
		{ "🥚", "Befriend", "Hatch eggs at the Summoning Shrine to get new monsters. Use extras to train your team." },
		{ "🔥", "Campfires", "Touch a campfire to heal your team and set your respawn point." },
	}
	for i, s in steps do
		local y = px(62) + (i - 1) * px(62)
		Ui.dot(howTo, C.Soft, s[1], px(44), UDim2.fromOffset(24, y + px(22)), Vector2.new(0, 0.5)).ZIndex = 31
		label(howTo, { Position = UDim2.fromOffset(24 + px(56), y), Size = UDim2.new(1, -px(56) - 48, 0, px(18)), Text = s[2], TextSize = px(17), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 31 }, "Title")
		label(howTo, { Position = UDim2.fromOffset(24 + px(56), y + px(19)), Size = UDim2.new(1, -px(56) - 48, 0, px(36)), Text = s[3], TextSize = px(14), TextColor3 = C.Sub, TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top, ZIndex = 31 }, "Bold")
	end
	local go = button({ AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -18), Size = UDim2.fromOffset(px(200), px(46)), BackgroundColor3 = C.Mint, Text = "Let's go!", TextScaled = false, TextSize = px(18), ZIndex = 31, Parent = howTo, Radius = 23 })
	go.Activated:Connect(function()
		howTo.Visible = false
		local p = Ui.profile
		if p and not p.tutorial.intro then
			Ui.call("Tutorial", "intro")
		end
	end)
end
Ui.beforeOpen = function()
	howTo.Visible = false
end
help.Activated:Connect(function()
	howTo.Visible = not howTo.Visible
end)

----------------------------------------------------------------------------------------------
-- Pads: stepping on one opens its menu

local PAD_PANEL = { Storage = "Monsters", Shrine = "Shrine", Smith = "Weapons", Quests = "Quests", Expeditions = "Expeditions", Arena = "Arena", Dungeons = "Dungeons" }
local pads: { BasePart } = {}
local onPad: string? = nil

local function scanPads()
	pads = {}
	for _, d in workspace:GetDescendants() do
		if d:IsA("BasePart") and d:GetAttribute("Pad") then
			table.insert(pads, d)
		end
	end
end

----------------------------------------------------------------------------------------------
-- Rewards

local function onReward(drops, ups)
	if typeof(drops) ~= "table" then
		return
	end
	if drops.pos then
		require(script.Parent.Wins).coins(drops.pos + Vector3.new(0, 3, 0), drops.coins or 0)
		UnitView.popText(drops.pos + Vector3.new(0, 4, 0), "+" .. drops.coins .. " 💰", C.Sun)
		task.delay(0.15, function()
			UnitView.popText(drops.pos + Vector3.new(0, 5.5, 0), "+" .. Ui.fmt(drops.xp) .. " XP", C.Sky)
		end)
		if drops.essence then
			task.delay(0.3, function()
				UnitView.popText(drops.pos + Vector3.new(0, 7, 0), "+" .. drops.essence .. " " .. EI[drops.el].Icon .. " Crystals", EI[drops.el].Color)
			end)
		end
	end
	if drops.legendary then
		Ui.toast("A Legendary Egg dropped! 🌟", "good")
	elseif drops.sealed and Config.Sealed.Tiers[drops.sealed] then
		Ui.toast(string.format("🧺 A %s dropped! Warm it at the Shrine", Config.Sealed.Tiers[drops.sealed].Name), "good")
	elseif drops.scroll then
		Ui.toast("A Regular Egg dropped! Hatch it at the Shrine 🥚", "good")
	end
	if drops.rune then
		require(script.Parent.RunesUi).dropped(drops.rune)
		require(script.Parent.Tips).show("rune")
	end
	if typeof(drops.gear) == "table" then
		Ui.toast(string.format("⚔ You found %s (%s %s)! Equip it at the Smithy", drops.gear.n, drops.gear.r, drops.gear.t), "good")
		require(script.Parent.Tips).show("gear")
	end
	local p = Ui.profile
	for _, uid in ups or {} do
		local m = p and p.monsters[uid]
		if m then
			Ui.toast(Monsters.Species[m.sp].Name .. " reached level " .. m.lv .. "!", "good")
		end
	end
end

----------------------------------------------------------------------------------------------
-- Top Tamers board

local function drawBoard(json: string)
	local board
	for _, d in workspace:GetDescendants() do
		if d:IsA("BasePart") and d:GetAttribute("LeaderBoard") then
			board = d
			break
		end
	end
	if not board then
		return
	end
	local ok, data = pcall(HttpService.JSONDecode, HttpService, json)
	if not ok or typeof(data) ~= "table" then
		return
	end
	local sg = board:FindFirstChild("BoardGui") :: SurfaceGui?
	if sg then
		sg:Destroy()
	end
	sg = new("SurfaceGui", { Name = "BoardGui", Face = Enum.NormalId.Front, CanvasSize = Vector2.new(700, 400), LightInfluence = 0, Parent = board }) :: SurfaceGui
	new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromRGB(250, 248, 255), Parent = sg })
	local TITLES = { Index = "📖 Most found", Defeated = "⚔ Most defeated", Arena = "🏟 Arena rating" }
	for col, key in { "Index", "Defeated", "Arena" } do
		local f = new("Frame", { Position = UDim2.new((col - 1) / 3, 10, 0, 14), Size = UDim2.new(1 / 3, -20, 1, -28), BackgroundColor3 = C.Card, Parent = sg }, { corner(16) })
		text({ Size = UDim2.new(1, 0, 0, 40), Text = TITLES[key], TextColor3 = C.Ink, Parent = f }, "Title")
		for i, e in (data[key] or {}) do
			if i > 8 then
				break
			end
			text({ Position = UDim2.new(0, 14, 0, 40 + (i - 1) * 40), Size = UDim2.new(1, -28, 0, 34), TextXAlignment = Enum.TextXAlignment.Left, Text = string.format("%d. %s", i, tostring(e.n or e.id)), TextColor3 = C.Ink, Parent = f }, "Bold")
			text({ Position = UDim2.new(0, 14, 0, 40 + (i - 1) * 40), Size = UDim2.new(1, -28, 0, 34), TextXAlignment = Enum.TextXAlignment.Right, Text = Ui.fmt(e.v or 0), TextColor3 = C.Sub, Parent = f }, "Title")
		end
		if #(data[key] or {}) == 0 then
			text({ Position = UDim2.fromOffset(14, 60), Size = UDim2.new(1, -28, 0, 30), Text = "No scores yet", TextColor3 = C.Sub, Parent = f }, "Bold")
		end
	end
end

----------------------------------------------------------------------------------------------

function Hud.setProfile(p)
	coinL.Text = "💰 " .. Ui.fmt(p.coins)
	if lastCoins and p.coins > lastCoins then
		-- the wallet hops when coins land
		local sc = coinL:FindFirstChild("Hop") :: UIScale? or Ui.new("UIScale", { Name = "Hop", Parent = coinL })
		sc.Scale = 1.25
		game:GetService("TweenService"):Create(sc, TweenInfo.new(0.35, Enum.EasingStyle.Back), { Scale = 1 }):Play()
	end
	lastCoins = p.coins
	regL.Text = "🥚 " .. (p.scrolls.Regular or 0)
	legL.Text = "🌟 " .. (p.scrolls.Legendary or 0)
	eclL.Visible = (p.scrolls.Eclipse or 0) > 0
	renderTeam(p)
	local claimable = false
	for _, q in p.daily.quests do
		if q.p >= q.n and not q.c then
			claimable = true
		end
	end
	local _, ready = Config.streakPreview(p, Config.today())
	questDot.Visible = claimable or ready
	monDot.Visible = next(p.overflow or {}) ~= nil
	local back = false
	for _, x in p.expeditions or {} do
		local d = Config.Loops.Expeditions.Durations[x.dur]
		if d and os.time() >= x.start + d.Minutes * 60 then
			back = true
		end
	end
	expDot.Visible = back
	local sealReady = false
	for _, sl in (p.sealed and p.sealed.slots) or {} do
		local t = Config.Sealed.Tiers[sl.tier]
		if t and os.time() >= sl.start + t.Minutes * 60 then
			sealReady = true
		end
	end
	shrineDot.Visible = sealReady
	-- menus appear as they unlock (NEW! badge until opened once)
	for name, b in railButtons do
		local open = Unlocks.open(p, name)
		if open and not b.Visible then
			b.Visible = true
			-- long-time players see everything without a badge storm
			local fresh = not (p.tutorial and p.tutorial["unl_" .. name]) and not Unlocks.veteran(p)
			if fresh and Unlocks.message(name) and Ui.profileLoadedOnce then
				newBadges[name].Visible = true
				Ui.toast("✨ New: " .. Unlocks.message(name), "good")
				local sc = new("UIScale", { Scale = 1.4, Parent = b })
				game:GetService("TweenService"):Create(sc, TweenInfo.new(0.5, Enum.EasingStyle.Back), { Scale = 1 }):Play()
				task.delay(0.6, function()
					sc:Destroy()
				end)
			elseif fresh and Unlocks.message(name) then
				newBadges[name].Visible = true
			end
		elseif not open then
			b.Visible = false
		end
	end
	Ui.profileLoadedOnce = true
	passDot.Visible = require(script.Parent.PassUi).ready(p) > 0
	if not p.tutorial.intro and not Hud.introShown and not player:GetAttribute("InIntro") and not p.tutorial.dream and (p.opened or 0) > 0 then
		Hud.introShown = true
		howTo.Visible = true
	end
end

function Hud.start()
	Ui.onProfile(Hud.setProfile)
	task.spawn(function()
		task.wait(2)
		scanPads()
	end)

	Controls.onTarget = function(part)
		targetCard.Visible = part ~= nil
	end

	local spinners: { BasePart } = {}
	task.spawn(function()
		task.wait(2)
		for _, d in workspace:GetDescendants() do
			if d:IsA("BasePart") and (d:GetAttribute("Spin") or d:GetAttribute("MillHub")) then
				table.insert(spinners, d)
			end
		end
	end)
	local bases: { [BasePart]: CFrame } = {}
	local lastMini = 0

	local lastRowW = -1
	RunService.RenderStepped:Connect(function(dt)
		local t = os.clock()
		-- player HP
		local char = player.Character
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		if hum then
			hpFill.Size = UDim2.fromScale(math.clamp(hum.Health / math.max(hum.MaxHealth, 1), 0, 1), 1)
			hpLabel.Text = string.format("%d / %d", math.max(0, math.floor(hum.Health)), hum.MaxHealth)
		end
		-- weapon: attack icon, weapon skill cooldown, dodge
		local kind = player:GetAttribute("Weapon") or "Blade"
		local w = T.Weapons[kind]
		if kind ~= shownWeapon and w then
			shownWeapon = kind
			task.spawn(SkillIcons.apply, atkImg, kind)
			task.spawn(SkillIcons.apply, skillImg, w.Skill.Name)
		end
		local nowS = workspace:GetServerTimeNow()
		local left = (player:GetAttribute("WeaponSkillReady") or 0) - nowS
		skillShade.Visible = left > 0
		skillCd.Text = left > 0 and tostring(math.ceil(left)) or ""
		dodgeShade.Visible = Controls.dodgeReady - os.clock() > 0
		-- the team: HP, fainted
		for _, sp in spots do
			local u = sp.slot and teamUnit(sp.slot)
			if u then
				local hp, max = u:GetAttribute("HP") or 0, u:GetAttribute("MaxHP") or 1
				sp.hp.Size = UDim2.fromScale(math.clamp(hp / max, 0, 1), 1)
				sp.faint.Visible = u:GetAttribute("State") == "fainted"
			end
		end
		-- the active monster's skills: gold and pulsing when ready, grey with a countdown
		local au = teamUnit(player:GetAttribute("ActiveSlot") or 1)
		-- a gold ring on the ground under the active monster
		if au and au:GetAttribute("State") ~= "fainted" and not au:GetAttribute("Mount") then
			local r = math.max(2.6, au.Size.X * 0.75)
			ringAd.Radius = r
			ringAd.InnerRadius = r - 0.45
			ringAd.Transparency = 0.2 + 0.2 * math.sin(t * 4)
			activeRing.CFrame = CFrame.new(au.Position.X, au.Position.Y - au.Size.Y / 2 + 0.2, au.Position.Z)
			activeRing.Parent = workspace
		else
			activeRing.Parent = nil
		end
		for i, sb in skillBtns do
			local cdLeft = au and ((au:GetAttribute("Cd" .. i) or 0) - nowS) or 0
			local ready = au ~= nil and cdLeft <= 0.05 and au:GetAttribute("State") ~= "fainted"
			local pulse = ready and (0.5 + 0.5 * math.sin(t * 7)) or 0
			sb.shade.Visible = not ready
			sb.cd.Text = (not ready and cdLeft > 0.05) and tostring(math.ceil(cdLeft)) or ""
			sb.ring.Color = ready and GOLD or GREY
			sb.ring.Thickness = ready and (2.5 + pulse * 2) or 2
			sb.sc.Scale = ready and (1 + pulse * 0.07) or 0.94
		end
		-- dots: the top-right buttons mirror their menu tiles; the Menu button lights up
		-- when anything inside it wants attention
		questQDot.Visible = questDot.Visible
		monQDot.Visible = monDot.Visible
		shrineQDot.Visible = shrineDot.Visible
		questQ.Visible = railButtons.Quests.Visible
		local wx = 8
		for _, tb in { menuB, monQ, shrineQ, questQ } do
			if tb.Visible then
				wx += 44
			end
		end
		wallet.Position = UDim2.new(1, -wx - 2, 0, 9)
		local rowW = wx + 2 + wallet.AbsoluteSize.X / (Ui.hudScale or 1)
		if math.abs(rowW - lastRowW) > 0.5 then
			lastRowW = rowW
			Ui.placeTop(rowW)
		end
		local anyDot = false
		for _, d in tileDots do
			if d.Visible and (d.Parent :: GuiObject).Visible then
				anyDot = true
			end
		end
		for name, nb in newBadges do
			if nb.Visible and railButtons[name].Visible then
				anyDot = true
			end
		end
		menuDot.Visible = anyDot
		-- minimap at 10 Hz
		if mapOn and t - lastMini > 0.1 then
			lastMini = t
			drawMinimap()
		end
		-- target frame
		local tgt = Controls.target
		if tgt and tgt.Parent then
			local sp = Monsters.Species[tgt:GetAttribute("Species")]
			local el = tgt:GetAttribute("Element")
			local hp, max = tgt:GetAttribute("HP") or 0, tgt:GetAttribute("MaxHP") or 1
			tName.Text = string.format("%s%s %s  Lv %d  %s", tgt:GetAttribute("Boss") and "👑 " or tgt:GetAttribute("Elite") and "★ Elite " or "", EI[el].Icon, sp and sp.Name or "?", tgt:GetAttribute("Level") or 1, string.rep("★", sp and sp.Stars or 1))
			tName.TextColor3 = EI[el].Color:Lerp(C.Ink, 0.4)
			tFx.Text = (tgt:GetAttribute("Effects") or ""):gsub(",", " ")
			tHp.Size = UDim2.fromScale(math.clamp(hp / max, 0, 1), 1)
			tHpText.Text = Ui.fmt(hp) .. " / " .. Ui.fmt(max)
		end
		-- world spinners
		for _, s in spinners do
			if s.Parent then
				bases[s] = bases[s] or s.CFrame
				if s:GetAttribute("MillHub") then
					s.CFrame = bases[s] * CFrame.Angles(0, 0, t * 0.6)
				else
					s.CFrame = bases[s] * CFrame.new(0, math.sin(t * 1.5) * 0.6, 0) * CFrame.Angles(t * 0.8, 0, 0)
				end
			end
		end
		local _ = dt
	end)

	-- pads
	task.spawn(function()
		while true do
			task.wait(0.2)
			local char = player.Character
			local hrp = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
			local now: string? = nil
			if hrp then
				for _, pad in pads do
					local d = pad.Position - hrp.Position
					if Vector3.new(d.X, 0, d.Z).Magnitude < 3.6 and math.abs(d.Y) < 6 then
						now = pad:GetAttribute("Pad")
						break
					end
				end
			end
			if now ~= onPad then
				if onPad and PAD_PANEL[onPad] and Ui.isOpen(PAD_PANEL[onPad]) then
					Ui.open(nil)
				end
				onPad = now
				if now and PAD_PANEL[now] then
					Ui.open(PAD_PANEL[now])
				end
			end
		end
	end)

	player:GetAttributeChangedSignal("Region"):Connect(function()
		local id = player:GetAttribute("Region")
		if id and REGION_NAMES[id] then
			Ui.toast("Entering " .. REGION_NAMES[id], "info")
		end
	end)

	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	remotes:WaitForChild("Reward").OnClientEvent:Connect(onReward)
	remotes:WaitForChild("Toast").OnClientEvent:Connect(function(msg, kind)
		Ui.toast(msg, kind)
	end)

	task.spawn(function()
		local lb = ReplicatedStorage:WaitForChild("Leaderboard", 30) :: StringValue?
		if lb then
			task.wait(2)
			drawBoard(lb.Value)
			lb.Changed:Connect(function()
				drawBoard(lb.Value)
			end)
		end
	end)
end

return Hud

-- Screen UI in the light house style (src/shared/Theme.luau): coins + rare timer pills, a left
-- rail (Shop, Index), the wake meter while carrying, hints, toasts, the reveal card, the shop
-- (upgrade tracks, Padded Shoes, wing unlocks) and the index (per-wing pages, evolution goals).
-- The Shop and Index also open by stepping on their glowing pads in the hideout.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local ContextActionService = game:GetService("ContextActionService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Creatures = require(Shared.Creatures)
local Theme = require(Shared.Theme)
local Portraits = require(Shared.Portraits)
local CreatureView = require(script.Parent.CreatureView)

local T = Config.Tuning
local C = Theme.C
local F = Theme.Font
local new, corner, pad, stroke, text, button = Theme.new, Theme.corner, Theme.pad, Theme.stroke, Theme.text, Theme.button
local player = Players.LocalPlayer
local Remotes = ReplicatedStorage:WaitForChild("Remotes")

local Hud = {}

local profile = nil

local gui = new("ScreenGui", {
	Name = "BrainrotHud",
	ResetOnSpawn = false,
	IgnoreGuiInset = false,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	Parent = player:WaitForChild("PlayerGui"),
})

local isTouch = UserInputService.TouchEnabled
local small = workspace.CurrentCamera.ViewportSize.X < 900
local S = small and 0.85 or 1 -- type scale
local function px(n: number): number
	return math.floor(n * S + 0.5)
end

local function fmt(n: number): string
	local s = tostring(math.floor(n))
	local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	return (out:gsub("^,", ""))
end

-- White card with a soft shadow.
local function card(props: { [string]: any }, radius: number?)
	props.BackgroundColor3 = props.BackgroundColor3 or C.Card
	local children = props.Children or {}
	props.Children = nil
	table.insert(children, corner(radius or 16))
	local f = new("Frame", props, children)
	Theme.shadow(f, radius or 16, 3)
	return f
end

-- Round coloured dot with an icon glyph.
local function dot(parent: Instance, color: Color3, glyph: string, size: number, pos: UDim2?, anchor: Vector2?)
	local d = new("Frame", {
		Name = "Dot",
		AnchorPoint = anchor or Vector2.new(0, 0.5),
		Position = pos or UDim2.new(0, 6, 0.5, 0),
		Size = UDim2.fromOffset(size, size),
		BackgroundColor3 = color,
		Parent = parent,
	}, { new("UICorner", { CornerRadius = UDim.new(0.5, 0) }) })
	text({ Name = "Glyph", Size = UDim2.fromScale(1, 1), Text = glyph, TextColor3 = Color3.new(1, 1, 1), Parent = d, Children = { pad(math.floor(size * 0.18)) } }, "Title")
	return d
end

----------------------------------------------------------------------------------------------
-- Top bar: coins + rare timer

local top = new("Frame", {
	Name = "Top",
	BackgroundTransparency = 1,
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 8),
	Size = UDim2.fromOffset(px(660), px(40)),
	Parent = gui,
}, {
	new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Center, Padding = UDim.new(0, 10), SortOrder = Enum.SortOrder.LayoutOrder }),
})

local function pill(name: string, order: number, width: number, color: Color3, glyph: string)
	local holder = new("Frame", { Name = name, LayoutOrder = order, BackgroundTransparency = 1, Size = UDim2.fromOffset(px(width), px(40)), Parent = top })
	local p = card({ Name = "Card", Size = UDim2.fromScale(1, 1), Parent = holder }, 20)
	local d = dot(p, color, glyph, px(30), UDim2.new(0, 5, 0.5, 0))
	local v = text({
		Name = "Value",
		Position = UDim2.new(0, px(42), 0, 0),
		Size = UDim2.new(1, -px(50), 1, 0),
		TextScaled = false,
		TextSize = px(18),
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = "",
		Parent = p,
	}, "Title")
	return holder, v, d
end
local coinsPill, coinsText = pill("Coins", 1, 128, C.Sun, "$")
local rarePill, rareText, rareDot = pill("Rare", 2, 240, C.Lilac, "★")
local eventPill, eventText, eventDot = pill("Event", 3, 250, C.Peach, "🍩")

local saveLabel = text({
	Name = "SaveStatus",
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, px(54)),
	Size = UDim2.fromOffset(240, 18),
	TextScaled = false,
	TextSize = px(14),
	Text = "",
	TextColor3 = C.Sub,
	Parent = gui,
}, "Bold")

----------------------------------------------------------------------------------------------
-- Wake meter (only while carrying), bottom centre so the creature overhead stays visible

local METER_POS = UDim2.new(0.5, 0, 1, small and -12 or -28)
local meter = card({
	Name = "WakeMeter",
	AnchorPoint = Vector2.new(0.5, 1),
	Position = METER_POS,
	Size = UDim2.new(small and 0.46 or 0.34, 0, 0, px(66)),
	Visible = false,
	Parent = gui,
	Children = { new("UISizeConstraint", { MaxSize = Vector2.new(460, 80) }) },
}, 18)
local meterTitle = text({
	Position = UDim2.fromOffset(14, 8),
	Size = UDim2.new(0.6, 0, 0, px(22)),
	TextScaled = false,
	TextSize = px(18),
	TextXAlignment = Enum.TextXAlignment.Left,
	Text = "Sleeping soundly",
	Parent = meter,
}, "Title")
local meterSurface = text({
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, -14, 0, 10),
	Size = UDim2.new(0.45, 0, 0, px(18)),
	TextScaled = false,
	TextSize = px(14),
	TextXAlignment = Enum.TextXAlignment.Right,
	Text = "",
	TextColor3 = C.Sub,
	Parent = meter,
}, "Bold")
local barBack = new("Frame", {
	Position = UDim2.new(0, 14, 1, -px(24)),
	Size = UDim2.new(1, -28, 0, px(12)),
	BackgroundColor3 = C.Soft,
	Parent = meter,
}, { new("UICorner", { CornerRadius = UDim.new(0.5, 0) }) })
local barFill = new("Frame", {
	Size = UDim2.fromScale(0, 1),
	BackgroundColor3 = C.Mint,
	Parent = barBack,
}, { new("UICorner", { CornerRadius = UDim.new(0.5, 0) }) })
for _, v in { T.WakeStages.Twitch, T.WakeStages.Squirm, T.WakeStages.EyeOpen } do
	new("Frame", { Position = UDim2.new(v / 100, -1, 0, 0), Size = UDim2.new(0, 2, 1, 0), BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0, ZIndex = 3, Parent = barBack })
end

----------------------------------------------------------------------------------------------
-- Hint line + toasts

local hint = card({
	Name = "Hint",
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 1, small and -88 or -110),
	Size = UDim2.fromOffset(px(420), px(36)),
	Visible = false,
	Parent = gui,
}, 18)
local hintDot = dot(hint, C.Sky, "!", px(24), UDim2.new(0, 6, 0.5, 0))
local hintText = text({
	Name = "Text",
	Position = UDim2.fromOffset(px(38), 0),
	Size = UDim2.new(1, -px(48), 1, 0),
	TextScaled = false,
	TextSize = px(15),
	TextWrapped = true,
	TextXAlignment = Enum.TextXAlignment.Left,
	Parent = hint,
}, "Bold")

local toastHolder = new("Frame", {
	BackgroundTransparency = 1,
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, px(84)),
	Size = UDim2.new(0.8, 0, 0, 200),
	Parent = gui,
}, { new("UIListLayout", { HorizontalAlignment = Enum.HorizontalAlignment.Center, Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }) })

local TOAST_COLORS = { info = C.Sky, warn = C.Peach, alert = C.Coral, good = C.Mint }
local TOAST_GLYPH = { info = "i", warn = "!", alert = "!", good = "✓" }
local toastN = 0
function Hud.toast(msg: string, kind: string?)
	toastN += 1
	local k = kind or "info"
	local holder = new("Frame", { LayoutOrder = toastN, BackgroundTransparency = 1, Size = UDim2.new(0, 0, 0, px(38)), AutomaticSize = Enum.AutomaticSize.X, Parent = toastHolder })
	local t = new("Frame", {
		BackgroundColor3 = C.Card,
		Size = UDim2.new(0, 0, 1, 0),
		AutomaticSize = Enum.AutomaticSize.X,
		Parent = holder,
	}, { corner(19), stroke(TOAST_COLORS[k] or C.Sky, 2) })
	new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, VerticalAlignment = Enum.VerticalAlignment.Center, Padding = UDim.new(0, 8), Parent = t })
	pad(0, 7, 0, 14).Parent = t
	local d = dot(t, TOAST_COLORS[k] or C.Sky, TOAST_GLYPH[k] or "i", px(24))
	d.LayoutOrder = 1
	local label = text({ LayoutOrder = 2, AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.new(0, 0, 1, 0), TextScaled = false, TextSize = px(16), Text = msg, Parent = t }, "Bold")
	new("UISizeConstraint", { MaxSize = Vector2.new(560, 60), Parent = label })
	task.delay(k == "alert" and 2 or 3, function()
		for _, x in t:GetDescendants() do
			if x:IsA("TextLabel") then
				TweenService:Create(x, TweenInfo.new(0.3), { TextTransparency = 1 }):Play()
			elseif x:IsA("Frame") then
				TweenService:Create(x, TweenInfo.new(0.3), { BackgroundTransparency = 1 }):Play()
			elseif x:IsA("UIStroke") then
				TweenService:Create(x, TweenInfo.new(0.3), { Transparency = 1 }):Play()
			end
		end
		TweenService:Create(t, TweenInfo.new(0.3), { BackgroundTransparency = 1 }):Play()
		task.wait(0.3)
		holder:Destroy()
	end)
end

----------------------------------------------------------------------------------------------
-- Portraits (2D images: they don't use the client's few EditableMesh slots)

local function setSilhouette(img: ImageLabel, on: boolean)
	img.ImageColor3 = on and Color3.new(0, 0, 0) or Color3.new(1, 1, 1)
	img.ImageTransparency = on and 0.55 or 0
end

local function portrait(species: string, size: UDim2, silhouette: boolean, parent: Instance)
	local img = new("ImageLabel", {
		Size = size,
		BackgroundTransparency = 1,
		ScaleType = Enum.ScaleType.Fit,
		Parent = parent,
	})
	Portraits.apply(img, species)
	setSilhouette(img, silhouette)
	return img
end

----------------------------------------------------------------------------------------------
-- Panels

local panels = {}
local function panel(name: string, title: string, subtitle: string, accent: Color3, glyph: string)
	local p = card({
		Name = name,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.53),
		Size = UDim2.new(small and 0.9 or 0.62, 0, small and 0.82 or 0.72, 0),
		Visible = false,
		ZIndex = 10,
		Parent = gui,
		Children = { new("UISizeConstraint", { MaxSize = Vector2.new(720, 540) }) },
	}, 24)
	dot(p, accent, glyph, px(40), UDim2.new(0, 18, 0, 18), Vector2.new(0, 0)).ZIndex = 11
	text({ Position = UDim2.fromOffset(px(68), 16), Size = UDim2.new(1, -150, 0, px(26)), TextScaled = false, TextSize = px(24), TextXAlignment = Enum.TextXAlignment.Left, Text = title, ZIndex = 11, Parent = p }, "Title")
	local sub = text({ Name = "Subtitle", Position = UDim2.fromOffset(px(68), 16 + px(27)), Size = UDim2.new(1, -150, 0, px(16)), TextScaled = false, TextSize = px(14), TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = C.Sub, Text = subtitle, ZIndex = 11, Parent = p }, "Bold")
	local close = button({
		Name = "Close",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -16, 0, 16),
		Size = UDim2.fromOffset(px(38), px(38)),
		BackgroundColor3 = C.Soft,
		TextColor3 = C.Sub,
		TextScaled = false,
		TextSize = px(18),
		Text = "X",
		ZIndex = 11,
		Parent = p,
		Radius = 19,
	})
	close.Activated:Connect(function()
		p.Visible = false
	end)
	local body = new("ScrollingFrame", {
		Name = "Body",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(16, px(76)),
		Size = UDim2.new(1, -32, 1, -px(76) - 16),
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 4,
		ScrollBarImageColor3 = C.Mute,
		BorderSizePixel = 0,
		ZIndex = 11,
		Parent = p,
	}, { new("UIListLayout", { Padding = UDim.new(0, 10), SortOrder = Enum.SortOrder.LayoutOrder }), pad(2, 2, 8, 6) })
	panels[name] = p
	return p, body, sub
end

local function openPanel(name: string?)
	for n, p in panels do
		p.Visible = n == name
	end
	if Hud.onOpen then
		Hud.onOpen(name)
	end
	if name then
		Hud.refresh()
		CreatureView.playUi("rbxasset://sounds/electronicpingshort.wav", 0.3, 1.3)
	end
end
Hud.openPanel = openPanel

local shop, shopBody = panel("Shop", "Shop", "Upgrades stay forever", C.Peach, "$")
local collection, indexBody, indexSub = panel("Collection", "Index", "Find every creature", C.Lilac, "★")

-- Left rail
local rail = new("Frame", {
	Name = "Rail",
	BackgroundTransparency = 1,
	AnchorPoint = Vector2.new(0, 0.5),
	Position = UDim2.new(0, 12, 0.45, 0),
	Size = UDim2.fromOffset(px(66), px(170)),
	Parent = gui,
}, { new("UIListLayout", { Padding = UDim.new(0, 12), SortOrder = Enum.SortOrder.LayoutOrder }) })

local function railButton(name: string, label: string, glyph: string, order: number, color: Color3, target: string)
	local holder = new("Frame", { Name = name .. "Holder", LayoutOrder = order, BackgroundTransparency = 1, Size = UDim2.fromOffset(px(66), px(74)), Parent = rail })
	local b = button({
		Name = name,
		Size = UDim2.fromOffset(px(66), px(74)),
		BackgroundColor3 = C.Card,
		Text = "",
		Parent = holder,
		Radius = 18,
	})
	Theme.shadow(b, 18, 3)
	dot(b, color, glyph, px(38), UDim2.new(0.5, 0, 0, px(8)), Vector2.new(0.5, 0))
	text({ Position = UDim2.new(0, 0, 1, -px(24)), Size = UDim2.new(1, 0, 0, px(18)), TextScaled = false, TextSize = px(14), Text = label, Parent = b }, "Title")
	local badge = new("Frame", {
		Name = "Badge",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 4, 0, -4),
		Size = UDim2.fromOffset(16, 16),
		BackgroundColor3 = C.Rose,
		Visible = false,
		ZIndex = 3,
		Parent = b,
	}, { new("UICorner", { CornerRadius = UDim.new(0.5, 0) }), stroke(Color3.new(1, 1, 1), 2) })
	b.Activated:Connect(function()
		openPanel(if panels[target].Visible then nil else target)
	end)
	return b, badge
end
local shopBtn, shopBadge = railButton("ShopButton", "Shop", "$", 1, C.Peach, "Shop")
local collectionBtn, newBadge = railButton("CollectionButton", "Index", "★", 2, C.Lilac, "Collection")
local shelves, shelvesBody, shelvesSub = panel("Shelves", "Shelves", "Creatures on display earn coins", C.Mint, "🏆")
local shelvesBtn, shelvesBadge = railButton("ShelvesButton", "Shelves", "🏆", 3, C.Mint, "Shelves")
local quests, questsBody, questsSub = panel("Quests", "Quests", "New quests every day", C.Sky, "📋")
local questsBtn, questsBadge = railButton("QuestsButton", "Quests", "📋", 4, C.Sky, "Quests")
local overtime, overtimeBody, overtimeSub = panel("Overtime", "Overtime", "Start over stronger", C.Rose, "⏰")
local overtimeBtn, overtimeBadge = railButton("OvertimeButton", "Overtime", "⏰", 5, C.Rose, "Overtime")
overtimeBtn.Parent.Visible = false -- shown once the Toy Barn is open
rail.Size = UDim2.fromOffset(px(66), px(440))
do
	-- shrink the rail on short screens (phones in landscape) so all buttons stay visible
	local railScale = new("UIScale", { Parent = rail })
	local function fit()
		local h = workspace.CurrentCamera.ViewportSize.Y
		local count = 0
		for _, c in rail:GetChildren() do
			if c:IsA("Frame") and c.Visible then
				count += 1
			end
		end
		local need = count * px(86)
		railScale.Scale = math.clamp((h - 150) / math.max(1, need), 0.55, 1)
	end
	workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(fit)
	overtimeBtn.Parent:GetPropertyChangedSignal("Visible"):Connect(fit)
	task.defer(fit)
end

----------------------------------------------------------------------------------------------
-- Shop rows

local function row(parent: Instance, order: number, accent: Color3, glyph: string, title: string, blurb: string)
	local r = new("Frame", {
		Name = "Row",
		LayoutOrder = order,
		Size = UDim2.new(1, 0, 0, px(78)),
		BackgroundColor3 = C.Soft,
		ZIndex = 12,
		Parent = parent,
	}, { corner(16) })
	local d = dot(r, Theme.tint(accent, 0.15), glyph, px(48), UDim2.new(0, 14, 0.5, 0))
	d.ZIndex = 13
	local name = text({ Name = "Title", Position = UDim2.fromOffset(px(74), px(14)), Size = UDim2.new(1, -px(74) - px(150), 0, px(22)), TextScaled = false, TextSize = px(19), TextXAlignment = Enum.TextXAlignment.Left, Text = title, ZIndex = 13, Parent = r }, "Title")
	local sub = text({ Name = "Blurb", Position = UDim2.fromOffset(px(74), px(38)), Size = UDim2.new(1, -px(74) - px(150), 0, px(30)), TextScaled = false, TextSize = px(14), TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top, TextColor3 = C.Sub, Text = blurb, ZIndex = 13, Parent = r }, "Bold")
	local buy = button({
		Name = "Buy",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -14, 0.5, 0),
		Size = UDim2.fromOffset(px(128), px(44)),
		BackgroundColor3 = accent,
		TextScaled = false,
		TextSize = px(17),
		Text = "",
		ZIndex = 13,
		Parent = r,
		Radius = 22,
	})
	return { row = r, title = name, blurb = sub, buy = buy, accent = accent }
end

local function setBuy(b: TextButton, label: string, state: string, accent: Color3)
	-- state: "afford" | "poor" | "done"
	b.Text = label
	if state == "afford" then
		b.BackgroundColor3 = accent
		b.TextColor3 = Color3.new(1, 1, 1)
	elseif state == "poor" then
		b.BackgroundColor3 = C.Line
		b.TextColor3 = C.Sub
	else
		b.BackgroundColor3 = Theme.tint(C.Mint, 0.6)
		b.TextColor3 = Color3.fromRGB(40, 140, 100)
	end
end

local shopRows = {}
local function buyItem(item: string)
	local ok, msg = Remotes.Buy:InvokeServer(item)
	Hud.toast(msg, ok and "good" or "warn")
	if ok then
		CreatureView.playUi(CreatureView.SOUNDS.Pop, 0.5, 1.8)
	end
end

do
	local order = 0
	local function section(title: string)
		order += 1
		text({ LayoutOrder = order, Size = UDim2.new(1, 0, 0, px(20)), TextScaled = false, TextSize = px(14), TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = C.Sub, Text = title, ZIndex = 12, Parent = shopBody }, "Title")
	end
	section("SPEED")
	for _, id in { "Sneakers", "SteadyHands" } do
		local def = T.Tracks[id]
		order += 1
		local r = row(shopBody, order, id == "Sneakers" and C.Sky or C.Mint, def.Icon, def.Name, def.Blurb)
		r.buy.Name = "Buy" .. id
		r.buy.Activated:Connect(function()
			buyItem(id)
		end)
		shopRows[id] = r
	end
	section("GEAR")
	for id, def in T.Shop do
		order += 1
		local r = row(shopBody, order, C.Peach, def.Icon, def.Name, def.Blurb)
		r.buy.Name = "Buy" .. id
		r.buy.Activated:Connect(function()
			buyItem(id)
		end)
		shopRows[id] = r
	end
	section("WINGS OF THE MALL")
	for _, w in Config.wingList() do
		if w.Price > 0 then
			order += 1
			local r = row(shopBody, order, C.Lilac, w.Icon or "★", w.Name, "New creatures worth " .. w.CoinMult .. "x coins. " .. (w.Where or ""))
			r.buy.Name = "Buy" .. w.Id
			r.buy.Activated:Connect(function()
				buyItem(w.Id)
			end)
			shopRows[w.Id] = r
		end
	end
end

----------------------------------------------------------------------------------------------
-- Index pages

local cards = {}
local wingHeaders = {}
local evoLines = {}
local pageChips = {} -- [wing..":"..tier] = chip
local trailChips = {}
local TIER_LABEL = { Found = "Complete page", Glazed = "All Glazed", Jumbo = "All Jumbo" }
local TIER_COLOR = { Found = C.Lilac, Glazed = C.Sun, Jumbo = C.Peach }
do
	local order = 0
	-- evolution goals first: the next thing to work toward
	order += 1
	local goals = new("Frame", { Name = "Goals", LayoutOrder = order, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundColor3 = Theme.tint(C.Sun, 0.8), ZIndex = 12, Parent = indexBody }, {
		corner(16),
		pad(10, 14),
		new("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }),
	})
	text({ LayoutOrder = 0, Size = UDim2.new(1, 0, 0, px(20)), TextScaled = false, TextSize = px(16), TextXAlignment = Enum.TextXAlignment.Left, Text = "Evolution goals", ZIndex = 13, Parent = goals }, "Title")
	for i, e in T.Evolutions do
		evoLines[e.To] = text({ LayoutOrder = i, Size = UDim2.new(1, 0, 0, px(18)), TextScaled = false, TextSize = px(14), TextWrapped = true, AutomaticSize = Enum.AutomaticSize.Y, TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = C.Ink, ZIndex = 13, Parent = goals }, "Bold")
	end
	for _, w in Config.wingList() do
		order += 1
		wingHeaders[w.Id] = text({ LayoutOrder = order, Size = UDim2.new(1, 0, 0, px(22)), TextScaled = false, TextSize = px(14), TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = C.Sub, Text = string.upper(w.Name), ZIndex = 12, Parent = indexBody }, "Title")
		-- page rewards: complete / all Glazed / all Jumbo
		order += 1
		local strip = new("Frame", { Name = "Rewards_" .. w.Id, LayoutOrder = order, BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, px(92)), ZIndex = 12, Parent = indexBody }, {
			new("UIGridLayout", { CellSize = UDim2.new(1 / 3, -7, 1, 0), CellPadding = UDim2.fromOffset(10, 0), SortOrder = Enum.SortOrder.LayoutOrder }),
		})
		for i, r in T.IndexRewards[w.Id] or {} do
			local col = TIER_COLOR[r.Tier]
			local chip = new("Frame", { Name = r.Tier, LayoutOrder = i, BackgroundColor3 = Theme.tint(col, 0.85), ZIndex = 13, Parent = strip }, { corner(14) })
			local title = text({ Position = UDim2.fromOffset(12, px(8)), Size = UDim2.new(1, -24, 0, px(18)), TextScaled = false, TextSize = px(15), TextXAlignment = Enum.TextXAlignment.Left, Text = TIER_LABEL[r.Tier], ZIndex = 14, Parent = chip }, "Title")
			local prize = text({ Position = UDim2.fromOffset(12, px(28)), Size = UDim2.new(1, -24, 0, px(16)), TextScaled = false, TextSize = px(13), TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd, TextColor3 = C.Sub, Text = "$ " .. fmt(r.Coins) .. (r.Trail and (" + " .. T.Trails[r.Trail].Name .. " trail") or ""), ZIndex = 14, Parent = chip }, "Bold")
			local claim = button({ Name = "Claim", Position = UDim2.new(0, 10, 1, -px(38)), Size = UDim2.new(1, -20, 0, px(30)), BackgroundColor3 = col, TextScaled = false, TextSize = px(14), Text = "", ZIndex = 14, Parent = chip, Radius = 15 })
			claim.Activated:Connect(function()
				local ok, msg = Remotes.ClaimPage:InvokeServer(w.Id, r.Tier)
				Hud.toast(msg, ok and "good" or "info")
				if ok then
					CreatureView.playUi(CreatureView.SOUNDS.Pop, 0.8, 1.2)
				end
			end)
			pageChips[w.Id .. ":" .. r.Tier] = { chip = chip, title = title, prize = prize, claim = claim, color = col, wing = w.Id, tier = r.Tier }
		end
		order += 1
		local grid = new("Frame", { Name = "Grid_" .. w.Id, LayoutOrder = order, BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, ZIndex = 12, Parent = indexBody }, {
			new("UIGridLayout", { CellSize = UDim2.new(0.25, -8, 0, px(170)), CellPadding = UDim2.fromOffset(10, 10), SortOrder = Enum.SortOrder.LayoutOrder }),
		})
		for _, sp in Creatures.ordered() do
			if sp.Wing == w.Id then
				local c = new("Frame", { Name = "Card_" .. sp.Id, LayoutOrder = sp.Order, BackgroundColor3 = C.Soft, ZIndex = 12, Parent = grid }, { corner(16) })
				local vf = portrait(sp.Id, UDim2.new(1, -16, 0, px(88)), true, c)
				vf.Position = UDim2.fromOffset(8, px(6))
				vf.ZIndex = 13
				local name = text({ Position = UDim2.new(0, 6, 0, px(96)), Size = UDim2.new(1, -12, 0, px(18)), TextScaled = false, TextSize = px(15), TextTruncate = Enum.TextTruncate.AtEnd, Text = "???", ZIndex = 13, Parent = c }, "Title")
				local info = text({ Position = UDim2.new(0, 6, 0, px(114)), Size = UDim2.new(1, -12, 0, px(16)), TextScaled = false, TextSize = px(13), Text = "", TextColor3 = C.Sub, ZIndex = 13, Parent = c }, "Bold")
				local equip = button({
					Name = "Equip",
					AnchorPoint = Vector2.new(0.5, 1),
					Position = UDim2.new(0.5, 0, 1, -6),
					Size = UDim2.new(1, -12, 0, px(26)),
					BackgroundColor3 = C.Mint,
					TextScaled = false,
					TextSize = px(14),
					Text = "Make buddy",
					Visible = false,
					ZIndex = 13,
					Parent = c,
					Radius = 13,
				})
				equip.Activated:Connect(function()
					local isBuddy = profile and profile.buddy == sp.Id
					local ok, msg = Remotes.Equip:InvokeServer(if isBuddy then nil else sp.Id)
					Hud.toast(msg, ok and "good" or "warn")
				end)
				cards[sp.Id] = { vf = vf, name = name, info = info, equip = equip }
			end
		end
	end
end

-- Trails (unlocked by Index pages), at the bottom of the Index
do
	text({ LayoutOrder = 100, Size = UDim2.new(1, 0, 0, px(22)), TextScaled = false, TextSize = px(14), TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = C.Sub, Text = "TRAILS", ZIndex = 12, Parent = indexBody }, "Title")
	local strip = new("Frame", { Name = "Trails", LayoutOrder = 101, BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, ZIndex = 12, Parent = indexBody }, {
		new("UIGridLayout", { CellSize = UDim2.new(0.25, -8, 0, px(96)), CellPadding = UDim2.fromOffset(10, 10), SortOrder = Enum.SortOrder.LayoutOrder }),
	})
	local source = {}
	for wing, list in T.IndexRewards do
		for _, r in list do
			if r.Trail then
				source[r.Trail] = Config.Wings[wing].Name .. " · " .. TIER_LABEL[r.Tier]
			end
		end
	end
	for id, def in T.Trails do
		local chip = new("Frame", { Name = id, LayoutOrder = def.Order, BackgroundColor3 = C.Soft, ZIndex = 13, Parent = strip }, { corner(14) })
		local swatch = new("Frame", { Position = UDim2.fromOffset(10, px(10)), Size = UDim2.new(1, -20, 0, px(12)), BackgroundColor3 = Color3.new(1, 1, 1), ZIndex = 14, Parent = chip }, { new("UICorner", { CornerRadius = UDim.new(0.5, 0) }) })
		local keys = {}
		for i, c in def.Colors do
			table.insert(keys, ColorSequenceKeypoint.new((i - 1) / math.max(1, #def.Colors - 1), c))
		end
		new("UIGradient", { Color = ColorSequence.new(keys), Parent = swatch })
		text({ Position = UDim2.fromOffset(10, px(26)), Size = UDim2.new(1, -20, 0, px(18)), TextScaled = false, TextSize = px(15), TextXAlignment = Enum.TextXAlignment.Left, Text = def.Name, ZIndex = 14, Parent = chip }, "Title")
		local btn = button({ Name = "Equip", Position = UDim2.new(0, 10, 1, -px(38)), Size = UDim2.new(1, -20, 0, px(30)), BackgroundColor3 = C.Lilac, TextScaled = false, TextSize = px(13), Text = "", ZIndex = 14, Parent = chip, Radius = 15 })
		btn.Activated:Connect(function()
			if not profile or not (profile.trails and profile.trails[id]) then
				return
			end
			local ok, msg = Remotes.EquipTrail:InvokeServer(if profile.trail == id then nil else id)
			Hud.toast(msg, ok and "good" or "warn")
		end)
		trailChips[id] = { btn = btn, source = source[id] or "" }
	end
end

local function refreshPages()
	if not profile or not profile.pages then
		return
	end
	for _, pc in pageChips do
		local have, total = Config.pageProgress(profile, Creatures.Species, pc.wing, pc.tier)
		local claimed = profile.pages[pc.wing .. ":" .. pc.tier]
		pc.title.Text = string.format("%s  %d/%d", TIER_LABEL[pc.tier], have, total)
		if claimed then
			setBuy(pc.claim, "Claimed ✓", "done", pc.color)
		elseif have >= total then
			setBuy(pc.claim, "Claim", "afford", pc.color)
		else
			setBuy(pc.claim, string.format("%d to go", total - have), "poor", pc.color)
		end
	end
	for id, tc in trailChips do
		local owned = profile.trails and profile.trails[id]
		if not owned then
			tc.btn.Text = tc.source
			tc.btn.BackgroundColor3 = C.Line
			tc.btn.TextColor3 = C.Sub
		elseif profile.trail == id then
			setBuy(tc.btn, "On ✓", "done", C.Lilac)
		else
			setBuy(tc.btn, "Wear", "afford", C.Lilac)
		end
	end
end

----------------------------------------------------------------------------------------------
-- Shelves panel: tip jar, fill-best, slot cards, picker

local D = T.Display
local function fmtRate(r: number): string
	return r >= 10 and tostring(math.floor(r + 0.5)) or string.format("%.1f", r)
end

local shelfSlots = {}
local pickerSlot: number? = nil
local jarText, collectBtn, fillBtn
local picker, pickerList, pickerTitle
do
	-- summary row
	local top = new("Frame", { Name = "JarRow", LayoutOrder = 1, Size = UDim2.new(1, 0, 0, px(78)), BackgroundColor3 = Theme.tint(C.Sun, 0.8), ZIndex = 12, Parent = shelvesBody }, { corner(16) })
	dot(top, C.Sun, "$", px(48), UDim2.new(0, 14, 0.5, 0)).ZIndex = 13
	text({ Position = UDim2.fromOffset(px(74), px(12)), Size = UDim2.new(1, -px(330), 0, px(22)), TextScaled = false, TextSize = px(19), TextXAlignment = Enum.TextXAlignment.Left, Text = "Tip jar", ZIndex = 13, Parent = top }, "Title")
	jarText = text({ Position = UDim2.fromOffset(px(74), px(38)), Size = UDim2.new(1, -px(330), 0, px(30)), TextScaled = false, TextSize = px(14), TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top, TextColor3 = C.Sub, Text = "", ZIndex = 13, Parent = top }, "Bold")
	collectBtn = button({ Name = "Collect", AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -14, 0.5, 0), Size = UDim2.fromOffset(px(128), px(44)), BackgroundColor3 = C.Sun, TextScaled = false, TextSize = px(17), Text = "Collect", ZIndex = 13, Parent = top, Radius = 22 })
	fillBtn = button({ Name = "FillBest", AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -px(150), 0.5, 0), Size = UDim2.fromOffset(px(128), px(44)), BackgroundColor3 = C.Mint, TextScaled = false, TextSize = px(17), Text = "Fill best", ZIndex = 13, Parent = top, Radius = 22 })
	collectBtn.Activated:Connect(function()
		local ok, msg = Remotes.Collect:InvokeServer()
		Hud.toast(msg, ok and "good" or "info")
		if ok then
			CreatureView.playUi(CreatureView.SOUNDS.Pop, 0.6, 1.6)
		end
	end)
	fillBtn.Activated:Connect(function()
		local ok, msg = Remotes.AutoFill:InvokeServer()
		Hud.toast(msg, ok and "good" or "warn")
	end)

	local grid = new("Frame", { Name = "Slots", LayoutOrder = 2, BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, ZIndex = 12, Parent = shelvesBody }, {
		new("UIGridLayout", { CellSize = UDim2.new(0.2, -8, 0, px(150)), CellPadding = UDim2.fromOffset(10, 10), SortOrder = Enum.SortOrder.LayoutOrder }),
	})
	for i = 1, Config.maxSlots() do
		local c = button({ Name = "Slot_" .. i, LayoutOrder = i, BackgroundColor3 = C.Soft, Text = "", ZIndex = 12, Parent = grid, Radius = 16 })
		local img = new("ImageLabel", { Name = "Portrait", Position = UDim2.fromOffset(8, px(6)), Size = UDim2.new(1, -16, 0, px(84)), BackgroundTransparency = 1, ScaleType = Enum.ScaleType.Fit, ZIndex = 13, Parent = c })
		local big = text({ Name = "Big", Position = UDim2.fromOffset(0, px(20)), Size = UDim2.new(1, 0, 0, px(44)), TextScaled = false, TextSize = px(34), TextColor3 = C.Mute, Text = "+", ZIndex = 13, Parent = c }, "Title")
		local name = text({ Name = "Name", Position = UDim2.new(0, 6, 0, px(94)), Size = UDim2.new(1, -12, 0, px(18)), TextScaled = false, TextSize = px(14), TextTruncate = Enum.TextTruncate.AtEnd, Text = "", ZIndex = 13, Parent = c }, "Title")
		local info = text({ Name = "Info", Position = UDim2.new(0, 6, 0, px(114)), Size = UDim2.new(1, -12, 0, px(28)), TextScaled = false, TextSize = px(13), TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top, TextColor3 = C.Sub, Text = "", ZIndex = 13, Parent = c }, "Bold")
		c.Activated:Connect(function()
			if not profile then
				return
			end
			if i <= profile.slots then
				Hud.openPicker(i)
			elseif i == profile.slots + 1 then
				local ok, msg = Remotes.Buy:InvokeServer("ShelfSlot")
				Hud.toast(msg, ok and "good" or "warn")
			end
		end)
		shelfSlots[i] = { btn = c, img = img, big = big, name = name, info = info }
	end

	-- picker overlay (inside the panel)
	picker = new("Frame", { Name = "Picker", Position = UDim2.fromOffset(0, 0), Size = UDim2.fromScale(1, 1), BackgroundColor3 = C.Card, Visible = false, ZIndex = 30, Parent = shelves }, { corner(24) })
	pickerTitle = text({ Position = UDim2.fromOffset(px(22), 18), Size = UDim2.new(1, -150, 0, px(26)), TextScaled = false, TextSize = px(22), TextXAlignment = Enum.TextXAlignment.Left, Text = "Choose a creature", ZIndex = 31, Parent = picker }, "Title")
	local back = button({ Name = "Back", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -16, 0, 16), Size = UDim2.fromOffset(px(90), px(38)), BackgroundColor3 = C.Soft, TextColor3 = C.Sub, TextScaled = false, TextSize = px(16), Text = "Back", ZIndex = 31, Parent = picker, Radius = 19 })
	back.Activated:Connect(function()
		picker.Visible = false
	end)
	pickerList = new("ScrollingFrame", { Name = "List", BackgroundTransparency = 1, Position = UDim2.fromOffset(16, px(64)), Size = UDim2.new(1, -32, 1, -px(64) - 16), CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y, ScrollBarThickness = 4, ScrollBarImageColor3 = C.Mute, BorderSizePixel = 0, ZIndex = 31, Parent = picker }, {
		new("UIGridLayout", { CellSize = UDim2.new(0.25, -8, 0, px(150)), CellPadding = UDim2.fromOffset(10, 10), SortOrder = Enum.SortOrder.LayoutOrder }),
		pad(2, 2, 8, 6),
	})
end

Hud.onOpen = function()
	picker.Visible = false
end

local function displayedCount(species: string, except: number?): number
	local n = 0
	for i = 1, profile.slots do
		local e = profile.display[i]
		if i ~= except and e and e.s == species then
			n += 1
		end
	end
	return n
end

function Hud.openPicker(slot: number)
	pickerSlot = slot
	for _, c in pickerList:GetChildren() do
		if c:IsA("GuiObject") then
			c:Destroy()
		end
	end
	pickerTitle.Text = "Shelf " .. slot .. ": choose a creature"
	local options = {}
	for id, entry in profile.collection do
		local sp = Creatures.Species[id]
		local free = entry.count - displayedCount(id, slot)
		for _, f in T.Forms do
			if entry.forms[f.Id] then
				table.insert(options, { s = id, f = f.Id, r = Config.displayRate(sp, f.Id), free = free })
			end
		end
	end
	table.sort(options, function(a, b)
		return a.r > b.r
	end)
	local cur = profile.display[slot]
	local order = 0
	local function option(label: string, sub: string, species: string?, form: string?, enabled: boolean)
		order += 1
		local c = button({ LayoutOrder = order, BackgroundColor3 = enabled and C.Soft or Theme.tint(C.Line, 0.4), Text = "", ZIndex = 32, Parent = pickerList, Radius = 16 })
		if species then
			local img = new("ImageLabel", { Position = UDim2.fromOffset(8, px(6)), Size = UDim2.new(1, -16, 0, px(84)), BackgroundTransparency = 1, ScaleType = Enum.ScaleType.Fit, ZIndex = 33, Parent = c })
			Portraits.apply(img, species)
			if form == "Glazed" then
				img.ImageColor3 = Color3.fromRGB(255, 245, 200)
			end
			img.ImageTransparency = enabled and 0 or 0.6
		else
			text({ Position = UDim2.fromOffset(0, px(24)), Size = UDim2.new(1, 0, 0, px(40)), TextScaled = false, TextSize = px(30), TextColor3 = C.Mute, Text = "–", ZIndex = 33, Parent = c }, "Title")
		end
		text({ Position = UDim2.new(0, 6, 0, px(94)), Size = UDim2.new(1, -12, 0, px(18)), TextScaled = false, TextSize = px(14), TextTruncate = Enum.TextTruncate.AtEnd, Text = label, ZIndex = 33, Parent = c }, "Title")
		text({ Position = UDim2.new(0, 6, 0, px(114)), Size = UDim2.new(1, -12, 0, px(28)), TextScaled = false, TextSize = px(13), TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top, TextColor3 = C.Sub, Text = sub, ZIndex = 33, Parent = c }, "Bold")
		c.Activated:Connect(function()
			if not enabled then
				return
			end
			local ok, msg = Remotes.Display:InvokeServer(slot, species, form)
			Hud.toast(msg, ok and "good" or "warn")
			if ok then
				picker.Visible = false
			end
		end)
	end
	if cur and cur.s then
		option("Empty shelf", "take it down", nil, nil, true)
	end
	for _, o in options do
		local sp = Creatures.Species[o.s]
		local isCur = cur and cur.s == o.s and cur.f == o.f
		local enabled = not isCur and o.free > 0
		local sub = string.format("%s / min", fmtRate(o.r))
		if isCur then
			sub = "on this shelf"
		elseif o.free <= 0 then
			sub = "all on shelves"
		end
		option((o.f ~= "Normal" and (o.f .. " ") or "") .. sp.Name, sub, o.s, o.f, enabled)
	end
	if #options == 0 then
		option("Nothing yet", "rescue a creature first", nil, nil, false)
	end
	picker.Visible = true
end

local function refreshShelves()
	if not profile then
		return
	end
	local rate = 0
	for i, sl in shelfSlots do
		local e = profile.display[i]
		sl.btn.Visible = i <= profile.slots + 1
		sl.img.Visible = false
		sl.big.Visible = false
		sl.btn.BackgroundColor3 = C.Soft
		if i <= profile.slots and e and e.s then
			local sp = Creatures.Species[e.s]
			local r = Config.displayRate(sp, e.f)
			rate += r
			Portraits.apply(sl.img, e.s)
			sl.img.ImageColor3 = e.f == "Glazed" and Color3.fromRGB(255, 245, 200) or Color3.new(1, 1, 1)
			sl.img.Visible = true
			sl.name.Text = (e.f ~= "Normal" and (e.f .. " ") or "") .. sp.Name
			sl.info.Text = fmtRate(r * Config.coinMult(profile)) .. " / min"
		elseif i <= profile.slots then
			sl.big.Visible = true
			sl.big.Text = "+"
			sl.name.Text = "Empty"
			sl.info.Text = "tap to fill"
		else
			local price = D.SlotCosts[i - D.StartSlots]
			sl.big.Visible = true
			sl.big.Text = "🔒"
			sl.name.Text = "Shelf " .. i
			sl.info.Text = price and ("unlock $ " .. fmt(price)) or ""
			sl.btn.BackgroundColor3 = (price and profile.coins >= price) and Theme.tint(C.Mint, 0.75) or Theme.tint(C.Line, 0.5)
		end
	end
	rate *= Config.coinMult(profile)
	shelvesSub.Text = string.format("%s coins a minute · %d/%d shelves", fmtRate(rate), profile.slots, Config.maxSlots())
	if picker.Visible and pickerSlot then
		Hud.openPicker(pickerSlot)
	end
end

local function updateJarText()
	local jar = player:GetAttribute("Jar") or 0
	local rate = player:GetAttribute("IncomeRate") or 0
	if rate <= 0 then
		jarText.Text = "Put creatures on your shelves and they earn coins here, even while you're away"
	elseif player:GetAttribute("JarFull") then
		jarText.Text = string.format("%s coins · full! Collect to keep earning", fmt(jar))
	else
		jarText.Text = string.format("%s coins · filling at %s a minute", fmt(jar), fmtRate(rate))
	end
	collectBtn.BackgroundColor3 = jar >= 1 and C.Sun or C.Line
	collectBtn.TextColor3 = jar >= 1 and Color3.new(1, 1, 1) or C.Sub
end

----------------------------------------------------------------------------------------------
-- Quests panel: login streak track + today's quests

local streakTiles = {}
local streakTitle, streakClaim
local questRows = {}
local bonusRow
local questsFooter
do
	local card = new("Frame", { Name = "Streak", LayoutOrder = 1, Size = UDim2.new(1, 0, 0, px(150)), BackgroundColor3 = Theme.tint(C.Sun, 0.8), ZIndex = 12, Parent = questsBody }, { corner(16) })
	streakTitle = text({ Position = UDim2.fromOffset(16, px(12)), Size = UDim2.new(1, -px(180), 0, px(22)), TextScaled = false, TextSize = px(19), TextXAlignment = Enum.TextXAlignment.Left, Text = "Daily reward", ZIndex = 13, Parent = card }, "Title")
	streakClaim = button({ Name = "ClaimStreak", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -14, 0, px(8)), Size = UDim2.fromOffset(px(150), px(36)), BackgroundColor3 = C.Sun, TextScaled = false, TextSize = px(16), Text = "Claim", ZIndex = 13, Parent = card, Radius = 18 })
	streakClaim.Activated:Connect(function()
		local ok, msg = Remotes.ClaimStreak:InvokeServer()
		Hud.toast(msg, ok and "good" or "info")
		if ok then
			CreatureView.playUi(CreatureView.SOUNDS.Pop, 0.7, 1.4)
		end
	end)
	local strip = new("Frame", { Position = UDim2.fromOffset(14, px(54)), Size = UDim2.new(1, -28, 0, px(84)), BackgroundTransparency = 1, ZIndex = 13, Parent = card }, {
		new("UIGridLayout", { CellSize = UDim2.new(1 / 7, -6, 1, 0), CellPadding = UDim2.fromOffset(6, 0), SortOrder = Enum.SortOrder.LayoutOrder }),
	})
	for i = 1, 7 do
		local t = new("Frame", { LayoutOrder = i, BackgroundColor3 = C.Card, ZIndex = 14, Parent = strip }, { corner(12), stroke(C.Line, 2) })
		local day = text({ Name = "Day", Position = UDim2.fromOffset(0, px(8)), Size = UDim2.new(1, 0, 0, px(16)), TextScaled = false, TextSize = px(13), TextColor3 = C.Sub, Text = "Day " .. i, ZIndex = 15, Parent = t }, "Bold")
		local amt = text({ Name = "Amount", Position = UDim2.fromOffset(0, px(30)), Size = UDim2.new(1, 0, 0, px(22)), TextScaled = false, TextSize = px(17), Text = "", ZIndex = 15, Parent = t }, "Title")
		local mark = text({ Name = "Mark", Position = UDim2.fromOffset(0, px(56)), Size = UDim2.new(1, 0, 0, px(18)), TextScaled = false, TextSize = px(14), TextColor3 = Color3.fromRGB(40, 160, 110), Text = "", ZIndex = 15, Parent = t }, "Title")
		streakTiles[i] = { frame = t, day = day, amt = amt, mark = mark, stroke = t:FindFirstChildOfClass("UIStroke") }
	end

	text({ LayoutOrder = 2, Size = UDim2.new(1, 0, 0, px(20)), TextScaled = false, TextSize = px(14), TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = C.Sub, Text = "TODAY'S QUESTS", ZIndex = 12, Parent = questsBody }, "Title")
	for i = 1, 3 do
		local r = row(questsBody, 2 + i, C.Sky, "", "", "")
		r.row.Name = "Quest" .. i
		r.buy.Name = "Claim"
		r.blurb.Size = UDim2.new(1, -px(74) - px(150), 0, px(16))
		local barBack = new("Frame", { Position = UDim2.new(0, px(74), 0, px(56)), Size = UDim2.new(1, -px(74) - px(160), 0, px(8)), BackgroundColor3 = C.Line, ZIndex = 13, Parent = r.row }, { new("UICorner", { CornerRadius = UDim.new(0.5, 0) }) })
		local fill = new("Frame", { Size = UDim2.fromScale(0, 1), BackgroundColor3 = C.Sky, ZIndex = 14, Parent = barBack }, { new("UICorner", { CornerRadius = UDim.new(0.5, 0) }) })
		r.fill = fill
		r.buy.Activated:Connect(function()
			local ok, msg = Remotes.ClaimQuest:InvokeServer(i)
			Hud.toast(msg, ok and "good" or "info")
			if ok then
				CreatureView.playUi(CreatureView.SOUNDS.Pop, 0.6, 1.6)
			end
		end)
		questRows[i] = r
	end
	bonusRow = row(questsBody, 7, C.Sun, "★", "Finish all three", "Bonus coins for a full day")
	bonusRow.row.Name = "Bonus"
	bonusRow.buy.Name = "ClaimBonus"
	bonusRow.buy.Activated:Connect(function()
		local ok, msg = Remotes.ClaimQuest:InvokeServer("bonus")
		Hud.toast(msg, ok and "good" or "info")
		if ok then
			CreatureView.playUi(CreatureView.SOUNDS.Pop, 0.7, 1.2)
		end
	end)
	questsFooter = text({ LayoutOrder = 8, Size = UDim2.new(1, 0, 0, px(20)), TextScaled = false, TextSize = px(14), TextColor3 = C.Sub, Text = "", ZIndex = 12, Parent = questsBody }, "Bold")
end

local function refreshQuests()
	if not profile or not profile.daily then
		return
	end
	local today = os.time() // 86400
	local d, ready = Config.streakPreview(profile, today)
	streakTitle.Text = ready and string.format("Daily reward · Day %d", d) or string.format("Daily reward · Day %d claimed", d)
	streakClaim.Visible = ready
	streakClaim.Text = "Claim $ " .. Config.streakReward(d)
	local cycleStart = ((d - 1) // 7) * 7
	for i, t in streakTiles do
		local day = cycleStart + i
		t.day.Text = "Day " .. day
		t.amt.Text = "$" .. Config.streakReward(day)
		if day < d or (day == d and not ready) then
			t.frame.BackgroundColor3 = Theme.tint(C.Mint, 0.75)
			t.stroke.Color = C.Mint
			t.mark.Text = "✓"
		elseif day == d then
			t.frame.BackgroundColor3 = C.Card
			t.stroke.Color = C.Sun
			t.mark.Text = "today"
			t.mark.TextColor3 = Color3.fromRGB(210, 150, 20)
		else
			t.frame.BackgroundColor3 = C.Card
			t.stroke.Color = C.Line
			t.mark.Text = ""
		end
	end
	local allClaimed = #profile.daily.quests > 0
	for i, r in questRows do
		local q = profile.daily.quests[i]
		r.row.Visible = q ~= nil
		if q then
			local def = Config.questDef(q.k)
			r.title.Text = Config.questText(q.k, q.n)
			r.row:FindFirstChild("Dot").Glyph.Text = def and def.Icon or "?"
			r.blurb.Text = string.format("%d / %d", q.p, q.n)
			r.fill.Size = UDim2.fromScale(q.p / q.n, 1)
			local amount = Config.questReward(profile, q.t)
			if q.c then
				setBuy(r.buy, "Done", "done", C.Sky)
				r.fill.BackgroundColor3 = C.Mint
			elseif q.p >= q.n then
				setBuy(r.buy, "Claim $ " .. amount, "afford", C.Sky)
				r.fill.BackgroundColor3 = C.Mint
			else
				setBuy(r.buy, "$ " .. amount, "poor", C.Sky)
				r.fill.BackgroundColor3 = C.Sky
			end
			allClaimed = allClaimed and q.c
		end
	end
	local bonus = Config.questBonus(profile)
	if profile.daily.bonus then
		setBuy(bonusRow.buy, "Done", "done", C.Sun)
	elseif allClaimed then
		setBuy(bonusRow.buy, "Claim $ " .. bonus, "afford", C.Sun)
	else
		setBuy(bonusRow.buy, "$ " .. bonus, "poor", C.Sun)
	end
	local done = 0
	for _, q in profile.daily.quests do
		if q.c then
			done += 1
		end
	end
	questsSub.Text = string.format("%d of %d done today", done, #profile.daily.quests)
end

local function questsBadgeOn(): boolean
	if not profile or not profile.daily then
		return false
	end
	if player:GetAttribute("StreakReady") or (player:GetAttribute("QuestsClaimable") or 0) > 0 then
		return true
	end
	local all = #profile.daily.quests > 0
	for _, q in profile.daily.quests do
		all = all and q.c
	end
	return all and not profile.daily.bonus
end

----------------------------------------------------------------------------------------------
-- Overtime panel: clock in (rebirth) + token perks

local OT = T.Overtime
local otTitle, otLine1, otLine2, otButton, otTokens
local perkRows = {}
local confirmUntil = 0
do
	local card = new("Frame", { Name = "ClockIn", LayoutOrder = 1, Size = UDim2.new(1, 0, 0, px(132)), BackgroundColor3 = Theme.tint(C.Rose, 0.85), ZIndex = 12, Parent = overtimeBody }, { corner(16) })
	otTitle = text({ Position = UDim2.fromOffset(16, px(12)), Size = UDim2.new(1, -px(200), 0, px(24)), TextScaled = false, TextSize = px(20), TextXAlignment = Enum.TextXAlignment.Left, Text = "Overtime", ZIndex = 13, Parent = card }, "Title")
	otLine1 = text({ Position = UDim2.fromOffset(16, px(40)), Size = UDim2.new(1, -px(200), 0, px(18)), TextScaled = false, TextSize = px(15), TextXAlignment = Enum.TextXAlignment.Left, Text = "", TextColor3 = Color3.fromRGB(40, 160, 110), ZIndex = 13, Parent = card }, "Title")
	otLine2 = text({ Position = UDim2.fromOffset(16, px(64)), Size = UDim2.new(1, -32, 0, px(60)), TextScaled = false, TextSize = px(14), TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top, Text = "", TextColor3 = C.Sub, ZIndex = 13, Parent = card }, "Bold")
	otButton = button({ Name = "ClockInButton", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -14, 0, px(12)), Size = UDim2.fromOffset(px(170), px(44)), BackgroundColor3 = C.Rose, TextScaled = false, TextSize = px(16), Text = "Clock in", ZIndex = 13, Parent = card, Radius = 22 })
	otButton.Activated:Connect(function()
		if not profile then
			return
		end
		if os.clock() > confirmUntil then
			-- first tap arms it; resetting coins needs a second tap
			if profile.coins >= Config.overtimeCost(profile.overtime) and profile.wings[OT.NeedsWing] then
				confirmUntil = os.clock() + 4
				otButton.Text = "Tap again to confirm"
				task.delay(4.1, function()
					if os.clock() > confirmUntil then
						Hud.refresh()
					end
				end)
				return
			end
		end
		confirmUntil = 0
		local ok, msg = Remotes.ClockIn:InvokeServer()
		Hud.toast(msg, ok and "good" or "warn")
		if ok then
			CreatureView.playUi(CreatureView.SOUNDS.Pop, 0.9, 0.9)
		end
	end)
	otTokens = text({ LayoutOrder = 2, Size = UDim2.new(1, 0, 0, px(22)), TextScaled = false, TextSize = px(14), TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = C.Sub, Text = "PERKS", ZIndex = 12, Parent = overtimeBody }, "Title")
	for i, d in OT.Perks do
		local r = row(overtimeBody, 2 + i, C.Rose, d.Icon, d.Name, d.Blurb)
		r.row.Name = "Perk_" .. d.Id
		r.buy.Name = "Buy"
		r.buy.Activated:Connect(function()
			local ok, msg = Remotes.BuyPerk:InvokeServer(d.Id)
			Hud.toast(msg, ok and "good" or "warn")
			if ok then
				CreatureView.playUi(CreatureView.SOUNDS.Pop, 0.6, 1.5)
			end
		end)
		perkRows[d.Id] = r
	end
end

local function refreshOvertime()
	if not profile or profile.overtime == nil then
		return
	end
	local n = profile.overtime
	local cost = Config.overtimeCost(n)
	local unlocked = profile.wings[OT.NeedsWing] == true
	overtimeBtn.Parent.Visible = unlocked or n > 0
	otTitle.Text = n > 0 and string.format("Overtime · Level %d", n) or "Clock in for Overtime"
	otLine1.Text = string.format("Coins +%d%% forever  →  +%d%% after the next one", math.floor(OT.CoinBonus * n * 100 + 0.5), math.floor(OT.CoinBonus * (n + 1) * 100 + 0.5))
	otLine2.Text = string.format("Needs $ %s (you have $ %s).\nResets: coins, tip jar, Sneakers and Steady Hands.\nKeeps: Index, shelves, wings, buddies, trails, Padded Shoes. You also get 1 token for perks.", fmt(cost), fmt(profile.coins))
	local can = unlocked and profile.coins >= cost
	if os.clock() > confirmUntil then
		if not unlocked then
			setBuy(otButton, "Open the Toy Barn", "poor", C.Rose)
		else
			setBuy(otButton, can and "Clock in" or ("$ " .. fmt(cost)), can and "afford" or "poor", C.Rose)
		end
	end
	otTokens.Text = string.format("PERKS  ·  %d token%s", profile.tokens, profile.tokens == 1 and "" or "s")
	local anyPerk = false
	for _, d in OT.Perks do
		local r = perkRows[d.Id]
		local lvl = Config.perk(profile, d.Id)
		r.title.Text = string.format("%s  ·  %d/%d", d.Name, lvl, d.Max)
		if lvl >= d.Max then
			setBuy(r.buy, "MAX", "done", C.Rose)
		else
			local c = lvl + 1
			local ok = profile.tokens >= c
			anyPerk = anyPerk or ok
			setBuy(r.buy, string.format("%d token%s", c, c == 1 and "" or "s"), ok and "afford" or "poor", C.Rose)
		end
	end
	overtimeSub.Text = n > 0 and string.format("Level %d · coins +%d%%", n, math.floor(OT.CoinBonus * n * 100 + 0.5)) or "Start over stronger"
	overtimeBadge.Visible = can or anyPerk
end

----------------------------------------------------------------------------------------------
-- Reveal card

local REVEAL_SIZE = UDim2.fromOffset(px(320), px(370))
local reveal = card({
	Name = "Reveal",
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = REVEAL_SIZE,
	Visible = false,
	ZIndex = 20,
	Parent = gui,
}, 28)
local revealBurst = new("Frame", {
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.4),
	Size = UDim2.fromScale(0.78, 0.6),
	SizeConstraint = Enum.SizeConstraint.RelativeXX,
	BackgroundColor3 = Theme.tint(C.Sun, 0.6),
	ZIndex = 20,
	Parent = reveal,
}, { new("UICorner", { CornerRadius = UDim.new(0.5, 0) }) })
local revealVfHolder = new("Frame", {
	BackgroundTransparency = 1,
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.4),
	Size = UDim2.fromScale(1, 0.66),
	ZIndex = 21,
	Parent = reveal,
})
local revealName = text({
	Position = UDim2.new(0, 12, 0.74, 0),
	Size = UDim2.new(1, -24, 0, px(28)),
	TextScaled = false,
	TextSize = px(24),
	Text = "???",
	ZIndex = 22,
	Parent = reveal,
}, "Title")
local revealSub = text({
	Position = UDim2.new(0, 12, 0.74, px(32)),
	Size = UDim2.new(1, -24, 0, px(20)),
	TextScaled = false,
	TextSize = px(16),
	Text = "",
	TextColor3 = C.Sub,
	ZIndex = 22,
	Parent = reveal,
}, "Bold")
local revealNew = text({
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.new(0.84, 0, 0.08, 0),
	Size = UDim2.fromOffset(px(76), px(32)),
	Rotation = 10,
	BackgroundTransparency = 0,
	BackgroundColor3 = C.Rose,
	TextScaled = false,
	TextSize = px(17),
	Text = "NEW",
	TextColor3 = Color3.new(1, 1, 1),
	Visible = false,
	ZIndex = 23,
	Parent = reveal,
	Children = { new("UICorner", { CornerRadius = UDim.new(0.5, 0) }) },
}, "Title")

local revealToken = 0
function Hud.reveal(data)
	revealToken += 1
	local token = revealToken
	local sp = Creatures.Species[data.species]
	for _, c in revealVfHolder:GetChildren() do
		c:Destroy()
	end
	local vf = portrait(data.species, UDim2.fromScale(0.86, 0.86), true, revealVfHolder)
	vf.AnchorPoint = Vector2.new(0.5, 0.5)
	vf.Position = UDim2.fromScale(0.5, 0.5)
	vf.ZIndex = 21
	local scale = new("UIScale", { Scale = 0.6, Parent = vf })
	local jumbo = data.form == "Jumbo"
	reveal.Visible = true
	reveal.Size = UDim2.fromOffset(10, 10)
	revealName.Text = (data.rarity == "Rare" and "★ " or "") .. sp.Family .. " family…"
	revealSub.Text = "?"
	revealNew.Visible = false
	revealBurst.BackgroundColor3 = Theme.tint(data.rarity == "Rare" and C.Sun or C.Sky, 0.7)
	TweenService:Create(reveal, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Size = REVEAL_SIZE }):Play()
	CreatureView.playUi(CreatureView.SOUNDS.Twitch, 0.6, 1.2)
	-- the silhouette wobbles and grows, then pops into colour and settles with a gentle sway
	local t0 = os.clock()
	local target = jumbo and 1.12 or 1
	local spin
	spin = RunService.RenderStepped:Connect(function(dt)
		local k = os.clock() - t0
		if k < 0.75 then
			vf.Rotation = math.sin(k * 34) * (14 - k * 10)
			scale.Scale = 0.6 + k * 0.4
		else
			vf.Rotation = math.sin(k * 2.2) * 4
			scale.Scale += (target - scale.Scale) * (1 - math.exp(-10 * dt))
		end
		if revealToken ~= token then
			spin:Disconnect()
		end
	end)
	task.wait(0.75)
	if revealToken ~= token then
		return
	end
	setSilhouette(vf, false)
	if data.form == "Glazed" then
		vf.ImageColor3 = Color3.fromRGB(255, 245, 200)
	end
	scale.Scale = target * 1.15
	revealBurst.BackgroundColor3 = Theme.tint(data.form == "Normal" and C.Mint or C.Sun, 0.55)
	TweenService:Create(revealBurst, TweenInfo.new(0.5), { BackgroundColor3 = Theme.tint(data.form == "Normal" and C.Mint or C.Sun, 0.8) }):Play()
	revealName.Text = (data.form ~= "Normal" and (data.form .. " ") or "") .. sp.Name
	local sub = "+ " .. fmt(data.coins) .. " coins"
	if data.wanted then
		sub ..= "  ·  WANTED x" .. T.Events.WantedMult .. "!"
	elseif data.rush then
		sub ..= "  ·  Snack Rush"
	end
	if data.evo and not data.evo.evolved then
		sub ..= string.format("  ·  evolution %d/%d", data.evo.count, data.evo.needed)
	end
	revealSub.Text = sub
	revealNew.Visible = data.isNew
	CreatureView.playUi(CreatureView.SOUNDS.Pop, 0.7, 1.6)
	CreatureView.playUi("rbxasset://sounds/action_jump.mp3", 0.6, 2)
	if data.isNew then
		newBadge.Visible = true
	end
	task.wait(2.2)
	if revealToken ~= token then
		return
	end
	if data.evo and data.evo.evolved then
		-- second beat: the buddy evolves
		for _, c in revealVfHolder:GetChildren() do
			c:Destroy()
		end
		local vf2 = portrait(data.evo.to, UDim2.fromScale(0.86, 0.86), false, revealVfHolder)
		vf2.AnchorPoint = Vector2.new(0.5, 0.5)
		vf2.Position = UDim2.fromScale(0.5, 0.5)
		vf2.ZIndex = 21
		revealBurst.BackgroundColor3 = Theme.tint(C.Sun, 0.5)
		revealName.Text = "Evolved: " .. Creatures.Species[data.evo.to].Name
		revealSub.Text = "Your buddy levelled up"
		revealNew.Visible = true
		newBadge.Visible = true
		CreatureView.playUi(CreatureView.SOUNDS.Pop, 0.8, 1.1)
		task.wait(2.6)
		if revealToken ~= token then
			return
		end
	end
	TweenService:Create(reveal, TweenInfo.new(0.2), { Size = UDim2.fromOffset(10, 10) }):Play()
	task.wait(0.2)
	if revealToken == token then
		reveal.Visible = false
	end
end

----------------------------------------------------------------------------------------------
-- Sprint

local sprinting = false
local function setSprint(on: boolean)
	if sprinting == on then
		return
	end
	sprinting = on
	Remotes.Sprint:FireServer(on)
	Hud.updateSprintButton()
end

local sprintBtn = button({
	Name = "Sprint",
	AnchorPoint = Vector2.new(1, 1),
	Position = small and UDim2.new(1, -112, 1, -24) or UDim2.new(1, -200, 1, -60),
	Size = UDim2.fromOffset(px(84), px(84)),
	BackgroundColor3 = C.Card,
	TextColor3 = C.Ink,
	TextScaled = false,
	TextSize = px(17),
	Text = "RUN",
	Visible = isTouch,
	Parent = gui,
	Radius = 42,
	Children = { stroke(C.Peach, 3) },
})
function Hud.updateSprintButton()
	sprintBtn.BackgroundColor3 = sprinting and C.Peach or C.Card
	sprintBtn.TextColor3 = sprinting and Color3.new(1, 1, 1) or C.Ink
	sprintBtn.Text = sprinting and "RUNNING" or "RUN"
end
sprintBtn.Activated:Connect(function()
	setSprint(not sprinting)
end)
local pcSprintHint = text({
	AnchorPoint = Vector2.new(1, 1),
	Position = UDim2.new(1, -14, 1, -14),
	Size = UDim2.fromOffset(170, 30),
	BackgroundTransparency = 0,
	BackgroundColor3 = C.Card,
	TextScaled = false,
	TextSize = 14,
	TextColor3 = C.Sub,
	Text = "Hold SHIFT to run",
	Visible = not isTouch,
	Parent = gui,
	Children = { corner(15) },
}, "Bold")

ContextActionService:BindAction("BrainrotSprint", function(_, state)
	if state == Enum.UserInputState.Begin then
		setSprint(true)
	elseif state == Enum.UserInputState.End or state == Enum.UserInputState.Cancel then
		setSprint(false)
	end
	return Enum.ContextActionResult.Pass
end, false, Enum.KeyCode.LeftShift, Enum.KeyCode.RightShift, Enum.KeyCode.ButtonL3)

-- Test hook for automated playtests.
Hud.setSprint = setSprint

----------------------------------------------------------------------------------------------
-- Guidance beam (first rescues and new goals)

local beamA0 = Instance.new("Attachment")
local beamA1 = Instance.new("Attachment")
local guide = Instance.new("Beam")
guide.Attachment0 = beamA0
guide.Attachment1 = beamA1
guide.Width0 = 1.2
guide.Width1 = 1.2
guide.FaceCamera = true
guide.LightEmission = 0.6
guide.Texture = "rbxasset://textures/particles/sparkles_main.dds"
guide.TextureMode = Enum.TextureMode.Static
guide.TextureLength = 3
guide.TextureSpeed = 2
guide.Transparency = NumberSequence.new(0.2, 0.7)
guide.Enabled = false
local beamAnchor = Instance.new("Part")
beamAnchor.Anchored = true
beamAnchor.CanCollide = false
beamAnchor.CanQuery = false
beamAnchor.Transparency = 1
beamAnchor.Size = Vector3.new(0.2, 0.2, 0.2)
beamAnchor.Parent = workspace
beamA1.Parent = beamAnchor
guide.Parent = beamAnchor

----------------------------------------------------------------------------------------------
-- Refresh (profile-driven)

local function evoLine(e): string
	local fromName = Creatures.Species[e.From].Name
	local toName = Creatures.Species[e.To].Name
	if profile.collection[e.To] then
		return "✓  " .. toName .. " evolved"
	end
	local n = profile.evo[e.To] or 0
	local dots = string.rep("●", n) .. string.rep("○", e.Needed - n)
	if profile.buddy == e.From then
		return string.format("%s  %s → %s: carry rescues through %s", dots, fromName, toName, e.RouteName)
	elseif profile.collection[e.From] then
		return string.format("%s  %s → %s: make %s your buddy first", dots, fromName, toName, fromName)
	end
	return string.format("%s  %s → %s: rescue a %s first", dots, fromName, toName, fromName)
end

function Hud.refresh()
	if not profile then
		return
	end
	coinsText.Text = fmt(profile.coins)
	local found, total = 0, 0
	local perWing = {}
	for _, sp in Creatures.ordered() do
		total += 1
		local entry = profile.collection[sp.Id]
		local card = cards[sp.Id]
		perWing[sp.Wing] = perWing[sp.Wing] or { 0, 0 }
		perWing[sp.Wing][2] += 1
		if entry then
			found += 1
			perWing[sp.Wing][1] += 1
			setSilhouette(card.vf, false)
			card.name.Text = sp.Name
			local forms = {}
			for _, f in T.Forms do
				table.insert(forms, entry.forms[f.Id] and "●" or "○")
			end
			card.info.Text = "×" .. entry.count .. "   " .. table.concat(forms, " ")
			card.equip.Visible = true
			local isBuddy = profile.buddy == sp.Id
			card.equip.Text = isBuddy and "Buddy ✓" or "Make buddy"
			card.equip.BackgroundColor3 = isBuddy and C.Sun or C.Mint
		else
			setSilhouette(card.vf, true)
			card.name.Text = "???"
			card.info.Text = sp.EvolvesFrom and "evolves…" or (sp.Family .. " family")
			card.equip.Visible = false
		end
	end
	for id, h in wingHeaders do
		local w = Config.Wings[id]
		local c = perWing[id] or { 0, 0 }
		h.Text = string.format("%s   %d/%d%s", string.upper(w.Name), c[1], c[2], profile.wings[id] and "" or "   ·  locked")
	end
	indexSub.Text = string.format("Found %d of %d", found, total)
	for _, e in T.Evolutions do
		evoLines[e.To].Text = evoLine(e)
	end

	-- shop
	local anyAfford = false
	for id, def in T.Tracks do
		local r = shopRows[id]
		local lvl = profile.tracks[id] or 0
		local price = def.Costs[lvl + 1]
		local pips = string.rep("●", lvl) .. string.rep("○", #def.Costs - lvl)
		local sp = Config.speeds(profile.tracks.Sneakers or 0, profile.tracks.SteadyHands or 0)
		local stat = id == "Sneakers" and string.format("run %d", sp.sprint) or string.format("careful walk %.1f", sp.carryWalk)
		r.title.Text = string.format("%s  ·  Lv %d", def.Name, lvl)
		r.blurb.Text = def.Blurb .. "\n" .. pips .. "   " .. stat
		if price then
			local can = profile.coins >= price
			anyAfford = anyAfford or can
			setBuy(r.buy, "$ " .. fmt(price), can and "afford" or "poor", r.accent)
		else
			setBuy(r.buy, "MAX", "done", r.accent)
		end
	end
	for id, def in T.Shop do
		local r = shopRows[id]
		if profile.upgrades[id] then
			setBuy(r.buy, "Owned", "done", r.accent)
		else
			local can = profile.coins >= def.Price
			anyAfford = anyAfford or can
			setBuy(r.buy, "$ " .. fmt(def.Price), can and "afford" or "poor", r.accent)
		end
	end
	for _, w in Config.wingList() do
		local r = shopRows[w.Id]
		if r then
			if profile.wings[w.Id] then
				setBuy(r.buy, "Open", "done", r.accent)
			else
				local can = profile.coins >= w.Price
				anyAfford = anyAfford or can
				setBuy(r.buy, "$ " .. fmt(w.Price), can and "afford" or "poor", r.accent)
			end
		end
	end
	shopBadge.Visible = anyAfford
	refreshShelves()
	refreshQuests()
	refreshPages()
	refreshOvertime()
	if collection.Visible then
		newBadge.Visible = false
	end
end

----------------------------------------------------------------------------------------------
-- Per-frame

local SURFACE_HINT = {
	Loud = "loud floor",
	Dance = "loud floor",
	Shelter = "cosy, settling down",
	Vent = "muffled vent",
	Quiet = "",
}
local STAGE_COLORS = { C.Mint, C.Sun, C.Peach, C.Coral, C.Coral }
local STAGE_TITLES = { "Sleeping soundly", "Twitching…", "Squirming!", "One eye open!", "Awake!" }

local function carriedPart(): BasePart?
	local id = player:GetAttribute("Carrying")
	if not id then
		return nil
	end
	local f = workspace:FindFirstChild("Sleepers")
	return f and f:FindFirstChild("Sleeper_" .. id) :: BasePart?
end

local function nearestSleeper(pos: Vector3): BasePart?
	local f = workspace:FindFirstChild("Sleepers")
	if not f then
		return nil
	end
	local best, bd = nil, math.huge
	for _, p in f:GetChildren() do
		local wing = p:GetAttribute("Wing") or "FoodCourt"
		if p:GetAttribute("State") ~= "Carried" and (not profile or profile.wings[wing]) then
			local d = (p.Position - pos).Magnitude
			if d < bd then
				best, bd = p, d
			end
		end
	end
	return best
end

local stationPos = Vector3.new(0, 0.5, -4)
local padParts: { [string]: BasePart } = {}
local onPad: string? = nil

local function updateSaveStatus(now: number)
	local mode = player:GetAttribute("SaveMode")
	if mode == "Loading" then
		saveLabel.Text = "loading your save…"
		saveLabel.TextColor3 = C.Sub
		saveLabel.TextTransparency = 0
	elseif mode == "Session" or mode == "Failed" then
		saveLabel.Text = "progress is not saving here"
		saveLabel.TextColor3 = C.Peach
		saveLabel.TextTransparency = 0
	elseif mode == "Retrying" then
		saveLabel.Text = "save failed, retrying…"
		saveLabel.TextColor3 = C.Peach
		saveLabel.TextTransparency = 0
	elseif mode == "Cloud" then
		local age = now - (player:GetAttribute("LastSave") or 0)
		saveLabel.Text = "✓ saved"
		saveLabel.TextColor3 = Color3.fromRGB(60, 170, 120)
		saveLabel.TextTransparency = math.clamp((age - 2) / 1, 0, 1)
	else
		saveLabel.Text = ""
	end
end

local function updateRare(now: number)
	local soonest, soonestWing = math.huge, nil
	-- the wing you're standing in comes first
	local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local here = hrp and Config.wingAt(hrp.Position) or "FoodCourt"
	local list = Config.wingList()
	table.sort(list, function(a, b)
		return (a.Id == here and 0 or a.Order) < (b.Id == here and 0 or b.Order)
	end)
	for _, w in list do
		if not profile or profile.wings[w.Id] then
			if workspace:GetAttribute("RareActive_" .. w.Id) then
				rareText.Text = "Rare on " .. w.RareStageName .. "!"
				rareDot.BackgroundColor3 = C.Sun
				return
			end
			local at = workspace:GetAttribute("RareAt_" .. w.Id) or math.huge
			if at < soonest then
				soonest, soonestWing = at, w
			end
		end
	end
	rareDot.BackgroundColor3 = C.Lilac
	if soonestWing then
		local left = math.max(0, soonest - now)
		rareText.Text = string.format("Rare in %d:%02d", left // 60, left % 60)
	else
		rareText.Text = "Rare soon"
	end
end

local function updateEvent(now: number)
	local wing = workspace:GetAttribute("RushWing")
	local untilT = workspace:GetAttribute("RushUntil") or 0
	if wing and now < untilT then
		local w = Config.Wings[wing]
		local left = untilT - now
		eventText.Text = string.format("Snack Rush · %s %d:%02d", w and w.Name or wing, left // 60, left % 60)
		eventDot.BackgroundColor3 = C.Coral
	else
		local left = math.max(0, (workspace:GetAttribute("RushNextAt") or now) - now)
		eventText.Text = string.format("Snack Rush in %d:%02d", left // 60, left % 60)
		eventDot.BackgroundColor3 = C.Peach
	end
end

local function setHint(msg: string?, color: Color3?)
	hint.Visible = msg ~= nil
	if msg then
		hintText.Text = msg
		hintDot.BackgroundColor3 = color or C.Sky
		local w = math.min(560, math.max(260, #msg * px(8) + 70))
		hint.Size = UDim2.fromOffset(w, px(36))
	end
end

local function frame()
	local now = workspace:GetServerTimeNow()
	updateJarText()
	questsBadge.Visible = questsBadgeOn()
	if (player:GetAttribute("PagesClaimable") or 0) > 0 then
		newBadge.Visible = true
	end
	if quests.Visible then
		local left = 86400 - os.time() % 86400
		questsFooter.Text = string.format("New quests in %dh %02dm (00:00 UTC)", left // 3600, (left % 3600) // 60)
		if streakClaim.Visible ~= (player:GetAttribute("StreakReady") == true) then
			refreshQuests()
		end
	end
	shelvesBadge.Visible = (player:GetAttribute("Jar") or 0) >= 10 or ((player:GetAttribute("IncomeRate") or 0) <= 0 and profile ~= nil and next(profile.collection) ~= nil)
	updateSaveStatus(now)
	updateRare(now)
	updateEvent(now)
	local part = carriedPart()
	meter.Visible = part ~= nil
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if part then
		local wake = part:GetAttribute("Wake") or 0
		local stage = part:GetAttribute("Stage") or 0
		barFill.Size = UDim2.fromScale(wake / 100, 1)
		barFill.BackgroundColor3 = STAGE_COLORS[stage + 1]
		meterTitle.Text = STAGE_TITLES[stage + 1]
		meterTitle.TextColor3 = stage >= 2 and C.Coral or C.Ink
		local surf = part:GetAttribute("Surface") or "Quiet"
		local s = SURFACE_HINT[surf] or ""
		if s == "" and sprinting then
			s = "running makes noise"
		end
		meterSurface.Text = s
		if stage >= 3 then
			meter.Position = METER_POS + UDim2.fromOffset(math.sin(os.clock() * 40) * 3, 0)
		else
			meter.Position = METER_POS
		end
	end

	-- walk-in pads in the hideout
	if hrp then
		local here = nil
		for name, p in padParts do
			local d = (p.Position - hrp.Position) * Vector3.new(1, 0, 1)
			if d.Magnitude < 3.6 and math.abs(p.Position.Y - hrp.Position.Y) < 5 then
				here = name
			end
		end
		if here ~= onPad then
			onPad = here
			if here == "Jar" then
				task.spawn(function()
					local ok, msg = Remotes.Collect:InvokeServer()
					if ok then
						Hud.toast(msg, "good")
						CreatureView.playUi(CreatureView.SOUNDS.Pop, 0.6, 1.6)
					elseif (player:GetAttribute("IncomeRate") or 0) <= 0 then
						Hud.toast("Put creatures on your shelves to fill the tip jar", "info")
					end
				end)
			elseif here then
				openPanel(here == "Shop" and "Shop" or "Collection")
			end
		end
	end

	-- hints + guidance beam
	local rescues = profile and profile.rescues or 0
	local msg, color = nil, nil
	local beamTarget: Vector3? = nil
	if part then
		if rescues < 3 then
			msg = "Walk it to the pink pad in your HIDEOUT. Running makes noise!"
			color = C.Rose
			beamTarget = stationPos
		end
	elseif rescues == 0 and hrp then
		local n = nearestSleeper(hrp.Position)
		if n then
			msg = "Sneak up to a sleeping creature and grab it"
			beamTarget = n.Position
		end
	elseif profile then
		local tracks = profile.tracks
		local nextWing = nil
		for _, w in Config.wingList() do
			if not profile.wings[w.Id] then
				nextWing = w
				break
			end
		end
		if profile.overtime == 0 and profile.wings[T.Overtime.NeedsWing] and profile.coins >= Config.overtimeCost(0) then
			msg, color = "You can clock in for Overtime: coins +25% forever. Open Overtime", C.Rose
		elseif (player:GetAttribute("PagesClaimable") or 0) > 0 then
			msg, color = "An Index page is complete! Claim your reward in the Index", C.Lilac
		elseif (player:GetAttribute("QuestsClaimable") or 0) > 0 then
			msg, color = "A quest is done! Open Quests to claim your coins", C.Sky
		elseif (player:GetAttribute("Jar") or 0) >= 25 and rescues >= 1 then
			msg, color = string.format("Your tip jar has %s coins! Step on it in the hideout", fmt(player:GetAttribute("Jar"))), C.Sun
		elseif (player:GetAttribute("IncomeRate") or 0) <= 0 and next(profile.collection) ~= nil then
			msg, color = "Put creatures on your Shelves: they earn coins, even while you're away", C.Mint
		elseif (tracks.Sneakers or 0) == 0 and profile.coins >= T.Tracks.Sneakers.Costs[1] then
			msg, color = "You can afford Sneakers! Open the Shop to run faster", C.Peach
		elseif not profile.upgrades.PaddedShoes and profile.coins >= T.Shop.PaddedShoes.Price then
			msg, color = "Padded Shoes are in the Shop: quieter running while carrying", C.Peach
		elseif nextWing and profile.coins >= nextWing.Price then
			msg, color = string.format("The %s can be unlocked! %s", string.upper(nextWing.Name), nextWing.Where or ""), C.Lilac
		elseif profile.collection.CrabRangoon and not profile.buddy and rescues < 8 then
			msg, color = "Open the Index and make Crab Rangoon your buddy (it opens vents)", C.Mint
		end
	end
	setHint(msg, color)
	if beamTarget and hrp then
		beamA0.Parent = hrp
		beamA0.Position = Vector3.new(0, -2, 0)
		beamAnchor.Position = beamTarget + Vector3.new(0, 0.5, 0)
		guide.Enabled = true
		guide.Color = ColorSequence.new(part and C.Rose or C.Sky)
	else
		guide.Enabled = false
	end
end

function Hud.start()
	local autoOpened = false
	local function maybeAutoOpen()
		if autoOpened or not profile or not player:GetAttribute("StreakReady") then
			return
		end
		autoOpened = true
		task.delay(1.5, function()
			if not reveal.Visible then
				openPanel("Quests")
			end
		end)
	end
	Remotes.Profile.OnClientEvent:Connect(function(p)
		profile = p
		Hud.refresh()
		maybeAutoOpen()
	end)
	player:GetAttributeChangedSignal("StreakReady"):Connect(function()
		if player:GetAttribute("StreakReady") then
			autoOpened = false -- a new day while playing: offer the reward again
			maybeAutoOpen()
		end
	end)
	Remotes.Toast.OnClientEvent:Connect(function(msg, kind)
		Hud.toast(msg, kind)
		if kind == "alert" then
			CreatureView.playUi(CreatureView.SOUNDS.Eye, 0.6, 1.1)
		end
	end)
	Remotes.Reveal.OnClientEvent:Connect(function(data)
		task.spawn(Hud.reveal, data)
	end)
	task.spawn(function()
		local p = Remotes.GetProfile:InvokeServer()
		if p then
			profile = p
			Hud.refresh()
		end
	end)
	local hideout = workspace:WaitForChild("Map"):WaitForChild("Hideout")
	local station = hideout:WaitForChild("StationPad")
	stationPos = station.Position
	for _, k in { "Shop", "Index" } do
		local kiosk = hideout:WaitForChild(k .. "Kiosk")
		padParts[k] = kiosk:WaitForChild(k .. "Pad")
	end
	local shelfFolder = hideout:WaitForChild("Shelves")
	padParts.Jar = shelfFolder:WaitForChild("JarPad")
	for _, d in shelfFolder:GetDescendants() do
		if d:IsA("ProximityPrompt") and d.Name == "ShelfPrompt" then
			d.Triggered:Connect(function()
				openPanel("Shelves")
			end)
		end
	end
	RunService.RenderStepped:Connect(frame)
	player.CharacterAdded:Connect(function()
		sprinting = false
		Hud.updateSprintButton()
	end)
end

Hud.getProfile = function()
	return profile
end

return Hud

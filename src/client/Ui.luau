-- Shared UI kit for Wildbound's screens (light minimal look from shared/Theme).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Theme = require(Shared.Theme)

local Ui = {}
local C = Theme.C
Ui.C = C
Ui.Theme = Theme
Ui.new = Theme.new
Ui.corner = Theme.corner
Ui.pad = Theme.pad
Ui.stroke = Theme.stroke
Ui.text = Theme.text
Ui.button = Theme.button

local new, corner, pad, stroke, text, button = Theme.new, Theme.corner, Theme.pad, Theme.stroke, Theme.text, Theme.button
local player = Players.LocalPlayer

Ui.gui = new("ScreenGui", {
	Name = "WildHud",
	ResetOnSpawn = false,
	IgnoreGuiInset = false,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	Parent = player:WaitForChild("PlayerGui"),
})

Ui.small = workspace.CurrentCamera.ViewportSize.X < 900
local S = Ui.small and 0.85 or 1
function Ui.px(n: number): number
	return math.floor(n * S + 0.5)
end
local px = Ui.px

function Ui.fmt(n: number): string
	local s = tostring(math.floor(n))
	local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	return (out:gsub("^,", ""))
end

function Ui.card(props: { [string]: any }, radius: number?)
	props.BackgroundColor3 = props.BackgroundColor3 or C.Card
	local children = props.Children or {}
	local shadow = props.Shadow ~= false -- pass Shadow = false for cards inside list/grid layouts
	props.Children = nil
	props.Shadow = nil
	table.insert(children, corner(radius or 16))
	local f = new("Frame", props, children)
	if shadow then
		Theme.shadow(f, radius or 16, 3)
	else
		Theme.stroke(C.Line, 1.5).Parent = f
	end
	return f
end

function Ui.dot(parent: Instance, color: Color3, glyph: string, size: number, pos: UDim2?, anchor: Vector2?)
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

-- Button state: "afford" (accent), "poor" (grey), "done" (soft mint)
function Ui.setBuy(b: TextButton, label: string, state: string, accent: Color3)
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

----------------------------------------------------------------------------------------------
-- Toasts

-- Toasts get their own top layer so they show above the summon reveal and panels.
local toastGui = new("ScreenGui", {
	Name = "WildToasts",
	DisplayOrder = 60,
	ResetOnSpawn = false,
	IgnoreGuiInset = false,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	Parent = player:WaitForChild("PlayerGui"),
})
local toastHolder = new("Frame", {
	BackgroundTransparency = 1,
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, px(84)),
	Size = UDim2.new(0.8, 0, 0, 200),
	Parent = toastGui,
}, { new("UIListLayout", { HorizontalAlignment = Enum.HorizontalAlignment.Center, Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }) })

local TOAST_COLORS = { info = C.Sky, warn = C.Peach, alert = C.Coral, good = C.Mint }
local TOAST_GLYPH = { info = "i", warn = "!", alert = "!", good = "✓" }
local toastN = 0
function Ui.toast(msg: string, kind: string?)
	toastN += 1
	local k = kind or "info"
	local holder = new("Frame", { LayoutOrder = toastN, BackgroundTransparency = 1, Size = UDim2.new(0, 0, 0, px(38)), AutomaticSize = Enum.AutomaticSize.X, Parent = toastHolder })
	local t = new("Frame", { BackgroundColor3 = C.Card, Size = UDim2.new(0, 0, 1, 0), AutomaticSize = Enum.AutomaticSize.X, Parent = holder }, { corner(19), stroke(TOAST_COLORS[k] or C.Sky, 2) })
	new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, VerticalAlignment = Enum.VerticalAlignment.Center, Padding = UDim.new(0, 8), Parent = t })
	pad(0, 7, 0, 14).Parent = t
	Ui.dot(t, TOAST_COLORS[k] or C.Sky, TOAST_GLYPH[k] or "i", px(24)).LayoutOrder = 1
	local label = text({ LayoutOrder = 2, AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.new(0, 0, 1, 0), TextScaled = false, TextSize = px(16), Text = msg, Parent = t }, "Bold")
	new("UISizeConstraint", { MaxSize = Vector2.new(620, 60), Parent = label })
	task.delay(k == "alert" and 2.5 or 3, function()
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
-- Panels (one open at a time)

Ui.panels = {} :: { [string]: Frame }
Ui.onOpen = {} :: { [string]: () -> () }

function Ui.panel(name: string, title: string, subtitle: string, accent: Color3, glyph: string, wide: boolean?)
	local p = Ui.card({
		Name = name,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.53),
		Size = UDim2.new(Ui.small and 0.92 or (wide and 0.74 or 0.62), 0, Ui.small and 0.84 or 0.76, 0),
		Visible = false,
		ZIndex = 10,
		Parent = Ui.gui,
		Children = { new("UISizeConstraint", { MaxSize = Vector2.new(wide and 900 or 740, 600) }) },
	}, 24)
	Ui.dot(p, accent, glyph, px(40), UDim2.new(0, 18, 0, 18), Vector2.new(0, 0)).ZIndex = 11
	text({ Name = "Title", Position = UDim2.fromOffset(px(68), 16), Size = UDim2.new(1, -150, 0, px(26)), TextScaled = false, TextSize = px(24), TextXAlignment = Enum.TextXAlignment.Left, Text = title, ZIndex = 11, Parent = p }, "Title")
	local sub = text({ Name = "Subtitle", Position = UDim2.fromOffset(px(68), 16 + px(27)), Size = UDim2.new(1, -150, 0, px(16)), TextScaled = false, TextSize = px(14), TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = C.Sub, Text = subtitle, ZIndex = 11, Parent = p }, "Bold")
	local close = button({ Name = "Close", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -16, 0, 16), Size = UDim2.fromOffset(px(38), px(38)), BackgroundColor3 = C.Soft, TextColor3 = C.Sub, TextScaled = false, TextSize = px(18), Text = "X", ZIndex = 11, Parent = p, Radius = 19 })
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
	Ui.panels[name] = p
	return p, body, sub
end

Ui.beforeOpen = nil :: ((string?) -> ())?
function Ui.open(name: string?)
	if name and Ui.beforeOpen then
		Ui.beforeOpen(name)
	end
	for n, p in Ui.panels do
		p.Visible = n == name
	end
	if name and Ui.onOpen[name] then
		Ui.onOpen[name]()
	end
end

function Ui.isOpen(name: string): boolean
	return Ui.panels[name] ~= nil and Ui.panels[name].Visible
end

-- A grey rounded row with an icon dot, a title, a blurb and a button on the right.
function Ui.row(parent: Instance, order: number, accent: Color3, glyph: string, title: string, blurb: string)
	local r = new("Frame", { Name = "Row", LayoutOrder = order, Size = UDim2.new(1, 0, 0, px(78)), BackgroundColor3 = C.Soft, ZIndex = 12, Parent = parent }, { corner(16) })
	Ui.dot(r, Theme.tint(accent, 0.15), glyph, px(48), UDim2.new(0, 14, 0.5, 0)).ZIndex = 13
	local name = text({ Name = "Title", Position = UDim2.fromOffset(px(74), px(14)), Size = UDim2.new(1, -px(74) - px(150), 0, px(22)), TextScaled = false, TextSize = px(19), TextXAlignment = Enum.TextXAlignment.Left, Text = title, ZIndex = 13, Parent = r }, "Title")
	local sub = text({ Name = "Blurb", Position = UDim2.fromOffset(px(74), px(38)), Size = UDim2.new(1, -px(74) - px(150), 0, px(32)), TextScaled = false, TextSize = px(14), TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top, TextColor3 = C.Sub, Text = blurb, ZIndex = 13, Parent = r }, "Bold")
	local buy = button({ Name = "Buy", AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -14, 0.5, 0), Size = UDim2.fromOffset(px(128), px(44)), BackgroundColor3 = accent, TextScaled = false, TextSize = px(16), Text = "", ZIndex = 13, Parent = r, Radius = 22 })
	return { row = r, title = name, blurb = sub, buy = buy, accent = accent }
end

function Ui.section(parent: Instance, order: number, label: string)
	return text({ LayoutOrder = order, Size = UDim2.new(1, 0, 0, px(20)), TextScaled = false, TextSize = px(14), TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = C.Sub, Text = label, ZIndex = 12, Parent = parent }, "Title")
end

----------------------------------------------------------------------------------------------
-- Profile state shared by every screen

Ui.profile = nil :: any
local listeners: { (any) -> () } = {}
function Ui.onProfile(fn: (any) -> ())
	table.insert(listeners, fn)
	if Ui.profile then
		task.spawn(fn, Ui.profile)
	end
end
function Ui.setProfile(p: any)
	Ui.profile = p
	for _, fn in listeners do
		task.spawn(fn, p)
	end
end

-- Invoke a RemoteFunction; toast its message. Returns (ok, msg, extra).
local remotes = game:GetService("ReplicatedStorage"):WaitForChild("Remotes")
local busy: { [string]: boolean } = {}
function Ui.call(name: string, ...): (boolean, string?, any)
	if busy[name] then
		return false, nil, nil
	end
	busy[name] = true
	local ok, a, b, c = pcall(function(...)
		return (remotes:WaitForChild(name) :: RemoteFunction):InvokeServer(...)
	end, ...)
	busy[name] = nil
	if not ok then
		Ui.toast("Something went wrong, try again", "alert")
		return false, nil, nil
	end
	if typeof(b) == "string" and b ~= "" and b ~= "ok" then
		Ui.toast(b, a and "good" or "warn")
	end
	return a, b, c
end

-- A small "slot" image with a rounded frame for a species portrait, tinted for its element.
function Ui.portrait(parent: Instance, sp: string, el: string?, size: UDim2, pos: UDim2?, z: number?)
	local Portraits = require(game:GetService("ReplicatedStorage").Shared.Portraits)
	local Config = require(game:GetService("ReplicatedStorage").Shared.Config)
	local info = el and Config.ElementInfo[el]
	local back = new("Frame", {
		Name = "Portrait",
		Size = size,
		Position = pos or UDim2.new(),
		BackgroundColor3 = info and Theme.tint(info.Color, 0.7) or C.Soft,
		ZIndex = z or 12,
		Parent = parent,
	}, { corner(12) })
	local img = new("ImageLabel", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ScaleType = Enum.ScaleType.Fit, ZIndex = (z or 12) + 1, Parent = back })
	if info then
		img.ImageColor3 = info.Light:Lerp(Color3.new(1, 1, 1), 0.45)
	end
	task.spawn(Portraits.apply, img, sp)
	return back, img
end

return Ui

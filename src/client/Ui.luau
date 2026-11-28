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

-- Phones (2026-11-27 mobile pass). `Ui.mobile` = a touch device without a keyboard, or a
-- small screen. Studio phone preview: set workspace attribute `DebugPhone` before Play; every
-- screen then draws into a phone-sized frame (844 x 390 points, Roblox's top bar and the
-- jump/joystick areas marked) scaled up to fit the window, so layouts can be checked here.
local UIS = game:GetService("UserInputService")
-- the camera reports a 1x1 viewport for the first frames after join: wait for the real size
-- (it decides phone layout and the preview scale)
local vp0 = workspace.CurrentCamera.ViewportSize
do
	local t0 = os.clock()
	while vp0.X < 100 and os.clock() - t0 < 5 do
		task.wait()
		vp0 = workspace.CurrentCamera.ViewportSize
	end
end
Ui.preview = game:GetService("RunService"):IsStudio() and workspace:GetAttribute("DebugPhone") == true
Ui.mobile = Ui.preview or (UIS.TouchEnabled and not UIS.KeyboardEnabled) or math.min(vp0.X, vp0.Y) < 500
Ui.small = Ui.mobile or vp0.X < 900
local PHONE = Vector2.new(844, 390)
local INSET = 58 -- Roblox's top bar on phones

-- Preview roots follow the window: the viewport is still resizing for a while after join.
local previewRoots: { { root: Frame, inset: boolean, scale: UIScale } } = {}
local previewBars: { Frame } = {}
local function placePreview()
	local vp = workspace.CurrentCamera.ViewportSize
	local scale = math.min((vp.X - 20) / PHONE.X, (vp.Y - 20) / PHONE.Y)
	local top = (vp.Y - PHONE.Y * scale) / 2
	local studioInset = game:GetService("GuiService"):GetGuiInset().Y
	for _, r in previewRoots do
		r.scale.Scale = scale
		-- screens that respect the top bar start INSET points lower (Studio's own inset is
		-- subtracted because those screens already start below it)
		r.root.Position = UDim2.new(0.5, 0, 0, r.inset and (top + INSET * scale - studioInset) or top)
	end
	if #previewBars == 4 then
		local pw, ph = PHONE.X * scale, PHONE.Y * scale
		local left = (vp.X - pw) / 2
		previewBars[1].Size = UDim2.new(1, 0, 0, top) -- above
		previewBars[2].Position = UDim2.new(0, 0, 0, top + ph) -- below
		previewBars[2].Size = UDim2.new(1, 0, 1, -(top + ph))
		previewBars[3].Size = UDim2.new(0, left, 1, 0) -- left
		previewBars[4].Position = UDim2.new(0, left + pw, 0, 0) -- right
		previewBars[4].Size = UDim2.new(1, -(left + pw), 1, 0)
	end
end
if Ui.preview then
	workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(placePreview)
end

-- A full-screen frame inside a ScreenGui that every child of that screen goes into. In phone
-- preview it becomes a phone-sized, scaled-up frame.
function Ui.layer(screen: ScreenGui): Frame
	local root = new("Frame", { Name = "Root", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Parent = screen })
	if Ui.preview then
		root.AnchorPoint = Vector2.new(0.5, 0)
		root.Size = UDim2.fromOffset(PHONE.X, screen.IgnoreGuiInset and PHONE.Y or PHONE.Y - INSET)
		root.ClipsDescendants = true
		table.insert(previewRoots, { root = root, inset = not screen.IgnoreGuiInset, scale = new("UIScale", { Parent = root }) })
		placePreview()
	end
	return root
end

-- The size the current layout has to fit (the phone frame in preview).
function Ui.view(insetAware: boolean?): Vector2
	if Ui.preview then
		return Vector2.new(PHONE.X, insetAware and PHONE.Y - INSET or PHONE.Y)
	end
	local v = workspace.CurrentCamera.ViewportSize
	return insetAware and Vector2.new(v.X, v.Y - game:GetService("GuiService"):GetGuiInset().Y) or v
end

Ui.screenGui = new("ScreenGui", {
	Name = "WildHud",
	ResetOnSpawn = false,
	IgnoreGuiInset = false,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	Parent = player:WaitForChild("PlayerGui"),
})
Ui.gui = Ui.layer(Ui.screenGui)

-- The HUD frame (2026-11-27 HUD redesign): every always-on HUD element is laid out once in
-- phone points (a phone landscape screen is ~844 x 332 under Roblox's top bar). On bigger
-- screens the frame is shrunk by 1/k and scaled back up by k, so the same layout fills the
-- screen with everything k times larger. Menus stay in Ui.gui.
Ui.hud = new("Frame", { Name = "Hud", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Parent = Ui.gui })
local hudScale = new("UIScale", { Parent = Ui.hud })
local function placeHud()
	local k = 1
	if not Ui.mobile then
		local v = workspace.CurrentCamera.ViewportSize
		k = math.clamp(math.min(v.X / 1250, v.Y / 650), 1, 1.6)
	end
	hudScale.Scale = k
	Ui.hud.Size = UDim2.fromScale(1 / k, 1 / k)
	Ui.hudScale = k
end
placeHud()
workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(placeHud)

-- Studio preview: a dark backdrop around the phone, Roblox's top bar, the jump button and the
-- joystick drawn as ghosts so nothing gets placed under them
if Ui.preview then
	local back = new("ScreenGui", { Name = "PhonePreview", DisplayOrder = -10, IgnoreGuiInset = true, Parent = player:WaitForChild("PlayerGui") })
	-- four bars around the phone (the phone area itself stays clear); placePreview sizes them
	for _ = 1, 4 do
		table.insert(previewBars, new("Frame", { BackgroundColor3 = Color3.fromRGB(20, 20, 30), BorderSizePixel = 0, Parent = back }))
	end
	local hole = Ui.layer(back)
	new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Parent = hole }, { new("UIStroke", { Color = Color3.new(1, 1, 1), Thickness = 2 }) })
	local over = new("ScreenGui", { Name = "PhoneGhosts", DisplayOrder = 200, IgnoreGuiInset = true, Parent = player:WaitForChild("PlayerGui") })
	local g = Ui.layer(over)
	local function ghost(pos: UDim2, size: Vector2, round: boolean, label: string)
		local f = new("Frame", { Position = pos, Size = UDim2.fromOffset(size.X, size.Y), BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0.55, Parent = g }, round and { new("UICorner", { CornerRadius = UDim.new(0.5, 0) }) } or {})
		new("TextLabel", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Text = label, TextColor3 = Color3.new(1, 1, 1), TextSize = 12, Font = Enum.Font.GothamBold, Parent = f })
	end
	ghost(UDim2.fromOffset(0, 0), Vector2.new(310, INSET), false, "Roblox top bar")
	ghost(UDim2.new(1, -95, 1, -90), Vector2.new(70, 70), true, "Jump")
	ghost(UDim2.new(0, 40, 1, -150), Vector2.new(110, 110), true, "Move")
end

local S = Ui.mobile and 0.74 or (Ui.small and 0.85 or 1)
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
	if props.Active == nil then
		props.Active = true -- a card blocks clicks to whatever is behind it
	end
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
	DisplayOrder = 76, -- toasts show above the hatch screen (72)
	ResetOnSpawn = false,
	IgnoreGuiInset = false,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	Parent = player:WaitForChild("PlayerGui"),
})
-- phones: toasts sit at the bottom centre, between the joystick and the thumb buttons
local toastHolder = new("Frame", {
	BackgroundTransparency = 1,
	AnchorPoint = Ui.mobile and Vector2.new(0.5, 1) or Vector2.new(0.5, 0),
	Position = Ui.mobile and UDim2.new(0.5, -12, 1, -10) or UDim2.new(0.5, 0, 0, px(84)),
	Size = Ui.mobile and UDim2.fromOffset(290, 120) or UDim2.new(0.8, 0, 0, 200),
	Parent = Ui.layer(toastGui),
}, { new("UIListLayout", { HorizontalAlignment = Enum.HorizontalAlignment.Center, VerticalAlignment = Ui.mobile and Enum.VerticalAlignment.Bottom or Enum.VerticalAlignment.Top, Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }) })

local TOAST_COLORS = { info = C.Sky, warn = C.Peach, alert = C.Coral, good = C.Mint }
local TOAST_GLYPH = { info = "i", warn = "!", alert = "!", good = "✓" }
local toastN = 0
function Ui.toast(msg: string, kind: string?)
	-- phones keep only the two newest toasts on screen
	if Ui.mobile then
		local list = {}
		for _, c in toastHolder:GetChildren() do
			if c:IsA("Frame") then
				table.insert(list, c)
			end
		end
		table.sort(list, function(a, b)
			return a.LayoutOrder < b.LayoutOrder
		end)
		for i = 1, #list - 1 do
			list[i]:Destroy()
		end
	end
	toastN += 1
	local k = kind or "info"
	local holder = new("Frame", { LayoutOrder = toastN, BackgroundTransparency = 1, Size = UDim2.new(0, 0, 0, px(38)), AutomaticSize = Ui.mobile and Enum.AutomaticSize.XY or Enum.AutomaticSize.X, Parent = toastHolder })
	local t = new("Frame", { BackgroundColor3 = C.Card, Size = UDim2.new(0, 0, 1, 0), AutomaticSize = Enum.AutomaticSize.X, Parent = holder }, { corner(19), stroke(TOAST_COLORS[k] or C.Sky, 2) })
	new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, VerticalAlignment = Enum.VerticalAlignment.Center, Padding = UDim.new(0, 8), Parent = t })
	pad(0, 7, 0, 14).Parent = t
	Ui.dot(t, TOAST_COLORS[k] or C.Sky, TOAST_GLYPH[k] or "i", px(24)).LayoutOrder = 1
	local label = text({ LayoutOrder = 2, AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.new(0, 0, 1, 0), TextScaled = false, TextSize = px(16), Text = msg, Parent = t }, "Bold")
	new("UISizeConstraint", { MaxSize = Vector2.new(Ui.mobile and 236 or 620, 60), Parent = label })
	if Ui.mobile then
		label.TextSize = 12
		label.TextWrapped = true
		label.AutomaticSize = Enum.AutomaticSize.XY
		t.AutomaticSize = Enum.AutomaticSize.XY
		t.Size = UDim2.fromOffset(0, 30)
	end
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

-- Is any menu open?
function Ui.anyOpen(): boolean
	for _, p in Ui.panels do
		if p.Visible then
			return true
		end
	end
	return false
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

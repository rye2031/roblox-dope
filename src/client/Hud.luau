-- Screen UI: coins, rare timer, wake meter, sprint (Shift / touch button), toasts, reveal card,
-- collection page with silhouettes + evolution goal, and the Padded Shoes shop.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local ContextActionService = game:GetService("ContextActionService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Creatures = require(Shared.Creatures)
local MeshLoader = require(Shared.MeshLoader)
local CreatureView = require(script.Parent.CreatureView)

local T = Config.Tuning
local player = Players.LocalPlayer
local Remotes = ReplicatedStorage:WaitForChild("Remotes")

local Hud = {}

local profile = nil
local FONT = Enum.Font.FredokaOne

local function new(class: string, props: { [string]: any }, children: { Instance }?)
	local i = Instance.new(class)
	for k, v in props do
		if k ~= "Parent" then
			(i :: any)[k] = v
		end
	end
	for _, c in children or {} do
		c.Parent = i
	end
	if props.Parent then
		i.Parent = props.Parent
	end
	return i
end

local function corner(r: number?)
	return new("UICorner", { CornerRadius = UDim.new(0, r or 12) })
end
local function stroke(th: number?, col: Color3?)
	return new("UIStroke", { Thickness = th or 3, Color = col or Color3.fromRGB(30, 20, 50), ApplyStrokeMode = Enum.ApplyStrokeMode.Border })
end
local function textStroke()
	return new("UIStroke", { Thickness = 2, Color = Color3.fromRGB(20, 10, 30) })
end

local gui = new("ScreenGui", {
	Name = "BrainrotHud",
	ResetOnSpawn = false,
	IgnoreGuiInset = false,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	Parent = player:WaitForChild("PlayerGui"),
})

local isTouch = UserInputService.TouchEnabled
local small = workspace.CurrentCamera.ViewportSize.X < 900

----------------------------------------------------------------------------------------------
-- Top bar

local top = new("Frame", {
	Name = "Top",
	BackgroundTransparency = 1,
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 6),
	Size = UDim2.fromOffset(small and 330 or 420, 40),
	Parent = gui,
}, {
	new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Center, Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }),
})

local coinsPill = new("TextLabel", {
	Name = "Coins",
	LayoutOrder = 1,
	Size = UDim2.fromOffset(small and 104 or 130, 38),
	BackgroundColor3 = Color3.fromRGB(255, 205, 60),
	Font = FONT,
	TextScaled = true,
	Text = "💰 0",
	TextColor3 = Color3.new(1, 1, 1),
	Parent = top,
}, { corner(19), stroke(3), textStroke(), new("UIPadding", { PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8), PaddingTop = UDim.new(0, 4), PaddingBottom = UDim.new(0, 4) }) })

local rarePill = new("TextLabel", {
	Name = "Rare",
	LayoutOrder = 2,
	Size = UDim2.fromOffset(small and 214 or 270, 38),
	BackgroundColor3 = Color3.fromRGB(90, 60, 150),
	Font = FONT,
	TextScaled = true,
	Text = "⭐ Rare sleeper soon",
	TextColor3 = Color3.new(1, 1, 1),
	Parent = top,
}, { corner(19), stroke(3), textStroke(), new("UIPadding", { PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8), PaddingTop = UDim.new(0, 5), PaddingBottom = UDim.new(0, 5) }) })

----------------------------------------------------------------------------------------------
-- Wake meter (only while carrying)

-- Bottom centre: the carried creature floats above the player's head, so the top of the
-- screen must stay clear (on a phone the meter used to cover the eye-open telegraph).
local METER_POS = UDim2.new(0.5, 0, 1, small and -10 or -26)
local meter = new("Frame", {
	Name = "WakeMeter",
	AnchorPoint = Vector2.new(0.5, 1),
	Position = METER_POS,
	Size = UDim2.new(small and 0.42 or 0.36, 0, 0, small and 54 or 64),
	BackgroundColor3 = Color3.fromRGB(30, 22, 50),
	BackgroundTransparency = 0.15,
	Visible = false,
	Parent = gui,
}, { corner(14), stroke(3, Color3.fromRGB(255, 255, 255)) })

local meterTitle = new("TextLabel", {
	BackgroundTransparency = 1,
	Position = UDim2.fromOffset(10, 3),
	Size = UDim2.new(1, -20, 0, small and 22 or 24),
	Font = FONT,
	TextScaled = true,
	TextXAlignment = Enum.TextXAlignment.Left,
	Text = "💤 Sleeping soundly",
	TextColor3 = Color3.new(1, 1, 1),
	Parent = meter,
}, { textStroke() })
local meterSurface = new("TextLabel", {
	BackgroundTransparency = 1,
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, -10, 0, 3),
	Size = UDim2.new(0.45, 0, 0, small and 22 or 24),
	Font = FONT,
	TextScaled = true,
	TextXAlignment = Enum.TextXAlignment.Right,
	Text = "",
	TextColor3 = Color3.fromRGB(255, 220, 120),
	Parent = meter,
}, { textStroke() })
local barBack = new("Frame", {
	Position = UDim2.new(0, 10, 1, small and -26 or -28),
	Size = UDim2.new(1, -20, 0, small and 18 or 20),
	BackgroundColor3 = Color3.fromRGB(60, 50, 80),
	Parent = meter,
}, { corner(9) })
local barFill = new("Frame", {
	Size = UDim2.fromScale(0, 1),
	BackgroundColor3 = Color3.fromRGB(120, 230, 140),
	Parent = barBack,
}, { corner(9) })
for _, v in { T.WakeStages.Twitch, T.WakeStages.Squirm, T.WakeStages.EyeOpen } do
	new("Frame", { Position = UDim2.new(v / 100, -1, 0, 0), Size = UDim2.new(0, 2, 1, 0), BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 0.3, BorderSizePixel = 0, ZIndex = 3, Parent = barBack })
end

----------------------------------------------------------------------------------------------
-- Hint line + toasts

local hint = new("TextLabel", {
	Name = "Hint",
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 1, small and -70 or -98),
	Size = UDim2.new(small and 0.5 or 0.42, 0, 0, small and 26 or 30),
	BackgroundColor3 = Color3.fromRGB(20, 14, 34),
	BackgroundTransparency = 0.35,
	Font = FONT,
	TextScaled = true,
	Text = "",
	TextColor3 = Color3.new(1, 1, 1),
	Visible = false,
	Parent = gui,
}, { corner(10), textStroke(), new("UIPadding", { PaddingTop = UDim.new(0, 3), PaddingBottom = UDim.new(0, 3), PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8) }) })

local toastHolder = new("Frame", {
	BackgroundTransparency = 1,
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0.3, 0),
	Size = UDim2.new(0.8, 0, 0, 200),
	Parent = gui,
}, { new("UIListLayout", { HorizontalAlignment = Enum.HorizontalAlignment.Center, Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }) })

local toastN = 0
function Hud.toast(text: string, kind: string?)
	toastN += 1
	local colors = { info = Color3.fromRGB(60, 50, 110), warn = Color3.fromRGB(170, 90, 20), alert = Color3.fromRGB(190, 30, 40), good = Color3.fromRGB(40, 140, 70) }
	local t = new("TextLabel", {
		LayoutOrder = toastN,
		Size = UDim2.new(1, 0, 0, small and 34 or 40),
		BackgroundColor3 = colors[kind or "info"] or colors.info,
		Font = FONT,
		TextScaled = true,
		Text = text,
		TextColor3 = Color3.new(1, 1, 1),
		Parent = toastHolder,
	}, { corner(12), stroke(3), textStroke(), new("UISizeConstraint", { MaxSize = Vector2.new(560, 60) }), new("UIPadding", { PaddingTop = UDim.new(0, 5), PaddingBottom = UDim.new(0, 5), PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10) }) })
	task.delay(kind == "alert" and 2 or 3, function()
		TweenService:Create(t, TweenInfo.new(0.3), { BackgroundTransparency = 1, TextTransparency = 1 }):Play()
		task.wait(0.3)
		t:Destroy()
	end)
end

----------------------------------------------------------------------------------------------
-- Viewport helper

local function viewport(species: string, size: UDim2, silhouette: boolean, parent: Instance)
	local vf = new("ViewportFrame", {
		Size = size,
		BackgroundTransparency = 1,
		Ambient = Color3.fromRGB(200, 200, 210),
		LightColor = Color3.fromRGB(255, 250, 240),
		LightDirection = Vector3.new(-0.4, -1, -0.6),
		ImageColor3 = silhouette and Color3.new(0, 0, 0) or Color3.new(1, 1, 1),
		Parent = parent,
	})
	local sp = Creatures.Species[species]
	local mp = MeshLoader.get(species, 4)
	local part: BasePart
	if mp then
		part = mp
	else
		local ball = Instance.new("Part")
		ball.Shape = Enum.PartType.Ball
		ball.Size = Vector3.new(4, 4, 4)
		ball.Color = sp.Color
		part = ball
	end
	part.CFrame = CFrame.Angles(0, -0.45, 0) -- meshes face -Z; camera sits at -Z, so this is a front 3/4 view
	part.Parent = vf
	local cam = Instance.new("Camera")
	cam.FieldOfView = 30
	cam.CFrame = CFrame.lookAt(Vector3.new(0, 1.2, -9.5), Vector3.new(0, 0, 0))
	cam.Parent = vf
	vf.CurrentCamera = cam
	return vf, part
end

----------------------------------------------------------------------------------------------
-- Modal panels

local function panel(name: string, title: string)
	local p = new("Frame", {
		Name = name,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.52),
		Size = UDim2.new(small and 0.92 or 0.6, 0, small and 0.8 or 0.7, 0),
		BackgroundColor3 = Color3.fromRGB(44, 32, 72),
		Visible = false,
		ZIndex = 10,
		Parent = gui,
	}, { corner(18), stroke(4, Color3.new(1, 1, 1)), new("UISizeConstraint", { MaxSize = Vector2.new(720, 520) }) })
	new("TextLabel", {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(14, 8),
		Size = UDim2.new(1, -70, 0, 36),
		Font = FONT,
		TextScaled = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = title,
		TextColor3 = Color3.new(1, 1, 1),
		ZIndex = 11,
		Parent = p,
	}, { textStroke() })
	local close = new("TextButton", {
		Name = "Close",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -8, 0, 8),
		Size = UDim2.fromOffset(44, 44),
		BackgroundColor3 = Color3.fromRGB(220, 60, 80),
		Font = FONT,
		TextScaled = true,
		Text = "X",
		TextColor3 = Color3.new(1, 1, 1),
		ZIndex = 11,
		Parent = p,
	}, { corner(22), stroke(3) })
	close.Activated:Connect(function()
		p.Visible = false
	end)
	return p
end

local collection = panel("Collection", "📖 Collection")
local shop = panel("Shop", "👟 Shop")

local function sideButton(text: string, order: number, color: Color3, target: Frame)
	local b = new("TextButton", {
		Name = target.Name .. "Button",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 10, 0.42, (order - 1) * (small and 70 or 84)),
		Size = UDim2.fromOffset(small and 62 or 74, small and 62 or 74),
		BackgroundColor3 = color,
		Font = FONT,
		TextScaled = true,
		Text = text,
		TextColor3 = Color3.new(1, 1, 1),
		Parent = gui,
	}, { corner(16), stroke(3), textStroke(), new("UIPadding", { PaddingTop = UDim.new(0, 6), PaddingBottom = UDim.new(0, 6), PaddingLeft = UDim.new(0, 4), PaddingRight = UDim.new(0, 4) }) })
	b.Activated:Connect(function()
		local open = not target.Visible
		collection.Visible = false
		shop.Visible = false
		target.Visible = open
		if open then
			Hud.refresh()
		end
	end)
	return b
end
local collectionBtn = sideButton("📖\nIndex", 1, Color3.fromRGB(80, 140, 255), collection)
local shopBtn = sideButton("👟\nShop", 2, Color3.fromRGB(255, 120, 60), shop)
local newBadge = new("TextLabel", {
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, 6, 0, -6),
	Size = UDim2.fromOffset(24, 24),
	BackgroundColor3 = Color3.fromRGB(255, 50, 80),
	Font = FONT,
	TextScaled = true,
	Text = "!",
	TextColor3 = Color3.new(1, 1, 1),
	Visible = false,
	Parent = collectionBtn,
}, { corner(12) })
local shopBadge = newBadge:Clone()
shopBadge.Parent = shopBtn

-- Collection contents
local evoBox = new("Frame", {
	Position = UDim2.new(0, 14, 1, -84),
	Size = UDim2.new(1, -28, 0, 72),
	BackgroundColor3 = Color3.fromRGB(70, 52, 110),
	ZIndex = 11,
	Parent = collection,
}, { corner(12) })
local evoText = new("TextLabel", {
	BackgroundTransparency = 1,
	Position = UDim2.fromOffset(10, 4),
	Size = UDim2.new(1, -20, 0, 34),
	Font = FONT,
	TextScaled = true,
	TextXAlignment = Enum.TextXAlignment.Left,
	TextColor3 = Color3.new(1, 1, 1),
	ZIndex = 12,
	Parent = evoBox,
}, { textStroke() })
local evoSub = new("TextLabel", {
	BackgroundTransparency = 1,
	Position = UDim2.fromOffset(10, 40),
	Size = UDim2.new(1, -20, 0, 26),
	Font = FONT,
	TextScaled = true,
	TextXAlignment = Enum.TextXAlignment.Left,
	TextColor3 = Color3.fromRGB(255, 220, 120),
	ZIndex = 12,
	Parent = evoBox,
}, { textStroke() })
local foundLabel = new("TextLabel", {
	BackgroundTransparency = 1,
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, -60, 0, 12),
	Size = UDim2.fromOffset(140, 30),
	Font = FONT,
	TextScaled = true,
	TextColor3 = Color3.fromRGB(255, 220, 120),
	ZIndex = 11,
	Parent = collection,
}, { textStroke() })
local grid = new("Frame", {
	Name = "Grid",
	BackgroundTransparency = 1,
	Position = UDim2.fromOffset(14, 56),
	Size = UDim2.new(1, -28, 1, -150),
	ZIndex = 11,
	Parent = collection,
}, { new("UIGridLayout", { CellSize = UDim2.new(0.25, -8, 1, 0), CellPadding = UDim2.fromOffset(8, 8), SortOrder = Enum.SortOrder.LayoutOrder }) })

local cards = {}
for _, sp in Creatures.ordered() do
	local card = new("Frame", {
		Name = "Card_" .. sp.Id,
		LayoutOrder = sp.Order,
		BackgroundColor3 = Color3.fromRGB(64, 48, 100),
		ZIndex = 11,
		Parent = grid,
	}, { corner(12) })
	local vf = viewport(sp.Id, UDim2.new(1, 0, 0.55, 0), true, card)
	vf.ZIndex = 12
	local name = new("TextLabel", {
		BackgroundTransparency = 1,
		Position = UDim2.new(0, 4, 0.55, 0),
		Size = UDim2.new(1, -8, 0.13, 0),
		Font = FONT,
		TextScaled = true,
		Text = "???",
		TextColor3 = Color3.new(1, 1, 1),
		ZIndex = 12,
		Parent = card,
	}, { textStroke() })
	local info = new("TextLabel", {
		BackgroundTransparency = 1,
		Position = UDim2.new(0, 4, 0.68, 0),
		Size = UDim2.new(1, -8, 0.11, 0),
		Font = FONT,
		TextScaled = true,
		Text = "",
		TextColor3 = Color3.fromRGB(200, 190, 230),
		ZIndex = 12,
		Parent = card,
	})
	local equip = new("TextButton", {
		Name = "Equip",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -6),
		Size = UDim2.new(0.9, 0, 0.16, 0),
		BackgroundColor3 = Color3.fromRGB(80, 200, 120),
		Font = FONT,
		TextScaled = true,
		Text = "Buddy",
		TextColor3 = Color3.new(1, 1, 1),
		Visible = false,
		ZIndex = 12,
		Parent = card,
	}, { corner(8), textStroke() })
	equip.Activated:Connect(function()
		local isBuddy = profile and profile.buddy == sp.Id
		local ok, msg = Remotes.Equip:InvokeServer(if isBuddy then nil else sp.Id)
		Hud.toast(msg, ok and "good" or "warn")
	end)
	cards[sp.Id] = { vf = vf, name = name, info = info, equip = equip }
end

-- Shop contents
local shopCard = new("Frame", {
	Name = "ShopCard",
	Position = UDim2.fromOffset(14, 56),
	Size = UDim2.new(1, -28, 0, 150),
	BackgroundColor3 = Color3.fromRGB(64, 48, 100),
	ZIndex = 11,
	Parent = shop,
}, { corner(12) })
new("TextLabel", {
	BackgroundTransparency = 1,
	Position = UDim2.fromOffset(12, 8),
	Size = UDim2.new(1, -24, 0, 40),
	Font = FONT,
	TextScaled = true,
	TextXAlignment = Enum.TextXAlignment.Left,
	Text = "👟 Padded Shoes",
	TextColor3 = Color3.new(1, 1, 1),
	ZIndex = 12,
	Parent = shopCard,
}, { textStroke() })
new("TextLabel", {
	BackgroundTransparency = 1,
	Position = UDim2.fromOffset(12, 52),
	Size = UDim2.new(1, -24, 0, 28),
	Font = FONT,
	TextScaled = true,
	TextXAlignment = Enum.TextXAlignment.Left,
	Text = string.format("Sprint noise −%d%% while carrying", math.floor((1 - T.Noise.PaddedShoesSprintScale) * 100 + 0.5)),
	TextColor3 = Color3.fromRGB(255, 220, 120),
	ZIndex = 12,
	Parent = shopCard,
})
local buyBtn = new("TextButton", {
	Name = "BuyPaddedShoes",
	Position = UDim2.new(0, 12, 1, -58),
	Size = UDim2.new(1, -24, 0, 48),
	BackgroundColor3 = Color3.fromRGB(255, 190, 40),
	Font = FONT,
	TextScaled = true,
	Text = "Buy 💰 " .. T.Shop.PaddedShoes.Price,
	TextColor3 = Color3.new(1, 1, 1),
	ZIndex = 12,
	Parent = shopCard,
}, { corner(12), stroke(3), textStroke() })
buyBtn.Activated:Connect(function()
	local ok, msg = Remotes.Buy:InvokeServer("PaddedShoes")
	Hud.toast(msg, ok and "good" or "warn")
	if ok then
		CreatureView.playUi(CreatureView.SOUNDS.Pop, 0.5, 1.8)
	end
end)

----------------------------------------------------------------------------------------------
-- Reveal card

local reveal = new("Frame", {
	Name = "Reveal",
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromOffset(small and 280 or 340, small and 320 or 380),
	BackgroundColor3 = Color3.fromRGB(255, 120, 190),
	Visible = false,
	ZIndex = 20,
	Parent = gui,
}, { corner(24), stroke(5, Color3.new(1, 1, 1)) })
local revealBurst = new("Frame", {
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.4),
	Size = UDim2.fromScale(0.9, 0.62),
	BackgroundColor3 = Color3.fromRGB(255, 240, 160),
	ZIndex = 20,
	Parent = reveal,
}, { corner(200) })
local revealVfHolder = new("Frame", {
	BackgroundTransparency = 1,
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.4),
	Size = UDim2.fromScale(1, 0.66),
	ZIndex = 21,
	Parent = reveal,
})
local revealName = new("TextLabel", {
	BackgroundTransparency = 1,
	Position = UDim2.new(0, 10, 0.72, 0),
	Size = UDim2.new(1, -20, 0.12, 0),
	Font = FONT,
	TextScaled = true,
	Text = "???",
	TextColor3 = Color3.new(1, 1, 1),
	ZIndex = 22,
	Parent = reveal,
}, { textStroke() })
local revealSub = new("TextLabel", {
	BackgroundTransparency = 1,
	Position = UDim2.new(0, 10, 0.84, 0),
	Size = UDim2.new(1, -20, 0.1, 0),
	Font = FONT,
	TextScaled = true,
	Text = "",
	TextColor3 = Color3.fromRGB(255, 240, 150),
	ZIndex = 22,
	Parent = reveal,
}, { textStroke() })
local revealNew = new("TextLabel", {
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.new(0.82, 0, 0.1, 0),
	Size = UDim2.fromOffset(90, 40),
	Rotation = 12,
	BackgroundColor3 = Color3.fromRGB(255, 60, 80),
	Font = FONT,
	TextScaled = true,
	Text = "NEW!",
	TextColor3 = Color3.new(1, 1, 1),
	Visible = false,
	ZIndex = 23,
	Parent = reveal,
}, { corner(10), stroke(3, Color3.new(1, 1, 1)) })

local revealToken = 0
function Hud.reveal(data)
	revealToken += 1
	local token = revealToken
	local sp = Creatures.Species[data.species]
	for _, c in revealVfHolder:GetChildren() do
		c:Destroy()
	end
	local vf, part = viewport(data.species, UDim2.fromScale(1, 1), true, revealVfHolder)
	vf.ZIndex = 21
	local jumbo = data.form == "Jumbo"
	reveal.Visible = true
	reveal.Size = UDim2.fromOffset(10, 10)
	revealName.Text = (data.rarity == "Rare" and "⭐ " or "") .. sp.Family .. " family…"
	revealSub.Text = "?"
	revealNew.Visible = false
	revealBurst.BackgroundTransparency = 0.6
	TweenService:Create(reveal, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Size = UDim2.fromOffset(small and 280 or 340, small and 320 or 380) }):Play()
	CreatureView.playUi(CreatureView.SOUNDS.Twitch, 0.6, 1.2)
	-- silhouette spin, then the flash
	-- spin fast as a silhouette, then settle facing the player with a small sway
	local t0 = os.clock()
	local angle = 0
	local spin
	spin = RunService.RenderStepped:Connect(function(dt)
		local k = os.clock() - t0
		if k < 0.75 then
			angle += (6 + k * 20) * dt
		else
			local front = -0.45 + math.sin(k * 2) * 0.25
			local target = front + math.round((angle - front) / (2 * math.pi)) * 2 * math.pi
			angle += (target - angle) * (1 - math.exp(-8 * dt))
		end
		part.CFrame = CFrame.Angles(0, angle, 0)
		if revealToken ~= token then
			spin:Disconnect()
		end
	end)
	task.wait(0.75)
	if revealToken ~= token then
		return
	end
	vf.ImageColor3 = data.form == "Glazed" and Color3.fromRGB(255, 245, 190) or Color3.new(1, 1, 1)
	if jumbo then
		part.Size *= 1.25
	end
	revealBurst.BackgroundTransparency = 0
	TweenService:Create(revealBurst, TweenInfo.new(0.5), { BackgroundTransparency = 0.5 }):Play()
	revealName.Text = (data.form ~= "Normal" and (data.form .. " ") or "") .. sp.Name .. "!"
	local sub = "+💰 " .. data.coins
	if data.ventCounted and not data.evolved then
		sub ..= string.format("   🦀 vent %d/%d", data.ventRescues, T.Evolution.VentRescuesNeeded)
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
	if data.evolved then
		-- second beat: the buddy evolves
		for _, c in revealVfHolder:GetChildren() do
			c:Destroy()
		end
		local vf2 = viewport("KingRangoon", UDim2.fromScale(1, 1), false, revealVfHolder)
		vf2.ZIndex = 21
		revealBurst.BackgroundColor3 = Color3.fromRGB(255, 215, 80)
		revealName.Text = "✨ EVOLVED: King Rangoon!"
		revealSub.Text = "Your buddy got a crown"
		revealNew.Visible = true
		CreatureView.playUi(CreatureView.SOUNDS.Pop, 0.8, 1.1)
		task.wait(2.6)
		revealBurst.BackgroundColor3 = Color3.fromRGB(255, 240, 160)
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

local sprintBtn = new("TextButton", {
	Name = "Sprint",
	AnchorPoint = Vector2.new(1, 1),
	Position = small and UDim2.new(1, -112, 1, -24) or UDim2.new(1, -200, 1, -60),
	Size = UDim2.fromOffset(small and 76 or 92, small and 76 or 92),
	BackgroundColor3 = Color3.fromRGB(255, 120, 60),
	BackgroundTransparency = 0.15,
	Font = FONT,
	TextScaled = true,
	Text = "🏃\nRUN",
	TextColor3 = Color3.new(1, 1, 1),
	Visible = isTouch,
	Parent = gui,
}, { corner(46), stroke(3, Color3.new(1, 1, 1)), textStroke(), new("UIPadding", { PaddingTop = UDim.new(0, 10), PaddingBottom = UDim.new(0, 10), PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8) }) })
sprintBtn.Activated:Connect(function()
	setSprint(not sprinting)
end)
function Hud.updateSprintButton()
	sprintBtn.BackgroundColor3 = sprinting and Color3.fromRGB(230, 40, 40) or Color3.fromRGB(255, 120, 60)
	sprintBtn.Text = sprinting and "🏃\nRUNNING" or "🏃\nRUN"
end
local pcSprintHint = new("TextLabel", {
	AnchorPoint = Vector2.new(1, 1),
	Position = UDim2.new(1, -12, 1, -12),
	Size = UDim2.fromOffset(200, 28),
	BackgroundColor3 = Color3.fromRGB(20, 14, 34),
	BackgroundTransparency = 0.35,
	Font = FONT,
	TextScaled = true,
	Text = "Hold SHIFT to run",
	TextColor3 = Color3.new(1, 1, 1),
	Visible = not isTouch,
	Parent = gui,
}, { corner(8), new("UIPadding", { PaddingTop = UDim.new(0, 4), PaddingBottom = UDim.new(0, 4) }) })

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
-- Guidance beam (first rescues): to the nearest sleeper, then to the hideout

local beamA0 = Instance.new("Attachment")
local beamA1 = Instance.new("Attachment")
local guide = Instance.new("Beam")
guide.Attachment0 = beamA0
guide.Attachment1 = beamA1
guide.Width0 = 1.2
guide.Width1 = 1.2
guide.FaceCamera = true
guide.LightEmission = 1
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

function Hud.refresh()
	if not profile then
		return
	end
	coinsPill.Text = "💰 " .. profile.coins
	local found = 0
	for _, sp in Creatures.ordered() do
		local entry = profile.collection[sp.Id]
		local card = cards[sp.Id]
		if entry then
			found += 1
			card.vf.ImageColor3 = Color3.new(1, 1, 1)
			card.name.Text = sp.Name
			local forms = {}
			for _, f in T.Forms do
				table.insert(forms, entry.forms[f.Id] and "●" or "○")
			end
			card.info.Text = "x" .. entry.count .. "  " .. table.concat(forms, "")
			card.equip.Visible = true
			local isBuddy = profile.buddy == sp.Id
			card.equip.Text = isBuddy and "★ Buddy" or "Make buddy"
			card.equip.BackgroundColor3 = isBuddy and Color3.fromRGB(255, 180, 40) or Color3.fromRGB(80, 200, 120)
		else
			card.vf.ImageColor3 = Color3.new(0, 0, 0)
			card.name.Text = "???"
			card.info.Text = sp.EvolvesFrom and "evolves…" or (sp.Family .. " family")
			card.equip.Visible = false
		end
	end
	foundLabel.Text = string.format("Found %d/%d", found, #Creatures.ordered())
	local evo = T.Evolution
	if profile.collection[evo.To] then
		evoText.Text = "✨ King Rangoon evolved!"
		evoSub.Text = "Next goal: complete the collection"
	else
		evoText.Text = "🎯 First evolution: Crab Rangoon → King Rangoon"
		local dots = string.rep("●", profile.ventRescues) .. string.rep("○", evo.VentRescuesNeeded - profile.ventRescues)
		if profile.buddy == evo.From then
			evoSub.Text = "Rescue sleepers through the 🦀 vent: " .. dots
		elseif profile.collection[evo.From] then
			evoSub.Text = "Make Crab Rangoon your buddy, then use the vent: " .. dots
		else
			evoSub.Text = "Rescue a Crab Rangoon (Dumpling family) first: " .. dots
		end
	end
	local owned = profile.upgrades.PaddedShoes
	buyBtn.Text = owned and "Owned ✓" or ("Buy 💰 " .. T.Shop.PaddedShoes.Price)
	buyBtn.BackgroundColor3 = owned and Color3.fromRGB(90, 170, 110) or (profile.coins >= T.Shop.PaddedShoes.Price and Color3.fromRGB(255, 190, 40) or Color3.fromRGB(130, 120, 140))
	shopBadge.Visible = not owned and profile.coins >= T.Shop.PaddedShoes.Price
	if collection.Visible then
		newBadge.Visible = false
	end
end

----------------------------------------------------------------------------------------------
-- Per-frame

local SURFACE_HINT = {
	Loud = "🔊 LOUD FLOOR",
	Shelter = "💤 cozy — settling",
	Vent = "🤫 muffled vent",
	Quiet = "",
}

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
		if p:GetAttribute("State") ~= "Carried" then
			local d = (p.Position - pos).Magnitude
			if d < bd then
				best, bd = p, d
			end
		end
	end
	return best
end

local stationPos = Vector3.new(0, 0.5, -4)

local function frame()
	local now = workspace:GetServerTimeNow()
	-- rare pill
	if workspace:GetAttribute("RareActive") then
		rarePill.Text = "⭐ RARE snoring — north stage!"
		rarePill.BackgroundColor3 = Color3.fromRGB(200, 140, 20)
	else
		local left = math.max(0, (workspace:GetAttribute("RareAt") or now) - now)
		rarePill.Text = string.format("⭐ Rare sleeper in %d:%02d", left // 60, left % 60)
		rarePill.BackgroundColor3 = Color3.fromRGB(90, 60, 150)
	end
	local part = carriedPart()
	meter.Visible = part ~= nil
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if part then
		local wake = part:GetAttribute("Wake") or 0
		local stage = part:GetAttribute("Stage") or 0
		barFill.Size = UDim2.fromScale(wake / 100, 1)
		local cols = { Color3.fromRGB(120, 230, 140), Color3.fromRGB(255, 220, 70), Color3.fromRGB(255, 140, 40), Color3.fromRGB(255, 50, 50), Color3.fromRGB(255, 50, 50) }
		barFill.BackgroundColor3 = cols[stage + 1]
		local titles = { "💤 Sleeping soundly", "😬 Twitching…", "😱 SQUIRMING!", "👁 ONE EYE OPEN!", "💥 AWAKE!" }
		meterTitle.Text = titles[stage + 1]
		local surf = part:GetAttribute("Surface") or "Quiet"
		local s = SURFACE_HINT[surf] or ""
		if s == "" and sprinting then
			s = "🏃 running = noise"
		end
		meterSurface.Text = s
		if stage >= 3 then
			meter.Position = METER_POS + UDim2.fromOffset(math.sin(os.clock() * 40) * 3, 0)
		else
			meter.Position = METER_POS
		end
	end
	-- hints + guidance beam for new players
	local rescues = profile and profile.rescues or 0
	local hintText = nil
	local beamTarget: Vector3? = nil
	if part then
		if rescues < 3 then
			hintText = "Carry it to the 🛏️ HIDEOUT — walk, don't run!"
			beamTarget = stationPos
		end
	elseif rescues == 0 and hrp then
		local n = nearestSleeper(hrp.Position)
		if n then
			hintText = "Sneak up and GRAB a sleeping creature!"
			beamTarget = n.Position
		end
	elseif profile and profile.coins >= T.Shop.PaddedShoes.Price and not profile.upgrades.PaddedShoes then
		hintText = "You can afford 👟 Padded Shoes!"
	elseif profile and profile.collection.CrabRangoon and not profile.buddy and rescues < 6 then
		hintText = "Open 📖 and make Crab Rangoon your buddy (opens vents)"
	end
	hint.Visible = hintText ~= nil
	hint.Text = hintText or ""
	if beamTarget and hrp then
		beamA0.Parent = hrp
		beamA0.Position = Vector3.new(0, -2, 0)
		beamAnchor.Position = beamTarget + Vector3.new(0, 0.5, 0)
		guide.Enabled = true
		guide.Color = ColorSequence.new(part and Color3.fromRGB(255, 120, 200) or Color3.fromRGB(120, 220, 255))
	else
		guide.Enabled = false
	end
end

function Hud.start()
	Remotes.Profile.OnClientEvent:Connect(function(p)
		profile = p
		Hud.refresh()
	end)
	Remotes.Toast.OnClientEvent:Connect(function(text, kind)
		Hud.toast(text, kind)
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
	local station = workspace:WaitForChild("Map"):WaitForChild("Hideout"):WaitForChild("StationPad")
	stationPos = station.Position
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

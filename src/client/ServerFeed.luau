-- Server-wide 5★ pulls. When anyone in the server opens a 5★, everyone gets:
--   • a system line in the chat window ("Name opened a ★★★★★ Phoenara!"), and
--   • an entry in the feed under the wallet (the chat corner). Hover (or tap) the gold
--     [Monster] name to see which element they got.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")
local TextChatService = game:GetService("TextChatService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Monsters = require(Shared.Monsters)
local Ui = require(script.Parent.Ui)
local Sfx = require(script.Parent.Sfx)

local C = Ui.C
local px = Ui.px
local new = Ui.new
local EI = Config.ElementInfo
local GOLD = Color3.fromRGB(255, 198, 58)
local ServerFeed = {}

local LIFE = 16 -- seconds an entry stays (while not hovered)
local MAX = 4

local feed = new("Frame", {
	Name = "ServerFeed",
	Position = UDim2.fromOffset(px(84), px(148)),
	Size = UDim2.fromOffset(px(420), px(240)),
	BackgroundTransparency = 1,
	ZIndex = 5,
	Parent = Ui.gui,
}, {
	new("UIListLayout", { Padding = UDim.new(0, px(6)), SortOrder = Enum.SortOrder.LayoutOrder }),
})

-- Tooltip card shown while hovering a monster name.
local tip = Ui.card({ Name = "FeedTip", Size = UDim2.fromOffset(px(230), px(86)), Visible = false, ZIndex = 60, Shadow = false, Parent = Ui.gui }, 14)
local tipPortraitHolder = new("Frame", { Position = UDim2.fromOffset(px(8), px(8)), Size = UDim2.fromOffset(px(70), px(70)), BackgroundTransparency = 1, ZIndex = 61, Parent = tip })
local function tipLabel(y: number, size: number, weight: string)
	return Ui.text({ Position = UDim2.fromOffset(px(86), y), Size = UDim2.new(1, -px(94), 0, size + 4), BackgroundTransparency = 1, TextScaled = false, TextSize = size, TextXAlignment = Enum.TextXAlignment.Left, Text = "", ZIndex = 61, Parent = tip }, weight)
end
local tipName = tipLabel(px(10), px(18), "Title")
local tipEl = tipLabel(px(34), px(16), "Title")
local tipStars = tipLabel(px(56), px(15), "Title")
local tipFor: Instance? = nil

local function showTip(anchor: GuiObject, data)
	local sp = Monsters.Species[data.sp]
	local info = EI[data.el]
	if not sp or not info then
		return
	end
	tipFor = anchor
	for _, c in tipPortraitHolder:GetChildren() do
		c:Destroy()
	end
	Ui.portrait(tipPortraitHolder, data.sp, data.el, UDim2.fromScale(1, 1), nil, 62)
	tipName.Text = sp.Name
	tipEl.Text = info.Icon .. " " .. data.el .. " element"
	tipEl.TextColor3 = info.Color
	tipStars.Text = string.rep("★", data.stars or 5) .. "  ·  " .. sp.Role
	tipStars.TextColor3 = GOLD
	tip.BackgroundColor3 = Ui.Theme.tint(info.Color, 0.9)
	local stroke = tip:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Color = info.Color
		stroke.Thickness = 2
	end
	local p = anchor.AbsolutePosition - Ui.gui.AbsolutePosition
	tip.Position = UDim2.fromOffset(p.X, p.Y + anchor.AbsoluteSize.Y + 4)
	tip.Visible = true
end

local function hideTip(anchor: Instance?)
	if anchor == nil or tipFor == anchor then
		tip.Visible = false
		tipFor = nil
	end
end

-- System line in whichever chat this place uses.
local function chatLine(data)
	local sp = Monsters.Species[data.sp]
	local name = sp and sp.Name or data.sp
	local msg = string.format("%s opened a ★★★★★ %s!", data.name, name)
	if TextChatService.ChatVersion == Enum.ChatVersion.TextChatService then
		local channels = TextChatService:FindFirstChild("TextChannels")
		local ch = channels and (channels:FindFirstChild("RBXSystem") or channels:FindFirstChild("RBXGeneral")) :: TextChannel?
		if ch then
			pcall(function()
				ch:DisplaySystemMessage(string.format('<font color="#%s"><b>🌟 %s</b></font>', GOLD:ToHex(), msg))
			end)
		end
	else
		task.spawn(function()
			for _ = 1, 5 do
				local ok = pcall(function()
					StarterGui:SetCore("ChatMakeSystemMessage", { Text = "🌟 " .. msg, Color = GOLD, Font = Enum.Font.BuilderSansBold })
				end)
				if ok then
					return
				end
				task.wait(1)
			end
		end)
	end
end

local n = 0
local function addEntry(data)
	local sp = Monsters.Species[data.sp]
	if not sp then
		return
	end
	n += 1
	local entries = {}
	for _, c in feed:GetChildren() do
		if c:IsA("Frame") then
			table.insert(entries, c)
		end
	end
	table.sort(entries, function(a, b)
		return a.LayoutOrder < b.LayoutOrder
	end)
	while #entries >= MAX do
		table.remove(entries, 1):Destroy()
	end

	local row = new("Frame", { Name = "Entry" .. n, LayoutOrder = n, Size = UDim2.new(0, 0, 0, px(34)), AutomaticSize = Enum.AutomaticSize.X, BackgroundColor3 = Color3.fromRGB(28, 30, 48), BackgroundTransparency = 0.25, ZIndex = 5, Parent = feed }, {
		new("UICorner", { CornerRadius = UDim.new(0, px(10)) }),
		new("UIStroke", { Color = GOLD, Thickness = 1.5, Transparency = 0.2 }),
		new("UIPadding", { PaddingLeft = UDim.new(0, px(10)), PaddingRight = UDim.new(0, px(10)) }),
		new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, VerticalAlignment = Enum.VerticalAlignment.Center, Padding = UDim.new(0, px(5)), SortOrder = Enum.SortOrder.LayoutOrder }),
	})
	local function piece(order: number, text: string, color: Color3, weight: string, button: boolean?)
		local props = { LayoutOrder = order, AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.new(0, 0, 1, 0), BackgroundTransparency = 1, TextScaled = false, TextSize = px(16), Text = text, TextColor3 = color, ZIndex = 6, Parent = row }
		if button then
			props.AutoButtonColor = false
			return Ui.button(props)
		end
		return Ui.text(props, weight)
	end
	piece(1, "🌟", GOLD, "Title")
	piece(2, data.name, Color3.new(1, 1, 1), "Title")
	piece(3, "opened a", Color3.fromRGB(200, 204, 222), "Bold")
	piece(4, "★★★★★", GOLD, "Title")
	local nameB = piece(5, "[" .. sp.Name .. "]", GOLD, "Title", true) :: TextButton
	nameB.Name = "MonsterName"
	nameB.BackgroundTransparency = 1
	nameB.TextColor3 = GOLD
	nameB.TextSize = px(16)
	-- underline so it reads as hoverable
	new("Frame", { AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 0, 1, -px(5)), Size = UDim2.new(1, 0, 0, 1), BackgroundColor3 = GOLD, BackgroundTransparency = 0.3, BorderSizePixel = 0, ZIndex = 7, Parent = nameB })

	local hovered = false
	ServerFeed.last = { button = nameB, data = data }
	nameB.MouseEnter:Connect(function()
		hovered = true
		nameB.TextColor3 = Color3.new(1, 1, 1)
		showTip(nameB, data)
	end)
	nameB.MouseLeave:Connect(function()
		hovered = false
		nameB.TextColor3 = GOLD
		hideTip(nameB)
	end)
	nameB.Activated:Connect(function()
		-- touch has no hover: tap toggles the card
		if tip.Visible and tipFor == nameB then
			hideTip(nameB)
		else
			showTip(nameB, data)
			if UserInputService.TouchEnabled then
				task.delay(3, function()
					hideTip(nameB)
				end)
			end
		end
	end)

	-- slide in with a gold flash
	local sc = new("UIScale", { Scale = 0.6, Parent = row })
	TweenService:Create(sc, TweenInfo.new(0.3, Enum.EasingStyle.Back), { Scale = 1 }):Play()
	row.BackgroundColor3 = GOLD
	TweenService:Create(row, TweenInfo.new(0.6), { BackgroundColor3 = Color3.fromRGB(28, 30, 48) }):Play()

	-- fade out after a while (waits while hovered)
	task.spawn(function()
		local t = 0
		while t < LIFE and row.Parent do
			task.wait(0.5)
			if not hovered then
				t += 0.5
			end
		end
		if not row.Parent then
			return
		end
		hideTip(nameB)
		for _, d in row:GetDescendants() do
			if d:IsA("TextLabel") or d:IsA("TextButton") then
				TweenService:Create(d, TweenInfo.new(0.4), { TextTransparency = 1 }):Play()
			elseif d:IsA("UIStroke") then
				TweenService:Create(d, TweenInfo.new(0.4), { Transparency = 1 }):Play()
			end
		end
		TweenService:Create(row, TweenInfo.new(0.4), { BackgroundTransparency = 1 }):Play()
		task.wait(0.45)
		row:Destroy()
	end)
end

-- Studio debug: show the hover card for the newest entry (synthetic mouse can't hover GUI).
function ServerFeed.debugHover()
	local l = ServerFeed.last
	if l and l.button.Parent then
		showTip(l.button, l.data)
		return tip.Visible
	end
	return false
end

function ServerFeed.add(data)
	Sfx.play("announce")
	addEntry(data)
	chatLine(data)
end

function ServerFeed.start()
	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	remotes:WaitForChild("Announce").OnClientEvent:Connect(function(data)
		if type(data) == "table" and type(data.sp) == "string" then
			ServerFeed.add(data)
		end
	end)
end

local _ = C
local _p = Players
return ServerFeed

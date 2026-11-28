-- Wildbound's always-on HUD: wallet bar, menu rail, team bar with ultimates, player HP and
-- weapon skill, target frame, touch buttons, reward pops, pads that open menus, the How to
-- play card, the Top Tamers board and small world animations.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Monsters = require(Shared.Monsters)
local Ui = require(script.Parent.Ui)
local Panels = require(script.Parent.Panels)
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
-- Wallet (top-left, after Roblox's buttons)

local wallet = Ui.card({ Position = UDim2.fromOffset(px(70), 10), Size = UDim2.fromOffset(0, px(44)), ZIndex = 2, Shadow = false, Parent = gui }, 22)
new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, VerticalAlignment = Enum.VerticalAlignment.Center, Padding = UDim.new(0, 12), Parent = wallet })
Ui.pad(0, 12, 0, 12).Parent = wallet
local coinL = label(wallet, { LayoutOrder = 1, AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.new(0, 0, 1, 0), Text = "💰 0", TextSize = px(18) }, "Title")
local regL = label(wallet, { LayoutOrder = 2, AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.new(0, 0, 1, 0), Text = "🥚 0", TextSize = px(18) }, "Title")
local legL = label(wallet, { LayoutOrder = 3, AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.new(0, 0, 1, 0), Text = "🌟 0", TextSize = px(18) }, "Title")
local eclL = label(wallet, { LayoutOrder = 4, AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.new(0, 0, 1, 0), Text = "🌑 1", TextSize = px(18), Visible = false }, "Title")
wallet.AutomaticSize = Enum.AutomaticSize.X

-- World boss chip (under the wallet)
local bossChip = Ui.card({ Position = UDim2.fromOffset(px(70), 10 + px(52)), Size = UDim2.fromOffset(px(250), px(32)), ZIndex = 2, Shadow = false, Parent = gui }, 16)
local bossText = label(bossChip, { Size = UDim2.fromScale(1, 1), Text = "", TextSize = px(14), TextXAlignment = Enum.TextXAlignment.Center }, "Title")
bossChip.Visible = false -- the Next-up ticker (Ticker.luau) shows the titan now

local REGION_NAMES = { Haven = "Haven", SproutMeadow = "Sprout Meadow", EmberCanyon = "Ember Canyon", TideCoast = "Tide Coast", GaleHighlands = "Gale Highlands", TwilightVale = "Twilight Vale", TitanField = "Titan Field" }

local help = button({ AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -px(70), 0, 10), Size = UDim2.fromOffset(px(44), px(44)), BackgroundColor3 = C.Card, TextColor3 = C.Ink, Text = "?", TextScaled = false, TextSize = px(22), ZIndex = 2, Parent = gui, Radius = 22 })
-- sound on/off (session only)
local Sfx = require(script.Parent.Sfx)
local muteB = button({ AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -px(70) - px(52), 0, 10), Size = UDim2.fromOffset(px(44), px(44)), BackgroundColor3 = C.Card, TextColor3 = C.Ink, Text = "🔊", TextScaled = false, TextSize = px(20), ZIndex = 2, Parent = gui, Radius = 22 })
muteB.Visible = Sfx.enabled
muteB.Activated:Connect(function()
	Sfx.setMuted(not Sfx.isMuted())
	muteB.Text = Sfx.isMuted() and "🔇" or "🔊"
end)

----------------------------------------------------------------------------------------------
-- Menu rail (left)

-- starts under the Next-up ticker (wallet + 3 rows)
local rail = new("Frame", { AnchorPoint = Vector2.new(0, 0), Position = UDim2.new(0, 10, 0, 10 + px(52) + px(100) + 12), Size = UDim2.fromOffset(px(64), px(64) * 8 + 64), BackgroundTransparency = 1, Parent = gui }, { new("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }) })
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
for i, r in RAIL do
	local b = button({ LayoutOrder = i, Size = UDim2.fromOffset(px(64), px(64)), BackgroundColor3 = C.Card, Text = "", ZIndex = 2, Parent = rail, Radius = 18 })
	Ui.stroke(Ui.Theme.tint(r[3], 0.4), 2).Parent = b
	label(b, { Position = UDim2.fromOffset(0, px(6)), Size = UDim2.new(1, 0, 0, px(30)), Text = r[2], TextSize = px(26), TextColor3 = r[3], TextXAlignment = Enum.TextXAlignment.Center }, "Title")
	label(b, { Position = UDim2.new(0, 0, 1, -px(22)), Size = UDim2.new(1, 0, 0, px(16)), Text = r[1], TextSize = px(12), TextXAlignment = Enum.TextXAlignment.Center }, "Title")
	railButtons[r[1]] = b
	b.Visible = r[1] == "Monsters" or r[1] == "Shrine"
	newBadges[r[1]] = new("Frame", { Name = "New", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(1, -px(4), 0, px(6)), Size = UDim2.fromOffset(px(40), px(18)), BackgroundColor3 = C.Coral, Visible = false, ZIndex = 5, Parent = b }, {
		new("UICorner", { CornerRadius = UDim.new(0.5, 0) }),
		Ui.text({ Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, TextScaled = false, TextSize = px(11), TextColor3 = Color3.new(1, 1, 1), Text = "NEW!", ZIndex = 6 }, "Title"),
	})
	b.Activated:Connect(function()
		if newBadges[r[1]].Visible then
			newBadges[r[1]].Visible = false
			task.spawn(Ui.call, "Tutorial", "unl_" .. r[1])
		end
		if Ui.isOpen(r[1]) then
			Ui.open(nil)
		else
			Ui.open(r[1])
		end
	end)
	if r[1] == "Shrine" then
		shrineDot = new("Frame", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 2, 0, -2), Size = UDim2.fromOffset(px(16), px(16)), BackgroundColor3 = C.Sun, Visible = false, ZIndex = 4, Parent = b }, { new("UICorner", { CornerRadius = UDim.new(0.5, 0) }) })
	end
	if r[1] == "Pass" then
		passDot = new("Frame", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 2, 0, -2), Size = UDim2.fromOffset(px(16), px(16)), BackgroundColor3 = C.Coral, Visible = false, ZIndex = 4, Parent = b }, { new("UICorner", { CornerRadius = UDim.new(0.5, 0) }) })
	end
	if r[1] == "Expeditions" then
		expDot = new("Frame", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 2, 0, -2), Size = UDim2.fromOffset(px(16), px(16)), BackgroundColor3 = C.Mint, Visible = false, ZIndex = 4, Parent = b }, { new("UICorner", { CornerRadius = UDim.new(0.5, 0) }) })
	end
	if r[1] == "Monsters" then
		monDot = new("Frame", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 2, 0, -2), Size = UDim2.fromOffset(px(16), px(16)), BackgroundColor3 = C.Peach, Visible = false, ZIndex = 4, Parent = b }, { new("UICorner", { CornerRadius = UDim.new(0.5, 0) }) })
	end
	if r[1] == "Quests" then
		questDot = new("Frame", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 2, 0, -2), Size = UDim2.fromOffset(px(16), px(16)), BackgroundColor3 = C.Coral, Visible = false, ZIndex = 4, Parent = b }, { new("UICorner", { CornerRadius = UDim.new(0.5, 0) }) })
	end
end

----------------------------------------------------------------------------------------------
-- Team bar (bottom centre) + player HP + weapon skill

local bottom = new("Frame", { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -10), Size = UDim2.fromOffset(px(560), px(132)), BackgroundTransparency = 1, Parent = gui })
local me = Ui.card({ Position = UDim2.fromOffset(0, 0), Size = UDim2.new(1, 0, 0, px(40)), ZIndex = 2, Parent = bottom }, 14)
local hpLabel = label(me, { Position = UDim2.fromOffset(12, 0), Size = UDim2.fromOffset(px(110), px(40)), Text = "HP", TextSize = px(15), TextXAlignment = Enum.TextXAlignment.Left }, "Title")
local _, hpFill = bar(me, UDim2.new(0, px(118), 0.5, -px(6)), UDim2.new(1, -px(118) - px(200), 0, px(12)), C.Mint)
local skillB = button({ AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -px(100), 0.5, 0), Size = UDim2.fromOffset(px(92), px(30)), BackgroundColor3 = C.Peach, Text = "Q", TextScaled = false, TextSize = px(14), ZIndex = 3, Parent = me, Radius = 15 })
local dodgeB = button({ AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -6, 0.5, 0), Size = UDim2.fromOffset(px(88), px(30)), BackgroundColor3 = C.Sky, Text = "Dodge", TextScaled = false, TextSize = px(14), ZIndex = 3, Parent = me, Radius = 15 })
skillB.Activated:Connect(function()
	Controls.skill()
end)
-- Auto-Hunt toggle (above the bar, right side)
local AutoHunt = require(script.Parent.AutoHunt)
local autoB = button({ AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, 0, 0, -6), Size = UDim2.fromOffset(px(170), px(30)), BackgroundColor3 = C.Card, TextColor3 = C.Ink, Text = "🤖 Auto-Hunt [R]", TextScaled = false, TextSize = px(14), ZIndex = 3, Parent = bottom, Radius = 15 })
Ui.stroke(C.Line, 1.5).Parent = autoB
autoB.Activated:Connect(function()
	AutoHunt.toggle()
end)
local function paintAuto(state: boolean)
	autoB.BackgroundColor3 = state and C.Mint or C.Card
	autoB.TextColor3 = state and Color3.new(1, 1, 1) or C.Ink
	autoB.Text = state and "🤖 Auto-Hunt ON [R]" or ((Controls.touch and "🤖 Auto-Hunt") or "🤖 Auto-Hunt [R]")
end
AutoHunt.onChanged(paintAuto)
Ui.onProfile(function(p)
	local open = p.kills >= 1 or (p.bosses and p.bosses[Config.AutoHunt.UnlockBoss])
	autoB.Visible = Unlocks.open(p, "Auto")
	if not open then
		autoB.Text = "🔒 Auto-Hunt"
		autoB.TextColor3 = C.Sub
	elseif not AutoHunt.isOn() then
		paintAuto(false)
	end
end)
dodgeB.Activated:Connect(Controls.dodge)

local teamRow = new("Frame", { Position = UDim2.fromOffset(0, px(48)), Size = UDim2.new(1, 0, 0, px(84)), BackgroundTransparency = 1, Parent = bottom }, { new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }) })
type Slot = { card: Frame, name: TextLabel, sub: TextLabel, hp: Frame, ult: TextButton, cd: TextLabel, portrait: Frame?, uid: string? }
local slots: { Slot } = {}
for i = 1, 3 do
	local card = Ui.card({ LayoutOrder = i, Size = UDim2.new(1 / 3, -6, 1, 0), ZIndex = 2, Shadow = false, Parent = teamRow }, 16)
	local name = label(card, { Position = UDim2.fromOffset(px(70), px(6)), Size = UDim2.new(1, -px(74), 0, px(18)), Text = "Empty", TextSize = px(15), TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd }, "Title")
	local sub = label(card, { Position = UDim2.fromOffset(px(70), px(25)), Size = UDim2.new(1, -px(74), 0, px(14)), Text = "Tap to add a monster", TextColor3 = C.Sub, TextSize = px(12), TextXAlignment = Enum.TextXAlignment.Left }, "Bold")
	local _, hp = bar(card, UDim2.fromOffset(px(70), px(43)), UDim2.new(1, -px(78), 0, px(8)), C.Mint)
	local ult = button({ Position = UDim2.fromOffset(px(70), px(56)), Size = UDim2.new(1, -px(78), 0, px(22)), BackgroundColor3 = C.Lilac, Text = "", TextScaled = false, TextSize = px(12), ZIndex = 3, Parent = card, Radius = 11 })
	local cd = label(ult, { Size = UDim2.fromScale(1, 1), Text = "", TextSize = px(12), TextColor3 = Color3.new(1, 1, 1), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 4 }, "Title")
	local open = button({ Size = UDim2.fromOffset(px(64), px(84)), BackgroundTransparency = 1, Text = "", ZIndex = 5, Parent = card })
	slots[i] = { card = card, name = name, sub = sub, hp = hp, ult = ult, cd = cd, portrait = nil, uid = nil }
	ult.Activated:Connect(function()
		Controls.team(i)
	end)
	open.Activated:Connect(function()
		local s = slots[i]
		if s.uid then
			Panels.showMonster(s.uid)
		else
			Ui.open("Monsters")
		end
	end)
end

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

local function renderTeam(p)
	for i, s in slots do
		local uid = p.team[i]
		local m = uid ~= "" and p.monsters[uid]
		if s.portrait then
			s.portrait:Destroy()
			s.portrait = nil
		end
		if m then
			local sp = Monsters.Species[m.sp]
			s.uid = uid
			s.portrait = Ui.portrait(s.card, m.sp, m.el, UDim2.fromOffset(px(58), px(72)), UDim2.fromOffset(6, 6), 3)
			s.name.Text = sp.Name
			s.sub.Text = EI[m.el].Icon .. " " .. string.rep("★", sp.Stars) .. "  Lv " .. m.lv
			s.sub.TextColor3 = EI[m.el].Color
			s.ult.Visible = true
			local skill = Monsters.skills(m.sp, m.el)[3]
			s.ult.Text = ""
			s.cd.Text = (Controls.touch and "" or "[" .. i .. "] ") .. skill.Name
		else
			s.uid = nil
			s.name.Text = "Empty slot"
			s.sub.Text = "Tap to add a monster"
			s.sub.TextColor3 = C.Sub
			s.ult.Visible = false
			s.hp.Size = UDim2.fromScale(0, 1)
		end
	end
end

----------------------------------------------------------------------------------------------
-- Target frame (top centre)

local targetCard = Ui.card({ AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, px(62)), Size = UDim2.fromOffset(px(300), px(54)), Visible = false, ZIndex = 2, Parent = gui }, 16)
local tName = label(targetCard, { Position = UDim2.fromOffset(12, px(5)), Size = UDim2.new(1, -24, 0, px(20)), Text = "", TextSize = px(16), TextXAlignment = Enum.TextXAlignment.Left }, "Title")
local tFx = label(targetCard, { Position = UDim2.fromOffset(12, px(5)), Size = UDim2.new(1, -24, 0, px(20)), Text = "", TextSize = px(13), TextColor3 = C.Sub, TextXAlignment = Enum.TextXAlignment.Right }, "Bold")
local _, tHp = bar(targetCard, UDim2.fromOffset(12, px(30)), UDim2.new(1, -24, 0, px(12)), C.Coral)
local tHpText = label(targetCard, { Position = UDim2.fromOffset(12, px(28)), Size = UDim2.new(1, -24, 0, px(16)), Text = "", TextSize = px(11), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 6 }, "Title")

----------------------------------------------------------------------------------------------
-- Touch buttons

if Controls.touch then
	local atk = button({ AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -px(120), 1, -px(150)), Size = UDim2.fromOffset(px(104), px(104)), BackgroundColor3 = C.Coral, Text = "⚔", TextScaled = false, TextSize = px(42), ZIndex = 3, Parent = gui, Radius = 52 })
	local holding = false
	atk.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.Touch then
			holding = true
			Controls.attack()
		end
	end)
	atk.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.Touch then
			holding = false
		end
	end)
	RunService.Heartbeat:Connect(function()
		if holding then
			Controls.attack()
		end
	end)
	bottom.Position = UDim2.new(0.5, -px(40), 1, -10)
end

----------------------------------------------------------------------------------------------
-- How to play

local howTo = Ui.card({ AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(px(520), px(430)), Visible = false, ZIndex = 30, Parent = gui }, 24)
do
	label(howTo, { Position = UDim2.fromOffset(24, 20), Size = UDim2.new(1, -48, 0, px(30)), Text = "Welcome to " .. Config.GameName .. "!", TextSize = px(26), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 31 }, "Title")
	local steps = {
		{ "🐾", "Your team", "Up to 3 monsters follow you and fight on their own. Manage them in Monsters." },
		{ "⚔", "Fight", Controls.touch and "Tap ⚔ to attack. Q-button: weapon skill. Tap a team card's bar for its ultimate." or "Click to attack (hold to keep swinging). Q: weapon skill. Shift: dodge. 1, 2, 3: team ultimates." },
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

	RunService.RenderStepped:Connect(function(dt)
		local t = os.clock()
		-- player HP
		local char = player.Character
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		if hum then
			hpFill.Size = UDim2.fromScale(math.clamp(hum.Health / math.max(hum.MaxHealth, 1), 0, 1), 1)
			hpLabel.Text = string.format("❤ %d / %d", math.max(0, math.floor(hum.Health)), hum.MaxHealth)
		end
		-- weapon skill / dodge
		local kind = player:GetAttribute("Weapon") or "Blade"
		local w = T.Weapons[kind]
		local left = (player:GetAttribute("WeaponSkillReady") or 0) - workspace:GetServerTimeNow()
		skillB.Text = left > 0 and string.format("%s %.0fs", w.Skill.Name, math.ceil(left)) or ((Controls.touch and "" or "[Q] ") .. w.Skill.Name)
		skillB.BackgroundColor3 = left > 0 and C.Mute or C.Peach
		local dl = Controls.dodgeReady - os.clock()
		dodgeB.BackgroundColor3 = dl > 0 and C.Mute or C.Sky
		dodgeB.Text = Controls.touch and "Dodge" or "[Shift] Dodge"
		-- team bar live values
		for i, s in slots do
			if s.uid then
				local u = teamUnit(i)
				if u then
					local hp, max = u:GetAttribute("HP") or 0, u:GetAttribute("MaxHP") or 1
					s.hp.Size = UDim2.fromScale(math.clamp(hp / max, 0, 1), 1)
					local st = u:GetAttribute("State")
					local cdLeft = (u:GetAttribute("CdB") or 0) - workspace:GetServerTimeNow()
					local ready = cdLeft <= 0.05 and st ~= "fainted"
					-- a ready big move pulses so it's obvious when to press it
					local pulse = ready and (0.5 + 0.5 * math.sin(os.clock() * 7)) or 0
					s.ult.BackgroundColor3 = st == "fainted" and C.Mute or ready and C.Lilac:Lerp(Color3.fromRGB(255, 220, 120), pulse * 0.55) or Ui.Theme.tint(C.Lilac, 0.5)
					local sc = s.ult:FindFirstChild("Pulse") :: UIScale?
					if not sc then
						sc = Instance.new("UIScale")
						sc.Name = "Pulse"
						sc.Parent = s.ult
					end
					sc.Scale = 1 + pulse * 0.06
					if st == "fainted" then
						s.cd.Text = "Fainted"
					elseif not ready then
						s.cd.Text = string.format("%.0fs", math.ceil(cdLeft))
					else
						local m = Ui.profile and Ui.profile.monsters[s.uid]
						s.cd.Text = m and ((Controls.touch and "" or "[" .. i .. "] ") .. Monsters.skills(m.sp, m.el)[3].Name) or ""
					end
				end
			end
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
		-- world boss timer
		local untilT = workspace:GetAttribute("WorldBossUntil") or 0
		local nowT = workspace:GetServerTimeNow()
		if untilT > nowT then
			local left = math.floor(untilT - nowT)
			bossText.Text = string.format("⚡ Titan %s at the Titan Field · %d:%02d", workspace:GetAttribute("WorldBossName") or "", left // 60, left % 60)
			bossText.TextColor3 = C.Coral
		else
			local left = math.max(0, math.floor((workspace:GetAttribute("WorldBossAt") or nowT) - nowT))
			bossText.Text = string.format("⚡ Next titan in %d:%02d", left // 60, left % 60)
			bossText.TextColor3 = C.Sub
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

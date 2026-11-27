-- Arena on the client: the Arena panel (record, defence team, opponents, token shop) and the
-- turn-based battle screen. The server runs the battle; this file shows its event log and
-- sends the player's choices (skill + target, Auto, Forfeit).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Monsters = require(Shared.Monsters)
local Ui = require(script.Parent.Ui)
local Sfx = require(script.Parent.Sfx)

local C = Ui.C
local px = Ui.px
local new = Ui.new
local EI = Config.ElementInfo
local A = Config.Arena
local player = Players.LocalPlayer
local ArenaUi = {}

local function label(parent: Instance, props: { [string]: any }, weight: string?)
	props.BackgroundTransparency = props.BackgroundTransparency or 1
	props.TextScaled = false
	props.ZIndex = props.ZIndex or 13
	props.Parent = parent
	return Ui.text(props, weight or "Title")
end
local function pill(parent: Instance, props: { [string]: any }, color: Color3)
	props.BackgroundColor3 = color
	props.TextScaled = false
	props.TextSize = props.TextSize or px(15)
	props.ZIndex = props.ZIndex or 14
	props.Parent = parent
	props.Radius = 18
	return Ui.button(props)
end
local function clear(f: Instance)
	for _, c in f:GetChildren() do
		if not c:IsA("UIListLayout") and not c:IsA("UIPadding") then
			c:Destroy()
		end
	end
end
local function tween(o: Instance, t: number, props, style: Enum.EasingStyle?)
	local tw = TweenService:Create(o, TweenInfo.new(t, style or Enum.EasingStyle.Quad, Enum.EasingDirection.Out), props)
	tw:Play()
	return tw
end

local function call(action: string, a: any?, b: any?)
	return Ui.call("Arena", action, a, b)
end

----------------------------------------------------------------------------------------------
-- Panel

local panel, body, sub = Ui.panel("Arena", "Arena", "3v3 turn-based battles against other Tamers' defence teams.", C.Coral, "🏟", true)
local _ = panel
local info: any = nil
local essenceEl = 1
local startBattle: (res: any) -> ()

local function teamStrip(parent: Instance, team, order: number?, size: number?)
	local s = size or px(46)
	local strip = new("Frame", { LayoutOrder = order or 0, Size = UDim2.fromOffset((s + 6) * 3, s + px(16)), BackgroundTransparency = 1, ZIndex = 13, Parent = parent }, {
		new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }),
	})
	for i, m in team or {} do
		local cell = new("Frame", { LayoutOrder = i, Size = UDim2.fromOffset(s, s + px(16)), BackgroundTransparency = 1, ZIndex = 13, Parent = strip })
		Ui.portrait(cell, m.sp, m.el, UDim2.fromOffset(s, s), nil, 13)
		label(cell, { Position = UDim2.fromOffset(0, s), Size = UDim2.new(1, 0, 0, px(15)), Text = (EI[m.el] and EI[m.el].Icon or "") .. " " .. m.lv .. (m.aw and "✦" or ""), TextSize = px(12), TextXAlignment = Enum.TextXAlignment.Center }, "Bold")
	end
	return strip
end

local function render()
	clear(body)
	if not info then
		label(body, { LayoutOrder = 1, Size = UDim2.new(1, 0, 0, px(30)), Text = "Loading the Arena...", TextColor3 = C.Sub, TextSize = px(16) }, "Bold")
		return
	end
	if info.locked then
		sub.Text = "Beat the Meadow Guardian to open the Arena."
		label(body, { LayoutOrder = 1, Size = UDim2.new(1, 0, 0, px(60)), Text = "🔒 The Arena opens once you've beaten the Meadow Guardian in Sprout Meadow.", TextColor3 = C.Sub, TextSize = px(18), TextWrapped = true }, "Bold")
		return
	end
	sub.Text = string.format("Rating %d  ·  %d wins, %d losses  ·  🎟 %d tokens  ·  %d fights left today", info.rating, info.wins, info.losses, info.tokens, info.attacksLeft)

	-- defence
	Ui.section(body, 1, "YOUR DEFENCE TEAM")
	local def = new("Frame", { LayoutOrder = 2, Size = UDim2.new(1, 0, 0, px(84)), BackgroundColor3 = C.Soft, ZIndex = 12, Parent = body }, { new("UICorner", { CornerRadius = UDim.new(0, 16) }) })
	local strip = teamStrip(def, info.def)
	strip.Position = UDim2.fromOffset(px(14), px(10))
	label(def, { Position = UDim2.fromOffset(px(14) + (px(46) + 6) * 3 + px(10), px(14)), Size = UDim2.new(1, -px(480), 0, px(22)), Text = "Power " .. Ui.fmt(info.defPower), TextSize = px(17), TextXAlignment = Enum.TextXAlignment.Left })
	label(def, { Position = UDim2.fromOffset(px(14) + (px(46) + 6) * 3 + px(10), px(40)), Size = UDim2.new(1, -px(480), 0, px(34)), Text = "Other Tamers fight this team while you're away. The AI plays it.", TextSize = px(13), TextColor3 = C.Sub, TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Left }, "Bold")
	local setB = pill(def, { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -px(14), 0.5, 0), Size = UDim2.fromOffset(px(220), px(42)), Text = "Use my current team" }, C.Lilac)
	setB.Activated:Connect(function()
		local p = Ui.profile
		local uids = {}
		for _, u in p.team do
			if u ~= "" then
				table.insert(uids, u)
			end
		end
		if #uids == 0 then
			Ui.toast("Put monsters on your team first", "warn")
			return
		end
		if call("defence", uids) then
			ArenaUi.refresh()
		end
	end)
	if #(info.log or {}) > 0 then
		local lines = {}
		for i, l in info.log do
			if i > 3 then
				break
			end
			table.insert(lines, string.format("%s %s attacked you: you %s (%+d)", l.won and "🛡" or "⚔", l.by, l.won and "held" or "lost", l.delta))
		end
		label(body, { LayoutOrder = 3, Size = UDim2.new(1, 0, 0, px(18) * #lines + 4), Text = table.concat(lines, "\n"), TextSize = px(14), TextColor3 = C.Sub, TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top }, "Bold")
	end

	-- opponents
	Ui.section(body, 4, "OPPONENTS  ·  your attack team is your current team")
	for i, o in info.opponents do
		local row = new("Frame", { LayoutOrder = 4 + i, Size = UDim2.new(1, 0, 0, px(84)), BackgroundColor3 = C.Soft, ZIndex = 12, Parent = body }, { new("UICorner", { CornerRadius = UDim.new(0, 16) }) })
		label(row, { Position = UDim2.fromOffset(px(14), px(12)), Size = UDim2.fromOffset(px(260), px(22)), Text = o.name, TextSize = px(18), TextXAlignment = Enum.TextXAlignment.Left })
		label(row, { Position = UDim2.fromOffset(px(14), px(38)), Size = UDim2.fromOffset(px(260), px(18)), Text = string.format("Rating %d  ·  Power %s", o.rating, Ui.fmt(o.power)), TextSize = px(14), TextColor3 = C.Sub, TextXAlignment = Enum.TextXAlignment.Left }, "Bold")
		local s = teamStrip(row, o.team)
		s.Position = UDim2.fromOffset(px(290), px(10))
		local fight = pill(row, { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -px(14), 0.5, 0), Size = UDim2.fromOffset(px(130), px(44)), Text = "Fight!" }, info.attacksLeft > 0 and C.Coral or C.Line)
		fight.Activated:Connect(function()
			if info.attacksLeft <= 0 then
				Ui.toast("No fights left today. They refill at 00:00 UTC", "warn")
				return
			end
			local ok, _, res = call("fight", o.i)
			if ok and res then
				Ui.open(nil)
				startBattle(res)
			end
		end)
	end

	-- token shop
	Ui.section(body, 9, "TOKEN SHOP  ·  🎟 " .. info.tokens)
	local shop = new("Frame", { LayoutOrder = 10, Size = UDim2.new(1, 0, 0, px(44)), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, ZIndex = 12, Parent = body }, {
		new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Wraps = true, Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }),
	})
	local items = {}
	for id, it in A.Shop do
		table.insert(items, { id = id, it = it })
	end
	table.sort(items, function(a, b)
		return a.it.order < b.it.order
	end)
	for _, e in items do
		local id, it = e.id, e.it
		local text = it.essence and string.format("%s 10 %s Essence · 🎟%d", EI[Config.Elements[essenceEl]].Icon, Config.Elements[essenceEl], it.cost) or string.format("%s · 🎟%d", it.legendary and "🌟 Legendary scroll" or it.rune and "💠 Rune (Rare+)" or "📜 Regular scroll", it.cost)
		local b = pill(shop, { LayoutOrder = it.order, Size = UDim2.fromOffset(px(it.essence and 250 or 220), px(44)), Text = text }, info.tokens >= it.cost and C.Sun or C.Line)
		b.Activated:Connect(function()
			if call("shop", id, Config.Elements[essenceEl]) then
				ArenaUi.refresh()
			end
		end)
		if it.essence then
			local cyc = pill(shop, { LayoutOrder = it.order, Size = UDim2.fromOffset(px(44), px(44)), Text = "🔄" }, C.Soft)
			cyc.TextColor3 = C.Ink
			cyc.Activated:Connect(function()
				essenceEl = essenceEl % #Config.Elements + 1
				render()
			end)
		end
	end
	label(body, { LayoutOrder = 11, Size = UDim2.new(1, 0, 0, px(36)), Text = string.format("Win: +%d tokens, +%d coins. Lose: +%d tokens. %d fights a day.", A.WinTokens, A.WinCoins, A.LossTokens, A.DailyAttacks), TextSize = px(13), TextColor3 = C.Sub, TextWrapped = true }, "Bold")
end

function ArenaUi.refresh()
	task.spawn(function()
		local ok, _, data = Ui.call("Arena", "info")
		if ok and data then
			info = data
			if Ui.isOpen("Arena") then
				render()
			end
		end
	end)
end

Ui.onOpen.Arena = function()
	render()
	ArenaUi.refresh()
end

----------------------------------------------------------------------------------------------
-- Battle screen

local gui = new("ScreenGui", { Name = "ArenaBattle", DisplayOrder = 35, IgnoreGuiInset = true, ResetOnSpawn = false, ZIndexBehavior = Enum.ZIndexBehavior.Sibling, Enabled = false, Parent = player:WaitForChild("PlayerGui") })
local bg = new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromRGB(26, 24, 44), BackgroundTransparency = 0.08, Parent = gui }, {
	new("UIGradient", { Color = ColorSequence.new(Color3.fromRGB(70, 60, 120), Color3.fromRGB(30, 26, 50)), Rotation = 90 }),
})
local stage = new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 2, Parent = gui })
local title = label(stage, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, px(60)), Size = UDim2.fromOffset(px(700), px(36)), Text = "", TextSize = px(28), TextColor3 = Color3.new(1, 1, 1), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 5 })
local logLine = label(stage, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, px(100)), Size = UDim2.fromOffset(px(700), px(26)), Text = "", TextSize = px(18), TextColor3 = Color3.fromRGB(230, 226, 255), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 5 }, "Bold")
local actionBar = new("Frame", { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -px(30)), Size = UDim2.fromOffset(px(860), px(120)), BackgroundTransparency = 1, ZIndex = 5, Parent = stage })
local resultBox = Ui.card({ AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(px(420), px(260)), Visible = false, ZIndex = 40, Parent = stage }, 24)
local resultInner = new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 40, Parent = resultBox })

type Card = { frame: Frame, hp: Frame, shield: Frame, hpText: TextLabel, fx: TextLabel, home: UDim2, maxHp: number, cur: number, side: string, slot: number, alive: boolean, stroke: UIStroke }
local cards: { [string]: { [number]: Card } } = { A = {}, B = {} }
local battle: any = nil -- { snap, pending, busy, target, start }
local queue: { any } = {}
local animating = false

local CARD_W, CARD_H = px(250), px(110)

local function makeCard(side: string, slot: number, m, maxHp: number): Card
	local x = side == "A" and 0.05 or 0.95
	local y = 0.22 + (slot - 1) * 0.2
	local home = UDim2.new(x, 0, y, 0)
	local f = Ui.card({ AnchorPoint = Vector2.new(side == "A" and 0 or 1, 0), Position = home, Size = UDim2.fromOffset(CARD_W, CARD_H), ZIndex = 10, Parent = stage }, 18)
	local stroke = new("UIStroke", { Color = EI[m.el].Color, Thickness = 2, Parent = f })
	Ui.portrait(f, m.sp, m.el, UDim2.fromOffset(px(84), px(84)), UDim2.fromOffset(px(12), px(13)), 11)
	local sp = Monsters.Species[m.sp]
	label(f, { Position = UDim2.fromOffset(px(106), px(10)), Size = UDim2.new(1, -px(116), 0, px(20)), Text = sp.Name, TextSize = px(17), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 11 })
	label(f, { Position = UDim2.fromOffset(px(106), px(32)), Size = UDim2.new(1, -px(116), 0, px(16)), Text = EI[m.el].Icon .. " " .. string.rep("★", sp.Stars) .. "  Lv " .. m.lv .. (m.aw and " ✦" or ""), TextSize = px(13), TextColor3 = EI[m.el].Color, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 11 }, "Bold")
	local back = new("Frame", { Position = UDim2.fromOffset(px(106), px(54)), Size = UDim2.new(1, -px(118), 0, px(14)), BackgroundColor3 = Color3.fromRGB(230, 230, 238), ZIndex = 11, Parent = f }, { new("UICorner", { CornerRadius = UDim.new(0.5, 0) }) })
	local hp = new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = side == "A" and C.Mint or C.Coral, ZIndex = 12, Parent = back }, { new("UICorner", { CornerRadius = UDim.new(0.5, 0) }) })
	local shield = new("Frame", { Size = UDim2.fromScale(0, 1), BackgroundColor3 = Color3.fromRGB(150, 200, 255), BackgroundTransparency = 0.15, ZIndex = 13, Parent = back }, { new("UICorner", { CornerRadius = UDim.new(0.5, 0) }) })
	local hpText = label(f, { Position = UDim2.fromOffset(px(106), px(70)), Size = UDim2.new(1, -px(116), 0, px(15)), Text = "", TextSize = px(12), TextColor3 = C.Sub, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 11 }, "Bold")
	local fx = label(f, { Position = UDim2.fromOffset(px(106), px(87)), Size = UDim2.new(1, -px(116), 0, px(15)), Text = "", TextSize = px(12), TextColor3 = C.Lilac, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 11 }, "Bold")
	local hit = new("TextButton", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Text = "", ZIndex = 15, Parent = f })
	local card: Card = { frame = f, hp = hp, shield = shield, hpText = hpText, fx = fx, home = home, maxHp = maxHp, cur = maxHp, side = side, slot = slot, alive = true, stroke = stroke }
	hit.Activated:Connect(function()
		if side == "B" and battle and card.alive then
			battle.target = slot
			for s, c in cards.B do
				c.stroke.Thickness = s == slot and 5 or 2
				c.stroke.Color = s == slot and C.Sun or EI[battle.start.theirs[s].el].Color
			end
		end
	end)
	return card
end

local function setHp(card: Card, hp: number, shield: number?)
	card.cur = hp
	tween(card.hp, 0.25, { Size = UDim2.fromScale(math.clamp(hp / card.maxHp, 0, 1), 1) })
	if shield then
		tween(card.shield, 0.25, { Size = UDim2.fromScale(math.clamp(shield / card.maxHp, 0, 1), 1) })
	end
	card.hpText.Text = string.format("%s / %s", Ui.fmt(math.max(0, hp)), Ui.fmt(card.maxHp))
end

local function pop(card: Card, text: string, color: Color3, big: boolean?)
	local l = label(stage, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(card.frame.AbsolutePosition.X + card.frame.AbsoluteSize.X / 2, card.frame.AbsolutePosition.Y - gui.AbsolutePosition.Y + px(20)), Size = UDim2.fromOffset(px(200), px(40)), Text = text, TextSize = big and px(34) or px(26), TextColor3 = color, TextStrokeTransparency = 0, TextStrokeColor3 = Color3.fromRGB(30, 26, 50), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 30 })
	local sc = new("UIScale", { Scale = 1.7, Parent = l })
	tween(sc, 0.18, { Scale = 1 }, Enum.EasingStyle.Back)
	tween(l, 0.9, { Position = l.Position - UDim2.fromOffset(0, px(40)) })
	task.delay(0.55, function()
		tween(l, 0.35, { TextTransparency = 1, TextStrokeTransparency = 1 })
	end)
	task.delay(1, function()
		l:Destroy()
	end)
end

local function shake(card: Card)
	local home = card.home
	task.spawn(function()
		for i = 1, 6 do
			card.frame.Position = home + UDim2.fromOffset((i % 2 == 0 and 1 or -1) * px(6), 0)
			task.wait(0.03)
		end
		card.frame.Position = home
	end)
	card.frame.BackgroundColor3 = Color3.fromRGB(255, 220, 220)
	tween(card.frame, 0.3, { BackgroundColor3 = C.Card })
end

local function lunge(card: Card)
	local dir = card.side == "A" and 1 or -1
	tween(card.frame, 0.12, { Position = card.home + UDim2.fromOffset(dir * px(60), 0) })
	task.delay(0.16, function()
		tween(card.frame, 0.2, { Position = card.home })
	end)
end

local FX_ICON = { burn = "🔥 Burn", stun = "💫 Stun", silence = "🤐 Silence", slow = "🐌 Slow", taunt = "🛡 Taunt", cleanse = "✨ Cleanse", buff = "⬆", debuff = "⬇" }

local function nameOf(side: string, slot: number): string
	local m = battle and (side == "A" and battle.start.mine or battle.start.theirs)[slot]
	return m and Monsters.Species[m.sp].Name or "?"
end

local function playEvent(e)
	local kind = e[1]
	if kind == "skill" then
		local card = cards[e[2]][e[3]]
		if card then
			lunge(card)
			local side = e[2] == "A" and "Your" or "Their"
			logLine.Text = string.format("%s %s used %s!", side, nameOf(e[2], e[3]), e[5])
			local m = (e[2] == "A" and battle.start.mine or battle.start.theirs)[e[3]]
			local sp = m and Monsters.Species[m.sp]
			Sfx.play(sp and sp.Range == "ranged" and "zap" or "swing", { pitch = e[4] == 3 and 0.8 or 1 })
			if e[4] == 3 then
				Sfx.play("blast", { vol = 0.6 })
			end
		end
		task.wait(0.32)
	elseif kind == "hit" then
		local card = cards[e[2]][e[3]]
		if card then
			shake(card)
			local color = e[5] and Color3.fromRGB(255, 150, 70) or (e[6] > 1 and Color3.fromRGB(255, 90, 90) or e[6] < 1 and Color3.fromRGB(190, 190, 210) or Color3.new(1, 1, 1))
			pop(card, (e[5] and "CRIT " or "") .. Ui.fmt(e[4]) .. (e[6] > 1 and "!" or ""), color, e[5])
			setHp(card, e[7], e[8])
			Sfx.play(e[5] and "crit" or "hit", { vary = 0.1 })
		end
		task.wait(0.16)
	elseif kind == "heal" then
		local card = cards[e[2]][e[3]]
		if card then
			pop(card, "+" .. Ui.fmt(e[4]), C.Mint)
			setHp(card, e[5])
			Sfx.play("revive", { vol = 0.6, vary = 0.08 })
		end
		task.wait(0.12)
	elseif kind == "shield" then
		local card = cards[e[2]][e[3]]
		if card then
			pop(card, "🛡", Color3.fromRGB(150, 200, 255))
			setHp(card, card.cur, e[4])
			Sfx.play("toast", { vol = 0.5 })
		end
		task.wait(0.08)
	elseif kind == "dot" then
		local card = cards[e[2]][e[3]]
		if card then
			pop(card, "🔥" .. Ui.fmt(e[4]), Color3.fromRGB(255, 140, 80))
			setHp(card, e[5])
		end
		task.wait(0.2)
	elseif kind == "fx" then
		local card = cards[e[2]][e[3]]
		if card then
			local t = FX_ICON[e[4]] or e[4]
			if e[5] then
				t = t .. " " .. string.upper(e[5])
			end
			pop(card, t, C.Lilac)
		end
		task.wait(0.06)
	elseif kind == "stunned" then
		local card = cards[e[2]][e[3]]
		if card then
			pop(card, "💫 Stunned", C.Sun)
			logLine.Text = nameOf(e[2], e[3]) .. " is stunned and can't move!"
		end
		task.wait(0.4)
	elseif kind == "faint" then
		local card = cards[e[2]][e[3]]
		if card then
			card.alive = false
			setHp(card, 0, 0)
			tween(card.frame, 0.4, { BackgroundTransparency = 0.5, Rotation = card.side == "A" and -8 or 8 })
			Sfx.play("poof")
			logLine.Text = nameOf(e[2], e[3]) .. " fainted!"
		end
		task.wait(0.35)
	end
end

local renderActions: () -> ()

local function sync(snap)
	for _, side in { "A", "B" } do
		for i, u in snap[side] do
			local card = cards[side][i]
			if card then
				card.maxHp = u.maxHp
				setHp(card, u.hp, u.shield)
				local tags = {}
				for _, f in u.fx do
					local t, stat = string.match(f, "^(%w+):?(%w*)$")
					table.insert(tags, (FX_ICON[t] or t) .. (stat ~= "" and (" " .. string.upper(stat)) or ""))
				end
				card.fx.Text = table.concat(tags, "  ")
			end
		end
	end
end

local function showResult(r)
	resultBox.Visible = true
	clear(resultInner)
	resultBox.BackgroundColor3 = r.won and Ui.Theme.tint(C.Sun, 0.85) or C.Card
	label(resultInner, { Position = UDim2.fromOffset(0, px(26)), Size = UDim2.new(1, 0, 0, px(44)), Text = r.won and "VICTORY!" or "Defeat", TextSize = px(40), TextColor3 = r.won and Color3.fromRGB(200, 140, 20) or C.Sub, TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 41 })
	label(resultInner, { Position = UDim2.fromOffset(0, px(84)), Size = UDim2.new(1, 0, 0, px(26)), Text = string.format("Rating %d (%+d)", r.rating, r.delta), TextSize = px(22), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 41 })
	label(resultInner, { Position = UDim2.fromOffset(0, px(118)), Size = UDim2.new(1, 0, 0, px(24)), Text = string.format("🎟 +%d tokens%s", r.tokens, r.coins > 0 and ("   💰 +" .. r.coins) or ""), TextSize = px(19), TextColor3 = C.Sub, TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 41 })
	local back = pill(resultInner, { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -px(22)), Size = UDim2.fromOffset(px(220), px(48)), Text = "Back to the Arena", ZIndex = 42 }, C.Coral)
	back.Activated:Connect(function()
		gui.Enabled = false
		battle = nil
		Ui.open("Arena")
	end)
	local sc = new("UIScale", { Scale = 0.5, Parent = resultBox })
	tween(sc, 0.35, { Scale = 1 }, Enum.EasingStyle.Back)
	if r.won then
		Sfx.play("reveal_rare")
		task.delay(0.2, Sfx.coin, true)
	else
		Sfx.play("faint")
	end
end

local function runQueue()
	if animating then
		return
	end
	animating = true
	task.spawn(function()
		while #queue > 0 do
			local item = table.remove(queue, 1)
			for _, e in item.events do
				if e[1] ~= "end" then
					playEvent(e)
				end
			end
			if item.snap then
				sync(item.snap)
			end
			if item.result then
				task.wait(0.4)
				showResult(item.result)
			end
		end
		animating = false
		renderActions()
	end)
end

local function receive(res)
	battle.pending = res.pending
	table.insert(queue, { events = res.events or {}, snap = res.snap, result = res.result })
	clear(actionBar)
	runQueue()
end

renderActions = function()
	clear(actionBar)
	if not battle or animating then
		return
	end
	local pend = battle.pending
	for slot, c in cards.A do
		c.stroke.Thickness = pend and pend.slot == slot and 5 or 2
		c.stroke.Color = pend and pend.slot == slot and C.Mint or EI[battle.start.mine[slot].el].Color
	end
	if not pend then
		return
	end
	local m = battle.start.mine[pend.slot]
	local skills = Monsters.skills(m.sp, m.el)
	logLine.Text = string.format("Your %s's turn: pick a skill (click an enemy to target it)", Monsters.Species[m.sp].Name)
	local row = new("Frame", { Size = UDim2.new(1, 0, 0, px(78)), BackgroundTransparency = 1, ZIndex = 5, Parent = actionBar }, {
		new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Center, Padding = UDim.new(0, px(10)), SortOrder = Enum.SortOrder.LayoutOrder }),
	})
	for i = 1, 3 do
		local s = skills[i]
		local ok = pend.ok[i]
		local tag = i == 1 and "Signature" or i == 2 and "Skill" or "Ultimate"
		local cdText = ok and "Ready" or (pend.cd[i] > 0 and (pend.cd[i] .. " turn" .. (pend.cd[i] > 1 and "s" or "")) or "Silenced")
		local b = new("TextButton", { LayoutOrder = i, Size = UDim2.fromOffset(px(230), px(78)), BackgroundColor3 = ok and (i == 3 and C.Lilac or C.Card) or Color3.fromRGB(90, 86, 110), AutoButtonColor = ok, Text = "", ZIndex = 6, Parent = row }, { new("UICorner", { CornerRadius = UDim.new(0, 16) }) })
		label(b, { Position = UDim2.fromOffset(px(12), px(8)), Size = UDim2.new(1, -px(24), 0, px(22)), Text = s.Name, TextSize = px(17), TextColor3 = ok and (i == 3 and Color3.new(1, 1, 1) or C.Ink) or Color3.fromRGB(200, 196, 220), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 7 })
		label(b, { Position = UDim2.fromOffset(px(12), px(32)), Size = UDim2.new(1, -px(24), 0, px(16)), Text = tag .. " · " .. cdText, TextSize = px(12), TextColor3 = ok and (i == 3 and Color3.fromRGB(240, 236, 255) or C.Sub) or Color3.fromRGB(190, 186, 210), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 7 }, "Bold")
		label(b, { Position = UDim2.fromOffset(px(12), px(50)), Size = UDim2.new(1, -px(24), 0, px(22)), Text = s.Desc, TextSize = px(11), TextWrapped = true, TextTruncate = Enum.TextTruncate.AtEnd, TextColor3 = ok and (i == 3 and Color3.fromRGB(240, 236, 255) or C.Sub) or Color3.fromRGB(190, 186, 210), TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top, ZIndex = 7 }, "Bold")
		b.Activated:Connect(function()
			if not ok or not battle or animating then
				return
			end
			local target = pend.taunt or battle.target
			if not target or not cards.B[target] or not cards.B[target].alive then
				for sl, c in cards.B do
					if c.alive then
						target = sl
						break
					end
				end
			end
			clear(actionBar)
			local good, _, res = call("act", i, target)
			if good and res then
				receive(res)
			else
				renderActions()
			end
		end)
	end
	local tools = new("Frame", { Position = UDim2.fromOffset(0, px(86)), Size = UDim2.new(1, 0, 0, px(34)), BackgroundTransparency = 1, ZIndex = 5, Parent = actionBar }, {
		new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Center, Padding = UDim.new(0, px(10)), SortOrder = Enum.SortOrder.LayoutOrder }),
	})
	local auto = pill(tools, { LayoutOrder = 1, Size = UDim2.fromOffset(px(160), px(34)), Text = "▶▶ Auto", ZIndex = 6 }, C.Sky)
	auto.Activated:Connect(function()
		clear(actionBar)
		local good, _, res = call("act", "auto")
		if good and res then
			receive(res)
		end
	end)
	local quit = pill(tools, { LayoutOrder = 2, Size = UDim2.fromOffset(px(160), px(34)), Text = "Forfeit", ZIndex = 6 }, Color3.fromRGB(110, 104, 140))
	quit.Activated:Connect(function()
		clear(actionBar)
		local good, _, res = call("forfeit")
		if good and res then
			receive(res)
		end
	end)
end

startBattle = function(res)
	for _, side in { "A", "B" } do
		for _, c in cards[side] do
			c.frame:Destroy()
		end
		cards[side] = {}
	end
	resultBox.Visible = false
	queue = {}
	battle = { start = res.start, pending = nil, target = nil }
	title.Text = string.format("You  vs  %s (%d)", res.start.name, res.start.rating)
	logLine.Text = "Battle start!"
	for _, side in { "A", "B" } do
		local team = side == "A" and res.start.mine or res.start.theirs
		for i, m in team do
			local u = res.snap[side][i]
			cards[side][i] = makeCard(side, i, m, u and u.maxHp or 1)
			setHp(cards[side][i], u and u.maxHp or 1, 0)
			-- slide in
			local c = cards[side][i]
			c.frame.Position = c.home + UDim2.fromOffset(side == "A" and -px(400) or px(400), 0)
			tween(c.frame, 0.4 + i * 0.08, { Position = c.home }, Enum.EasingStyle.Back)
		end
	end
	gui.Enabled = true
	Sfx.play("boss", { pitch = 1.3, vol = 0.6 })
	task.delay(0.6, function()
		receive(res)
	end)
end

-- Studio debug: the same calls the buttons make.
function ArenaUi.debugFight(i: number)
	local ok, _, res = call("fight", i)
	if ok and res then
		startBattle(res)
	end
	return ok
end
function ArenaUi.debugAct(skill: any, target: number?)
	local good, _, res = call("act", skill, target)
	if good and res then
		receive(res)
	end
	return good
end

-- Studio debug: current battle state for tests.
function ArenaUi.debugState(): string
	if not battle then
		return "none"
	end
	return string.format("pending=%s animating=%s queue=%d result=%s", battle.pending and tostring(battle.pending.slot) or "nil", tostring(animating), #queue, tostring(resultBox.Visible))
end

function ArenaUi.start()
	local _ = bg
end

return ArenaUi

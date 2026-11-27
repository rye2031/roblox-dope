-- M6 loops on the client: the Expeditions panel (slots, planner, claim) and the Element Surge
-- chip under the titan timer.
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
local E = Config.Loops.Expeditions
local LoopsUi = {}

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
		if not c:IsA("UIListLayout") and not c:IsA("UIPadding") and not c:IsA("UIGridLayout") then
			c:Destroy()
		end
	end
end
local function fmtTime(sec: number): string
	sec = math.max(0, math.floor(sec))
	if sec >= 3600 then
		return string.format("%dh %02dm", sec // 3600, (sec % 3600) // 60)
	end
	return string.format("%d:%02d", sec // 60, sec % 60)
end

----------------------------------------------------------------------------------------------
-- Surge chip

local chip = Ui.card({ Name = "Surge", Position = UDim2.fromOffset(px(70), 10 + px(52) + px(40)), Size = UDim2.fromOffset(px(250), px(32)), ZIndex = 2, Shadow = false, Parent = Ui.gui }, 16)
local chipText = label(chip, { Size = UDim2.fromScale(1, 1), Text = "", TextSize = px(14), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 3 })

local function updateChip()
	local el = workspace:GetAttribute("SurgeElement")
	local untilT = workspace:GetAttribute("SurgeUntil") or 0
	local info = el and EI[el]
	if not info then
		chip.Visible = false
		return
	end
	chip.Visible = false -- shown in the Next-up ticker (Ticker.luau)
	chipText.Text = string.format("%s %s Surge · %s", info.Icon, el, fmtTime(untilT - os.time()))
	chipText.TextColor3 = info.Color:Lerp(Color3.new(0, 0, 0), 0.25)
	local stroke = chip:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Color = info.Color
		stroke.Thickness = (el == "Light" or el == "Dark") and 2.5 or 1.5
	end
end

----------------------------------------------------------------------------------------------
-- Expeditions panel

local panel, body, sub = Ui.panel("Expeditions", "Expeditions", "Send storage monsters away. They come back with loot, even while you're offline.", C.Sun, "🧭", true)
local _ = panel
local planning: number? = nil -- slot being planned
local plan = { place = "SproutMeadow", dur = 2, picked = {} :: { string } }

local function teamSet(p): { [string]: boolean }
	local t = {}
	for _, u in p.team do
		t[u] = true
	end
	return t
end
local function awaySet(p): { [string]: boolean }
	local a = {}
	for _, x in p.expeditions or {} do
		for _, u in x.uids do
			a[u] = true
		end
	end
	return a
end

local render: () -> ()

local function slotRow(p, slot: number, order: number)
	local key = tostring(slot)
	local x = p.expeditions[key]
	local need = E.SlotBoss[slot]
	local locked = need ~= nil and not p.bosses[need]
	local row = new("Frame", { LayoutOrder = order, Size = UDim2.new(1, 0, 0, px(96)), BackgroundColor3 = C.Soft, ZIndex = 12, Parent = body }, { new("UICorner", { CornerRadius = UDim.new(0, 16) }) })
	label(row, { Position = UDim2.fromOffset(px(16), px(10)), Size = UDim2.fromOffset(px(200), px(20)), Text = "SLOT " .. slot, TextSize = px(13), TextColor3 = C.Sub, TextXAlignment = Enum.TextXAlignment.Left })
	if locked then
		local names = { SproutMeadow = "the Meadow Guardian", EmberCanyon = "the Canyon Tyrant", TideCoast = "the Tide Monarch" }
		label(row, { Position = UDim2.fromOffset(px(16), px(34)), Size = UDim2.new(1, -px(32), 0, px(40)), Text = "🔒 Opens after you beat " .. (names[need] or need), TextSize = px(17), TextColor3 = C.Sub, TextXAlignment = Enum.TextXAlignment.Left })
		return
	end
	if not x then
		label(row, { Position = UDim2.fromOffset(px(16), px(34)), Size = UDim2.new(1, -px(200), 0, px(40)), Text = "Free. Plan a trip for up to " .. E.MaxMonsters .. " storage monsters.", TextSize = px(16), TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Left })
		local b = pill(row, { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -px(16), 0.5, 0), Size = UDim2.fromOffset(px(150), px(44)), Text = "Plan trip" }, C.Sun)
		b.Activated:Connect(function()
			planning = slot
			plan.picked = {}
			render()
		end)
		return
	end
	local pl = E.Places[x.place]
	local d = E.Durations[x.dur]
	local left = x.start + d.Minutes * 60 - os.time()
	label(row, { Position = UDim2.fromOffset(px(16), px(30)), Size = UDim2.fromOffset(px(320), px(22)), Text = pl.Icon .. " " .. pl.Name .. "  ·  " .. d.Name, TextSize = px(18), TextXAlignment = Enum.TextXAlignment.Left })
	local por = new("Frame", { Position = UDim2.fromOffset(px(16), px(56)), Size = UDim2.fromOffset(px(140), px(34)), BackgroundTransparency = 1, ZIndex = 13, Parent = row }, {
		new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }),
	})
	for i, u in x.uids do
		local m = p.monsters[u]
		if m then
			local f = Ui.portrait(por, m.sp, m.el, UDim2.fromOffset(px(34), px(34)), nil, 13)
			f.LayoutOrder = i
		end
	end
	local r = x.reward
	label(row, { Position = UDim2.fromOffset(px(170), px(58)), Size = UDim2.new(1, -px(380), 0, px(30)), Text = string.format("💰 %s  ·  %s Crystals %d  ·  📜 %s  ·  XP %s each", Ui.fmt(r.coins), r.element and EI[r.element].Icon or "✨", r.essence, tostring(r.scrolls) .. (r.scrollChance > 0 and "+" or ""), Ui.fmt(r.xp)), TextSize = px(13), TextColor3 = C.Sub, TextXAlignment = Enum.TextXAlignment.Left }, "Bold")
	if left <= 0 then
		local b = pill(row, { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -px(16), 0.5, 0), Size = UDim2.fromOffset(px(150), px(44)), Text = "Claim!" }, C.Mint)
		b.Activated:Connect(function()
			local ok = Ui.call("Expedition", "claim", slot)
			if ok then
				Sfx.coin(true)
				task.delay(0.15, Sfx.play, "scroll_get")
			end
		end)
	else
		local timer = label(row, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -px(16), 0, px(14)), Size = UDim2.fromOffset(px(150), px(26)), Text = "Back in " .. fmtTime(left), TextSize = px(16), TextXAlignment = Enum.TextXAlignment.Right })
		timer:SetAttribute("EndsAt", x.start + d.Minutes * 60)
		local b = pill(row, { AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -px(16), 1, -px(10)), Size = UDim2.fromOffset(px(110), px(32)), Text = "Recall", TextColor3 = C.Sub }, C.Line)
		b.Activated:Connect(function()
			Ui.call("Expedition", "recall", slot)
		end)
	end
end

local function planner(p)
	local slot = planning :: number
	Ui.section(body, 1, "PLAN A TRIP · SLOT " .. slot)
	-- places
	local places = new("Frame", { LayoutOrder = 2, Size = UDim2.new(1, 0, 0, px(44)), BackgroundTransparency = 1, ZIndex = 12, Parent = body }, {
		new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }),
	})
	for i, id in { "SproutMeadow", "EmberCanyon", "TideCoast", "GaleHighlands", "TwilightVale" } do
		local pl = E.Places[id]
		local open = p.regions[id] == true
		local b = pill(places, { LayoutOrder = i, Size = UDim2.fromOffset(px(170), px(40)), Text = pl.Icon .. " " .. pl.Name .. (pl.Mult > 1 and (" ×" .. pl.Mult) or "") }, open and (plan.place == id and C.Sun or C.Soft) or C.Line)
		b.TextColor3 = plan.place == id and Color3.new(1, 1, 1) or (open and C.Ink or C.Sub)
		b.Activated:Connect(function()
			if open then
				plan.place = id
				render()
			else
				Ui.toast("Reach " .. pl.Name .. " first", "warn")
			end
		end)
	end
	-- lengths
	local durs = new("Frame", { LayoutOrder = 3, Size = UDim2.new(1, 0, 0, px(44)), BackgroundTransparency = 1, ZIndex = 12, Parent = body }, {
		new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }),
	})
	for i, d in E.Durations do
		local b = pill(durs, { LayoutOrder = i, Size = UDim2.fromOffset(px(140), px(40)), Text = d.Name .. " · " .. (d.Minutes >= 60 and (d.Minutes // 60 .. "h") or (d.Minutes .. "m")) }, plan.dur == i and C.Sky or C.Soft)
		b.TextColor3 = plan.dur == i and Color3.new(1, 1, 1) or C.Ink
		b.Activated:Connect(function()
			plan.dur = i
			render()
		end)
	end
	-- preview + send
	local ms = {}
	for _, u in plan.picked do
		local m = p.monsters[u]
		if m then
			table.insert(ms, { sp = m.sp, lv = m.lv, aw = m.aw })
		end
	end
	local bar = new("Frame", { LayoutOrder = 4, Size = UDim2.new(1, 0, 0, px(46)), BackgroundTransparency = 1, ZIndex = 12, Parent = body }, {
		new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 8), VerticalAlignment = Enum.VerticalAlignment.Center, SortOrder = Enum.SortOrder.LayoutOrder }),
	})
	local preview = "Pick up to " .. E.MaxMonsters .. " monsters below (not your team)"
	if #ms > 0 then
		local r = Config.expeditionReward(ms, plan.place, E.Durations[plan.dur].Minutes)
		local pl = E.Places[plan.place]
		preview = string.format("%d picked → 💰 %s · %s %d Crystals · 📜 %d%s · %s XP each", #ms, Ui.fmt(r.coins), pl.Essence and EI[pl.Essence].Icon or "✨", r.essence, r.scrolls, r.scrollChance > 0 and string.format(" (+%d%% for 1 more)", math.floor(r.scrollChance * 100)) or "", Ui.fmt(r.xp))
	end
	label(bar, { LayoutOrder = 1, Size = UDim2.new(1, -px(260), 1, 0), Text = preview, TextSize = px(14), TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Left }, "Bold")
	local send = pill(bar, { LayoutOrder = 2, Size = UDim2.fromOffset(px(120), px(40)), Text = "Send" }, #ms > 0 and C.Mint or C.Line)
	send.Activated:Connect(function()
		if #plan.picked == 0 then
			return
		end
		local ok = Ui.call("Expedition", "start", slot, plan.place, plan.dur, plan.picked)
		if ok then
			Sfx.play("region", { pitch = 1.2 })
			planning = nil
			plan.picked = {}
		end
	end)
	local cancel = pill(bar, { LayoutOrder = 3, Size = UDim2.fromOffset(px(120), px(40)), Text = "Cancel", TextColor3 = C.Sub }, C.Soft)
	cancel.Activated:Connect(function()
		planning = nil
		render()
	end)
	-- monster picker: eligible storage monsters, strongest first
	local team, away = teamSet(p), awaySet(p)
	local list = {}
	for uid, m in p.monsters do
		if not team[uid] and not away[uid] then
			table.insert(list, uid)
		end
	end
	table.sort(list, function(a, b)
		local ma, mb = p.monsters[a], p.monsters[b]
		local pa, pb = Monsters.power(ma.sp, ma.lv, ma.aw), Monsters.power(mb.sp, mb.lv, mb.aw)
		if pa ~= pb then
			return pa > pb
		end
		return a < b
	end)
	local grid = new("Frame", { LayoutOrder = 5, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, ZIndex = 12, Parent = body }, {
		new("UIGridLayout", { CellSize = UDim2.fromOffset(px(92), px(112)), CellPadding = UDim2.fromOffset(8, 8), SortOrder = Enum.SortOrder.LayoutOrder }),
	})
	if #list == 0 then
		label(body, { LayoutOrder = 6, Size = UDim2.new(1, 0, 0, px(30)), Text = "No free monsters: everything is on your team or already away.", TextColor3 = C.Sub, TextSize = px(15) }, "Bold")
	end
	for i, uid in list do
		local m = p.monsters[uid]
		local sp = Monsters.Species[m.sp]
		local picked = table.find(plan.picked, uid) ~= nil
		local card = new("TextButton", { Name = uid, LayoutOrder = i, Text = "", AutoButtonColor = true, BackgroundColor3 = picked and Ui.Theme.tint(C.Mint, 0.55) or C.Soft, ZIndex = 12, Parent = grid }, { new("UICorner", { CornerRadius = UDim.new(0, 14) }) })
		if picked then
			Ui.stroke(C.Mint, 3).Parent = card
		end
		Ui.portrait(card, m.sp, m.el, UDim2.new(1, -12, 1, -px(36)), UDim2.fromOffset(6, 6), 13)
		label(card, { Position = UDim2.new(0, 4, 1, -px(32)), Size = UDim2.new(1, -8, 0, px(15)), Text = EI[m.el].Icon .. " " .. string.rep("★", sp.Stars), TextColor3 = EI[m.el].Color, TextSize = px(12), TextXAlignment = Enum.TextXAlignment.Center })
		label(card, { Position = UDim2.new(0, 4, 1, -px(17)), Size = UDim2.new(1, -8, 0, px(15)), Text = "Lv " .. m.lv, TextSize = px(12), TextXAlignment = Enum.TextXAlignment.Center }, "Bold")
		card.Activated:Connect(function()
			local at = table.find(plan.picked, uid)
			if at then
				table.remove(plan.picked, at)
			elseif #plan.picked < E.MaxMonsters then
				table.insert(plan.picked, uid)
			else
				Ui.toast("Up to " .. E.MaxMonsters .. " monsters per trip", "warn")
			end
			render()
		end)
	end
end

render = function()
	local p = Ui.profile
	if not p then
		return
	end
	clear(body)
	if planning then
		sub.Text = "Longer trips and harder places bring back more. Monsters away can't fight or be trained."
		planner(p)
		return
	end
	sub.Text = "Send storage monsters away. They come back with loot, even while you're offline."
	for slot = 1, E.Slots do
		slotRow(p, slot, slot)
	end
	Ui.section(body, 10, "HOW IT WORKS")
	label(body, { LayoutOrder = 11, Size = UDim2.new(1, 0, 0, px(44)), Text = "Stronger monsters, longer trips and harder regions bring back more coins, Crystals (the region's element), scrolls and XP. Recalling early brings them back empty-handed.", TextSize = px(14), TextColor3 = C.Sub, TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top }, "Bold")
end
Ui.onOpen.Expeditions = render

function LoopsUi.start()
	Ui.onProfile(function()
		if Ui.isOpen("Expeditions") then
			render()
		end
	end)
	-- tick timers and the surge chip
	task.spawn(function()
		local lastSurge = nil
		while true do
			updateChip()
			local el = workspace:GetAttribute("SurgeElement")
			if el ~= lastSurge then
				if lastSurge ~= nil then
					local sc = new("UIScale", { Scale = 1.25, Parent = chip })
					TweenService:Create(sc, TweenInfo.new(0.4, Enum.EasingStyle.Back), { Scale = 1 }):Play()
					task.delay(0.5, function()
						sc:Destroy()
					end)
					Sfx.play("announce", { pitch = 0.9 })
				end
				lastSurge = el
			end
			if Ui.isOpen("Expeditions") and not planning then
				local needRender = false
				for _, d in body:GetDescendants() do
					local endsAt = d:GetAttribute("EndsAt")
					if endsAt and d:IsA("TextLabel") then
						local left = endsAt - os.time()
						d.Text = "Back in " .. fmtTime(left)
						if left <= 0 then
							needRender = true
						end
					end
				end
				if needRender then
					render()
				end
			end
			task.wait(1)
		end
	end)
end

return LoopsUi

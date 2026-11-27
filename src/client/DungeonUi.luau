-- Dungeons on the client: the panel at the Dungeon Gate (keys, one card per dungeon with
-- Normal/Hard, rune focus and set bonus, clears and best time), the run HUD (wave, monsters
-- left, timer, Leave) and the results card when the chest opens.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Runes = require(Shared.Runes)
local DD = require(Shared.DungeonData)
local Ui = require(script.Parent.Ui)
local Sfx = require(script.Parent.Sfx)

local C = Ui.C
local new, corner, px = Ui.new, Ui.corner, Ui.px
local EI = Config.ElementInfo
local DungeonUi = {}

local function label(parent: Instance, props: { [string]: any }, weight: string?)
	props.TextScaled = false
	props.TextSize = props.TextSize or px(15)
	props.TextXAlignment = props.TextXAlignment or Enum.TextXAlignment.Left
	props.BackgroundTransparency = 1
	props.ZIndex = props.ZIndex or 13
	props.Parent = parent
	return Ui.text(props, weight)
end

local function pill(parent: Instance, props: { [string]: any }, color: Color3)
	props.BackgroundColor3 = color
	props.TextScaled = false
	props.TextSize = props.TextSize or px(14)
	props.ZIndex = props.ZIndex or 13
	props.Radius = props.Radius or 16
	props.Parent = parent
	return Ui.button(props)
end

local function clear(f: Instance)
	for _, c in f:GetChildren() do
		if not c:IsA("UIListLayout") and not c:IsA("UIGridLayout") and not c:IsA("UIPadding") then
			c:Destroy()
		end
	end
end

local function fmt(sec: number): string
	sec = math.max(0, math.floor(sec))
	if sec >= 3600 then
		return string.format("%dh %02dm", sec // 3600, (sec % 3600) // 60)
	end
	return string.format("%d:%02d", sec // 60, sec % 60)
end

local function focusText(id: string): string
	local set = Runes.Sets[id]
	local names = {}
	for _, s in set.Focus do
		table.insert(names, Runes.Stats[s].Name)
	end
	return table.concat(names, " · ")
end

----------------------------------------------------------------------------------------------
-- panel

local panel, body, sub = Ui.panel("Dungeons", "Dungeons", "Short runs for runes: 3 waves, a boss, a chest.", C.Lilac, "🗝", true)
local info: any = nil

local render: () -> ()

local playMode = "solo" -- solo | party (Normal/Hard then opens a party instead of starting)

local function start(id: string, mode: string)
	if playMode == "party" then
		if Ui.call("Dungeon", "host", id, mode) then
			DungeonUi.refresh()
		end
		return
	end
	local ok = Ui.call("Dungeon", "start", id, mode)
	if ok then
		Ui.open(nil)
	end
end

-- Party controls: Solo/Party switch, your party (Start / Leave / remove), parties to join.
local function partySection(order: number)
	local parties = info.parties or {}
	local mine
	for _, pt in parties do
		if pt.mine then
			mine = pt
		end
	end
	local bar = new("Frame", { Name = "PlayMode", LayoutOrder = order, Size = UDim2.new(1, 0, 0, px(36)), BackgroundTransparency = 1, ZIndex = 12, Parent = body }, {
		new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder, VerticalAlignment = Enum.VerticalAlignment.Center }),
	})
	for i, opt in { { "solo", "🧍 Solo" }, { "party", "👥 Party (up to " .. (info.partyMax or 3) .. ")" } } do
		local on = playMode == opt[1]
		local b = pill(bar, { Name = opt[1], LayoutOrder = i, Size = UDim2.fromOffset(px(i == 1 and 110 or 190), px(34)), Text = opt[2], TextColor3 = on and Color3.new(1, 1, 1) or C.Ink }, on and C.Lilac or C.Soft)
		b.Activated:Connect(function()
			playMode = opt[1]
			render()
		end)
	end
	label(bar, { LayoutOrder = 3, Size = UDim2.new(1, -px(330), 1, 0), Text = playMode == "party" and "Pick a dungeon below to open a party; friends at the gate join it." or "Pick a dungeon below to start alone.", TextColor3 = C.Sub, TextSize = px(13) }, "Bold")
	local function row(o: number, color: Color3, text: string)
		local r = new("Frame", { LayoutOrder = o, Size = UDim2.new(1, 0, 0, px(48)), BackgroundColor3 = Ui.Theme.tint(color, 0.85), ZIndex = 12, Parent = body }, { corner(14) })
		label(r, { Position = UDim2.fromOffset(px(14), 0), Size = UDim2.new(1, -px(320), 1, 0), Text = text, TextSize = px(15), TextTruncate = Enum.TextTruncate.AtEnd }, "Title")
		local btns = new("Frame", { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -8, 0.5, 0), Size = UDim2.fromOffset(px(300), px(34)), BackgroundTransparency = 1, ZIndex = 12, Parent = r }, {
			new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Right, Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }),
		})
		return r, btns
	end
	if mine then
		local d = DD.List[mine.id]
		local _, btns = row(order + 1, C.Mint, string.format("👥 %s · %s · %s (%d/%d)", d.Name, mine.mode, table.concat(mine.names, ", "), mine.n, info.partyMax or 3))
		if mine.lead then
			local go = pill(btns, { Name = "StartParty", LayoutOrder = 1, Size = UDim2.fromOffset(px(110), px(34)), Text = "▶ Start" }, C.Mint)
			go.Activated:Connect(function()
				if Ui.call("Dungeon", "start") then
					Ui.open(nil)
				end
			end)
		else
			label(btns, { LayoutOrder = 1, Size = UDim2.fromOffset(px(170), px(34)), Text = "Waiting for " .. mine.leaderName .. "…", TextColor3 = C.Sub, TextSize = px(13), TextXAlignment = Enum.TextXAlignment.Right }, "Bold")
		end
		local lv = pill(btns, { Name = "LeaveParty", LayoutOrder = 2, Size = UDim2.fromOffset(px(110), px(34)), Text = mine.lead and "Close" or "Leave", TextColor3 = C.Ink }, C.Card)
		lv.Activated:Connect(function()
			Ui.call("Dungeon", "leave")
			DungeonUi.refresh()
		end)
	end
	local n = 0
	for _, pt in parties do
		if not pt.mine then
			n += 1
			local d = DD.List[pt.id]
			local _, btns = row(order + 1 + n, C.Sky, string.format("%s %s's party · %s · %s (%d/%d)", d.Icon, pt.leaderName, d.Name, pt.mode, pt.n, info.partyMax or 3))
			local full = pt.n >= (info.partyMax or 3)
			local j = pill(btns, { Name = "Join", LayoutOrder = 1, Size = UDim2.fromOffset(px(110), px(34)), Text = full and "Full" or "Join" }, full and C.Line or C.Sky)
			j.Activated:Connect(function()
				if not full and Ui.call("Dungeon", "join", pt.leader) then
					DungeonUi.refresh()
				end
			end)
		end
	end
end

render = function()
	if not panel.Visible then
		return
	end
	clear(body)
	if not info then
		label(body, { LayoutOrder = 1, Size = UDim2.new(1, 0, 0, px(30)), Text = "Loading…", TextColor3 = C.Sub }, "Bold")
		return
	end
	local keysRow = new("Frame", { LayoutOrder = 1, Size = UDim2.new(1, 0, 0, px(44)), BackgroundColor3 = Ui.Theme.tint(C.Lilac, 0.85), ZIndex = 12, Parent = body }, { corner(14) })
	local keyText = label(keysRow, { Name = "Keys", Position = UDim2.fromOffset(px(14), 0), Size = UDim2.new(1, -px(28), 1, 0), Text = "", TextSize = px(17) }, "Title")
	local function paintKeys()
		local nextAt = info.nextAt
		keyText.Text = string.format("🗝 Keys %d / %d%s   ·   a clear uses a key; a failed run or leaving is free", info.keys, DD.KeyCap, nextAt and ("  ·  next in " .. fmt(nextAt - os.time())) or "")
	end
	paintKeys()
	task.spawn(function()
		while keyText.Parent and panel.Visible do
			task.wait(1)
			if info.nextAt and os.time() >= info.nextAt then
				DungeonUi.refresh()
				return
			end
			paintKeys()
		end
	end)
	partySection(2)
	for i, row in info.list do
		local d = DD.List[row.id]
		local set = Runes.Sets[row.id]
		local card = new("Frame", { Name = row.id, LayoutOrder = 10 + i, Size = UDim2.new(1, 0, 0, px(112)), BackgroundColor3 = C.Soft, ZIndex = 12, Parent = body }, { corner(16) })
		Ui.stroke(Ui.Theme.tint(d.Color, 0.35), 2).Parent = card
		Ui.dot(card, d.Color, d.Icon, px(54), UDim2.new(0, 14, 0, px(14)), Vector2.new(0, 0)).ZIndex = 13
		local x = px(80)
		label(card, { Position = UDim2.fromOffset(x, px(10)), Size = UDim2.new(1, -x - px(300), 0, px(22)), Text = d.Name, TextSize = px(20) }, "Title")
		label(card, { Position = UDim2.fromOffset(x, px(34)), Size = UDim2.new(1, -x - px(300), 0, px(16)), Text = d.RegionName .. "  ·  " .. d.Blurb, TextColor3 = C.Sub, TextSize = px(13), TextTruncate = Enum.TextTruncate.AtEnd }, "Bold")
		label(card, { Position = UDim2.fromOffset(x, px(56)), Size = UDim2.new(1, -x - px(300), 0, px(18)), Text = "💠 Runes lean to " .. focusText(row.id), TextSize = px(14) }, "Bold")
		label(card, { Position = UDim2.fromOffset(x, px(78)), Size = UDim2.new(1, -x - px(300), 0, px(18)), Text = string.format("%s set: 2 on one monster = %s", set.Name, set.Desc), TextColor3 = d.Color:Lerp(Color3.new(0, 0, 0), 0.35), TextSize = px(14) }, "Title")
		for j, mode in { "Normal", "Hard" } do
			local m = row.modes[mode]
			local lo, hi = DD.levels(row.id, mode)
			local bx = UDim2.new(1, -px(292) + (j - 1) * px(146), 0, px(12))
			local b = pill(card, { Name = mode, Position = bx, Size = UDim2.fromOffset(px(138), px(52)), Text = "" }, m.open and (mode == "Hard" and C.Coral or C.Mint) or C.Line)
			label(b, { Position = UDim2.fromOffset(0, px(6)), Size = UDim2.new(1, 0, 0, px(20)), Text = (m.open and "" or "🔒 ") .. mode, TextColor3 = Color3.new(1, 1, 1), TextSize = px(17), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 14 }, "Title")
			label(b, { Position = UDim2.fromOffset(0, px(28)), Size = UDim2.new(1, 0, 0, px(16)), Text = string.format("Lv %d-%d · %d rune%s", lo, hi + 2, DD.Modes[mode].runes, DD.Modes[mode].runes > 1 and "s" or ""), TextColor3 = Color3.new(1, 1, 1), TextSize = px(12), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 14 }, "Bold")
			label(card, { Position = bx + UDim2.fromOffset(0, px(56)), Size = UDim2.fromOffset(px(138), px(36)), Text = m.open and (m.clears > 0 and string.format("Cleared %d×\nBest %s", m.clears, fmt(m.best or 0)) or "Not cleared yet") or (m.why or ""), TextColor3 = C.Sub, TextSize = px(11), TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Center, TextYAlignment = Enum.TextYAlignment.Top }, "Bold")
			b.Activated:Connect(function()
				if not m.open then
					Ui.toast(m.why or "Locked", "warn")
					return
				end
				start(row.id, mode)
			end)
		end
	end
	label(body, { LayoutOrder = 30, Size = UDim2.new(1, 0, 0, px(50)), Text = string.format("Parties: up to 3 at the gate; more monsters and HP for each extra player; everyone with a key gets their own chest (no key: coins and Essence as a helper). Normal: 1 rune (Rare 60%% · Epic 32%% · Legendary 8%%). Hard: 2 runes (Rare 25%% · Epic 50%% · Legendary 25%%). First clear: 2 Regular scrolls on Normal, a Legendary scroll on Hard. %d minutes per run.", DD.TimeLimit // 60), TextColor3 = C.Sub, TextSize = px(12), TextWrapped = true }, "Bold")
end

function DungeonUi.refresh()
	task.spawn(function()
		local ok, _, data = Ui.call("Dungeon", "info")
		if ok and data then
			info = data
			render()
		end
	end)
end

Ui.onOpen.Dungeons = function()
	render()
	DungeonUi.refresh()
end

----------------------------------------------------------------------------------------------
-- run HUD

local hud = Ui.card({ Name = "DungeonHud", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 10), Size = UDim2.fromOffset(px(460), px(44)), Visible = false, ZIndex = 3, Shadow = false, Parent = Ui.gui }, 22)
local hudText = label(hud, { Position = UDim2.fromOffset(px(16), 0), Size = UDim2.new(1, -px(130), 1, 0), Text = "", TextSize = px(15), ZIndex = 4 }, "Title")
local leaveB = pill(hud, { Name = "Leave", AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -6, 0.5, 0), Size = UDim2.fromOffset(px(104), px(32)), Text = "Leave", TextColor3 = C.Ink, ZIndex = 4 }, C.Soft)
local run: any = nil

local function paintHud()
	if not run then
		hud.Visible = false
		return
	end
	hud.Visible = true
	local d = DD.List[run.id]
	local stage = run.boss and "⚔ BOSS" or run.wave and string.format("Wave %d/%d", run.wave, run.waves) or "Get ready…"
	local left = run.left and run.left > 0 and string.format(" · %d left", run.left) or ""
	hudText.Text = string.format("%s %s · %s%s   %s%s   ⏱ %s", d.Icon, d.Name, run.mode, (run.n or 1) > 1 and ("  👥" .. run.n) or "", stage, left, fmt(run.endsAt - workspace:GetServerTimeNow()))
	hudText.TextColor3 = run.boss and C.Coral:Lerp(Color3.new(0, 0, 0), 0.2) or C.Ink
end

leaveB.Activated:Connect(function()
	Ui.call("Dungeon", "leave")
end)

----------------------------------------------------------------------------------------------
-- results

local results = Ui.card({ Name = "DungeonResults", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.45), Size = UDim2.fromOffset(px(440), px(320)), Visible = false, ZIndex = 40, Parent = Ui.gui }, 24)
local resBody = new("Frame", { Position = UDim2.fromOffset(px(18), px(16)), Size = UDim2.new(1, -px(36), 1, -px(32)), BackgroundTransparency = 1, ZIndex = 41, Parent = results }, {
	new("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder, HorizontalAlignment = Enum.HorizontalAlignment.Center }),
})

local function showResults(msg)
	clear(resBody)
	local r = msg.rewards
	local d = DD.List[msg.id]
	label(resBody, { LayoutOrder = 1, Size = UDim2.new(1, 0, 0, px(30)), Text = d.Icon .. " " .. d.Name .. " cleared!", TextSize = px(24), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 42 }, "Title")
	label(resBody, { LayoutOrder = 2, Size = UDim2.new(1, 0, 0, px(18)), Text = string.format("%s  ·  ⏱ %s%s", msg.mode, fmt(r.time), r.best and "  ·  new best!" or ""), TextColor3 = C.Sub, TextSize = px(14), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 42 }, "Bold")
	local line = string.format("+%s 💰   +%d %s Essence", Ui.fmt(r.coins), r.essence, EI[r.el] and EI[r.el].Icon or "")
	if r.first then
		line ..= (r.firstLegendary and ("   +%d 🌟 first clear"):format(r.firstLegendary) or r.firstScrolls and ("   +%d 📜 first clear"):format(r.firstScrolls) or "")
	end
	label(resBody, { LayoutOrder = 3, Size = UDim2.new(1, 0, 0, px(22)), Text = line, TextSize = px(16), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 42 }, "Title")
	if r.gear then
		label(resBody, { LayoutOrder = 5, Size = UDim2.new(1, 0, 0, px(20)), Text = string.format("⚔ %s (%s %s)", r.gear.n, r.gear.r, r.gear.t), TextColor3 = C.Lilac:Lerp(Color3.new(0, 0, 0), 0.3), TextSize = px(15), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 42 }, "Title")
	end
	if r.helper then
		label(resBody, { LayoutOrder = 4, Size = UDim2.new(1, 0, 0, px(18)), Text = "🤝 Helper reward: thanks for helping! (no key, so no runes this time)", TextColor3 = C.Sub, TextSize = px(13), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 42 }, "Bold")
	elseif (r.party or 1) > 1 then
		label(resBody, { LayoutOrder = 4, Size = UDim2.new(1, 0, 0, px(18)), Text = "👥 Cleared with a party of " .. r.party, TextColor3 = C.Sub, TextSize = px(13), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 42 }, "Bold")
	end
	for i, rune in r.runes do
		local rar = Runes.Rarities[rune.r]
		local _, perfect = Runes.quality(rune)
		local f = new("Frame", { LayoutOrder = 10 + i, Size = UDim2.new(1, 0, 0, px(54)), BackgroundColor3 = Ui.Theme.tint(rar.Color, 0.8), ZIndex = 42, Parent = resBody }, { corner(14) })
		Ui.stroke(rar.Color, 2).Parent = f
		label(f, { Position = UDim2.fromOffset(px(12), px(6)), Size = UDim2.new(1, -px(24), 0, px(20)), Text = string.format("💠 %s %s rune%s", rune.r, rune.set or "", perfect and "  ✨ PERFECT" or ""), TextColor3 = rar.Color:Lerp(Color3.new(0, 0, 0), 0.4), TextSize = px(16), ZIndex = 43 }, "Title")
		label(f, { Position = UDim2.fromOffset(px(12), px(28)), Size = UDim2.new(1, -px(24), 0, px(18)), Text = Runes.describe(rune), TextSize = px(14), ZIndex = 43 }, "Bold")
	end
	if r.bagFull then
		label(resBody, { LayoutOrder = 30, Size = UDim2.new(1, 0, 0, px(18)), Text = "Your rune bag was full, so a rune was lost. Sell some!", TextColor3 = C.Coral, TextSize = px(13), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 42 }, "Bold")
	end
	local ok = pill(resBody, { LayoutOrder = 40, Size = UDim2.fromOffset(px(160), px(40)), Text = "Great!", ZIndex = 42 }, C.Mint)
	ok.Activated:Connect(function()
		results.Visible = false
	end)
	results.Size = UDim2.fromOffset(px(440), px(170) + #r.runes * px(60) + (r.bagFull and px(24) or 0) + ((r.helper or (r.party or 1) > 1) and px(24) or 0) + (r.gear and px(26) or 0))
	results.Visible = true
	local sc = new("UIScale", { Scale = 0.6, Parent = results })
	TweenService:Create(sc, TweenInfo.new(0.4, Enum.EasingStyle.Back), { Scale = 1 }):Play()
	task.delay(0.5, function()
		sc:Destroy()
	end)
	Sfx.play("quest_done")
	task.delay(0.35, Sfx.play, "reveal_rare")
end

----------------------------------------------------------------------------------------------

function DungeonUi.start()
	local remote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("DungeonRun") :: RemoteEvent
	remote.OnClientEvent:Connect(function(msg)
		if typeof(msg) ~= "table" then
			return
		end
		if msg.kind == "start" then
			run = { id = msg.id, mode = msg.mode, endsAt = msg.endsAt, waves = msg.waves, n = msg.names and #msg.names or 1 }
			results.Visible = false
			Ui.toast(DD.List[msg.id].Icon .. " " .. DD.List[msg.id].Name .. ": defeat 3 waves and the boss!" .. (run.n > 1 and (" Party: " .. table.concat(msg.names, ", ")) or ""), "info")
			if msg.helper then
				Ui.toast("No key (or a full rune bag): you're helping this run for coins and Essence", "info")
			end
			Sfx.play("region")
		elseif msg.kind == "wave" and run then
			local newWave = run.wave ~= msg.wave
			run.wave, run.left, run.boss = msg.wave, msg.left, msg.boss
			run.n = msg.n or run.n
			if newWave then
				if msg.boss then
					Ui.toast("⚔ The dungeon boss appears!", "alert")
					Sfx.play("boss")
				else
					Ui.toast(string.format("Wave %d of %d", msg.wave, msg.of), "info")
					Sfx.play("warn")
				end
			end
		elseif msg.kind == "clear" then
			showResults(msg)
			if run then
				run.left = 0
			end
		elseif msg.kind == "lobby" then
			if msg.note then
				Ui.toast("👥 " .. msg.note, "info")
			end
			if panel.Visible then
				DungeonUi.refresh()
			end
		elseif msg.kind == "party" then
			if run then
				run.n = msg.n or run.n
			end
			Ui.toast("👥 " .. (msg.note or ""), "info")
		elseif msg.kind == "fail" then
			Ui.toast(msg.why or "The run ended", "warn")
		elseif msg.kind == "end" then
			run = nil
		end
		paintHud()
	end)
	task.spawn(function()
		while true do
			task.wait(0.5)
			paintHud()
		end
	end)
end

DungeonUi.debugParty = function()
	playMode = "party"
end
DungeonUi.debugState = function()
	return string.format("panel %s hud %s results %s run %s", tostring(panel.Visible), tostring(hud.Visible), tostring(results.Visible), run and (run.id .. " " .. tostring(run.wave)) or "none")
end

return DungeonUi

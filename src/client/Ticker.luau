-- Next-up ticker: one small card under the wallet that always shows the next three things
-- coming up (or happening now): titan, surge, night/day, Wandering Legend, expeditions,
-- sealed scrolls attuning, daily reset. Live events glow; clicking one with a place points
-- the Journey waypoint at it. "Two more minutes" made visible.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Ui = require(script.Parent.Ui)
local Sfx = require(script.Parent.Sfx)

local C = Ui.C
local px = Ui.px
local new = Ui.new
local EI = Config.ElementInfo
local Ticker = {}

local ROWS = 3
local ROW_H = px(30)

type Entry = { key: string, icon: string, text: string, at: number, active: boolean?, color: Color3?, pos: Vector3? }

local card = Ui.card({ Name = "Ticker", Position = UDim2.fromOffset(px(70), 10 + px(52)), Size = UDim2.fromOffset(px(270), ROW_H * ROWS + px(10)), ZIndex = 2, Shadow = false, Parent = Ui.gui }, 16)
local rows = {}
for i = 1, ROWS do
	local b = new("TextButton", { Name = "Row" .. i, Position = UDim2.fromOffset(px(6), px(5) + (i - 1) * ROW_H), Size = UDim2.new(1, -px(12), 0, ROW_H), BackgroundColor3 = C.Soft, BackgroundTransparency = 1, AutoButtonColor = false, Text = "", ZIndex = 3, Parent = card }, {
		new("UICorner", { CornerRadius = UDim.new(0, px(10)) }),
	})
	b:SetAttribute("NoTap", true)
	local icon = Ui.text({ Position = UDim2.fromOffset(px(4), 0), Size = UDim2.new(0, px(24), 1, 0), BackgroundTransparency = 1, TextScaled = false, TextSize = px(16), Text = "", ZIndex = 4, Parent = b }, "Title")
	local text = Ui.text({ Position = UDim2.fromOffset(px(30), 0), Size = UDim2.new(1, -px(98), 1, 0), BackgroundTransparency = 1, TextScaled = false, TextSize = px(13), TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd, Text = "", ZIndex = 4, Parent = b }, "Title")
	local time = Ui.text({ AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -px(6), 0, 0), Size = UDim2.new(0, px(64), 1, 0), BackgroundTransparency = 1, TextScaled = false, TextSize = px(13), TextXAlignment = Enum.TextXAlignment.Right, Text = "", ZIndex = 4, Parent = b }, "Title")
	rows[i] = { button = b, icon = icon, text = text, time = time, entry = nil :: Entry? }
end

local function fmt(sec: number): string
	sec = math.max(0, math.floor(sec))
	if sec >= 3600 then
		return string.format("%dh %02dm", sec // 3600, (sec % 3600) // 60)
	end
	return string.format("%d:%02d", sec // 60, sec % 60)
end

----------------------------------------------------------------------------------------------
-- sources

local function gather(now: number): { Entry }
	local out: { Entry } = {}
	local W = workspace
	-- titan
	local tUntil = W:GetAttribute("WorldBossUntil") or 0
	if tUntil > now then
		table.insert(out, { key = "titan", icon = "⚡", text = "Titan " .. (W:GetAttribute("WorldBossName") or "") .. " is out!", at = tUntil, active = true, color = C.Lilac, pos = Vector3.new(170, 0, -10) })
	else
		local at = W:GetAttribute("WorldBossAt")
		if at then
			table.insert(out, { key = "titan", icon = "⚡", text = "Titan at the Titan Field", at = at })
		end
	end
	-- surge (current one, and what comes next)
	local el = W:GetAttribute("SurgeElement")
	local sUntil = W:GetAttribute("SurgeUntil") or 0
	if el and EI[el] and sUntil > now then
		table.insert(out, { key = "surge", icon = EI[el].Icon, text = el .. " Surge", at = sUntil, active = true, color = EI[el].Color })
		local nextEl = Config.surgeAt(sUntil + 1)
		if nextEl == "Light" or nextEl == "Dark" then
			table.insert(out, { key = "surge2", icon = EI[nextEl].Icon, text = "Rare " .. nextEl .. " Surge", at = sUntil })
		end
	end
	-- day and night (Stage 2)
	local nightAt, dayAt = W:GetAttribute("NightAt"), W:GetAttribute("DayAt")
	if W:GetAttribute("IsNight") and dayAt then
		table.insert(out, { key = "night", icon = "🌙", text = "Night: more Dark monsters", at = dayAt, active = true, color = C.Lilac })
	elseif nightAt then
		table.insert(out, { key = "night", icon = "🌙", text = "Nightfall", at = nightAt })
	end
	-- Wandering Legend (Stage 3)
	local lUntil = W:GetAttribute("LegendUntil") or 0
	if lUntil > now then
		table.insert(out, { key = "legend", icon = "✨", text = (W:GetAttribute("LegendName") or "A Legend") .. " sighted!", at = lUntil, active = true, color = C.Sun, pos = W:GetAttribute("LegendPos") })
	end
	-- the player's own timers
	local p = Ui.profile
	if p then
		for _, x in p.expeditions or {} do
			local d = Config.Loops.Expeditions.Durations[x.dur]
			if d then
				local at = x.start + d.Minutes * 60
				table.insert(out, { key = "exp" .. tostring(x.start), icon = "🧭", text = at <= now and "Expedition is back!" or "Expedition back", at = at, active = at <= now, color = C.Mint })
			end
		end
		if p.dungeon then
			local DD = require(Shared.DungeonData)
			local copy = { keys = p.dungeon.keys, keyAt = p.dungeon.keyAt }
			local keys, nextAt = DD.refill(copy, now)
			if nextAt and keys < DD.KeyCap then
				table.insert(out, { key = "dkey", icon = "🗝", text = string.format("Dungeon key (%d/%d)", keys, DD.KeyCap), at = nextAt })
			end
		end
		local sealed = p.sealed
		for _, sl in (sealed and sealed.slots) or {} do
			local tier = Config.Sealed and Config.Sealed.Tiers[sl.tier]
			if tier then
				local at = sl.start + tier.Minutes * 60
				table.insert(out, { key = "seal" .. tostring(sl.start), icon = "🧺", text = at <= now and (tier.Name .. " is ready!") or (tier.Name .. " warming"), at = at, active = at <= now, color = C.Sun })
			end
		end
	end
	-- daily reset
	table.insert(out, { key = "daily", icon = "📋", text = "New daily quests", at = (now // 86400 + 1) * 86400 })
	return out
end

local function rank(list: { Entry }, now: number)
	table.sort(list, function(a, b)
		-- ready/live first (ready personal timers above world events), then soonest
		if (a.active == true) ~= (b.active == true) then
			return a.active == true
		end
		local ta = a.active and (a.at <= now and -1 or a.at) or a.at
		local tb = b.active and (b.at <= now and -1 or b.at) or b.at
		return ta < tb
	end)
end

----------------------------------------------------------------------------------------------

local Journey = nil -- set in start (avoids a require loop)
local shown: { [string]: boolean } = {}

local function render(now: number)
	local Unlocks = require(script.Parent.Unlocks)
	card.Visible = Ui.profile ~= nil and Unlocks.open(Ui.profile, "Ticker")
	local list = gather(now)
	rank(list, now)
	local seen = {}
	for i = 1, ROWS do
		local r = rows[i]
		local e = list[i]
		r.entry = e
		if not e then
			r.button.Visible = false
			continue
		end
		r.button.Visible = true
		r.icon.Text = e.icon
		r.text.Text = e.text
		local left = e.at - now
		r.time.Text = e.active and (left <= 0 and "Now!" or fmt(left)) or fmt(left)
		r.text.TextColor3 = e.active and (e.color or C.Ink):Lerp(Color3.new(0, 0, 0), 0.25) or C.Ink
		r.time.TextColor3 = e.active and (e.color or C.Mint):Lerp(Color3.new(0, 0, 0), 0.2) or C.Sub
		r.button.BackgroundTransparency = e.active and 0.15 or 1
		r.button.BackgroundColor3 = e.active and Ui.Theme.tint(e.color or C.Mint, 0.82) or C.Soft
		seen[e.key] = true
		if e.active and not shown[e.key] then
			-- a new live entry pops in
			local sc = new("UIScale", { Scale = 1.15, Parent = r.button })
			TweenService:Create(sc, TweenInfo.new(0.35, Enum.EasingStyle.Back), { Scale = 1 }):Play()
			task.delay(0.4, function()
				sc:Destroy()
			end)
		end
	end
	shown = {}
	for k in seen do
		shown[k] = true
	end
end

function Ticker.start(journey)
	Journey = journey
	for _, r in rows do
		r.button.Activated:Connect(function()
			local e = r.entry
			if e and e.pos and Journey and Journey.pointTo then
				Journey.pointTo(e.pos, e.at)
				Sfx.play("select")
				Ui.toast("Waypoint set: " .. e.text, "info")
			elseif e and e.key == "dkey" and Journey and Journey.pointTo then
				Journey.pointTo(Vector3.new(-24, 0, 58), os.time() + 180)
				Sfx.play("select")
				Ui.toast("Waypoint set: the Dungeon Gate in Haven", "info")
			elseif e and (e.key:sub(1, 3) == "exp") then
				Ui.open("Expeditions")
			elseif e and e.key:sub(1, 4) == "seal" then
				Ui.open("Shrine")
			end
		end)
	end
	task.spawn(function()
		while true do
			render(os.time())
			task.wait(1)
		end
	end)
end

return Ticker

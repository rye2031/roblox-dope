-- The five menu screens: Monsters (team + storage + detail, feed, awaken, sell), Shrine
-- (open scrolls, reveal), Index (species x element), Quests (daily + streak) and Weapons.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Monsters = require(Shared.Monsters)
local Ui = require(script.Parent.Ui)
local SummonReveal = require(script.Parent.SummonReveal)

local T = Config.Tuning
local C = Ui.C
local new, corner, text, button, px = Ui.new, Ui.corner, Ui.text, Ui.button, Ui.px
local EI = Config.ElementInfo
local STAR = "★"

local Panels = {}

local function stars(n: number): string
	return string.rep(STAR, n)
end

local function clear(f: Instance)
	for _, c in f:GetChildren() do
		if not c:IsA("UIListLayout") and not c:IsA("UIGridLayout") and not c:IsA("UIPadding") then
			c:Destroy()
		end
	end
end

local function label(parent: Instance, props: { [string]: any }, weight: string?)
	props.TextScaled = props.TextScaled or false
	props.TextSize = props.TextSize or px(15)
	props.TextXAlignment = props.TextXAlignment or Enum.TextXAlignment.Left
	props.ZIndex = props.ZIndex or 13
	props.Parent = parent
	return text(props, weight)
end

local function pill(parent: Instance, props: { [string]: any }, color: Color3)
	props.BackgroundColor3 = color
	props.TextScaled = false
	props.TextSize = props.TextSize or px(15)
	props.ZIndex = props.ZIndex or 13
	props.Radius = props.Radius or 18
	props.Parent = parent
	return button(props)
end

local function inTeam(p, uid: string): number?
	for i, u in p.team do
		if u == uid then
			return i
		end
	end
	return nil
end

local function countMonsters(p): number
	local n = 0
	for _ in p.monsters do
		n += 1
	end
	return n
end

----------------------------------------------------------------------------------------------
-- Monsters

local monPanel, monBody, monSub = Ui.panel("Monsters", "Monsters", "Your team of 3 follows you. The rest wait in storage.", C.Lilac, "🐾", true)
local SORTS = { "Power", "Stars", "Level", "Element", "Newest" }
local sortIdx = 1
local mode: string? = nil -- nil | "feed" | "sell" | "swap"
local swapKey: string? = nil -- overflow group being swapped in
local selected: { [string]: boolean } = {}
local feedTarget: string? = nil
local detailUid: string? = nil

local detail = Ui.card({ Name = "Detail", Size = UDim2.new(1, -32, 1, -px(76) - 16), Position = UDim2.fromOffset(16, px(76)), BackgroundColor3 = C.Card, Visible = false, ZIndex = 20, Parent = monPanel }, 18)
local detailScroll = new("ScrollingFrame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y, ScrollBarThickness = 4, BorderSizePixel = 0, ZIndex = 21, Parent = detail }, { new("UIListLayout", { Padding = UDim.new(0, 10), SortOrder = Enum.SortOrder.LayoutOrder }), Ui.pad(4, 4, 8, 8) })

local function sortedUids(p): { string }
	local list = {}
	for uid in p.monsters do
		table.insert(list, uid)
	end
	local key = SORTS[sortIdx]
	table.sort(list, function(a, b)
		local ma, mb = p.monsters[a], p.monsters[b]
		local sa, sb = Monsters.Species[ma.sp], Monsters.Species[mb.sp]
		if key == "Stars" and sa.Stars ~= sb.Stars then
			return sa.Stars > sb.Stars
		elseif key == "Level" and ma.lv ~= mb.lv then
			return ma.lv > mb.lv
		elseif key == "Element" and ma.el ~= mb.el then
			return table.find(Config.Elements, ma.el) < table.find(Config.Elements, mb.el)
		elseif key == "Newest" and ma.got ~= mb.got then
			return ma.got > mb.got
		end
		local pa, pb = Monsters.power(ma.sp, ma.lv, ma.aw), Monsters.power(mb.sp, mb.lv, mb.aw)
		if pa ~= pb then
			return pa > pb
		end
		return a < b
	end)
	return list
end

local function feedXp(p): (number, number)
	local xp, ups = 0, 0
	local target = feedTarget and p.monsters[feedTarget]
	for uid in selected do
		local m = p.monsters[uid]
		if m then
			xp += T.Feed.Xp(Monsters.Species[m.sp].Stars, m.lv)
			if target and m.sp == target.sp then
				ups += 1
			end
		end
	end
	return xp, ups
end

-- Level a monster would reach with `xp` more (capped like the server).
local function previewLevel(m, xp: number): number
	local cap = m.aw and T.MaxLevel or T.AwakenLevel
	local lv, cur = m.lv, m.xp + xp
	while lv < cap and cur >= T.XpToNext(lv) do
		cur -= T.XpToNext(lv)
		lv += 1
	end
	return lv
end

local function isAway(p, uid: string): boolean
	for _, x in p.expeditions or {} do
		if table.find(x.uids, uid) then
			return true
		end
	end
	return false
end

local function monsterCard(parent: Instance, p, uid: string, order: number, onClick: () -> ())
	local m = p.monsters[uid]
	local sp = Monsters.Species[m.sp]
	local info = EI[m.el]
	local slot = inTeam(p, uid)
	local picked = selected[uid]
	local card = new("TextButton", { Name = uid, LayoutOrder = order, Text = "", AutoButtonColor = true, BackgroundColor3 = picked and Ui.Theme.tint(C.Mint, 0.55) or C.Soft, ZIndex = 12, Parent = parent }, { corner(14) })
	if picked or uid == feedTarget then
		Ui.stroke(uid == feedTarget and C.Lilac or C.Mint, 3).Parent = card
	elseif m.el == "Light" or m.el == "Dark" then
		Ui.stroke(info.Color, 2).Parent = card
	end
	Ui.portrait(card, m.sp, m.el, UDim2.new(1, -12, 1, -px(40)), UDim2.fromOffset(6, 6), 13)
	label(card, { Position = UDim2.new(0, 6, 1, -px(36)), Size = UDim2.new(1, -12, 0, px(16)), Text = info.Icon .. " " .. stars(sp.Stars), TextColor3 = info.Color, TextSize = px(13), TextXAlignment = Enum.TextXAlignment.Center }, "Title")
	label(card, { Position = UDim2.new(0, 6, 1, -px(20)), Size = UDim2.new(1, -12, 0, px(16)), Text = "Lv " .. m.lv .. (m.aw and " ✦" or ""), TextSize = px(13), TextXAlignment = Enum.TextXAlignment.Center }, "Bold")
	if slot then
		local b = label(card, { Position = UDim2.fromOffset(4, 4), Size = UDim2.fromOffset(px(22), px(22)), Text = tostring(slot), TextColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 0, BackgroundColor3 = C.Mint, TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 15 }, "Title")
		corner(11).Parent = b
	end
	if m.lock then
		label(card, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -4, 0, 4), Size = UDim2.fromOffset(px(22), px(22)), Text = "🔒", TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 15 }, "Title")
	end
	if isAway(p, uid) then
		card.BackgroundTransparency = 0.4
		label(card, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 4), Size = UDim2.fromOffset(px(70), px(18)), Text = "🧭 Away", TextSize = px(12), TextColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 0, BackgroundColor3 = C.Sun, TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 15 }, "Title")
	end
	card.Activated:Connect(onClick)
	return card
end

local renderMonsters: () -> ()
local renderDetail: (string) -> ()

local function eligibleFood(p, uid: string): boolean
	local m = p.monsters[uid]
	return m and not m.lock and not inTeam(p, uid) and uid ~= feedTarget and not isAway(p, uid)
end

renderMonsters = function()
	local p = Ui.profile
	if not p then
		return
	end
	clear(monBody)
	local n = countMonsters(p)
	monSub.Text = string.format("Storage %d / %d  ·  Team of 3 follows you and fights", n, p.storageCap)

	-- Team row
	Ui.section(monBody, 1, "TEAM")
	local teamRow = new("Frame", { LayoutOrder = 2, Size = UDim2.new(1, 0, 0, px(86)), BackgroundTransparency = 1, ZIndex = 12, Parent = monBody }, { new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 10), SortOrder = Enum.SortOrder.LayoutOrder }) })
	for i = 1, 3 do
		local uid = p.team[i]
		local m = uid ~= "" and p.monsters[uid]
		local cell = new("TextButton", { LayoutOrder = i, Size = UDim2.new(1 / 3, -7, 1, 0), BackgroundColor3 = C.Soft, Text = "", AutoButtonColor = true, ZIndex = 12, Parent = teamRow }, { corner(16) })
		if m then
			local sp = Monsters.Species[m.sp]
			Ui.portrait(cell, m.sp, m.el, UDim2.fromOffset(px(70), px(70)), UDim2.fromOffset(8, 8), 13)
			label(cell, { Position = UDim2.fromOffset(px(70) + 16, px(12)), Size = UDim2.new(1, -px(70) - 22, 0, px(20)), Text = sp.Name, TextSize = px(17), TextTruncate = Enum.TextTruncate.AtEnd }, "Title")
			label(cell, { Position = UDim2.fromOffset(px(70) + 16, px(34)), Size = UDim2.new(1, -px(70) - 22, 0, px(16)), Text = EI[m.el].Icon .. " " .. stars(sp.Stars) .. "  Lv " .. m.lv, TextColor3 = EI[m.el].Color, TextSize = px(14) }, "Bold")
			label(cell, { Position = UDim2.fromOffset(px(70) + 16, px(54)), Size = UDim2.new(1, -px(70) - 22, 0, px(16)), Text = "Slot " .. i .. "  ·  ultimate on key " .. i, TextColor3 = C.Sub, TextSize = px(13) }, "Bold")
			cell.Activated:Connect(function()
				renderDetail(uid)
			end)
		else
			label(cell, { Size = UDim2.fromScale(1, 1), Text = "+ Empty slot " .. i .. "\nPick a monster below", TextColor3 = C.Sub, TextSize = px(15), TextXAlignment = Enum.TextXAlignment.Center }, "Bold")
		end
	end

	-- Toolbar
	-- Overflow (summons that arrived while storage was full)
	local ofKeys = {}
	local ofTotal = 0
	for k, c in p.overflow or {} do
		table.insert(ofKeys, k)
		ofTotal += c
	end
	if ofTotal > 0 and mode ~= "feed" and mode ~= "sell" then
		table.sort(ofKeys, function(a, b)
			local sa = Monsters.Species[string.match(a, "^(%w+):")].Stars
			local sb = Monsters.Species[string.match(b, "^(%w+):")].Stars
			if sa ~= sb then
				return sa > sb
			end
			return a < b
		end)
		local head = new("Frame", { LayoutOrder = 3, Size = UDim2.new(1, 0, 0, px(36)), BackgroundTransparency = 1, ZIndex = 12, Parent = monBody }, {
			new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 8), VerticalAlignment = Enum.VerticalAlignment.Center, SortOrder = Enum.SortOrder.LayoutOrder }),
		})
		label(head, { LayoutOrder = 1, Size = UDim2.new(1, -px(150), 1, 0), Text = string.format("OVERFLOW  ·  %d waiting (storage was full)", ofTotal), TextColor3 = C.Peach, TextSize = px(14) }, "Title")
		local sellAll = pill(head, { LayoutOrder = 2, Size = UDim2.fromOffset(px(130), px(32)), Text = "Sell all" }, C.Coral)
		sellAll.Activated:Connect(function()
			Ui.call("Overflow", "sellall")
		end)
		local ofList = new("Frame", { LayoutOrder = 4, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, ZIndex = 12, Parent = monBody }, {
			new("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }),
		})
		local full = countMonsters(p) >= p.storageCap
		for i, k in ofKeys do
			local spId, el = string.match(k, "^(%w+):(%w+)$")
			local sp = Monsters.Species[spId]
			local info = EI[el]
			local c = p.overflow[k]
			local row = new("Frame", { LayoutOrder = i, Size = UDim2.new(1, 0, 0, px(60)), BackgroundColor3 = swapKey == k and Ui.Theme.tint(C.Lilac, 0.75) or Ui.Theme.tint(C.Peach, 0.88), ZIndex = 12, Parent = ofList }, { corner(14) })
			Ui.portrait(row, spId, el, UDim2.fromOffset(px(48), px(48)), UDim2.fromOffset(6, 6), 13)
			label(row, { Position = UDim2.fromOffset(px(48) + 16, px(8)), Size = UDim2.new(1, -px(48) - px(380), 0, px(20)), Text = sp.Name .. "  ×" .. c, TextSize = px(17), TextTruncate = Enum.TextTruncate.AtEnd }, "Title")
			label(row, { Position = UDim2.fromOffset(px(48) + 16, px(30)), Size = UDim2.new(1, -px(48) - px(380), 0, px(18)), Text = info.Icon .. " " .. el .. "  " .. stars(sp.Stars) .. "  ·  Lv 1", TextColor3 = info.Color, TextSize = px(14) }, "Bold")
			local btns = new("Frame", { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -8, 0.5, 0), Size = UDim2.fromOffset(px(360), px(38)), BackgroundTransparency = 1, ZIndex = 13, Parent = row }, {
				new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Right, Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }),
			})
			local take = pill(btns, { LayoutOrder = 1, Size = UDim2.fromOffset(px(96), px(36)), Text = "Take", ZIndex = 14 }, full and C.Line or C.Mint)
			take.Activated:Connect(function()
				if full then
					Ui.toast("Storage is full: use Swap, sell extras or buy more storage", "warn")
					return
				end
				Ui.call("Overflow", "take", k)
			end)
			local swap = pill(btns, { LayoutOrder = 2, Size = UDim2.fromOffset(px(96), px(36)), Text = swapKey == k and "Picking..." or "Swap", ZIndex = 14 }, C.Lilac)
			swap.Activated:Connect(function()
				mode, swapKey, selected = "swap", k, {}
				renderMonsters()
			end)
			local value = Config.sellValue(sp.Stars, 1) * c
			local sell = pill(btns, { LayoutOrder = 3, Size = UDim2.fromOffset(px(150), px(36)), Text = "Sell · " .. Ui.fmt(value), ZIndex = 14 }, C.Coral)
			sell.Activated:Connect(function()
				Ui.call("Overflow", "sell", k)
			end)
		end
	end

	local bar = new("Frame", { LayoutOrder = 6, Size = UDim2.new(1, 0, 0, px(40)), BackgroundTransparency = 1, ZIndex = 12, Parent = monBody }, { new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 8), VerticalAlignment = Enum.VerticalAlignment.Center, SortOrder = Enum.SortOrder.LayoutOrder }) })
	if mode then
		local p2 = Ui.profile
		local nSel = 0
		for _ in selected do
			nSel += 1
		end
		local msg
		if mode == "swap" then
			local spId = swapKey and string.match(swapKey, "^(%w+):")
			msg = string.format("Swapping in %s: pick a stored monster to sell in its place", spId and Monsters.Species[spId].Name or "?")
		elseif mode == "feed" then
			local tm = p2.monsters[feedTarget]
			local xp, ups = feedXp(p2)
			local to = tm and previewLevel(tm, xp) or 0
			msg = string.format("Feeding %s: %d picked · +%s XP%s%s", tm and Monsters.Species[tm.sp].Name or "?", nSel, Ui.fmt(xp), tm and to > tm.lv and (" → Lv " .. to) or "", ups > 0 and (" · " .. ups .. " skill-up" .. (ups > 1 and "s" or "")) or "")
		else
			local coins = 0
			for uid in selected do
				local m = p2.monsters[uid]
				if m then
					coins += Config.sellValue(Monsters.Species[m.sp].Stars, m.lv)
				end
			end
			msg = string.format("Selling %d · +%s coins", nSel, Ui.fmt(coins))
		end
		label(bar, { LayoutOrder = 1, Size = UDim2.new(1, -px(250), 1, 0), Text = msg, TextSize = px(15), TextTruncate = Enum.TextTruncate.AtEnd }, "Title")
		local go = pill(bar, { LayoutOrder = 2, Size = UDim2.fromOffset(px(110), px(36)), Text = mode == "feed" and "Feed" or mode == "swap" and "Pick one" or "Sell" }, nSel > 0 and (mode == "feed" and C.Mint or C.Coral) or C.Line)
		go.Visible = mode ~= "swap"
		go.Activated:Connect(function()
			if nSel == 0 then
				return
			end
			local list = {}
			for uid in selected do
				table.insert(list, uid)
			end
			local ok
			if mode == "feed" then
				ok = Ui.call("Feed", feedTarget, list)
			else
				ok = Ui.call("Sell", list)
			end
			if ok then
				local back = mode == "feed" and feedTarget
				mode, selected, feedTarget = nil, {}, nil
				if back then
					task.wait(0.2)
					renderDetail(back)
				end
			end
		end)
		local cancel = pill(bar, { LayoutOrder = 3, Size = UDim2.fromOffset(px(110), px(36)), Text = "Cancel", TextColor3 = C.Sub }, C.Soft)
		cancel.Activated:Connect(function()
			local back = mode == "feed" and feedTarget
			mode, selected, feedTarget, swapKey = nil, {}, nil, nil
			if back then
				renderDetail(back)
			else
				renderMonsters()
			end
		end)
	else
		label(bar, { LayoutOrder = 1, Size = UDim2.fromOffset(px(90), px(36)), Text = "STORAGE", TextColor3 = C.Sub, TextSize = px(14) }, "Title")
		local sortB = pill(bar, { LayoutOrder = 2, Size = UDim2.fromOffset(px(140), px(36)), Text = "Sort: " .. SORTS[sortIdx], TextColor3 = C.Ink }, C.Soft)
		sortB.Activated:Connect(function()
			sortIdx = sortIdx % #SORTS + 1
			renderMonsters()
		end)
		local sellB = pill(bar, { LayoutOrder = 3, Size = UDim2.fromOffset(px(120), px(36)), Text = "Sell extras", TextColor3 = C.Ink }, C.Soft)
		sellB.Activated:Connect(function()
			mode, selected = "sell", {}
			renderMonsters()
		end)
		local step = (p.storageCap - T.StartStorage) // T.StorageStep + 1
		local price = T.StorageCost[step]
		local buy = pill(bar, { LayoutOrder = 4, Size = UDim2.fromOffset(px(190), px(36)), Text = "" }, C.Lilac)
		if price then
			Ui.setBuy(buy, "+" .. T.StorageStep .. " slots · " .. Ui.fmt(price), p.coins >= price and "afford" or "poor", C.Lilac)
		else
			Ui.setBuy(buy, "Storage maxed", "done", C.Lilac)
		end
		buy.Activated:Connect(function()
			if price then
				Ui.call("BuyStorage")
			end
		end)
	end

	-- Grid
	local grid = new("Frame", { LayoutOrder = 7, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, ZIndex = 12, Parent = monBody }, {
		new("UIGridLayout", { CellSize = UDim2.fromOffset(px(92), px(118)), CellPadding = UDim2.fromOffset(8, 8), SortOrder = Enum.SortOrder.LayoutOrder }),
	})
	local list = sortedUids(Ui.profile)
	if #list == 0 then
		label(monBody, { LayoutOrder = 8, Size = UDim2.new(1, 0, 0, px(40)), Text = "No monsters yet. Open a scroll at the Shrine!", TextColor3 = C.Sub }, "Bold")
	end
	for i, uid in list do
		if mode and not eligibleFood(p, uid) then
			continue
		end
		monsterCard(grid, p, uid, i, function()
			if mode == "swap" then
				local key = swapKey
				local ok = Ui.call("Overflow", "swap", key, uid)
				if ok then
					mode, swapKey, selected = nil, nil, {}
					renderMonsters()
				end
			elseif mode then
				selected[uid] = not selected[uid] or nil
				renderMonsters()
			else
				renderDetail(uid)
			end
		end)
	end
end

renderDetail = function(uid: string)
	local p = Ui.profile
	local m = p and p.monsters[uid]
	if not m then
		detail.Visible = false
		detailUid = nil
		renderMonsters()
		return
	end
	detailUid = uid
	detail.Visible = true
	clear(detailScroll)
	local sp = Monsters.Species[m.sp]
	local info = EI[m.el]
	local st = Monsters.stats(m.sp, m.lv, m.aw)

	-- header
	local head = new("Frame", { LayoutOrder = 1, Size = UDim2.new(1, 0, 0, px(150)), BackgroundTransparency = 1, ZIndex = 21, Parent = detailScroll })
	Ui.portrait(head, m.sp, m.el, UDim2.fromOffset(px(140), px(140)), UDim2.fromOffset(0, 4), 22)
	local x = px(140) + 16
	label(head, { Position = UDim2.fromOffset(x, 4), Size = UDim2.new(1, -x - px(110), 0, px(30)), Text = sp.Name, TextSize = px(28), ZIndex = 22 }, "Title")
	label(head, { Position = UDim2.fromOffset(x, px(36)), Size = UDim2.new(1, -x, 0, px(20)), Text = string.format("%s %s  ·  %s  ·  %s %s", info.Icon, m.el, stars(sp.Stars), sp.Role, sp.Range == "ranged" and "(ranged)" or "(melee)"), TextColor3 = info.Color, TextSize = px(16), ZIndex = 22 }, "Bold")
	local cap = m.aw and T.MaxLevel or T.AwakenLevel
	local need = T.XpToNext(m.lv)
	label(head, { Position = UDim2.fromOffset(x, px(60)), Size = UDim2.new(1, -x, 0, px(20)), Text = string.format("Level %d / %d%s", m.lv, cap, m.aw and "  ✦ Awakened" or ""), TextSize = px(17), ZIndex = 22 }, "Title")
	local xpBack = new("Frame", { Position = UDim2.fromOffset(x, px(84)), Size = UDim2.new(1, -x - 8, 0, px(10)), BackgroundColor3 = C.Soft, ZIndex = 22, Parent = head }, { corner(5) })
	new("Frame", { Size = UDim2.fromScale(m.lv >= cap and 1 or math.clamp(m.xp / need, 0, 1), 1), BackgroundColor3 = C.Sky, ZIndex = 23, Parent = xpBack }, { corner(5) })
	label(head, { Position = UDim2.fromOffset(x, px(98)), Size = UDim2.new(1, -x, 0, px(40)), Text = sp.Blurb, TextColor3 = C.Sub, TextSize = px(14), TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top, ZIndex = 22 }, "Bold")
	local back = pill(head, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -4, 0, 4), Size = UDim2.fromOffset(px(96), px(34)), Text = "← Back", TextColor3 = C.Ink, ZIndex = 22 }, C.Soft)
	back.Activated:Connect(function()
		detail.Visible = false
		detailUid = nil
		renderMonsters()
	end)

	-- stats
	local statRow = new("Frame", { LayoutOrder = 2, Size = UDim2.new(1, 0, 0, px(52)), BackgroundTransparency = 1, ZIndex = 21, Parent = detailScroll }, { new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }) })
	for i, s in { { "HP", st.hp, C.Mint }, { "ATK", st.atk, C.Coral }, { "DEF", st.def, C.Sky }, { "SPD", st.spd, C.Sun }, { "POWER", Monsters.power(m.sp, m.lv, m.aw), C.Lilac } } do
		local f = new("Frame", { LayoutOrder = i, Size = UDim2.new(0.2, -7, 1, 0), BackgroundColor3 = Ui.Theme.tint(s[3], 0.85), ZIndex = 21, Parent = statRow }, { corner(12) })
		label(f, { Position = UDim2.fromOffset(0, px(6)), Size = UDim2.new(1, 0, 0, px(14)), Text = s[1], TextColor3 = C.Sub, TextSize = px(12), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 22 }, "Title")
		label(f, { Position = UDim2.fromOffset(0, px(22)), Size = UDim2.new(1, 0, 0, px(22)), Text = Ui.fmt(s[2]), TextSize = px(20), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 22 }, "Title")
	end

	-- skills
	local kit = Monsters.skills(m.sp, m.el)
	local tags = { "Signature", "Auto skill", "Ultimate" }
	for i, s in kit do
		local r = new("Frame", { LayoutOrder = 2 + i, Size = UDim2.new(1, 0, 0, px(58)), BackgroundColor3 = C.Soft, ZIndex = 21, Parent = detailScroll }, { corner(12) })
		local lvl = m.sk[i] or 1
		label(r, { Position = UDim2.fromOffset(12, px(6)), Size = UDim2.new(1, -24, 0, px(20)), Text = string.format("%s  ·  %s  ·  Lv %d/%d  ·  %ss", s.Name, tags[i], lvl, T.Feed.MaxSkillLevel, tostring(math.floor(Monsters.skillCooldown(s.Cooldown, lvl) * 10) / 10)), TextSize = px(16), ZIndex = 22 }, "Title")
		label(r, { Position = UDim2.fromOffset(12, px(28)), Size = UDim2.new(1, -24, 0, px(26)), Text = s.Desc or "", TextColor3 = C.Sub, TextSize = px(13), TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top, ZIndex = 22 }, "Bold")
	end

	-- actions
	local acts = new("Frame", { LayoutOrder = 10, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, ZIndex = 21, Parent = detailScroll }, { new("UIGridLayout", { CellSize = UDim2.fromOffset(px(150), px(40)), CellPadding = UDim2.fromOffset(8, 8), SortOrder = Enum.SortOrder.LayoutOrder }) })
	local slot = inTeam(p, uid)
	if slot then
		local b = pill(acts, { LayoutOrder = 1, Text = "Remove from team", ZIndex = 22 }, C.Peach)
		b.Activated:Connect(function()
			if Ui.call("SetTeam", slot, "") then
				task.wait(0.15)
				renderDetail(uid)
			end
		end)
	else
		for i = 1, 3 do
			local b = pill(acts, { LayoutOrder = i, Text = p.team[i] == "" and ("Team slot " .. i) or ("Swap into slot " .. i), ZIndex = 22 }, C.Mint)
			b.Activated:Connect(function()
				if Ui.call("SetTeam", i, uid) then
					task.wait(0.15)
					renderDetail(uid)
				end
			end)
		end
	end
	local lockB = pill(acts, { LayoutOrder = 5, Text = m.lock and "🔒 Unlock" or "🔓 Lock", TextColor3 = C.Ink, ZIndex = 22 }, C.Soft)
	lockB.Activated:Connect(function()
		if Ui.call("Lock", uid, not m.lock) then
			task.wait(0.15)
			renderDetail(uid)
		end
	end)
	local feedB = pill(acts, { LayoutOrder = 6, Text = m.lv >= cap and "Feed (skills)" or "Feed", ZIndex = 22 }, C.Sky)
	feedB.Activated:Connect(function()
		mode, selected, feedTarget = "feed", {}, uid
		detail.Visible = false
		renderMonsters()
	end)
	if not m.aw then
		local ess, coins = T.Awaken.Essence(sp.Stars), T.Awaken.Coins(sp.Stars)
		local ready = m.lv >= T.AwakenLevel and (p.essence[m.el] or 0) >= ess and p.coins >= coins
		local awB = pill(acts, { LayoutOrder = 7, Text = "", ZIndex = 22 }, C.Sun)
		Ui.setBuy(awB, m.lv < T.AwakenLevel and ("Awaken at Lv " .. T.AwakenLevel) or "Awaken", ready and "afford" or "poor", C.Sun)
		awB.Activated:Connect(function()
			if Ui.call("Awaken", uid) then
				task.wait(0.15)
				renderDetail(uid)
			end
		end)
		label(detailScroll, { LayoutOrder = 11, Size = UDim2.new(1, 0, 0, px(18)), Text = string.format("Awakening: Lv %d, %d %s Essence (have %d), %s coins. +15%% stats and max level %d.", T.AwakenLevel, ess, m.el, p.essence[m.el] or 0, Ui.fmt(coins), T.MaxLevel), TextColor3 = C.Sub, TextSize = px(13), TextWrapped = true, ZIndex = 22 }, "Bold")
	end
	if not slot and not m.lock then
		local value = Config.sellValue(sp.Stars, m.lv)
		local sellB = pill(acts, { LayoutOrder = 8, Text = "Sell · " .. Ui.fmt(value), ZIndex = 22 }, C.Coral)
		sellB.Activated:Connect(function()
			if Ui.call("Sell", { uid }) then
				detail.Visible = false
				detailUid = nil
				renderMonsters()
			end
		end)
	end
end

Ui.onOpen.Monsters = function()
	mode, selected, feedTarget = nil, {}, nil
	detail.Visible = false
	detailUid = nil
	renderMonsters()
end
Panels.showMonster = function(uid: string)
	Ui.open("Monsters")
	renderDetail(uid)
end
-- Debug helpers (Studio playtests)
Panels.startFeed = function(uid: string, foods: { string }?)
	Ui.open("Monsters")
	mode, selected, feedTarget = "feed", {}, uid
	for _, f in foods or {} do
		selected[f] = true
	end
	detail.Visible = false
	renderMonsters()
end

----------------------------------------------------------------------------------------------
-- Shrine

local shrinePanel, shrineBody, shrineSub = Ui.panel("Shrine", "Summoning Shrine", "Open a scroll to befriend a random monster.", C.Sun, "📜")
local _ = shrinePanel
local renderShrine: () -> ()
local reveal: (any, string?) -> ()

local function doSummon(kind: string, count: number)
	local have = Ui.profile and Ui.profile.scrolls[kind] or 0
	if have <= 0 then
		Ui.toast("Scrolls drop from wild monsters, quests, bosses and your login streak", "info")
		return
	end
	if have < count then
		Ui.toast(string.format("You need %d %s scrolls to open %d at once (you have %d)", count, kind, count, have), "warn")
		return
	end
	local ok, _, res = Ui.call("Summon", kind, count)
	if ok and res then
		reveal(res, kind)
	end
end

local function oddsText(kind: string): string
	local w = T.Scrolls[kind].Stars
	local parts = {}
	for s = 1, 5 do
		if w[s] > 0 then
			table.insert(parts, string.format("%d★ %s%%", s, tostring(w[s])))
		end
	end
	return table.concat(parts, "  ·  ")
end

renderShrine = function()
	local p = Ui.profile
	if not p then
		return
	end
	clear(shrineBody)
	shrineSub.Text = string.format("Elements: Fire, Water, Wind 33%% each · Light and Dark %s%% each", tostring(T.Scrolls.Elements.Light))
	for i, kind in { "Regular", "Legendary" } do
		local accent = kind == "Regular" and C.Sky or C.Sun
		local have = p.scrolls[kind] or 0
		local r = Ui.row(shrineBody, i, accent, kind == "Regular" and "📜" or "🌟", kind .. " Scroll  ×" .. have, oddsText(kind))
		r.row.Size = UDim2.new(1, 0, 0, px(84))
		local multiN = T.Scrolls.MultiOpen
		Ui.setBuy(r.buy, have > 0 and "Open 1" or "None left", have > 0 and "afford" or "poor", accent)
		-- second button: open ten at once
		local ten = r.buy:Clone()
		ten.Name = "BuyTen"
		ten.Position = UDim2.new(1, -14 - px(128) - px(10), 0.5, 0)
		ten.Size = UDim2.fromOffset(px(112), px(44))
		ten.Parent = r.row
		Ui.setBuy(ten, "Open " .. multiN, have >= multiN and "afford" or "poor", C.Lilac)
		for _, l in { r.title, r.blurb } do
			l.Size = UDim2.new(1, -px(74) - px(270), l.Size.Y.Scale, l.Size.Y.Offset)
		end
		r.buy.Activated:Connect(function()
			doSummon(kind, 1)
		end)
		ten.Activated:Connect(function()
			doSummon(kind, multiN)
		end)
	end
	Ui.section(shrineBody, 3, "PITY")
	local four = T.Scrolls.PityFourStar - (p.pity.four or 0)
	local ld = T.Scrolls.PityLightDark - (p.pity.ld or 0)
	label(shrineBody, { LayoutOrder = 4, Size = UDim2.new(1, 0, 0, px(40)), Text = string.format("A 4★ or better is guaranteed within %d Regular scrolls.\nA Light or Dark monster is guaranteed within %d scrolls.", four, ld), TextColor3 = C.Sub, TextSize = px(14), TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top }, "Bold")
	Ui.section(shrineBody, 5, "WHERE SCROLLS COME FROM")
	label(shrineBody, { LayoutOrder = 6, Size = UDim2.new(1, 0, 0, px(40)), Text = "Wild monsters sometimes drop Regular scrolls (elites often). Bosses always drop 3, sometimes a Legendary. Every daily quest gives Regular scrolls, and so does your login streak.", TextColor3 = C.Sub, TextSize = px(14), TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top }, "Bold")
end
Ui.onOpen.Shrine = renderShrine

-- Full-screen reveal (single scroll or ten): see SummonReveal.
reveal = function(res, kind)
	local k = kind or res.kind or (res[1] and res[1].kind) or "Regular"
	local nOver = 0
	for _, r in (res.sp and { res } or res) do
		if r.overflow then
			nOver += 1
		end
	end
	if nOver > 0 then
		Ui.toast(string.format("Storage full: %d went to Overflow. Open Monsters to take, swap or sell %s", nOver, nOver > 1 and "them" or "it"), "warn")
	end
	SummonReveal.show(res, {
		kind = k,
		one = function()
			doSummon(k, 1)
		end,
		ten = function()
			doSummon(k, T.Scrolls.MultiOpen)
		end,
		done = function()
			SummonReveal.hide()
			renderShrine()
		end,
	})
	renderShrine()
end
Panels.reveal = function(res)
	reveal(res)
end

----------------------------------------------------------------------------------------------
-- Index

local _, indexBody, indexSub = Ui.panel("Index", "Index", "Every species in every element you've befriended.", C.Mint, "📖", true)
Ui.onOpen.Index = function()
	local p = Ui.profile
	if not p then
		return
	end
	clear(indexBody)
	local list = Monsters.ordered()
	local found = 0
	for k in p.index do
		local _ = k
		found += 1
	end
	indexSub.Text = string.format("Found %d of %d (%d species × 5 elements)", found, #list * 5, #list)
	-- collection rewards
	local claims = p.indexClaims or { m = {}, s = {} }
	Ui.section(indexBody, -3, "COLLECTION REWARDS")
	local strip = new("ScrollingFrame", { LayoutOrder = -2, Size = UDim2.new(1, 0, 0, px(92)), BackgroundTransparency = 1, CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.X, ScrollingDirection = Enum.ScrollingDirection.X, ScrollBarThickness = 4, BorderSizePixel = 0, ZIndex = 12, Parent = indexBody }, {
		new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }),
	})
	for mi, m in Config.Loops.IndexMilestones do
		local claimed = claims.m[tostring(mi)]
		local ready = not claimed and found >= m.n
		local parts = {}
		if m.coins then
			table.insert(parts, "💰" .. Ui.fmt(m.coins))
		end
		if m.scrolls then
			table.insert(parts, "📜" .. m.scrolls)
		end
		if m.legendary then
			table.insert(parts, "🌟" .. m.legendary)
		end
		local cell = new("TextButton", { LayoutOrder = mi, Size = UDim2.fromOffset(px(120), px(80)), Text = "", AutoButtonColor = ready, BackgroundColor3 = claimed and Ui.Theme.tint(C.Mint, 0.7) or ready and C.Sun or C.Soft, ZIndex = 12, Parent = strip }, { corner(14) })
		label(cell, { Position = UDim2.fromOffset(0, px(8)), Size = UDim2.new(1, 0, 0, px(22)), Text = claimed and ("✓ " .. m.n) or (m.n .. " found"), TextSize = px(17), TextColor3 = ready and Color3.new(1, 1, 1) or C.Ink, TextXAlignment = Enum.TextXAlignment.Center }, "Title")
		label(cell, { Position = UDim2.fromOffset(0, px(32)), Size = UDim2.new(1, 0, 0, px(18)), Text = table.concat(parts, " "), TextSize = px(13), TextColor3 = ready and Color3.new(1, 1, 1) or C.Sub, TextXAlignment = Enum.TextXAlignment.Center }, "Bold")
		label(cell, { Position = UDim2.fromOffset(0, px(54)), Size = UDim2.new(1, 0, 0, px(18)), Text = claimed and "Claimed" or ready and "Claim!" or string.format("%d / %d", math.min(found, m.n), m.n), TextSize = px(13), TextColor3 = ready and Color3.new(1, 1, 1) or C.Sub, TextXAlignment = Enum.TextXAlignment.Center }, "Title")
		cell.Activated:Connect(function()
			if ready then
				if Ui.call("IndexReward", "milestone", mi) then
					Ui.onOpen.Index()
				end
			end
		end)
	end
	label(indexBody, { LayoutOrder = -1, Size = UDim2.new(1, 0, 0, px(20)), Text = "Find all 5 elements of a species for a 🌟 Legendary scroll.", TextColor3 = C.Sub, TextSize = px(13) }, "Bold")
	local lastStars = 0
	for i, sp in list do
		if sp.Stars ~= lastStars then
			lastStars = sp.Stars
			Ui.section(indexBody, i * 2 - 1, stars(sp.Stars) .. (sp.Stars <= 2 and "  (great food for leveling)" or ""))
		end
		local r = new("Frame", { LayoutOrder = i * 2, Size = UDim2.new(1, 0, 0, px(64)), BackgroundColor3 = C.Soft, ZIndex = 12, Parent = indexBody }, { corner(14) })
		local any, all = false, true
		for _, el in Config.Elements do
			if p.index[sp.Id .. ":" .. el] then
				any = true
			else
				all = false
			end
		end
		if all and not claims.s[sp.Id] then
			r.BackgroundColor3 = Ui.Theme.tint(C.Sun, 0.7)
			local claim = pill(r, { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -(px(40) * 5 + 44), 0.5, 0), Size = UDim2.fromOffset(px(110), px(36)), Text = "Claim 🌟", ZIndex = 15 }, C.Sun)
			claim.Activated:Connect(function()
				if Ui.call("IndexReward", "species", sp.Id) then
					Ui.onOpen.Index()
				end
			end)
		elseif all then
			r.BackgroundColor3 = Ui.Theme.tint(C.Mint, 0.8)
		end
		local _, img = Ui.portrait(r, sp.Id, nil, UDim2.fromOffset(px(52), px(52)), UDim2.fromOffset(6, 6), 13)
		if not any then
			img.ImageColor3 = Color3.new(0, 0, 0)
			img.ImageTransparency = 0.6
		end
		label(r, { Position = UDim2.fromOffset(px(52) + 16, px(10)), Size = UDim2.new(0.45, 0, 0, px(20)), Text = any and sp.Name or "???", TextSize = px(17) }, "Title")
		label(r, { Position = UDim2.fromOffset(px(52) + 16, px(32)), Size = UDim2.new(0.45, 0, 0, px(18)), Text = sp.Role .. " · " .. (sp.Range == "ranged" and "ranged" or "melee"), TextColor3 = C.Sub, TextSize = px(13) }, "Bold")
		local dots = new("Frame", { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -10, 0.5, 0), Size = UDim2.fromOffset(px(40) * 5 + 24, px(40)), BackgroundTransparency = 1, ZIndex = 13, Parent = r }, { new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }) })
		for j, el in Config.Elements do
			local has = p.index[sp.Id .. ":" .. el]
			local d = Ui.dot(dots, has and EI[el].Color or C.Line, has and EI[el].Icon or "?", px(40))
			d.LayoutOrder = j
			d.Position = UDim2.new()
			d.AnchorPoint = Vector2.zero
			d.ZIndex = 14
		end
	end
end

----------------------------------------------------------------------------------------------
-- Quests

local _, questBody, questSub = Ui.panel("Quests", "Daily Quests", "New quests every day at 00:00 UTC.", C.Sky, "✓")
Ui.onOpen.Quests = function()
	local p = Ui.profile
	if not p then
		return
	end
	clear(questBody)
	local day, ready = Config.streakPreview(p, Config.today())
	local streakR = Config.streakReward(day)
	local sc = Config.streakScrolls(day)
	local sr = Ui.row(questBody, 1, C.Sun, "🔥", "Login streak · day " .. day, ready and string.format("Today's reward: %s coins%s", Ui.fmt(streakR), sc > 0 and string.format(" + %d 📜", sc) or "") or "Come back tomorrow for the next day")
	Ui.setBuy(sr.buy, ready and "Claim" or "Claimed", ready and "afford" or "done", C.Sun)
	sr.buy.Activated:Connect(function()
		if ready then
			Ui.call("ClaimStreak")
			task.wait(0.2)
			Ui.onOpen.Quests()
		end
	end)
	Ui.section(questBody, 2, "TODAY")
	local all = #p.daily.quests > 0
	for i, q in p.daily.quests do
		local def = Config.questDef(q.k)
		local r = Ui.row(questBody, 2 + i, C.Sky, def and def.Icon or "•", Config.questText(q.k, q.n), string.format("%d / %d  ·  %s coins + %d 📜", math.min(q.p, q.n), q.n, Ui.fmt(Config.questReward(p, q.t)), Config.questScrolls(q.t)))
		local done = q.p >= q.n
		if not q.c then
			all = false
		end
		Ui.setBuy(r.buy, q.c and "Claimed" or done and "Claim" or (math.floor(q.p / q.n * 100) .. "%"), q.c and "done" or done and "afford" or "poor", C.Sky)
		r.buy.Activated:Connect(function()
			if done and not q.c then
				Ui.call("ClaimQuest", i)
				task.wait(0.2)
				Ui.onOpen.Quests()
			end
		end)
	end
	local br = Ui.row(questBody, 10, C.Mint, "★", "All three done", "Bonus: " .. Ui.fmt(Config.questBonus(p)) .. " coins + " .. T.Quests.AllBonusScrolls .. " 📜")
	Ui.setBuy(br.buy, p.daily.bonus and "Claimed" or all and "Claim" or "Locked", p.daily.bonus and "done" or all and "afford" or "poor", C.Mint)
	br.buy.Activated:Connect(function()
		if all and not p.daily.bonus then
			Ui.call("ClaimQuest", "bonus")
			task.wait(0.2)
			Ui.onOpen.Quests()
		end
	end)
	questSub.Text = "New quests every day at 00:00 UTC. Rewards grow with each region boss you beat."
end

----------------------------------------------------------------------------------------------
-- Weapons

local _, weapBody, weapSub = Ui.panel("Weapons", "Smithy", "Pick your weapon. One weapon level is shared by all four.", C.Peach, "⚔")
Ui.onOpen.Weapons = function()
	local p = Ui.profile
	if not p then
		return
	end
	clear(weapBody)
	local lv = p.weapon.lv
	local s = Config.tamerStats(lv)
	local maxed = lv >= T.Tamer.MaxWeaponLevel
	local cost = not maxed and T.Tamer.WeaponLevelCost(lv) or 0
	local nx = Config.tamerStats(lv + 1)
	local up = Ui.row(weapBody, 1, C.Peach, "⬆", "Weapon level " .. lv .. " / " .. T.Tamer.MaxWeaponLevel, maxed and string.format("HP %d · ATK %d · DEF %d", s.hp, s.atk, s.def) or string.format("HP %d→%d · ATK %d→%d · DEF %d→%d", s.hp, nx.hp, s.atk, nx.atk, s.def, nx.def))
	Ui.setBuy(up.buy, maxed and "Maxed" or Ui.fmt(cost), maxed and "done" or p.coins >= cost and "afford" or "poor", C.Peach)
	up.buy.Activated:Connect(function()
		if not maxed then
			Ui.call("UpgradeWeapon")
			task.wait(0.2)
			Ui.onOpen.Weapons()
		end
	end)
	Ui.section(weapBody, 2, "WEAPONS")
	for i, kind in T.WeaponOrder do
		local w = T.Weapons[kind]
		local r = Ui.row(weapBody, 2 + i, C.Peach, w.Icon, w.Name .. (w.Ranged and "  (ranged)" or "  (melee)"), w.Blurb .. ". Q: " .. w.Skill.Name .. " (" .. w.Skill.Blurb:lower() .. ", " .. w.Skill.Cooldown .. "s)")
		local on = p.weapon.type == kind
		Ui.setBuy(r.buy, on and "Equipped" or "Equip", on and "done" or "afford", C.Peach)
		r.buy.Activated:Connect(function()
			if not on then
				Ui.call("SetWeapon", kind)
				task.wait(0.2)
				Ui.onOpen.Weapons()
			end
		end)
	end
	weapSub.Text = "All four are free to swap. Upgrades raise your HP, attack and defense."
end

----------------------------------------------------------------------------------------------
-- Live refresh when the profile changes while a panel is open

Ui.onProfile(function()
	if Ui.isOpen("Monsters") then
		if detailUid and detail.Visible then
			renderDetail(detailUid)
		else
			renderMonsters()
		end
	elseif Ui.isOpen("Shrine") then
		renderShrine()
	elseif Ui.isOpen("Quests") then
		Ui.onOpen.Quests()
	elseif Ui.isOpen("Weapons") then
		Ui.onOpen.Weapons()
	end
end)

return Panels

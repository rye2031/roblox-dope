-- Runes panel: the rune bag (filter, sort, quality, PERFECT tag), a detail card with each roll's
-- tier, per-roll Reforge, Lock, Sell and Unequip, bulk-sell of unlocked Commons, and a picker
-- mode the monster detail's sockets open ("pick a rune for <monster>").
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Monsters = require(Shared.Monsters)
local Runes = require(Shared.Runes)
local Ui = require(script.Parent.Ui)

local C = Ui.C
local new, corner, px = Ui.new, Ui.corner, Ui.px
local RunesUi = {}

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

local RANK = { Common = 1, Rare = 2, Epic = 3, Legendary = 4 }

local function pips(t: number): string
	return string.rep("◆", t) .. string.rep("◇", 4 - t)
end

local function rollText(roll): string
	local st = Runes.Stats[roll.s]
	local v = st.Tiers[roll.t]
	return string.format("%s +%s%s", st.Name, v % 1 == 0 and tostring(math.floor(v)) or string.format("%.1f", v), st.Pct and "%" or "")
end

local function monsterName(p, uid: string?): string?
	local m = uid and p.monsters[uid]
	return m and Monsters.Species[m.sp].Name or nil
end

-- state
local filter = "all" -- all | bag | on
local selected: string? = nil
local picking: { uid: string }? = nil
RunesUi.onPicked = nil :: ((string) -> ())? -- Panels sets this to go back to the monster

local panel, body, sub = Ui.panel("Runes", "Runes", "Each monster has 3 rune sockets. Runes drop from monsters, bosses and Legends.", C.Sky, "◆", true)

local function sortedIds(p): { string }
	local ids = {}
	for id, r in p.runes or {} do
		if filter == "bag" and r.on then
			continue
		elseif filter == "on" and not r.on then
			continue
		end
		if picking and r.on == picking.uid then
			continue
		end
		table.insert(ids, id)
	end
	table.sort(ids, function(a, b)
		local ra, rb = p.runes[a], p.runes[b]
		if RANK[ra.r] ~= RANK[rb.r] then
			return RANK[ra.r] > RANK[rb.r]
		end
		local qa, qb = Runes.quality(ra), Runes.quality(rb)
		if qa ~= qb then
			return qa > qb
		end
		return (tonumber(a:sub(2)) or 0) > (tonumber(b:sub(2)) or 0)
	end)
	return ids
end

local render: () -> ()

local function act(...)
	local ok, msg, data = Ui.call("Runes", ...)
	return ok, msg, data
end

local function runeCard(parent: Instance, p, id: string, order: number)
	local r = p.runes[id]
	local rar = Runes.Rarities[r.r]
	local q, perfect = Runes.quality(r)
	local b = Ui.button({ LayoutOrder = order, BackgroundColor3 = id == selected and Ui.Theme.tint(rar.Color, 0.75) or C.Soft, Text = "", ZIndex = 13, Parent = parent, Radius = 14 })
	Ui.stroke(rar.Color, id == selected and 3 or 2).Parent = b
	b.Name = "Rune_" .. id
	new("Frame", { Position = UDim2.fromOffset(0, 0), Size = UDim2.new(0, px(6), 1, 0), BackgroundColor3 = rar.Color, ZIndex = 14, Parent = b }, { corner(3) })
	label(b, { Position = UDim2.fromOffset(px(14), px(6)), Size = UDim2.new(1, -px(20), 0, px(18)), Text = string.format("💠 %s%s%s%s", r.r, r.set and (" · " .. r.set) or "", r.lock and "  🔒" or "", perfect and "  ✨ PERFECT" or ""), TextColor3 = rar.Color:Lerp(Color3.new(0, 0, 0), 0.35), TextSize = px(15), ZIndex = 14 }, "Title")
	label(b, { Position = UDim2.fromOffset(px(14), px(26)), Size = UDim2.new(1, -px(20), 0, px(34)), Text = Runes.describe(r), TextSize = px(13), TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top, ZIndex = 14 }, "Bold")
	local on = monsterName(p, r.on)
	label(b, { AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, px(14), 1, -px(6)), Size = UDim2.new(1, -px(20), 0, px(16)), Text = string.format("Quality %d%%%s", math.floor(q * 100 + 0.5), on and ("  ·  on " .. on) or ""), TextColor3 = C.Sub, TextSize = px(12), TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 14 }, "Bold")
	b.Activated:Connect(function()
		selected = selected ~= id and id or nil
		render()
	end)
	return b
end

local function detailCard(p, id: string)
	local r = p.runes[id]
	if not r then
		return
	end
	local rar = Runes.Rarities[r.r]
	local q, perfect = Runes.quality(r)
	local card = new("Frame", { Name = "Detail", LayoutOrder = 3, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundColor3 = Ui.Theme.tint(rar.Color, 0.86), ZIndex = 12, Parent = body }, {
		corner(16),
		Ui.pad(12, 12, 10, 10),
		new("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }),
	})
	Ui.stroke(rar.Color, 2).Parent = card
	local on = monsterName(p, r.on)
	label(card, { LayoutOrder = 1, Size = UDim2.new(1, 0, 0, px(24)), Text = string.format("💠 %s rune%s", r.r, perfect and "  ✨ PERFECT" or ""), TextColor3 = rar.Color:Lerp(Color3.new(0, 0, 0), 0.4), TextSize = px(20) }, "Title")
	if r.set and Runes.Sets[r.set] then
		label(card, { LayoutOrder = 3, Size = UDim2.new(1, 0, 0, px(18)), Text = string.format("%s set: rolls lean to %s %s; 2 on one monster = %s", r.set, Runes.Stats[Runes.Sets[r.set].Focus[1]].Name, Runes.Stats[Runes.Sets[r.set].Focus[2]].Name, Runes.Sets[r.set].Desc), TextColor3 = rar.Color:Lerp(Color3.new(0, 0, 0), 0.4), TextSize = px(13) }, "Title")
	end
	label(card, { LayoutOrder = 2, Size = UDim2.new(1, 0, 0, px(18)), Text = string.format("%d roll%s · quality %d%% · %s%s", #r.rolls, #r.rolls > 1 and "s" or "", math.floor(q * 100 + 0.5), on and ("equipped on " .. on) or "in your bag", (r.rf or 0) > 0 and string.format(" · reforged %d×", r.rf) or ""), TextColor3 = C.Sub, TextSize = px(13) }, "Bold")
	local cost = Runes.reforgeCost(r)
	for i, roll in r.rolls do
		local row = new("Frame", { Name = "Roll" .. i, LayoutOrder = 10 + i, Size = UDim2.new(1, 0, 0, px(40)), BackgroundColor3 = C.Card, ZIndex = 13, Parent = card }, { corner(12) })
		label(row, { Position = UDim2.fromOffset(px(12), 0), Size = UDim2.new(0, px(90), 1, 0), Text = pips(roll.t), TextColor3 = rar.Color:Lerp(Color3.new(0, 0, 0), 0.25), TextSize = px(16), ZIndex = 14 }, "Title")
		label(row, { Position = UDim2.fromOffset(px(100), 0), Size = UDim2.new(1, -px(100) - px(170), 1, 0), Text = string.format("%s  (tier %d)", rollText(roll), roll.t), TextSize = px(15), ZIndex = 14 }, "Title")
		local rb = pill(row, { Name = "Reforge", AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -6, 0.5, 0), Size = UDim2.fromOffset(px(160), px(30)), Text = "", ZIndex = 14 }, C.Lilac)
		Ui.setBuy(rb, "Reforge · " .. Ui.fmt(cost), p.coins >= cost and "afford" or "poor", C.Lilac)
		rb.Activated:Connect(function()
			act("reforge", id, i)
		end)
	end
	label(card, { LayoutOrder = 20, Size = UDim2.new(1, 0, 0, px(16)), Text = "Reforge re-rolls one roll (stat and tier). Each reforge on a rune costs 50% more.", TextColor3 = C.Sub, TextSize = px(12), TextWrapped = true }, "Bold")
	local acts = new("Frame", { LayoutOrder = 30, Size = UDim2.new(1, 0, 0, px(34)), BackgroundTransparency = 1, ZIndex = 13, Parent = card }, {
		new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }),
	})
	if picking then
		local eb = pill(acts, { Name = "Equip", LayoutOrder = 1, Size = UDim2.fromOffset(px(200), px(34)), Text = "Equip on " .. (monsterName(p, picking.uid) or "?") }, C.Mint)
		eb.Activated:Connect(function()
			local uid = picking and picking.uid
			if uid and act("equip", id, uid) then
				RunesUi.cancelPick(true)
			end
		end)
	end
	if r.on then
		local ub = pill(acts, { Name = "Unequip", LayoutOrder = 2, Size = UDim2.fromOffset(px(120), px(34)), Text = "Unequip", TextColor3 = C.Ink }, C.Soft)
		ub.Activated:Connect(function()
			act("unequip", id)
		end)
	end
	local lb = pill(acts, { Name = "Lock", LayoutOrder = 3, Size = UDim2.fromOffset(px(110), px(34)), Text = r.lock and "🔒 Unlock" or "🔓 Lock", TextColor3 = C.Ink }, C.Soft)
	lb.Activated:Connect(function()
		act("lock", id)
	end)
	if not r.lock and not r.on then
		local sb = pill(acts, { Name = "Sell", LayoutOrder = 4, Size = UDim2.fromOffset(px(140), px(34)), Text = "Sell · " .. Ui.fmt(rar.Sell) }, C.Coral)
		sb.Activated:Connect(function()
			if act("sell", { id }) then
				selected = nil
			end
		end)
	end
end

render = function()
	local p = Ui.profile
	if not p or not panel.Visible then
		return
	end
	clear(body)
	local runes = p.runes or {}
	if selected and not runes[selected] then
		selected = nil
	end
	local total, commons = 0, {}
	for id, r in runes do
		total += 1
		if r.r == "Common" and not r.lock and not r.on then
			table.insert(commons, id)
		end
	end
	sub.Text = string.format("Bag %d / %d  ·  3 sockets per monster  ·  drops from monsters, bosses, Legends and the Arena shop", total, Runes.BagCap)

	-- picker banner
	if picking then
		local ban = new("Frame", { LayoutOrder = 1, Size = UDim2.new(1, 0, 0, px(44)), BackgroundColor3 = Ui.Theme.tint(C.Mint, 0.8), ZIndex = 12, Parent = body }, { corner(14) })
		label(ban, { Position = UDim2.fromOffset(px(14), 0), Size = UDim2.new(1, -px(140), 1, 0), Text = "Pick a rune for " .. (monsterName(p, picking.uid) or "?") .. ", then press Equip", TextSize = px(16) }, "Title")
		local cb = pill(ban, { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -6, 0.5, 0), Size = UDim2.fromOffset(px(110), px(32)), Text = "← Back", TextColor3 = C.Ink }, C.Card)
		cb.Activated:Connect(function()
			RunesUi.cancelPick(true)
		end)
	end

	-- filters + bulk sell
	local bar = new("Frame", { LayoutOrder = 2, Size = UDim2.new(1, 0, 0, px(34)), BackgroundTransparency = 1, ZIndex = 12, Parent = body }, {
		new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }),
	})
	for i, f in { { "all", "All" }, { "bag", "In bag" }, { "on", "Equipped" } } do
		local b = pill(bar, { LayoutOrder = i, Size = UDim2.fromOffset(px(96), px(32)), Text = f[2], TextColor3 = filter == f[1] and Color3.new(1, 1, 1) or C.Ink }, filter == f[1] and C.Sky or C.Soft)
		b.Activated:Connect(function()
			filter = f[1]
			render()
		end)
	end
	if #commons > 0 then
		local sb = pill(bar, { Name = "SellCommons", LayoutOrder = 9, Size = UDim2.fromOffset(px(230), px(32)), Text = string.format("Sell %d unlocked Common%s · %s", #commons, #commons > 1 and "s" or "", Ui.fmt(#commons * Runes.Rarities.Common.Sell)) }, C.Coral)
		sb.Activated:Connect(function()
			act("sell", commons)
		end)
	end

	if selected then
		detailCard(p, selected)
	end

	local ids = sortedIds(p)
	if #ids == 0 then
		label(body, { LayoutOrder = 5, Size = UDim2.new(1, 0, 0, px(60)), Text = total == 0 and "No runes yet. Every wild monster has a small chance to drop one; elites more, bosses and Wandering Legends always. The Arena shop sells them too." or "Nothing here with this filter.", TextColor3 = C.Sub, TextWrapped = true }, "Bold")
		return
	end
	local grid = new("Frame", { Name = "Grid", LayoutOrder = 5, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, ZIndex = 12, Parent = body }, {
		new("UIGridLayout", { CellSize = UDim2.fromOffset(px(206), px(86)), CellPadding = UDim2.fromOffset(8, 8), SortOrder = Enum.SortOrder.LayoutOrder }),
	})
	for i, id in ids do
		runeCard(grid, p, id, i)
	end
end

-- Open the bag to choose a rune for a monster.
function RunesUi.pick(uid: string)
	picking = { uid = uid }
	selected = nil
	filter = "all"
	Ui.open("Runes")
end

function RunesUi.cancelPick(goBack: boolean?)
	local uid = picking and picking.uid
	picking = nil
	if goBack and uid and RunesUi.onPicked then
		RunesUi.onPicked(uid)
	else
		render()
	end
end

-- Toast + sound for a rune drop (Hud calls this from the kill rewards).
function RunesUi.dropped(rarity: string)
	local rar = Runes.Rarities[rarity]
	if rar then
		Ui.toast(string.format("💠 A %s rune dropped! Equip it from a monster's page", rarity), "good")
	end
end

Ui.onOpen.Runes = function()
	render()
end
-- keep the picker only while the panel is open
local was = false
panel:GetPropertyChangedSignal("Visible"):Connect(function()
	if was and not panel.Visible then
		picking = nil
	end
	was = panel.Visible
end)
Ui.onProfile(function()
	if panel.Visible then
		render()
	end
end)

-- debug
RunesUi.debugSelect = function(id: string?)
	selected = id
	render()
end
RunesUi.render = function()
	render()
end

return RunesUi

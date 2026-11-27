-- Tamer Pass panel: XP bar, the 50 tiers as cards (claim each, or Claim all), and the endless
-- bonus after the last tier. Everything here is free and never expires.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PassData = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("PassData"))
local Ui = require(script.Parent.Ui)

local C = Ui.C
local new, corner, px = Ui.new, Ui.corner, Ui.px
local PassUi = {}

local panel, body, sub = Ui.panel("Pass", "Tamer Pass", "Free rewards for playing: fighting, quests, dungeons, discoveries and the story all fill it.", C.Sun, "🎖", true)

local function label(parent: Instance, props: { [string]: any }, weight: string?)
	props.TextScaled = false
	props.TextSize = props.TextSize or px(14)
	props.BackgroundTransparency = 1
	props.ZIndex = props.ZIndex or 14
	props.Parent = parent
	return Ui.text(props, weight)
end

local function clear(f: Instance)
	for _, c in f:GetChildren() do
		if not c:IsA("UIListLayout") and not c:IsA("UIGridLayout") and not c:IsA("UIPadding") then
			c:Destroy()
		end
	end
end

local function render()
	local p = Ui.profile
	if not p or not panel.Visible then
		return
	end
	clear(body)
	local st = p.pass or { xp = 0, claimed = {}, bonus = 0 }
	local tier = PassData.tierAt(st.xp)
	local maxT = #PassData.Tiers
	local into = st.xp % PassData.XpPerTier
	-- progress card
	local top = new("Frame", { LayoutOrder = 1, Size = UDim2.new(1, 0, 0, px(70)), BackgroundColor3 = Ui.Theme.tint(C.Sun, 0.85), ZIndex = 12, Parent = body }, { corner(16) })
	label(top, { Position = UDim2.fromOffset(px(16), px(8)), Size = UDim2.new(1, -px(200), 0, px(24)), Text = tier >= maxT and "🎖 All 50 tiers done! Bonus scrolls keep coming" or string.format("🎖 Tier %d of %d", tier, maxT), TextSize = px(19), TextXAlignment = Enum.TextXAlignment.Left }, "Title")
	local back = new("Frame", { Position = UDim2.fromOffset(px(16), px(40)), Size = UDim2.new(1, -px(200), 0, px(14)), BackgroundColor3 = C.Card, ZIndex = 13, Parent = top }, { corner(7) })
	new("Frame", { Size = UDim2.fromScale(into / PassData.XpPerTier, 1), BackgroundColor3 = C.Sun, ZIndex = 14, Parent = back }, { corner(7) })
	label(top, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -px(190), 0, px(56)), Size = UDim2.fromOffset(px(160), px(12)), Text = string.format("%d / %d XP", into, PassData.XpPerTier), TextColor3 = C.Sub, TextSize = px(11), TextXAlignment = Enum.TextXAlignment.Right }, "Bold")
	local ready = 0
	for i = 1, math.min(tier, maxT) do
		if not st.claimed[tostring(i)] then
			ready += 1
		end
	end
	local bonusReady = PassData.bonusAvailable(st.xp) - (st.bonus or 0)
	local claimAll = Ui.button({ Name = "ClaimAll", AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -px(14), 0.5, 0), Size = UDim2.fromOffset(px(160), px(42)), BackgroundColor3 = (ready > 0 or bonusReady > 0) and C.Mint or C.Line, Text = ready > 0 and ("Claim all (" .. ready .. ")") or bonusReady > 0 and ("Claim bonus (" .. bonusReady .. ")") or "All claimed", TextScaled = false, TextSize = px(15), ZIndex = 13, Parent = top, Radius = 21 })
	claimAll.Activated:Connect(function()
		if ready > 0 then
			Ui.call("Pass", "all")
		elseif bonusReady > 0 then
			Ui.call("Pass", "bonus")
		end
	end)
	label(body, { LayoutOrder = 2, Size = UDim2.new(1, 0, 0, px(18)), Text = "Kills, elites, bosses, daily quests, dungeons, discoveries, story steps, Arena wins and expeditions all give Pass XP. No time limit.", TextColor3 = C.Sub, TextSize = px(12), TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Left }, "Bold")
	-- tiers grid
	local grid = new("Frame", { Name = "Tiers", LayoutOrder = 3, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, ZIndex = 12, Parent = body }, {
		new("UIGridLayout", { CellSize = UDim2.fromOffset(px(120), px(104)), CellPadding = UDim2.fromOffset(8, 8), SortOrder = Enum.SortOrder.LayoutOrder }),
	})
	for i, r in PassData.Tiers do
		local claimed = st.claimed[tostring(i)] == true
		local can = i <= tier and not claimed
		local big = i % 10 == 0
		local b = Ui.button({ Name = "Tier" .. i, LayoutOrder = i, BackgroundColor3 = claimed and Ui.Theme.tint(C.Mint, 0.8) or can and Ui.Theme.tint(C.Sun, 0.7) or C.Soft, Text = "", ZIndex = 13, Parent = grid, Radius = 14 })
		Ui.stroke(big and C.Sun or (can and C.Sun or C.Line), big and 3 or 2).Parent = b
		label(b, { Position = UDim2.fromOffset(0, px(6)), Size = UDim2.new(1, 0, 0, px(14)), Text = "Tier " .. i, TextColor3 = C.Sub, TextSize = px(11) }, "Title")
		label(b, { Position = UDim2.fromOffset(0, px(22)), Size = UDim2.new(1, 0, 0, px(30)), Text = PassData.icon(r), TextSize = px(big and 28 or 24) }, "Title")
		label(b, { Position = UDim2.fromOffset(px(4), px(54)), Size = UDim2.new(1, -px(8), 0, px(28)), Text = PassData.text(r), TextSize = px(11), TextWrapped = true }, "Bold")
		label(b, { Position = UDim2.new(0, 0, 1, -px(18)), Size = UDim2.new(1, 0, 0, px(14)), Text = claimed and "✓ Claimed" or can and "Claim!" or "🔒", TextColor3 = can and C.Coral or C.Sub, TextSize = px(11) }, "Title")
		b.Activated:Connect(function()
			if can then
				Ui.call("Pass", i)
			end
		end)
	end
	sub.Text = ready > 0 and string.format("%d reward%s ready to claim!", ready, ready > 1 and "s" or "") or "Free rewards for playing. No time limit, nothing to buy."
end

Ui.onOpen.Pass = render
Ui.onProfile(function()
	if panel.Visible then
		render()
	end
end)

-- How many rewards are ready (Hud shows a dot on the rail button).
function PassUi.ready(p): number
	local st = p.pass or { xp = 0, claimed = {} }
	local n = 0
	for i = 1, math.min(PassData.tierAt(st.xp), #PassData.Tiers) do
		if not st.claimed[tostring(i)] then
			n += 1
		end
	end
	return n + math.max(0, PassData.bonusAvailable(st.xp) - (st.bonus or 0))
end

return PassUi

-- Tips (2026-11-27, playtester: "you're gonna have to explain this to me"): short, friendly
-- explanations shown in context the first time something comes up: one at a time, never a
-- wall of text. Each is remembered in the save (p.tutorial["tip_<id>"]) so it shows once, and
-- the main menus get a small "?" button that replays their tips.
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local Ui = require(script.Parent.Ui)
local Sfx = require(script.Parent.Sfx)

local C = Ui.C
local new, px = Ui.new, Ui.px
local Tips = {}
local player = Players.LocalPlayer

-- id = { icon, title, text }. Keep every text to a sentence or two of plain words.
local TIPS = {
	welcome = { "🧭", "Welcome, Tamer!", "You collect monsters, and they fight beside you. Follow the green arrow to Mira to begin." },
	combat = { "⚔", "Fighting", "Your monster on the bottom right is active: press 1 or 2 for its skills when they glow. The other two use theirs on their own. X switches who's active. Click to swing your weapon." },
	dodge = { "💨", "Dodge!", "Red circles on the ground mean a big hit is coming. Press Shift (or the Dodge button) to roll out of the way." },
	Monsters = { "🐾", "Your monsters", "The 3 at the top follow you and fight. The rest wait in storage. Tap any monster to look at it, swap it in or power it up." },
	detail = { "⬆", "Making monsters stronger", "Use spare monsters to train this one: it levels up. Spares of the same species also power up its skills." },
	Shrine = { "🥚", "Summoning", "Hatch eggs to get new monsters. More stars means stronger and rarer. Light and Dark monsters are the rarest of all." },
	Runes = { "💠", "Runes", "Runes are gear for monsters. Each monster has 3 sockets: open a monster and tap an empty socket to add one." },
	Dungeons = { "🗝", "Dungeons", "A short fight: 3 waves and a boss, then a chest with runes. A win uses a key. Losing or leaving costs nothing." },
	Weapons = { "⚔", "Your weapons", "Rarer weapons hit harder and have bonus perks. Tap one to equip it. Weapon level makes every weapon stronger." },
	Expeditions = { "🧭", "Expeditions", "Send monsters you aren't using on a trip. They come back with coins and Crystals, even while you're offline." },
	Arena = { "🏟", "The Arena", "Battle other Tamers' teams, turn by turn. Pick a move for each monster, or press Auto." },
	Pass = { "🎖", "Tamer Pass", "Everything you do fills this bar. Each tier has a free reward: tap to claim. There's no time limit." },
	Travel = { "🔥", "Travel", "Jump to any campfire you've lit, from anywhere. Just not in the middle of a fight." },
	rune = { "💠", "You found a rune!", "Open a monster and tap one of its 3 sockets to put the rune on. It makes that monster stronger." },
	gear = { "⚔", "New weapon!", "Open Weapons (the Smithy) and tap it to equip it. Rarer ones glow." },
	awaken = { "✨", "Level 20!", "A monster reached level 20, its cap. Evolve it on its page to raise the cap to 40 and boost its stats." },
	auto = { "🤖", "Auto-Hunt", "Press R (or the Auto-Hunt button) and your Tamer fights nearby monsters for you, at a bit less reward." },
	ride = { "🐾", "Ride your monster", "Press F (or Ride) to hop on your lead monster and travel fast. A fight knocks you off." },
	portal = { "🌀", "Portals", "Glowing portals take you between places. A locked one tells you what opens it." },
}
-- phones have no keys: the same tips in tap words
if Ui.mobile then
	TIPS.combat[3] = "Your monster on the bottom right is active: tap its skills when they glow gold. The other two use theirs on their own. Tap one of them to make it active."
	TIPS.dodge[3] = "Red circles on the ground mean a big hit is coming. Tap the 💨 button to roll out of the way."
	TIPS.auto[3] = "Tap 🤖 Auto and your Tamer fights nearby monsters for you, at a bit less reward."
	TIPS.ride[3] = "Tap 🐾 Ride to hop on your lead monster and travel fast. A fight knocks you off."
end

-- Panels with a "?" button and which tips it replays.
local PANEL_TIPS = {
	Monsters = { "Monsters", "detail" },
	Shrine = { "Shrine" },
	Runes = { "Runes" },
	Dungeons = { "Dungeons" },
	Weapons = { "Weapons", "gear" },
	Expeditions = { "Expeditions" },
	Arena = { "Arena" },
	Travel = { "Travel" },
	Pass = { "Pass" },
}

local queue: { string } = {}
local showing = false
local forced: { [string]: boolean } = {}

-- Bottom left, just above the quest tracker (2026-11-28, playtester: the banner top right was
-- "weird"): a see-through card in HUD points that goes away on its own after LIFE seconds (a
-- thin bar shows the time left) or when tapped. Its own ScreenGui keeps it above menus, so a
-- menu's first-time tip shows over that menu.
local LIFE = 20
local gui = new("ScreenGui", { Name = "WildTips", DisplayOrder = 55, ResetOnSpawn = false, IgnoreGuiInset = false, Parent = player:WaitForChild("PlayerGui") })
local layer = Ui.hudLayer(gui) -- (phone preview: draws inside the phone frame)
local card = new("TextButton", { Name = "Tip", AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 8, 1, -60), Size = UDim2.fromOffset(260, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundColor3 = Color3.fromRGB(16, 20, 30), BackgroundTransparency = 0.3, AutoButtonColor = false, Text = "", Visible = false, ZIndex = 5, Parent = layer }, {
	new("UICorner", { CornerRadius = UDim.new(0, 12) }),
	new("UIPadding", { PaddingBottom = UDim.new(0, 9) }),
})
local content = new("Frame", { Position = UDim2.fromOffset(44, 7), Size = UDim2.new(1, -70, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, ZIndex = 6, Parent = card }, {
	new("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 1) }),
})
local icon = new("Frame", { Position = UDim2.fromOffset(8, 8), Size = UDim2.fromOffset(28, 28), BackgroundColor3 = Ui.Theme.tint(C.Mint, 0.3), BackgroundTransparency = 0.2, ZIndex = 6, Parent = card }, { new("UICorner", { CornerRadius = UDim.new(0.5, 0) }) })
local glyph = Ui.text({ Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, TextScaled = false, TextSize = 15, Text = "", ZIndex = 7, Parent = icon }, "Title")
Ui.text({ AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -6, 0, 4), Size = UDim2.fromOffset(16, 16), BackgroundTransparency = 1, TextScaled = false, TextSize = 15, Text = "×", TextColor3 = Color3.fromRGB(200, 205, 220), ZIndex = 7, Parent = card }, "Title")
-- time left (bottom edge; +6 because of the bottom padding)
local timeBack = new("Frame", { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, 6), Size = UDim2.new(1, -20, 0, 2), BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 0.8, BorderSizePixel = 0, ZIndex = 6, Parent = card })
local timeBar = new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = C.Mint, BorderSizePixel = 0, ZIndex = 7, Parent = timeBack })
local title = Ui.text({ LayoutOrder = 1, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, TextScaled = false, TextSize = 12, TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = Color3.new(1, 1, 1), Text = "", ZIndex = 6, Parent = content }, "Title")
local body = Ui.text({ LayoutOrder = 2, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, TextScaled = false, TextSize = 11, TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = Color3.fromRGB(215, 222, 235), Text = "", ZIndex = 6, Parent = content }, "Bold")
-- sit above the quest tracker (it grows with long steps)
local function place()
	local tr = Ui.hud:FindFirstChild("Journey") :: GuiObject?
	local k = Ui.hudScale or 1
	local above = (tr and tr.Visible) and tr.AbsoluteSize.Y / k + 6 or 0
	card.Position = UDim2.new(0, 8, 1, -8 - above)
end

local function seen(id: string): boolean
	local p = Ui.profile
	return p ~= nil and p.tutorial ~= nil and p.tutorial["tip_" .. id] == true
end

local showNext: () -> ()

local function dismiss()
	if not card.Visible then
		return
	end
	card.Visible = false
	showing = false
	task.delay(1.2, showNext)
end
card.Activated:Connect(dismiss)
local shownAt = 0
Tips.dismiss = dismiss -- debug
Tips.state = function()
	return string.format("showing %s (%s) queue %d", tostring(card.Visible), title.Text, #queue)
end

showNext = function()
	-- the dream intro has its own hints: tips wait until it's over
	if showing or #queue == 0 or player:GetAttribute("InIntro") then
		return
	end
	-- never on top of a conversation or a hatch: try again shortly
	if Ui.dialogOpen or require(script.Parent.SummonReveal).isOpen() then
		task.delay(1, showNext)
		return
	end
	local id = table.remove(queue, 1)
	if seen(id) and not forced[id] then
		showNext()
		return
	end
	forced[id] = nil
	local t = TIPS[id]
	if not t then
		showNext()
		return
	end
	showing = true
	glyph.Text, title.Text, body.Text = t[1], t[2], t[3]
	place()
	card.Visible = true
	local sc = new("UIScale", { Scale = 0.85, Parent = card })
	TweenService:Create(sc, TweenInfo.new(0.3, Enum.EasingStyle.Back), { Scale = 1 }):Play()
	task.delay(0.35, function()
		sc:Destroy()
	end)
	-- gone on its own after LIFE seconds
	local at = os.clock()
	shownAt = at
	timeBar.Size = UDim2.fromScale(1, 1)
	TweenService:Create(timeBar, TweenInfo.new(LIFE, Enum.EasingStyle.Linear), { Size = UDim2.fromScale(0, 1) }):Play()
	task.delay(LIFE, function()
		if shownAt == at and card.Visible then
			dismiss()
		end
	end)
	Sfx.play("toast")
	if not seen(id) then
		task.spawn(Ui.call, "Tutorial", "tip_" .. id)
	end
end

-- Queue a tip if it hasn't been seen (force = replay from a "?" button; front = jump the
-- queue, for the menu the player just opened).
function Tips.show(id: string, force: boolean?, front: boolean?)
	if not TIPS[id] or (seen(id) and not force) or table.find(queue, id) then
		return
	end
	if force then
		forced[id] = true
	end
	if front then
		table.insert(queue, 1, id)
	else
		table.insert(queue, id)
	end
	showNext()
end

function Tips.start()
	player:GetAttributeChangedSignal("InIntro"):Connect(function()
		if not player:GetAttribute("InIntro") then
			task.delay(2.5, showNext)
		end
	end)
	-- the first time a menu opens
	local open = Ui.open
	Ui.open = function(name: string?)
		open(name)
		if name and TIPS[name] then
			task.delay(0.4, Tips.show, name, false, true)
		end
	end
	-- a "?" in the corner of menus that have tips
	for name, list in PANEL_TIPS do
		local panel = Ui.panels[name]
		if panel then
			local q = Ui.button({ Name = "Help", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -16 - px(46), 0, 16), Size = UDim2.fromOffset(px(38), px(38)), BackgroundColor3 = Ui.Theme.tint(C.Mint, 0.75), TextColor3 = C.Ink, TextScaled = false, TextSize = px(18), Text = "?", ZIndex = 11, Parent = panel, Radius = 19 })
			q.Activated:Connect(function()
				for _, id in list do
					Tips.show(id, true)
				end
			end)
		end
	end
	-- moments in play: only when they happen this session (a returning player isn't greeted
	-- with a pile of tips about things they already know)
	local first = true
	local hadL20, hadAuto = false, false
	Ui.onProfile(function(p)
		local l20 = false
		for _, m in p.monsters or {} do
			if m.lv >= 20 and not m.aw then
				l20 = true
				break
			end
		end
		local auto = p.kills >= 1
		if first then
			first = false
			hadL20, hadAuto = l20, auto
			-- brand-new players only (still on the first steps of the journey)
			if (p.story and p.story.i or 1) <= 2 then
				task.delay(4, Tips.show, "welcome")
			end
			return
		end
		if l20 and not hadL20 then
			Tips.show("awaken")
		end
		if auto and not hadAuto then
			Tips.show("auto")
		end
		hadL20, hadAuto = l20, auto
	end)
	player:GetAttributeChangedSignal("InCombat"):Connect(function()
		if player:GetAttribute("InCombat") then
			Tips.show("combat")
		end
	end)
	player:GetAttributeChangedSignal("Region"):Connect(function()
		local r = player:GetAttribute("Region")
		if r and r ~= "Haven" and r ~= "TitanField" then
			Tips.show("portal")
			Tips.show("ride")
		end
	end)
	local function watchHp(char: Model)
		local hum = char:WaitForChild("Humanoid", 10) :: Humanoid?
		if hum then
			hum.HealthChanged:Connect(function(h)
				if h < hum.MaxHealth * 0.6 and h > 0 then
					Tips.show("dodge")
				end
			end)
		end
	end
	player.CharacterAdded:Connect(watchHp)
	if player.Character then
		task.spawn(watchHp, player.Character)
	end
end

return Tips

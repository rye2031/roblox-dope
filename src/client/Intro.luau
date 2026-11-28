-- The dream intro on the client (server: Intro.luau). A soft dream screen with typed lines,
-- three quick questions (each answer leans Fire, Water or Wind), the starter eggs hatching
-- one after another, a tiny shadow fight to learn the buttons, then "you wake up". A Skip
-- button is always there.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Ui = require(script.Parent.Ui)
local Sfx = require(script.Parent.Sfx)

local C, px, new = Ui.C, Ui.px, Ui.new
local Intro = {}
local player = Players.LocalPlayer

local QUESTIONS = {
	{ "A storm rolls over the hills. What do you do?", { { "Run out and race the lightning!", "Fire" }, { "Watch the rain from the window", "Water" }, { "Fly a kite in the wind", "Wind" } } },
	{ "A lost little creature is crying. You...", { { "Cheer it up with a silly dance", "Fire" }, { "Sit with it until it feels safe", "Water" }, { "Help it find its way home", "Wind" } } },
	{ "Pick a place to explore first:", { { "A glowing volcano", "Fire" }, { "A secret beach cove", "Water" }, { "The floating sky islands", "Wind" } } },
}
local ELEMENT_LINE = {
	Fire = "Your heart burns bright and brave, like Fire.",
	Water = "Your heart is calm and kind, like Water.",
	Wind = "Your heart is free and curious, like Wind.",
}

local gui = new("ScreenGui", { Name = "WildDream", DisplayOrder = 80, ResetOnSpawn = false, IgnoreGuiInset = true, Enabled = false, Parent = player:WaitForChild("PlayerGui") })
local layer = Ui.layer(gui) -- (phone preview: draws inside the phone frame)
local veil = new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromRGB(236, 228, 255), BackgroundTransparency = 0, Active = true, ZIndex = 1, Parent = layer }, {
	new("UIGradient", { Color = ColorSequence.new(Color3.fromRGB(255, 240, 250), Color3.fromRGB(214, 220, 255)), Rotation = 90 }),
})
local box = new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(px(640), px(320)), BackgroundTransparency = 1, ZIndex = 2, Parent = layer })
local line = Ui.text({ Position = UDim2.fromOffset(0, 0), Size = UDim2.new(1, 0, 0, px(110)), BackgroundTransparency = 1, TextScaled = false, TextSize = px(26), TextWrapped = true, TextColor3 = Color3.fromRGB(90, 70, 150), Text = "", ZIndex = 3, Parent = box }, "Title")
local answers = new("Frame", { Position = UDim2.fromOffset(0, px(130)), Size = UDim2.new(1, 0, 0, px(180)), BackgroundTransparency = 1, ZIndex = 3, Parent = box }, {
	new("UIListLayout", { Padding = UDim.new(0, px(10)), HorizontalAlignment = Enum.HorizontalAlignment.Center, SortOrder = Enum.SortOrder.LayoutOrder }),
})
local skip = Ui.button({ Name = "Skip", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -px(20), 0, px(20)), Size = UDim2.fromOffset(px(140), px(40)), BackgroundColor3 = Color3.fromRGB(255, 255, 255), TextColor3 = C.Sub, Text = "Skip intro", TextScaled = false, TextSize = px(15), ZIndex = 5, Parent = layer, Radius = 20 })
local hint = Ui.card({ Name = "DreamHint", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, px(90)), Size = UDim2.fromOffset(px(520), px(70)), Visible = false, ZIndex = 4, Parent = layer }, 20)
Ui.stroke(C.Lilac, 3).Parent = hint
local hintText = Ui.text({ Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, TextScaled = false, TextSize = px(18), TextWrapped = true, Text = "", ZIndex = 5, Parent = hint }, "Title")
if Ui.mobile then
	-- below the HUD's target card, left of the quest pill
	hint.Position = UDim2.new(0.5, 0, 0, 116)
	hint.Size = UDim2.fromOffset(350, 56)
	hintText.TextSize = 13
end

local token = 0
local debugPick: number? = nil
local debugNext = false
local ask = nil :: RemoteFunction?

local function call(action: string, a: any?)
	local ok, r1, r2, r3 = pcall(function()
		return (ask :: RemoteFunction):InvokeServer(action, a)
	end)
	return ok and r1, r2, r3
end

local function alive(my: number): boolean
	return token == my and gui.Enabled
end

local function say(text: string, my: number, hold: number?)
	line.Text = ""
	line.TextTransparency = 0
	for i = 1, #text do
		if not alive(my) then
			return false
		end
		line.Text = string.sub(text, 1, i)
		if i % 3 == 0 then
			task.wait(0.025)
		end
	end
	task.wait(hold or 1.4)
	return alive(my)
end

local function choose(q, my: number): string?
	line.Text = q[1]
	local picked: string? = nil
	for i, opt in q[2] do
		local b = Ui.button({ LayoutOrder = i, Size = UDim2.fromOffset(px(440), px(48)), BackgroundColor3 = Color3.fromRGB(255, 255, 255), TextColor3 = Color3.fromRGB(90, 70, 150), Text = opt[1], TextScaled = false, TextSize = px(18), ZIndex = 4, Parent = answers, Radius = 24 })
		Ui.stroke(C.Lilac, 2).Parent = b
		b.Activated:Connect(function()
			if not picked then
				picked = opt[2]
				Sfx.play("select")
			end
		end)
	end
	while not picked and alive(my) do
		if debugPick then
			picked = q[2][debugPick][2]
			debugPick = nil
		end
		task.wait()
	end
	for _, c in answers:GetChildren() do
		if c:IsA("TextButton") then
			c:Destroy()
		end
	end
	return picked
end

local function fadeVeil(to: number, t: number)
	TweenService:Create(veil, TweenInfo.new(t), { BackgroundTransparency = to }):Play()
end

local function showHint(text: string?)
	hint.Visible = text ~= nil
	hintText.Text = text or ""
end

local function run()
	token += 1
	local my = token
	gui.Enabled = true
	veil.Visible = true
	veil.BackgroundTransparency = 0
	box.Visible = true
	showHint(nil)
	if not say("...", my, 0.8) then return end
	if not say("You're dreaming.", my) then return end
	if not say("A soft, friendly voice drifts through the clouds.", my) then return end
	if not say("\"Hello, little Tamer. Tell me a little about yourself...\"", my, 1.2) then return end
	-- the quiz
	local votes = { Fire = 0, Water = 0, Wind = 0 }
	local last = "Fire"
	for _, q in QUESTIONS do
		local el = choose(q, my)
		if not el then
			return
		end
		votes[el] += 1
		last = el
	end
	local best, bv = last, votes[last]
	for el, v in votes do
		if v > bv then
			best, bv = el, v
		end
	end
	call("answer", best)
	local info = Config.ElementInfo[best]
	line.TextColor3 = info.Color:Lerp(Color3.new(0, 0, 0), 0.25)
	if not say(info.Icon .. " " .. ELEMENT_LINE[best], my, 1.6) then return end
	line.TextColor3 = Color3.fromRGB(90, 70, 150)
	if not say("\"Here is a Legendary Egg, just for you...\"", my, 1.2) then return end
	-- the eggs hatch, one after another, with the real reveal (the dream backdrop steps aside:
	-- it draws above the reveal's own screen)
	box.Visible = false
	veil.Visible = false
	local ok, _, res = call("hatch")
	if ok and typeof(res) == "table" then
		local SummonReveal = require(script.Parent.SummonReveal)
		-- first the Legendary egg on its own, then a Hatch-10 of Regular eggs
		local shows = {}
		if res.legendary then
			table.insert(shows, res.legendary)
		end
		if res.ten and #res.ten > 0 then
			table.insert(shows, res.ten)
		end
		for n, r in shows do
			if not alive(my) then
				return
			end
			if n == 2 then
				box.Visible = true
				veil.Visible = true
				if not say("\"...and ten more eggs to build your team!\"", my, 1.2) then return end
				box.Visible = false
				veil.Visible = false
			end
			local done = false
			task.spawn(require(script.Parent.Wins).summoned, r)
			SummonReveal.show(r, {
				kind = "Intro",
				one = function()
					done = true
				end,
				ten = function()
					done = true
				end,
				done = function()
					done = true
				end,
			})
			debugNext = false
			while not done and alive(my) and not debugNext do
				task.wait()
			end
			debugNext = false
			SummonReveal.hide()
		end
	end
	if not alive(my) then return end
	-- the shadow fight on the cloud island (no veil: it would block the fight buttons)
	veil.BackgroundTransparency = 1
	veil.Visible = false
	box.Visible = false
	task.wait(0.8)
	showHint(Ui.mobile and "A shadow appears! Your monsters fight on their own.\nTap ⚔ to swing. Tap a glowing monster button for a big move." or "A shadow appears! Your monsters fight on their own.\nClick to swing. Press 1 when a big move glows.")
	call("fight")
	Sfx.play("warn")
	local won = false
	local remote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Intro") :: RemoteEvent
	local conn = remote.OnClientEvent:Connect(function(msg)
		if typeof(msg) == "table" and msg.kind == "won" then
			won = true
		end
	end)
	local t0 = os.clock()
	while not won and alive(my) and os.clock() - t0 < 90 do
		task.wait(0.2)
	end
	conn:Disconnect()
	if not alive(my) then return end
	showHint(won and "You did it! The shadow fades away..." or "The dream is fading...")
	Sfx.play("quest_done")
	task.wait(2)
	-- wake up
	showHint(nil)
	box.Visible = true
	veil.Visible = true
	fadeVeil(0, 1)
	task.wait(1)
	if not say("Everything goes bright...", my, 1) then return end
	call("done")
	task.wait(0.6)
	fadeVeil(1, 1.2)
	box.Visible = false
	task.wait(1.2)
	veil.Visible = false
	gui.Enabled = false
	Ui.toast("You wake up in Haven with your new team! Go say hi to Mira 🧭", "good")
end

function Intro.start()
	ask = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("IntroAsk") :: RemoteFunction
	local remote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Intro") :: RemoteEvent
	remote.OnClientEvent:Connect(function(msg)
		if typeof(msg) == "table" and msg.kind == "begin" then
			task.spawn(run)
		end
	end)
	skip.Activated:Connect(function()
		token += 1
		require(script.Parent.SummonReveal).hide()
		call("skip")
		showHint(nil)
		gui.Enabled = false
		Ui.toast("Skipped the dream. Your eggs are waiting at the Summoning Shrine!", "info")
	end)
end

Intro.state = function()
	return string.format("enabled %s line '%s' answers %d hint %s", tostring(gui.Enabled), line.Text, #answers:GetChildren() - 1, hint.Visible and hintText.Text or "-")
end
-- Studio tests (synthetic clicks can't press GUI): answer with option i / move past a reveal.
Intro.pick = function(i: number)
	debugPick = i
end
Intro.next = function()
	debugNext = true
end

return Intro

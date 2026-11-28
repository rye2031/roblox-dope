-- Tamer's Journey on the client: the objective tracker (top right), a waypoint marker at the
-- objective plus a ground arrow by your feet, the guides' dialogue box, the "step done" /
-- "chapter complete" moments, and campfire fast travel.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local StoryData = require(Shared.StoryData)
local Places = require(Shared.Places)
local Ui = require(script.Parent.Ui)
local Sfx = require(script.Parent.Sfx)

local C = Ui.C
local px = Ui.px
local new = Ui.new
local player = Players.LocalPlayer
local Journey = {}

local COUNTED = { defeat = true, feed = true, ult = true, summon = true }
local REGION_NAMES = { Haven = "Haven", SproutMeadow = "Sprout Meadow", EmberCanyon = "Ember Canyon", TideCoast = "Tide Coast", GaleHighlands = "Gale Highlands", TwilightVale = "Twilight Vale" }
local CAMPFIRE_ORDER = { "Haven", "SproutMeadow", "EmberCanyon", "TideCoast", "GaleHighlands", "TwilightVale" }

local function label(parent: Instance, props: { [string]: any }, weight: string?)
	props.BackgroundTransparency = props.BackgroundTransparency or 1
	props.TextScaled = false
	props.Parent = parent
	return Ui.text(props, weight or "Title")
end

----------------------------------------------------------------------------------------------
-- Tracker

local tracker = Ui.card({ Name = "Journey", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -px(16), 0, px(64)), Size = UDim2.fromOffset(px(300), px(86)), ZIndex = 3, Shadow = false, Parent = Ui.gui }, 16)
local tChapter = label(tracker, { Position = UDim2.fromOffset(px(14), px(8)), Size = UDim2.new(1, -px(28), 0, px(16)), Text = "", TextSize = px(13), TextColor3 = C.Lilac, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 4 })
local tText = label(tracker, { Position = UDim2.fromOffset(px(14), px(26)), Size = UDim2.new(1, -px(28), 0, px(38)), Text = "", TextSize = px(16), TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top, ZIndex = 4 })
local tInfo = label(tracker, { Position = UDim2.new(0, px(14), 1, -px(22)), Size = UDim2.new(1, -px(28), 0, px(16)), Text = "", TextSize = px(13), TextColor3 = C.Sub, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 4 }, "Bold")
local tScale = new("UIScale", { Parent = tracker })
-- phones: a small quest pill under the top-right buttons
if Ui.mobile then
	tracker.Position = UDim2.new(1, -8, 0, 50)
	tracker.Size = UDim2.fromOffset(236, 54)
	tChapter.Visible = false
	tText.Position = UDim2.fromOffset(10, 5)
	tText.Size = UDim2.new(1, -20, 0, 30)
	tText.TextSize = 12
	tInfo.Position = UDim2.new(0, 10, 1, -17)
	tInfo.Size = UDim2.new(1, -20, 0, 13)
	tInfo.TextSize = 10
end

local travelB = Ui.button({ AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -px(16), 0, px(158)), Size = UDim2.fromOffset(px(170), px(40)), BackgroundColor3 = C.Peach, Text = "🔥 Fast travel", TextScaled = false, TextSize = px(16), Visible = false, ZIndex = 3, Parent = Ui.gui, Radius = 20 })

----------------------------------------------------------------------------------------------
-- Waypoint marker + ground arrow

local markerPart = new("Part", { Name = "JourneyMarker", Anchored = true, CanCollide = false, CanQuery = false, CanTouch = false, Transparency = 1, Size = Vector3.new(1, 1, 1), Parent = workspace })
local markerGui = new("BillboardGui", { Size = UDim2.fromOffset(px(150), px(56)), StudsOffset = Vector3.new(0, 6, 0), AlwaysOnTop = true, LightInfluence = 0, MaxDistance = 2000, Enabled = false, Parent = markerPart })
local markerPin = label(markerGui, { Size = UDim2.new(1, 0, 0, px(32)), Text = "📍", TextSize = px(30), TextXAlignment = Enum.TextXAlignment.Center })
local markerDist = label(markerGui, { Position = UDim2.fromOffset(0, px(32)), Size = UDim2.new(1, 0, 0, px(20)), Text = "", TextSize = px(15), TextColor3 = Color3.new(1, 1, 1), TextStrokeTransparency = 0.3, TextStrokeColor3 = Color3.fromRGB(60, 50, 90), TextXAlignment = Enum.TextXAlignment.Center })
local ring = new("Part", { Name = "JourneyRing", Shape = Enum.PartType.Cylinder, Anchored = true, CanCollide = false, CanQuery = false, CanTouch = false, Material = Enum.Material.Neon, Color = C.Mint, Transparency = 1, Size = Vector3.new(0.12, 10, 10), Parent = workspace })

local arrow = new("Model", { Name = "JourneyArrow", Parent = workspace })
local function arrowPiece(rot: number)
	return new("Part", { Anchored = true, CanCollide = false, CanQuery = false, CanTouch = false, CastShadow = false, Material = Enum.Material.Neon, Color = C.Mint, Size = Vector3.new(0.35, 0.15, 1.7), Transparency = 1, Parent = arrow, Name = tostring(rot) })
end
local arrowL, arrowR = arrowPiece(1), arrowPiece(-1)

local target: Vector3? = nil
local areaStep: string? = nil -- the region an "anywhere here" step is about
local override: { pos: Vector3, untilT: number }? = nil -- a live event the player clicked (ticker)

-- Points the waypoint at a place until os.time() reaches untilT (then back to the story).
function Journey.pointTo(pos: Vector3, untilT: number)
	override = { pos = pos, untilT = untilT }
end

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Include
rayParams.FilterDescendantsInstances = { workspace.Terrain }
local function ground(v: Vector3): Vector3
	local hit = workspace:Raycast(Vector3.new(v.X, 400, v.Z), Vector3.new(0, -800, 0), rayParams)
	return Vector3.new(v.X, hit and hit.Position.Y or v.Y, v.Z)
end

----------------------------------------------------------------------------------------------
-- Dialogue

local dialog = Ui.card({ Name = "Dialogue", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -px(196)), Size = UDim2.fromOffset(px(580), px(132)), Visible = false, ZIndex = 30, Parent = Ui.gui }, 20)
local dIcon = new("Frame", { Position = UDim2.fromOffset(px(16), px(16)), Size = UDim2.fromOffset(px(56), px(56)), BackgroundColor3 = C.Mint, ZIndex = 31, Parent = dialog }, { new("UICorner", { CornerRadius = UDim.new(0.5, 0) }) })
local dGlyph = label(dIcon, { Size = UDim2.fromScale(1, 1), Text = "🧭", TextSize = px(30), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 32 })
local dName = label(dialog, { Position = UDim2.fromOffset(px(84), px(14)), Size = UDim2.new(1, -px(100), 0, px(22)), Text = "", TextSize = px(19), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 31 })
local dText = label(dialog, { Position = UDim2.fromOffset(px(84), px(40)), Size = UDim2.new(1, -px(100), 0, px(60)), Text = "", TextSize = px(17), TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top, ZIndex = 31 }, "Bold")
local dNext = label(dialog, { AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -px(16), 1, -px(10)), Size = UDim2.fromOffset(px(220), px(18)), Text = "Click or press E ▸", TextSize = px(13), TextColor3 = C.Sub, TextXAlignment = Enum.TextXAlignment.Right, ZIndex = 31 }, "Bold")
local dHit = new("TextButton", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Text = "", ZIndex = 33, Parent = dialog })
dHit:SetAttribute("NoTap", true)
dialog:GetPropertyChangedSignal("Visible"):Connect(function()
	Ui.dialogOpen = dialog.Visible
end)
if Ui.mobile then
	dialog.AnchorPoint = Vector2.new(0.5, 0)
	dialog.Position = UDim2.new(0.5, -30, 0, 52) -- left of the quest pill
	dialog.Size = UDim2.fromOffset(350, 104)
	dIcon.Position = UDim2.fromOffset(10, 10)
	dIcon.Size = UDim2.fromOffset(36, 36)
	dGlyph.TextSize = 20
	dName.Position = UDim2.fromOffset(56, 8)
	dName.Size = UDim2.new(1, -64, 0, 18)
	dName.TextSize = 14
	dText.Position = UDim2.fromOffset(56, 28)
	dText.Size = UDim2.new(1, -64, 0, 52)
	dText.TextSize = 13
	dNext.Position = UDim2.new(1, -10, 1, -6)
	dNext.Size = UDim2.fromOffset(160, 14)
	dNext.TextSize = 11
	dNext.Text = "Tap to continue ▸"
end

local queue: { { npc: string, lines: { string } } } = {}
local lineIdx = 0
local typing = false
local fullText = ""

local function showLine()
	local cur = queue[1]
	if not cur then
		dialog.Visible = false
		return
	end
	local g = StoryData.Npcs[cur.npc] or StoryData.Npcs.Mira
	dGlyph.Text = g.Icon
	dIcon.BackgroundColor3 = Ui.Theme.tint(g.Color, 0.4)
	dName.Text = g.Name .. "  ·  " .. g.Title
	dName.TextColor3 = g.Color:Lerp(Color3.new(0, 0, 0), 0.25)
	fullText = cur.lines[lineIdx] or ""
	dialog.Visible = true
	dNext.Text = Ui.mobile and (lineIdx < #cur.lines and "Tap to continue ▸" or "Tap to close") or (lineIdx < #cur.lines and "Click or press E ▸" or "Click or press E to close")
	typing = true
	task.spawn(function()
		for i = 1, #fullText do
			if not typing or dText.Parent == nil then
				break
			end
			dText.Text = string.sub(fullText, 1, i)
			if i % 3 == 0 then
				task.wait()
			end
		end
		dText.Text = fullText
		typing = false
	end)
	Sfx.play("tap", { pitch = 1.4, vol = 0.6 })
end

local function advance()
	if not dialog.Visible then
		return
	end
	if typing then
		typing = false
		dText.Text = fullText
		return
	end
	local cur = queue[1]
	if cur and lineIdx < #cur.lines then
		lineIdx += 1
		showLine()
	else
		table.remove(queue, 1)
		lineIdx = 1
		showLine()
	end
end
dHit.Activated:Connect(advance)
UserInputService.InputBegan:Connect(function(input, processed)
	if dialog.Visible and (input.KeyCode == Enum.KeyCode.E or input.KeyCode == Enum.KeyCode.Return) and not processed then
		advance()
	end
end)

function Journey.say(npc: string, lines: { string })
	table.insert(queue, { npc = npc, lines = lines })
	if #queue == 1 then
		lineIdx = 1
		Sfx.play("open")
		showLine()
	end
end

----------------------------------------------------------------------------------------------
-- Chapter banner

local banner = new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.3), Size = UDim2.fromOffset(px(560), px(110)), BackgroundTransparency = 1, Visible = false, ZIndex = 45, Parent = Ui.gui })
local bTop = label(banner, { Size = UDim2.new(1, 0, 0, px(30)), Text = "CHAPTER COMPLETE", TextSize = px(24), TextColor3 = C.Sun, TextStrokeTransparency = 0.2, TextStrokeColor3 = Color3.fromRGB(80, 50, 20), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 46 })
local bTitle = label(banner, { Position = UDim2.fromOffset(0, px(34)), Size = UDim2.new(1, 0, 0, px(44)), Text = "", TextSize = px(40), TextColor3 = Color3.new(1, 1, 1), TextStrokeTransparency = 0.2, TextStrokeColor3 = Color3.fromRGB(60, 40, 100), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 46 })
local bReward = label(banner, { Position = UDim2.fromOffset(0, px(80)), Size = UDim2.new(1, 0, 0, px(24)), Text = "", TextSize = px(20), TextColor3 = C.Sun, TextStrokeTransparency = 0.3, TextStrokeColor3 = Color3.fromRGB(80, 50, 20), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 46 })
local bScale = new("UIScale", { Parent = banner })

local function showBanner(chapter: number, reward: string)
	local ch = StoryData.Chapters[chapter]
	bTitle.Text = string.format("Chapter %d: %s", chapter, ch and ch.Title or "")
	bReward.Text = reward
	banner.Visible = true
	bScale.Scale = 0.4
	TweenService:Create(bScale, TweenInfo.new(0.45, Enum.EasingStyle.Back), { Scale = 1 }):Play()
	Sfx.play("level_up", { pitch = 0.9 })
	task.delay(0.25, Sfx.play, "quest_done")
	task.delay(3.2, function()
		banner.Visible = false
	end)
end

----------------------------------------------------------------------------------------------
-- Travel panel

local _, travelBody, travelSub = Ui.panel("Travel", "Campfires", "Travel to any campfire you've lit, from anywhere. Not during a fight or a dungeon.", C.Peach, "🔥")
local function renderTravel()
	local p = Ui.profile
	if not p then
		return
	end
	for _, c in travelBody:GetChildren() do
		if not c:IsA("UIListLayout") and not c:IsA("UIPadding") then
			c:Destroy()
		end
	end
	travelSub.Text = "Travel to any campfire you've lit. Not during a fight."
	for i, region in CAMPFIRE_ORDER do
		local lit = p.campfires and p.campfires[region]
		local r = Ui.row(travelBody, i, C.Peach, "🔥", REGION_NAMES[region] .. " campfire", lit and "Lit · heals your team on arrival" or "Not lit yet: walk up to it to light it")
		Ui.setBuy(r.buy, lit and "Travel" or "Not lit", lit and "afford" or "poor", C.Peach)
		r.buy.Activated:Connect(function()
			if not lit then
				return
			end
			local ok = Ui.call("Travel", region)
			if ok then
				Ui.open(nil)
				Sfx.play("region", { pitch = 1.1 })
			end
		end)
	end
end
Ui.onOpen.Travel = renderTravel
travelB.Activated:Connect(function()
	Ui.open("Travel")
end)

----------------------------------------------------------------------------------------------

local lastStep = 0
local function render(p)
	local i = p.story and p.story.i or 1
	local s = StoryData.Steps[i]
	if not s then
		tChapter.Text = "TAMER'S JOURNEY"
		tText.Text = "Journey complete! More to come."
		tInfo.Text = ""
		target = nil
		return
	end
	tChapter.Text = string.format("📖 CHAPTER %d · %s", s.chapter, string.upper(s.chapterTitle))
	tText.Text = s.text
	local info = ""
	if COUNTED[s.kind] and s.n then
		info = string.format("%d / %d", math.min(p.story.n or 0, s.n), s.n)
	elseif s.kind == "level" then
		local best = 0
		for _, m in p.monsters do
			best = math.max(best, m.lv)
		end
		info = string.format("Best level %d / %d", best, s.n)
	elseif s.kind == "weapon" then
		info = string.format("Weapon level %d / %d", p.weapon.lv, s.n)
	elseif s.kind == "index" then
		local n = 0
		for _ in p.index do
			n += 1
		end
		info = string.format("%d / %d", n, s.n)
	end
	local reward = StoryData.rewardText(s.reward or {})
	tInfo.Text = info ~= "" and (info .. "   ·   " .. reward) or reward
	target = s.at and ground(s.at) or nil
	-- "defeat monsters in <region>" can be done anywhere in that region: the marker only leads
	-- you there, and goes away once you're inside (owner, 2026-11-27)
	areaStep = (s.kind == "defeat" and s.region) and s.region or nil
	if areaStep and info ~= "" then
		tInfo.Text = info .. "  ·  anywhere in " .. (REGION_NAMES[areaStep] or areaStep) .. "   ·   " .. reward
	end
	if i ~= lastStep then
		if lastStep ~= 0 then
			tScale.Scale = 1.12
			TweenService:Create(tScale, TweenInfo.new(0.35, Enum.EasingStyle.Back), { Scale = 1 }):Play()
		end
		lastStep = i
	end
end

function Journey.start()
	Ui.onProfile(render)
	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	remotes:WaitForChild("Story").OnClientEvent:Connect(function(msg)
		if type(msg) ~= "table" then
			return
		end
		if msg.kind == "dialogue" and type(msg.lines) == "table" then
			Journey.say(msg.npc, msg.lines)
		elseif msg.kind == "eclipse" then
			task.delay(dialog.Visible and 4 or 3.4, function()
				bTop.Text = "TAMER'S JOURNEY COMPLETE"
				showBanner(0, "")
				bTitle.Text = "🌑 You earned the Eclipse Egg"
				bReward.Text = "A guaranteed 5★ Light or Dark. Hatch it at the Shrine. There's only ever one."
				task.delay(4, function()
					bTop.Text = "CHAPTER COMPLETE"
				end)
			end)
		elseif msg.kind == "done" then
			local s = StoryData.Steps[msg.step]
			if msg.chapterDone then
				task.delay(dialog.Visible and 0.6 or 0, showBanner, msg.chapter, msg.reward)
			else
				Sfx.play("quest_done")
			end
			Ui.toast((s and s.text or "Step done") .. "  " .. (msg.reward or ""), "good")
		end
	end)

	-- marker, ring and arrow
	RunService.RenderStepped:Connect(function()
		local char = player.Character
		local hrp = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
		if override and os.time() >= override.untilT then
			override = nil
		end
		local goal = override and ground(override.pos) or target
		if not override and areaStep and player:GetAttribute("Region") == areaStep then
			goal = nil
		end
		-- in another place: point at the portal that leads there instead (valleys are closed)
		local via = false
		if goal and hrp then
			local here = Places.regionAt(hrp.Position)
			local there = Places.regionAt(goal)
			if here ~= there then
				local side = Places.nextPortal(here, there)
				if side then
					goal = ground(side.pos)
					via = true
				end
			end
		end
		if not goal or not hrp then
			markerGui.Enabled = false
			ring.Transparency = 1
			arrowL.Transparency, arrowR.Transparency = 1, 1
			return
		end
		local tgt = goal :: Vector3
		local flat = Vector3.new(tgt.X - hrp.Position.X, 0, tgt.Z - hrp.Position.Z)
		local dist = flat.Magnitude
		markerPart.Position = tgt
		markerGui.Enabled = dist > 10
		markerDist.Text = via and string.format("portal · %dm", math.floor(dist)) or string.format("%dm", math.floor(dist))
		local t = os.clock()
		ring.CFrame = CFrame.new(tgt + Vector3.new(0, 0.15, 0)) * CFrame.Angles(0, 0, math.rad(90))
		ring.Transparency = dist < 220 and (0.55 + 0.2 * math.sin(t * 4)) or 1
		local pinS = 1 + 0.08 * math.sin(t * 5)
		markerPin.TextSize = math.floor(px(30) * pinS)
		if dist > 24 then
			local dir = flat.Unit
			local feet = hrp.Position - Vector3.new(0, 2.7, 0) + dir * (4.5 + 0.4 * math.sin(t * 6))
			local base = CFrame.lookAt(feet, feet + dir)
			arrowL.CFrame = base * CFrame.Angles(0, math.rad(35), 0) * CFrame.new(0, 0, 0.75)
			arrowR.CFrame = base * CFrame.Angles(0, math.rad(-35), 0) * CFrame.new(0, 0, 0.75)
			arrowL.Transparency, arrowR.Transparency = 0.15, 0.15
		else
			arrowL.Transparency, arrowR.Transparency = 1, 1
		end
	end)

	-- fast travel button next to a lit campfire
	task.spawn(function()
		local fires: { BasePart } = {}
		local scanned = 0
		while true do
			task.wait(0.5)
			if os.clock() - scanned > 15 then
				scanned = os.clock()
				fires = {}
				local world = workspace:FindFirstChild("World")
				for _, d in (world and world:GetDescendants() or {}) do
					if d:IsA("SpawnLocation") and d:GetAttribute("Campfire") then
						table.insert(fires, d)
					end
				end
			end
			local char = player.Character
			local hrp = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
			local near = false
			if hrp and Ui.profile then
				for _, d in fires do
					if (d.Position - hrp.Position).Magnitude < 14 then
						near = true
						break
					end
				end
			end
			-- travel from anywhere (owner, 2026-11-27): the button is always there outside dungeons
			local _ = near
			travelB.Visible = not Ui.mobile and Ui.profile ~= nil and player:GetAttribute("Dungeon") == nil and require(script.Parent.Unlocks).open(Ui.profile, "Travel")
			local fighting = player:GetAttribute("InCombat") == true
			travelB.BackgroundColor3 = fighting and C.Line or C.Peach
			travelB.Text = fighting and "🔥 Travel (in a fight)" or "🔥 Travel"
		end
	end)
end

return Journey

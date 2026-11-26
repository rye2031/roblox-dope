-- Draws creatures locally on top of the server's invisible sleeper parts, plus each player's
-- buddy. Handles the readable telegraphs: twitch -> squirm -> one eye open -> bolt.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Creatures = require(Shared.Creatures)
local Faces = require(Shared.Faces)
local MeshLoader = require(Shared.MeshLoader)

local player = Players.LocalPlayer

local CreatureView = {}

local SOUNDS = {
	Snore = "rbxasset://sounds/action_swim.mp3",
	Twitch = "rbxasset://sounds/action_get_up.mp3",
	Squirm = "rbxasset://sounds/oof.ogg",
	Eye = "rbxasset://sounds/ouch.ogg",
	Beat = "rbxasset://sounds/action_jump_land.mp3",
	Pop = "rbxasset://sounds/impact_explosion_03.mp3",
}
CreatureView.SOUNDS = SOUNDS

local function playAt(parent: Instance, id: string, volume: number, pitch: number)
	local s = Instance.new("Sound")
	s.SoundId = id
	s.Volume = volume
	s.PlaybackSpeed = pitch
	s.RollOffMaxDistance = 90
	s.RollOffMinDistance = 8
	s.Parent = parent
	s:Play()
	s.Ended:Once(function()
		s:Destroy()
	end)
	task.delay(4, function()
		if s.Parent then
			s:Destroy()
		end
	end)
	return s
end
CreatureView.playAt = playAt

local function playUi(id: string, volume: number, pitch: number)
	local s = Instance.new("Sound")
	s.SoundId = id
	s.Volume = volume
	s.PlaybackSpeed = pitch
	s.Parent = SoundService
	s:Play()
	s.Ended:Once(function()
		s:Destroy()
	end)
end
CreatureView.playUi = playUi

local holder = Instance.new("Folder")
holder.Name = "CreatureViews"
holder.Parent = workspace

-- Build a creature model: mesh body (or a soft coloured placeholder when no mesh slot is free)
-- + eyelids. Pair every build with CreatureView.destroy so the mesh slot is handed back.
function CreatureView.build(meshName: string, height: number, parent: Instance?, opts: { optional: boolean? }?)
	local sp = Creatures.Species[meshName]
	local model = Instance.new("Model")
	model.Name = meshName
	local body: BasePart? = MeshLoader.get(meshName, height, opts)
	local temp = false
	if not body then
		temp = true
		local ball = Instance.new("Part")
		ball.Shape = Enum.PartType.Ball
		ball.Size = Vector3.new(height, height, height)
		ball.Color = sp and sp.Color or Color3.new(1, 0, 1)
		ball.Material = Enum.Material.SmoothPlastic
		ball.Anchored = true
		ball.CanCollide = false
		ball.CanQuery = false
		ball.CanTouch = false
		body = ball
	end
	local b = body :: BasePart
	b.Name = "Body"
	b.Parent = model
	model.PrimaryPart = b
	local lids = {}
	local face = Faces[meshName]
	if face and not temp then
		for i, e in face do
			local r = e.Radius * height
			local lid = Instance.new("Part")
			lid.Name = "Lid" .. i
			lid.Shape = Enum.PartType.Ball
			lid.Size = Vector3.new(r * 2.3, r * 2.3, r * 1.2)
			lid.Color = e.Lid
			lid.Material = Enum.Material.SmoothPlastic
			lid.CanCollide = false
			lid.CanQuery = false
			lid.CanTouch = false
			lid.Massless = true
			lid.CFrame = b.CFrame * CFrame.new(e.Pos * height + Vector3.new(0, 0, -r * 0.15))
			local line = Instance.new("Part")
			line.Name = "LidLine"
			line.Size = Vector3.new(r * 1.7, r * 0.22, r * 0.2)
			line.Color = Color3.fromRGB(60, 30, 20)
			line.Material = Enum.Material.SmoothPlastic
			line.CanCollide = false
			line.CanQuery = false
			line.CanTouch = false
			line.Massless = true
			line.CFrame = lid.CFrame * CFrame.new(0, -r * 0.15, -r * 0.6)
			for _, p in { lid, line } do
				local w = Instance.new("WeldConstraint")
				w.Part0 = b
				w.Part1 = p
				w.Parent = p
				p.Anchored = false
				p.Parent = model
			end
			table.insert(lids, { lid = lid, line = line, size = lid.Size, lineSize = line.Size })
		end
	end
	model.Parent = parent or holder
	return { model = model, body = b, lids = lids, height = height, temp = temp, mesh = meshName }
end

function CreatureView.destroy(c)
	if c.model then
		c.model:Destroy()
	end
	if not c.temp and not c.released then
		c.released = true
		MeshLoader.release(c.mesh)
	end
end

-- open = 0 closed .. 1 fully open
local function setLid(l, open: number)
	if open >= 0.99 then
		l.lid.Transparency = 1
		l.line.Transparency = 1
	else
		l.lid.Transparency = 0
		l.line.Transparency = open > 0.3 and 1 or 0
		l.lid.Size = Vector3.new(l.size.X, l.size.Y * (1 - open * 0.7), l.size.Z)
	end
end

local Theme = require(Shared.Theme)

-- Small white name pill over a creature: family name + status line.
local function billboard(adornee: BasePart, offsetY: number)
	local bb = Instance.new("BillboardGui")
	bb.Size = UDim2.fromOffset(170, 52)
	bb.StudsOffset = Vector3.new(0, offsetY, 0)
	bb.MaxDistance = 80
	bb.LightInfluence = 0
	bb.Adornee = adornee
	local pill = Instance.new("Frame")
	pill.Name = "Pill"
	pill.AnchorPoint = Vector2.new(0.5, 0)
	pill.Position = UDim2.fromScale(0.5, 0)
	pill.Size = UDim2.new(0.8, 0, 0.5, 0)
	pill.BackgroundColor3 = Color3.new(1, 1, 1)
	pill.BackgroundTransparency = 0.05
	pill.Parent = bb
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0.5, 0)
	c.Parent = pill
	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.Size = UDim2.new(1, -12, 1, -6)
	title.Position = UDim2.fromOffset(6, 3)
	title.BackgroundTransparency = 1
	title.FontFace = Theme.Font.Title
	title.TextScaled = true
	title.TextColor3 = Theme.C.Ink
	title.Parent = pill
	local sub = Instance.new("TextLabel")
	sub.Name = "Sub"
	sub.Size = UDim2.new(1, 0, 0.42, 0)
	sub.Position = UDim2.fromScale(0, 0.56)
	sub.BackgroundTransparency = 1
	sub.FontFace = Theme.Font.Title
	sub.TextScaled = true
	sub.TextColor3 = Color3.fromRGB(120, 160, 230)
	sub.Parent = bb
	local st = Instance.new("UIStroke")
	st.Thickness = 2
	st.Color = Color3.new(1, 1, 1)
	st.Parent = sub
	bb.Parent = adornee
	return bb
end

----------------------------------------------------------------------------------------------
-- Sleepers

type View = {
	part: BasePart,
	c: any,
	bb: BillboardGui,
	seed: number,
	cf: CFrame?,
	lastStage: number,
	nextTwitch: number,
	twitchStart: number,
	twitchAxis: Vector3,
	rollAngle: number,
	lastPos: Vector3?,
	trail: Trail?,
	snore: Sound?,
	nextBeat: number,
	highlight: Highlight?,
	bag: any?,
	rushFx: ParticleEmitter?,
}

local views: { [BasePart]: View } = {}
CreatureView.views = views

local function addSleeper(part: BasePart)
	local rarity = part:GetAttribute("Rarity")
	local fieldMesh = part:GetAttribute("FieldMesh") or "CrabRangoon"
	local sp = Creatures.Species[fieldMesh]
	local height = (sp and sp.Height or 3) * (rarity == "Rare" and 1.35 or 1)
	local c = CreatureView.build(fieldMesh, height)
	local family = part:GetAttribute("Family")
	local bb = billboard(c.body, height / 2 + 1.6)
	bb.Pill.Title.Text = (rarity == "Rare" and "★ RARE " or "Sleeping ") .. family
	bb.Pill.Title.TextColor3 = rarity == "Rare" and Color3.fromRGB(210, 150, 20) or Creatures.Families[family].Color:Lerp(Color3.new(0, 0, 0), 0.25)
	bb.Sub.Text = "z z Z"
	local a0 = Instance.new("Attachment")
	a0.Position = Vector3.new(0, -height * 0.35, 0.3)
	a0.Parent = c.body
	local a1 = Instance.new("Attachment")
	a1.Position = Vector3.new(0, -height * 0.1, 0.3)
	a1.Parent = c.body
	local trail = Instance.new("Trail")
	trail.Attachment0 = a0
	trail.Attachment1 = a1
	trail.Lifetime = 1.4
	trail.Color = ColorSequence.new(Color3.fromRGB(255, 80, 80), Color3.fromRGB(255, 220, 80))
	trail.Transparency = NumberSequence.new(0.1, 1)
	trail.LightEmission = 0.6
	trail.Enabled = false
	trail.Parent = c.body
	local snore = Instance.new("Sound")
	snore.SoundId = SOUNDS.Snore
	snore.Looped = true
	snore.Volume = rarity == "Rare" and 0.35 or 0.18
	snore.PlaybackSpeed = 0.35
	snore.RollOffMaxDistance = 40
	snore.RollOffMinDistance = 4
	snore.Parent = c.body
	snore:Play()
	local hl
	if rarity == "Rare" then
		hl = Instance.new("Highlight")
		hl.FillTransparency = 0.85
		hl.FillColor = Color3.fromRGB(255, 220, 90)
		hl.OutlineColor = Color3.fromRGB(255, 200, 40)
		hl.DepthMode = Enum.HighlightDepthMode.Occluded
		hl.Adornee = c.model
		hl.Parent = c.model
		local sparkle = Instance.new("ParticleEmitter")
		sparkle.Texture = "rbxasset://textures/particles/sparkles_main.dds"
		sparkle.Color = ColorSequence.new(Color3.fromRGB(255, 220, 90))
		sparkle.Rate = 12
		sparkle.Lifetime = NumberRange.new(0.8, 1.4)
		sparkle.Speed = NumberRange.new(1, 3)
		sparkle.SpreadAngle = Vector2.new(180, 180)
		sparkle.Size = NumberSequence.new(0.5, 0)
		sparkle.Parent = c.body
	end
	-- oversized takeout bag the sleeper naps against (stays at the spot as a landmark)
	local bag = CreatureView.bagFor and CreatureView.bagFor(part, height)
	views[part] = {
		part = part,
		c = c,
		bb = bb,
		seed = math.random() * 10,
		cf = nil,
		lastStage = 0,
		nextTwitch = 0,
		twitchStart = -10,
		twitchAxis = Vector3.new(0, 0, 1),
		rollAngle = 0,
		lastPos = nil,
		trail = trail,
		snore = snore,
		nextBeat = 0,
		highlight = hl,
		bag = bag,
	}
	for _, l in c.lids do
		setLid(l, 0)
	end
end

local function removeSleeper(part: BasePart)
	local v = views[part]
	if v then
		CreatureView.destroy(v.c)
		if v.bag then
			v.bag:Destroy()
			MeshLoader.release("PropTakeoutBag")
		end
		views[part] = nil
	end
end

local function serverNow()
	return workspace:GetServerTimeNow()
end

local function updateSleeper(v: View, dt: number, t: number)
	local part = v.part
	local c = v.c
	local h = c.height
	local state = part:GetAttribute("State")
	local stage = part:GetAttribute("Stage") or 0
	local carried = state == "Carried"
	local mine = part:GetAttribute("CarrierId") == player.UserId

	-- smooth the anchored server CFrame; carried parts are already smooth (physics)
	local target = part.CFrame * CFrame.new(0, h / 2 - part.Size.Y / 2, 0)
	if carried then
		target = part.CFrame * CFrame.Angles(0, math.pi, 0) -- face the camera
	end
	if not v.cf or carried or (v.cf.Position - target.Position).Magnitude > 20 then
		v.cf = target
	else
		v.cf = v.cf:Lerp(target, 1 - math.exp(-18 * dt))
	end
	local base = v.cf :: CFrame
	local off = CFrame.identity
	local s = v.seed

	if state == "Sleeping" then
		off = CFrame.new(0, math.sin(t * 2.2 + s) * 0.05 * h, 0) * CFrame.Angles(0, 0, math.sin(t * 1.1 + s) * 0.05)
	elseif carried then
		-- stage-driven telegraphs
		local sway = math.sin(t * 3 + s) * 0.06
		off = CFrame.Angles(0, 0, sway)
		if stage >= 1 then
			if t > v.nextTwitch then
				v.twitchStart = t
				v.nextTwitch = t + (stage >= 2 and 0.45 or 0.9) + math.random() * 0.6
				v.twitchAxis = Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5).Unit
				if stage == 1 then
					playAt(c.body, SOUNDS.Twitch, 0.35, 1.9 + math.random() * 0.3)
				end
			end
			local k = (t - v.twitchStart) / 0.16
			if k < 1 then
				off *= CFrame.fromAxisAngle(v.twitchAxis, math.sin(k * math.pi) * 0.45) * CFrame.new(0, math.sin(k * math.pi) * 0.25, 0)
			end
		end
		if stage >= 2 then
			local amp = stage >= 3 and 0.32 or 0.2
			off *= CFrame.new(math.sin(t * 23) * 0.07 * h, 0, 0) * CFrame.Angles(math.sin(t * 13) * amp * 0.5, math.sin(t * 11) * amp * 0.6, math.sin(t * 16) * amp)
		end
	elseif state == "Bolting" then
		local pos = part.Position
		local moved = v.lastPos and (pos - v.lastPos).Magnitude or 0
		v.lastPos = pos
		local sp = Creatures.Species[part:GetAttribute("FieldMesh")]
		if sp and sp.Rolls then
			v.rollAngle -= moved / (h * 0.5)
			off = CFrame.Angles(v.rollAngle, 0, 0)
		else
			off = CFrame.new(0, math.abs(math.sin(t * 15)) * 0.35 * h, 0) * CFrame.Angles(0, 0, math.sin(t * 15) * 0.2)
		end
	elseif state == "Loose" then
		off = CFrame.new(0, math.abs(math.sin(t * 4)) * 0.1 * h, 0) * CFrame.Angles(0, math.sin(t * 2) * 0.4, math.sin(t * 3) * 0.12)
	end
	c.body.CFrame = base * off

	-- lids: closed asleep; one opens at stage 3; awake = open; loose = groggy half
	if #c.lids > 0 then
		local open1, open2 = 0, 0
		if state == "Bolting" then
			open1, open2 = 1, 1
		elseif state == "Loose" then
			open1, open2 = 0.5, 0.5
		elseif stage >= 3 then
			open1 = 1
		end
		setLid(c.lids[1], open1)
		if c.lids[2] then
			setLid(c.lids[2], open2)
		end
	end

	-- sounds on stage increase
	if stage > v.lastStage and carried then
		if stage == 2 then
			playAt(c.body, SOUNDS.Squirm, 0.5, 1.8)
		elseif stage == 3 then
			playAt(c.body, SOUNDS.Eye, 0.7, 1.5)
		end
	end
	v.lastStage = stage
	if carried and stage >= 2 and t > v.nextBeat then
		v.nextBeat = t + (stage >= 3 and 0.38 or 0.6)
		if mine then
			playUi(SOUNDS.Beat, stage >= 3 and 0.7 or 0.4, 0.55)
		end
	end
	if v.snore then
		local want = state == "Sleeping" or (carried and stage == 0)
		v.snore.Volume = want and (part:GetAttribute("Rarity") == "Rare" and 0.35 or 0.18) or 0
	end
	v.trail.Enabled = state == "Bolting"
	-- Snack Rush: sleepers in the rushing wing glitter (they bank as Glazed or better)
	local rushing = workspace:GetAttribute("RushWing") == part:GetAttribute("Wing") and serverNow() < (workspace:GetAttribute("RushUntil") or 0)
	if rushing and not v.rushFx then
		local e = Instance.new("ParticleEmitter")
		e.Texture = "rbxasset://textures/particles/sparkles_main.dds"
		e.Color = ColorSequence.new(Color3.fromRGB(255, 225, 120), Color3.fromRGB(255, 160, 200))
		e.Rate = 10
		e.Lifetime = NumberRange.new(0.7, 1.2)
		e.Speed = NumberRange.new(1, 3)
		e.SpreadAngle = Vector2.new(180, 180)
		e.Size = NumberSequence.new(0.45, 0)
		e.Parent = c.body
		v.rushFx = e
	end
	if v.rushFx then
		v.rushFx.Enabled = rushing
	end

	-- billboard text
	local bb = v.bb
	bb.Enabled = not (carried and mine)
	local exclusiveId = part:GetAttribute("ExclusiveId")
	local exUntil = part:GetAttribute("ExclusiveUntil") or 0
	local left = exUntil - serverNow()
	local prompt = part:FindFirstChild("GrabPrompt") :: ProximityPrompt?
	if state == "Sleeping" then
		bb.Sub.Text = string.rep("z ", 1 + math.floor(t * 2) % 3) .. "Z"
		bb.Sub.TextColor3 = Color3.fromRGB(110, 150, 230)
	elseif carried then
		bb.Sub.Text = ({ "z z Z", "*twitch*", "*SQUIRM*", "ONE EYE OPEN!" })[stage + 1] or ""
		bb.Sub.TextColor3 = stage >= 2 and Color3.fromRGB(235, 80, 70) or Color3.fromRGB(220, 160, 30)
	elseif exclusiveId and left > 0 then
		if exclusiveId == player.UserId then
			bb.Sub.Text = string.format("CATCH IT! %.1fs", left)
			bb.Sub.TextColor3 = Color3.fromRGB(40, 170, 110)
		else
			bb.Sub.Text = string.format("🔒 locked %.1fs", left)
			bb.Sub.TextColor3 = Color3.fromRGB(230, 80, 90)
		end
	elseif state == "Bolting" then
		bb.Sub.Text = "IT'S LOOSE! GRAB IT!"
		bb.Sub.TextColor3 = Color3.fromRGB(235, 120, 50)
	elseif state == "Loose" then
		bb.Sub.Text = "?! dozing… grab it!"
		bb.Sub.TextColor3 = Color3.fromRGB(220, 140, 40)
	end
	if prompt then
		local lockedForMe = exclusiveId ~= nil and exclusiveId ~= player.UserId and left > 0
		local busy = player:GetAttribute("Carrying") ~= nil
		local serverEnabled = state ~= "Carried"
		prompt.Enabled = serverEnabled and not lockedForMe and not busy
	end
end

----------------------------------------------------------------------------------------------
-- Buddies

local buddies: { [Player]: any } = {}

local function updateBuddy(plr: Player, dt: number, t: number)
	local want = plr:GetAttribute("Buddy")
	local b = buddies[plr]
	if b and b.species ~= want then
		CreatureView.destroy(b.c)
		buddies[plr] = nil
		b = nil
	end
	local char = plr.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not want or not hrp then
		return
	end
	if not b then
		local sp = Creatures.Species[want]
		local c = CreatureView.build(want, sp.Height * 0.75)
		for _, l in c.lids do
			setLid(l, 1)
		end
		b = { species = want, c = c, cf = nil, hopT = 0, jumpUntil = 0 }
		buddies[plr] = b
	end
	local h = b.c.height
	local goal = hrp.CFrame * CFrame.new(2.8, 0, 2.6)
	local hum = char:FindFirstChildOfClass("Humanoid")
	local hip = hum and (hum.HipHeight + hrp.Size.Y / 2) or 3
	local groundY = hrp.Position.Y - hip
	local goalPos = Vector3.new(goal.Position.X, groundY + h / 2, goal.Position.Z)
	if b.jumpTarget and t < b.jumpUntil then
		goalPos = b.jumpTarget
	end
	local cur = b.cf and b.cf.Position or goalPos
	if (cur - goalPos).Magnitude > 40 then
		cur = goalPos
	end
	local newPos = cur:Lerp(goalPos, 1 - math.exp(-8 * dt))
	local moving = (newPos - cur).Magnitude / math.max(dt, 1e-3) > 2
	local look = hrp.CFrame.LookVector
	b.cf = CFrame.lookAt(newPos, newPos + Vector3.new(look.X, 0, look.Z))
	local hop = moving and math.abs(math.sin(t * 12)) * 0.5 or math.sin(t * 2.5) * 0.05
	b.c.body.CFrame = b.cf * CFrame.new(0, hop, 0) * CFrame.Angles(0, 0, moving and math.sin(t * 12) * 0.12 or 0)
end

function CreatureView.buddyPry(userId: number, doorPos: Vector3)
	for plr, b in buddies do
		if plr.UserId == userId then
			b.jumpTarget = doorPos + Vector3.new(0, 1.5, 0)
			b.jumpUntil = os.clock() + 1.2
		end
	end
end

----------------------------------------------------------------------------------------------

function CreatureView.start()
	-- Level of detail: only sleepers in the player's wing (or very close) get a mesh view, so the
	-- client stays inside its EditableMesh budget as the mall grows.
	local folder = workspace:WaitForChild("Sleepers")
	local known: { [BasePart]: boolean } = {}
	for _, p in folder:GetChildren() do
		known[p] = true
	end
	folder.ChildAdded:Connect(function(p)
		known[p] = true
	end)
	folder.ChildRemoved:Connect(function(p)
		known[p] = nil
		removeSleeper(p)
	end)
	local wingAt = require(Shared.Config).wingAt
	task.spawn(function()
		while true do
			local cam = workspace.CurrentCamera
			local char = player.Character
			local hrp = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
			local focus = hrp and hrp.Position or (cam and cam.CFrame.Position) or Vector3.zero
			local myWing = wingAt(focus)
			for p in known do
				local d = (p.Position - focus).Magnitude
				local carriedByMe = p:GetAttribute("CarrierId") == player.UserId
				local want = carriedByMe or d < 45 or (wingAt(p.Position) == myWing and d < 230)
				if want and not views[p] then
					addSleeper(p)
				elseif not want and views[p] and d > 60 then
					removeSleeper(p)
				end
			end
			task.wait(0.4)
		end
	end)
	Players.PlayerRemoving:Connect(function(plr)
		local b = buddies[plr]
		if b then
			CreatureView.destroy(b.c)
			buddies[plr] = nil
		end
	end)
	RunService.RenderStepped:Connect(function(dt)
		local t = os.clock()
		for _, v in views do
			if v.part.Parent then
				updateSleeper(v, dt, t)
			end
		end
		for _, plr in Players:GetPlayers() do
			updateBuddy(plr, dt, t)
		end
	end)
end

return CreatureView

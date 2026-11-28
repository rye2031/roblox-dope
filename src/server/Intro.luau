-- The dream intro (2026-11-27, owner: "like old-school Mystery Dungeon, the player is having a
-- dream", and start the team off right away). A brand-new Tamer wakes on a cloud island far
-- from the map: a few gentle questions pick their starter element, their three starter eggs
-- hatch (1 Legendary in that element + 2 Regular), and a weak shadow monster teaches them to
-- fight. Then they wake up in Haven next to Mira. Always skippable; never shown twice.
--
-- Client: Intro.luau. Remote "Intro": "begin" | "answer" el | "hatch" | "fight" | "done" | "skip".
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PlayerData = require(script.Parent.PlayerData)
local World = require(script.Parent.World)

local Intro = {}
local Combat, Summon, remotes
local ISLAND = Vector3.new(-3000, 160, -3000)
local runs: { [Player]: { el: string?, hatched: boolean, camp: any?, fought: boolean } } = {}

local function eligible(p): boolean
	return not p.tutorial.dream and (p.story and p.story.i or 1) <= 1 and (p.opened or 0) == 0
end
Intro.eligible = eligible

local function part(props, parent)
	local p = Instance.new("Part")
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Material = Enum.Material.SmoothPlastic
	for k, v in props do
		(p :: any)[k] = v
	end
	p.Parent = parent
	return p
end

function Intro.build()
	local f = Instance.new("Folder")
	f.Name = "DreamIsland"
	f.Parent = workspace
	local c = ISLAND
	-- a round cloud island: a soft floor, puffs around the rim, a few floating stars
	part({ Name = "DreamFloor", Shape = Enum.PartType.Cylinder, Size = Vector3.new(4, 90, 90), CFrame = CFrame.new(c - Vector3.new(0, 2, 0)) * CFrame.Angles(0, 0, math.rad(90)), Color = Color3.fromRGB(246, 240, 255), Material = Enum.Material.SmoothPlastic }, f)
	for i = 0, 17 do
		local a = i / 18 * math.pi * 2
		local r = 9 + (i % 3) * 3
		part({ Name = "DreamPuff", Shape = Enum.PartType.Ball, Size = Vector3.new(r * 2, r * 1.3, r * 2), Position = c + Vector3.new(math.cos(a) * 46, -2 + (i % 2) * 2, math.sin(a) * 46), Color = Color3.fromRGB(236, 230, 252), CanCollide = true }, f)
		-- invisible rim so nobody walks off the dream
		part({ Name = "DreamWall", Size = Vector3.new(2, 40, 18), CFrame = CFrame.lookAt(c + Vector3.new(math.cos(a) * 44, 18, math.sin(a) * 44), c + Vector3.new(0, 18, 0)), Transparency = 1 }, f)
	end
	for i = 1, 14 do
		local a = i * 2.4
		local st = part({ Name = "DreamStar", Shape = Enum.PartType.Ball, Size = Vector3.new(1.2, 1.2, 1.2), Position = c + Vector3.new(math.cos(a) * (20 + i * 2), 14 + (i % 5) * 4, math.sin(a) * (20 + i * 2)), Color = i % 2 == 0 and Color3.fromRGB(255, 230, 160) or Color3.fromRGB(200, 180, 255), Material = Enum.Material.Neon, CanCollide = false }, f)
		st:SetAttribute("NoLod", true)
	end
	-- the stone circle the eggs sit on
	part({ Name = "DreamAltar", Shape = Enum.PartType.Cylinder, Size = Vector3.new(1, 14, 14), CFrame = CFrame.new(c + Vector3.new(0, 0.5, -12)) * CFrame.Angles(0, 0, math.rad(90)), Color = Color3.fromRGB(220, 210, 246) }, f)
	World.addGround(f)
	Intro.spawnAt = c + Vector3.new(0, 4, 14)
end

local function hrpOf(pl: Player): BasePart?
	return pl.Character and pl.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
end

local function moveTo(pl: Player, pos: Vector3, look: Vector3)
	local hrp = hrpOf(pl)
	if hrp then
		pcall(function()
			pl:RequestStreamAroundAsync(pos)
		end)
		hrp.AssemblyLinearVelocity = Vector3.zero
		hrp.CFrame = CFrame.lookAt(pos, pos + look)
		Combat.warpTeam(pl, pos - Vector3.new(0, 3, 0))
	end
end

local function finish(pl: Player)
	local p = PlayerData.get(pl)
	local run = runs[pl]
	if run and run.camp then
		Combat.despawnCamp(run.camp)
	end
	runs[pl] = nil
	if p then
		p.tutorial.dream = true
		p.tutorial.intro = true -- the old How-to-play card isn't needed after the dream
		PlayerData.push(pl)
		PlayerData.saveSoon(pl)
	end
	pl:SetAttribute("InIntro", nil)
	local spawn = World.Points.Spawn
	moveTo(pl, Vector3.new(spawn.X + 6, 6, spawn.Z + 8), Vector3.new(1, 0, -1))
end

function Intro.handle(pl: Player, action: any, a: any)
	local p = PlayerData.get(pl)
	if not p then
		return false, "No profile"
	end
	local run = runs[pl]
	if action == "skip" or action == "done" then
		if run or pl:GetAttribute("InIntro") then
			finish(pl)
		end
		return true, "ok"
	end
	if not run then
		return false, "Not dreaming"
	end
	if action == "answer" then
		if a == "Fire" or a == "Water" or a == "Wind" then
			run.el = a
			return true, "ok"
		end
		return false, "Pick an answer"
	elseif action == "hatch" then
		if run.hatched then
			return false, "Already hatched"
		end
		run.hatched = true
		local res = Summon.starter(pl, run.el or "Fire")
		task.defer(Combat.syncTeam, pl)
		return true, "ok", res
	elseif action == "fight" then
		if run.fought or not run.hatched then
			return false, "Not yet"
		end
		run.fought = true
		local camp = { id = "Dream_" .. pl.UserId, region = "SproutMeadow", pos = ISLAND + Vector3.new(0, 0, -16), radius = 2, count = 1, lv = { 1, 1 }, once = true, noElite = true, dungeon = "Dream", species = "Blockodile", element = "Dark", hpMult = 0.7, dream = true }
		run.camp = camp
		Combat.spawnWild(camp)
		Combat.aggroCamp(camp, pl)
		task.spawn(function()
			while runs[pl] == run do
				task.wait(0.3)
				if #Combat.campUnits(camp) == 0 then
					remotes.Intro:FireClient(pl, { kind = "won" })
					break
				end
			end
		end)
		return true, "ok"
	end
	return false, "Unknown"
end

function Intro.init(r, combat, summon)
	remotes, Combat, Summon = r, combat, summon
	r.IntroAsk.OnServerInvoke = function(pl, action, a)
		return Intro.handle(pl, action, a)
	end
	-- start the dream for brand-new Tamers once their profile and character are in
	local function tryStart(pl: Player)
		for _ = 1, 40 do
			local p = PlayerData.get(pl)
			if p and hrpOf(pl) then
				if eligible(p) and not runs[pl] then
					runs[pl] = { el = nil, hatched = false, camp = nil, fought = false }
					pl:SetAttribute("InIntro", true)
					task.wait(0.5)
					moveTo(pl, Intro.spawnAt, Vector3.new(0, 0, -1))
					remotes.Intro:FireClient(pl, { kind = "begin" })
				end
				return
			end
			task.wait(0.5)
		end
	end
	Players.PlayerAdded:Connect(function(pl)
		task.spawn(tryStart, pl)
	end)
	for _, pl in Players:GetPlayers() do
		task.spawn(tryStart, pl)
	end
	Players.PlayerRemoving:Connect(function(pl)
		local run = runs[pl]
		if run and run.camp then
			Combat.despawnCamp(run.camp)
		end
		runs[pl] = nil
	end)
	Intro.tryStart = tryStart
end

return Intro

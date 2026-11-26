-- Server-authoritative sleeper encounters: spawn, grab, carry noise, wake + bolt, recovery
-- window, banking and reveal rewards, and recovery when a carrier resets or leaves.
--
-- Each sleeper is one invisible server Part in workspace.Sleepers carrying replicated
-- attributes; clients draw the creature mesh and animations on top of it.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Creatures = require(Shared.Creatures)
local Noise = require(Shared.Noise)
local Map = require(script.Parent.Map)
local PlayerData = require(script.Parent.PlayerData)
local Quests = require(script.Parent.Quests)
local Events = require(script.Parent.Events)

local T = Config.Tuning

local Sleepers = {}

type Sleeper = {
	id: number,
	rarity: string,
	wing: string,
	family: string,
	species: string,
	spawnPos: Vector3,
	spawnIndex: number?,
	state: string, -- Sleeping | Carried | Bolting | Loose | Gone
	part: BasePart,
	prompt: ProximityPrompt,
	carrier: Player?,
	wake: number,
	exclusiveUser: number?,
	exclusiveUntil: number,
	routes: { [string]: boolean }, -- route tags passed while carried (Vent, BallPit, Cozy)
	maxWake: number, -- highest wake meter during this carry (quests: "before they twitch")
	regrabbed: boolean, -- caught again after waking up (quests: "catch a woken creature")
	lastSurface: string?,
	rush: boolean, -- grabbed during a Snack Rush in its wing: banks as Glazed or better
	lastPos: Vector3?,
	lastWakeSent: number,
	path: { Vector3 }?,
	pathT: number,
	boltStart: number,
	looseSince: number,
	landConn: RBXScriptConnection?,
	hop: { from: Vector3, to: Vector3 }?,
	speed: number,
}

local folder: Folder
local remotes: { [string]: any }
local sleepers: { [number]: Sleeper } = {}
local carrying: { [Player]: Sleeper } = {}
local stunnedUntil: { [Player]: number } = {}
local nextId = 0
local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Include

local function now()
	return workspace:GetServerTimeNow()
end

local function toast(player: Player, text: string, kind: string?)
	remotes.Toast:FireClient(player, text, kind or "info")
end

local function hrpOf(player: Player): BasePart?
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if not hum or hum.Health <= 0 then
		return nil
	end
	return char:FindFirstChild("HumanoidRootPart") :: BasePart?
end

function Sleepers.applySpeed(player: Player)
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if not hum then
		return
	end
	if (stunnedUntil[player] or 0) > now() then
		hum.WalkSpeed = 0
		return
	end
	local sprint = player:GetAttribute("Sprinting") == true
	local sp = Config.speeds(player:GetAttribute("Sneakers") or 0, player:GetAttribute("SteadyHands") or 0)
	if carrying[player] then
		hum.WalkSpeed = sprint and sp.carrySprint or sp.carryWalk
	else
		hum.WalkSpeed = sprint and sp.sprint or sp.walk
	end
end

local function groundAt(pos: Vector3): Vector3?
	local hit = workspace:Raycast(pos + Vector3.new(0, 6, 0), Vector3.new(0, -40, 0), rayParams)
	return hit and hit.Position
end

local function setState(s: Sleeper, state: string)
	s.state = state
	s.part:SetAttribute("State", state)
	local p = s.prompt
	if state == "Sleeping" then
		p.Enabled = true
		p.ActionText = "Grab"
		p.HoldDuration = 0.25
	elseif state == "Bolting" or state == "Loose" then
		p.Enabled = true
		p.ActionText = "Catch!"
		p.HoldDuration = 0
	else
		p.Enabled = false
	end
end

local function setWake(s: Sleeper, wake: number, force: boolean?)
	s.wake = math.clamp(wake, 0, 100)
	if s.state == "Carried" and s.wake > (s.maxWake or 0) then
		s.maxWake = s.wake
	end
	if force or math.abs(s.wake - s.lastWakeSent) >= 0.75 or (s.wake == 0) ~= (s.lastWakeSent == 0) then
		s.lastWakeSent = s.wake
		s.part:SetAttribute("Wake", math.floor(s.wake * 10) / 10)
		s.part:SetAttribute("Stage", Noise.stage(s.wake))
	end
end

local function placeAt(s: Sleeper, groundPos: Vector3, facing: Vector3?)
	local look = facing and Vector3.new(facing.X, 0, facing.Z)
	local h = s.part.Size.Y / 2
	local pos = groundPos + Vector3.new(0, h, 0)
	if look and look.Magnitude > 0.01 then
		s.part.CFrame = CFrame.lookAt(pos, pos + look.Unit)
	else
		local _, ry, _ = s.part.CFrame:ToOrientation()
		s.part.CFrame = CFrame.new(pos) * CFrame.Angles(0, ry, 0)
	end
end

local function detach(s: Sleeper)
	local weld = s.part:FindFirstChild("CarryWeld")
	if weld then
		weld:Destroy()
	end
	if s.landConn then
		s.landConn:Disconnect()
		s.landConn = nil
	end
	s.part.Anchored = true
	local c = s.carrier
	s.carrier = nil
	s.part:SetAttribute("CarrierId", nil)
	if c then
		carrying[c] = nil
		c:SetAttribute("Carrying", nil)
		Sleepers.applySpeed(c)
	end
end

local function destroySleeper(s: Sleeper)
	detach(s)
	s.state = "Gone"
	sleepers[s.id] = nil
	s.part:Destroy()
end

local spawnSleeper -- forward

local function scheduleRespawn(s: Sleeper)
	if s.rarity == "Rare" then
		workspace:SetAttribute("RareAt_" .. s.wing, now() + T.Spawns.RareRespawn)
		workspace:SetAttribute("RareActive_" .. s.wing, false)
	elseif s.spawnIndex then
		local idx = s.spawnIndex
		local delay = Events.rushActive(s.wing) and T.Events.RushRespawn or T.Spawns.CommonRespawn
		task.delay(delay, function()
			spawnSleeper("Common", idx)
		end)
	end
end

-- Send a loose or abandoned creature back to its spawn point.
local function returnHome(s: Sleeper)
	detach(s)
	s.exclusiveUser = nil
	s.exclusiveUntil = 0
	s.routes = {}
	s.part:SetAttribute("ExclusiveId", nil)
	s.part:SetAttribute("ExclusiveUntil", 0)
	setWake(s, 0, true)
	placeAt(s, s.spawnPos)
	setState(s, "Sleeping")
	remotes.Fx:FireAllClients("Poof", s.part.Position)
end

local function rollSpecies(rarity: string, family: string): string
	if rarity == "Common" then
		local list = Creatures.Families[family].Common
		return list[math.random(1, #list)]
	end
	return family -- unused
end

local function weighted(list: { any }, key: string): any
	local total = 0
	for _, e in list do
		total += e[key]
	end
	local r = math.random() * total
	for _, e in list do
		r -= e[key]
		if r <= 0 then
			return e
		end
	end
	return list[#list]
end

spawnSleeper = function(rarity: string, spawnIndex: number?, rareWing: string?): Sleeper
	nextId += 1
	local species, family, pos, wing
	if rarity == "Rare" then
		wing = rareWing or "FoodCourt"
		species = weighted(Creatures.RarePools[wing], "Weight").Species
		family = Creatures.Species[species].Family
		pos = Map.Points.RareStages[wing] + Vector3.new(0, 1, 0)
	else
		local spot = Map.Points.Spawns[spawnIndex :: number]
		wing = spot.wing
		local fams = Config.Wings[wing].Families
		-- the very first sleeper by the hideout is always a Dumpling, so a new player can
		-- get Crab Rangoon early
		family = (spawnIndex == 1 and nextId == 1) and "Dumpling" or fams[math.random(1, #fams)]
		species = rollSpecies("Common", family)
		pos = spot.pos
	end
	local sp = Creatures.Species[species]
	local size = rarity == "Rare" and 4 or 3
	local part = Instance.new("Part")
	part.Name = `Sleeper_{nextId}`
	part.Size = Vector3.new(size, size, size)
	part.Transparency = 1
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = true
	part.Massless = true
	part.Anchored = true
	part:SetAttribute("Id", nextId)
	part:SetAttribute("Rarity", rarity)
	part:SetAttribute("Wing", wing)
	part:SetAttribute("Family", family)
	-- Field visuals show the family's base look; exact species/form stays server-side.
	part:SetAttribute("FieldMesh", Creatures.Families[family].Common[1])
	part:SetAttribute("Wake", 0)
	part:SetAttribute("Stage", 0)
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "GrabPrompt"
	prompt.ObjectText = (rarity == "Rare" and "⭐ RARE " or "") .. family .. " sleeper"
	prompt.ActionText = "Grab"
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.MaxActivationDistance = T.PickupRange
	prompt.RequiresLineOfSight = false
	prompt.Parent = part
	local s: Sleeper = {
		id = nextId,
		rarity = rarity,
		wing = wing,
		family = family,
		species = species,
		spawnPos = pos,
		spawnIndex = spawnIndex,
		state = "Sleeping",
		part = part,
		prompt = prompt,
		carrier = nil,
		wake = 0,
		exclusiveUser = nil,
		exclusiveUntil = 0,
		routes = {},
		maxWake = 0,
		regrabbed = false,
		rush = false,
		lastPos = nil,
		lastWakeSent = 0,
		path = nil,
		pathT = 0,
		boltStart = 0,
		looseSince = 0,
		landConn = nil,
		hop = nil,
		speed = 0,
	}
	sleepers[s.id] = s
	placeAt(s, pos, Map.Points.Station - pos)
	part.Parent = folder
	setState(s, "Sleeping")
	prompt.Triggered:Connect(function(player)
		Sleepers.tryGrab(player, s.id)
	end)
	if rarity == "Rare" then
		workspace:SetAttribute("RareActive_" .. wing, true)
		remotes.Fx:FireAllClients("RareSpawn", part.Position, family, wing)
	end
	return s
end

function Sleepers.tryGrab(player: Player, id: number): (boolean, string?)
	local s = sleepers[id]
	if not s or s.state == "Carried" or s.state == "Gone" then
		return false, "gone"
	end
	if not PlayerData.get(player) then
		toast(player, "Loading your save… one sec", "info")
		return false, "loading"
	end
	if carrying[player] then
		toast(player, "Hands full! Bank it at the hideout first.", "warn")
		return false, "hands full"
	end
	local hrp = hrpOf(player)
	if not hrp then
		return false, "dead"
	end
	if (hrp.Position - s.part.Position).Magnitude > T.PickupRange + 3 then
		return false, "too far"
	end
	local t = now()
	if s.exclusiveUser and s.exclusiveUntil > t and s.exclusiveUser ~= player.UserId then
		toast(player, string.format("Not yet! Their grab window: %.1fs", s.exclusiveUntil - t), "warn")
		return false, "exclusive"
	end
	local regrab = s.state ~= "Sleeping"
	local sameCarrier = s.exclusiveUser == player.UserId
	-- claim
	s.carrier = player
	carrying[player] = s
	player:SetAttribute("Carrying", s.id)
	s.part:SetAttribute("CarrierId", player.UserId)
	s.exclusiveUser = nil
	s.exclusiveUntil = 0
	s.part:SetAttribute("ExclusiveId", nil)
	s.part:SetAttribute("ExclusiveUntil", 0)
	s.path = nil
	s.hop = nil
	if not (regrab and sameCarrier) then
		s.routes = {}
	end
	s.regrabbed = regrab
	s.maxWake = regrab and T.Bolt.RegrabWake or 0
	s.rush = (regrab and s.rush) or Events.rushActive(s.wing)
	setWake(s, regrab and T.Bolt.RegrabWake or 0, true)
	s.lastPos = hrp.Position
	s.speed = 0
	s.part.Anchored = false
	s.part.CFrame = hrp.CFrame * CFrame.new(0, 4.2, -0.6) -- held overhead so the camera sees its face
	local weld = Instance.new("WeldConstraint")
	weld.Name = "CarryWeld"
	weld.Part0 = hrp
	weld.Part1 = s.part
	weld.Parent = s.part
	local hum = player.Character:FindFirstChildOfClass("Humanoid")
	s.landConn = hum.StateChanged:Connect(function(_, new)
		if new == Enum.HumanoidStateType.Landed and s.carrier == player then
			setWake(s, s.wake + T.Noise.LandSpike * T.Rarity[s.rarity].WakeMult * Config.Wings[s.wing].WakeMult)
		end
	end)
	setState(s, "Carried")
	Sleepers.applySpeed(player)
	remotes.Fx:FireAllClients("Grab", s.part.Position, s.id, player.UserId)
	return true
end

-- Ground nav path for a bolting creature: greedy walk away from the carrier.
local function buildBoltPath(from: Vector3, awayFrom: Vector3): { Vector3 }
	local nodes, links = Map.Nav.nodes, Map.Nav.links
	local adj = {}
	for i = 1, #nodes do
		adj[i] = {}
	end
	for _, l in links do
		table.insert(adj[l[1]], l[2])
		table.insert(adj[l[2]], l[1])
	end
	-- nearest node with line of sight, preferring ones away from the carrier
	local best, bestScore = nil, math.huge
	for i, n in nodes do
		local d = (n - from).Magnitude
		local away = (n - awayFrom).Magnitude - (from - awayFrom).Magnitude
		local score = d - away * 0.6
		local hit = workspace:Raycast(from + Vector3.new(0, 1.5, 0), n - from, rayParams)
		if hit then
			score += 1000
		end
		if score < bestScore then
			best, bestScore = i, score
		end
	end
	local path = { from, nodes[best] }
	local budget = T.Bolt.Speed * T.Bolt.Duration
	local dist = (nodes[best] - from).Magnitude
	local visited = { [best] = true }
	local cur = best
	while dist < budget do
		local nextNode, nextScore = nil, -math.huge
		for _, j in adj[cur] do
			if not visited[j] then
				local sc = (nodes[j] - awayFrom).Magnitude + math.random() * 6
				if sc > nextScore then
					nextNode, nextScore = j, sc
				end
			end
		end
		if not nextNode then
			break
		end
		visited[nextNode] = true
		dist += (nodes[nextNode] - nodes[cur]).Magnitude
		table.insert(path, nodes[nextNode])
		cur = nextNode
	end
	return path
end

local function wakeUp(s: Sleeper)
	local carrier = s.carrier :: Player
	local hrp = carrier and hrpOf(carrier)
	local start = s.part.Position
	local carrierPos = hrp and hrp.Position or start
	local look = hrp and hrp.CFrame.LookVector or Vector3.new(0, 0, 1)
	detach(s)
	-- startled hop away from the carrier (forward, out of their hands)
	local hopTo = start + Vector3.new(look.X, 0, look.Z).Unit * T.Bolt.HopDistance
	local hit = workspace:Raycast(start, hopTo - start, rayParams)
	if hit then
		hopTo = hit.Position - (hopTo - start).Unit * 1.5
	end
	local g = groundAt(hopTo) or groundAt(start) or (start - Vector3.new(0, 3, 0))
	s.hop = { from = s.part.Position, to = g }
	s.path = buildBoltPath(g, carrierPos)
	s.pathT = 0
	s.boltStart = now()
	if carrier then
		s.exclusiveUser = carrier.UserId
		s.exclusiveUntil = now() + T.Bolt.ExclusiveWindow
		s.part:SetAttribute("ExclusiveId", carrier.UserId)
		s.part:SetAttribute("ExclusiveUntil", s.exclusiveUntil)
		stunnedUntil[carrier] = now() + T.Bolt.CarrierStun
		Sleepers.applySpeed(carrier)
		task.delay(T.Bolt.CarrierStun + 0.05, function()
			Sleepers.applySpeed(carrier)
		end)
		toast(carrier, "IT WOKE UP! Catch it!", "alert")
	end
	setWake(s, 100, true)
	setState(s, "Bolting")
	remotes.Fx:FireAllClients("Wake", start, s.id)
end

-- Wake multiplier for this sleeper (rarity x wing: deeper wings wake faster).
local function wakeMult(s: Sleeper): number
	return T.Rarity[s.rarity].WakeMult * Config.Wings[s.wing].WakeMult
end

local function bank(s: Sleeper, player: Player)
	local p = PlayerData.get(player)
	if not p or s.state ~= "Carried" or s.carrier ~= player then
		return
	end
	-- claim first so nothing else can touch this encounter
	local routes = s.routes
	local species = s.species
	local rarity = s.rarity
	local wing = s.wing
	local maxWake = s.maxWake or 0
	local regrabbed = s.regrabbed == true
	destroySleeper(s)
	scheduleRespawn(s)

	local formsKey = rarity == "Rare" and "RareWeight" or (s.rush and "RushWeight" or "Weight")
	local form = weighted(T.Forms, formsKey)
	local coins = T.Rarity[rarity].BaseCoins * Config.Wings[wing].CoinMult * form.CoinMult
	local ws, wf = Events.wanted(wing)
	local wanted = Config.isWanted(ws, wf, species, form.Id)
	if wanted then
		coins *= T.Events.WantedMult
	end
	local bonus = p.buddy and T.BuddyCoinBonus[p.buddy]
	if bonus then
		coins *= 1 + bonus
	end
	coins = math.floor(coins)
	p.coins += coins
	p.rescues += 1
	local isNew = PlayerData.record(p, species, form.Id)

	-- evolution progress: the From buddy equipped, and this rescue passed the route
	local evoInfo = nil
	for _, evo in T.Evolutions do
		if p.buddy == evo.From and routes[evo.Route] and not p.collection[evo.To] then
			p.evo[evo.To] = (p.evo[evo.To] or 0) + 1
			evoInfo = { to = evo.To, from = evo.From, count = p.evo[evo.To], needed = evo.Needed, route = evo.RouteName }
			if p.evo[evo.To] >= evo.Needed then
				PlayerData.record(p, evo.To, "Normal")
				p.buddy = evo.To
				evoInfo.evolved = true
			end
		end
	end
	PlayerData.push(player)
	if isNew or evoInfo or rarity == "Rare" then
		PlayerData.saveSoon(player)
	end
	remotes.Reveal:FireClient(player, {
		species = species,
		form = form.Id,
		coins = coins,
		isNew = isNew,
		rarity = rarity,
		wing = wing,
		evo = evoInfo,
		wanted = wanted,
		rush = s.rush,
	})
	remotes.Fx:FireAllClients("Bank", Map.Points.Station, species, player.UserId, form.Id)
	task.spawn(Quests.onBank, player, { wing = wing, routes = routes, maxWake = maxWake, regrabbed = regrabbed, form = form.Id, rarity = rarity })
end

local function updateCarried(s: Sleeper, dt: number)
	local player = s.carrier :: Player
	local hrp = hrpOf(player)
	if not hrp then
		-- died mid-carry; drop where they were
		Sleepers.drop(player)
		return
	end
	local pos = hrp.Position
	local last = s.lastPos or pos
	s.lastPos = pos
	local delta = Vector3.new(pos.X - last.X, 0, pos.Z - last.Z)
	local inst = dt > 0 and delta.Magnitude / dt or 0
	if inst > 120 then
		inst = 0 -- teleport/reset, ignore
	end
	-- Replicated positions arrive in bursts, so per-frame speed is spiky; smooth it (~0.3 s).
	s.speed = s.speed + (inst - s.speed) * (1 - math.exp(-dt / 0.3))
	local speed = s.speed
	local surface, route = Map.surfaceAt(pos)
	if route then
		s.routes[route] = true
	end
	if surface == "Squeak" and s.lastSurface ~= "Squeak" then
		-- stepped on a squeaky toy
		setWake(s, s.wake + T.Noise.SqueakSpike * wakeMult(s))
		remotes.Fx:FireAllClients("Squeak", pos)
	end
	s.lastSurface = surface
	if (pos - Map.Points.Station).Magnitude <= T.BankRadius then
		bank(s, player)
		return
	end
	local rate = Noise.rate({
		speed = speed,
		surface = surface,
		t = now(),
		rarity = s.rarity,
		paddedShoes = player:GetAttribute("PaddedShoes") == true,
		carryWalk = Config.speeds(0, player:GetAttribute("SteadyHands") or 0).carryWalk,
		mult = wakeMult(s),
	})
	setWake(s, s.wake + rate * dt)
	s.part:SetAttribute("Surface", surface)
	if s.wake >= T.WakeStages.Awake then
		wakeUp(s)
	end
end

local function updateBolting(s: Sleeper, dt: number)
	local t = now() - s.boltStart
	local hop = s.hop
	local hopT = T.Bolt.HopTime
	if hop and t < hopT then
		local a = t / hopT
		local p = hop.from:Lerp(hop.to + Vector3.new(0, s.part.Size.Y / 2, 0), a) + Vector3.new(0, math.sin(a * math.pi) * 3, 0)
		s.part.CFrame = CFrame.lookAt(p, p + (hop.to - hop.from) * Vector3.new(1, 0, 1) + Vector3.new(0, 0, 0.001))
		return
	end
	local path = s.path
	if not path or t > hopT + T.Bolt.Duration then
		s.looseSince = now()
		setWake(s, 70, true)
		setState(s, "Loose")
		return
	end
	s.pathT += T.Bolt.Speed * dt
	local remaining = s.pathT
	for i = 1, #path - 1 do
		local a, b = path[i], path[i + 1]
		local seg = (b - a).Magnitude
		if remaining <= seg then
			local p = a:Lerp(b, remaining / seg)
			placeAt(s, p, b - a)
			return
		end
		remaining -= seg
	end
	-- ran out of path
	s.looseSince = now()
	setWake(s, 70, true)
	setState(s, "Loose")
end

local function step(dt: number)
	local t = now()
	for _, s in sleepers do
		if s.state == "Carried" then
			updateCarried(s, dt)
		elseif s.state == "Bolting" then
			updateBolting(s, dt)
		elseif s.state == "Loose" then
			-- loose creatures slowly settle; untouched ones walk home
			setWake(s, math.max(0, s.wake - 4 * dt))
			if s.exclusiveUntil > 0 and s.exclusiveUntil <= t then
				s.exclusiveUser = nil
				s.exclusiveUntil = 0
				s.part:SetAttribute("ExclusiveId", nil)
				s.part:SetAttribute("ExclusiveUntil", 0)
			end
			if t - s.looseSince > T.Bolt.LooseTimeout then
				returnHome(s)
			end
		end
		if s.state == "Bolting" and s.exclusiveUntil > 0 and s.exclusiveUntil <= t then
			s.exclusiveUser = nil
			s.exclusiveUntil = 0
			s.part:SetAttribute("ExclusiveId", nil)
			s.part:SetAttribute("ExclusiveUntil", 0)
		end
	end
	-- rare spawn timers, one per wing
	for wing in Config.Wings do
		local active = workspace:GetAttribute("RareActive_" .. wing)
		if not active and t >= (workspace:GetAttribute("RareAt_" .. wing) or math.huge) then
			spawnSleeper("Rare", nil, wing)
			active = true
		end
		local beam = Map.beams[wing]
		if beam then
			beam.Transparency = active and 0.6 or 1
		end
	end
end

-- Carrier reset, died or left: the creature drops where they were (recoverable by anyone),
-- or goes home if that spot is invalid.
function Sleepers.drop(player: Player)
	local s = carrying[player]
	if not s then
		return
	end
	local pos = s.part.Position
	detach(s)
	stunnedUntil[player] = nil
	local g = groundAt(pos)
	if not g or g.Y < -10 then
		returnHome(s)
		return
	end
	placeAt(s, g)
	s.exclusiveUser = nil
	s.exclusiveUntil = 0
	s.part:SetAttribute("ExclusiveId", nil)
	s.part:SetAttribute("ExclusiveUntil", 0)
	s.looseSince = now()
	setWake(s, 60, true)
	setState(s, "Loose")
	remotes.Fx:FireAllClients("Drop", g, s.id)
end

function Sleepers.init(r: { [string]: any }, mapFolder: Folder)
	remotes = r
	rayParams.FilterDescendantsInstances = { mapFolder }
	folder = Instance.new("Folder")
	folder.Name = "Sleepers"
	folder.Parent = workspace
	for wing, w in Config.Wings do
		workspace:SetAttribute("RareAt_" .. wing, now() + T.Spawns.RareFirstDelay + (w.Order - 1) * 15)
		workspace:SetAttribute("RareActive_" .. wing, false)
	end
	for i = 1, #Map.Points.Spawns do
		spawnSleeper("Common", i)
	end
	RunService.Heartbeat:Connect(step)
	Players.PlayerRemoving:Connect(function(player)
		Sleepers.drop(player)
		stunnedUntil[player] = nil
	end)
end

function Sleepers.onCharacter(player: Player, char: Model)
	local hum = char:WaitForChild("Humanoid") :: Humanoid
	Sleepers.applySpeed(player)
	hum.Died:Connect(function()
		Sleepers.drop(player)
	end)
	char.AncestryChanged:Connect(function(_, parent)
		if not parent then
			Sleepers.drop(player)
		end
	end)
end

-- Test hooks (used by Studio MCP playtests; harmless in play).
Sleepers.debug = {
	list = function()
		local out = {}
		for id, s in sleepers do
			out[id] = { state = s.state, rarity = s.rarity, wing = s.wing, family = s.family, species = s.species, wake = s.wake, carrier = s.carrier and s.carrier.Name, exclusive = s.exclusiveUser, passedVent = s.routes.Vent == true, routes = s.routes, pos = s.part.Position, speed = s.speed, surface = s.part:GetAttribute("Surface") }
		end
		return out
	end,
	get = function(id)
		return sleepers[id]
	end,
	carrying = carrying,
	forceWake = function(id)
		local s = sleepers[id]
		if s and s.state == "Carried" then
			wakeUp(s)
		end
	end,
	home = function(id)
		local s = sleepers[id]
		if s then
			returnHome(s)
		end
	end,
	forceRare = function(wing)
		workspace:SetAttribute("RareAt_" .. (wing or "FoodCourt"), now())
	end,
	setWake = function(id, w)
		local s = sleepers[id]
		if s then
			setWake(s, w, true)
		end
	end,
}

return Sleepers

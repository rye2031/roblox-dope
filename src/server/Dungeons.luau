-- Dungeon runs (see Shared/DungeonData). A run is solo: the player and their team are moved to
-- a floating arena far off the map (one per run, built on first use and reused), fight three
-- waves that charge straight at them, then a boss, and open the chest: runes of the dungeon's
-- set, coins, Essence and a first-clear bonus. A clear uses a key; a failed run (knocked out,
-- time up) or leaving costs nothing.
--
-- Profile: p.dungeon = { keys, keyAt, clears = { ["Grove:Normal"] = n }, best = { [same] = seconds } }
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Runes = require(Shared.Runes)
local DD = require(Shared.DungeonData)
local PlayerData = require(script.Parent.PlayerData)
local RuneBag = require(script.Parent.RuneBag)
local World = require(script.Parent.World)

local Dungeons = {}
local Combat -- set in init (Combat requires lots; avoid a loop)
local remotes
local rng = Random.new()

local FLOOR_Y = 120
local ORIGIN = Vector3.new(4000, FLOOR_Y, 4000)
local SPACING = 320
local RADIUS = 44

local arenas: { { centre: Vector3, folder: Folder, busy: boolean, theme: string? } } = {}
local runs: { [Player]: any } = {}

local function now(): number
	return os.time()
end

----------------------------------------------------------------------------------------------
-- arenas

local function newPart(props, parent)
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

local folderRoot: Folder

-- Paint an arena in a dungeon's colours (floor, rim, pillars, crystals).
local function theme(a, id: string)
	if a.theme == id then
		return
	end
	a.theme = id
	local d = DD.List[id]
	for _, p in a.folder:GetDescendants() do
		if p:IsA("BasePart") then
			local role = p:GetAttribute("Role")
			if role == "floor" then
				p.Color = d.Stone
			elseif role == "rim" or role == "pillar" then
				p.Color = d.Stone:Lerp(Color3.new(1, 1, 1), 0.25)
			elseif role == "glow" then
				p.Color = d.Color
			end
		end
	end
end

local function buildArena(i: number)
	local centre = ORIGIN + Vector3.new((i - 1) * SPACING, 0, 0)
	local f = Instance.new("Folder")
	f.Name = "Arena" .. i
	f.Parent = folderRoot
	-- floor: a 24-sided disc of wedges, thick so nothing falls through
	newPart({ Name = "Floor", Shape = Enum.PartType.Cylinder, Size = Vector3.new(6, RADIUS * 2 + 8, RADIUS * 2 + 8), CFrame = CFrame.new(centre - Vector3.new(0, 3, 0)) * CFrame.Angles(0, 0, math.rad(90)), Material = Enum.Material.Slate }, f):SetAttribute("Role", "floor")
	newPart({ Name = "Underside", Shape = Enum.PartType.Ball, Size = Vector3.new(RADIUS * 1.6, 40, RADIUS * 1.6), CFrame = CFrame.new(centre - Vector3.new(0, 25, 0)), Material = Enum.Material.Rock, CanCollide = false }, f):SetAttribute("Role", "floor")
	-- rim wall + pillars + glowing crystals
	local n = 24
	for k = 0, n - 1 do
		local a = k / n * math.pi * 2
		local pos = centre + Vector3.new(math.cos(a) * (RADIUS + 3), 4, math.sin(a) * (RADIUS + 3))
		newPart({ Name = "Rim", Size = Vector3.new(2, 8, (RADIUS + 3) * 2 * math.pi / n + 0.6), CFrame = CFrame.lookAt(pos, Vector3.new(centre.X, pos.Y, centre.Z)) * CFrame.Angles(0, math.rad(90), 0), Material = Enum.Material.Cobblestone }, f):SetAttribute("Role", "rim")
		-- invisible tall wall so nobody jumps out
		newPart({ Name = "Barrier", Size = Vector3.new(2, 40, (RADIUS + 3) * 2 * math.pi / n + 0.6), CFrame = CFrame.lookAt(pos + Vector3.new(0, 20, 0), Vector3.new(centre.X, pos.Y + 20, centre.Z)) * CFrame.Angles(0, math.rad(90), 0), Transparency = 1, CanQuery = false }, f)
		if k % 4 == 0 then
			local pp = centre + Vector3.new(math.cos(a) * (RADIUS - 2), 0, math.sin(a) * (RADIUS - 2))
			newPart({ Name = "Pillar", Shape = Enum.PartType.Cylinder, Size = Vector3.new(14, 3.4, 3.4), CFrame = CFrame.new(pp + Vector3.new(0, 7, 0)) * CFrame.Angles(0, 0, math.rad(90)), Material = Enum.Material.Cobblestone }, f):SetAttribute("Role", "pillar")
			newPart({ Name = "Crystal", Size = Vector3.new(1.8, 3.6, 1.8), CFrame = CFrame.new(pp + Vector3.new(0, 15.6, 0)) * CFrame.Angles(0, math.rad(45), math.rad(12)), Material = Enum.Material.Neon, CanCollide = false }, f):SetAttribute("Role", "glow")
		end
	end
	-- centre rune circle (where the chest appears)
	newPart({ Name = "Circle", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.2, 14, 14), CFrame = CFrame.new(centre + Vector3.new(0, 0.1, 0)) * CFrame.Angles(0, 0, math.rad(90)), Material = Enum.Material.Neon, Transparency = 0.6, CanCollide = false, CanQuery = false }, f):SetAttribute("Role", "glow")
	World.addGround(f)
	local a = { centre = centre, folder = f, busy = false, theme = nil }
	arenas[i] = a
	return a
end

local function freeArena()
	for _, a in arenas do
		if not a.busy then
			return a
		end
	end
	return buildArena(#arenas + 1)
end

----------------------------------------------------------------------------------------------
-- profile

local function state(p)
	p.dungeon = p.dungeon or { keys = DD.KeyCap, keyAt = now(), clears = {}, best = {} }
	DD.refill(p.dungeon, now())
	return p.dungeon
end

function Dungeons.sanitize(raw, p)
	local d = typeof(raw) == "table" and typeof(raw.dungeon) == "table" and raw.dungeon or {}
	local out = { keys = math.clamp(math.floor(tonumber(d.keys) or DD.KeyCap), 0, DD.KeyCap), keyAt = tonumber(d.keyAt) or now(), clears = {}, best = {} }
	for _, field in { "clears", "best" } do
		if typeof(d[field]) == "table" then
			for k, v in d[field] do
				local id, mode
				if typeof(k) == "string" then
					id, mode = string.match(k, "^(%w+):(%w+)$")
				end
				if id and DD.List[id] and DD.Modes[mode] and tonumber(v) then
					out[field][k] = math.max(0, math.floor(tonumber(v) :: number))
				end
			end
		end
	end
	p.dungeon = out
end

local function unlocked(p, id: string, mode: string): (boolean, string?)
	local d = DD.List[id]
	if not d then
		return false, "Unknown dungeon"
	end
	if not p.bosses[d.Region] then
		return false, "Opens when you beat the " .. d.RegionName .. " boss"
	end
	if mode == "Hard" and (state(p).clears[id .. ":Normal"] or 0) < 1 then
		return false, "Clear " .. d.Name .. " on Normal first"
	end
	return true
end

----------------------------------------------------------------------------------------------
-- parties: a leader opens a party at the Dungeon Gate for one dungeon and mode, up to two
-- more players standing at the gate join, and the leader starts. Each member's chest uses
-- their own key; members without a key (or a bag that's full) come along as helpers and get
-- coins and Essence. Waves and the boss scale with the party size.

local PARTY_MAX = 3
local GATE_RANGE = 40
local LOBBY_SECONDS = 5 * 60
local lobbies: { [Player]: { id: string, mode: string, members: { Player }, at: number } } = {}
local memberOf: { [Player]: Player } = {} -- player -> lobby leader

local function hrpOf(player: Player): BasePart?
	local c = player.Character
	return c and c:FindFirstChild("HumanoidRootPart") :: BasePart?
end

local function atGate(player: Player): boolean
	local hrp = hrpOf(player)
	return hrp ~= nil and (hrp.Position - World.Points.Dungeons).Magnitude <= GATE_RANGE
end

local function lobbyChanged(note: string?, near: Player?)
	-- everyone at the gate refreshes their panel (and hears about a new party)
	for _, pl in Players:GetPlayers() do
		if atGate(pl) or memberOf[pl] then
			remotes.DungeonRun:FireClient(pl, { kind = "lobby", note = pl ~= near and note or nil })
		end
	end
end

local function dropFromLobby(player: Player, why: string?)
	local leader = memberOf[player]
	if not leader then
		return
	end
	memberOf[player] = nil
	local lob = lobbies[leader]
	if not lob then
		return
	end
	if player == leader then
		-- the party closes
		for _, m in lob.members do
			memberOf[m] = nil
			if m ~= player and m.Parent then
				remotes.Toast:FireClient(m, leader.DisplayName .. "'s party closed", "info")
			end
		end
		lobbies[leader] = nil
	else
		local i = table.find(lob.members, player)
		if i then
			table.remove(lob.members, i)
		end
		if why and player.Parent then
			remotes.Toast:FireClient(player, why, "info")
		end
	end
	lobbyChanged()
end

local function partyInfo(player: Player)
	local open = {}
	for leader, lob in lobbies do
		local names = {}
		for _, m in lob.members do
			table.insert(names, m.DisplayName)
		end
		table.insert(open, { leader = leader.UserId, leaderName = leader.DisplayName, id = lob.id, mode = lob.mode, names = names, n = #lob.members, mine = memberOf[player] == leader, lead = leader == player })
	end
	return open
end

function Dungeons.info(player: Player)
	local p = PlayerData.get(player)
	if not p then
		return false, "No profile"
	end
	local st = state(p)
	local list = {}
	for _, id in DD.Order do
		local row = { id = id, modes = {} }
		for mode in DD.Modes do
			local ok, why = unlocked(p, id, mode)
			row.modes[mode] = { open = ok, why = why, clears = st.clears[id .. ":" .. mode] or 0, best = st.best[id .. ":" .. mode] }
		end
		table.insert(list, row)
	end
	local keys, nextAt = DD.refill(st, now())
	return true, "ok", { keys = keys, nextAt = nextAt, list = list, inRun = runs[player] ~= nil, parties = partyInfo(player), partyMax = PARTY_MAX }
end

----------------------------------------------------------------------------------------------
-- runs (a run is shared by its members: runs[member] = run)

local function send(player: Player, msg)
	if player.Parent then
		remotes.DungeonRun:FireClient(player, msg)
	end
end

local function sendAll(run, msg)
	for _, m in run.members do
		send(m, msg)
	end
end

local function moveTo(player: Player, pos: Vector3, facing: Vector3?)
	local hrp = hrpOf(player)
	if not hrp then
		return
	end
	pcall(function()
		player:RequestStreamAroundAsync(pos)
	end)
	local look = facing or Vector3.new(0, 0, -1)
	hrp.AssemblyLinearVelocity = Vector3.zero
	hrp.CFrame = CFrame.lookAt(pos + Vector3.new(0, 3.5, 0), pos + Vector3.new(look.X, 3.5, look.Z))
	Combat.warpTeam(player, pos)
end

local function clearUnits(run)
	for _, camp in run.camps do
		Combat.despawnCamp(camp)
	end
	run.camps = {}
end

local function endRun(run)
	run.over = true
	clearUnits(run)
	run.arena.busy = false
end

-- One member leaves the run (left, knocked out, time up, cleared). The run ends when the last
-- member is gone. `result` "knocked" skips the walk home (they respawn at a campfire).
local function memberOut(player: Player, run, result: string, why: string?)
	local i = table.find(run.members, player)
	if not i then
		return
	end
	table.remove(run.members, i)
	if result ~= "clear" and why then
		send(player, { kind = "fail", why = why })
	end
	if #run.members == 0 and not run.over then
		endRun(run)
	elseif result ~= "clear" and not run.over then
		sendAll(run, { kind = "party", note = player.DisplayName .. (result == "knocked" and " was knocked out" or " left the run"), n = #run.members })
	end
	task.delay(result == "clear" and 4 or 2.5, function()
		if runs[player] == run then
			runs[player] = nil
			player:SetAttribute("Dungeon", nil)
			if result ~= "knocked" and player.Parent then
				moveTo(player, World.Points.Dungeons + Vector3.new(4, 0, 0), Vector3.new(1, 0, 0))
			end
			send(player, { kind = "end" })
		end
	end)
end

local function chest(player: Player, run)
	local p = PlayerData.get(player)
	if not p then
		return
	end
	local d, m = DD.List[run.id], DD.Modes[run.mode]
	local st = state(p)
	local key = run.id .. ":" .. run.mode
	local secs = now() - run.started
	local lvTop = select(2, DD.levels(run.id, run.mode))
	local el = Config.pickWeighted(d.Elements, rng:NextNumber())
	local rewards = { runes = {}, time = secs, el = el, party = run.size }
	-- a helper (no key left, or bag full at the start) gets coins and Essence only
	local helper = run.helpers[player] == true or DD.refill(st, now()) < 1
	if helper then
		rewards.helper = true
		rewards.coins = math.floor((200 + lvTop * 25) * m.coins * 0.5)
		rewards.essence = run.mode == "Hard" and 5 or 3
		p.coins += rewards.coins
		p.essence[el] = (p.essence[el] or 0) + rewards.essence
	else
		local first = (st.clears[key] or 0) == 0
		st.keys = math.max(0, st.keys - 1)
		if st.keys == DD.KeyCap - 1 then
			st.keyAt = now()
		end
		st.clears[key] = (st.clears[key] or 0) + 1
		local best = st.best[key]
		rewards.best = best == nil or secs < best
		if rewards.best then
			st.best[key] = secs
		end
		rewards.first = first
		rewards.coins = math.floor((200 + lvTop * 25) * m.coins)
		p.coins += rewards.coins
		rewards.essence = run.mode == "Hard" and 10 or 5
		p.essence[el] = (p.essence[el] or 0) + rewards.essence
		for _ = 1, m.runes do
			local rarity = Runes.pickRarity(rng, m.weights)
			local rune = RuneBag.give(p, rarity, run.id)
			if rune then
				table.insert(rewards.runes, rune)
			else
				rewards.bagFull = true
			end
		end
		if first then
			p.scrolls.Regular += m.first.scrolls or 0
			p.scrolls.Legendary += m.first.legendary or 0
			rewards.firstScrolls = m.first.scrolls
			rewards.firstLegendary = m.first.legendary
		end
	end
	PlayerData.push(player)
	PlayerData.saveSoon(player)
	send(player, { kind = "clear", rewards = rewards, id = run.id, mode = run.mode })
	if Dungeons.onClear then
		Dungeons.onClear(player, run.id, run.mode)
	end
end

-- Extra monsters and HP for a bigger party (n = members when the wave spawns).
function Dungeons.scale(n: number): { count: number, hp: number, boss: number }
	n = math.max(1, n)
	return { count = 1 + 0.5 * (n - 1), hp = 1 + 0.3 * (n - 1), boss = 1 + 0.75 * (n - 1) }
end

local function aggro(run)
	-- spread the camps over the members so everyone has something to fight
	for i, camp in run.camps do
		local target = run.members[(i - 1) % math.max(1, #run.members) + 1]
		if target then
			Combat.aggroCamp(camp, target)
		end
	end
end

local function spawnWave(run, w: number)
	local d, m = DD.List[run.id], DD.Modes[run.mode]
	local lo, hi = DD.levels(run.id, run.mode)
	local c = run.arena.centre
	local sc = Dungeons.scale(#run.members)
	local camps = {}
	local function camp(props)
		local base = { id = "dg" .. run.key .. "_" .. w .. "_" .. #camps, region = d.Region, radius = 8, lv = { lo, hi }, once = true, noElite = true, dungeon = run.id, elements = d.Elements, hpMult = m.hpMult * sc.hp }
		for k, v in props do
			base[k] = v
		end
		base.pos = Vector3.new(base.pos.X, c.Y, base.pos.Z)
		table.insert(camps, base)
		return base
	end
	if w <= #DD.WaveSizes then
		local n = math.floor(DD.WaveSizes[w] * sc.count + 0.5)
		-- far side of the arena, spread out
		camp({ pos = c + Vector3.new(0, 0, -24), count = math.ceil(n / 2), radius = 10 })
		camp({ pos = c + Vector3.new(w % 2 == 0 and 20 or -20, 0, -12), count = math.floor(n / 2), radius = 8 })
		if w == #DD.WaveSizes then
			camp({ pos = c + Vector3.new(0, 0, -30), count = 1, elite = true, hpMult = 3.5 * m.hpMult * sc.hp, stars = 4 })
		end
	else
		camp({ pos = c + Vector3.new(0, 0, -26), count = 1, boss = true, hpMult = m.bossHp * sc.boss, stars = 4, lv = { hi + 2, hi + 2 }, radius = 0 })
	end
	run.camps = camps
	for _, cp in camps do
		Combat.spawnWild(cp)
	end
	aggro(run)
	run.wave = w
	run.left = -1
end

local function living(run): number
	local n = 0
	for _, camp in run.camps do
		n += #Combat.campUnits(camp)
	end
	return n
end

local function loop(run)
	local waves = #DD.WaveSizes
	spawnWave(run, 1)
	while not run.over and #run.members > 0 do
		task.wait(0.4)
		if run.over or #run.members == 0 then
			break
		end
		if now() >= run.endsAt then
			for _, m in table.clone(run.members) do
				memberOut(m, run, "time", "Time's up! The run ended (no key used)")
			end
			break
		end
		-- keep their aggro on the party (a wiped team leaves them idle otherwise)
		for _, camp in run.camps do
			for _, u in Combat.campUnits(camp) do
				local t = u.target
				local who = t and (t.player or t.owner)
				if not who or not table.find(run.members, who) then
					aggro(run)
					break
				end
			end
		end
		local left = living(run)
		if left ~= run.left then
			run.left = left
			sendAll(run, { kind = "wave", wave = run.wave, of = waves, left = left, boss = run.wave > waves, n = #run.members })
		end
		if left == 0 then
			if run.wave > waves then
				for _, m in table.clone(run.members) do
					chest(m, run)
				end
				endRun(run)
				for _, m in table.clone(run.members) do
					memberOut(m, run, "clear")
				end
				break
			end
			task.wait(2.5)
			if run.over or #run.members == 0 then
				break
			end
			spawnWave(run, run.wave + 1)
		end
	end
end

-- Checks one member can go: profile, dungeon open, not busy, at the gate.
local function canGo(player: Player, id: string, mode: string, leader: boolean): (boolean, string?)
	local p = PlayerData.get(player)
	if not p then
		return false, "No profile"
	end
	if runs[player] then
		return false, "already in a run"
	end
	local ok, why = unlocked(p, id, leader and mode or "Normal")
	if not ok then
		return false, why
	end
	if Combat.inCombat(player) then
		return false, "Finish your fight first"
	end
	if not atGate(player) then
		return false, "Stand at the Dungeon Gate in Haven"
	end
	if leader then
		if DD.refill(state(p), now()) < 1 then
			return false, "No keys left: one comes back every " .. DD.KeyMinutes .. " minutes"
		end
		if RuneBag.count(p) >= Runes.BagCap then
			return false, "Your rune bag is full: sell some runes first"
		end
	end
	return true
end

local function launch(members: { Player }, id: string, mode: string)
	local arena = freeArena()
	arena.busy = true
	theme(arena, id)
	local run = { id = id, mode = mode, arena = arena, started = now(), endsAt = now() + DD.TimeLimit, camps = {}, wave = 0, over = false, members = {}, helpers = {}, size = #members, key = tostring(members[1].UserId) .. "_" .. now() }
	for i, pl in members do
		local p = PlayerData.get(pl)
		if p and (DD.refill(state(p), now()) < 1 or RuneBag.count(p) >= Runes.BagCap) then
			run.helpers[pl] = true
		end
		table.insert(run.members, pl)
		runs[pl] = run
		pl:SetAttribute("Dungeon", id .. ":" .. mode)
		Combat.healTeam(pl)
		local hum = pl.Character and pl.Character:FindFirstChildOfClass("Humanoid")
		if hum then
			hum.Health = hum.MaxHealth
		end
		-- stand at the near edge, side by side, facing the far side where waves appear
		moveTo(pl, arena.centre + Vector3.new((i - (#members + 1) / 2) * 9, 0, 26), Vector3.new(0, 0, -1))
	end
	local names = {}
	for _, pl in members do
		table.insert(names, pl.DisplayName)
	end
	for _, pl in members do
		send(pl, { kind = "start", id = id, mode = mode, endsAt = workspace:GetServerTimeNow() + DD.TimeLimit, waves = #DD.WaveSizes, names = names, helper = run.helpers[pl] == true })
	end
	task.delay(3, function()
		if not run.over and #run.members > 0 then
			loop(run)
		end
	end)
	return run
end

-- Solo start (no party), or the leader starting their party.
function Dungeons.start(player: Player, id: any, mode: any)
	local lob = lobbies[player]
	if lob then
		id, mode = lob.id, lob.mode
	end
	if typeof(id) ~= "string" or not DD.List[id] or typeof(mode) ~= "string" or not DD.Modes[mode] then
		return false, "Pick a dungeon"
	end
	if memberOf[player] and not lob then
		return false, "Only the party leader can start"
	end
	local ok, why = canGo(player, id, mode, true)
	if not ok then
		return false, why
	end
	local members = { player }
	if lob then
		for _, m in table.clone(lob.members) do
			if m ~= player then
				local mok, mwhy = canGo(m, id, mode, false)
				if mok then
					table.insert(members, m)
				else
					remotes.Toast:FireClient(m, "Couldn't join the run: " .. tostring(mwhy), "warn")
				end
			end
		end
		for _, m in lob.members do
			memberOf[m] = nil
		end
		lobbies[player] = nil
		lobbyChanged()
	end
	launch(members, id, mode)
	return true, "ok"
end

function Dungeons.host(player: Player, id: any, mode: any)
	if typeof(id) ~= "string" or not DD.List[id] or typeof(mode) ~= "string" or not DD.Modes[mode] then
		return false, "Pick a dungeon"
	end
	local ok, why = canGo(player, id, mode, true)
	if not ok then
		return false, why
	end
	local lob = lobbies[player]
	if lob then
		lob.id, lob.mode, lob.at = id, mode, now()
		lobbyChanged()
		return true, "Party set to " .. DD.List[id].Name .. " (" .. mode .. ")"
	end
	dropFromLobby(player)
	lobbies[player] = { id = id, mode = mode, members = { player }, at = now() }
	memberOf[player] = player
	lobbyChanged(player.DisplayName .. " opened a party for " .. DD.List[id].Name .. " (" .. mode .. ") at the Dungeon Gate", player)
	return true, "Party open: friends at the gate can join, then press Start"
end

function Dungeons.join(player: Player, leaderId: any)
	local leader = typeof(leaderId) == "number" and Players:GetPlayerByUserId(leaderId)
	local lob = leader and lobbies[leader]
	if not lob then
		return false, "That party is gone"
	end
	if memberOf[player] == leader then
		return true, "ok"
	end
	if #lob.members >= PARTY_MAX then
		return false, "That party is full"
	end
	local ok, why = canGo(player, lob.id, lob.mode, false)
	if not ok then
		return false, why
	end
	dropFromLobby(player)
	table.insert(lob.members, player)
	memberOf[player] = leader
	remotes.Toast:FireClient(leader, player.DisplayName .. " joined your party", "good")
	lobbyChanged()
	return true, "Joined " .. leader.DisplayName .. "'s party"
end

function Dungeons.leave(player: Player)
	local run = runs[player]
	if not run then
		if memberOf[player] then
			dropFromLobby(player)
			return true, "Left the party"
		end
		return false, "Not in a run"
	end
	if run.over then
		return true, "ok"
	end
	memberOut(player, run, "left", "You left the dungeon (no key used)")
	return true, "ok"
end

function Dungeons.kick(player: Player, userId: any)
	local lob = lobbies[player]
	local target = typeof(userId) == "number" and Players:GetPlayerByUserId(userId)
	if not lob or not target or target == player or memberOf[target] ~= player then
		return false, "Can't remove them"
	end
	dropFromLobby(target, "You were removed from the party")
	return true, "Removed " .. target.DisplayName
end

function Dungeons.handle(player: Player, action: any, a: any, b: any)
	if action == "info" then
		return Dungeons.info(player)
	elseif action == "start" then
		return Dungeons.start(player, a, b)
	elseif action == "host" then
		return Dungeons.host(player, a, b)
	elseif action == "join" then
		return Dungeons.join(player, a)
	elseif action == "kick" then
		return Dungeons.kick(player, a)
	elseif action == "leave" then
		return Dungeons.leave(player)
	end
	return false, "Unknown action"
end

function Dungeons.inRun(player: Player): boolean
	return runs[player] ~= nil
end

function Dungeons.init(r, combat)
	remotes = r
	Combat = combat
	folderRoot = Instance.new("Folder")
	folderRoot.Name = "DungeonArenas"
	folderRoot.Parent = workspace
	buildArena(1)
	local function watch(player: Player, char: Model)
		local hum = char:WaitForChild("Humanoid", 10) :: Humanoid?
		if hum then
			hum.Died:Connect(function()
				local run = runs[player]
				if run and table.find(run.members, player) then
					memberOut(player, run, "knocked", "Knocked out! You're out of the run (no key used)")
				end
			end)
		end
	end
	local function onPlayer(player: Player)
		player.CharacterAdded:Connect(function(char)
			watch(player, char)
		end)
		if player.Character then
			task.spawn(watch, player, player.Character)
		end
	end
	Players.PlayerAdded:Connect(onPlayer)
	for _, pl in Players:GetPlayers() do
		onPlayer(pl)
	end
	Players.PlayerRemoving:Connect(function(player)
		dropFromLobby(player)
		local run = runs[player]
		if run then
			local i = table.find(run.members, player)
			if i then
				table.remove(run.members, i)
			end
			runs[player] = nil
			if #run.members == 0 and not run.over then
				endRun(run)
			end
		end
	end)
	-- parties close when members wander off or the leader waits too long
	task.spawn(function()
		while true do
			task.wait(2)
			for leader, lob in lobbies do
				if not leader.Parent or not atGate(leader) or now() - lob.at > LOBBY_SECONDS then
					dropFromLobby(leader)
				else
					for _, m in table.clone(lob.members) do
						if m ~= leader and (not m.Parent or not atGate(m)) then
							dropFromLobby(m, "You left the Dungeon Gate, so you left the party")
						end
					end
				end
			end
		end
	end)
end

-- Debug (Studio): skip the current wave without rewards.
function Dungeons.debugSkip(player: Player): string
	local run = runs[player]
	if not run then
		return "no run"
	end
	clearUnits(run)
	return "skipped wave " .. run.wave
end
function Dungeons.debugState(player: Player): string
	local run = runs[player]
	if not run then
		local lob = lobbies[player]
		return lob and ("lobby " .. lob.id .. " " .. lob.mode .. " members " .. #lob.members) or "no run"
	end
	return string.format("%s %s wave %d left %d members %d arena %s over %s", run.id, run.mode, run.wave, living(run), #run.members, tostring(run.arena.centre), tostring(run.over))
end

return Dungeons

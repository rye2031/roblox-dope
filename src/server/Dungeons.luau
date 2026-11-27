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
	return true, "ok", { keys = keys, nextAt = nextAt, list = list, inRun = runs[player] ~= nil }
end

----------------------------------------------------------------------------------------------
-- runs

local function hrpOf(player: Player): BasePart?
	local c = player.Character
	return c and c:FindFirstChild("HumanoidRootPart") :: BasePart?
end

local function send(player: Player, msg)
	if player.Parent then
		remotes.DungeonRun:FireClient(player, msg)
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

local function finish(player: Player, run, result: string, why: string?)
	if run.over then
		return
	end
	run.over = true
	clearUnits(run)
	if result ~= "clear" then
		send(player, { kind = "fail", why = why or "The run ended" })
	end
	-- back to the Dungeon Gate after a moment (a cleared run waits for the player to read)
	task.delay(result == "clear" and 4 or 2.5, function()
		if runs[player] == run then
			runs[player] = nil
			run.arena.busy = false
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
	local first = (st.clears[key] or 0) == 0
	st.keys = math.max(0, st.keys - 1)
	if st.keys == DD.KeyCap - 1 then
		st.keyAt = now()
	end
	st.clears[key] = (st.clears[key] or 0) + 1
	local best = st.best[key]
	local newBest = best == nil or secs < best
	if newBest then
		st.best[key] = secs
	end
	local rewards = { runes = {}, time = secs, best = newBest, first = first }
	local lvTop = select(2, DD.levels(run.id, run.mode))
	rewards.coins = math.floor((200 + lvTop * 25) * m.coins)
	p.coins += rewards.coins
	local el = Config.pickWeighted(d.Elements, rng:NextNumber())
	rewards.el = el
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
	PlayerData.push(player)
	PlayerData.saveSoon(player)
	send(player, { kind = "clear", rewards = rewards, id = run.id, mode = run.mode })
	if Dungeons.onClear then
		Dungeons.onClear(player, run.id, run.mode)
	end
end

local function spawnWave(player: Player, run, w: number)
	local d, m = DD.List[run.id], DD.Modes[run.mode]
	local lo, hi = DD.levels(run.id, run.mode)
	local c = run.arena.centre
	local camps = {}
	local function camp(props)
		local base = { id = "dg" .. player.UserId .. "_" .. w .. "_" .. #camps, region = d.Region, radius = 8, lv = { lo, hi }, once = true, noElite = true, dungeon = run.id, elements = d.Elements, hpMult = m.hpMult }
		for k, v in props do
			base[k] = v
		end
		base.pos = Vector3.new(base.pos.X, c.Y, base.pos.Z)
		table.insert(camps, base)
		return base
	end
	if w <= #DD.WaveSizes then
		local n = DD.WaveSizes[w]
		-- far side of the arena, spread out
		camp({ pos = c + Vector3.new(0, 0, -24), count = math.ceil(n / 2), radius = 10 })
		camp({ pos = c + Vector3.new(w % 2 == 0 and 20 or -20, 0, -12), count = math.floor(n / 2), radius = 8 })
		if w == #DD.WaveSizes then
			camp({ pos = c + Vector3.new(0, 0, -30), count = 1, elite = true, hpMult = 3.5 * m.hpMult, stars = 4 })
		end
	else
		camp({ pos = c + Vector3.new(0, 0, -26), count = 1, boss = true, hpMult = m.bossHp, stars = 4, lv = { hi + 2, hi + 2 }, radius = 0 })
	end
	run.camps = camps
	for _, cp in camps do
		Combat.spawnWild(cp)
		Combat.aggroCamp(cp, player)
	end
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

local function loop(player: Player, run)
	local waves = #DD.WaveSizes
	spawnWave(player, run, 1)
	while not run.over and runs[player] == run do
		task.wait(0.4)
		if run.over or not player.Parent then
			break
		end
		if now() >= run.endsAt then
			finish(player, run, "time", "Time's up! The run ended (no key used)")
			break
		end
		-- keep their aggro on the player (a wiped team leaves them idle otherwise)
		for _, camp in run.camps do
			for _, u in Combat.campUnits(camp) do
				if not u.target then
					Combat.aggroCamp(camp, player)
					break
				end
			end
		end
		local left = living(run)
		if left ~= run.left then
			run.left = left
			send(player, { kind = "wave", wave = run.wave, of = waves, left = left, boss = run.wave > waves })
		end
		if left == 0 then
			if run.wave > waves then
				chest(player, run)
				finish(player, run, "clear")
				break
			end
			task.wait(2.5)
			if run.over then
				break
			end
			spawnWave(player, run, run.wave + 1)
		end
	end
end

function Dungeons.start(player: Player, id: any, mode: any)
	local p = PlayerData.get(player)
	if not p then
		return false, "No profile"
	end
	if typeof(id) ~= "string" or not DD.List[id] or typeof(mode) ~= "string" or not DD.Modes[mode] then
		return false, "Pick a dungeon"
	end
	if runs[player] then
		return false, "You're already in a run"
	end
	local ok, why = unlocked(p, id, mode)
	if not ok then
		return false, why
	end
	if DD.refill(state(p), now()) < 1 then
		return false, "No keys left: one comes back every " .. DD.KeyMinutes .. " minutes"
	end
	if Combat.inCombat(player) then
		return false, "Finish your fight first"
	end
	local hrp = hrpOf(player)
	if not hrp or (hrp.Position - World.Points.Dungeons).Magnitude > 40 then
		return false, "Stand at the Dungeon Gate in Haven"
	end
	if RuneBag.count(p) >= Runes.BagCap then
		return false, "Your rune bag is full: sell some runes first"
	end
	local arena = freeArena()
	arena.busy = true
	theme(arena, id)
	local run = { id = id, mode = mode, arena = arena, started = now(), endsAt = now() + DD.TimeLimit, camps = {}, wave = 0, over = false }
	runs[player] = run
	player:SetAttribute("Dungeon", id .. ":" .. mode)
	-- stand at the near edge, facing the far side where waves appear
	Combat.healTeam(player)
	local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if hum then
		hum.Health = hum.MaxHealth
	end
	moveTo(player, arena.centre + Vector3.new(0, 0, 26), Vector3.new(0, 0, -1))
	send(player, { kind = "start", id = id, mode = mode, endsAt = workspace:GetServerTimeNow() + DD.TimeLimit, waves = #DD.WaveSizes })
	task.delay(3, function()
		if runs[player] == run and not run.over then
			loop(player, run)
		end
	end)
	return true, "ok"
end

function Dungeons.leave(player: Player)
	local run = runs[player]
	if not run then
		return false, "Not in a run"
	end
	if run.over then
		return true, "ok"
	end
	finish(player, run, "left", "You left the dungeon (no key used)")
	return true, "ok"
end

function Dungeons.handle(player: Player, action: any, a: any, b: any)
	if action == "info" then
		return Dungeons.info(player)
	elseif action == "start" then
		return Dungeons.start(player, a, b)
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
				if run and not run.over then
					finish(player, run, "knocked", "Knocked out! The run ended (no key used)")
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
		local run = runs[player]
		if run then
			run.over = true
			clearUnits(run)
			run.arena.busy = false
			runs[player] = nil
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
		return "no run"
	end
	return string.format("%s %s wave %d left %d arena %s over %s", run.id, run.mode, run.wave, living(run), tostring(run.arena.centre), tostring(run.over))
end

return Dungeons

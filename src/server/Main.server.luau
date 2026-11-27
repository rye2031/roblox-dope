-- Wildbound server entry point: builds the world, wires remotes, and connects players to their
-- saved profile, team and combat.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")

local Config = require(ReplicatedStorage.Shared.Config)
local Monsters = require(ReplicatedStorage.Shared.Monsters)
local World = require(script.Parent.World)
local PlayerData = require(script.Parent.PlayerData)
local Inventory = require(script.Parent.Inventory)
local Summon = require(script.Parent.Summon)
local Story = require(script.Parent.Story)
local Loops = require(script.Parent.Loops)
local RuneBag = require(script.Parent.RuneBag)
local Dungeons = require(script.Parent.Dungeons)
local Arena = require(script.Parent.Arena)
local Quests = require(script.Parent.Quests)
local Combat = require(script.Parent.Combat)
local Leaderboard = require(script.Parent.Leaderboard)
local Regions = require(script.Parent.Regions)

local T = Config.Tuning

for _, name in { "Baseplate", "SpawnLocation", "Map" } do
	local old = workspace:FindFirstChild(name)
	if old then
		old:Destroy()
	end
end

-- Remotes
local remoteFolder = Instance.new("Folder")
remoteFolder.Name = "Remotes"
local remotes = {}
for _, n in { "Profile", "Toast", "Combat", "Reward", "Intent", "Fx", "Announce", "Story", "DungeonRun", "Portal" } do
	local r = Instance.new("RemoteEvent")
	r.Name = n
	r.Parent = remoteFolder
	remotes[n] = r
end
for _, n in { "GetProfile", "Summon", "SetTeam", "Lock", "Feed", "Awaken", "Sell", "BuyStorage", "SetWeapon", "UpgradeWeapon", "ClaimQuest", "ClaimStreak", "Tutorial", "Overflow", "Travel", "Expedition", "IndexReward", "Arena", "Sealed", "Runes", "Dungeon" } do
	local r = Instance.new("RemoteFunction")
	r.Name = n
	r.Parent = remoteFolder
	remotes[n] = r
end
remoteFolder.Parent = ReplicatedStorage

-- World
World.setupLighting()
Regions.register(World)
local worldFolder = World.build()
task.spawn(World.settle)
PlayerData.init(remotes.Profile)
Quests.init(remotes)
Summon.init(remotes)
Story.init(remotes)
Loops.init(remotes)
Arena.init()
Combat.init(remotes)
Dungeons.init(remotes, Combat)
Regions.init(remotes, Combat)
Leaderboard.init()

PlayerData.onPush = function(player: Player)
	task.defer(Combat.syncTeam, player)
	task.defer(Story.check, player)
	Regions.applyPass(player)
end

-- Panels
remotes.GetProfile.OnServerInvoke = function(player)
	return PlayerData.get(player)
end
remotes.Summon.OnServerInvoke = function(player, kind, count)
	return Summon.openMany(player, kind, count)
end
remotes.Sealed.OnServerInvoke = function(player, action, a)
	return Loops.sealed(player, action, a)
end
remotes.Dungeon.OnServerInvoke = function(player, action, a, b)
	return Dungeons.handle(player, action, a, b)
end
remotes.Runes.OnServerInvoke = function(player, action, a, b)
	return RuneBag.action(player, action, a, b)
end
remotes.Arena.OnServerInvoke = function(player, action, a, b)
	return Arena.handle(player, action, a, b)
end
remotes.Expedition.OnServerInvoke = function(player, action, slot, place, dur, uids)
	return Loops.expedition(player, action, slot, place, dur, uids)
end
remotes.IndexReward.OnServerInvoke = function(player, kind, key)
	return Loops.indexReward(player, kind, key)
end
remotes.Overflow.OnServerInvoke = function(player, action, key, uid)
	return Inventory.overflow(player, action, key, uid)
end
remotes.SetTeam.OnServerInvoke = function(player, slot, uid)
	return Inventory.setTeam(player, slot, uid)
end
remotes.Lock.OnServerInvoke = function(player, uid, on)
	return Inventory.setLock(player, uid, on)
end
remotes.Feed.OnServerInvoke = function(player, target, foods)
	local ok, msg = Inventory.feed(player, target, foods)
	if ok then
		Combat.refreshTeamStats(player)
	end
	return ok, msg
end
remotes.Awaken.OnServerInvoke = function(player, uid)
	local ok, msg = Inventory.awaken(player, uid)
	if ok then
		Combat.refreshTeamStats(player)
	end
	return ok, msg
end
remotes.Sell.OnServerInvoke = function(player, uids)
	return Inventory.sell(player, uids)
end
remotes.BuyStorage.OnServerInvoke = function(player)
	return Inventory.buyStorage(player)
end
remotes.SetWeapon.OnServerInvoke = function(player, kind)
	return Inventory.setWeapon(player, kind)
end
remotes.UpgradeWeapon.OnServerInvoke = function(player)
	local ok, msg = Inventory.upgradeWeapon(player)
	if ok then
		Combat.refreshTeamStats(player)
	end
	return ok, msg
end
remotes.ClaimQuest.OnServerInvoke = function(player, index)
	return Quests.claim(player, index)
end
remotes.ClaimStreak.OnServerInvoke = function(player)
	return Quests.claimStreak(player)
end
remotes.Tutorial.OnServerInvoke = function(player, flag)
	local p = PlayerData.get(player)
	if p and typeof(flag) == "string" and #flag < 24 then
		p.tutorial[flag] = true
		PlayerData.push(player)
	end
	return true
end

-- Combat intents (fire-and-forget; the server validates everything)
remotes.Intent.OnServerEvent:Connect(function(player, kind, a)
	if kind == "attack" then
		Combat.attack(player, a)
	elseif kind == "wskill" then
		Combat.weaponSkill(player, a)
	elseif kind == "dodge" then
		Combat.dodge(player)
	elseif kind == "team" then
		Combat.teamSkill(player, a)
	elseif kind == "focus" then
		Combat.focus(player, a)
	elseif kind == "auto" then
		local p = PlayerData.get(player)
		local allowed = p and p.bosses[Config.AutoHunt.UnlockBoss] == true
		player:SetAttribute("AutoHunt", a == true and allowed or false)
	end
end)

-- Campfires: touching one heals your team and makes it your respawn point.
local lastCamp = {}
for _, c in World.Campfires do
	c.part.Touched:Connect(function(hit)
		local char = hit:FindFirstAncestorOfClass("Model")
		local player = char and Players:GetPlayerFromCharacter(char)
		if not player then
			return
		end
		local key = player.UserId .. c.region
		if lastCamp[key] and os.clock() - lastCamp[key] < 4 then
			return
		end
		lastCamp[key] = os.clock()
		if player.RespawnLocation ~= c.part then
			player.RespawnLocation = c.part
			local p = PlayerData.get(player)
			local first = p and not p.campfires[c.region]
			remotes.Toast:FireClient(player, first and "Campfire lit: you'll respawn here, and you can travel back to it" or "Campfire: you'll respawn here", "info")
		end
		Story.event(player, "campfire", { region = c.region })
		Combat.healTeam(player)
		local hum = char:FindFirstChildOfClass("Humanoid")
		if hum then
			hum.Health = hum.MaxHealth
		end
	end)
end

-- Story guides
for id, prompt in World.Guides do
	prompt.Triggered:Connect(function(player)
		Story.talk(player, id)
	end)
end

-- Fast travel between lit campfires (from next to any campfire, out of combat).
local lastTravel: { [Player]: number } = {}
remotes.Travel.OnServerInvoke = function(player, region)
	local p = PlayerData.get(player)
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not p or not hrp or typeof(region) ~= "string" then
		return false, "Can't travel right now"
	end
	if Dungeons.inRun(player) then
		return false, "Leave the dungeon first"
	end
	if not p.campfires[region] then
		return false, "Light that campfire first"
	end
	if Combat.inCombat(player) then
		return false, "You can't travel during a fight"
	end
	if os.clock() - (lastTravel[player] or 0) < 6 then
		return false, "Catch your breath first"
	end
	local near, dest = false, nil
	for _, c in World.Campfires do
		if (c.pos - hrp.Position).Magnitude < 16 then
			near = true
		end
		if c.region == region then
			dest = c
		end
	end
	if not near then
		return false, "Stand next to a campfire to travel"
	end
	if not dest then
		return false, "Unknown campfire"
	end
	lastTravel[player] = os.clock()
	local to = dest.pos + Vector3.new(0, 4, -6)
	char:PivotTo(CFrame.lookAt(to, dest.pos + Vector3.new(0, 4, 0)))
	player.RespawnLocation = dest.part
	Combat.warpTeam(player, dest.pos + Vector3.new(0, 0, -6))
	Combat.healTeam(player)
	return true, "Travelled to the " .. (World.Regions[region] and World.Regions[region].Name or region) .. " campfire"
end

local function onCharacter(player: Player, char: Model)
	local hum = char:WaitForChild("Humanoid") :: Humanoid
	local p = PlayerData.get(player)
	if p then
		local max = Config.tamerStats(p.weapon.lv).hp
		hum.MaxHealth = max
		hum.Health = max
	end
	hum.WalkSpeed = 20
	task.defer(function()
		Combat.healTeam(player)
		Combat.syncTeam(player)
	end)
	hum.Died:Connect(function()
		remotes.Toast:FireClient(player, "You were knocked out! Back to your last campfire", "alert")
	end)
end

local function onPlayer(player: Player)
	player.DevEnableMouseLock = false -- Shift is the dodge key
	player.CharacterAdded:Connect(function(char)
		onCharacter(player, char)
	end)
	if player.Character then
		task.spawn(onCharacter, player, player.Character)
	end
	task.spawn(function()
		if PlayerData.join(player) then
			Quests.ensure(player)
			PlayerData.push(player)
			local mode = player:GetAttribute("SaveMode")
			if mode == "Session" then
				remotes.Toast:FireClient(player, "Saving is off here: progress resets when you leave", "warn")
			elseif mode == "Failed" then
				remotes.Toast:FireClient(player, "Couldn't load your save. This session won't be saved, so rejoin later", "alert")
			end
		end
	end)
end

Players.PlayerAdded:Connect(onPlayer)
for _, p in Players:GetPlayers() do
	onPlayer(p)
end
Players.PlayerRemoving:Connect(function(player)
	Leaderboard.onLeave(player)
	PlayerData.leave(player)
end)

----------------------------------------------------------------------------------------------
-- Debug bridge for Studio MCP playtests (execute_luau runs in a separate Lua state).
if game:GetService("RunService"):IsStudio() then
	local bf = Instance.new("BindableFunction")
	bf.Name = "WildDebug"
	local function plr(name)
		return (name and Players:FindFirstChild(name)) or Players:GetPlayers()[1]
	end
	local function vec(v)
		return v and { math.floor(v.X * 10) / 10, math.floor(v.Y * 10) / 10, math.floor(v.Z * 10) / 10 }
	end
	bf.OnInvoke = function(cmd, a, b, c, d)
		local player = plr(nil)
		local p = player and PlayerData.get(player)
		if cmd == "state" then
			local out = { units = {}, profile = nil }
			for id, u in Combat.debug.units do
				out.units[id] = { side = u.side, sp = u.sp, el = u.el, lv = u.lv, hp = math.floor(u.hp), max = math.floor(u.maxHp), st = u.state, pos = vec(u.pos), tgt = u.target and (u.target.id or u.target.key) or nil, camp = u.camp and u.camp.id, elite = u.elite, boss = u.boss, slot = u.slot, atk = u.stats and u.stats.atk, crit = u.stats and u.stats.crit }
			end
			if p then
				local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
				local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
				out.player = { pos = hrp and vec(hrp.Position), hp = hum and math.floor(hum.Health), maxHp = hum and hum.MaxHealth }
				out.profile = { coins = p.coins, team = p.team, scrolls = p.scrolls, pity = p.pity, essence = p.essence, weapon = p.weapon, kills = p.kills, count = Inventory.count(p), monsters = p.monsters, bosses = p.bosses, regions = p.regions, index = PlayerData.indexCount(p) }
			end
			return HttpService:JSONEncode(out)
		elseif cmd == "give" then
			-- give species a, element b, level c
			local uid = Inventory.addMonster(p, a, b or "Fire", true)
			if c then
				p.monsters[uid].lv = c
			end
			PlayerData.push(player)
			return uid
		elseif cmd == "expfast" then
			for _, x in p.expeditions do
				x.start -= 12 * 3600
			end
			PlayerData.push(player)
			return HttpService:JSONEncode(p.expeditions)
		elseif cmd == "talk" then
			Story.talk(player, a)
			return HttpService:JSONEncode(p.story)
		elseif cmd == "story" then
			if a then
				p.story = { i = a, n = 0 }
				PlayerData.push(player)
			end
			return HttpService:JSONEncode({ story = p.story, campfires = p.campfires })
		elseif cmd == "storagecap" then
			p.storageCap = a
			PlayerData.push(player)
			return "ok"
		elseif cmd == "overflow" then
			return HttpService:JSONEncode(p.overflow)
		elseif cmd == "scrolls" then
			p.scrolls.Regular += a or 0
			p.scrolls.Legendary += b or 0
			PlayerData.push(player)
			return "ok"
		elseif cmd == "coins" then
			p.coins += a
			PlayerData.push(player)
			return tostring(p.coins)
		elseif cmd == "essence" then
			p.essence[a] += b
			PlayerData.push(player)
			return "ok"
		elseif cmd == "odds" then
			return HttpService:JSONEncode(Summon.debugOdds(a or "Regular", b or 100000))
		elseif cmd == "summon" then
			local ok, msg, res = Summon.openMany(player, a, b)
			return HttpService:JSONEncode({ ok = ok, msg = msg, res = res })
		elseif cmd == "team" then
			return table.concat({ tostring(Inventory.setTeam(player, a, b)) }, " ")
		elseif cmd == "tp" then
			player.Character:PivotTo(CFrame.new(a))
			return "ok"
		elseif cmd == "attack" then
			Combat.attack(player, a)
			return "ok"
		elseif cmd == "wskill" then
			Combat.weaponSkill(player, a)
			return "ok"
		elseif cmd == "teamskill" then
			return tostring(Combat.teamSkill(player, a))
		elseif cmd == "focus" then
			Combat.focus(player, a)
			return "ok"
		elseif cmd == "hurt" then
			Combat.debug.damage(a, b)
			return "ok"
		elseif cmd == "weapon" then
			return table.concat({ tostring(Inventory.setWeapon(player, a)) }, " ")
		elseif cmd == "feed" then
			local ok, msg = Inventory.feed(player, a, b)
			return tostring(ok) .. " " .. msg
		elseif cmd == "awaken" then
			local ok, msg = Inventory.awaken(player, a)
			return tostring(ok) .. " " .. msg
		elseif cmd == "upgrade" then
			local ok, msg = Inventory.upgradeWeapon(player)
			return tostring(ok) .. " " .. msg
		elseif cmd == "setlevel" then
			p.monsters[a].lv = b
			PlayerData.push(player)
			Combat.refreshTeamStats(player)
			return "ok"
		elseif cmd == "replace" then
			PlayerData.debugReplace(player, a and HttpService:JSONDecode(a) or nil)
			return "ok"
		elseif cmd == "boss" then
			return tostring(Regions.debugSpawnBoss(a))
		elseif cmd == "unlock" then
			p.bosses[a] = true
			Regions.refreshRegions(player)
			PlayerData.push(player)
			return "ok"
		elseif cmd == "seal" then
			p.sealed.bag[a] = (p.sealed.bag[a] or 0) + (b or 1)
			PlayerData.push(player)
			return "ok"
		elseif cmd == "rune" then
			-- rune <rarity> [n] | rune perfect <stat> | rune drop <kind> [n] | rune list
			if a == "list" then
				local HttpService = game:GetService("HttpService")
				return HttpService:JSONEncode(p.runes)
			elseif a == "perfect" then
				local id = "r" .. p.nextRune
				p.nextRune += 1
				local s = b or "atk"
				p.runes[id] = { r = "Legendary", rolls = { { s = s, t = 4 }, { s = s, t = 4 }, { s = s, t = 4 }, { s = s, t = 4 } }, rf = 0 }
				PlayerData.push(player)
				return id
			elseif a == "drop" then
				local got = {}
				for _ = 1, b or 1 do
					local r = RuneBag.rollDrop(p, c or "boss")
					if r then
						got[r] = (got[r] or 0) + 1
					end
				end
				PlayerData.push(player)
				return game:GetService("HttpService"):JSONEncode(got)
			end
			for _ = 1, b or 1 do
				RuneBag.give(p, a or "Rare")
			end
			PlayerData.push(player)
			return "ok"
		elseif cmd == "dungeon" then
			-- dungeon start <id> <mode> | skip | state | leave | keys <n> | open (beat every boss)
			if a == "start" then
				local ok, msg = Dungeons.start(player, b, c or "Normal")
				return tostring(ok) .. " " .. tostring(msg)
			elseif a == "skip" then
				return Dungeons.debugSkip(player)
			elseif a == "host" then
				local ok, msg = Dungeons.host(player, b, c or "Normal")
				return tostring(ok) .. " " .. tostring(msg)
			elseif a == "partystart" then
				local ok, msg = Dungeons.start(player)
				return tostring(ok) .. " " .. tostring(msg)
			elseif a == "scale" then
				local sc = Dungeons.scale(b or 1)
				return string.format("count x%.2f hp x%.2f boss x%.2f", sc.count, sc.hp, sc.boss)
			elseif a == "leave" then
				return tostring((Dungeons.leave(player)))
			elseif a == "keys" then
				p.dungeon.keys = b or 5
				PlayerData.push(player)
				return "ok"
			elseif a == "info" then
				local _, _, data = Dungeons.info(player)
				return HttpService:JSONEncode(data)
			end
			return Dungeons.debugState(player)
		elseif cmd == "runeact" then
			local ok, msg = RuneBag.action(player, a, b, c)
			return tostring(ok) .. " " .. tostring(msg)
		elseif cmd == "sealfast" then
			for _, sl in p.sealed.slots do
				sl.start -= 2 * 3600
			end
			PlayerData.push(player)
			return "ok"
		elseif cmd == "legend" then
			return tostring(Regions.spawnLegend(a))
		elseif cmd == "relock" then
			p.regions[a] = nil -- until the next push re-checks it (Studio test of locked portals)
			return "ok"
		elseif cmd == "unitstats" then
			local u = a == "tamer" and Combat.debug.tamerOf(player) or Combat.debug.units[a]
			if not u then
				return "none"
			end
			local fx = {}
			for _, e in u.effects or {} do
				table.insert(fx, { type = e.type, stat = e.stat, value = e.value, pct = e.pct, left = e.untilT and math.floor((e.untilT - os.clock()) * 10) / 10 })
			end
			return HttpService:JSONEncode({ stats = u.stats, fx = fx, lv = u.lv, el = u.el })
		elseif cmd == "worldboss" then
			return tostring(Regions.debugWorldBoss())
		end
		return "unknown"
	end
	bf.Parent = game:GetService("ServerStorage")
end

print(`[server] {Config.GameName} started`)

-- Player progress for Wildbound: loaded from / saved to a DataStore through Persistence
-- (session-locked), with a session-only fallback when DataStores are unavailable.
-- Gameplay changes go through Inventory / Summon / Quests, which call push() + saveSoon().
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Monsters = require(Shared.Monsters)
local Persistence = require(script.Parent.Persistence)

local T = Config.Tuning
local PlayerData = {}

export type Monster = { sp: string, el: string, lv: number, xp: number, aw: boolean, sk: { number }, lock: boolean, got: number }
export type Profile = {
	coins: number,
	monsters: { [string]: Monster },
	nextUid: number,
	team: { string }, -- 3 slots, "" = empty
	storageCap: number,
	overflow: { [string]: number }, -- "<species>:<element>" -> count, summons that arrived while storage was full
	scrolls: { Regular: number, Legendary: number },
	pity: { four: number, ld: number },
	essence: { [string]: number },
	weapon: { type: string, lv: number },
	index: { [string]: boolean }, -- "<species>:<element>"
	kills: number,
	opened: number,
	regions: { [string]: boolean }, -- unlocked regions
	bosses: { [string]: boolean }, -- region bosses beaten
	daily: { day: number, quests: { any }, bonus: boolean },
	streak: { last: number, count: number },
	tutorial: { [string]: boolean },
	story: { i: number, n: number }, -- Tamer's Journey step index + progress
	campfires: { [string]: boolean }, -- lit campfires (fast travel)
	expeditions: { [string]: any }, -- slot "1".."3" -> { place, dur, start, uids, reward }
	indexClaims: { m: { [string]: boolean }, s: { [string]: boolean } }, -- Index milestones / complete species claimed
	arena: { tokens: number, day: number, attacks: number }, -- Arena tokens and today's fights (rating lives in the Arena store)
	lastSeen: number,
}

type Meta = { cloud: boolean, dirty: boolean, saveQueued: boolean, leaving: boolean }

local profiles: { [Player]: Profile } = {}
local meta: { [Player]: Meta } = {}
local remote: RemoteEvent
local activeSaves = 0

local function defaults(): Profile
	local essence = {}
	for _, e in Config.Elements do
		essence[e] = 0
	end
	return {
		coins = 0,
		monsters = {},
		nextUid = 1,
		team = { "", "", "" },
		storageCap = T.StartStorage,
		overflow = {},
		scrolls = { Regular = T.Scrolls.Start.Regular, Legendary = T.Scrolls.Start.Legendary, Eclipse = 0 },
		pity = { four = 0, ld = 0 },
		essence = essence,
		weapon = { type = "Blade", lv = 1 },
		index = {},
		kills = 0,
		opened = 0,
		regions = { SproutMeadow = true },
		bosses = {},
		daily = { day = 0, quests = {}, bonus = false },
		streak = { last = 0, count = 0 },
		tutorial = {},
		story = { i = 1, n = 0 },
		campfires = { Haven = true },
		expeditions = {},
		indexClaims = { m = {}, s = {} },
		arena = { tokens = 0, day = 0, attacks = 0 },
		lastSeen = 0,
	}
end

local function int(v: any, min: number): number
	if typeof(v) ~= "number" or v ~= v or v == math.huge or v == -math.huge then
		return min
	end
	return math.max(min, math.floor(v))
end

local function validElement(e: any): boolean
	return typeof(e) == "string" and Config.ElementInfo[e] ~= nil
end

-- Turn whatever came out of the DataStore into a valid profile (unknown species, bad numbers
-- and dangling team slots are dropped), so a bad or old record can't break the game.
function PlayerData.sanitize(raw: any): Profile
	local p = defaults()
	if typeof(raw) ~= "table" then
		return p
	end
	-- A brand-new record keeps the starter scrolls; an existing one uses what it saved.
	p.coins = int(raw.coins, 0)
	p.nextUid = int(raw.nextUid, 1)
	if typeof(raw.monsters) == "table" then
		for uid, m in raw.monsters do
			if typeof(uid) == "string" and typeof(m) == "table" and Monsters.Species[m.sp] and validElement(m.el) then
				local aw = m.aw == true
				local cap = aw and T.MaxLevel or T.AwakenLevel
				local skl = {}
				for i = 1, 3 do
					skl[i] = math.clamp(int(typeof(m.sk) == "table" and m.sk[i] or 1, 1), 1, Config.Tuning.Feed.MaxSkillLevel)
				end
				p.monsters[uid] = {
					sp = m.sp,
					el = m.el,
					lv = math.clamp(int(m.lv, 1), 1, cap),
					xp = int(m.xp, 0),
					aw = aw,
					sk = skl,
					lock = m.lock == true,
					got = int(m.got, 0),
				}
				local n = tonumber(string.match(uid, "%d+"))
				if n and n >= p.nextUid then
					p.nextUid = n + 1
				end
			end
		end
	end
	if typeof(raw.team) == "table" then
		local seen = {}
		for i = 1, T.TeamSize do
			local uid = raw.team[i]
			if typeof(uid) == "string" and p.monsters[uid] and not seen[uid] then
				p.team[i] = uid
				seen[uid] = true
			end
		end
	end
	p.storageCap = math.max(T.StartStorage, int(raw.storageCap, T.StartStorage))
	if typeof(raw.overflow) == "table" then
		local total = 0
		for k, v in raw.overflow do
			local sp, el = string.match(tostring(k), "^(%w+):(%w+)$")
			local n = math.min(int(v, 0), T.OverflowCap - total)
			if sp and Monsters.Species[sp] and validElement(el) and n > 0 then
				p.overflow[k] = n
				total += n
			end
		end
	end
	if typeof(raw.scrolls) == "table" then
		p.scrolls = { Regular = int(raw.scrolls.Regular, 0), Legendary = int(raw.scrolls.Legendary, 0), Eclipse = math.min(1, int(raw.scrolls.Eclipse, 0)) }
	end
	if typeof(raw.pity) == "table" then
		p.pity = { four = int(raw.pity.four, 0), ld = int(raw.pity.ld, 0) }
	end
	if typeof(raw.essence) == "table" then
		for _, e in Config.Elements do
			p.essence[e] = int(raw.essence[e], 0)
		end
	end
	if typeof(raw.weapon) == "table" then
		p.weapon = {
			type = T.Weapons[raw.weapon.type] and raw.weapon.type or "Blade",
			lv = math.clamp(int(raw.weapon.lv, 1), 1, T.Tamer.MaxWeaponLevel),
		}
	end
	if typeof(raw.index) == "table" then
		for k, v in raw.index do
			local sp, el = string.match(tostring(k), "^(%w+):(%w+)$")
			if v == true and sp and Monsters.Species[sp] and validElement(el) then
				p.index[k] = true
			end
		end
	end
	p.kills = int(raw.kills, 0)
	p.opened = int(raw.opened, 0)
	if typeof(raw.expeditions) == "table" then
		local E = Config.Loops.Expeditions
		local used = {}
		for slot, x in raw.expeditions do
			local n = tonumber(slot)
			if n and n >= 1 and n <= E.Slots and typeof(x) == "table" and E.Places[x.place] and E.Durations[x.dur] and typeof(x.uids) == "table" and typeof(x.reward) == "table" then
				local uids = {}
				for _, u in x.uids do
					if typeof(u) == "string" and p.monsters[u] and not used[u] and #uids < E.MaxMonsters then
						used[u] = true
						table.insert(uids, u)
					end
				end
				if #uids > 0 then
					local r = x.reward
					p.expeditions[tostring(n)] = { place = x.place, dur = x.dur, start = int(x.start, 0), uids = uids, reward = {
						coins = int(r.coins, 0), essence = int(r.essence, 0), element = validElement(r.element) and r.element or nil,
						scrolls = int(r.scrolls, 0), scrollChance = typeof(r.scrollChance) == "number" and math.clamp(r.scrollChance, 0, 1) or 0, xp = int(r.xp, 0),
					} }
				end
			end
		end
	end
	if typeof(raw.arena) == "table" then
		p.arena = { tokens = int(raw.arena.tokens, 0), day = int(raw.arena.day, 0), attacks = int(raw.arena.attacks, 0) }
	end
	if typeof(raw.indexClaims) == "table" then
		for _, k in { "m", "s" } do
			if typeof(raw.indexClaims[k]) == "table" then
				for key, v in raw.indexClaims[k] do
					if typeof(key) == "string" and v == true then
						p.indexClaims[k][key] = true
					end
				end
			end
		end
	end
	if typeof(raw.story) == "table" then
		p.story = { i = math.max(1, int(raw.story.i, 1)), n = int(raw.story.n, 0) }
	end
	for _, key in { "regions", "bosses", "tutorial", "campfires" } do
		if typeof(raw[key]) == "table" then
			for k, v in raw[key] do
				if typeof(k) == "string" and v == true then
					p[key][k] = true
				end
			end
		end
	end
	p.regions.SproutMeadow = true
	if typeof(raw.streak) == "table" then
		p.streak = { last = int(raw.streak.last, 0), count = int(raw.streak.count, 0) }
	end
	if typeof(raw.daily) == "table" and typeof(raw.daily.quests) == "table" then
		local quests = {}
		for _, q in raw.daily.quests do
			if typeof(q) == "table" and typeof(q.k) == "string" and Config.questDef(q.k) and #quests < 3 then
				local n = math.max(1, int(q.n, 1))
				table.insert(quests, { k = q.k, n = n, p = math.min(n, int(q.p, 0)), t = math.clamp(int(q.t, 1), 1, 3), c = q.c == true })
			end
		end
		p.daily = { day = int(raw.daily.day, 0), quests = quests, bonus = raw.daily.bonus == true }
	end
	p.lastSeen = int(raw.lastSeen, 0)
	return p
end

-- Plain deep copy for the DataStore.
local function copy(v)
	if typeof(v) ~= "table" then
		return v
	end
	local out = {}
	for k, x in v do
		out[k] = copy(x)
	end
	return out
end

function PlayerData.serialize(p: Profile)
	local out = copy(p)
	out.lastSeen = os.time()
	return out
end

local function setSaveStatus(player: Player, mode: string)
	player:SetAttribute("SaveMode", mode) -- Loading | Cloud | Session | Failed | Retrying
	if mode == "Cloud" then
		player:SetAttribute("LastSave", workspace:GetServerTimeNow())
	end
end

local function saveNow(player: Player, release: boolean?): boolean
	local p, m = profiles[player], meta[player]
	if not p or not m or not m.cloud then
		return false
	end
	activeSaves += 1
	m.dirty = false
	local ok = Persistence.save(player.UserId, PlayerData.serialize(p), release)
	activeSaves -= 1
	if ok then
		if player.Parent then
			setSaveStatus(player, "Cloud")
		end
	else
		m.dirty = true
		if player.Parent then
			player:SetAttribute("SaveMode", "Retrying")
		end
	end
	return ok
end

-- Save soon after an important change; coalesces bursts.
function PlayerData.saveSoon(player: Player)
	local m = meta[player]
	if not m or not m.cloud or m.saveQueued then
		return
	end
	m.saveQueued = true
	task.delay(3, function()
		m.saveQueued = false
		if profiles[player] and not m.leaving then
			saveNow(player)
		end
	end)
end

function PlayerData.init(profileRemote: RemoteEvent)
	remote = profileRemote
	Persistence.init()
	task.spawn(function()
		while true do
			task.wait(Persistence.AUTOSAVE_INTERVAL)
			for player, m in meta do
				if m.cloud and m.dirty and not m.leaving then
					task.spawn(saveNow, player)
				end
			end
		end
	end)
	game:BindToClose(function()
		for _, player in Players:GetPlayers() do
			task.spawn(PlayerData.leave, player)
		end
		local deadline = os.clock() + 25
		task.wait(0.1)
		while activeSaves > 0 and os.clock() < deadline do
			task.wait(0.2)
		end
	end)
end

local function makeLeaderstats(player: Player)
	local old = player:FindFirstChild("leaderstats")
	if old then
		old:Destroy()
	end
	local ls = Instance.new("Folder")
	ls.Name = "leaderstats"
	for _, n in { "Coins", "Index", "Defeated" } do
		local v = Instance.new("IntValue")
		v.Name = n
		v.Parent = ls
	end
	ls.Parent = player
end

function PlayerData.join(player: Player): Profile?
	setSaveStatus(player, "Loading")
	local cloud = false
	local data = nil
	if Persistence.available then
		local ok, loaded = Persistence.load(player.UserId)
		cloud = ok
		data = loaded
		if not ok then
			setSaveStatus(player, "Failed")
		end
	end
	if not player.Parent then
		if cloud then
			Persistence.release(player.UserId)
		end
		return nil
	end
	local p = PlayerData.sanitize(data)
	profiles[player] = p
	meta[player] = { cloud = cloud, dirty = data == nil, saveQueued = false, leaving = false }
	makeLeaderstats(player)
	if cloud then
		setSaveStatus(player, "Cloud")
	elseif player:GetAttribute("SaveMode") ~= "Failed" then
		setSaveStatus(player, "Session")
	end
	return p
end

function PlayerData.leave(player: Player)
	local m = meta[player]
	if not m or m.leaving then
		return
	end
	m.leaving = true
	if m.cloud then
		saveNow(player, true)
	end
	profiles[player] = nil
	meta[player] = nil
end

function PlayerData.get(player: Player): Profile?
	return profiles[player]
end

function PlayerData.isCloud(player: Player): boolean
	local m = meta[player]
	return m ~= nil and m.cloud
end

function PlayerData.indexCount(p: Profile): number
	local n = 0
	for _ in p.index do
		n += 1
	end
	return n
end

-- Optional hook (set by Main): called after every push, e.g. to refresh the team in the world.
PlayerData.onPush = nil :: ((Player) -> ())?

-- Send the profile to the client and refresh replicated attributes.
function PlayerData.push(player: Player)
	local p = profiles[player]
	if not p then
		return
	end
	local m = meta[player]
	if m then
		m.dirty = true
	end
	local ls = player:FindFirstChild("leaderstats")
	if ls then
		ls.Coins.Value = p.coins
		ls.Index.Value = PlayerData.indexCount(p)
		ls.Defeated.Value = p.kills
	end
	player:SetAttribute("Weapon", p.weapon.type)
	player:SetAttribute("WeaponLevel", p.weapon.lv)
	if PlayerData.onPush then
		PlayerData.onPush(player)
	end
	remote:FireClient(player, p)
end

-- Debug: replace a profile wholesale (Studio tests).
function PlayerData.debugReplace(player: Player, raw: any)
	profiles[player] = PlayerData.sanitize(raw)
	PlayerData.push(player)
end

return PlayerData

-- Everything that changes a player's monsters, team, storage and weapon. All validation lives
-- here; remotes in Main call these and pass the (ok, message) result back to the client.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Monsters = require(Shared.Monsters)
local PlayerData = require(script.Parent.PlayerData)
local Quests = require(script.Parent.Quests)

local T = Config.Tuning
local Inventory = {}

local function count(p): number
	local n = 0
	for _ in p.monsters do
		n += 1
	end
	return n
end
Inventory.count = count

local function inTeam(p, uid: string): number?
	for i, u in p.team do
		if u == uid then
			return i
		end
	end
	return nil
end
Inventory.inTeam = inTeam

-- Adds a level-1 monster (no push). Returns its uid, or nil if storage is full.
function Inventory.addMonster(p, sp: string, el: string, ignoreCap: boolean?): string?
	if not ignoreCap and count(p) >= p.storageCap then
		return nil
	end
	local uid = "m" .. p.nextUid
	p.nextUid += 1
	p.monsters[uid] = { sp = sp, el = el, lv = 1, xp = 0, aw = false, sk = { 1, 1, 1 }, lock = false, got = os.time() }
	p.index[sp .. ":" .. el] = true
	-- the first monsters you get fill your team
	for i = 1, T.TeamSize do
		if p.team[i] == "" then
			p.team[i] = uid
			break
		end
	end
	return uid
end

-- XP for one monster; returns levels gained. Un-awakened monsters stop at the awaken level.
function Inventory.grantXp(p, uid: string, xp: number): number
	local m = p.monsters[uid]
	if not m then
		return 0
	end
	local cap = m.aw and T.MaxLevel or T.AwakenLevel
	local gained = 0
	m.xp += xp
	while m.lv < cap and m.xp >= T.XpToNext(m.lv) do
		m.xp -= T.XpToNext(m.lv)
		m.lv += 1
		gained += 1
	end
	if m.lv >= cap then
		m.xp = math.min(m.xp, T.XpToNext(m.lv))
	end
	return gained
end

function Inventory.setTeam(player: Player, slot: any, uid: any): (boolean, string)
	local p = PlayerData.get(player)
	if not p or typeof(slot) ~= "number" or slot % 1 ~= 0 or slot < 1 or slot > T.TeamSize then
		return false, "No such team slot"
	end
	if uid == nil or uid == "" then
		p.team[slot] = ""
		PlayerData.push(player)
		return true, "Removed from your team"
	end
	if typeof(uid) ~= "string" or not p.monsters[uid] then
		return false, "You don't have that monster"
	end
	local other = inTeam(p, uid)
	if other then
		p.team[other] = p.team[slot] -- swap
	end
	p.team[slot] = uid
	PlayerData.push(player)
	PlayerData.saveSoon(player)
	return true, `{Monsters.Species[p.monsters[uid].sp].Name} joined your team`
end

function Inventory.setLock(player: Player, uid: any, on: any): (boolean, string)
	local p = PlayerData.get(player)
	local m = p and typeof(uid) == "string" and p.monsters[uid]
	if not m then
		return false, "You don't have that monster"
	end
	m.lock = on == true
	PlayerData.push(player)
	return true, m.lock and "Locked: it won't be fed or sold" or "Unlocked"
end

local function canConsume(p, uid: string, target: string?): (boolean, string?)
	local m = p.monsters[uid]
	if not m then
		return false, "missing"
	end
	if uid == target then
		return false, "can't feed a monster to itself"
	end
	if m.lock then
		return false, "it's locked"
	end
	if inTeam(p, uid) then
		return false, "it's on your team"
	end
	return true
end

----------------------------------------------------------------------------------------------
-- Overflow: summons that arrive while storage is full wait here, grouped by species + element
-- (they're all fresh Lv 1, so duplicates are identical). Take one into storage, swap one in for
-- a stored monster (which is sold), or sell them.

function Inventory.overflowCount(p): number
	local n = 0
	for _, c in p.overflow do
		n += c
	end
	return n
end

function Inventory.overflowAdd(p, sp: string, el: string): boolean
	if Inventory.overflowCount(p) >= T.OverflowCap then
		return false
	end
	local key = sp .. ":" .. el
	p.overflow[key] = (p.overflow[key] or 0) + 1
	p.index[key] = true
	return true
end

local function takeOne(p, key: string): (string?, string?)
	local sp, el = string.match(key, "^(%w+):(%w+)$")
	if not sp or not el then
		return nil, nil
	end
	p.overflow[key] -= 1
	if p.overflow[key] <= 0 then
		p.overflow[key] = nil
	end
	return sp, el
end

function Inventory.overflow(player: Player, action: any, key: any, uid: any): (boolean, string)
	local p = PlayerData.get(player)
	if not p then
		return false, "No profile"
	end
	local function done(msg: string): (boolean, string)
		PlayerData.push(player)
		PlayerData.saveSoon(player)
		return true, msg
	end
	if action == "sellall" then
		local total, n = 0, 0
		for k, c in p.overflow do
			local sp = string.match(k, "^(%w+):")
			total += Config.sellValue(Monsters.Species[sp].Stars, 1) * c
			n += c
		end
		if n == 0 then
			return false, "Overflow is empty"
		end
		p.overflow = {}
		p.coins += total
		return done(`Sold {n} overflow monsters for {total} coins`)
	end
	if typeof(key) ~= "string" or not p.overflow[key] then
		return false, "That group is gone"
	end
	local sp0 = string.match(key, "^(%w+):")
	local name = Monsters.Species[sp0].Name
	if action == "take" then
		if count(p) >= p.storageCap then
			return false, "Storage is full: swap, sell or buy more storage"
		end
		local sp, el = takeOne(p, key)
		Inventory.addMonster(p, sp :: string, el :: string)
		return done(`{name} moved into storage`)
	elseif action == "swap" then
		if typeof(uid) ~= "string" then
			return false, "Pick a monster to swap out"
		end
		local ok, why = canConsume(p, uid, nil)
		if not ok then
			return false, `Can't swap that one: {why}`
		end
		local old = p.monsters[uid]
		local value = Inventory.sellValue(old)
		local oldName = Monsters.Species[old.sp].Name
		p.monsters[uid] = nil
		p.coins += value
		local sp, el = takeOne(p, key)
		Inventory.addMonster(p, sp :: string, el :: string)
		return done(`Sold {oldName} for {value} coins; {name} joined your storage`)
	elseif action == "sell" then
		local c = p.overflow[key]
		local total = Config.sellValue(Monsters.Species[sp0].Stars, 1) * c
		p.overflow[key] = nil
		p.coins += total
		return done(`Sold {c} {name} for {total} coins`)
	end
	return false, "Unknown action"
end

-- Feed fodder to a monster: XP by the fodder's stars and level; a duplicate species levels up a
-- random unmaxed skill. Returns (ok, message).
function Inventory.feed(player: Player, target: any, foods: any): (boolean, string)
	local p = PlayerData.get(player)
	local m = p and typeof(target) == "string" and p.monsters[target]
	if not m or typeof(foods) ~= "table" or #foods == 0 or #foods > 20 then
		return false, "Pick a monster and some food"
	end
	local seen = {}
	for _, f in foods do
		if typeof(f) ~= "string" or seen[f] then
			return false, "Bad food list"
		end
		seen[f] = true
		local ok, why = canConsume(p, f, target)
		if not ok then
			return false, `Can't feed that one: {why}`
		end
	end
	local xp, skillUps = 0, 0
	for _, f in foods do
		local food = p.monsters[f]
		xp += T.Feed.Xp(Monsters.Species[food.sp].Stars, food.lv)
		if food.sp == m.sp then
			local open = {}
			for i = 1, 3 do
				if m.sk[i] < T.Feed.MaxSkillLevel then
					table.insert(open, i)
				end
			end
			if #open > 0 then
				local i = open[math.random(1, #open)]
				m.sk[i] += 1
				skillUps += 1
			end
		end
		p.monsters[f] = nil
	end
	local levels = Inventory.grantXp(p, target, xp)
	Quests.progress(player, "Feed", #foods)
	if levels > 0 then
		Quests.progress(player, "LevelUp", levels)
	end
	PlayerData.push(player)
	PlayerData.saveSoon(player)
	local msg = `+{xp} XP`
	if levels > 0 then
		msg ..= `, level {m.lv}!`
	end
	if skillUps > 0 then
		msg ..= `, {skillUps} skill-up{skillUps > 1 and "s" or ""}`
	end
	return true, msg
end

function Inventory.awaken(player: Player, uid: any): (boolean, string)
	local p = PlayerData.get(player)
	local m = p and typeof(uid) == "string" and p.monsters[uid]
	if not m then
		return false, "You don't have that monster"
	end
	if m.aw then
		return false, "Already awakened"
	end
	if m.lv < T.AwakenLevel then
		return false, `Reach level {T.AwakenLevel} first`
	end
	local stars = Monsters.Species[m.sp].Stars
	local ess, coins = T.Awaken.Essence(stars), T.Awaken.Coins(stars)
	if (p.essence[m.el] or 0) < ess then
		return false, `Need {ess - (p.essence[m.el] or 0)} more {m.el} Essence`
	end
	if p.coins < coins then
		return false, `Need {coins - p.coins} more coins`
	end
	p.essence[m.el] -= ess
	p.coins -= coins
	m.aw = true
	PlayerData.push(player)
	PlayerData.saveSoon(player)
	return true, `{Monsters.Species[m.sp].Name} awakened! Stats +15% and it can now reach level {T.MaxLevel}`
end

function Inventory.sellValue(m): number
	return Config.sellValue(Monsters.Species[m.sp].Stars, m.lv)
end

function Inventory.sell(player: Player, uids: any): (boolean, string)
	local p = PlayerData.get(player)
	if not p or typeof(uids) ~= "table" or #uids == 0 or #uids > 50 then
		return false, "Pick monsters to sell"
	end
	local total = 0
	local seen = {}
	for _, u in uids do
		if typeof(u) ~= "string" or seen[u] then
			return false, "Bad list"
		end
		seen[u] = true
		local ok, why = canConsume(p, u, nil)
		if not ok then
			return false, `Can't sell that one: {why}`
		end
	end
	for _, u in uids do
		total += Inventory.sellValue(p.monsters[u])
		p.monsters[u] = nil
	end
	p.coins += total
	PlayerData.push(player)
	PlayerData.saveSoon(player)
	return true, `Sold for {total} coins`
end

function Inventory.buyStorage(player: Player): (boolean, string)
	local p = PlayerData.get(player)
	if not p then
		return false, "No profile"
	end
	local step = (p.storageCap - T.StartStorage) // T.StorageStep + 1
	local price = T.StorageCost[step]
	if not price then
		return false, "Storage is maxed out"
	end
	if p.coins < price then
		return false, `Need {price - p.coins} more coins`
	end
	p.coins -= price
	p.storageCap += T.StorageStep
	PlayerData.push(player)
	PlayerData.saveSoon(player)
	return true, `Storage is now {p.storageCap} slots`
end

function Inventory.setWeapon(player: Player, kind: any): (boolean, string)
	local p = PlayerData.get(player)
	if not p or typeof(kind) ~= "string" or not T.Weapons[kind] then
		return false, "Unknown weapon"
	end
	p.weapon.type = kind
	PlayerData.push(player)
	PlayerData.saveSoon(player)
	return true, `{T.Weapons[kind].Name} equipped`
end

function Inventory.upgradeWeapon(player: Player): (boolean, string)
	local p = PlayerData.get(player)
	if not p then
		return false, "No profile"
	end
	if p.weapon.lv >= T.Tamer.MaxWeaponLevel then
		return false, "Your weapon is maxed out"
	end
	local price = T.Tamer.WeaponLevelCost(p.weapon.lv)
	if p.coins < price then
		return false, `Need {price - p.coins} more coins`
	end
	p.coins -= price
	p.weapon.lv += 1
	PlayerData.push(player)
	PlayerData.saveSoon(player)
	return true, `Weapon level {p.weapon.lv}!`
end

return Inventory

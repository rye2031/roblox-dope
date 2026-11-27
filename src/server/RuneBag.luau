-- Server side of runes: drops, the rune bag, equip / unequip / lock / sell / reforge, and the
-- save-data sanitiser. Stats are applied in Combat (team units) and Arena (snapshots) through
-- the shared Runes module.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Runes = require(ReplicatedStorage.Shared.Runes)
local PlayerData = require(script.Parent.PlayerData)

local RuneBag = {}
local rng = Random.new()

local function count(p): number
	local n = 0
	for _ in p.runes do
		n += 1
	end
	return n
end

-- Adds a rune of a rarity to the bag (nil if the bag is full). Returns the rune.
function RuneBag.give(p, rarity: string, set: string?)
	if not Runes.Rarities[rarity] or count(p) >= Runes.BagCap then
		return nil
	end
	local rune = Runes.make(rng, rarity, set)
	local id = "r" .. p.nextRune
	p.nextRune += 1
	p.runes[id] = rune
	return rune
end

-- Rolls a drop for a kill kind ("common" | "elite" | "boss" | "legend"). Returns the rarity.
function RuneBag.rollDrop(p, kind: string): string?
	local rarity = Runes.rollRarity(rng, kind)
	if rarity and RuneBag.give(p, rarity) then
		return rarity
	end
	return nil
end

RuneBag.count = count

-- A monster left the save (fed, sold, swapped): its runes go back to the bag.
function RuneBag.release(p, uid: string)
	for _, rune in p.runes or {} do
		if rune.on == uid then
			rune.on = nil
		end
	end
end

function RuneBag.action(player: Player, action: any, a: any, b: any): (boolean, string, any)
	local p = PlayerData.get(player)
	if not p then
		return false, "No profile"
	end
	local function done(msg: string, data: any?)
		PlayerData.push(player)
		PlayerData.saveSoon(player)
		if RuneBag.onChanged then
			RuneBag.onChanged(player)
		end
		return true, msg, data
	end
	if action == "sell" then
		if typeof(a) ~= "table" or #a == 0 or #a > 60 then
			return false, "Pick runes to sell"
		end
		local total, n = 0, 0
		for _, id in a do
			local rune = typeof(id) == "string" and p.runes[id]
			if rune and not rune.lock and not rune.on then
				total += Runes.Rarities[rune.r].Sell
				p.runes[id] = nil
				n += 1
			end
		end
		if n == 0 then
			return false, "Nothing to sell (locked or equipped runes are kept)"
		end
		p.coins += total
		return done(string.format("Sold %d rune%s for %d coins", n, n > 1 and "s" or "", total))
	end
	local rune = typeof(a) == "string" and p.runes[a]
	if not rune then
		return false, "That rune is gone"
	end
	if action == "equip" then
		local uid = b
		if typeof(uid) ~= "string" or not p.monsters[uid] then
			return false, "Pick a monster"
		end
		if rune.on == uid then
			return false, "Already equipped there"
		end
		if #Runes.on(p, uid) >= Runes.Slots then
			return false, "That monster has 3 runes already: take one off first"
		end
		rune.on = uid
		return done("Rune equipped")
	elseif action == "unequip" then
		rune.on = nil
		return done("Rune back in your bag")
	elseif action == "lock" then
		rune.lock = not rune.lock or nil
		return done(rune.lock and "Rune locked" or "Rune unlocked")
	elseif action == "reforge" then
		local i = typeof(b) == "number" and math.floor(b)
		if not i or not rune.rolls[i] then
			return false, "Pick a roll to reforge"
		end
		local cost = Runes.reforgeCost(rune)
		if p.coins < cost then
			return false, "Need " .. (cost - p.coins) .. " more coins"
		end
		p.coins -= cost
		local old = rune.rolls[i]
		rune.rolls[i] = Runes.rollOne(rng, rune.set)
		rune.rf = (rune.rf or 0) + 1
		local new = rune.rolls[i]
		return done(string.format("Reforged: %s T%d → %s T%d", Runes.Stats[old.s].Short, old.t, Runes.Stats[new.s].Short, new.t), { roll = new })
	end
	return false, "Unknown action"
end

-- Clean whatever came out of the DataStore.
function RuneBag.sanitize(raw, p)
	p.runes = {}
	p.nextRune = 1
	if typeof(raw) ~= "table" then
		return
	end
	local maxId = 0
	local perMonster = {}
	local n = 0
	for id, r in (typeof(raw.runes) == "table" and raw.runes or {}) do
		local num = typeof(id) == "string" and tonumber(string.match(id, "^r(%d+)$"))
		local rar = typeof(r) == "table" and Runes.Rarities[r.r]
		if num and rar and typeof(r.rolls) == "table" and #r.rolls == rar.Rolls and n < Runes.BagCap then
			local rolls, ok = {}, true
			for _, roll in r.rolls do
				local tier = typeof(roll) == "table" and tonumber(roll.t)
				if typeof(roll) == "table" and Runes.Stats[roll.s] and tier and tier >= 1 and tier <= 4 then
					table.insert(rolls, { s = roll.s, t = math.floor(tier) })
				else
					ok = false
				end
			end
			if ok then
				local on = typeof(r.on) == "string" and p.monsters[r.on] and r.on or nil
				if on then
					perMonster[on] = (perMonster[on] or 0) + 1
					if perMonster[on] > Runes.Slots then
						on = nil
					end
				end
				p.runes[id] = { r = r.r, rolls = rolls, on = on, lock = r.lock == true or nil, rf = math.max(0, math.floor(tonumber(r.rf) or 0)), set = typeof(r.set) == "string" and Runes.Sets[r.set] and r.set or nil }
				n += 1
				maxId = math.max(maxId, num)
			end
		end
	end
	p.nextRune = math.max(maxId + 1, math.floor(tonumber(raw.nextRune) or 1))
end

return RuneBag

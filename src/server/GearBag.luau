-- Server side of weapon items (Shared/Gear): the bag, drops, equip / lock / sell / destroy and
-- the save sanitiser. Combat reads GearBag.equipped(p) for damage, speed and perks.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Gear = require(ReplicatedStorage.Shared.Gear)
local Config = require(ReplicatedStorage.Shared.Config)
local PlayerData = require(script.Parent.PlayerData)

local GearBag = {}
local rng = Random.new()

local function count(p): number
	local n = 0
	for _ in p.gear do
		n += 1
	end
	return n
end
GearBag.count = count

function GearBag.give(p, item)
	if not item or count(p) >= Gear.BagCap then
		return nil
	end
	local id = "g" .. p.nextGear
	p.nextGear += 1
	p.gear[id] = item
	return id
end

-- Roll a drop for a source ("elite" | "boss" | "legend" | "titan" | "dungeon" | "dungeonHard").
-- Returns the item (also added to the bag) or nil.
function GearBag.rollDrop(p, source: string, place: string?)
	local item = Gear.roll(rng, source, place)
	if item and GearBag.give(p, item) then
		return item
	end
	return nil
end

function GearBag.equipped(p)
	local id = p.weapon and p.weapon.eq
	return id and p.gear[id] or nil
end

function GearBag.action(player: Player, action: any, a: any): (boolean, string)
	local p = PlayerData.get(player)
	if not p then
		return false, "No profile"
	end
	local function done(msg: string)
		PlayerData.push(player)
		PlayerData.saveSoon(player)
		if GearBag.onChanged then
			GearBag.onChanged(player)
		end
		return true, msg
	end
	if action == "equip" then
		-- "basic:<Type>" for a starter weapon, else an item id
		if typeof(a) == "string" and a:sub(1, 6) == "basic:" then
			local t = a:sub(7)
			if not Config.Tuning.Weapons[t] then
				return false, "Unknown weapon"
			end
			p.weapon.type, p.weapon.eq = t, nil
			return done(Config.Tuning.Weapons[t].Name .. " equipped")
		end
		local item = typeof(a) == "string" and p.gear[a]
		if not item then
			return false, "That weapon is gone"
		end
		p.weapon.type, p.weapon.eq = item.t, a
		return done(item.n .. " equipped")
	elseif action == "lock" then
		local item = typeof(a) == "string" and p.gear[a]
		if not item then
			return false, "That weapon is gone"
		end
		item.lock = not item.lock or nil
		return done(item.lock and "Locked" or "Unlocked")
	elseif action == "sell" or action == "destroy" then
		local ids = typeof(a) == "table" and a or { a }
		local n, coins = 0, 0
		for _, id in ids do
			local item = typeof(id) == "string" and p.gear[id]
			if item and not item.lock and p.weapon.eq ~= id then
				if action == "sell" then
					coins += (Gear.Rarities[item.r] or Gear.Rarities.Common).Sell
				end
				p.gear[id] = nil
				n += 1
			end
		end
		if n == 0 then
			return false, "Nothing to " .. action .. " (locked or equipped weapons are kept)"
		end
		p.coins += coins
		return done(action == "sell" and string.format("Sold %d weapon%s for %d coins", n, n > 1 and "s" or "", coins) or string.format("Destroyed %d weapon%s", n, n > 1 and "s" or ""))
	end
	return false, "Unknown action"
end

-- Clean whatever came out of the DataStore (run after the weapon itself is sanitised).
function GearBag.sanitize(raw, p)
	p.gear = {}
	p.nextGear = 1
	local maxId, n = 0, 0
	local src = typeof(raw) == "table" and typeof(raw.gear) == "table" and raw.gear or {}
	for id, it in src do
		local num = typeof(id) == "string" and tonumber(string.match(id, "^g(%d+)$"))
		if num and typeof(it) == "table" and Config.Tuning.Weapons[it.t] and Gear.Rarities[it.r] and typeof(it.n) == "string" and n < Gear.BagCap then
			local perks = {}
			for _, pk in (typeof(it.perks) == "table" and it.perks or {}) do
				local P = typeof(pk) == "table" and Gear.Perks[pk.k]
				local v = P and tonumber(pk.v)
				if P and v then
					table.insert(perks, { k = pk.k, v = math.clamp(math.floor(v), P.Min, P.Max) })
				end
			end
			p.gear[id] = { t = it.t, r = it.r, n = string.sub(it.n, 1, 40), perks = perks, lock = it.lock == true or nil }
			n += 1
			maxId = math.max(maxId, num)
		end
	end
	p.nextGear = math.max(maxId + 1, math.floor(tonumber(raw and raw.nextGear) or 1))
	local eq = typeof(raw) == "table" and typeof(raw.weapon) == "table" and raw.weapon.eq
	if typeof(eq) == "string" and p.gear[eq] then
		p.weapon.eq = eq
		p.weapon.type = p.gear[eq].t
	else
		p.weapon.eq = nil
	end
end

return GearBag

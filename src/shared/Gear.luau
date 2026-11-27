-- Weapon items (2026-11-27, owner: weapons should feel like an inventory). The four basic
-- weapons (Blade, Staff, Hammer, Bow) are always yours; on top of them you find rarer weapons
-- of each type: Rare, Epic and Legendary hit harder and roll perks. Equip, lock, sell or
-- destroy them in the Smithy. The Smithy's weapon level (coins) still applies to whatever
-- you hold.
--
-- Save data: p.gear = { [id] = { t = type, r = rarity, n = name, perks = { {k, v} }, lock? } },
-- p.nextGear, p.weapon.eq = id of the equipped item (nil = the basic weapon of p.weapon.type).
local Gear = {}

Gear.Rarities = {
	Common = { Mult = 1.0, Perks = 0, Color = Color3.fromRGB(176, 182, 196), Sell = 60 },
	Rare = { Mult = 1.15, Perks = 1, Color = Color3.fromRGB(102, 174, 255), Sell = 250 },
	Epic = { Mult = 1.3, Perks = 2, Color = Color3.fromRGB(186, 112, 255), Sell = 800 },
	Legendary = { Mult = 1.5, Perks = 3, Color = Color3.fromRGB(255, 186, 58), Sell = 2500 },
}
Gear.Order = { "Common", "Rare", "Epic", "Legendary" }
Gear.BagCap = 40

-- Perks: value ranges per roll (percent).
Gear.Perks = {
	power = { Name = "Weapon damage", Short = "DMG", Min = 6, Max = 15 },
	crit = { Name = "Crit chance", Short = "CRIT", Min = 3, Max = 8 },
	haste = { Name = "Attack speed", Short = "SPD", Min = 5, Max = 12 },
	focus = { Name = "Skill cooldown", Short = "CDR", Min = 6, Max = 15 },
	vigor = { Name = "Tamer HP", Short = "HP", Min = 6, Max = 15 },
	rally = { Name = "Team attack", Short = "TEAM", Min = 3, Max = 8 },
}
Gear.PerkOrder = { "power", "crit", "haste", "focus", "vigor", "rally" }

-- Where it dropped decides the name (and Legendaries get their own names).
Gear.Prefix = {
	SproutMeadow = "Thornwood",
	EmberCanyon = "Cinder",
	TideCoast = "Coral",
	GaleHighlands = "Skyward",
	TwilightVale = "Twilight",
	Haven = "Titan",
}
Gear.Legendary = {
	Blade = { "Dawnbreaker", "Stormedge", "Ember Fang" },
	Staff = { "Starwhisper", "Tidecaller", "Moonroot" },
	Hammer = { "Mountainheart", "Thunderfall", "Titan's Knuckle" },
	Bow = { "Galestring", "Sunpiercer", "Nightwing" },
}

-- Drop chances and rarity weights by source.
Gear.Drops = {
	elite = { chance = 0.05, weights = { Rare = 75, Epic = 22, Legendary = 3 } },
	champion = { chance = 0.1, weights = { Rare = 35, Epic = 48, Legendary = 17 } }, -- Champion Rifts
	boss = { chance = 0.35, weights = { Rare = 55, Epic = 37, Legendary = 8 } },
	legend = { chance = 0.6, weights = { Rare = 30, Epic = 55, Legendary = 15 } },
	titan = { chance = 1, weights = { Rare = 35, Epic = 50, Legendary = 15 } },
	dungeon = { chance = 0.2, weights = { Rare = 55, Epic = 38, Legendary = 7 } },
	dungeonHard = { chance = 0.45, weights = { Rare = 30, Epic = 55, Legendary = 15 } },
}

local TYPES = { "Blade", "Staff", "Hammer", "Bow" }

local function pick(weights, r: number)
	local total = 0
	for _, w in weights do
		total += w
	end
	local x = r * total
	for k, w in weights do
		x -= w
		if x <= 0 then
			return k
		end
	end
	local any
	for k in weights do
		any = k
	end
	return any
end

function Gear.make(rng: Random, rarity: string, kind: string?, place: string?)
	local t = kind or TYPES[rng:NextInteger(1, #TYPES)]
	local rar = Gear.Rarities[rarity]
	local perks = {}
	local used = {}
	for _ = 1, rar.Perks do
		local k
		repeat
			k = Gear.PerkOrder[rng:NextInteger(1, #Gear.PerkOrder)]
		until not used[k]
		used[k] = true
		local P = Gear.Perks[k]
		table.insert(perks, { k = k, v = rng:NextInteger(P.Min, P.Max) })
	end
	local name
	if rarity == "Legendary" then
		local list = Gear.Legendary[t]
		name = list[rng:NextInteger(1, #list)]
	else
		name = (Gear.Prefix[place or ""] or "Wanderer's") .. " " .. t
	end
	return { t = t, r = rarity, n = name, perks = perks }
end

function Gear.roll(rng: Random, source: string, place: string?)
	local d = Gear.Drops[source]
	if not d or rng:NextNumber() >= d.chance then
		return nil
	end
	return Gear.make(rng, pick(d.weights, rng:NextNumber()), nil, place)
end

-- Combined stats of an item (nil = a basic weapon): multipliers and fractions.
function Gear.stats(item)
	local s = { mult = 1, crit = 0, haste = 0, focus = 0, vigor = 0, rally = 0 }
	if not item then
		return s
	end
	s.mult = (Gear.Rarities[item.r] or Gear.Rarities.Common).Mult
	for _, pk in item.perks or {} do
		if pk.k == "power" then
			s.mult *= 1 + pk.v / 100
		elseif s[pk.k] ~= nil then
			s[pk.k] += pk.v / 100
		end
	end
	return s
end

function Gear.describe(item): string
	local parts = {}
	for _, pk in item.perks or {} do
		local P = Gear.Perks[pk.k]
		if P then
			table.insert(parts, string.format("%s %s%d%%", P.Short, pk.k == "focus" and "-" or "+", pk.v))
		end
	end
	local base = string.format("x%.2f damage", (Gear.Rarities[item.r] or Gear.Rarities.Common).Mult)
	if #parts == 0 then
		return base
	end
	return base .. " · " .. table.concat(parts, " · ")
end

-- Rough score for sorting (damage plus perks).
function Gear.score(item): number
	local s = Gear.stats(item)
	return math.floor((s.mult - 1) * 100 + (s.crit + s.haste + s.focus + s.vigor + s.rally) * 60)
end

Gear.Types = TYPES
return Gear

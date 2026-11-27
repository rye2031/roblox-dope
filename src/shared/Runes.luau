-- Runes: gear for monsters. Each monster has 3 sockets. A rune has a rarity (Common 1 roll,
-- Rare 2, Epic 3, Legendary 4); each roll is a stat and a tier 1-4 (4 is rarest). Rolls can
-- land on the same stat, so the dream is a Legendary with four tier-4 rolls on one stat.
-- Reforge re-rolls one roll for coins (pricier each time).
--
-- Save data (server): p.runes = { [id] = { r = rarity, rolls = { {s = stat, t = tier}, ... },
-- on = monster uid | nil, lock = bool?, rf = reforge count } }, p.nextRune.
local Monsters = require(script.Parent.Monsters)

local Runes = {}

Runes.Stats = {
	hp = { Name = "HP", Short = "HP", Pct = true, Tiers = { 1.5, 3, 4.5, 6 } },
	atk = { Name = "Attack", Short = "ATK", Pct = true, Tiers = { 1.5, 3, 4.5, 6 } },
	def = { Name = "Defence", Short = "DEF", Pct = true, Tiers = { 1.5, 3, 4.5, 6 } },
	spd = { Name = "Speed", Short = "SPD", Pct = false, Tiers = { 1, 2, 3, 4 } },
	crit = { Name = "Crit rate", Short = "CRIT", Pct = true, Tiers = { 1, 2, 3, 4 } },
	critDmg = { Name = "Crit damage", Short = "CDMG", Pct = true, Tiers = { 2, 4, 6, 8 } },
}
Runes.StatOrder = { "hp", "atk", "def", "spd", "crit", "critDmg" }
Runes.TierWeights = { 40, 30, 20, 10 } -- tier 1..4

Runes.Order = { "Common", "Rare", "Epic", "Legendary" }
Runes.Rarities = {
	Common = { Rolls = 1, Color = Color3.fromRGB(176, 182, 196), Sell = 40, Reforge = 200 },
	Rare = { Rolls = 2, Color = Color3.fromRGB(102, 174, 255), Sell = 120, Reforge = 500 },
	Epic = { Rolls = 3, Color = Color3.fromRGB(186, 112, 255), Sell = 400, Reforge = 1200 },
	Legendary = { Rolls = 4, Color = Color3.fromRGB(255, 186, 58), Sell = 1200, Reforge = 3000 },
}
-- Dungeon runes belong to a set: their rolls lean to the set's two stats (60% per roll, also
-- when reforged), and two runes of one set on the same monster add the set bonus.
Runes.SetFocusChance = 0.6
Runes.Sets = {
	Grove = { Name = "Grove", Focus = { "hp", "def" }, Bonus = { hp = 10 }, Desc = "+10% HP" },
	Forge = { Name = "Forge", Focus = { "atk", "critDmg" }, Bonus = { atk = 8 }, Desc = "+8% ATK" },
	Grotto = { Name = "Grotto", Focus = { "def", "crit" }, Bonus = { def = 12 }, Desc = "+12% DEF" },
	Aerie = { Name = "Aerie", Focus = { "spd", "crit" }, Bonus = { spd = 4, crit = 3 }, Desc = "+4 SPD · +3% crit" },
	Sanctum = { Name = "Sanctum", Focus = { "atk", "crit" }, Bonus = { atk = 5, critDmg = 10 }, Desc = "+5% ATK · +10% crit damage" },
}
Runes.SetPieces = 2
Runes.Slots = 3
Runes.BagCap = 60
Runes.Drops = {
	common = { chance = 0.02, weights = { Common = 85, Rare = 15 } },
	elite = { chance = 0.12, weights = { Common = 55, Rare = 38, Epic = 7 } },
	boss = { chance = 1, weights = { Rare = 55, Epic = 35, Legendary = 10 } },
	legend = { chance = 1, weights = { Epic = 60, Legendary = 40 } },
	shop = { chance = 1, weights = { Rare = 70, Epic = 25, Legendary = 5 } },
	champion = { chance = 0.3, weights = { Rare = 35, Epic = 48, Legendary = 17 } }, -- Champion Rifts
}

local function pick(weights: { [any]: number }, r: number): any
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

function Runes.rollOne(rng: Random, set: string?): { s: string, t: number }
	local focus = set and Runes.Sets[set] and Runes.Sets[set].Focus
	local s
	if focus and rng:NextNumber() < Runes.SetFocusChance then
		s = focus[rng:NextInteger(1, #focus)]
	else
		s = Runes.StatOrder[rng:NextInteger(1, #Runes.StatOrder)]
	end
	local t = pick({ [1] = Runes.TierWeights[1], [2] = Runes.TierWeights[2], [3] = Runes.TierWeights[3], [4] = Runes.TierWeights[4] }, rng:NextNumber())
	return { s = s, t = t }
end

function Runes.make(rng: Random, rarity: string, set: string?)
	local rolls = {}
	for _ = 1, Runes.Rarities[rarity].Rolls do
		table.insert(rolls, Runes.rollOne(rng, set))
	end
	return { r = rarity, rolls = rolls, rf = 0, set = set and Runes.Sets[set] and set or nil }
end

-- Rarity from a weights table (dungeon chests).
function Runes.pickRarity(rng: Random, weights): string
	return pick(weights, rng:NextNumber())
end

function Runes.rollRarity(rng: Random, kind: string): string?
	local d = Runes.Drops[kind]
	if not d or rng:NextNumber() >= d.chance then
		return nil
	end
	return pick(d.weights, rng:NextNumber())
end

-- Summed bonus of a set of runes: percentages for hp/atk/def/crit/critDmg, flat spd.
function Runes.bonus(list: { any }): { [string]: number }
	local b = { hp = 0, atk = 0, def = 0, spd = 0, crit = 0, critDmg = 0 }
	local sets = {}
	for _, rune in list do
		for _, roll in rune.rolls or {} do
			local st = Runes.Stats[roll.s]
			if st then
				b[roll.s] += st.Tiers[roll.t] or 0
			end
		end
		if rune.set and Runes.Sets[rune.set] then
			sets[rune.set] = (sets[rune.set] or 0) + 1
		end
	end
	for set, n in sets do
		if n >= Runes.SetPieces then
			for k, v in Runes.Sets[set].Bonus do
				b[k] += v
			end
		end
	end
	return b
end

-- Stats with a bonus applied (returns a new table).
function Runes.apply(stats, b)
	local s = table.clone(stats)
	if not b then
		return s
	end
	s.hp = math.floor(s.hp * (1 + (b.hp or 0) / 100))
	s.atk = math.floor(s.atk * (1 + (b.atk or 0) / 100))
	s.def = math.floor(s.def * (1 + (b.def or 0) / 100))
	s.spd = math.floor(s.spd + (b.spd or 0))
	s.crit = (s.crit or 0) + (b.crit or 0) / 100
	s.critDmg = (s.critDmg or 1.5) + (b.critDmg or 0) / 100
	return s
end

-- Runes equipped on a monster.
function Runes.on(p, uid: string): { any }
	local out = {}
	for _, rune in p.runes or {} do
		if rune.on == uid then
			table.insert(out, rune)
		end
	end
	return out
end

-- A monster's stats including its runes.
function Runes.monsterStats(p, uid: string)
	local m = p.monsters[uid]
	return Runes.apply(Monsters.stats(m.sp, m.lv, m.aw), Runes.bonus(Runes.on(p, uid)))
end

-- Power from stats (same formula as Monsters.power, crit counted a little).
function Runes.statPower(s): number
	return math.floor(s.hp / 10 + s.atk * 2 + s.def * 1.5 + s.spd + math.max(0, (s.crit or 0) - 0.1) * 400 + math.max(0, (s.critDmg or 1.5) - 1.5) * 150)
end

function Runes.power(p, uid: string): number
	return Runes.statPower(Runes.monsterStats(p, uid))
end

-- Bonus with the zero stats dropped (compact, for Arena snapshots); nil when no runes.
function Runes.compact(b): { [string]: number }?
	local out, any = {}, false
	for k, v in b do
		if v ~= 0 then
			out[k] = v
			any = true
		end
	end
	return any and out or nil
end

-- "ATK +7.5% · SPD +3" (rolls on the same stat merged).
function Runes.describe(rune): string
	local sum, order = {}, {}
	for _, roll in rune.rolls do
		if not sum[roll.s] then
			table.insert(order, roll.s)
			sum[roll.s] = 0
		end
		sum[roll.s] += Runes.Stats[roll.s].Tiers[roll.t]
	end
	local parts = {}
	for _, s in order do
		local st = Runes.Stats[s]
		table.insert(parts, string.format("%s +%s%s", st.Short, (sum[s] % 1 == 0) and tostring(math.floor(sum[s])) or string.format("%.1f", sum[s]), st.Pct and "%" or ""))
	end
	return table.concat(parts, " · ")
end

-- 0..1 (average tier / 4). Perfect = every roll tier 4 on the same stat.
function Runes.quality(rune): (number, boolean)
	local total, same = 0, true
	for _, roll in rune.rolls do
		total += roll.t
		if roll.s ~= rune.rolls[1].s then
			same = false
		end
	end
	local q = total / (4 * #rune.rolls)
	return q, q >= 1 and same and #rune.rolls == 4
end

function Runes.reforgeCost(rune): number
	return math.floor(Runes.Rarities[rune.r].Reforge * (1 + 0.5 * (rune.rf or 0)))
end

return Runes

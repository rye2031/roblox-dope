-- Monster species, stats and skills (shared by server and client).
--
-- A species has fixed stars (1-5 forever), a role and a signature move. Each of the 5 elements
-- gives it two element skills (A = auto-cast, B = the "ultimate" the player fires). Light and
-- Dark kits carry the premium effects (stun, damage over time, lifesteal, shields, silence).
-- Every skill stores both seconds (open-world combat) and turns (turn-based PvP, later).
local Config = require(script.Parent.Config)

local T = Config.Tuning
local Monsters = {}

-- Roles set base stats and which element skills a species gets.
local ROLE_BASE = {
	Attacker = { hp = 540, atk = 62, def = 28, spd = 104 },
	Tank = { hp = 820, atk = 42, def = 46, spd = 94 },
	Support = { hp = 620, atk = 46, def = 34, spd = 100 },
	Speed = { hp = 520, atk = 54, def = 30, spd = 122 },
}
Monsters.RoleBase = ROLE_BASE

-- Model = name in ReplicatedStorage/CreatureModels (uploaded) or MeshData (runtime-built).
-- Hover lifts flyers off the ground. Height is the in-game height in studs.
local S = {}
local function species(id, name, stars, role, range, height, sig, blurb, extra)
	local d = { Id = id, Name = name, Stars = stars, Role = role, Range = range, Height = height, Model = id, Signature = sig, Blurb = blurb }
	for k, v in extra or {} do
		d[k] = v
	end
	S[id] = d
end

-- 1-2 star filler (the original brainrot creatures)
species("MallGobstopper", "Mall Gobstopper", 1, "Speed", "melee", 3.0, { Name = "Sugar Roll", Mult = 1.0 }, "Rolls into everything. Great snack for leveling.")
species("Clawmato", "Clawmato", 1, "Tank", "melee", 3.2, { Name = "Squish Bonk", Mult = 1.0 }, "Escaped a claw machine. Still squishy.")
species("Joystingray", "Joystingray", 1, "Speed", "ranged", 3.0, { Name = "Button Mash", Mult = 0.4, Hits = 3 }, "Up, up, down, down…", { Hover = 1.5 })
species("Blockodile", "Blockodile", 1, "Tank", "melee", 3.0, { Name = "Brick Chomp", Mult = 1.0 }, "Rebuilds itself, grumpily.")
species("Crocsquatch", "Crocsquatch", 1, "Attacker", "melee", 3.4, { Name = "Clog Stomp", Mult = 1.1 }, "Squeaks when it runs.")
species("Yoyoctopus", "Yo-Yoctopus", 1, "Support", "ranged", 3.0, { Name = "Yo-yo Snap", Mult = 0.5, Hits = 2 }, "Walks the dog with eight yo-yos.")
species("CrabRangoon", "Crab Rangoon", 2, "Attacker", "melee", 3.2, { Name = "Pinch Combo", Mult = 0.6, Hits = 2 }, "Grumpy. Pinches.")
species("Ticketoad", "Ticketoad", 2, "Support", "ranged", 3.2, { Name = "Ticket Lash", Mult = 1.0 }, "Licks prize tickets.")
species("Squeakicorn", "Squeakicorn", 2, "Speed", "melee", 3.2, { Name = "Squeak Charge", Mult = 1.05 }, "Squeaks when it dreams.")
species("KingRangoon", "King Rangoon", 2, "Tank", "melee", 3.8, { Name = "Royal Pinch", Mult = 1.0 }, "Crowned by a crumpled carton.")
species("JackpotTicketoad", "Jackpot Ticketoad", 2, "Support", "ranged", 3.8, { Name = "Jackpot Toss", Mult = 1.0 }, "Crowned in golden tickets.")
species("SqueakicornRoyale", "Squeakicorn Royale", 2, "Attacker", "melee", 3.8, { Name = "Royal Horn", Mult = 1.1 }, "A crown and one very loud squeak.")

-- 3-5 star core monsters
species("Tuftail", "Tuftail", 3, "Speed", "melee", 4.0, { Name = "Tail Whip", Mult = 0.6, Hits = 2 }, "A nimble fox cub with a blazing tuft of a tail.", { Core = true })
species("Glimmoth", "Glimmoth", 3, "Support", "ranged", 4.0, { Name = "Dust Flutter", Mult = 1.0 }, "Its wing dust glows in the dark.", { Core = true, Hover = 2 })
species("Sproutknight", "Sproutknight", 3, "Tank", "melee", 4.2, { Name = "Sprout Slash", Mult = 1.0 }, "Small, brave, and very leafy.", { Core = true })
species("Shellotl", "Shellotl", 3, "Support", "melee", 4.0, { Name = "Shell Bash", Mult = 1.0 }, "Carries its home and its friends.", { Core = true })
species("Gryphlet", "Gryphlet", 4, "Attacker", "melee", 5.0, { Name = "Talon Dive", Mult = 1.2 }, "A young griffin that never misses its dive.", { Core = true })
species("Runegolem", "Runegolem", 4, "Tank", "melee", 5.6, { Name = "Rune Fist", Mult = 1.1 }, "Ancient runes keep it awake.", { Core = true })
species("Lancewing", "Lancewing", 4, "Speed", "melee", 5.4, { Name = "Lance Thrust", Mult = 0.65, Hits = 2 }, "Strikes first, from above.", { Core = true })
species("Drakoryn", "Drakoryn", 5, "Attacker", "ranged", 7.0, { Name = "Dragon Breath", Mult = 0.5, Hits = 3 }, "The dragon every Tamer dreams of.", { Core = true })
species("Kirinth", "Kirinth", 5, "Support", "ranged", 6.2, { Name = "Horn Beam", Mult = 1.1 }, "Where it walks, flowers bloom.", { Core = true })
-- wave 2 (2026-11-26): more dragons, humanoids and creature types
species("Bramblebun", "Bramblebun", 3, "Speed", "melee", 3.6, { Name = "Bramble Hop", Mult = 0.55, Hits = 2 }, "Its leafy ears hear rain coming.", { Core = true })
species("Pebblit", "Pebblit", 3, "Tank", "melee", 3.6, { Name = "Rock Roll", Mult = 1.0 }, "Rolls into a stone ball when it's shy.", { Core = true })
species("Wyrmlet", "Wyrmlet", 3, "Attacker", "ranged", 4.0, { Name = "Little Breath", Mult = 0.5, Hits = 2 }, "A baby dragon practising its first roar.", { Core = true })
species("Duskfang", "Duskfang", 4, "Speed", "melee", 5.2, { Name = "Crescent Bite", Mult = 0.65, Hits = 2 }, "Hunts by moonlight, howls at noon.", { Core = true })
species("Owlsage", "Owlsage", 4, "Support", "ranged", 5.0, { Name = "Arcane Hoot", Mult = 1.0 }, "Reads every book in the tower, twice.", { Core = true })
species("Ironhorn", "Ironhorn", 4, "Tank", "melee", 5.4, { Name = "Horn Charge", Mult = 1.1 }, "A beetle knight sworn to protect the small.", { Core = true })
species("Wyvernox", "Wyvernox", 5, "Attacker", "melee", 7.6, { Name = "Wyvern Rend", Mult = 0.7, Hits = 2 }, "Its wingbeat flattens forests.", { Core = true })
species("Valkyra", "Valkyra", 5, "Speed", "melee", 6.4, { Name = "Sky Spear", Mult = 0.7, Hits = 2 }, "A winged warrior who chooses the bravest Tamers.", { Core = true })
species("Phoenara", "Phoenara", 5, "Support", "ranged", 6.6, { Name = "Rebirth Flare", Mult = 1.1 }, "Rises from every fall a little brighter.", { Core = true })

Monsters.Species = S

function Monsters.ordered()
	local list = {}
	for _, sp in S do
		table.insert(list, sp)
	end
	table.sort(list, function(a, b)
		if a.Stars ~= b.Stars then
			return a.Stars < b.Stars
		end
		return a.Name < b.Name
	end)
	return list
end

function Monsters.byStars(stars: number): { string }
	local out = {}
	for id, sp in S do
		if sp.Stars == stars then
			table.insert(out, id)
		end
	end
	table.sort(out)
	return out
end

----------------------------------------------------------------------------------------------
-- Stats

export type Stats = { hp: number, atk: number, def: number, spd: number, crit: number, critDmg: number }

function Monsters.stats(id: string, level: number, awakened: boolean?): Stats
	local sp = S[id]
	local base = ROLE_BASE[sp.Role]
	local budget = T.StarBudget[sp.Stars]
	local g = 1 + T.GrowthPerLevel * (level - 1)
	local a = awakened and (1 + T.AwakenBonus) or 1
	return {
		hp = math.floor(base.hp * budget * g * a),
		atk = math.floor(base.atk * budget * g * a),
		def = math.floor(base.def * budget * g * a),
		spd = math.floor(base.spd * (0.92 + 0.08 * budget) + 0.3 * (level - 1)),
		crit = T.Combat.CritRate + (sp.Role == "Speed" and 0.05 or 0),
		critDmg = T.Combat.CritDamage,
	}
end

function Monsters.power(id: string, level: number, awakened: boolean?): number
	local s = Monsters.stats(id, level, awakened)
	return math.floor(s.hp / 10 + s.atk * 2 + s.def * 1.5 + s.spd)
end

----------------------------------------------------------------------------------------------
-- Skills
--
-- Effect types: burn (pct of max HP per second), stun, heal, shield, buff, debuff, cleanse,
-- silence, lifesteal, slow, taunt. Target: "enemy" (the target), "aoe" (enemies within Radius
-- of the target), "none" (pure support). Effects can target "team", "self" or "lowest" (ally).

local function sk(name, desc, mult, target, cd, extra)
	local s = { Name = name, Desc = desc, Mult = mult, Target = target, Cooldown = cd, Turns = math.max(1, math.floor(cd / 5)), Hits = 1, Radius = 0, Effects = {} }
	for k, v in extra or {} do
		s[k] = v
	end
	return s
end

local function fx(t, p)
	p.type = t
	return p
end

-- Each element: A and B by role. Light/Dark multipliers and effects run hotter.
local ELEMENT = {}

ELEMENT.Fire = function(role)
	local A, B
	if role == "Tank" then
		A = sk("Ember Guard", "Shields itself and draws enemies' attention", 0, "none", 9, { Effects = { fx("shield", { pct = 0.2, dur = 6, to = "self" }), fx("taunt", { dur = 4 }) } })
		B = sk("Magma Slam", "Slams the ground, burning everything nearby", 2.0, "aoe", 18, { Radius = 10, Effects = { fx("burn", { pct = 0.04, dur = 4 }) } })
	elseif role == "Support" then
		A = sk("Kindle", "Fires up the team: +30% attack", 0, "none", 10, { Effects = { fx("buff", { stat = "atk", pct = 0.3, dur = 6, to = "team" }) } })
		B = sk("Phoenix Warmth", "Heals the team and fires them up", 0, "none", 20, { Effects = { fx("heal", { pct = 0.2, to = "team" }), fx("buff", { stat = "atk", pct = 0.25, dur = 6, to = "team" }) } })
	else
		A = sk("Flare Strike", "A burning strike that sets the target alight", 2.0, "enemy", 7, { Effects = { fx("burn", { pct = 0.04, dur = 4 }) } })
		B = sk("Inferno", "Engulfs the target and everything near it in flames", 2.6, "aoe", 18, { Radius = 10, Effects = { fx("burn", { pct = 0.05, dur = 4 }) } })
	end
	return A, B
end

ELEMENT.Water = function(role)
	local A, B
	if role == "Tank" then
		A = sk("Bubble Shell", "Wraps the team in bubbles that absorb damage", 0, "none", 10, { Effects = { fx("shield", { pct = 0.12, dur = 6, to = "team" }) } })
		B = sk("Riptide Wall", "A wall of water: big team shield and cleanse", 0, "none", 20, { Effects = { fx("shield", { pct = 0.2, dur = 6, to = "team" }), fx("cleanse", { to = "team" }) } })
	elseif role == "Support" then
		A = sk("Mend", "Heals the most hurt ally", 0, "none", 7, { Effects = { fx("heal", { pct = 0.25, to = "lowest" }) } })
		B = sk("Healing Rain", "Heals and cleanses the whole team", 0, "none", 18, { Effects = { fx("heal", { pct = 0.25, to = "team" }), fx("cleanse", { to = "team" }) } })
	else
		A = sk("Tidal Lash", "A heavy wave that slows the target", 1.8, "enemy", 7, { Effects = { fx("slow", { pct = 0.3, dur = 4 }) } })
		B = sk("Tsunami", "A huge wave crashes over the target and its friends", 2.3, "aoe", 18, { Radius = 12, Effects = { fx("slow", { pct = 0.3, dur = 4 }) } })
	end
	return A, B
end

ELEMENT.Wind = function(role)
	local A, B
	if role == "Tank" then
		A = sk("Updraft", "Lifts itself: +30% speed and defence", 0, "none", 9, { Effects = { fx("buff", { stat = "spd", pct = 0.3, dur = 6, to = "self" }), fx("buff", { stat = "def", pct = 0.3, dur = 6, to = "self" }) } })
		B = sk("Storm Wall", "Wind armour for the team: +40% defence", 0, "none", 18, { Effects = { fx("buff", { stat = "def", pct = 0.4, dur = 6, to = "team" }) } })
	elseif role == "Support" then
		A = sk("Tailwind", "The team moves faster: +30% speed", 0, "none", 10, { Effects = { fx("buff", { stat = "spd", pct = 0.3, dur = 6, to = "team" }) } })
		B = sk("Zephyr Blessing", "A healing breeze that also speeds the team up", 0, "none", 18, { Effects = { fx("heal", { pct = 0.15, to = "team" }), fx("buff", { stat = "spd", pct = 0.3, dur = 6, to = "team" }) } })
	else
		A = sk("Gale Flurry", "Four quick cuts of wind", 0.6, "enemy", 6, { Hits = 4 })
		B = sk("Cyclone", "A whirlwind that shreds everything near the target", 0.5, "aoe", 16, { Hits = 6, Radius = 11 })
	end
	return A, B
end

ELEMENT.Light = function(role)
	local A, B
	if role == "Tank" then
		A = sk("Halo Guard", "Shields and cleanses the team", 0, "none", 9, { Effects = { fx("shield", { pct = 0.18, dur = 6, to = "team" }), fx("cleanse", { to = "team" }) } })
		B = sk("Sanctuary", "Holy ground: huge team shield and +40% defence", 0, "none", 20, { Effects = { fx("shield", { pct = 0.3, dur = 6, to = "team" }), fx("buff", { stat = "def", pct = 0.4, dur = 6, to = "team" }) } })
	elseif role == "Support" then
		A = sk("Dawn Heal", "Heals and cleanses the team", 0, "none", 8, { Effects = { fx("heal", { pct = 0.18, to = "team" }), fx("cleanse", { to = "team" }) } })
		B = sk("Revival Light", "A great heal, cleanse and +20% attack for everyone", 0, "none", 20, { Effects = { fx("heal", { pct = 0.35, to = "team" }), fx("cleanse", { to = "team" }), fx("buff", { stat = "atk", pct = 0.2, dur = 6, to = "team" }) } })
	else
		A = sk("Radiant Ray", "A searing beam with a chance to stun", 2.3, "enemy", 7, { Effects = { fx("stun", { dur = 1.5, chance = 0.5 }) } })
		B = sk("Judgement", "Blinding light that hits and stuns everything nearby", 3.0, "aoe", 18, { Radius = 12, Effects = { fx("stun", { dur = 1.5, chance = 1 }) } })
	end
	return A, B
end

ELEMENT.Dark = function(role)
	local A, B
	if role == "Tank" then
		A = sk("Shadow Bulwark", "A dark shield that also taunts enemies", 0, "none", 9, { Effects = { fx("shield", { pct = 0.3, dur = 6, to = "self" }), fx("taunt", { dur = 4 }) } })
		B = sk("Abyss Grasp", "Drags enemies down: damage, defence break and silence", 2.0, "aoe", 18, { Radius = 11, Effects = { fx("debuff", { stat = "def", pct = 0.4, dur = 5 }), fx("silence", { dur = 2 }) } })
	elseif role == "Support" then
		A = sk("Hex", "Curses the target: -40% defence and silence", 1.0, "enemy", 8, { Effects = { fx("debuff", { stat = "def", pct = 0.4, dur = 5 }), fx("silence", { dur = 3 }) } })
		B = sk("Eclipse", "Darkness falls: damage over time on everything nearby, the team drinks life", 1.6, "aoe", 20, { Radius = 12, Effects = { fx("burn", { pct = 0.05, dur = 5 }), fx("buff", { stat = "lifesteal", pct = 0.3, dur = 6, to = "team" }) } })
	else
		A = sk("Soul Drain", "Steals life and leaves a lingering curse", 2.2, "enemy", 7, { Effects = { fx("lifesteal", { pct = 0.4 }), fx("burn", { pct = 0.04, dur = 4 }) } })
		B = sk("Nightfall", "Crushing darkness: damage, defence break and silence", 2.8, "aoe", 18, { Radius = 12, Effects = { fx("debuff", { stat = "def", pct = 0.4, dur = 5 }), fx("silence", { dur = 2 }), fx("burn", { pct = 0.05, dur = 4 }) } })
	end
	return A, B
end

local cache = {}
-- The 3 skills of a species in an element: { signature, A, B }.
function Monsters.skills(id: string, element: string)
	local key = id .. ":" .. element
	if cache[key] then
		return cache[key]
	end
	local sp = S[id]
	local scale = 0.85 + 0.05 * sp.Stars -- stronger kits at higher stars
	local sig = sk(sp.Signature.Name, "Signature move (same in every element)", sp.Signature.Mult, "enemy", sp.Range == "ranged" and 1.6 or 1.3, { Hits = sp.Signature.Hits or 1, Signature = true })
	local A, B = ELEMENT[element](sp.Role)
	for _, s in { A, B } do
		s.Mult *= scale
		for _, e in s.Effects do
			if e.pct and (e.type == "heal" or e.type == "shield") then
				e.pct *= scale
			end
		end
	end
	cache[key] = { sig, A, B }
	return cache[key]
end

-- Skill level multiplier (+8% power and -5% cooldown per level above 1).
function Monsters.skillPower(level: number): number
	return 1 + 0.08 * (level - 1)
end
function Monsters.skillCooldown(base: number, level: number): number
	return base * (1 - 0.05 * (level - 1))
end

return Monsters

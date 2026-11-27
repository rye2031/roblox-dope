-- Wildbound: values shared by the server and the client. Gameplay numbers live in Config.Tuning
-- so playtests only touch this file. Design: docs/monster_design.md.
local Config = {
	GameName = "Wildbound",
}

Config.Elements = { "Fire", "Water", "Wind", "Light", "Dark" }

Config.ElementInfo = {
	Fire = { Name = "Fire", Icon = "🔥", Color = Color3.fromRGB(255, 112, 88), Dark = Color3.fromRGB(150, 40, 28), Light = Color3.fromRGB(255, 196, 120) },
	Water = { Name = "Water", Icon = "💧", Color = Color3.fromRGB(80, 160, 255), Dark = Color3.fromRGB(26, 66, 150), Light = Color3.fromRGB(176, 222, 255) },
	Wind = { Name = "Wind", Icon = "🍃", Color = Color3.fromRGB(70, 200, 140), Dark = Color3.fromRGB(26, 104, 66), Light = Color3.fromRGB(196, 246, 196) },
	Light = { Name = "Light", Icon = "✨", Color = Color3.fromRGB(255, 200, 60), Dark = Color3.fromRGB(176, 124, 30), Light = Color3.fromRGB(255, 250, 214) },
	Dark = { Name = "Dark", Icon = "🌙", Color = Color3.fromRGB(150, 104, 230), Dark = Color3.fromRGB(40, 20, 74), Light = Color3.fromRGB(196, 160, 245) },
}

-- Damage multiplier for an attacker element hitting a defender element.
-- Fire > Wind > Water > Fire; Light and Dark are strong against each other.
local BEATS = { Fire = "Wind", Wind = "Water", Water = "Fire" }
function Config.advantage(att: string, def: string): number
	if BEATS[att] == def then
		return 1.25
	elseif BEATS[def] == att then
		return 0.8
	elseif (att == "Light" and def == "Dark") or (att == "Dark" and def == "Light") then
		return 1.25
	end
	return 1
end

Config.Tuning = {
	MaxLevel = 40,
	AwakenLevel = 20, -- un-awakened monsters stop here
	StarBudget = { 0.60, 0.75, 0.92, 0.97, 1.00 }, -- stat share of a 5-star, by stars
	GrowthPerLevel = 0.06,
	AwakenBonus = 0.15,
	TeamSize = 3,
	StartStorage = 50,
	StorageStep = 10,
	OverflowCap = 100, -- summons land here (grouped by species + element) while storage is full
	StorageCost = { 500, 1200, 2500, 5000, 9000 }, -- coins per +10 slots

	Scrolls = {
		Regular = { Stars = { 40, 35, 20, 4.5, 0.5 } }, -- 1..5 star weights
		Legendary = { Stars = { 0, 0, 0, 92, 8 } },
		-- The one Eclipse Scroll: earned once, for finishing the whole story. Always a 5-star,
		-- always Light or Dark (species random). The only free 5-star Light/Dark in the game.
		Eclipse = { Stars = { 0, 0, 0, 0, 1 }, Elements = { Light = 50, Dark = 50 } },
		Elements = { Fire = 33, Water = 33, Wind = 33, Light = 0.5, Dark = 0.5 },
		PityFourStar = 50, -- Regular scrolls without a 4-star+ before one is guaranteed
		PityLightDark = 200, -- scrolls without Light/Dark before one is guaranteed
		Start = { Regular = 4, Legendary = 1 },
		MultiOpen = 10, -- scrolls opened by the "Open 10" button -- a new Tamer's first scrolls
	},

	-- XP needed to go from level L to L+1, and XP a defeated wild monster gives each team member.
	XpToNext = function(l: number): number
		return math.floor(40 * l ^ 1.6)
	end,
	KillXp = function(l: number, stars: number): number
		return math.floor(20 * l ^ 1.25 * (0.8 + 0.1 * stars))
	end,

	Combat = {
		TickRate = 10, -- server combat updates per second
		FollowSpeed = 26, -- studs/s, team monsters (they keep up with a running player)
		WildSpeed = 14,
		RoamSpeed = 5,
		MeleeRange = 5.5,
		RangedRange = 22,
		LeashRadius = 70, -- a wild monster dragged this far from home gives up and heals
		WildHpMult = 2.0, -- wild monsters fight a whole team, so they're beefier
		WildAtkMult = 0.75, -- ...but hit a little softer
		TamerDamageTaken = 0.45, -- wild hits on a Tamer are scaled down (your monsters are the front line)
		TamerThreat = 0.35, -- a Tamer's hits draw less aggro than their monsters' hits
		MobHpPerPlayer = 0.6, -- +60% HP for each extra player hitting the same monster
		ContributionShare = 0.05, -- share of HP you must deal (or heal) for full rewards
		FaintRevive = 15, -- seconds before a fainted team monster gets back up (50% HP)
		OutOfCombatRegen = 0.06, -- share of max HP per second when nothing is fighting
		CritRate = 0.15,
		CritDamage = 1.5,
		Mitigation = 150, -- damage x Mitigation / (Mitigation + DEF)
		CommonRespawn = 25, -- seconds before a defeated wild monster respawns
	},

	-- The Tamer's weapons. All four are available from the start; one weapon level is shared.
	Weapons = {
		Blade = { Name = "Blade", Icon = "⚔", Blurb = "Fast melee combos", Range = 8, Arc = 110, Mult = 1.0, Cooldown = 0.42,
			Skill = { Name = "Spin Slash", Blurb = "Hit everything around you", Mult = 2.4, Radius = 11, Cooldown = 8 } },
		Staff = { Name = "Staff", Icon = "🪄", Blurb = "Ranged magic bolts", Range = 42, Mult = 0.85, Cooldown = 0.6, Ranged = true,
			Skill = { Name = "Healing Pulse", Blurb = "Heal your team and yourself", Heal = 0.18, Radius = 30, Cooldown = 12 } },
		Hammer = { Name = "Hammer", Icon = "🔨", Blurb = "Slow, heavy hits", Range = 9, Arc = 90, Mult = 1.9, Cooldown = 1.05,
			Skill = { Name = "Ground Slam", Blurb = "Smash and stun nearby monsters", Mult = 2.0, Radius = 12, Stun = 1.5, Cooldown = 10 } },
		Bow = { Name = "Bow", Icon = "🏹", Blurb = "Long-range shots", Range = 60, Mult = 0.95, Cooldown = 0.7, Ranged = true,
			Skill = { Name = "Volley", Blurb = "Rain arrows on your target and its friends", Mult = 1.4, Radius = 10, Cooldown = 8 } },
	},
	WeaponOrder = { "Blade", "Staff", "Hammer", "Bow" },
	Tamer = {
		BaseHp = 360,
		HpPerLevel = 24,
		BaseAtk = 38,
		AtkPerLevel = 6,
		BaseDef = 18,
		DefPerLevel = 3,
		DodgeCooldown = 1.2,
		DodgeTime = 0.35, -- invulnerable for this long
		DodgeDistance = 16,
		MaxWeaponLevel = 40,
		WeaponLevelCost = function(l: number): number -- coins to go from l to l+1
			return math.floor(120 * l ^ 1.55 / 10 + 0.5) * 10
		end,
	},

	-- Awakening and feeding (M3)
	Awaken = {
		Essence = function(stars: number): number
			return 10 + 6 * stars
		end,
		Coins = function(stars: number): number
			return 400 * stars
		end,
	},
	Feed = {
		Xp = function(stars: number, level: number): number
			return math.floor(60 * stars ^ 2 * (1 + level / 8))
		end,
		MaxSkillLevel = 5,
	},

	-- Daily quests: 3 a day (one per tier). Streak: 7-day track; day 7 adds a Regular scroll.
	Quests = {
		Rewards = { 60, 120, 220 },
		AllBonus = 150,
		ScrollRewards = { 1, 1, 2 }, -- Regular scrolls per quest tier
		AllBonusScrolls = 2,
		Pool = {
			{ Id = "Defeat", Icon = "⚔", Text = "Defeat %d wild monsters", Targets = { 10, 20, 35 } },
			{ Id = "DefeatFire", Icon = "🔥", Text = "Defeat %d Fire monsters", Targets = { 4, 8, 14 } },
			{ Id = "DefeatWater", Icon = "💧", Text = "Defeat %d Water monsters", Targets = { 4, 8, 14 } },
			{ Id = "DefeatWind", Icon = "🍃", Text = "Defeat %d Wind monsters", Targets = { 4, 8, 14 } },
			{ Id = "Summon", Icon = "📜", Text = "Open %d scrolls", Text1 = "Open a scroll", Targets = { 1, 2, 3 } },
			{ Id = "LevelUp", Icon = "⬆", Text = "Level up your monsters %d times", Targets = { 3, 6, 10 } },
			{ Id = "TeamSkill", Icon = "✨", Text = "Use your team's ultimate skills %d times", Targets = { 5, 10, 18 } },
			{ Id = "Feed", Icon = "🍖", Text = "Feed %d monsters to your team", Targets = { 1, 3, 5 }, MinMonsters = 6 },
			{ Id = "Elite", Icon = "★", Text = "Defeat %d elite monsters", Text1 = "Defeat an elite monster", Targets = { 1, 1, 2 }, Tiers = { 2, 3 }, NeedsBoss = "SproutMeadow" },
		},
		Streak = { 50, 80, 120, 160, 220, 300, 500 },
		StreakScrolls = { 0, 1, 0, 1, 0, 1, 5 }, -- Regular scrolls on each day of the 7-day track
	},

	Rewards = {
		CoinsPerKill = function(l: number): number
			return math.floor(6 + 2.2 * l)
		end,
		EssenceChance = 0.35, -- chance to get Essence of the monster's element
		RegularScrollChance = 0.06,
		EliteScrollChance = 0.4,
		BossScrolls = 3,
	},
}

----------------------------------------------------------------------------------------------
-- M6 loops: Element Surges, Expeditions, Index rewards

Config.Loops = {
	Surge = {
		Cycle = { "Fire", "Water", "Wind" }, -- one per UTC hour
		RareEvery = 6, -- every 6th hour is a Light or Dark surge instead
		SpawnMult = 3, -- surge element's spawn weight (triangle); Light/Dark weight becomes RareWeight
		RareWeight = 4,
		EssenceMult = 2,
		CoinMult = 1.25,
	},
	Expeditions = {
		Slots = 3,
		SlotBoss = { nil, "SproutMeadow", "EmberCanyon" }, -- boss to beat before the slot opens
		MaxMonsters = 3,
		Durations = {
			{ Name = "Quick", Minutes = 15 },
			{ Name = "Short", Minutes = 60 },
			{ Name = "Long", Minutes = 240 },
			{ Name = "Overnight", Minutes = 480 },
		},
		Places = {
			SproutMeadow = { Name = "Sprout Meadow", Mult = 1, Essence = nil, Icon = "🌱" },
			EmberCanyon = { Name = "Ember Canyon", Mult = 1.5, Essence = "Fire", Icon = "🔥" },
			TideCoast = { Name = "Tide Coast", Mult = 2, Essence = "Water", Icon = "💧" },
			GaleHighlands = { Name = "Gale Highlands", Mult = 2.5, Essence = "Wind", Icon = "🍃" },
		},
	},
	IndexMilestones = {
		{ n = 5, coins = 300 },
		{ n = 10, coins = 600, scrolls = 1 },
		{ n = 20, coins = 800, scrolls = 2 },
		{ n = 30, legendary = 1 },
		{ n = 45, coins = 2000, scrolls = 3 },
		{ n = 60, legendary = 1, scrolls = 2 },
		{ n = 80, scrolls = 5, coins = 3000 },
		{ n = 100, legendary = 2 },
		{ n = 125, legendary = 2, scrolls = 5 },
		{ n = 150, legendary = 5 },
	},
	SpeciesComplete = { legendary = 1 }, -- all 5 elements of one species
}

-- Sealed Scrolls (the "egg hatch" timer): drops that must attune at the Shrine before they
-- open into real scrolls. Longer seals give more.
Config.Sealed = {
	Order = { "Bronze", "Silver", "Gold", "Prismatic" },
	Tiers = {
		Bronze = { Name = "Bronze Seal", Minutes = 2, Color = Color3.fromRGB(205, 140, 90), scrolls = 1 },
		Silver = { Name = "Silver Seal", Minutes = 5, Color = Color3.fromRGB(170, 184, 206), scrolls = 2 },
		Gold = { Name = "Gold Seal", Minutes = 15, Color = Color3.fromRGB(255, 198, 58), scrolls = 3, legendaryChance = 0.35 },
		Prismatic = { Name = "Prismatic Seal", Minutes = 60, Color = Color3.fromRGB(190, 120, 255), legendary = 1 },
	},
	Slots = 3,
	BagCap = 20,
	Drops = {
		common = { chance = 0.01, weights = { Bronze = 100 } },
		elite = { chance = 0.15, weights = { Bronze = 60, Silver = 35, Gold = 5 } },
		boss = { chance = 0.5, weights = { Silver = 50, Gold = 40, Prismatic = 10 } },
		legend = { chance = 1, weights = { Gold = 60, Prismatic = 40 } },
	},
}

-- Day and night: a 20-minute cycle on server time (every server agrees). The last 6 minutes
-- are night (more Dark monsters and elites, double Dark Essence); the first 2 minutes of day
-- are dawn (more Light monsters).
Config.DayNight = {
	Cycle = 1200,
	NightStart = 840,
	DawnLength = 120,
	DarkWeight = 4, -- Dark spawn weight at night (normally 0.5)
	LightWeight = 3, -- Light spawn weight at dawn
	NightEliteBonus = 0.06,
	DarkEssenceMult = 2,
}

-- Phase at os.time t: "day" | "dawn" | "night", plus the next nightfall and the next sunrise.
function Config.dayPhase(t: number): (string, number, number)
	local D = Config.DayNight
	local c = t % D.Cycle
	local base = t - c
	local nightAt = c < D.NightStart and base + D.NightStart or base + D.Cycle + D.NightStart
	local dayAt = base + D.Cycle
	local phase = c >= D.NightStart and "night" or (c < D.DawnLength and "dawn" or "day")
	return phase, nightAt, dayAt
end

-- M7 Arena: async turn-based 3v3 PvP
Config.Arena = {
	UnlockBoss = "SproutMeadow",
	StartRating = 1000,
	MatchRange = 200,
	RefreshSeconds = 300,
	DailyAttacks = 10,
	K = 32,
	WinTokens = 10,
	LossTokens = 3,
	WinCoins = 150,
	Shop = {
		regular = { name = "a Regular scroll", cost = 40, scrolls = 1, order = 1 },
		essence = { name = "10 Essence", cost = 25, essence = 10, order = 2 },
		legendary = { name = "a Legendary scroll", cost = 300, legendary = 1, order = 3 },
	},
}

-- The surge for a moment (os.time): element and the os.time it ends.
function Config.surgeAt(t: number): (string, number)
	local S = Config.Loops.Surge
	local hour = t // 3600
	local el
	if hour % S.RareEvery == S.RareEvery - 1 then
		el = (hour // S.RareEvery) % 2 == 0 and "Light" or "Dark"
	else
		el = S.Cycle[hour % #S.Cycle + 1]
	end
	return el, (hour + 1) * 3600
end

-- What an expedition brings back. monsters = list of { sp, lv, aw }.
function Config.expeditionReward(monsters, place: string, minutes: number)
	local E = Config.Loops.Expeditions
	local pl = E.Places[place]
	local power = 0
	for _, m in monsters do
		local stars = (require(script.Parent.Monsters).Species[m.sp] or { Stars = 1 }).Stars
		power += stars ^ 1.5 * (1 + m.lv / 15) * (m.aw and 1.25 or 1)
	end
	local mult = pl and pl.Mult or 1
	local refLevel = place == "GaleHighlands" and 28 or place == "TideCoast" and 20 or place == "EmberCanyon" and 13 or 6
	return {
		coins = math.floor(power * minutes * 0.5 * mult),
		essence = math.max(1, math.floor(power * minutes / 80 * mult)),
		element = pl and pl.Essence, -- nil: random triangle element when claimed
		scrolls = math.floor(minutes / 240),
		scrollChance = (minutes % 240) / 240 * 0.6,
		xp = math.floor(Config.Tuning.KillXp(refLevel, 2) * minutes / 6),
	}
end

-- Coins for selling a monster (server pays this; the HUD previews it).
function Config.sellValue(stars: number, level: number): number
	return math.floor(20 * stars ^ 2 * (1 + level / 10))
end

-- Tamer stats from the shared weapon level.
function Config.tamerStats(weaponLevel: number)
	local t = Config.Tuning.Tamer
	local l = math.max(1, weaponLevel)
	return {
		hp = t.BaseHp + t.HpPerLevel * (l - 1),
		atk = t.BaseAtk + t.AtkPerLevel * (l - 1),
		def = t.BaseDef + t.DefPerLevel * (l - 1),
	}
end

-- Weighted pick from { [key] = weight } using a 0..1 roll.
function Config.pickWeighted(weights: { [any]: number }, roll: number): any
	local total = 0
	local keys = {}
	for k, w in weights do
		total += w
		table.insert(keys, k)
	end
	table.sort(keys, function(a, b)
		return tostring(a) < tostring(b)
	end)
	local r = roll * total
	for _, k in keys do
		r -= weights[k]
		if r <= 0 then
			return k
		end
	end
	return keys[#keys]
end

function Config.questDef(id: string)
	for _, d in Config.Tuning.Quests.Pool do
		if d.Id == id then
			return d
		end
	end
	return nil
end

function Config.questText(id: string, n: number): string
	local d = Config.questDef(id)
	if not d then
		return id
	end
	if n == 1 and d.Text1 then
		return d.Text1
	end
	return string.format(d.Text, n)
end

local function round5(n: number): number
	return math.floor(n / 5 + 0.5) * 5
end

-- Quest rewards grow with the number of region bosses beaten.
local function questScale(p: any): number
	local n = 0
	for _ in p.bosses or {} do
		n += 1
	end
	return 1 + 0.5 * n
end
function Config.questReward(p: any, tier: number): number
	return round5(Config.Tuning.Quests.Rewards[tier] * questScale(p))
end
function Config.questBonus(p: any): number
	return round5(Config.Tuning.Quests.AllBonus * questScale(p))
end

-- Login streak: the day you'd get by claiming today, and whether it's claimable.
function Config.streakPreview(p: any, today: number): (number, boolean)
	if p.streak.last == today then
		return p.streak.count, false
	end
	if p.streak.last == today - 1 then
		return p.streak.count + 1, true
	end
	return 1, true
end
function Config.questScrolls(tier: number): number
	return Config.Tuning.Quests.ScrollRewards[tier] or 0
end
function Config.streakScrolls(day: number): number
	local list = Config.Tuning.Quests.StreakScrolls
	return list[(day - 1) % #list + 1] or 0
end
function Config.streakReward(day: number): number
	local list = Config.Tuning.Quests.Streak
	return list[(day - 1) % #list + 1]
end

-- UTC day number; quests and the login streak roll over at 00:00 UTC.
function Config.today(): number
	return os.time() // 86400
end

return Config

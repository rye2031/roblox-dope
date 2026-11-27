-- Dungeons: short instanced runs (3 waves, then a boss) on floating arenas off the map.
-- Each dungeon belongs to a region (opens with that region's boss clear), favours two rune
-- stats and drops runes of its own set (2 of a set on one monster = a set bonus). Normal and
-- Hard (Hard opens after a Normal clear: +8 levels, tougher, 2 runes with better odds).
-- Keys: a clear uses one; they refill over time; a failed or abandoned run costs nothing.
local DungeonData = {}

DungeonData.KeyCap = 5
DungeonData.KeyMinutes = 30 -- one key back every 30 minutes
DungeonData.TimeLimit = 8 * 60 -- seconds
DungeonData.WaveSizes = { 3, 4, 5 } -- then the boss
DungeonData.Modes = {
	Normal = { lvAdd = 0, hpMult = 1, bossHp = 8, runes = 1, weights = { Rare = 60, Epic = 32, Legendary = 8 }, coins = 1, first = { scrolls = 2 } },
	Hard = { lvAdd = 8, hpMult = 1.5, bossHp = 12, runes = 2, weights = { Rare = 25, Epic = 50, Legendary = 25 }, coins = 2, first = { legendary = 1 } },
}

DungeonData.Order = { "Grove", "Forge", "Grotto", "Aerie", "Sanctum" }
DungeonData.List = {
	Grove = {
		Name = "Bramble Hollow",
		Icon = "🌿",
		Region = "SproutMeadow",
		RegionName = "Sprout Meadow",
		Levels = { 9, 11 },
		Elements = { Fire = 33, Water = 33, Wind = 33 },
		Color = Color3.fromRGB(122, 196, 120),
		Stone = Color3.fromRGB(150, 132, 110),
		Blurb = "A tangle of roots under the Meadow.",
	},
	Forge = {
		Name = "Cinder Forge",
		Icon = "🔥",
		Region = "EmberCanyon",
		RegionName = "Ember Canyon",
		Levels = { 16, 18 },
		Elements = { Fire = 80, Wind = 10, Water = 10 },
		Color = Color3.fromRGB(255, 132, 84),
		Stone = Color3.fromRGB(96, 74, 70),
		Blurb = "An old smithy of the canyon drakes.",
	},
	Grotto = {
		Name = "Pearl Grotto",
		Icon = "🌊",
		Region = "TideCoast",
		RegionName = "Tide Coast",
		Levels = { 24, 26 },
		Elements = { Water = 80, Wind = 10, Fire = 10 },
		Color = Color3.fromRGB(92, 182, 236),
		Stone = Color3.fromRGB(178, 196, 210),
		Blurb = "A drowned cave full of shells and echoes.",
	},
	Aerie = {
		Name = "Storm Aerie",
		Icon = "🌪",
		Region = "GaleHighlands",
		RegionName = "Gale Highlands",
		Levels = { 32, 34 },
		Elements = { Wind = 80, Fire = 10, Water = 10 },
		Color = Color3.fromRGB(150, 224, 196),
		Stone = Color3.fromRGB(196, 204, 214),
		Blurb = "Nests on a pillar in the thunderclouds.",
	},
	Sanctum = {
		Name = "Eclipse Sanctum",
		Icon = "🌗",
		Region = "TwilightVale",
		RegionName = "Twilight Vale",
		Levels = { 40, 42 },
		Elements = { Light = 45, Dark = 45, Fire = 4, Water = 3, Wind = 3 },
		Color = Color3.fromRGB(170, 140, 230),
		Stone = Color3.fromRGB(226, 220, 240),
		Blurb = "Half sunlit, half starlit, all dangerous.",
	},
}

-- Run with the dungeon's level range for a mode.
function DungeonData.levels(id: string, mode: string): (number, number)
	local d, m = DungeonData.List[id], DungeonData.Modes[mode]
	return d.Levels[1] + m.lvAdd, d.Levels[2] + m.lvAdd
end

-- Refill keys up to now (mutates state = {keys, keyAt}). Returns keys and when the next one
-- arrives (nil when full). The client calls it on a copy.
function DungeonData.refill(state, now: number): (number, number?)
	local step = DungeonData.KeyMinutes * 60
	state.keys = state.keys or DungeonData.KeyCap
	state.keyAt = state.keyAt or now
	while state.keys < DungeonData.KeyCap and now >= state.keyAt + step do
		state.keys += 1
		state.keyAt += step
	end
	if state.keys >= DungeonData.KeyCap then
		state.keyAt = now
		return state.keys, nil
	end
	return state.keys, state.keyAt + step
end

return DungeonData

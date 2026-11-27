-- What a player sees grows with them (2026-11-27, owner: too much for young players at once).
-- A brand-new Tamer starts with only Monsters and Shrine; the other menus and HUD pieces show
-- up as they become useful, each with a "NEW!" badge the first time. Players already past the
-- first story steps see everything.
local Unlocks = {}

local function count(t): number
	local n = 0
	for _ in t or {} do
		n += 1
	end
	return n
end

local function veteran(p): boolean
	return (p.story and p.story.i or 1) >= 9
end

-- id -> { when unlocked, message shown the first time }
Unlocks.Rules = {
	Monsters = { function()
		return true
	end },
	Shrine = { function()
		return true
	end },
	Quests = { function(p)
		return p.kills >= 1
	end, "Daily Quests: small goals for scrolls and coins" },
	Pass = { function(p)
		return p.kills >= 3
	end, "Tamer Pass: free rewards for everything you do" },
	Index = { function(p)
		return p.kills >= 6 or count(p.index) >= 6
	end, "Index: every monster you've ever found" },
	Weapons = { function(p)
		return p.kills >= 12
	end, "Weapons: change and upgrade your weapon" },
	Runes = { function(p)
		return count(p.runes) > 0
	end, "Runes: gear that makes monsters stronger" },
	Expeditions = { function(p)
		return p.bosses and p.bosses.SproutMeadow == true
	end, "Expeditions: send spare monsters on trips" },
	-- HUD pieces (no message)
	Auto = { function(p)
		return p.kills >= 1
	end },
	Ride = { function(p)
		return p.kills >= 4
	end, "Ride: hop on your monster to travel fast (F)" },
	Ticker = { function(p)
		return p.kills >= 10
	end },
	Travel = { function(p)
		return count(p.campfires) >= 2
	end, "Travel: jump to any campfire you've lit" },
}

function Unlocks.open(p, id: string): boolean
	if not p then
		return false
	end
	local r = Unlocks.Rules[id]
	if not r then
		return true
	end
	return veteran(p) or r[1](p) == true
end

function Unlocks.message(id: string): string?
	local r = Unlocks.Rules[id]
	return r and r[2]
end

return Unlocks

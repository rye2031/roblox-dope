-- Tamer Pass tiers and XP (2026-11-27). Free for everyone, no expiry, no paid skips.
local PassData = {}

PassData.XpPerTier = 400

-- XP for things you do (Pass.add source names).
PassData.Xp = {
	kill = 2,
	elite = 8,
	boss = 40,
	legend = 60,
	titan = 60,
	quest = 60,
	dungeon = 80,
	dungeonHard = 120,
	discovery = 100,
	story = 40,
	arena = 30,
	expedition = 30,
}

-- 50 tiers. Every 10th is a big one. After the last tier, every XpPerTier gives the bonus.
local T = {}
for i = 1, 50 do
	local r
	if i % 10 == 0 then
		r = i == 50 and { legendary = 2, gear = "Legendary" } or i == 30 and { legendary = 1, gear = "Epic" } or { legendary = 1 }
	elseif i % 5 == 0 then
		r = i >= 25 and { rune = "Epic" } or { rune = "Rare" }
	elseif i % 4 == 0 then
		r = { sealed = i >= 20 and "Gold" or "Silver" }
	elseif i % 3 == 0 then
		r = { scrolls = i >= 20 and 3 or 2 }
	elseif i % 2 == 0 then
		r = { essence = 10 + math.floor(i / 5) * 2 }
	else
		r = { coins = 300 + i * 40 }
	end
	T[i] = r
end
PassData.Tiers = T
PassData.Bonus = { scrolls = 1 }

function PassData.tierAt(xp: number): number
	return math.floor(xp / PassData.XpPerTier)
end

function PassData.bonusAvailable(xp: number): number
	return math.max(0, math.floor((xp - #PassData.Tiers * PassData.XpPerTier) / PassData.XpPerTier))
end

function PassData.text(r): string
	local parts = {}
	if r.coins then
		table.insert(parts, "💰 " .. r.coins)
	end
	if r.scrolls then
		table.insert(parts, "🥚 " .. r.scrolls .. " Regular")
	end
	if r.legendary then
		table.insert(parts, "🌟 " .. r.legendary .. " Legendary")
	end
	if r.essence then
		table.insert(parts, "✦ " .. r.essence .. " Crystals")
	end
	if r.rune then
		table.insert(parts, "💠 " .. r.rune .. " rune")
	end
	if r.gear then
		table.insert(parts, "⚔ " .. r.gear .. " weapon")
	end
	if r.sealed then
		table.insert(parts, "🧺 " .. r.sealed .. " Egg")
	end
	return table.concat(parts, " · ")
end

function PassData.icon(r): string
	return r.gear and "⚔" or r.legendary and "🌟" or r.rune and "💠" or r.sealed and "🧺" or r.scrolls and "🥚" or r.essence and "✦" or "💰"
end

return PassData

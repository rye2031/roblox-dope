-- M6 loops: Element Surges (hourly element events), Expeditions (send storage monsters away
-- for rewards, also while offline) and Index rewards (collection milestones).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Monsters = require(Shared.Monsters)
local PlayerData = require(script.Parent.PlayerData)
local Inventory = require(script.Parent.Inventory)

local L = Config.Loops
local E = L.Expeditions
local T = Config.Tuning
local Loops = {}
local rng = Random.new()
local toast: RemoteEvent

----------------------------------------------------------------------------------------------
-- Element Surges

function Loops.surge(): string
	return (Config.surgeAt(os.time()))
end

local RunService = game:GetService("RunService")
local function now(): number
	-- Studio only: workspace attribute DebugTimeOffset (seconds) fast-forwards the clock for tests
	return os.time() + (RunService:IsStudio() and (workspace:GetAttribute("DebugTimeOffset") or 0) or 0)
end
Loops.now = now

function Loops.phase(): string
	return (Config.dayPhase(now()))
end

-- Element weights for a region with the current surge and time of day applied.
function Loops.surgeWeights(base: { [string]: number }): { [string]: number }
	local el = Loops.surge()
	local w = table.clone(base)
	if el == "Light" or el == "Dark" then
		w[el] = L.Surge.RareWeight
	elseif w[el] then
		w[el] *= L.Surge.SpawnMult
	end
	local phase = Loops.phase()
	local D = Config.DayNight
	if phase == "night" then
		w.Dark = math.max(w.Dark or 0, D.DarkWeight)
	elseif phase == "dawn" then
		w.Light = math.max(w.Light or 0, D.LightWeight)
	end
	return w
end

local function dayNightLoop()
	local last = nil
	while true do
		local phase, nightAt, dayAt = Config.dayPhase(now())
		local isNight = phase == "night"
		workspace:SetAttribute("IsNight", isNight)
		workspace:SetAttribute("NightAt", nightAt)
		workspace:SetAttribute("DayAt", dayAt)
		if last ~= nil and phase ~= last then
			if phase == "night" then
				toast:FireAllClients("🌙 Night falls. Dark monsters and elites roam, and Dark Crystals drop double", "info")
			elseif phase == "dawn" then
				toast:FireAllClients("🌅 Dawn breaks. Light monsters are out for a little while", "info")
			end
		end
		last = phase
		task.wait(2)
	end
end

local function surgeLoop()
	local current = nil
	while true do
		local el, untilT = Config.surgeAt(os.time())
		if el ~= current then
			current = el
			workspace:SetAttribute("SurgeElement", el)
			workspace:SetAttribute("SurgeUntil", untilT)
			local info = Config.ElementInfo[el]
			local rare = el == "Light" or el == "Dark"
			toast:FireAllClients(string.format("%s %s Surge! %s for the next hour", info.Icon, el, rare and ("Rare " .. el .. " monsters are out") or ("More " .. el .. " monsters, double " .. el .. " Crystals")), "good")
		end
		task.wait(5)
	end
end

----------------------------------------------------------------------------------------------
-- Expeditions

Loops.awaySet = Inventory.awaySet

local function slotOpen(p, slot: number): boolean
	local need = E.SlotBoss[slot]
	return slot >= 1 and slot <= E.Slots and (need == nil or p.bosses[need] == true)
end

function Loops.expedition(player: Player, action: any, slot: any, place: any, dur: any, uids: any): (boolean, string, any)
	local p = PlayerData.get(player)
	if not p or typeof(slot) ~= "number" then
		return false, "No profile"
	end
	slot = math.floor(slot)
	local key = tostring(slot)
	if action == "start" then
		if not slotOpen(p, slot) then
			return false, "That slot opens after a region boss"
		end
		if p.expeditions[key] then
			return false, "That slot is busy"
		end
		local pl = E.Places[place]
		local d = typeof(dur) == "number" and E.Durations[dur]
		if not pl or not d then
			return false, "Pick a place and a length"
		end
		if not p.regions[place] then
			return false, "You haven't reached " .. pl.Name .. " yet"
		end
		if typeof(uids) ~= "table" or #uids < 1 or #uids > E.MaxMonsters then
			return false, "Pick 1 to " .. E.MaxMonsters .. " monsters"
		end
		local away = Loops.awaySet(p)
		local team = {}
		for _, u in p.team do
			team[u] = true
		end
		local seen = {}
		local ms = {}
		for _, u in uids do
			local m = typeof(u) == "string" and p.monsters[u]
			if not m or seen[u] then
				return false, "Bad monster list"
			end
			if team[u] then
				return false, "Team monsters stay with you"
			end
			if away[u] then
				return false, "That monster is already away"
			end
			seen[u] = true
			table.insert(ms, { sp = m.sp, lv = m.lv, aw = m.aw })
		end
		local list = {}
		for _, u in uids do
			table.insert(list, u)
		end
		p.expeditions[key] = { place = place, dur = dur, start = os.time(), uids = list, reward = Config.expeditionReward(ms, place, d.Minutes) }
		PlayerData.push(player)
		PlayerData.saveSoon(player)
		return true, string.format("Expedition to %s: back in %s", pl.Name, d.Minutes >= 60 and (d.Minutes // 60 .. " h") or (d.Minutes .. " min"))
	end
	local x = p.expeditions[key]
	if not x then
		return false, "Nothing in that slot"
	end
	if action == "recall" then
		p.expeditions[key] = nil
		PlayerData.push(player)
		PlayerData.saveSoon(player)
		return true, "Recalled: they came back empty-handed"
	elseif action == "claim" then
		local d = E.Durations[x.dur]
		if os.time() < x.start + d.Minutes * 60 then
			return false, "Not back yet"
		end
		local r = x.reward
		local el = r.element == "Twilight" and (rng:NextNumber() < 0.5 and "Light" or "Dark") or r.element or ({ "Fire", "Water", "Wind" })[rng:NextInteger(1, 3)]
		local scrolls = r.scrolls + (rng:NextNumber() < r.scrollChance and 1 or 0)
		p.coins += r.coins
		p.essence[el] = (p.essence[el] or 0) + r.essence
		p.scrolls.Regular += scrolls
		local levels = 0
		for _, u in x.uids do
			if p.monsters[u] then
				levels += Inventory.grantXp(p, u, r.xp)
			end
		end
		p.expeditions[key] = nil
		PlayerData.push(player)
		PlayerData.saveSoon(player)
		local parts = { "+" .. r.coins .. " coins", "+" .. r.essence .. " " .. el .. " Crystals" }
		if scrolls > 0 then
			table.insert(parts, "+" .. scrolls .. " 🥚")
		end
		if levels > 0 then
			table.insert(parts, levels .. " level-up" .. (levels > 1 and "s" or ""))
		end
		require(script.Parent.Pass).add(player, "expedition")
		return true, "Expedition back! " .. table.concat(parts, ", "), { coins = r.coins, essence = r.essence, element = el, scrolls = scrolls, levels = levels }
	end
	return false, "Unknown action"
end

----------------------------------------------------------------------------------------------
-- Sealed Scrolls

local SE = Config.Sealed

-- Roll a sealed-scroll drop for a kill; adds it to the satchel. Returns the tier or nil.
function Loops.rollSealed(p, kind: string): string?
	local d = SE.Drops[kind]
	if not d or rng:NextNumber() >= d.chance then
		return nil
	end
	local total = 0
	for _, n in p.sealed.bag do
		total += n
	end
	if total >= SE.BagCap then
		return nil
	end
	local tier = Config.pickWeighted(d.weights, rng:NextNumber())
	p.sealed.bag[tier] = (p.sealed.bag[tier] or 0) + 1
	return tier
end

function Loops.sealed(player: Player, action: any, a: any): (boolean, string, any)
	local p = PlayerData.get(player)
	if not p then
		return false, "No profile"
	end
	local function done(msg: string, data: any?)
		PlayerData.push(player)
		PlayerData.saveSoon(player)
		return true, msg, data
	end
	if action == "attune" then
		local tier = typeof(a) == "string" and SE.Tiers[a] and a
		if not tier or (p.sealed.bag[tier] or 0) <= 0 then
			return false, "You don't have that seal"
		end
		for i = 1, SE.Slots do
			local k = tostring(i)
			if not p.sealed.slots[k] then
				p.sealed.bag[tier] -= 1
				if p.sealed.bag[tier] <= 0 then
					p.sealed.bag[tier] = nil
				end
				p.sealed.slots[k] = { tier = tier, start = os.time() }
				return done(string.format("Warming a %s: ready in %d min", SE.Tiers[tier].Name, SE.Tiers[tier].Minutes))
			end
		end
		return false, "All nest slots are busy"
	elseif action == "claim" then
		local k = tostring(a)
		local sl = p.sealed.slots[k]
		if not sl then
			return false, "Nothing in that slot"
		end
		local t = SE.Tiers[sl.tier]
		if os.time() < sl.start + t.Minutes * 60 then
			return false, "Still warming"
		end
		p.sealed.slots[k] = nil
		local reg, leg = t.scrolls or 0, t.legendary or 0
		if t.legendaryChance and rng:NextNumber() < t.legendaryChance then
			reg, leg = 0, leg + 1
		end
		p.scrolls.Regular += reg
		p.scrolls.Legendary += leg
		local parts = {}
		if reg > 0 then
			table.insert(parts, "+" .. reg .. " Regular Egg" .. (reg > 1 and "s" or ""))
		end
		if leg > 0 then
			table.insert(parts, "+" .. leg .. " Legendary Egg")
		end
		return done(t.Name .. " opened! " .. table.concat(parts, ", "), { regular = reg, legendary = leg, tier = sl.tier })
	end
	return false, "Unknown action"
end

----------------------------------------------------------------------------------------------
-- Index rewards

local function grant(p, r)
	p.coins += r.coins or 0
	p.scrolls.Regular += r.scrolls or 0
	p.scrolls.Legendary += r.legendary or 0
end

function Loops.indexReward(player: Player, kind: any, key: any): (boolean, string)
	local p = PlayerData.get(player)
	if not p then
		return false, "No profile"
	end
	if kind == "milestone" then
		local m = typeof(key) == "number" and L.IndexMilestones[key]
		if not m then
			return false, "Unknown reward"
		end
		if p.indexClaims.m[tostring(key)] then
			return false, "Already claimed"
		end
		local n = 0
		for _ in p.index do
			n += 1
		end
		if n < m.n then
			return false, "Find " .. (m.n - n) .. " more first"
		end
		p.indexClaims.m[tostring(key)] = true
		grant(p, m)
	elseif kind == "species" then
		local sp = typeof(key) == "string" and Monsters.Species[key]
		if not sp then
			return false, "Unknown species"
		end
		if p.indexClaims.s[key] then
			return false, "Already claimed"
		end
		for _, el in Config.Elements do
			if not p.index[key .. ":" .. el] then
				return false, "Find all 5 elements first"
			end
		end
		p.indexClaims.s[key] = true
		grant(p, L.SpeciesComplete)
	else
		return false, "Unknown reward"
	end
	PlayerData.push(player)
	PlayerData.saveSoon(player)
	return true, "Collection reward claimed!"
end

----------------------------------------------------------------------------------------------

function Loops.init(remotes)
	toast = remotes.Toast
	task.spawn(surgeLoop)
	task.spawn(dayNightLoop)
	local _ = Players
	local _t = T
end

return Loops

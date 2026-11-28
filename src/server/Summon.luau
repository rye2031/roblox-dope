-- Summoning scrolls: the only way to get monsters.
--   Regular:   1★ 40, 2★ 34.4, 3★ 20, 4★ 4.3, 4★ Light/Dark 0.2, 5★ 1, 5★ Light/Dark 0.1 (%).
--   Legendary: 4★ 87, 4★ Light/Dark 2, 5★ 10, 5★ Light/Dark 1 (%).
--   4/5-star results are Fire/Water/Wind unless they're the Light/Dark roll; 1-3 star results
--   roll their element: Fire/Water/Wind 33 each, Light 0.5, Dark 0.5.
--   Pity: 50 Regular scrolls without a 4-star+ guarantees a Fire/Water/Wind 4★ or 5★; 200
--   scrolls without Light/Dark guarantees a 1-3 star Light/Dark. Pity never gives a 4★ or 5★
--   Light/Dark: those are only ever their own chances (and the one Eclipse Scroll).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Monsters = require(Shared.Monsters)
local PlayerData = require(script.Parent.PlayerData)
local Inventory = require(script.Parent.Inventory)
local Quests = require(script.Parent.Quests)
local Story = require(script.Parent.Story)

local T = Config.Tuning
local SC = T.Scrolls
local Summon = {}

local rng = Random.new()
local toast: RemoteEvent
local announce: RemoteEvent

-- Stars, and whether it's a 4/5-star Light/Dark outcome.
local function rollStars(kind: string, p): (number, boolean)
	local weights = {}
	for i, w in SC[kind].Stars do
		weights[i] = w
	end
	weights[6] = SC[kind].FourLD -- 6 = "4-star Light/Dark"
	weights[7] = SC[kind].FiveLD -- 7 = "5-star Light/Dark"
	if kind == "Regular" and p.pity.four + 1 >= SC.PityFourStar then
		weights = { [4] = SC.Regular.Stars[4], [5] = SC.Regular.Stars[5] }
	end
	local r = Config.pickWeighted(weights, rng:NextNumber())
	if r == 6 then
		return 4, true
	elseif r == 7 then
		return 5, true
	end
	return r, false
end

local function rollElement(p, kind: string?, stars: number, fiveLD: boolean): string
	if kind == "Eclipse" or fiveLD then
		return rng:NextNumber() < 0.5 and "Light" or "Dark"
	end
	if stars >= 4 then
		return Config.pickWeighted(SC.FiveElements, rng:NextNumber())
	end
	if p.pity.ld + 1 >= SC.PityLightDark then
		return rng:NextNumber() < 0.5 and "Light" or "Dark"
	end
	return Config.pickWeighted(SC.Elements, rng:NextNumber())
end

-- Rolls one scroll for a profile (no checks, no push). Returns the result table.
Summon.debugOdds = function(kind: string, n: number)
	-- Studio: roll n scrolls on a throwaway profile (pity off) and count outcomes
	local out = {}
	for _ = 1, n do
		local p = { pity = { four = 0, ld = 0 } }
		local stars, fiveLD = rollStars(kind, p)
		local el = rollElement(p, kind, stars, fiveLD)
		local key = stars .. ((el == "Light" or el == "Dark") and "LD" or "")
		out[key] = (out[key] or 0) + 1
	end
	return out
end

local function rollOne(p, kind: string)
	local stars, fiveLD = 5, true
	if kind ~= "Eclipse" then
		stars, fiveLD = rollStars(kind, p)
	end
	local el = rollElement(p, kind, stars, fiveLD)
	local pool = Monsters.byStars(stars)
	local sp = pool[rng:NextInteger(1, #pool)]
	p.scrolls[kind] -= 1
	p.opened += 1
	-- pity bookkeeping
	if kind == "Regular" then
		p.pity.four = stars >= 4 and 0 or p.pity.four + 1
	end
	if kind ~= "Eclipse" then
		p.pity.ld = (el == "Light" or el == "Dark") and 0 or p.pity.ld + 1
	end
	local isNew = not p.index[sp .. ":" .. el]
	local uid = Inventory.addMonster(p, sp, el)
	if not uid then
		-- storage is full: it waits in the overflow box (room was checked before rolling)
		Inventory.overflowAdd(p, sp, el)
	end
	return { uid = uid, sp = sp, el = el, stars = stars, kind = kind, new = isNew, overflow = uid == nil }
end

-- Opens `count` scrolls (1 or Scrolls.MultiOpen). Returns (ok, message, results?) where
-- results is one result for count 1, or a list for a multi-open.
function Summon.openMany(player: Player, kind: any, count: any)
	local p = PlayerData.get(player)
	if not p or (kind ~= "Regular" and kind ~= "Legendary" and kind ~= "Eclipse") then
		return false, "Unknown egg"
	end
	local n = (count == SC.MultiOpen and kind ~= "Eclipse") and SC.MultiOpen or 1
	local have = p.scrolls[kind] or 0
	if have <= 0 then
		return false, `You have no {kind} Eggs`
	end
	if have < n then
		return false, `You need {n} {kind} Eggs (you have {have})`
	end
	local room = (p.storageCap - Inventory.count(p)) + (T.OverflowCap - Inventory.overflowCount(p))
	if room < n then
		return false, `Storage and overflow are full ({room} spaces left). Sell or train monsters first`
	end
	local results = {}
	for _ = 1, n do
		table.insert(results, rollOne(p, kind))
	end
	Quests.progress(player, "Summon", n)
	Story.event(player, "summon", { n = n })
	if n == SC.MultiOpen then
		Story.event(player, "multi")
	end
	PlayerData.push(player)
	PlayerData.saveSoon(player)
	for _, r in results do
		if r.stars >= 5 then
			-- everyone in the server sees it in the chat area; hovering the name shows the element
			announce:FireAllClients({ name = player.DisplayName, user = player.UserId, sp = r.sp, el = r.el, stars = r.stars, kind = kind })
		end
		if r.el == "Light" or r.el == "Dark" then
			for _, other in Players:GetPlayers() do
				toast:FireClient(other, `{player.DisplayName} summoned a {r.el} {Monsters.Species[r.sp].Name}!`, "good")
			end
		end
	end
	if n == 1 then
		return true, "ok", results[1]
	end
	return true, "ok", results
end

function Summon.open(player: Player, kind: any)
	return Summon.openMany(player, kind, 1)
end

function Summon.init(r)
	toast = r.Toast
	announce = r.Announce
end

return Summon

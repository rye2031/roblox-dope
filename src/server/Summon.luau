-- Summoning scrolls: the only way to get monsters.
--   Regular:   1-5 stars (40/35/20/4.5/0.5). Legendary: 4-5 stars (92/8).
--   Element is rolled after the star: Fire/Water/Wind 33 each, Light 0.5, Dark 0.5.
--   Pity: 50 Regular scrolls without a 4-star+ guarantees one; 200 scrolls without
--   Light/Dark guarantees one.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Monsters = require(Shared.Monsters)
local PlayerData = require(script.Parent.PlayerData)
local Inventory = require(script.Parent.Inventory)
local Quests = require(script.Parent.Quests)

local T = Config.Tuning
local SC = T.Scrolls
local Summon = {}

local rng = Random.new()
local toast: RemoteEvent
local announce: RemoteEvent

local function rollStars(kind: string, p): number
	local weights = {}
	for i, w in SC[kind].Stars do
		weights[i] = w
	end
	if kind == "Regular" and p.pity.four + 1 >= SC.PityFourStar then
		weights = { [4] = SC.Regular.Stars[4], [5] = SC.Regular.Stars[5] }
	end
	return Config.pickWeighted(weights, rng:NextNumber())
end

local function rollElement(p): string
	if p.pity.ld + 1 >= SC.PityLightDark then
		return rng:NextNumber() < 0.5 and "Light" or "Dark"
	end
	return Config.pickWeighted(SC.Elements, rng:NextNumber())
end

-- Rolls one scroll for a profile (no checks, no push). Returns the result table.
local function rollOne(p, kind: string)
	local stars = rollStars(kind, p)
	local el = rollElement(p)
	local pool = Monsters.byStars(stars)
	local sp = pool[rng:NextInteger(1, #pool)]
	p.scrolls[kind] -= 1
	p.opened += 1
	-- pity bookkeeping
	if kind == "Regular" then
		p.pity.four = stars >= 4 and 0 or p.pity.four + 1
	end
	p.pity.ld = (el == "Light" or el == "Dark") and 0 or p.pity.ld + 1
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
	if not p or (kind ~= "Regular" and kind ~= "Legendary") then
		return false, "Unknown scroll"
	end
	local n = count == SC.MultiOpen and SC.MultiOpen or 1
	local have = p.scrolls[kind] or 0
	if have <= 0 then
		return false, `You have no {kind} scrolls`
	end
	if have < n then
		return false, `You need {n} {kind} scrolls (you have {have})`
	end
	local room = (p.storageCap - Inventory.count(p)) + (T.OverflowCap - Inventory.overflowCount(p))
	if room < n then
		return false, `Storage and overflow are full ({room} spaces left). Sell or feed monsters first`
	end
	local results = {}
	for _ = 1, n do
		table.insert(results, rollOne(p, kind))
	end
	Quests.progress(player, "Summon", n)
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

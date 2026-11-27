-- Daily quests + login streak. Quests roll per player at 00:00 UTC (3 a day: easy, medium,
-- hard), progress from gameplay events, and are claimed with a button. The streak pays a
-- 7-day reward track once per UTC day; missing a day starts it again at day 1.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local PlayerData = require(script.Parent.PlayerData)

local Q = Config.Tuning.Quests
local Quests = {}

local toastRemote: RemoteEvent

local reward = Config.questReward

local function valid(def, p, tier: number): boolean
	if def.Tiers and not table.find(def.Tiers, tier) then
		return false
	end
	if def.NeedsBoss and not p.bosses[def.NeedsBoss] then
		return false
	end
	if def.MinMonsters then
		local n = 0
		for _ in p.monsters do
			n += 1
		end
		if n < def.MinMonsters then
			return false
		end
	end
	return true
end

local function roll(player: Player, p, day: number)
	local rng = Random.new(player.UserId * 7919 + day)
	local quests, used = {}, {}
	for tier = 1, 3 do
		local options = {}
		for _, def in Q.Pool do
			if not used[def.Id] and valid(def, p, tier) then
				table.insert(options, def)
			end
		end
		if #options > 0 then
			local def = options[rng:NextInteger(1, #options)]
			used[def.Id] = true
			table.insert(quests, { k = def.Id, n = def.Targets[tier], p = 0, t = tier, c = false })
		end
	end
	p.daily = { day = day, quests = quests, bonus = false }
end

function Quests.streakPreview(p): (number, boolean)
	return Config.streakPreview(p, Config.today())
end

-- New day? Reroll quests. Returns true if anything changed.
function Quests.ensure(player: Player): boolean
	local p = PlayerData.get(player)
	if not p then
		return false
	end
	local today = Config.today()
	local changed = false
	if p.daily.day ~= today then
		roll(player, p, today)
		changed = true
	end
	local _, ready = Quests.streakPreview(p)
	player:SetAttribute("StreakReady", ready)
	local claimable = 0
	for _, q in p.daily.quests do
		if q.p >= q.n and not q.c then
			claimable += 1
		end
	end
	player:SetAttribute("QuestsClaimable", claimable)
	return changed
end

-- Gameplay progress. kind matches a quest id; amount defaults to 1.
function Quests.progress(player: Player, kind: string, amount: number?)
	local p = PlayerData.get(player)
	if not p then
		return
	end
	if Quests.ensure(player) then
		PlayerData.push(player)
	end
	local any = false
	for _, q in p.daily.quests do
		if q.k == kind and q.p < q.n then
			q.p = math.min(q.n, q.p + (amount or 1))
			any = true
			if q.p >= q.n then
				toastRemote:FireClient(player, "Quest done: " .. Config.questText(q.k, q.n) .. ". Claim it in Quests!", "good")
			end
		end
	end
	if any then
		Quests.ensure(player)
		PlayerData.push(player)
	end
end

-- A wild monster this player helped defeat.
function Quests.onKill(player: Player, element: string, elite: boolean?)
	Quests.progress(player, "Defeat")
	if element == "Fire" or element == "Water" or element == "Wind" then
		Quests.progress(player, "Defeat" .. element)
	end
	if elite then
		Quests.progress(player, "Elite")
	end
end

function Quests.claim(player: Player, index: any): (boolean, string)
	local p = PlayerData.get(player)
	if not p then
		return false, "No profile"
	end
	Quests.ensure(player)
	if index == "bonus" then
		for _, q in p.daily.quests do
			if not q.c then
				return false, "Finish all three quests first"
			end
		end
		if p.daily.bonus or #p.daily.quests == 0 then
			return false, "Already claimed"
		end
		p.daily.bonus = true
		local n = Config.questBonus(p)
		local sc = Config.Tuning.Quests.AllBonusScrolls
		p.coins += n
		p.scrolls.Regular += sc
		PlayerData.push(player)
		PlayerData.saveSoon(player)
		return true, `All quests done! +{n} coins and {sc} Regular scrolls`
	end
	local q = typeof(index) == "number" and p.daily.quests[index]
	if not q then
		return false, "No such quest"
	end
	if q.c then
		return false, "Already claimed"
	end
	if q.p < q.n then
		return false, "Not finished yet"
	end
	q.c = true
	local n = reward(p, q.t)
	local sc = Config.questScrolls(q.t)
	p.coins += n
	p.scrolls.Regular += sc
	Quests.ensure(player)
	PlayerData.push(player)
	PlayerData.saveSoon(player)
	local extra = sc > 0 and string.format(" and %d Regular scroll%s", sc, sc > 1 and "s" or "") or ""
	return true, `Quest reward: +{n} coins{extra}`
end

function Quests.claimStreak(player: Player): (boolean, string)
	local p = PlayerData.get(player)
	if not p then
		return false, "No profile"
	end
	local day, ready = Quests.streakPreview(p)
	if not ready then
		return false, "Come back tomorrow for the next reward"
	end
	p.streak = { last = Config.today(), count = day }
	local n = Config.streakReward(day)
	p.coins += n
	local sc = Config.streakScrolls(day)
	p.scrolls.Regular += sc
	Quests.ensure(player)
	PlayerData.push(player)
	PlayerData.saveSoon(player)
	local extra = sc > 0 and string.format(" and %d Regular scroll%s", sc, sc > 1 and "s" or "") or ""
	return true, `Day {day} reward: +{n} coins{extra}`
end

function Quests.init(r)
	toastRemote = r.Toast
	-- day rollover for players who stay online past midnight UTC
	task.spawn(function()
		while true do
			task.wait(30)
			for _, player in Players:GetPlayers() do
				if Quests.ensure(player) then
					PlayerData.push(player)
					toastRemote:FireClient(player, "New day: fresh quests and a login reward!", "info")
				end
			end
		end
	end)
end

return Quests

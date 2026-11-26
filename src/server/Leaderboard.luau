-- Global "Top Keepers" leaderboards in OrderedDataStores (Studio uses its own _Studio stores so
-- tests never touch the real boards):
--   Overtime: overtime * 1e7 + rescues (Overtime first, rescues break ties)
--   Rescues:  total rescues
-- Scores are submitted every minute and when a player leaves (only for real, cloud-saved
-- profiles). The top 10 of each is published as JSON in ReplicatedStorage.Leaderboard.
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local DataStoreService = game:GetService("DataStoreService")
local UserService = game:GetService("UserService")

local PlayerData = require(script.Parent.PlayerData)
local Persistence = require(script.Parent.Persistence)

local Leaderboard = {}

local SUFFIX = "_v1" .. (RunService:IsStudio() and "_Studio" or "")
local REFRESH = 60
local TOP = 10

local stores: { [string]: OrderedDataStore } = {}
local lastSent: { [number]: { [string]: number } } = {}
local names: { [number]: string } = {}
local published: StringValue

local function scores(p): { [string]: number }
	local r = math.min(p.rescues, 9999999)
	return { Overtime = p.overtime * 10000000 + r, Rescues = r }
end

-- Submit one player's scores (only values that changed since the last submit).
function Leaderboard.submit(userId: number, p, cloud: boolean)
	if not cloud or not p or not stores.Rescues then
		return
	end
	local sc = scores(p)
	local sent = lastSent[userId] or {}
	lastSent[userId] = sent
	for board, value in sc do
		local eligible = value > 0 and (board ~= "Overtime" or p.overtime > 0)
		if sent[board] ~= value and eligible then
			local ok = pcall(function()
				stores[board]:SetAsync(tostring(userId), value)
			end)
			if ok then
				sent[board] = value
			end
		end
	end
end

local function resolveNames(ids: { number })
	local missing = {}
	for _, id in ids do
		if not names[id] then
			local plr = Players:GetPlayerByUserId(id)
			if plr then
				names[id] = plr.DisplayName
			else
				table.insert(missing, id)
			end
		end
	end
	if #missing > 0 then
		local ok, infos = pcall(function()
			return UserService:GetUserInfosByUserIdsAsync(missing)
		end)
		if ok and infos then
			for _, info in infos do
				names[info.Id] = info.DisplayName
			end
		end
		for _, id in missing do
			names[id] = names[id] or ("Keeper " .. id % 10000)
		end
	end
end

function Leaderboard.refresh()
	if not stores.Rescues then
		return
	end
	local out = { updated = os.time(), Overtime = {}, Rescues = {} }
	local ids = {}
	local raw = {}
	for board, store in stores do
		local ok, page = pcall(function()
			return store:GetSortedAsync(false, TOP):GetCurrentPage()
		end)
		raw[board] = ok and page or {}
		for _, e in raw[board] do
			table.insert(ids, tonumber(e.key))
		end
	end
	resolveNames(ids)
	for board, list in raw do
		for _, e in list do
			local id = tonumber(e.key) :: number
			if board == "Overtime" then
				table.insert(out.Overtime, { id = id, n = names[id], ot = e.value // 10000000, r = e.value % 10000000 })
			else
				table.insert(out.Rescues, { id = id, n = names[id], r = e.value })
			end
		end
	end
	published.Value = HttpService:JSONEncode(out)
end

local function submitAll()
	for _, player in Players:GetPlayers() do
		Leaderboard.submit(player.UserId, PlayerData.get(player), player:GetAttribute("SaveMode") == "Cloud")
	end
end

function Leaderboard.init()
	published = Instance.new("StringValue")
	published.Name = "Leaderboard"
	published.Value = "{}"
	published.Parent = ReplicatedStorage
	if not Persistence.available then
		return -- no DataStores (e.g. Studio without API access): the board stays empty
	end
	for _, board in { "Overtime", "Rescues" } do
		local ok, store = pcall(function()
			return DataStoreService:GetOrderedDataStore("Leaderboard_" .. board .. SUFFIX)
		end)
		if ok then
			stores[board] = store
		end
	end
	task.spawn(function()
		task.wait(8)
		while true do
			submitAll()
			Leaderboard.refresh()
			task.wait(REFRESH)
		end
	end)
end

-- Called just before a player's profile is released.
function Leaderboard.onLeave(player: Player)
	local p = PlayerData.get(player)
	if p then
		local cloud = player:GetAttribute("SaveMode") == "Cloud"
		local snapshot = { rescues = p.rescues, overtime = p.overtime }
		task.spawn(Leaderboard.submit, player.UserId, snapshot, cloud)
	end
	lastSent[player.UserId] = nil
end

return Leaderboard

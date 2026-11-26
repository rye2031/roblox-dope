-- Timed events that keep a session interesting:
--   Snack Rush: every 15 min (UTC-aligned) one wing gets 2 minutes where every creature grabbed
--     there banks as Glazed or Jumbo and sleepers respawn fast.
--   Wanted poster: each UTC hour every wing has one Wanted creature (sometimes "Glazed or
--     better") that pays 3x coins, so the poster always shows something you can reach.
-- State is published as workspace attributes so clients can show countdowns:
--   RushWing / RushUntil / RushNextAt, WantedSpecies_<wing> / WantedForm_<wing> / WantedUntil.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Creatures = require(ReplicatedStorage.Shared.Creatures)

local E = Config.Tuning.Events
local Events = {}

local remotes
local PlayerData -- set in init (avoids a require cycle with modules that require Events)
local rush = { wing = nil :: string?, untilT = 0, startedAt = -1 }
local forced = { rushUntil = 0, rushWing = nil :: string?, wanted = {} :: { [string]: { s: string, f: string } } }
local wantedHour = -1

local function now(): number
	return workspace:GetServerTimeNow()
end

function Events.rushActive(wing: string): boolean
	return rush.wing == wing and now() < rush.untilT
end

function Events.wanted(wing: string): (string?, string?)
	return workspace:GetAttribute("WantedSpecies_" .. wing), workspace:GetAttribute("WantedForm_" .. wing)
end

-- Wings someone in the server can play right now (the Food Court always counts).
local function openWings(): { string }
	local seen, list = { FoodCourt = true }, { "FoodCourt" }
	for _, player in Players:GetPlayers() do
		local p = PlayerData and PlayerData.get(player)
		if p then
			for id in p.wings do
				if not seen[id] then
					seen[id] = true
					table.insert(list, id)
				end
			end
		end
	end
	return list
end

local function startRush(wing: string, untilT: number)
	rush.wing = wing
	rush.untilT = untilT
	workspace:SetAttribute("RushWing", wing)
	workspace:SetAttribute("RushUntil", untilT)
	local w = Config.Wings[wing]
	for _, player in Players:GetPlayers() do
		local p = PlayerData and PlayerData.get(player)
		if p and p.wings[wing] then
			remotes.Toast:FireClient(player, `SNACK RUSH in the {w.Name}! Everything there is Glazed or better for 2 minutes`, "good")
		end
	end
	remotes.Fx:FireAllClients("RushStart", Vector3.zero, wing)
end

local function endRush()
	rush.wing = nil
	workspace:SetAttribute("RushWing", nil)
end

local function pickWanted(hour: number, wing: string): (string, string)
	local rng = Random.new(hour * 31337 + Config.Wings[wing].Order * 101)
	local pool = {}
	for _, famId in Config.Wings[wing].Families do
		for _, id in Creatures.Families[famId].Common do
			table.insert(pool, id)
		end
	end
	table.sort(pool) -- stable order so every server picks the same creature
	local species = pool[rng:NextInteger(1, #pool)]
	local form = rng:NextNumber() < E.WantedFancyChance and "Fancy" or "Any"
	return species, form
end

local function wantedText(wing: string): string
	local sp, form = Events.wanted(wing)
	if not sp then
		return ""
	end
	return `{form == "Fancy" and "a Glazed or Jumbo " or ""}{Creatures.Species[sp].Name}`
end

-- Tell each player about the poster for the deepest wing they've opened.
local function announceWanted()
	for _, player in Players:GetPlayers() do
		local p = PlayerData and PlayerData.get(player)
		local best = "FoodCourt"
		if p then
			for _, w in Config.wingList() do
				if p.wings[w.Id] then
					best = w.Id
				end
			end
		end
		remotes.Toast:FireClient(player, `New Wanted poster: {wantedText(best)} pays {E.WantedMult}x coins this hour!`, "info")
	end
end

local function step()
	local t = now()
	-- Snack Rush
	local k = t // E.RushEvery
	local start = k * E.RushEvery
	workspace:SetAttribute("RushNextAt", (k + 1) * E.RushEvery)
	if forced.rushUntil > t then
		if rush.wing ~= forced.rushWing then
			startRush(forced.rushWing :: string, forced.rushUntil)
		end
	elseif t - start < E.RushLength then
		if rush.startedAt ~= start then
			rush.startedAt = start
			local wings = openWings()
			startRush(wings[math.random(1, #wings)], start + E.RushLength)
		end
	elseif rush.wing then
		endRush()
	end
	-- Wanted posters (one per wing)
	local hour = t // 3600
	if hour ~= wantedHour then
		local first = wantedHour < 0
		wantedHour = hour
		for wing in Config.Wings do
			local sp, f = pickWanted(hour, wing)
			workspace:SetAttribute("WantedSpecies_" .. wing, sp)
			workspace:SetAttribute("WantedForm_" .. wing, f)
		end
		workspace:SetAttribute("WantedUntil", (hour + 1) * 3600)
		if not first then
			announceWanted()
		end
	end
	for wing, w in forced.wanted do
		workspace:SetAttribute("WantedSpecies_" .. wing, w.s)
		workspace:SetAttribute("WantedForm_" .. wing, w.f)
	end
end

function Events.init(r, playerData)
	remotes = r
	PlayerData = playerData
	step()
	task.spawn(function()
		while true do
			task.wait(1)
			step()
		end
	end)
end

-- Test hooks
function Events.forceRush(wing: string?, seconds: number?)
	if wing then
		forced.rushWing = wing
		forced.rushUntil = now() + (seconds or E.RushLength)
	else
		forced.rushUntil = 0
		endRush()
	end
	step()
end

function Events.forceWanted(species: string?, form: string?)
	if species then
		forced.wanted[Creatures.Species[species].Wing] = { s = species, f = form or "Any" }
	else
		forced.wanted = {}
		wantedHour = -1
	end
	step()
end

return Events

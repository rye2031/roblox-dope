-- Player progress: loaded from / saved to a DataStore through Persistence (session-locked),
-- with a session-only fallback when DataStores are unavailable (e.g. Studio without API access).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Creatures = require(Shared.Creatures)
local Persistence = require(script.Parent.Persistence)

local PlayerData = {}

export type Profile = {
	coins: number,
	collection: { [string]: { count: number, forms: { [string]: boolean } } },
	upgrades: { [string]: boolean },
	tracks: { [string]: number }, -- upgrade track levels (Sneakers, SteadyHands)
	wings: { [string]: boolean }, -- unlocked wings
	evo: { [string]: number }, -- evolution progress by target species
	buddy: string?,
	rescues: number,
}

type Meta = {
	cloud: boolean, -- true when this session owns the saved profile and may write it
	dirty: boolean,
	saveQueued: boolean,
	leaving: boolean,
}

local profiles: { [Player]: Profile } = {}
local meta: { [Player]: Meta } = {}
local remote: RemoteEvent
local activeSaves = 0

local function defaults(): Profile
	return {
		coins = 0,
		collection = {},
		upgrades = {},
		tracks = { Sneakers = 0, SteadyHands = 0 },
		wings = { FoodCourt = true },
		evo = {},
		buddy = nil,
		rescues = 0,
	}
end

local function int(v: any, min: number): number
	if typeof(v) ~= "number" or v ~= v then
		return min
	end
	return math.max(min, math.floor(v))
end

-- Turn whatever came out of the DataStore into a valid profile (unknown species, items or
-- forms are dropped, numbers are clamped), so a bad or old record can't break the game.
function PlayerData.sanitize(raw: any): Profile
	local p = defaults()
	if typeof(raw) ~= "table" then
		return p
	end
	p.coins = int(raw.coins, 0)
	p.rescues = int(raw.rescues, 0)
	if typeof(raw.tracks) == "table" then
		for id, def in Config.Tuning.Tracks do
			p.tracks[id] = math.min(#def.Costs, int(raw.tracks[id], 0))
		end
	end
	if typeof(raw.wings) == "table" then
		for id in Config.Wings do
			if raw.wings[id] == true then
				p.wings[id] = true
			end
		end
	end
	if typeof(raw.evo) == "table" then
		for _, e in Config.Tuning.Evolutions do
			local n = int(raw.evo[e.To], 0)
			if n > 0 then
				p.evo[e.To] = math.min(n, e.Needed)
			end
		end
	end
	-- schema 1 records kept King Rangoon progress in ventRescues
	if raw.ventRescues ~= nil and p.evo.KingRangoon == nil then
		local n = int(raw.ventRescues, 0)
		if n > 0 then
			p.evo.KingRangoon = math.min(n, 3)
		end
	end
	local validForms = {}
	for _, f in Config.Tuning.Forms do
		validForms[f.Id] = true
	end
	if typeof(raw.collection) == "table" then
		for id, entry in raw.collection do
			if Creatures.Species[id] and typeof(entry) == "table" then
				local forms = {}
				if typeof(entry.forms) == "table" then
					for form, has in entry.forms do
						if validForms[form] and has == true then
							forms[form] = true
						end
					end
				end
				p.collection[id] = { count = math.max(1, int(entry.count, 1)), forms = forms }
			end
		end
	end
	if typeof(raw.upgrades) == "table" then
		for item, has in raw.upgrades do
			if Config.Tuning.Shop[item] and has == true then
				p.upgrades[item] = true
			end
		end
	end
	if typeof(raw.buddy) == "string" and p.collection[raw.buddy] then
		p.buddy = raw.buddy
	end
	return p
end

-- Plain copy for the DataStore (only the fields we own).
function PlayerData.serialize(p: Profile)
	local collection = {}
	for id, e in p.collection do
		local forms = {}
		for f, has in e.forms do
			forms[f] = has
		end
		collection[id] = { count = e.count, forms = forms }
	end
	local upgrades = {}
	for k, v in p.upgrades do
		upgrades[k] = v
	end
	local tracks, wings, evo = {}, {}, {}
	for k, v in p.tracks do
		tracks[k] = v
	end
	for k, v in p.wings do
		wings[k] = v
	end
	for k, v in p.evo do
		evo[k] = v
	end
	return {
		coins = p.coins,
		collection = collection,
		upgrades = upgrades,
		tracks = tracks,
		wings = wings,
		evo = evo,
		buddy = p.buddy,
		rescues = p.rescues,
	}
end

local function setSaveStatus(player: Player, mode: string)
	player:SetAttribute("SaveMode", mode) -- Loading | Cloud | Session | Failed
	if mode == "Cloud" then
		player:SetAttribute("LastSave", workspace:GetServerTimeNow())
	end
end

local function saveNow(player: Player, release: boolean?): boolean
	local p, m = profiles[player], meta[player]
	if not p or not m or not m.cloud then
		return false
	end
	activeSaves += 1
	m.dirty = false
	local ok = Persistence.save(player.UserId, PlayerData.serialize(p), release)
	activeSaves -= 1
	if ok then
		if player.Parent then
			setSaveStatus(player, "Cloud")
		end
	else
		m.dirty = true
		if player.Parent then
			player:SetAttribute("SaveMode", "Retrying")
		end
	end
	return ok
end

-- Save soon after an important change (purchase, new creature, evolution); coalesces bursts.
function PlayerData.saveSoon(player: Player)
	local m = meta[player]
	if not m or not m.cloud or m.saveQueued then
		return
	end
	m.saveQueued = true
	task.delay(3, function()
		m.saveQueued = false
		if profiles[player] and not m.leaving then
			saveNow(player)
		end
	end)
end

function PlayerData.init(profileRemote: RemoteEvent)
	remote = profileRemote
	Persistence.init()
	-- autosave
	task.spawn(function()
		while true do
			task.wait(Persistence.AUTOSAVE_INTERVAL)
			for player, m in meta do
				if m.cloud and m.dirty and not m.leaving then
					task.spawn(saveNow, player)
				end
			end
		end
	end)
	-- server shutdown: final save for everyone, then wait for writes to finish
	game:BindToClose(function()
		for _, player in Players:GetPlayers() do
			task.spawn(PlayerData.leave, player)
		end
		local deadline = os.clock() + 25
		task.wait(0.1)
		while activeSaves > 0 and os.clock() < deadline do
			task.wait(0.2)
		end
	end)
end

local function makeLeaderstats(player: Player)
	local old = player:FindFirstChild("leaderstats")
	if old then
		old:Destroy()
	end
	local ls = Instance.new("Folder")
	ls.Name = "leaderstats"
	local coins = Instance.new("IntValue")
	coins.Name = "Coins"
	coins.Parent = ls
	local found = Instance.new("IntValue")
	found.Name = "Found"
	found.Parent = ls
	ls.Parent = player
end

-- Loads (or creates) the player's profile. Yields while the DataStore answers.
function PlayerData.join(player: Player): Profile?
	setSaveStatus(player, "Loading")
	local cloud = false
	local data = nil
	if Persistence.available then
		local ok, loaded = Persistence.load(player.UserId)
		cloud = ok
		data = loaded
		if not ok then
			setSaveStatus(player, "Failed")
		end
	end
	if not player.Parent then
		-- left while loading
		if cloud then
			Persistence.release(player.UserId)
		end
		return nil
	end
	local p = PlayerData.sanitize(data)
	profiles[player] = p
	meta[player] = { cloud = cloud, dirty = false, saveQueued = false, leaving = false }
	makeLeaderstats(player)
	if cloud then
		setSaveStatus(player, "Cloud")
	elseif player:GetAttribute("SaveMode") ~= "Failed" then
		setSaveStatus(player, "Session")
	end
	return p
end

-- Final save + lock release. Safe to call more than once.
function PlayerData.leave(player: Player)
	local m = meta[player]
	if not m or m.leaving then
		return
	end
	m.leaving = true
	if m.cloud then
		saveNow(player, true)
	end
	profiles[player] = nil
	meta[player] = nil
end

function PlayerData.get(player: Player): Profile?
	return profiles[player]
end


function PlayerData.speciesFound(p: Profile): number
	local n = 0
	for _ in p.collection do
		n += 1
	end
	return n
end

function PlayerData.push(player: Player)
	local p = profiles[player]
	if not p then
		return
	end
	local m = meta[player]
	if m then
		m.dirty = true
	end
	local ls = player:FindFirstChild("leaderstats")
	if ls then
		ls.Coins.Value = p.coins
		ls.Found.Value = PlayerData.speciesFound(p)
	end
	player:SetAttribute("Buddy", p.buddy)
	player:SetAttribute("PaddedShoes", p.upgrades.PaddedShoes == true)
	player:SetAttribute("Sneakers", p.tracks.Sneakers)
	player:SetAttribute("SteadyHands", p.tracks.SteadyHands)
	-- highest unlocked wing decides which gates the character passes through
	local top = nil
	for _, w in Config.wingList() do
		if p.wings[w.Id] and w.Price > 0 then
			top = w.Id
		end
	end
	player:SetAttribute("PassWing", top)
	if PlayerData.onPush then
		PlayerData.onPush(player)
	end
	remote:FireClient(player, p)
end

-- Adds a creature to the collection. Returns true if the species is new.
function PlayerData.record(p: Profile, species: string, form: string): boolean
	local entry = p.collection[species]
	local isNew = entry == nil
	if not entry then
		entry = { count = 0, forms = {} }
		p.collection[species] = entry
	end
	entry.count += 1
	entry.forms[form] = true
	return isNew
end

-- Buys a shop item, the next level of an upgrade track, or a wing unlock.
function PlayerData.buy(player: Player, item: string): (boolean, string)
	local p = profiles[player]
	if not p or typeof(item) ~= "string" then
		return false, "Unknown item"
	end
	local track = Config.Tuning.Tracks[item]
	if track then
		local lvl = p.tracks[item] or 0
		local price = track.Costs[lvl + 1]
		if not price then
			return false, `{track.Name} is maxed out`
		end
		if p.coins < price then
			return false, `Need {price - p.coins} more coins`
		end
		p.coins -= price
		p.tracks[item] = lvl + 1
		PlayerData.push(player)
		PlayerData.saveSoon(player)
		return true, `{track.Name} level {lvl + 1}!`
	end
	local wing = Config.Wings[item]
	if wing then
		if p.wings[item] then
			return false, `{wing.Name} is already open`
		end
		for _, w in Config.wingList() do
			if w.Order < wing.Order and not p.wings[w.Id] then
				return false, `Unlock {w.Name} first`
			end
		end
		if p.coins < wing.Price then
			return false, `Need {wing.Price - p.coins} more coins`
		end
		p.coins -= wing.Price
		p.wings[item] = true
		PlayerData.push(player)
		PlayerData.saveSoon(player)
		return true, `{wing.Name} unlocked! Walk through the gate`
	end
	local def = Config.Tuning.Shop[item]
	if not def then
		return false, "Unknown item"
	end
	if p.upgrades[item] then
		return false, "Already owned"
	end
	if p.coins < def.Price then
		return false, `Need {def.Price - p.coins} more coins`
	end
	p.coins -= def.Price
	p.upgrades[item] = true
	PlayerData.push(player)
	PlayerData.saveSoon(player)
	return true, `{def.Name} equipped!`
end

function PlayerData.equip(player: Player, species: string?): (boolean, string)
	local p = profiles[player]
	if not p then
		return false, "No profile"
	end
	if species == nil then
		p.buddy = nil
		PlayerData.push(player)
		return true, "Buddy unequipped"
	end
	if typeof(species) ~= "string" or not Creatures.Species[species] then
		return false, "Unknown creature"
	end
	if not p.collection[species] then
		return false, "You haven't rescued one yet"
	end
	p.buddy = species
	PlayerData.push(player)
	return true, `{Creatures.Species[species].Name} is your buddy!`
end

return PlayerData

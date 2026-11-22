-- Session-only player progress (the place is unpublished, so no DataStore).
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Creatures = require(Shared.Creatures)

local PlayerData = {}

export type Profile = {
	coins: number,
	collection: { [string]: { count: number, forms: { [string]: boolean } } },
	upgrades: { [string]: boolean },
	buddy: string?,
	ventRescues: number,
	rescues: number,
}

local profiles: { [Player]: Profile } = {}
local remote: RemoteEvent

function PlayerData.init(profileRemote: RemoteEvent)
	remote = profileRemote
end

function PlayerData.create(player: Player): Profile
	local p: Profile = {
		coins = 0,
		collection = {},
		upgrades = {},
		buddy = nil,
		ventRescues = 0,
		rescues = 0,
	}
	profiles[player] = p
	local ls = Instance.new("Folder")
	ls.Name = "leaderstats"
	local coins = Instance.new("IntValue")
	coins.Name = "Coins"
	coins.Parent = ls
	local found = Instance.new("IntValue")
	found.Name = "Found"
	found.Parent = ls
	ls.Parent = player
	return p
end

function PlayerData.get(player: Player): Profile?
	return profiles[player]
end

function PlayerData.remove(player: Player)
	profiles[player] = nil
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
	local ls = player:FindFirstChild("leaderstats")
	if ls then
		ls.Coins.Value = p.coins
		ls.Found.Value = PlayerData.speciesFound(p)
	end
	player:SetAttribute("Buddy", p.buddy)
	player:SetAttribute("PaddedShoes", p.upgrades.PaddedShoes == true)
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

function PlayerData.buy(player: Player, item: string): (boolean, string)
	local p = profiles[player]
	local def = Config.Tuning.Shop[item]
	if not p or not def then
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

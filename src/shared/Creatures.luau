-- Creature species. Families are what players see in the field; the exact species and form
-- are revealed at the hideout.
local Creatures = {}

Creatures.Species = {
	CrabRangoon = {
		Id = "CrabRangoon",
		Name = "Crab Rangoon",
		Family = "Dumpling",
		Color = Color3.fromRGB(232, 168, 64),
		Accent = Color3.fromRGB(255, 120, 170),
		Height = 3.2, -- studs, Normal form
		Mesh = "CrabRangoon",
		Blurb = "Grumpy. Pinches. Can pry open vents.",
		Ability = "Vent",
		Order = 1,
	},
	Crocsquatch = {
		Id = "Crocsquatch",
		Name = "Crocsquatch",
		Family = "Clog",
		Color = Color3.fromRGB(120, 230, 180),
		Accent = Color3.fromRGB(255, 255, 255),
		Height = 3.2,
		Mesh = "Crocsquatch",
		Blurb = "Squeaks when it runs. Smells like the beach.",
		Order = 2,
	},
	MallGobstopper = {
		Id = "MallGobstopper",
		Name = "Mall Gobstopper",
		Family = "Candy",
		Color = Color3.fromRGB(255, 90, 120),
		Accent = Color3.fromRGB(255, 220, 60),
		Height = 2.8,
		Mesh = "MallGobstopper",
		Blurb = "Rolls away the second you blink.",
		Rolls = true,
		Order = 3,
	},
	KingRangoon = {
		Id = "KingRangoon",
		Name = "King Rangoon",
		Family = "Dumpling",
		Color = Color3.fromRGB(255, 200, 60),
		Accent = Color3.fromRGB(255, 120, 170),
		Height = 4.0,
		Mesh = "KingRangoon",
		Blurb = "Crowned by a crumpled carton. Evolves from Crab Rangoon.",
		Ability = "Vent",
		EvolvesFrom = "CrabRangoon",
		Order = 4,
	},
}

Creatures.Families = {
	Dumpling = { Name = "Dumpling", Color = Color3.fromRGB(232, 168, 64), Common = { "CrabRangoon" } },
	Clog = { Name = "Clog", Color = Color3.fromRGB(120, 230, 180), Common = { "Crocsquatch" } },
	Candy = { Name = "Candy", Color = Color3.fromRGB(255, 90, 120), Common = { "MallGobstopper" } },
}

-- What a rare sleeper can turn out to be (weights).
Creatures.RarePool = {
	{ Species = "KingRangoon", Weight = 50 },
	{ Species = "CrabRangoon", Weight = 20 },
	{ Species = "Crocsquatch", Weight = 15 },
	{ Species = "MallGobstopper", Weight = 15 },
}

Creatures.FormColor = {
	Normal = nil,
	Glazed = Color3.fromRGB(255, 240, 160),
	Jumbo = nil,
}

Creatures.FormScale = { Normal = 1, Glazed = 1, Jumbo = 1.45 }

function Creatures.ordered()
	local list = {}
	for _, s in Creatures.Species do
		table.insert(list, s)
	end
	table.sort(list, function(a, b)
		return a.Order < b.Order
	end)
	return list
end

return Creatures

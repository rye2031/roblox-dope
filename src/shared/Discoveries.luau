-- Hidden discoveries (2026-11-27, owner: more character, reward wandering). Each landmark
-- hides a spot; standing on it the first time gives a small reward and fills its line in the
-- Index. Finding them all gives a Legendary scroll. y is the height of the spot (some are up
-- a tree, on a crater rim or on a sky island).
local Discoveries = {}

Discoveries.List = {
	{ id = "elder_top", region = "SproutMeadow", name = "Elder Tree Crown", hint = "Climb the giant tree in Sprout Meadow", pos = Vector3.new(175, 56, 210), coins = 250 },
	{ id = "old_mill", region = "SproutMeadow", name = "The Old Mill", hint = "Something is tucked behind the windmill", pos = Vector3.new(-110, 3, 312), coins = 200 },
	{ id = "crater", region = "EmberCanyon", name = "Volcano Crater", hint = "Climb the volcano in Ember Canyon", pos = Vector3.new(689, 63, 300), coins = 400 },
	{ id = "lava_bridge", region = "EmberCanyon", name = "Lava Bridge", hint = "Cross the river of lava", pos = Vector3.new(590, 7, 250), coins = 300 },
	{ id = "wreck", region = "TideCoast", name = "Shipwreck Hold", hint = "Look inside the wreck on the beach", pos = Vector3.new(-592, 4, 250), coins = 400 },
	{ id = "sea_arch", region = "TideCoast", name = "Sea Arch", hint = "Stand on top of the arch in the sea", pos = Vector3.new(-662, 36, 470), coins = 450 },
	{ id = "sky_bridge", region = "GaleHighlands", name = "Sky Bridge", hint = "Ride the wind up to the floating islands", pos = Vector3.new(5, 33, -420), coins = 500 },
	{ id = "cliff_mill", region = "GaleHighlands", name = "Cliff Windmill", hint = "A windmill stands on a bluff", pos = Vector3.new(-200, 22, -152), coins = 450 },
	{ id = "temple", region = "TwilightVale", name = "Temple of Sun and Moon", hint = "Enter the temple on the seam of light and dark", pos = Vector3.new(620, 5, -332), coins = 600 },
	{ id = "crystal_grove", region = "TwilightVale", name = "Crystal Grove", hint = "Deep in the Gloamwood, the crystals sing", pos = Vector3.new(312, 3, -556), coins = 600 },
	{ id = "titan_stone", region = "Haven", name = "The Last Titan Stone", hint = "One stone at the Titan Field is different", pos = Vector3.new(170, 3, 32), coins = 300 },
}
Discoveries.ById = {}
for _, d in Discoveries.List do
	Discoveries.ById[d.id] = d
end
Discoveries.Radius = 7
Discoveries.ScrollEach = 1 -- Regular scroll per discovery
Discoveries.AllReward = { legendary = 1 }

return Discoveries

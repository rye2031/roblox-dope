-- Map-pass props (Meshy models baked into MeshData as Prop*). The client places them
-- (PropView.luau): each prop loads when you're near and shares one runtime mesh per kind.
-- Once uploaded to Roblox they'll come from ReplicatedStorage/PropModels instead.
-- { mesh, x, z, h = height in studs, yaw = degrees }
local PropData = {}

PropData.List = {
	-- Haven: market corner, lamps along the north road, a fountain and carts
	{ mesh = "PropFountain", x = -22, z = -22, h = 9, yaw = 0 },
	{ mesh = "PropMarketStall", x = -34, z = -10, h = 9, yaw = 80 },
	{ mesh = "PropMarketStall", x = -36, z = 6, h = 9, yaw = 100 },
	{ mesh = "PropMarketStall", x = 30, z = -24, h = 9, yaw = -70 },
	{ mesh = "PropCart", x = -30, z = 24, h = 5, yaw = 40 },
	{ mesh = "PropCart", x = 26, z = 30, h = 5, yaw = -130 },
	{ mesh = "PropStreetLamp", x = -11, z = 44, h = 10, yaw = 90 },
	{ mesh = "PropStreetLamp", x = 11, z = 44, h = 10, yaw = -90 },
	{ mesh = "PropStreetLamp", x = -11, z = 66, h = 10, yaw = 90 },
	{ mesh = "PropStreetLamp", x = 11, z = 66, h = 10, yaw = -90 },
	{ mesh = "PropStreetLamp", x = -11, z = 86, h = 10, yaw = 90 },
	{ mesh = "PropStreetLamp", x = 11, z = 86, h = 10, yaw = -90 },
	{ mesh = "PropStreetLamp", x = -40, z = -40, h = 10, yaw = 45 },
	{ mesh = "PropStreetLamp", x = 40, z = -40, h = 10, yaw = -45 },

	-- Sprout Meadow: mushroom groves, a ruined arch over the road, the old well by the campfire
	{ mesh = "PropStoneArch", x = 0, z = 190, h = 16, yaw = 0 },
	{ mesh = "PropStoneArch", x = -150, z = 300, h = 12, yaw = 35 },
	{ mesh = "PropWell", x = 36, z = 306, h = 8, yaw = -30 },
	{ mesh = "PropMushrooms", x = -60, z = 160, h = 10, yaw = 20 },
	{ mesh = "PropMushrooms", x = 110, z = 260, h = 13, yaw = 140 },
	{ mesh = "PropMushrooms", x = -120, z = 410, h = 11, yaw = 260 },
	{ mesh = "PropMushrooms", x = 170, z = 520, h = 14, yaw = 80 },
	{ mesh = "PropMushrooms", x = -200, z = 520, h = 9, yaw = 200 },

	-- Ember Canyon: magma crystals, dragon fossils, braziers at the campfire and the arena
	{ mesh = "PropDragonSkull", x = 450, z = 330, h = 16, yaw = -60 },
	{ mesh = "PropDragonSkull", x = 650, z = 250, h = 12, yaw = 200 },
	{ mesh = "PropMagmaCrystals", x = 360, z = 180, h = 8, yaw = 0 },
	{ mesh = "PropMagmaCrystals", x = 540, z = 250, h = 10, yaw = 70 },
	{ mesh = "PropMagmaCrystals", x = 380, z = 500, h = 9, yaw = 150 },
	{ mesh = "PropMagmaCrystals", x = 560, z = 420, h = 7, yaw = 210 },
	{ mesh = "PropMagmaCrystals", x = 680, z = 360, h = 11, yaw = 300 },
	{ mesh = "PropFireBrazier", x = 282, z = 334, h = 6, yaw = 0 },
	{ mesh = "PropFireBrazier", x = 282, z = 356, h = 6, yaw = 0 },
	{ mesh = "PropFireBrazier", x = 576, z = 498, h = 7, yaw = 45 },
	{ mesh = "PropFireBrazier", x = 624, z = 498, h = 7, yaw = -45 },

	-- Tide Coast: a lighthouse on the shore, giant shells and coral
	{ mesh = "PropLighthouse", x = -592, z = 430, h = 34, yaw = 0 },
	{ mesh = "PropSeashell", x = -360, z = 250, h = 7, yaw = 30 },
	{ mesh = "PropSeashell", x = -500, z = 400, h = 9, yaw = 160 },
	{ mesh = "PropSeashell", x = -440, z = 520, h = 6, yaw = 260 },
	{ mesh = "PropCoral", x = -440, z = 205, h = 6, yaw = 0 },
	{ mesh = "PropCoral", x = -540, z = 300, h = 7, yaw = 90 },
	{ mesh = "PropCoral", x = -580, z = 520, h = 6, yaw = 200 },
	{ mesh = "PropCoral", x = -360, z = 470, h = 5, yaw = 300 },

	-- Titan Field: the fallen titan
	{ mesh = "PropTitanHead", x = 205, z = 24, h = 18, yaw = -40 },
}

return PropData

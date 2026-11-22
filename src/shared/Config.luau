-- Values shared by the server and the client.
-- Tuning lives in Config.Tuning so playtests only touch this table.
local Config = {
	GameName = "DON'T WAKE THE BRAINROT",
}

Config.Tuning = {
	-- Movement (studs/s)
	WalkSpeed = 16,
	SprintSpeed = 26,
	CarryWalkSpeed = 14,
	CarrySprintSpeed = 24,

	-- Wake meter runs 0..100. Rates are per second, before the creature's rarity multiplier.
	-- Normal walking on quiet ground holds the meter steady.
	Noise = {
		IdleDrain = 2, -- standing still lets it settle a little
		WalkQuiet = 0, -- careful walking on quiet floor: steady
		SprintQuiet = 9, -- sprinting on quiet floor
		WalkLoud = 9, -- walking carefully on the rattling escalator
		SprintLoud = 38, -- sprinting on the rattling escalator
		ShelterDrain = 28, -- standing or walking in the sheltered corner
		VentRate = 0, -- the vent duct is muffled
		LandSpike = 10, -- landing a jump
		-- The escalator rattles in a cycle. During the calm part its loud rates are scaled down,
		-- so a player who times the sprint can get across.
		RattleCycle = 4.0, -- seconds per full cycle
		RattleLoudPortion = 0.5, -- fraction of the cycle that is loud
		RattleCalmScale = 0.1,
		-- Padded Shoes multiply sprint noise while carrying.
		PaddedShoesSprintScale = 0.45,
		-- Speed above (carry walk speed + this) counts as sprinting.
		SprintThreshold = 3,
	},

	WakeStages = { Twitch = 35, Squirm = 60, EyeOpen = 85, Awake = 100 },

	-- Bolt / recovery
	Bolt = {
		HopDistance = 9, -- first startled leap away from the carrier
		HopTime = 0.45,
		Speed = 15, -- studs/s while bolting (carrier sprints at 26)
		Duration = 3.2, -- seconds of running before it stops to doze
		CarrierStun = 0.5, -- carrier fumbles for this long
		ExclusiveWindow = 2.0, -- seconds only the original carrier may re-grab
		LooseTimeout = 22, -- a loose creature nobody grabs walks home after this
		RegrabWake = 45, -- wake meter after a re-grab (still groggy)
	},

	PickupRange = 10, -- server-validated grab distance
	BankRadius = 11, -- distance to the rescue station that banks a carried creature

	Spawns = {
		CommonRespawn = 6, -- seconds after a common is banked
		RareFirstDelay = 25, -- first rare after server start
		RareRespawn = 70, -- seconds after the rare is banked or returned
	},

	Rarity = {
		Common = { WakeMult = 0.75, BaseCoins = 20 },
		Rare = { WakeMult = 1.5, BaseCoins = 90 },
	},

	Forms = {
		-- Exact form is only revealed after banking.
		{ Id = "Normal", Weight = 75, CoinMult = 1, RareWeight = 30 },
		{ Id = "Glazed", Weight = 20, CoinMult = 2, RareWeight = 45 },
		{ Id = "Jumbo", Weight = 5, CoinMult = 3, RareWeight = 25 },
	},

	Shop = {
		PaddedShoes = { Price = 60, Name = "Padded Shoes" },
	},

	Evolution = {
		From = "CrabRangoon",
		To = "KingRangoon",
		VentRescuesNeeded = 3,
	},

	VentOpenTime = 8, -- seconds the vent door stays open
	KingCoinBonus = 0.1,
}

return Config

-- Values shared by the server and the client.
-- Tuning lives in Config.Tuning so playtests only touch this table.
local Config = {
	GameName = "DON'T WAKE THE BRAINROT",
}

Config.Tuning = {
	-- Movement (studs/s), before upgrades
	WalkSpeed = 20,
	SprintSpeed = 30,
	CarryWalkSpeed = 14,
	CarrySprintSpeed = 24,

	-- Upgrade tracks bought in the shop. Level n costs Costs[n].
	Tracks = {
		Sneakers = {
			Name = "Sneakers",
			Icon = "⚡",
			Blurb = "Run faster with empty hands",
			WalkPerLevel = 1.5,
			SprintPerLevel = 3,
			Costs = { 40, 90, 180, 350, 650, 1200, 2200, 4000 },
		},
		SteadyHands = {
			Name = "Steady Hands",
			Icon = "🤲",
			Blurb = "Walk faster while carrying — still quiet",
			CarryWalkPerLevel = 1.5,
			CarrySprintPerLevel = 1.5,
			Costs = { 120, 300, 700, 1500, 3200 },
		},
	},

	-- Wake meter runs 0..100. Rates are per second, before the creature's wake multiplier.
	-- Normal walking on quiet ground holds the meter steady.
	Noise = {
		IdleDrain = 2, -- standing still lets it settle a little
		WalkQuiet = 0, -- careful walking on quiet floor: steady
		SprintQuiet = 9, -- sprinting on quiet floor
		WalkLoud = 9, -- walking carefully on a loud floor
		SprintLoud = 38, -- sprinting on a loud floor
		ShelterDrain = 28, -- standing or walking somewhere cosy (Cozy Corner, ball pit)
		VentRate = 0, -- the vent duct is muffled
		LandSpike = 10, -- landing a jump
		-- Loud floors pulse in a cycle. During the calm part their rates are scaled down,
		-- so a player who times the sprint can get across.
		RattleCycle = 4.0, -- escalator: seconds per full cycle
		RattleLoudPortion = 0.5, -- fraction of the cycle that is loud
		DanceCycle = 3.0, -- arcade dance floor: faster beat, longer loud part
		DanceLoudPortion = 0.6,
		RattleCalmScale = 0.1,
		-- Padded Shoes multiply sprint noise while carrying.
		PaddedShoesSprintScale = 0.45,
		-- Speed above (the player's carry walk speed + this) counts as sprinting.
		SprintThreshold = 3,
	},

	WakeStages = { Twitch = 35, Squirm = 60, EyeOpen = 85, Awake = 100 },

	-- Bolt / recovery
	Bolt = {
		HopDistance = 9, -- first startled leap away from the carrier
		HopTime = 0.45,
		Speed = 15, -- studs/s while bolting
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
		PaddedShoes = { Price = 60, Name = "Padded Shoes", Icon = "👟", Blurb = "Running while carrying is 55% quieter" },
	},

	-- Evolutions: rescue with the From buddy equipped, through the named route, Needed times.
	Evolutions = {
		{ From = "CrabRangoon", To = "KingRangoon", Route = "Vent", RouteName = "the vent", Needed = 3 },
		{ From = "Ticketoad", To = "JackpotTicketoad", Route = "BallPit", RouteName = "the ball pit", Needed = 3 },
	},

	-- Hideout shelves: displayed creatures earn coins into the tip jar, also while offline.
	Display = {
		BaseRatePerMin = 1.5, -- a Normal Food Court creature
		EvolvedMult = 2.5, -- evolved species (King Rangoon, Jackpot Ticketoad)
		StartSlots = 3,
		SlotCosts = { 100, 250, 500, 1000, 2000, 4000, 8000 }, -- slots 4..10
		JarCapMinutes = 120, -- the jar stops filling at this many minutes of income
		OfflineCapMinutes = 120, -- most offline time that counts
		MinJarCap = 60,
	},

	-- Daily quests: 3 a day (one per tier), rerolled at 00:00 UTC. Targets and rewards by tier.
	Quests = {
		Rewards = { 40, 80, 150 }, -- easy, medium, hard
		AllBonus = 100, -- finishing all three
		ArcadeScale = 1.6, -- rewards once the Arcade is open (its coins are worth more)
		Pool = {
			{ Id = "Rescue", Icon = "🛏", Text = "Rescue %d creatures", Targets = { 6, 10, 15 } },
			{ Id = "Arcade", Icon = "🕹", Text = "Rescue %d Arcade creatures", Targets = { 3, 5, 8 }, NeedsWing = "Arcade" },
			{ Id = "Quiet", Icon = "💤", Text = "Bring %d home the quiet way (Cozy Corner, vent or ball pit)", Targets = { 2, 3, 5 } },
			{ Id = "Perfect", Icon = "✨", Text = "Bring %d home before they even twitch", Targets = { 3, 5, 8 } },
			{ Id = "Bolter", Icon = "🏃", Text = "Catch a creature that woke up and still bring it home", TextN = "Catch %d woken creatures and still bring them home", Targets = { 1, 1, 2 }, MinRescues = 5 },
			{ Id = "Fancy", Icon = "🍩", Text = "Rescue %d Glazed or Jumbo creatures", Text1 = "Rescue a Glazed or Jumbo creature", Targets = { 1, 2, 3 } },
			{ Id = "Rare", Icon = "⭐", Text = "Rescue %d rare sleepers", Text1 = "Rescue a rare sleeper", Targets = { 1, 1, 2 }, Tiers = { 2, 3 } },
			{ Id = "Jar", Icon = "$", Text = "Collect %d coins from your tip jar", Targets = { 30, 80, 200 }, NeedsShelf = true },
		},
		Streak = { 25, 50, 75, 100, 150, 200, 400 }, -- login reward by day of the streak (repeats every 7)
	},

	VentOpenTime = 8, -- seconds the vent door stays open
	-- Evolved buddies add a coin bonus to every rescue.
	BuddyCoinBonus = { KingRangoon = 0.1, JackpotTicketoad = 0.15 },
}

-- Wings of the mall. Each has its own sleepers, rare stage and (except the first) a paid gate.
Config.Wings = {
	FoodCourt = {
		Id = "FoodCourt",
		Name = "Food Court",
		Order = 1,
		Price = 0,
		CoinMult = 1,
		WakeMult = 1,
		Families = { "Dumpling", "Clog", "Candy" },
		RareStageName = "the north stage",
	},
	Arcade = {
		Id = "Arcade",
		Name = "Arcade",
		Order = 2,
		Price = 300,
		CoinMult = 2.25,
		WakeMult = 1.2,
		Families = { "Ticket", "Joystick", "Plush" },
		RareStageName = "the Prize Stage",
	},
}

function Config.wingList()
	local list = {}
	for _, w in Config.Wings do
		table.insert(list, w)
	end
	table.sort(list, function(a, b)
		return a.Order < b.Order
	end)
	return list
end

-- Movement speeds for upgrade levels (used by the server and the HUD).
function Config.speeds(sneakers: number, hands: number)
	local T = Config.Tuning
	local s, h = T.Tracks.Sneakers, T.Tracks.SteadyHands
	return {
		walk = T.WalkSpeed + sneakers * s.WalkPerLevel,
		sprint = T.SprintSpeed + sneakers * s.SprintPerLevel,
		carryWalk = T.CarryWalkSpeed + hands * h.CarryWalkPerLevel,
		carrySprint = T.CarrySprintSpeed + hands * h.CarrySprintPerLevel,
	}
end

-- Coins per minute for one displayed creature. sp is a Creatures.Species entry.
function Config.displayRate(sp: any, formId: string): number
	local D = Config.Tuning.Display
	local formMult = 1
	for _, f in Config.Tuning.Forms do
		if f.Id == formId then
			formMult = f.CoinMult
		end
	end
	local wing = Config.Wings[sp.Wing or "FoodCourt"]
	return D.BaseRatePerMin * wing.CoinMult * formMult * (sp.EvolvesFrom and D.EvolvedMult or 1)
end

function Config.maxSlots(): number
	return Config.Tuning.Display.StartSlots + #Config.Tuning.Display.SlotCosts
end

function Config.questDef(id: string)
	for _, d in Config.Tuning.Quests.Pool do
		if d.Id == id then
			return d
		end
	end
	return nil
end

function Config.questText(id: string, n: number): string
	local d = Config.questDef(id)
	if not d then
		return id
	end
	if n == 1 and d.Text1 then
		return d.Text1
	end
	if n ~= 1 and d.TextN then
		return string.format(d.TextN, n)
	end
	if n == 1 and d.Id == "Bolter" then
		return d.Text
	end
	return string.format(d.Text, n)
end

local function round5(n: number): number
	return math.floor(n / 5 + 0.5) * 5
end

-- Coins for a quest of this tier (1..3) / for finishing all three, for this profile.
function Config.questReward(p: any, tier: number): number
	local Q = Config.Tuning.Quests
	return round5(Q.Rewards[tier] * (p.wings.Arcade and Q.ArcadeScale or 1))
end

function Config.questBonus(p: any): number
	local Q = Config.Tuning.Quests
	return round5(Q.AllBonus * (p.wings.Arcade and Q.ArcadeScale or 1))
end

-- Login streak: the day you'd get by claiming today, and whether it's claimable.
function Config.streakPreview(p: any, today: number): (number, boolean)
	if p.streak.last == today then
		return p.streak.count, false
	end
	if p.streak.last == today - 1 then
		return p.streak.count + 1, true
	end
	return 1, true
end

function Config.streakReward(day: number): number
	local list = Config.Tuning.Quests.Streak
	return list[(day - 1) % #list + 1]
end

-- UTC day number; quests and the login streak roll over at 00:00 UTC.
function Config.today(): number
	return os.time() // 86400
end

function Config.evolutionTo(to: string)
	for _, e in Config.Tuning.Evolutions do
		if e.To == to then
			return e
		end
	end
	return nil
end

return Config

-- Tamer's Journey: the main story, one step at a time. Shared so the client can show the
-- objective, dialogue and waypoint for the step the server says you're on.
--
-- Step kinds (server checks them in Story.luau):
--   talk     npc            talk to that guide (ProximityPrompt)
--   summon   n              open n scrolls
--   team     n              have n monsters on your team
--   visit    region         walk into the region
--   defeat   n, region?     defeat n wild monsters (in that region)
--   campfire region         light that region's campfire
--   level    n              any monster reaches level n
--   feed     n              feed monsters n times
--   ult      n              use your team's ultimates n times
--   boss     region         beat that region's boss (or have beaten it)
--   weapon   n              weapon level n
--   awaken   n              n awakened monsters
--   index    n              n species+element entries in your Index
--   titan                   help defeat the world titan
--   multi                   open 10 scrolls at once
--   arena                   win an Arena fight
--   discover id             find that hidden discovery (Shared/Discoveries)
--   dungeon  id?            clear a dungeon (that one, any mode)
-- Waypoints are world positions (Y is ignored: the marker sits on the ground).
local StoryData = {}

StoryData.Npcs = {
	Mira = { Name = "Mira", Title = "Wayfinder", Icon = "🧭", Color = Color3.fromRGB(120, 200, 170), Pos = Vector3.new(14, 0, -4) },
	Pip = { Name = "Pip", Title = "Meadow Scout", Icon = "🌱", Color = Color3.fromRGB(140, 210, 120), Pos = Vector3.new(22, 0, 300) },
	Cinder = { Name = "Cinder", Title = "Canyon Scout", Icon = "🔥", Color = Color3.fromRGB(240, 130, 90), Pos = Vector3.new(298, 0, 345) },
	Marlo = { Name = "Marlo", Title = "Coast Scout", Icon = "💧", Color = Color3.fromRGB(90, 160, 240), Pos = Vector3.new(-298, 0, 345) },
	Aeris = { Name = "Aeris", Title = "Windkeeper", Icon = "🍃", Color = Color3.fromRGB(110, 200, 180), Pos = Vector3.new(30, 0, -146) },
	Selene = { Name = "Selene", Title = "Twilight Seer", Icon = "🌗", Color = Color3.fromRGB(176, 140, 240), Pos = Vector3.new(300, 0, -236) },
}

local P = {
	Shrine = Vector3.new(48, 0, 14),
	Storage = Vector3.new(-52, 0, 14),
	Smith = Vector3.new(-36, 0, -48),
	Arch = Vector3.new(0, 0, 93), -- the Meadow portal in Haven's north arch
	MeadowCamps = Vector3.new(0, 0, 230),
	MeadowFire = Vector3.new(14, 0, 300),
	MeadowBoss = Vector3.new(0, 0, 520),
	EmberGate = Vector3.new(226, 0, 330), -- portals (Shared/Places)
	EmberCamps = Vector3.new(420, 0, 380),
	EmberBoss = Vector3.new(600, 0, 520),
	TideGate = Vector3.new(-226, 0, 330),
	TideCamps = Vector3.new(-420, 0, 380),
	TideBoss = Vector3.new(-560, 0, 520),
	Titan = Vector3.new(170, 0, -10),
	Arena = Vector3.new(52, 0, 52),
	GaleGate = Vector3.new(0, 0, -82),
	GaleCamps = Vector3.new(0, 0, -300),
	GaleFire = Vector3.new(20, 0, -140),
	GaleBoss = Vector3.new(0, 0, -520),
	ValeGate = Vector3.new(226, 0, -200),
	ValeFire = Vector3.new(290, 0, -222),
	Dawnfield = Vector3.new(450, 0, -230),
	Gloamwood = Vector3.new(430, 0, -440),
	Temple = Vector3.new(620, 0, -332),
	ValeBoss = Vector3.new(600, 0, -500),
	DungeonGate = Vector3.new(-24, 0, 58),
}
StoryData.Points = P

StoryData.Chapters = {
	{
		Title = "A New Tamer",
		Steps = {
			{ id = "meet", kind = "talk", npc = "Mira", text = "Talk to Mira in the plaza", at = StoryData.Npcs.Mira.Pos, reward = { coins = 100 },
				lines = { "Oh! A new Tamer. Welcome to Haven.", "Out past the arch, wild monsters roam. Tamers don't catch them: we befriend them with summoning scrolls.", "You've got a few scrolls already. Take them to the Summoning Shrine and see who answers!" } },
			{ id = "first_summon", kind = "summon", n = 1, text = "Open a scroll at the Summoning Shrine", at = P.Shrine, reward = { coins = 150, scrolls = 1 } },
			{ id = "team", kind = "team", n = 3, text = "Have 3 monsters on your team", at = P.Shrine, reward = { coins = 150 },
				hint = "Open more scrolls. Your first three monsters join your team on their own." },
			{ id = "to_meadow", kind = "visit", region = "SproutMeadow", text = "Walk through the portal in Haven's north arch to Sprout Meadow", at = P.Arch, reward = { coins = 150 } },
		},
	},
	{
		Title = "Sprout Meadow",
		Steps = {
			{ id = "meadow_hunt", kind = "defeat", n = 5, region = "SproutMeadow", text = "Defeat wild monsters in Sprout Meadow", at = P.MeadowCamps, reward = { coins = 200, scrolls = 1 },
				hint = "Click a monster to attack it and send your team after it. Shift dodges the red circles." },
			{ id = "meadow_fire", kind = "campfire", region = "SproutMeadow", text = "Light the Meadow campfire", at = P.MeadowFire, reward = { coins = 150 } },
			{ id = "pip", kind = "talk", npc = "Pip", text = "Talk to Pip by the campfire", at = StoryData.Npcs.Pip.Pos, reward = { coins = 150 },
				lines = { "Mira sent you? Great timing!", "Campfires heal your team, and you'll come back here if you're knocked out.", "Lit campfires are linked, too: stand by one and you can travel to any other you've lit.", "Now let's toughen your team up." } },
			{ id = "lv5", kind = "level", n = 5, text = "Get a monster to level 5", at = P.MeadowCamps, reward = { coins = 200 } },
			{ id = "feed", kind = "feed", n = 1, text = "Train a team monster with a spare one (Monsters panel)", reward = { coins = 150, scrolls = 1 },
				hint = "Open Monsters, pick a team monster, press Train and choose spares. Same species also levels up a skill." },
			{ id = "ults", kind = "ult", n = 3, text = "Use your team's ultimates 3 times (keys 1-3)", at = P.MeadowCamps, reward = { coins = 200 } },
			{ id = "guardian", kind = "boss", region = "SproutMeadow", text = "Defeat the Meadow Guardian", at = P.MeadowBoss, reward = { coins = 400, legendary = 1 },
				hint = "Bring a team around level 10. Watch for its big red circles." },
		},
	},
	{
		Title = "Ember Canyon",
		Steps = {
			{ id = "to_ember", kind = "visit", region = "EmberCanyon", text = "Take the east portal in Sprout Meadow to Ember Canyon", at = P.EmberGate, reward = { coins = 250 } },
			{ id = "cinder", kind = "talk", npc = "Cinder", text = "Talk to Cinder at the canyon campfire", at = StoryData.Npcs.Cinder.Pos, reward = { coins = 200 },
				lines = { "Hot enough for you? Most monsters here are Fire.", "Fire beats Wind, but Water beats Fire. Bring Water monsters and they'll hit harder.", "And visit the Weapon Smith in Haven. A sharper weapon keeps you standing longer." } },
			{ id = "ember_hunt", kind = "defeat", n = 12, region = "EmberCanyon", text = "Defeat wild monsters in Ember Canyon", at = P.EmberCamps, reward = { coins = 300, scrolls = 2 } },
			{ id = "weapon5", kind = "weapon", n = 5, text = "Upgrade your weapon to level 5 at the Smith", at = P.Smith, reward = { coins = 250 } },
			{ id = "lv15", kind = "level", n = 15, text = "Get a monster to level 15", at = P.EmberCamps, reward = { coins = 300 } },
			{ id = "tyrant", kind = "boss", region = "EmberCanyon", text = "Defeat the Canyon Tyrant", at = P.EmberBoss, reward = { coins = 600, legendary = 1 } },
		},
	},
	{
		Title = "Tide Coast",
		Steps = {
			{ id = "to_tide", kind = "visit", region = "TideCoast", text = "Take the west portal in Sprout Meadow to Tide Coast", at = P.TideGate, reward = { coins = 300 } },
			{ id = "marlo", kind = "talk", npc = "Marlo", text = "Talk to Marlo at the coast campfire", at = StoryData.Npcs.Marlo.Pos, reward = { coins = 250 },
				lines = { "Ahoy, Tamer! Mind the tide pools.", "At level 20 a monster stops growing until it Evolves. Evolving takes Crystals of its element, and the cap jumps to 40.", "Wild monsters drop Crystals. Evolve one and you'll feel the difference." } },
			{ id = "tide_hunt", kind = "defeat", n = 15, region = "TideCoast", text = "Defeat wild monsters in Tide Coast", at = P.TideCamps, reward = { coins = 350, scrolls = 2 } },
			{ id = "awaken", kind = "awaken", n = 1, text = "Evolve a monster (Monsters panel)", reward = { coins = 400, scrolls = 1 } },
			{ id = "monarch", kind = "boss", region = "TideCoast", text = "Defeat the Tide Monarch", at = P.TideBoss, reward = { coins = 800, legendary = 1 } },
		},
	},
	{
		Title = "The Titan",
		Steps = {
			{ id = "mira2", kind = "talk", npc = "Mira", text = "Return to Mira in Haven", at = StoryData.Npcs.Mira.Pos, reward = { coins = 300 },
				lines = { "Three guardians down! The whole town's talking.", "Every half hour a Titan stomps into the field east of Haven. No Tamer can beat one alone.", "Team up with the others when the horn sounds. Everyone who helps gets a share." } },
			{ id = "titan", kind = "titan", text = "Help defeat a Titan at the Titan Field", at = P.Titan, reward = { coins = 1000, legendary = 1 },
				hint = "The HUD shows when the next Titan arrives." },
			{ id = "collector", kind = "index", n = 25, text = "Fill 25 entries in your Index", reward = { coins = 500, scrolls = 3 } },
			{ id = "big_summon", kind = "multi", text = "Open 10 scrolls at once at the Shrine", at = P.Shrine, reward = { coins = 500, legendary = 1 } },
			{ id = "arena_win", kind = "arena", text = "Win a fight in the Arena", at = P.Arena, reward = { coins = 600, scrolls = 3 },
				hint = "The Arena is east of the plaza. Pick skills turn by turn, or press Auto." },
		},
	},
	{
		Title = "Gale Highlands",
		Steps = {
			{ id = "to_gale", kind = "visit", region = "GaleHighlands", text = "Take the portal at Haven's south edge to Gale Highlands", at = P.GaleGate, reward = { coins = 400 },
				hint = "The south gate opens once the Tide Monarch falls, or when a monster reaches Lv 30." },
			{ id = "aeris", kind = "talk", npc = "Aeris", text = "Talk to Aeris at the highland campfire", at = StoryData.Npcs.Aeris.Pos, reward = { coins = 300 },
				lines = { "You climbed all the way up here? The wind told me you might.", "Wind monsters rule these heights. Fire burns through them, so bring your hottest team.", "At the top sits the Sky Sovereign. Beat it and you'll have walked the whole Tamer's Journey.", "And legend says the journey's end brings a very rare scroll..." } },
			{ id = "gale_fire", kind = "campfire", region = "GaleHighlands", text = "Light the highland campfire", at = P.GaleFire, reward = { coins = 300 } },
			{ id = "gale_hunt", kind = "defeat", n = 20, region = "GaleHighlands", text = "Defeat wild monsters in Gale Highlands", at = P.GaleCamps, reward = { coins = 600, scrolls = 3 } },
			{ id = "lv30", kind = "level", n = 30, text = "Get a monster to level 30", at = P.GaleCamps, reward = { coins = 600 } },
			{ id = "sovereign", kind = "boss", region = "GaleHighlands", text = "Defeat the Sky Sovereign", at = P.GaleBoss, reward = { coins = 1500, legendary = 1 },
				hint = "Bring evolved monsters. Fire hits Wind hardest." },
		},
	},
	{
		Title = "Twilight Vale",
		Steps = {
			{ id = "to_vale", kind = "visit", region = "TwilightVale", text = "Take the east portal in Gale Highlands to Twilight Vale", at = P.ValeGate, reward = { coins = 600 },
				hint = "It opens once the Sky Sovereign falls, or when a monster reaches Lv 38." },
			{ id = "selene", kind = "talk", npc = "Selene", text = "Talk to Selene by the Vale campfire", at = StoryData.Npcs.Selene.Pos, reward = { coins = 400 },
				lines = { "Ah, a Tamer who walks between day and night. I am Selene.", "North of the arches it is always morning: Light monsters gather there. South, in the Gloamwood, it is always dusk, and Dark ones prowl.", "Light and Dark are strong against each other. Bring both if you can." } },
			{ id = "vale_fire", kind = "campfire", region = "TwilightVale", text = "Light the Vale campfire", at = P.ValeFire, reward = { coins = 300 } },
			{ id = "vale_hunt", kind = "defeat", n = 25, region = "TwilightVale", text = "Defeat wild monsters in Twilight Vale", at = P.Dawnfield, reward = { coins = 800, scrolls = 3 } },
			{ id = "temple", kind = "discover", target = "temple", text = "Find the Temple of Sun and Moon", at = P.Temple, reward = { coins = 500 },
				hint = "It stands on the seam where day meets night." },
			{ id = "sanctum", kind = "dungeon", target = "Sanctum", text = "Clear the Eclipse Sanctum dungeon", at = P.DungeonGate, reward = { coins = 1000, scrolls = 2 },
				hint = "The Dungeon Gate is in Haven. Friends can join as a party." },
			{ id = "warden", kind = "boss", region = "TwilightVale", text = "Defeat the Eclipse Warden", at = P.ValeBoss, reward = { coins = 2500, legendary = 2 },
				hint = "It's Light by day and Dark by night. Pick the team that beats it." },
		},
	},
}
-- The one Eclipse Scroll comes with finishing this step (the end of the original journey);
-- chapters after it are extra (2026-11-27).
StoryData.EclipseAfter = "sovereign"

-- Flattened list: StoryData.Steps[i] = step with .chapter (index) and .chapterTitle.
StoryData.Steps = {}
for ci, ch in StoryData.Chapters do
	for _, s in ch.Steps do
		s.chapter = ci
		s.chapterTitle = ch.Title
		table.insert(StoryData.Steps, s)
	end
end

function StoryData.rewardText(r): string
	local parts = {}
	if r.coins and r.coins > 0 then
		table.insert(parts, "+" .. r.coins .. " coins")
	end
	if r.scrolls and r.scrolls > 0 then
		table.insert(parts, "+" .. r.scrolls .. " 📜")
	end
	if r.legendary and r.legendary > 0 then
		table.insert(parts, "+" .. r.legendary .. " 🌟")
	end
	return table.concat(parts, "  ")
end

return StoryData

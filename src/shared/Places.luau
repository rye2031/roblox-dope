-- The world's places and how they link (2026-11-27, owner: regions should feel like separate
-- places you travel to). Haven and every region sit in their own valley ringed by mountains;
-- portals at the old gate spots carry you between them with a fade. Shared so the server
-- builds and runs the portals and the client routes the Journey waypoint through them.
local Places = {}

-- x0, x1, z0, z1 (same as World.Regions bounds). Anything outside is Haven.
Places.Bounds = {
	SproutMeadow = { -240, 240, 100, 570 },
	EmberCanyon = { 260, 700, 100, 570 },
	TideCoast = { -700, -260, 100, 570 },
	GaleHighlands = { -240, 240, -570, -110 },
	TwilightVale = { 260, 700, -570, -110 },
}

Places.Names = {
	Haven = "Haven",
	SproutMeadow = "Sprout Meadow",
	EmberCanyon = "Ember Canyon",
	TideCoast = "Tide Coast",
	GaleHighlands = "Gale Highlands",
	TwilightVale = "Twilight Vale",
}

function Places.regionAt(pos: Vector3): string
	for id, b in Places.Bounds do
		if pos.X >= b[1] and pos.X <= b[2] and pos.Z >= b[3] and pos.Z <= b[4] then
			return id
		end
	end
	return "Haven"
end

-- Portal pairs. Each side: the place it stands in, the portal's spot (ground) and facing (the
-- way you walk into it), and where you arrive when you come through from the other side.
-- `needs` is the region that must be open to go from `a` to `b` (going back is always free).
Places.Links = {
	{
		id = "meadow",
		a = { place = "Haven", pos = Vector3.new(0, 0, 93), face = Vector3.new(0, 0, 1), arrive = Vector3.new(0, 0, 70), frame = false }, -- Haven's north arch is the frame
		b = { place = "SproutMeadow", pos = Vector3.new(0, 0, 132), face = Vector3.new(0, 0, -1), arrive = Vector3.new(0, 0, 154) },
	},
	{
		id = "ember",
		needs = "EmberCanyon",
		a = { place = "SproutMeadow", pos = Vector3.new(226, 0, 330), face = Vector3.new(1, 0, 0), arrive = Vector3.new(204, 0, 330) },
		b = { place = "EmberCanyon", pos = Vector3.new(276, 0, 330), face = Vector3.new(-1, 0, 0), arrive = Vector3.new(298, 0, 330) },
	},
	{
		id = "tide",
		needs = "TideCoast",
		a = { place = "SproutMeadow", pos = Vector3.new(-226, 0, 330), face = Vector3.new(-1, 0, 0), arrive = Vector3.new(-204, 0, 330) },
		b = { place = "TideCoast", pos = Vector3.new(-276, 0, 330), face = Vector3.new(1, 0, 0), arrive = Vector3.new(-298, 0, 330) },
	},
	{
		id = "gale",
		needs = "GaleHighlands",
		a = { place = "Haven", pos = Vector3.new(0, 0, -82), face = Vector3.new(0, 0, -1), arrive = Vector3.new(16, 0, -62) },
		b = { place = "GaleHighlands", pos = Vector3.new(0, 0, -124), face = Vector3.new(0, 0, 1), arrive = Vector3.new(0, 0, -146) },
	},
	{
		id = "vale",
		needs = "TwilightVale",
		a = { place = "GaleHighlands", pos = Vector3.new(226, 0, -200), face = Vector3.new(1, 0, 0), arrive = Vector3.new(204, 0, -200) },
		b = { place = "TwilightVale", pos = Vector3.new(276, 0, -200), face = Vector3.new(-1, 0, 0), arrive = Vector3.new(298, 0, -200) },
	},
}

-- The portal to take from `from` to head toward `to` (first hop of a shortest route), or nil
-- when they're the same place. Returns the portal side standing in `from`.
function Places.nextPortal(from: string, to: string)
	if from == to then
		return nil
	end
	local prev: { [string]: any } = { [from] = false }
	local queue = { from }
	while #queue > 0 do
		local cur = table.remove(queue, 1)
		if cur == to then
			break
		end
		for _, l in Places.Links do
			for _, pair in { { l.a, l.b }, { l.b, l.a } } do
				local here, there = pair[1], pair[2]
				if here.place == cur and prev[there.place] == nil then
					prev[there.place] = { place = cur, side = here }
					table.insert(queue, there.place)
				end
			end
		end
	end
	if prev[to] == nil then
		return nil
	end
	local step = to
	while prev[step] and prev[step].place ~= from do
		step = prev[step].place
	end
	return prev[step] and prev[step].side or nil
end

return Places

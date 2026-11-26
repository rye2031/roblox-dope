-- Eye positions on each Meshy model, in the same normalized space as MeshData (height = 1,
-- centred on the bounding box, facing -Z). Found with scripts/find_eyes.py; Gobstopper's were
-- read off its front preview by hand because the candy stripes fool the white-blob detector.
-- Sleeping creatures wear lids over these; stage 3 ("one eye open") lifts one lid.
return {
	CrabRangoon = {
		{ Pos = Vector3.new(-0.164, 0.062, -0.299), Radius = 0.087, Lid = Color3.fromRGB(207, 155, 59) },
		{ Pos = Vector3.new(0.176, 0.066, -0.294), Radius = 0.087, Lid = Color3.fromRGB(210, 156, 60) },
	},
	KingRangoon = {
		{ Pos = Vector3.new(-0.162, 0.057, -0.310), Radius = 0.085, Lid = Color3.fromRGB(196, 141, 51) },
		{ Pos = Vector3.new(0.168, 0.057, -0.307), Radius = 0.085, Lid = Color3.fromRGB(198, 143, 52) },
	},
	Crocsquatch = {
		{ Pos = Vector3.new(-0.101, 0.275, -0.520), Radius = 0.066, Lid = Color3.fromRGB(111, 204, 173) },
		{ Pos = Vector3.new(0.108, 0.277, -0.515), Radius = 0.066, Lid = Color3.fromRGB(111, 204, 173) },
	},
	MallGobstopper = {
		{ Pos = Vector3.new(-0.148, 0.142, -0.45), Radius = 0.062, Lid = Color3.fromRGB(246, 242, 236) },
		{ Pos = Vector3.new(0.164, 0.142, -0.45), Radius = 0.062, Lid = Color3.fromRGB(246, 242, 236) },
	},
	-- Arcade wing (dark glossy eyes: found with find_eyes.py ... dark)
	Ticketoad = {
		{ Pos = Vector3.new(-0.209, 0.197, -0.162), Radius = 0.085, Lid = Color3.fromRGB(205, 227, 129) },
		{ Pos = Vector3.new(0.222, 0.195, -0.157), Radius = 0.087, Lid = Color3.fromRGB(204, 229, 127) },
	},
	JackpotTicketoad = {
		{ Pos = Vector3.new(-0.171, 0.095, -0.140), Radius = 0.072, Lid = Color3.fromRGB(236, 192, 57) },
		{ Pos = Vector3.new(0.166, 0.095, -0.140), Radius = 0.072, Lid = Color3.fromRGB(235, 191, 58) },
	},
	Joystingray = {
		{ Pos = Vector3.new(-0.183, -0.088, -0.628), Radius = 0.06, Lid = Color3.fromRGB(146, 215, 245) },
		{ Pos = Vector3.new(0.176, -0.090, -0.632), Radius = 0.06, Lid = Color3.fromRGB(145, 216, 245) },
	},
	Clawmato = {
		{ Pos = Vector3.new(-0.120, -0.046, -0.347), Radius = 0.05, Lid = Color3.fromRGB(225, 36, 35) },
		{ Pos = Vector3.new(0.125, -0.048, -0.347), Radius = 0.05, Lid = Color3.fromRGB(225, 36, 35) },
	},
}

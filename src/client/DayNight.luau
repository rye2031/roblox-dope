-- Day and night on the client: moves the sun with the shared 20-minute cycle (server time, so
-- every player sees the same sky), dims and cools the light at night, and switches on the
-- lamps, braziers and the lighthouse once it's dark.
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local DayNight = {}
local D = Config.DayNight

local SUNRISE, SUNSET = 6.2, 17.8
local LIGHTS = {
	PropStreetLamp = { y = 0.42, color = Color3.fromRGB(255, 214, 150), range = 24, brightness = 1.6 },
	PropFireBrazier = { y = 0.4, color = Color3.fromRGB(255, 150, 80), range = 20, brightness = 2 },
	PropLighthouse = { y = 0.32, color = Color3.fromRGB(255, 240, 180), range = 60, brightness = 3 },
	PropMagmaCrystals = { y = 0.1, color = Color3.fromRGB(255, 140, 60), range = 16, brightness = 1.2 },
	PropMoonLantern = { y = 0.8, color = Color3.fromRGB(170, 210, 255), range = 26, brightness = 2 },
	PropShadowCrystals = { y = 0.3, color = Color3.fromRGB(180, 120, 255), range = 16, brightness = 1.4 },
}

local function smooth(x: number): number
	x = math.clamp(x, 0, 1)
	return x * x * (3 - 2 * x)
end

-- Clock time (0-24) and how dark it is (0 = full day, 1 = deep night) for a server time.
local function sky(t: number): (number, number)
	local c = t % D.Cycle
	local clock
	if c < D.NightStart then
		clock = SUNRISE + (c / D.NightStart) * (SUNSET - SUNRISE)
	else
		local k = (c - D.NightStart) / (D.Cycle - D.NightStart)
		clock = (SUNSET + k * (24 - SUNSET + SUNRISE)) % 24
	end
	local dark
	if clock >= SUNSET or clock < SUNRISE then
		dark = 1
	else
		dark = 0
	end
	-- twilight blends over ~0.8 game-hours each side
	if clock >= SUNSET - 0.8 and clock < SUNSET + 0.8 then
		dark = smooth((clock - (SUNSET - 0.8)) / 1.6)
	elseif clock >= SUNRISE - 0.8 and clock < SUNRISE + 0.8 then
		dark = 1 - smooth((clock - (SUNRISE - 0.8)) / 1.6)
	end
	return clock, dark
end

function DayNight.start()
	local base = {
		exposure = Lighting.ExposureCompensation,
		brightness = Lighting.Brightness,
		ambient = Lighting.Ambient,
		outdoor = Lighting.OutdoorAmbient,
	}
	local EVENING, MORNING = 17.0, 6.9
	local EVENING_TINT = { ambient = Color3.fromRGB(200, 170, 196), outdoor = Color3.fromRGB(214, 180, 196) }
	local NIGHT = { brightness = 0.9, ambient = Color3.fromRGB(70, 76, 120), outdoor = Color3.fromRGB(84, 92, 146) }
	-- Twilight Vale zones: the Dawnfield is always sunlit and warm, the Gloamwood always dusky
	local GLOAM = { ambient = Color3.fromRGB(96, 70, 140), outdoor = Color3.fromRGB(110, 86, 160) }
	local DAWN = { ambient = Color3.fromRGB(190, 170, 130), outdoor = Color3.fromRGB(200, 182, 140) }
	local zone = 0 -- smoothed: -1 Dawnfield, 0 elsewhere, 1 Gloamwood
	local atm = Lighting:FindFirstChildOfClass("Atmosphere")
	local cc = Lighting:FindFirstChildOfClass("ColorCorrectionEffect")
	local atmBase = atm and { color = atm.Color, decay = atm.Decay, density = atm.Density, haze = atm.Haze }
	local ccBase = cc and { tint = cc.TintColor, sat = cc.Saturation }
	-- each place has its own air (closed valleys, 2026-11-27): colour of the haze, how thick,
	-- the colour grade and a nudge to the sun so every region feels like somewhere else
	local LOOKS = {
		SproutMeadow = { color = Color3.fromRGB(232, 246, 222), decay = Color3.fromRGB(186, 222, 170), density = 0.3, haze = 0.9, tint = Color3.fromRGB(250, 255, 240), sat = 0.04 },
		EmberCanyon = { color = Color3.fromRGB(255, 214, 172), decay = Color3.fromRGB(226, 140, 92), density = 0.38, haze = 1.8, tint = Color3.fromRGB(255, 236, 218), sat = 0.06, clock = 16.2 },
		TideCoast = { color = Color3.fromRGB(214, 238, 255), decay = Color3.fromRGB(150, 204, 244), density = 0.26, haze = 0.5, tint = Color3.fromRGB(236, 248, 255), sat = 0.04, clock = 10.5 },
		GaleHighlands = { color = Color3.fromRGB(238, 246, 255), decay = Color3.fromRGB(204, 222, 246), density = 0.22, haze = 0.2, tint = Color3.fromRGB(244, 250, 255), sat = -0.04, clock = 11.5 },
	}
	local look = 0 -- smoothed blend toward the current place's look
	local lookId: string? = nil
	local ATM_GLOAM = { color = Color3.fromRGB(150, 120, 200), decay = Color3.fromRGB(90, 60, 140), density = 0.42, haze = 2.2 }
	local ATM_DAWN = { color = Color3.fromRGB(255, 238, 205), decay = Color3.fromRGB(255, 214, 160), density = 0.32, haze = 1.4 }
	local player = game:GetService("Players").LocalPlayer
	task.spawn(function()
		while true do
			local offset = game:GetService("RunService"):IsStudio() and (workspace:GetAttribute("DebugTimeOffset") or 0) or 0
			local clock, dark = sky(workspace:GetServerTimeNow() + offset)
			local want = 0
			local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
			if hrp and player:GetAttribute("Region") == "TwilightVale" then
				want = hrp.Position.Z > D.TwilightSeam and -1 or 1
			end
			zone += (want - zone) * 0.12
			local region = player:GetAttribute("Region")
			local L = LOOKS[region]
			if L then
				if lookId ~= region then
					lookId = region
				end
				look += (1 - look) * 0.15
			else
				look += (0 - look) * 0.15
			end
			local LL = lookId and LOOKS[lookId]
			if LL and LL.clock and math.abs(zone) < 0.01 then
				clock = clock + (LL.clock - clock) * look * 0.7
			end
			-- Night is an event, not darkness (owner, 2026-11-27): the sun holds at golden hour and
			-- the light only takes a soft evening tint; lamps still come on.
			local night = dark
			local evening = night
			dark *= 0.18
			if zone <= 0 and (clock >= EVENING or clock < MORNING) then
				clock = EVENING
			end
			if zone > 0 then
				dark = math.max(dark, 0.7 * zone)
				-- the Gloamwood sits in a permanent dusk: the sun sinks toward the horizon
				if clock > 6 and clock < 18.4 then
					clock = clock + (18.4 - clock) * zone * 0.9
				end
			elseif zone < 0 then
				dark *= 1 + zone * 0.8
				clock = clock + (13 - clock) * -zone * 0.6
			end
			DayNight.zone = zone
			Lighting.ClockTime = clock
			Lighting.Brightness = base.brightness + (NIGHT.brightness - base.brightness) * dark
			Lighting.Ambient = base.ambient:Lerp(NIGHT.ambient, dark)
			Lighting.OutdoorAmbient = base.outdoor:Lerp(NIGHT.outdoor, dark)
			if evening > 0.01 and zone <= 0.5 then
				Lighting.Ambient = Lighting.Ambient:Lerp(EVENING_TINT.ambient, evening * 0.35)
				Lighting.OutdoorAmbient = Lighting.OutdoorAmbient:Lerp(EVENING_TINT.outdoor, evening * 0.35)
			end
			if atm and atmBase and LL and look > 0.01 and math.abs(zone) < 0.01 then
				atm.Color = atmBase.color:Lerp(LL.color, look)
				atm.Decay = atmBase.decay:Lerp(LL.decay, look)
				atm.Density = atmBase.density + (LL.density - atmBase.density) * look
				atm.Haze = atmBase.haze + (LL.haze - atmBase.haze) * look
			elseif atm and atmBase then
				local to, k = zone > 0 and ATM_GLOAM or ATM_DAWN, math.abs(zone)
				atm.Color = atmBase.color:Lerp(to.color, k)
				atm.Decay = atmBase.decay:Lerp(to.decay, k)
				atm.Density = atmBase.density + (to.density - atmBase.density) * k
				atm.Haze = atmBase.haze + (to.haze - atmBase.haze) * k
			end
			if cc and ccBase then
				cc.TintColor = ccBase.tint:Lerp(Color3.fromRGB(255, 232, 224), evening * 0.35):Lerp(zone > 0 and Color3.fromRGB(222, 208, 255) or Color3.fromRGB(255, 246, 228), math.abs(zone))
				cc.Saturation = ccBase.sat - math.abs(zone) * 0.12
				if LL and look > 0.01 and math.abs(zone) < 0.01 then
					cc.TintColor = cc.TintColor:Lerp(LL.tint, look)
					cc.Saturation += LL.sat * look
				end
			end
			Lighting.ExposureCompensation = base.exposure - math.max(0, zone) * 0.7 - math.max(0, -zone) * 0.15
			if zone > 0.01 then
				Lighting.Ambient = Lighting.Ambient:Lerp(GLOAM.ambient, zone * 0.7)
				Lighting.OutdoorAmbient = Lighting.OutdoorAmbient:Lerp(GLOAM.outdoor, zone * 0.7)
			elseif zone < -0.01 then
				Lighting.Ambient = Lighting.Ambient:Lerp(DAWN.ambient, -zone * 0.3)
				Lighting.OutdoorAmbient = Lighting.OutdoorAmbient:Lerp(DAWN.outdoor, -zone * 0.3)
			end
			-- lamps
			local props = workspace:FindFirstChild("Props")
			for _, p in (props and props:GetChildren() or {}) do
				local spec = LIGHTS[p.Name]
				local lit = math.max(evening, zone)
				if spec and p:IsA("BasePart") then
					local l = p:FindFirstChild("NightLight", true) :: PointLight?
					if not l then
						local att = Instance.new("Attachment")
						att.Name = "LightPoint"
						att.Position = Vector3.new(0, p.Size.Y * spec.y, 0)
						att.Parent = p
						l = Instance.new("PointLight")
						l.Name = "NightLight"
						l.Color = spec.color
						l.Range = spec.range
						l.Shadows = false
						l.Parent = att
						l = att:FindFirstChild("NightLight") :: PointLight
					end
					local light = l :: PointLight
					light.Brightness = spec.brightness * lit
					light.Enabled = lit > 0.05
				end
			end
			task.wait(0.25)
		end
	end)
end

DayNight.sky = sky
return DayNight

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
		brightness = Lighting.Brightness,
		ambient = Lighting.Ambient,
		outdoor = Lighting.OutdoorAmbient,
	}
	local NIGHT = { brightness = 0.9, ambient = Color3.fromRGB(70, 76, 120), outdoor = Color3.fromRGB(84, 92, 146) }
	task.spawn(function()
		while true do
			local offset = game:GetService("RunService"):IsStudio() and (workspace:GetAttribute("DebugTimeOffset") or 0) or 0
			local clock, dark = sky(workspace:GetServerTimeNow() + offset)
			Lighting.ClockTime = clock
			Lighting.Brightness = base.brightness + (NIGHT.brightness - base.brightness) * dark
			Lighting.Ambient = base.ambient:Lerp(NIGHT.ambient, dark)
			Lighting.OutdoorAmbient = base.outdoor:Lerp(NIGHT.outdoor, dark)
			-- lamps
			local props = workspace:FindFirstChild("Props")
			for _, p in (props and props:GetChildren() or {}) do
				local spec = LIGHTS[p.Name]
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
					light.Brightness = spec.brightness * dark
					light.Enabled = dark > 0.05
				end
			end
			task.wait(0.25)
		end
	end)
end

DayNight.sky = sky
return DayNight

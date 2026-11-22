-- Pure wake-meter maths, shared so the server (authority) and client (preview) agree.
local Config = require(script.Parent.Config)

local Noise = {}

local T = Config.Tuning

-- Is the escalator in the loud part of its rattle cycle at server time t?
function Noise.rattleLoud(t: number): boolean
	local n = T.Noise
	local phase = (t % n.RattleCycle) / n.RattleCycle
	return phase < n.RattleLoudPortion
end

-- 0..1 phase, for client visuals.
function Noise.rattlePhase(t: number): number
	local n = T.Noise
	return (t % n.RattleCycle) / n.RattleCycle
end

export type Sample = {
	speed: number, -- horizontal studs/s measured by the server
	surface: string, -- "Quiet" | "Loud" | "Shelter" | "Vent"
	t: number, -- server time
	rarity: string, -- "Common" | "Rare"
	paddedShoes: boolean,
}

-- Returns d(wake)/dt for one sample. Positive raises the meter.
function Noise.rate(s: Sample): number
	local n = T.Noise
	local mult = T.Rarity[s.rarity].WakeMult
	local sprinting = s.speed > T.CarryWalkSpeed + n.SprintThreshold
	local moving = s.speed > 1.5

	if s.surface == "Shelter" then
		return -n.ShelterDrain
	end
	if s.surface == "Vent" then
		return n.VentRate
	end

	local rate
	if not moving then
		rate = -n.IdleDrain
		return rate
	elseif s.surface == "Loud" then
		local scale = Noise.rattleLoud(s.t) and 1 or n.RattleCalmScale
		rate = (sprinting and n.SprintLoud or n.WalkLoud) * scale
	else
		rate = sprinting and n.SprintQuiet or n.WalkQuiet
	end

	if sprinting and s.paddedShoes then
		rate *= n.PaddedShoesSprintScale
	end
	return rate * mult
end

function Noise.stage(wake: number): number
	local st = T.WakeStages
	if wake >= st.Awake then
		return 4
	elseif wake >= st.EyeOpen then
		return 3
	elseif wake >= st.Squirm then
		return 2
	elseif wake >= st.Twitch then
		return 1
	end
	return 0
end

return Noise

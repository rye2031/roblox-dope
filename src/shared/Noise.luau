-- Pure wake-meter maths, shared so the server (authority) and client (preview) agree.
local Config = require(script.Parent.Config)

local Noise = {}

local T = Config.Tuning

-- Loud floors pulse: the escalator rattles ("Loud") and the arcade dance floor thumps ("Dance").
local function cycleOf(surface: string?): (number, number)
	local n = T.Noise
	if surface == "Dance" then
		return n.DanceCycle, n.DanceLoudPortion
	end
	return n.RattleCycle, n.RattleLoudPortion
end
Noise.cycleOf = cycleOf

-- Is that floor in the loud part of its cycle at server time t?
function Noise.loudNow(surface: string?, t: number): boolean
	local cycle, portion = cycleOf(surface)
	return (t % cycle) / cycle < portion
end

-- 0..1 phase, for client visuals.
function Noise.phase(surface: string?, t: number): number
	local cycle = cycleOf(surface)
	return (t % cycle) / cycle
end

function Noise.rattleLoud(t: number): boolean
	return Noise.loudNow("Loud", t)
end

function Noise.rattlePhase(t: number): number
	return Noise.phase("Loud", t)
end

export type Sample = {
	speed: number, -- horizontal studs/s measured by the server
	surface: string, -- "Quiet" | "Loud" | "Dance" | "Shelter" | "Vent"
	t: number, -- server time
	rarity: string, -- "Common" | "Rare"
	paddedShoes: boolean,
	carryWalk: number?, -- the carrier's careful walking speed (Steady Hands raises it)
	mult: number?, -- wake multiplier override (rarity x wing)
}

-- Returns d(wake)/dt for one sample. Positive raises the meter.
function Noise.rate(s: Sample): number
	local n = T.Noise
	local mult = s.mult or T.Rarity[s.rarity].WakeMult
	local sprinting = s.speed > (s.carryWalk or T.CarryWalkSpeed) + n.SprintThreshold
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
	elseif s.surface == "Loud" or s.surface == "Dance" then
		local scale = Noise.loudNow(s.surface, s.t) and 1 or n.RattleCalmScale
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

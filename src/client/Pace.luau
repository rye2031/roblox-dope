-- Travel pace on the client: when the server says you're out of combat long enough
-- (player attribute Travelling) you run faster; this adds a light dust trail at your feet and
-- a one-time tip so players notice it.
local Players = game:GetService("Players")

local Ui = require(script.Parent.Ui)

local Pace = {}
local player = Players.LocalPlayer
local told = false

local function dust(char: Model): ParticleEmitter?
	local hrp = char:WaitForChild("HumanoidRootPart", 10) :: BasePart?
	if not hrp then
		return nil
	end
	local att = Instance.new("Attachment")
	att.Name = "PaceDust"
	att.Position = Vector3.new(0, -2.8, 0.6)
	att.Parent = hrp
	local e = Instance.new("ParticleEmitter")
	e.Texture = "rbxasset://textures/particles/smoke_main.dds"
	e.Color = ColorSequence.new(Color3.fromRGB(236, 230, 214))
	e.Transparency = NumberSequence.new(0.55, 1)
	e.Size = NumberSequence.new(0.9, 0.2)
	e.Lifetime = NumberRange.new(0.35, 0.6)
	e.Speed = NumberRange.new(0.5, 1.5)
	e.SpreadAngle = Vector2.new(40, 40)
	e.Rate = 0
	e.Parent = att
	return e
end

function Pace.start()
	local emitter: ParticleEmitter? = nil
	local function onChar(char: Model)
		emitter = dust(char)
	end
	player.CharacterAdded:Connect(onChar)
	if player.Character then
		task.spawn(onChar, player.Character)
	end
	task.spawn(function()
		while true do
			task.wait(0.2)
			local fast = player:GetAttribute("Travelling") == true
			local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
			local moving = hum ~= nil and hum.MoveDirection.Magnitude > 0.1
			if emitter then
				emitter.Rate = (fast and moving) and 14 or 0
			end
			if fast and moving and not told then
				told = true
				Ui.toast("🏃 Out of a fight you run faster. Your team keeps up", "info")
			end
		end
	end)
end

return Pace

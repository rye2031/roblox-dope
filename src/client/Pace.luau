-- Travel pace on the client: when the server says you're out of combat long enough
-- (player attribute Travelling) you run faster; this adds a light dust trail at your feet and
-- a one-time tip so players notice it.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Ui = require(script.Parent.Ui)
local Sfx = require(script.Parent.Sfx)

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

-- Ride button (F): hop on your lead monster to travel faster. Out of combat only.
local C, px = Ui.C, Ui.px
local rideB = Ui.button({ Name = "Ride", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -px(16), 0, px(206)), Size = UDim2.fromOffset(px(170), px(40)), BackgroundColor3 = C.Lilac, Text = "🐾 Ride [F]", TextScaled = false, TextSize = px(16), ZIndex = 3, Parent = Ui.gui, Radius = 20 })

local function toggleRide()
	local Intent = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Intent") :: RemoteEvent
	if not player:GetAttribute("Riding") and player:GetAttribute("InCombat") then
		Ui.toast("You can't ride during a fight", "warn")
		return
	end
	Intent:FireServer("ride")
end

function Pace.start()
	rideB.Activated:Connect(toggleRide)
	UserInputService.InputBegan:Connect(function(input, processed)
		if not processed and input.KeyCode == Enum.KeyCode.F then
			toggleRide()
		end
	end)
	local function paintRide()
		local riding = player:GetAttribute("Riding") ~= nil
		rideB.Text = riding and "🐾 Get off [F]" or "🐾 Ride [F]"
		rideB.BackgroundColor3 = riding and C.Mint or (player:GetAttribute("InCombat") and C.Line or C.Lilac)
		rideB.Visible = player:GetAttribute("Dungeon") == nil
	end
	for _, a in { "Riding", "InCombat", "Dungeon" } do
		player:GetAttributeChangedSignal(a):Connect(paintRide)
	end
	paintRide()
	player:GetAttributeChangedSignal("Riding"):Connect(function()
		if player:GetAttribute("Riding") then
			Sfx.play("skill_ready", { pitch = 1.2 })
		end
	end)
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

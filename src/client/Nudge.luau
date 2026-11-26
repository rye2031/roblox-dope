-- Nudge prompt: when another player is carrying (outside the hideout, past their newbie
-- shield) and your cooldown is up, a "Nudge" prompt (F / tap) shows on them. The server
-- re-checks everything; this only decides when to offer it.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local Remotes = ReplicatedStorage:WaitForChild("Remotes")

local N = Config.Tuning.Nudge
local player = Players.LocalPlayer
local Nudge = {}

local prompts: { [Player]: ProximityPrompt } = {}
local readyAt = 0

local hideoutZone: BasePart? = nil
local function inHideout(pos: Vector3): boolean
	if not hideoutZone then
		local zones = workspace:FindFirstChild("Map") and workspace.Map:FindFirstChild("Zones")
		if zones then
			for _, z in zones:GetChildren() do
				if z:GetAttribute("Kind") == "Hideout" then
					hideoutZone = z :: BasePart
				end
			end
		end
	end
	local z = hideoutZone
	if not z then
		return false
	end
	local rel = z.CFrame:PointToObjectSpace(pos)
	return math.abs(rel.X) <= z.Size.X / 2 and math.abs(rel.Z) <= z.Size.Z / 2
end

local function promptFor(other: Player): ProximityPrompt?
	local hrp = other.Character and other.Character:FindFirstChild("HumanoidRootPart")
	if not hrp then
		return nil
	end
	local p = prompts[other]
	if p and p.Parent == hrp then
		return p
	end
	if p then
		p:Destroy()
	end
	p = Instance.new("ProximityPrompt")
	p.Name = "NudgePrompt"
	p.ActionText = "Nudge"
	p.ObjectText = other.DisplayName
	p.KeyboardKeyCode = Enum.KeyCode.F
	p.GamepadKeyCode = Enum.KeyCode.ButtonY
	p.HoldDuration = 0
	p.MaxActivationDistance = N.Range
	p.RequiresLineOfSight = false
	p.Enabled = false
	p.Triggered:Connect(function()
		if os.clock() < readyAt then
			return
		end
		readyAt = os.clock() + N.Cooldown
		Remotes.Nudge:FireServer(other.UserId)
	end)
	p.Parent = hrp
	prompts[other] = p
	return p
end

function Nudge.start()
	Players.PlayerRemoving:Connect(function(other)
		local p = prompts[other]
		if p then
			p:Destroy()
			prompts[other] = nil
		end
	end)
	local acc = 0
	RunService.Heartbeat:Connect(function(dt)
		acc += dt
		if acc < 0.25 then
			return
		end
		acc = 0
		for _, other in Players:GetPlayers() do
			if other ~= player then
				local p = promptFor(other)
				if p then
					local hrp = p.Parent :: BasePart
					p.Enabled = other:GetAttribute("Carrying") ~= nil
						and other:GetAttribute("NudgeShield") ~= true
						and not inHideout(hrp.Position)
						and os.clock() >= readyAt
				end
			end
		end
	end)
end

return Nudge

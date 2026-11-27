-- Auto-Hunt: while it's on, your Tamer and team keep fighting nearby wild monsters on their
-- own. Only works while you're in the game (offline earning is Expeditions), pays 60% (the
-- server applies it), skips bosses and Wandering Legends unless you picked them, dodges red
-- circles, and pauses after 30 minutes without real input or when your HP gets low.
-- Toggle: R or the HUD button. Unlocks after the Meadow Guardian.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Ui = require(script.Parent.Ui)
local Sfx = require(script.Parent.Sfx)
local Controls = require(script.Parent.Controls)
local UnitView = require(script.Parent.UnitView)

local AutoHunt = {}
local player = Players.LocalPlayer
local Intent = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Intent") :: RemoteEvent
local A = Config.AutoHunt

local on = false
local lastInput = os.clock()
local lastMoveInput = 0
local target: BasePart? = nil
local listeners: { (boolean) -> () } = {}

local MOVE_KEYS = { [Enum.KeyCode.W] = true, [Enum.KeyCode.A] = true, [Enum.KeyCode.S] = true, [Enum.KeyCode.D] = true, [Enum.KeyCode.Up] = true, [Enum.KeyCode.Down] = true, [Enum.KeyCode.Left] = true, [Enum.KeyCode.Right] = true, [Enum.KeyCode.Thumbstick1] = true }

local function unlocked(): boolean
	local p = Ui.profile
	return p ~= nil and (p.kills >= 1 or (p.bosses ~= nil and p.bosses[A.UnlockBoss] == true))
end

function AutoHunt.isOn(): boolean
	return on
end

function AutoHunt.onChanged(fn: (boolean) -> ())
	table.insert(listeners, fn)
end

function AutoHunt.set(state: boolean, why: string?)
	if state and not unlocked() then
		Ui.toast("Auto-Hunt unlocks after your first win", "warn")
		return
	end
	if on == state then
		return
	end
	on = state
	lastInput = os.clock()
	target = nil
	Intent:FireServer("auto", state)
	local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if not state and hum then
		hum:Move(Vector3.zero)
	end
	Ui.toast(why or (state and "🤖 Auto-Hunt on: your team fights nearby monsters (60% rewards). Press R to stop" or "Auto-Hunt off"), state and "good" or "info")
	Sfx.play(state and "skill_ready" or "close")
	for _, fn in listeners do
		fn(state)
	end
end

function AutoHunt.toggle()
	AutoHunt.set(not on)
end

local function hrp(): BasePart?
	local c = player.Character
	return c and c:FindFirstChild("HumanoidRootPart") :: BasePart?
end

local function valid(part: BasePart?): boolean
	return part ~= nil and part.Parent ~= nil and part:GetAttribute("Side") == "wild" and part:GetAttribute("State") ~= "dead"
end

-- Nearest ordinary wild monster (no bosses or Legends unless the player chose them).
local function pickTarget(pos: Vector3): BasePart?
	local chosen = Controls.target
	if valid(chosen) and ((chosen :: BasePart).Position - pos).Magnitude < 90 then
		return chosen
	end
	local best, bd = nil, 120
	for part in UnitView.views do
		if valid(part) and not part:GetAttribute("Boss") and not part:GetAttribute("Legend") then
			local d = (part.Position - pos).Magnitude
			if d < bd then
				best, bd = part, d
			end
		end
	end
	return best
end

-- Red circles: if we're standing in one, roll out of it.
function AutoHunt.onEvents(list)
	if not on then
		return
	end
	local root = hrp()
	if not root then
		return
	end
	for _, e in list do
		if e[1] == "telegraph" and typeof(e[3]) == "Vector3" then
			local centre, radius = e[3], e[4] or 8
			local flat = Vector3.new(root.Position.X - centre.X, 0, root.Position.Z - centre.Z)
			if flat.Magnitude < radius + 2 then
				local away = flat.Magnitude > 0.1 and flat.Unit or Vector3.new(1, 0, 0)
				local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
				if hum then
					hum:Move(away)
					task.delay(0.05, Controls.dodge)
				end
			end
		end
	end
end

function AutoHunt.start()
	UserInputService.InputBegan:Connect(function(input, processed)
		lastInput = os.clock()
		if MOVE_KEYS[input.KeyCode] then
			lastMoveInput = os.clock()
		end
		if not processed and input.KeyCode == Enum.KeyCode.R then
			AutoHunt.toggle()
		end
	end)
	UserInputService.InputChanged:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseMovement or input.KeyCode == Enum.KeyCode.Thumbstick1 then
			lastInput = os.clock()
		end
	end)

	task.spawn(function()
		while true do
			task.wait(0.15)
			if not on then
				continue
			end
			local root = hrp()
			local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
			if not root or not hum or hum.Health <= 0 then
				continue
			end
			if os.clock() - lastInput > A.IdleMinutes * 60 then
				AutoHunt.set(false, "Auto-Hunt paused: you've been away a while. Press R to start again")
				continue
			end
			if hum.Health < hum.MaxHealth * 0.25 then
				AutoHunt.set(false, "Auto-Hunt paused: your HP is low. Rest at a campfire")
				continue
			end
			local pos = root.Position
			if not valid(target) or (target :: BasePart).Position.Y < -500 then
				target = pickTarget(pos)
				if target then
					Controls.focus(target :: BasePart)
				end
			end
			if not target then
				continue
			end
			local t = target :: BasePart
			local w = Config.Tuning.Weapons[player:GetAttribute("Weapon") or "Blade"] or Config.Tuning.Weapons.Blade
			local want = w.Ranged and math.min(w.Range - 6, 26) or math.max(3, w.Range - 2)
			local flat = Vector3.new(t.Position.X - pos.X, 0, t.Position.Z - pos.Z)
			local dist = flat.Magnitude - t.Size.X / 2
			-- walk into range (unless the player is steering right now)
			if os.clock() - lastMoveInput > 3 then
				if dist > want then
					hum:MoveTo(t.Position - flat.Unit * (want * 0.8))
				else
					hum:Move(Vector3.zero)
				end
			end
			if dist <= want + 4 then
				Controls.attack(flat)
				-- weapon skill when it's up
				Controls.skill(flat)
				-- team ultimates when ready
				for slot = 1, 3 do
					for part in UnitView.views do
						if part:GetAttribute("Owner") == player.UserId and part:GetAttribute("Slot") == slot and part:GetAttribute("State") ~= "fainted" then
							if (part:GetAttribute("CdB") or 0) <= workspace:GetServerTimeNow() then
								Controls.team(slot)
							end
						end
					end
				end
			end
		end
	end)
end

return AutoHunt

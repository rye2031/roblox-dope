-- Player combat input and weapon visuals.
--   Click / hold LMB (or the Attack button): attack toward the cursor, snapping to a monster
--   under it. Clicking a wild monster also focuses your team on it.
--   Q: weapon skill · Shift: dodge roll · 1/2/3: your team's ultimates.
-- The server validates every intent (range, cooldowns); this file only aims and animates.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local UnitView = require(script.Parent.UnitView)
local TamerAnim = require(script.Parent.TamerAnim)
local Sfx = require(script.Parent.Sfx)

local T = Config.Tuning
local player = Players.LocalPlayer
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local Intent = remotes:WaitForChild("Intent") :: RemoteEvent

local Controls = {}
Controls.target = nil :: BasePart? -- the wild unit you last clicked or hit
Controls.dodgeReady = 0
Controls.onTarget = nil :: ((BasePart?) -> ())?

local function hrp(): BasePart?
	local c = player.Character
	return c and c:FindFirstChild("HumanoidRootPart") :: BasePart?
end

local function weapon()
	return T.Weapons[player:GetAttribute("Weapon") or "Blade"] or T.Weapons.Blade
end

local function setTarget(part: BasePart?)
	if Controls.target ~= part then
		Controls.target = part
		if Controls.onTarget then
			Controls.onTarget(part)
		end
	end
end

-- Wild unit closest to a screen point (within `radius` px), or nil.
local function unitAtScreen(pt: Vector2, radius: number): BasePart?
	local cam = workspace.CurrentCamera
	local best, bd = nil, radius
	for part in UnitView.views do
		if part.Parent and part:GetAttribute("Side") == "wild" and part:GetAttribute("State") ~= "dead" then
			local sp, on = cam:WorldToViewportPoint(part.Position)
			if on then
				local d = (Vector2.new(sp.X, sp.Y) - pt).Magnitude
				-- bigger monsters are easier to click
				local scale = math.clamp(part.Size.Y * 600 / math.max(sp.Z, 1), 0, 200)
				if d < bd + scale * 0.5 then
					best, bd = part, d
				end
			end
		end
	end
	return best
end

-- Nearest living wild unit to the player within `range` studs.
local function nearestWild(range: number): BasePart?
	local root = hrp()
	if not root then
		return nil
	end
	local best, bd = nil, range
	for part in UnitView.views do
		if part.Parent and part:GetAttribute("Side") == "wild" and part:GetAttribute("State") ~= "dead" then
			local d = (part.Position - root.Position).Magnitude - part.Size.X / 2
			if d < bd then
				best, bd = part, d
			end
		end
	end
	return best
end

local touch = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
Controls.touch = touch

-- Aim direction for an attack: the clicked/hovered monster, else the cursor point on the
-- ground, else (touch) the target or nearest monster, else where the character faces.
local function aim(): Vector3?
	local root = hrp()
	if not root then
		return nil
	end
	local w = weapon()
	local reach = (w.Range or 8) + 6
	local tgt: BasePart? = nil
	if not touch then
		local m = UserInputService:GetMouseLocation()
		tgt = unitAtScreen(m, 40)
		if not tgt then
			local cam = workspace.CurrentCamera
			local ray = cam:ViewportPointToRay(m.X, m.Y)
			local params = RaycastParams.new()
			params.FilterType = Enum.RaycastFilterType.Exclude
			params.FilterDescendantsInstances = { player.Character, workspace:FindFirstChild("UnitViews"), workspace:FindFirstChild("CombatFx") }
			local hit = workspace:Raycast(ray.Origin, ray.Direction * 500, params)
			local point = hit and hit.Position or (ray.Origin + ray.Direction * 60)
			local d = point - root.Position
			if Vector3.new(d.X, 0, d.Z).Magnitude > 1 then
				return d
			end
		end
	else
		local t = Controls.target
		if t and t.Parent and t:GetAttribute("State") ~= "dead" and (t.Position - root.Position).Magnitude < reach + 10 then
			tgt = t
		else
			tgt = nearestWild(reach)
		end
	end
	if tgt then
		setTarget(tgt)
		return tgt.Position - root.Position
	end
	return root.CFrame.LookVector
end

local function faceToward(dir: Vector3)
	local root = hrp()
	local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if not root or not hum or hum.Sit then
		return
	end
	local flat = Vector3.new(dir.X, 0, dir.Z)
	if flat.Magnitude < 0.01 then
		return
	end
	root.CFrame = CFrame.lookAt(root.Position, root.Position + flat.Unit)
end

local nextAttack = 0
function Controls.attack()
	local now = os.clock()
	if now < nextAttack then
		return
	end
	local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if not hum or hum.Health <= 0 then
		return
	end
	local dir = aim()
	if not dir then
		return
	end
	nextAttack = now + weapon().Cooldown
	faceToward(dir)
	Intent:FireServer("attack", dir)
	TamerAnim.play(player, player:GetAttribute("Weapon") or "Blade", false, true)
end

function Controls.skill()
	local ready = player:GetAttribute("WeaponSkillReady") or 0
	if workspace:GetServerTimeNow() < ready - 0.1 then
		return
	end
	local dir = aim()
	if dir then
		faceToward(dir)
		Intent:FireServer("wskill", dir)
		TamerAnim.play(player, player:GetAttribute("Weapon") or "Blade", true, true)
	end
end

function Controls.dodge()
	local now = os.clock()
	if now < Controls.dodgeReady then
		return
	end
	local root = hrp()
	local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if not root or not hum or hum.Health <= 0 then
		return
	end
	Controls.dodgeReady = now + T.Tamer.DodgeCooldown
	Intent:FireServer("dodge")
	local dir = hum.MoveDirection.Magnitude > 0.1 and hum.MoveDirection or root.CFrame.LookVector
	dir = Vector3.new(dir.X, 0, dir.Z).Unit
	local att = Instance.new("Attachment")
	att.Parent = root
	local lv = Instance.new("LinearVelocity")
	lv.Attachment0 = att
	lv.MaxForce = 1e6
	lv.VelocityConstraintMode = Enum.VelocityConstraintMode.Plane
	lv.PrimaryTangentAxis = Vector3.new(1, 0, 0)
	lv.SecondaryTangentAxis = Vector3.new(0, 0, 1)
	lv.PlaneVelocity = Vector2.new(dir.X, dir.Z) * (T.Tamer.DodgeDistance / T.Tamer.DodgeTime)
	lv.RelativeTo = Enum.ActuatorRelativeTo.World
	lv.Parent = root
	task.delay(T.Tamer.DodgeTime, function()
		lv:Destroy()
		att:Destroy()
	end)
	-- face the roll direction (yaw only) and play the tucked roll on the body joints
	root.CFrame = CFrame.lookAt(root.Position, root.Position + dir)
	hum:SetStateEnabled(Enum.HumanoidStateType.FallingDown, false)
	hum:SetStateEnabled(Enum.HumanoidStateType.Ragdoll, false)
	TamerAnim.dodge(player)
	Sfx.play("dodge")
end

function Controls.team(slot: number)
	Intent:FireServer("team", slot)
end

function Controls.focus(part: BasePart)
	setTarget(part)
	Intent:FireServer("focus", part.Name)
end

function Controls.onEvents(_list) end

----------------------------------------------------------------------------------------------

function Controls.start()
	TamerAnim.start()

	local holding = false
	UserInputService.InputBegan:Connect(function(input, processed)
		if processed then
			return
		end
		local k = input.KeyCode
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			holding = true
			local m = UserInputService:GetMouseLocation()
			local u = unitAtScreen(m, 40)
			if u then
				Controls.focus(u)
			end
			Controls.attack()
		elseif k == Enum.KeyCode.Q then
			Controls.skill()
		elseif k == Enum.KeyCode.LeftShift or k == Enum.KeyCode.RightShift then
			Controls.dodge()
		elseif k == Enum.KeyCode.One then
			Controls.team(1)
		elseif k == Enum.KeyCode.Two then
			Controls.team(2)
		elseif k == Enum.KeyCode.Three then
			Controls.team(3)
		elseif k == Enum.KeyCode.ButtonR2 then
			holding = true
			Controls.attack()
		elseif k == Enum.KeyCode.ButtonX then
			Controls.skill()
		elseif k == Enum.KeyCode.ButtonB then
			Controls.dodge()
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.KeyCode == Enum.KeyCode.ButtonR2 then
			holding = false
		end
	end)

	RunService.RenderStepped:Connect(function()
		if holding then
			Controls.attack()
		end
		-- drop a dead or vanished target
		local t = Controls.target
		if t and (not t.Parent or t:GetAttribute("State") == "dead") then
			setTarget(nil)
		end
	end)
end

return Controls

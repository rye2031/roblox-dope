-- Landmarks on the client: windmill blades turn, wind-lift pads throw you up to the sky
-- islands, and every discovery you haven't found yet shows a small sparkle when you're near.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Discoveries = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Discoveries"))
local Ui = require(script.Parent.Ui)
local Sfx = require(script.Parent.Sfx)

local Landmarks = {}
local player = Players.LocalPlayer

local function sparkle(pos: Vector3): BasePart
	local p = Instance.new("Part")
	p.Name = "DiscoveryGlint"
	p.Shape = Enum.PartType.Ball
	p.Size = Vector3.new(1.1, 1.1, 1.1)
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Material = Enum.Material.Neon
	p.Color = Color3.fromRGB(255, 236, 150)
	p.CFrame = CFrame.new(pos + Vector3.new(0, 1, 0))
	local e = Instance.new("ParticleEmitter")
	e.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	e.Color = ColorSequence.new(Color3.fromRGB(255, 240, 170), Color3.new(1, 1, 1))
	e.Rate = 8
	e.Lifetime = NumberRange.new(0.8, 1.4)
	e.Speed = NumberRange.new(1, 3)
	e.Size = NumberSequence.new(0.5, 0)
	e.LightEmission = 0.8
	e.Parent = p
	p.Parent = workspace
	return p
end

function Landmarks.start()
	-- windmills: blades turn around their hub
	local blades = {}
	local pads = {}
	-- parts can stream in later (far regions), so watch for them as well as scanning once
	local function consider(d: Instance)
		if not d:IsA("BasePart") then
			return
		end
		if d:GetAttribute("Lift") then
			table.insert(pads, d)
		elseif d:GetAttribute("Blade") then
			task.defer(function()
				local hub = d:FindFirstChild("Hub") :: ObjectValue?
				local h = hub and hub.Value :: BasePart?
				if h then
					table.insert(blades, { part = d, hub = h, off = h.CFrame:ToObjectSpace(d.CFrame) })
				end
			end)
		end
	end
	for _, d in workspace:GetDescendants() do
		consider(d)
	end
	workspace.DescendantAdded:Connect(consider)
	-- discovery sparkles
	local glints: { [string]: BasePart } = {}
	for _, d in Discoveries.List do
		glints[d.id] = sparkle(d.pos)
	end
	Ui.onProfile(function(p)
		for id, g in glints do
			if p.found and p.found[id] then
				g:Destroy()
				glints[id] = nil
			end
		end
	end)
	local lastLift = 0
	local flight: { vx: number, vz: number, untilT: number, hrp: BasePart }? = nil
	RunService.Heartbeat:Connect(function()
		local f = flight
		if f then
			if os.clock() >= f.untilT or not f.hrp.Parent then
				flight = nil
			else
				local v = f.hrp.AssemblyLinearVelocity
				f.hrp.AssemblyLinearVelocity = Vector3.new(f.vx, v.Y, f.vz)
			end
		end
	end)
	RunService.RenderStepped:Connect(function()
		local t = os.clock()
		for _, b in blades do
			b.part.CFrame = b.hub.CFrame * CFrame.Angles(0, 0, t * 0.9) * b.off
		end
		local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not hrp then
			return
		end
		for id, g in glints do
			local d = (g.Position - hrp.Position).Magnitude
			g.Transparency = d < 90 and 0.1 or 1
			g.CFrame = CFrame.new(Discoveries.ById[id].pos + Vector3.new(0, 1.2 + math.sin(t * 2) * 0.3, 0)) * CFrame.Angles(0, t, 0)
		end
		if t - lastLift > 2 then
			for _, pad in pads do
				local d = hrp.Position - pad.Position
				if Vector3.new(d.X, 0, d.Z).Magnitude < 4 and math.abs(d.Y) < 6 then
					-- a throw that lands on the target in ~1.3 s
					local target = pad:GetAttribute("Lift") :: Vector3
					local T = 1.3
					local g = workspace.Gravity
					local dx = target - hrp.Position
					local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
					if hum then
						hum:ChangeState(Enum.HumanoidStateType.Freefall)
					end
					local v = Vector3.new(dx.X / T, dx.Y / T + 0.5 * g * T, dx.Z / T)
					hrp.AssemblyLinearVelocity = v
					-- the humanoid's own air control would cancel the sideways part: hold it
					flight = { vx = v.X, vz = v.Z, untilT = t + T, hrp = hrp }
					lastLift = t
					Sfx.play("dodge", { pitch = 0.8 })
				end
			end
		end
	end)
	-- found one
	local remote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Discovery") :: RemoteEvent
	remote.OnClientEvent:Connect(function(msg)
		if typeof(msg) ~= "table" then
			return
		end
		Ui.toast(string.format("🔍 Discovery: %s! +%d 💰 +%d 🥚  (%d/%d)", msg.name, msg.coins, msg.scrolls, msg.n, msg.total), "good")
		Sfx.play("reveal_rare")
		if msg.all then
			task.delay(1.5, Ui.toast, "🌟 You found every discovery! +1 Legendary Egg", "good")
		end
	end)
end

return Landmarks

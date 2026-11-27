-- Places the map-pass props (PropData) on the client. Each prop appears when you're within
-- ~220 studs and goes away past ~260. Uploaded props (ReplicatedStorage/PropModels) are
-- cloned freely; baked ones share one runtime mesh per kind through MeshLoader (as
-- "optional", so monsters always win a pool slot). Decor only: no collisions.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local PropData = require(Shared.PropData)
local MeshLoader = require(Shared.MeshLoader)

local PropView = {}
local player = Players.LocalPlayer

local SHOW, HIDE = 220, 260
local folder = Instance.new("Folder")
folder.Name = "Props"
folder.Parent = workspace

type Live = { part: BasePart, release: () -> () }
local live: { [number]: Live } = {}

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Include

local function groundAt(x: number, z: number): number
	local world = workspace:FindFirstChild("World")
	rayParams.FilterDescendantsInstances = { workspace.Terrain, world }
	local hit = workspace:Raycast(Vector3.new(x, 300, z), Vector3.new(0, -600, 0), rayParams)
	return hit and hit.Position.Y or 2
end

local function uploaded(mesh: string): BasePart?
	local f = ReplicatedStorage:FindFirstChild("PropModels")
	local m = f and f:FindFirstChild(mesh)
	if not m then
		return nil
	end
	return (m:IsA("BasePart") and m or m:FindFirstChildWhichIsA("MeshPart", true)) :: BasePart?
end

local function spawnProp(i: number, d)
	local part: BasePart? = nil
	local release = function() end
	local tpl = uploaded(d.mesh)
	if tpl then
		local c = tpl:Clone()
		c.Size = tpl.Size * (d.h / tpl.Size.Y)
		part = c
	else
		local mp = MeshLoader.get(d.mesh, d.h, { optional = true })
		if mp then
			part = mp
			local done = false
			release = function()
				if not done then
					done = true
					MeshLoader.release(d.mesh)
				end
			end
		end
	end
	if not part then
		return
	end
	local p = part :: BasePart
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = true
	local y = groundAt(d.x, d.z)
	p.CFrame = CFrame.new(d.x, y + p.Size.Y / 2 - 0.2, d.z) * CFrame.Angles(0, math.rad(d.yaw or 0), 0)
	p.Name = d.mesh
	p.Parent = folder
	live[i] = { part = p, release = release }
end

local function despawn(i: number)
	local l = live[i]
	if l then
		live[i] = nil
		l.part:Destroy()
		l.release()
	end
end

function PropView.start()
	task.spawn(function()
		workspace:WaitForChild("World", 60)
		task.wait(2)
		while true do
			local char = player.Character
			local hrp = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
			if hrp then
				local pos = hrp.Position
				for i, d in PropData.List do
					local dist = (Vector3.new(d.x, pos.Y, d.z) - pos).Magnitude
					if dist < SHOW and not live[i] then
						spawnProp(i, d)
					elseif dist > HIDE and live[i] then
						despawn(i)
					end
				end
			end
			task.wait(0.6)
		end
	end)
end

function PropView.stats(): string
	local n = 0
	for _ in live do
		n += 1
	end
	return n .. " props shown"
end

return PropView

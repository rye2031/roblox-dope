-- Studio debug: a wall of every species in every element (real models, element recolour) high
-- above the map, one row per species, for screenshots. `gallery <page>` builds a page and
-- points the camera at it; `gallery 0` clears it and gives the camera back.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Monsters = require(Shared.Monsters)
local Theme = require(Shared.Theme)
local Models = require(script.Parent.Models)
local Ui = require(script.Parent.Ui)

local DebugGallery = {}
local ELEMENTS = { "Fire", "Water", "Wind", "Light", "Dark" }
local ROWS, GROUPS = 7, 2 -- 14 species per page, in two side-by-side groups
local CELL, ROW_H, H = 9, 8.5, 6
local ORIGIN = Vector3.new(0, 600, 0)

local folder: Folder? = nil
local releases = {}

local function sorted(): { string }
	local list = {}
	for id in Monsters.Species do
		table.insert(list, id)
	end
	table.sort(list, function(a, b)
		local sa, sb = Monsters.Species[a], Monsters.Species[b]
		if sa.Stars ~= sb.Stars then
			return sa.Stars < sb.Stars
		end
		return sa.Name < sb.Name
	end)
	return list
end

-- Text painted on a thin card facing the camera (billboards get hidden by the label LOD).
local function label(parent: BasePart, text: string, size: number, color: Color3?)
	parent.Size = Vector3.new(8.4, 3.6, 0.1)
	parent.Transparency = 1
	local bb = Instance.new("SurfaceGui")
	bb.Face = Enum.NormalId.Back
	bb.CanvasSize = Vector2.new(420, 180)
	bb.LightInfluence = 0
	bb.Parent = parent
	local t = Instance.new("TextLabel")
	t.TextWrapped = true
	t.Size = UDim2.fromScale(1, 1)
	t.BackgroundTransparency = 1
	t.Text = text
	t.TextSize = size * 2.6
	t.Font = Enum.Font.GothamBold
	t.TextColor3 = color or Color3.fromRGB(60, 50, 90)
	t.Parent = bb
end

local function anchor(pos: Vector3): BasePart
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.Transparency = 1
	p.Size = Vector3.new(0.2, 0.2, 0.2)
	p.Position = pos
	p.Parent = folder
	return p
end

function DebugGallery.clear()
	for _, r in releases do
		r()
	end
	releases = {}
	if folder then
		folder:Destroy()
		folder = nil
	end
	game:GetService("RunService"):UnbindFromRenderStep("DebugGallery")
	local cam = workspace.CurrentCamera
	cam.CameraType = Enum.CameraType.Custom
	cam.FieldOfView = 70
	Ui.screenGui.Enabled = true
end

function DebugGallery.show(page: number): string
	DebugGallery.clear()
	if page <= 0 then
		return "cleared"
	end
	local list = sorted()
	local per = ROWS * GROUPS
	local first = (page - 1) * per + 1
	if first > #list then
		return "no page " .. page .. " (" .. #list .. " species)"
	end
	folder = Instance.new("Folder")
	folder.Name = "DebugGallery"
	folder.Parent = workspace
	local groupW = CELL * (#ELEMENTS + 1.6)
	local totalW = groupW * GROUPS
	-- a soft backdrop and a floor strip under each row
	local back = Instance.new("Part")
	back.Anchored = true
	back.Size = Vector3.new(totalW + 20, ROWS * ROW_H + 24, 1)
	back.Position = ORIGIN + Vector3.new(totalW / 2 - 4, -ROWS * ROW_H / 2 + 6, -8)
	back.Color = Color3.fromRGB(236, 238, 246)
	back.Material = Enum.Material.SmoothPlastic
	back.Parent = folder
	local shown = 0
	for g = 0, GROUPS - 1 do
		local gx = g * groupW
		for c, el in ELEMENTS do
			local info = require(Shared.Config).ElementInfo[el]
			label(anchor(ORIGIN + Vector3.new(gx + CELL * (c + 0.6), H + 3.4, 0)), info.Icon .. " " .. el, 18, info.Color:Lerp(Color3.new(0, 0, 0), 0.25))
		end
		for r = 1, ROWS do
			local id = list[first + g * ROWS + r - 1]
			if not id then
				break
			end
			shown += 1
			local sp = Monsters.Species[id]
			local y = ORIGIN.Y - (r - 1) * ROW_H
			local strip = Instance.new("Part")
			strip.Anchored = true
			strip.Size = Vector3.new(groupW - 1, 0.4, 5)
			strip.Position = Vector3.new(gx + groupW / 2 + CELL * 0.1, y - 0.2, 0)
			strip.Color = r % 2 == 0 and Color3.fromRGB(222, 224, 236) or Color3.fromRGB(212, 214, 230)
			strip.Parent = folder
			label(anchor(Vector3.new(gx + CELL * 0.45, y + H / 2, 0)), sp.Name .. "\n" .. string.rep("★", sp.Stars), 15)
			for c, el in ELEMENTS do
				local part, release = Models.get(id, el, H)
				table.insert(releases, release)
				part.CFrame = CFrame.new(gx + CELL * (c + 0.6), y + H / 2 + (sp.Hover and 0.4 or 0), 0) * CFrame.Angles(0, math.rad(155), 0)
				part.Parent = folder
			end
		end
	end
	-- camera straight at the wall
	local cam = workspace.CurrentCamera
	cam.CameraType = Enum.CameraType.Scriptable
	cam.FieldOfView = 30
	local centre = ORIGIN + Vector3.new(totalW / 2 - 2, -(ROWS - 1) * ROW_H / 2 + 2, 0)
	local dist = (ROWS * ROW_H + 10) / 2 / math.tan(math.rad(15)) * 1.02
	local want = CFrame.lookAt(centre + Vector3.new(0, 0, dist), centre)
	cam.CFrame = want
	-- hold it every frame (the default camera scripts pull it back to the character)
	game:GetService("RunService"):BindToRenderStep("DebugGallery", Enum.RenderPriority.Last.Value, function()
		local c = workspace.CurrentCamera
		c.CameraType = Enum.CameraType.Scriptable
		c.FieldOfView = 30
		c.CFrame = want
	end)
	Ui.screenGui.Enabled = false
	local toasts = Players.LocalPlayer.PlayerGui:FindFirstChild("WildToasts")
	if toasts then
		toasts.Enabled = false
	end
	local _ = Theme
	return string.format("page %d: species %d-%d of %d", page, first, first + shown - 1, #list)
end

return DebugGallery

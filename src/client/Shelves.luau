-- Draws this player's shelf displays in the hideout: a portrait of each displayed creature on
-- the shared shelf frames (every client sees its own shelves), the coin rate under it, locked
-- and empty states, and the tip jar's fill + amount. Portraits use EditableImages, so the
-- shelves never take one of the client's few EditableMesh slots.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Creatures = require(Shared.Creatures)
local Portraits = require(Shared.Portraits)
local Theme = require(Shared.Theme)
local Hud = require(script.Parent.Hud)

local C = Theme.C
local player = Players.LocalPlayer

local Shelves = {}

type Slot = { frame: BasePart, img: ImageLabel, big: TextLabel, title: TextLabel, rate: TextLabel, key: string? }
local slots: { [number]: Slot } = {}
local jarFill: BasePart? = nil
local jarFillBase: CFrame? = nil
local jarSub: TextLabel? = nil

local function fmtRate(r: number): string
	return r >= 10 and tostring(math.floor(r + 0.5)) or string.format("%.1f", r)
end

local function makeSlot(frame: BasePart): Slot
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 60
	gui.LightInfluence = 0
	gui.Parent = frame
	local bg = Theme.new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(1, 1, 1), Parent = gui }, {
		Theme.new("UIStroke", { Thickness = 6, Color = C.Mint, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }),
	})
	local img = Theme.new("ImageLabel", { Size = UDim2.new(1, -16, 0.7, 0), Position = UDim2.fromOffset(8, 8), BackgroundTransparency = 1, ScaleType = Enum.ScaleType.Fit, Parent = bg })
	local big = Theme.text({ Size = UDim2.new(1, 0, 0.5, 0), Position = UDim2.fromScale(0, 0.12), Text = "+", TextColor3 = C.Mute, Parent = bg }, "Title")
	local title = Theme.text({ Size = UDim2.new(1, -12, 0.1, 0), Position = UDim2.new(0, 6, 0.72, 0), Text = "", Parent = bg }, "Title")
	local rate = Theme.text({ Size = UDim2.new(1, -12, 0.1, 0), Position = UDim2.new(0, 6, 0.85, 0), Text = "", TextColor3 = Color3.fromRGB(40, 160, 110), Parent = bg }, "Bold")
	return { frame = frame, img = img, big = big, title = title, rate = rate, key = nil }
end

local function render(profile)
	for i, sl in slots do
		local e = profile.display[i]
		local key
		if i > profile.slots then
			key = "locked"
		elseif e and e.s then
			key = e.s .. ":" .. e.f
		else
			key = "empty"
		end
		if key ~= sl.key then
			sl.key = key
			if key == "locked" then
				sl.img.Visible = false
				sl.big.Visible = true
				sl.big.Text = "🔒"
				local price = Config.Tuning.Display.SlotCosts[i - Config.Tuning.Display.StartSlots]
				sl.title.Text = "Locked"
				sl.rate.Text = price and ("$ " .. price) or ""
				sl.rate.TextColor3 = C.Sub
			elseif key == "empty" then
				sl.img.Visible = false
				sl.big.Visible = true
				sl.big.Text = "+"
				sl.title.Text = "Empty"
				sl.rate.Text = "add a creature"
				sl.rate.TextColor3 = C.Sub
			else
				local sp = Creatures.Species[e.s]
				Portraits.apply(sl.img, e.s)
				sl.img.ImageColor3 = e.f == "Glazed" and Color3.fromRGB(255, 245, 200) or Color3.new(1, 1, 1)
				sl.img.Visible = true
				sl.big.Visible = false
				sl.title.Text = sp.Name
				sl.rate.Text = "+" .. fmtRate(Config.displayRate(sp, e.f)) .. " / min"
				sl.rate.TextColor3 = Color3.fromRGB(40, 160, 110)
			end
		end
	end
end

function Shelves.start()
	local hideout = workspace:WaitForChild("Map"):WaitForChild("Hideout")
	local folder = hideout:WaitForChild("Shelves")
	for _, d in folder:GetChildren() do
		if d:IsA("BasePart") and d:GetAttribute("Shelf") then
			slots[d:GetAttribute("Shelf")] = makeSlot(d)
		end
	end
	jarFill = folder:FindFirstChild("JarFill") :: BasePart?
	jarFillBase = jarFill and jarFill.CFrame
	local labels = workspace.Map:WaitForChild("Labels")
	local jarLabel = labels:WaitForChild("Label_Jar")
	jarSub = jarLabel:FindFirstChild("Sub", true) :: TextLabel?

	local lastProfile = nil
	RunService.Heartbeat:Connect(function()
		local p = Hud.getProfile()
		if p and p ~= lastProfile then
			lastProfile = p
			render(p)
		end
		-- jar: fill height follows the jar against its cap
		local jar = player:GetAttribute("Jar") or 0
		local rate = player:GetAttribute("IncomeRate") or 0
		local D = Config.Tuning.Display
		local cap = math.max(D.MinJarCap, rate * D.JarCapMinutes)
		local k = math.clamp(jar / cap, 0, 1)
		if jarFill and jarFillBase then
			local h = 0.2 + k * 3.4
			jarFill.Size = Vector3.new(h, jarFill.Size.Y, jarFill.Size.Z)
			jarFill.CFrame = jarFillBase + Vector3.new(0, h / 2 - 0.1, 0)
		end
		if jarSub then
			if jar >= 1 then
				jarSub.Text = string.format("$ %d · step here to collect", jar)
			elseif rate > 0 then
				jarSub.Text = string.format("filling at %s a minute", fmtRate(rate))
			else
				jarSub.Text = "fill your shelves to earn"
			end
		end
	end)
end

return Shelves

-- Summon reveal screens.
--   Single: the egg (a 3D Meshy model: Regular, Legendary or Eclipse) drops in and bounces,
--   wobbles harder while cracks spread (a 5★ glows purple, then "upgrades" to gold), swells and
--   bursts into shell pieces and the monster's card while the stars pop in. 4★/5★ get
--   lightning strikes.
--   Ten: ten sealed cards fly into a 5×2 grid and flip one at a time; before a 4★ or 5★ card
--   flips, lightning cracks down onto it with a flash and a screen shake.
-- Click (or press Space) to skip ahead. Buttons call back into the Shrine panel.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Monsters = require(Shared.Monsters)
local Ui = require(script.Parent.Ui)
local Sfx = require(script.Parent.Sfx)
local MeshLoader = require(Shared.MeshLoader)

local C = Ui.C
local px = Ui.px
local new = Ui.new
local EI = Config.ElementInfo
local SummonReveal = {}

local RARITY = {
	[1] = Color3.fromRGB(196, 202, 214),
	[2] = Color3.fromRGB(130, 214, 156),
	[3] = Color3.fromRGB(102, 174, 255),
	[4] = Color3.fromRGB(186, 112, 255),
	[5] = Color3.fromRGB(255, 198, 58),
}
SummonReveal.rarity = RARITY

local gui = new("ScreenGui", {
	Name = "SummonReveal",
	DisplayOrder = 40,
	IgnoreGuiInset = true,
	ResetOnSpawn = false,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	Enabled = false,
	Parent = Players.LocalPlayer:WaitForChild("PlayerGui"),
})
local dim = new("Frame", { Name = "Dim", Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromRGB(14, 14, 26), BackgroundTransparency = 1, ZIndex = 1, Parent = gui })
local stage = new("Frame", { Name = "Stage", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 2, Parent = gui })
local fxLayer = new("Frame", { Name = "Fx", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 30, Parent = gui })
local flashF = new("Frame", { Name = "Flash", Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 1, ZIndex = 50, Parent = gui })

local token = 0 -- bumps on every new reveal so old coroutines stop
local skipping = false

local function tween(obj: Instance, t: number, props: { [string]: any }, style: Enum.EasingStyle?, dir: Enum.EasingDirection?)
	local tw = TweenService:Create(obj, TweenInfo.new(t, style or Enum.EasingStyle.Quad, dir or Enum.EasingDirection.Out), props)
	tw:Play()
	return tw
end

-- Waits, but returns early when the player skips. Returns false if this reveal was replaced.
local function pause(t: number, my: number): boolean
	local s = os.clock()
	while os.clock() - s < t do
		if token ~= my then
			return false
		end
		if skipping then
			return true
		end
		RunService.RenderStepped:Wait()
	end
	return token == my
end

local function clearAll()
	for _, f in { stage, fxLayer } do
		for _, c in f:GetChildren() do
			c:Destroy()
		end
	end
	-- the 3D hatch egg lives in workspace
	for _, c in workspace:GetChildren() do
		if c.Name == "HatchEgg" then
			c:Destroy()
		end
	end
end

local function label(parent: Instance, props: { [string]: any }, weight: string?)
	props.BackgroundTransparency = 1
	props.TextScaled = props.TextScaled or false
	props.Parent = parent
	return Ui.text(props, weight or "Title")
end

local function flash(color: Color3, strength: number)
	flashF.BackgroundColor3 = color
	flashF.BackgroundTransparency = 1 - strength
	tween(flashF, 0.35, { BackgroundTransparency = 1 })
end

local function shake(amount: number, dur: number)
	local s = os.clock()
	local conn
	conn = RunService.RenderStepped:Connect(function()
		local k = (os.clock() - s) / dur
		if k >= 1 then
			stage.Position = UDim2.new()
			conn:Disconnect()
			return
		end
		local a = amount * (1 - k)
		stage.Position = UDim2.fromOffset((math.random() - 0.5) * 2 * a, (math.random() - 0.5) * 2 * a)
	end)
end

-- A straight glowing segment between two screen points.
local function segment(parent: Instance, a: Vector2, b: Vector2, thick: number, color: Color3, transp: number, z: number): Frame
	local d = b - a
	return new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset((a.X + b.X) / 2, (a.Y + b.Y) / 2),
		Size = UDim2.fromOffset(d.Magnitude + thick * 0.6, thick),
		Rotation = math.deg(math.atan2(d.Y, d.X)),
		BackgroundColor3 = color,
		BackgroundTransparency = transp,
		BorderSizePixel = 0,
		ZIndex = z,
		Parent = parent,
	}, { new("UICorner", { CornerRadius = UDim.new(0.5, 0) }) })
end

local function jagged(from: Vector2, to: Vector2, n: number, spread: number): { Vector2 }
	local pts = { from }
	local d = to - from
	local perp = Vector2.new(-d.Y, d.X).Unit
	for i = 1, n - 1 do
		local k = i / n
		table.insert(pts, from + d * k + perp * (math.random() - 0.5) * 2 * spread * math.sin(k * math.pi))
	end
	table.insert(pts, to)
	return pts
end

-- Lightning from the top of the screen down to `to` (screen pixels), with a branch or two.
local function lightning(to: Vector2, color: Color3, scale: number)
	Sfx.play("thunder", { pitch = 1.15 - scale * 0.15, vary = 0.06 })
	local vp = workspace.CurrentCamera.ViewportSize
	local from = Vector2.new(math.clamp(to.X + (math.random() - 0.5) * vp.X * 0.35, 0, vp.X), -20)
	local holder = new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 31, Parent = fxLayer })
	local function draw(pts: { Vector2 }, w: number)
		for i = 1, #pts - 1 do
			segment(holder, pts[i], pts[i + 1], w * 3.2, color, 0.55, 31)
			segment(holder, pts[i], pts[i + 1], w, Color3.new(1, 1, 1), 0, 32)
		end
	end
	local main = jagged(from, to, 10, 46 * scale)
	draw(main, 4 * scale)
	for _ = 1, math.random(1, 2) do
		local i = math.random(3, #main - 2)
		local p = main[i]
		local dir = (main[i + 1] - main[i - 1]).Unit
		local side = Vector2.new(-dir.Y, dir.X) * (math.random() < 0.5 and -1 or 1)
		draw(jagged(p, p + (dir + side * 0.9).Unit * (70 + math.random() * 70) * scale, 5, 16 * scale), 2 * scale)
	end
	-- impact glow
	local glow = new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(to.X, to.Y), Size = UDim2.fromOffset(30, 30), BackgroundColor3 = color, BackgroundTransparency = 0.2, ZIndex = 33, Parent = holder }, { new("UICorner", { CornerRadius = UDim.new(0.5, 0) }) })
	tween(glow, 0.3, { Size = UDim2.fromOffset(180 * scale, 180 * scale), BackgroundTransparency = 1 })
	-- flicker, then fade
	task.spawn(function()
		for _, v in { false, true, false, true } do
			task.wait(0.04)
			holder.Visible = v
		end
		for _, f in holder:GetChildren() do
			if f:IsA("Frame") and f ~= glow then
				tween(f, 0.25, { BackgroundTransparency = 1 })
			end
		end
		task.wait(0.3)
		holder:Destroy()
	end)
end

-- Rotating light rays behind a point (returns the holder; destroy it to stop).
local function rays(parent: Instance, centre: UDim2, size: number, color: Color3, z: number, count: number?): Frame
	local h = new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = centre, Size = UDim2.fromOffset(size, size), BackgroundTransparency = 1, ZIndex = z, Parent = parent })
	local n = count or 12
	for i = 1, n do
		new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.new(1, 0, 0, math.max(6, size * 0.05)),
			Rotation = (i / n) * 180,
			BackgroundColor3 = color,
			BorderSizePixel = 0,
			ZIndex = z,
			Parent = h,
		}, {
			new("UIGradient", {
				Transparency = NumberSequence.new({
					NumberSequenceKeypoint.new(0, 1),
					NumberSequenceKeypoint.new(0.35, 0.55),
					NumberSequenceKeypoint.new(0.5, 0.2),
					NumberSequenceKeypoint.new(0.65, 0.55),
					NumberSequenceKeypoint.new(1, 1),
				}),
			}),
		})
	end
	local conn
	conn = RunService.RenderStepped:Connect(function(dt)
		if not h.Parent then
			conn:Disconnect()
			return
		end
		h.Rotation += dt * 25
	end)
	return h
end

-- Little sparks flying out of a point.
local function sparks(parent: Instance, centre: Vector2, color: Color3, n: number, dist: number, z: number)
	for _ = 1, n do
		local a = math.random() * math.pi * 2
		local s = math.random(5, 10)
		local f = new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(centre.X, centre.Y), Size = UDim2.fromOffset(s, s), Rotation = 45, BackgroundColor3 = math.random() < 0.4 and Color3.new(1, 1, 1) or color, ZIndex = z, Parent = parent })
		local d = dist * (0.5 + math.random() * 0.6)
		tween(f, 0.55 + math.random() * 0.3, { Position = UDim2.fromOffset(centre.X + math.cos(a) * d, centre.Y + math.sin(a) * d), Size = UDim2.fromOffset(2, 2), BackgroundTransparency = 1 }, Enum.EasingStyle.Quart)
		task.delay(1, function()
			f:Destroy()
		end)
	end
end

local function starsText(n: number): string
	return string.rep("★", n)
end

----------------------------------------------------------------------------------------------
-- Buttons under a reveal

type Handlers = { one: () -> (), ten: () -> (), done: () -> (), kind: string }

local function buttonBar(parent: Instance, h: Handlers, y: UDim, z: number)
	local p = Ui.profile
	local have = p and p.scrolls[h.kind] or 0
	local multi = Config.Tuning.Scrolls.MultiOpen
	local bar = new("Frame", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, y.Scale, y.Offset), Size = UDim2.fromOffset(px(520), px(50)), BackgroundTransparency = 1, ZIndex = z, Parent = parent }, {
		new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Center, Padding = UDim.new(0, px(12)), SortOrder = Enum.SortOrder.LayoutOrder }),
	})
	local function pill(order: number, text: string, color: Color3, enabled: boolean, fn: () -> ())
		local b = Ui.button({ LayoutOrder = order, Size = UDim2.fromOffset(px(160), px(48)), BackgroundColor3 = enabled and color or C.Line, TextColor3 = enabled and Color3.new(1, 1, 1) or C.Sub, TextScaled = false, TextSize = px(17), Text = text, ZIndex = z, Parent = bar, Radius = 24 })
		b.Activated:Connect(function()
			if enabled then
				fn()
			end
		end)
		return b
	end
	if h.kind ~= "Intro" then -- the dream intro only needs "Done"
		pill(1, string.format("Hatch 1  (%d)", have), C.Sky, have >= 1, h.one)
		pill(2, string.format("Hatch %d", multi), C.Lilac, have >= multi, h.ten)
	end
	pill(3, "Done", C.Mint, true, h.done)
	-- pop in
	local sc = new("UIScale", { Scale = 0.6, Parent = bar })
	tween(sc, 0.3, { Scale = 1 }, Enum.EasingStyle.Back)
	return bar
end

----------------------------------------------------------------------------------------------
-- Single reveal

local function monsterCard(parent: Instance, res, w: number, z: number): (Frame, Frame)
	local sp = Monsters.Species[res.sp]
	local info = EI[res.el]
	local rc = RARITY[res.stars] or RARITY[1]
	local h = math.floor(w * 1.32)
	local card = new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(w, h), BackgroundColor3 = Ui.Theme.tint(info.Color, 0.88), ZIndex = z, Parent = parent }, {
		new("UICorner", { CornerRadius = UDim.new(0, math.floor(w * 0.08)) }),
		new("UIStroke", { Color = rc, Thickness = res.stars >= 4 and 4 or 2.5 }),
	})
	local _, img = Ui.portrait(card, res.sp, res.el, UDim2.fromOffset(w * 0.78, w * 0.78), UDim2.new(0.11, 0, 0, w * 0.07), z + 1)
	img.Parent.BackgroundTransparency = 1
	label(card, { Position = UDim2.new(0, 0, 0, w * 0.86), Size = UDim2.new(1, 0, 0, w * 0.11), Text = sp.Name, TextSize = math.floor(w * 0.1), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = z + 2 })
	if res.overflow then
		-- storage was full: this one waits in the Overflow box
		local tag = new("Frame", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, w * 0.04), Size = UDim2.fromOffset(w * 0.62, w * 0.12), BackgroundColor3 = Color3.fromRGB(240, 140, 70), ZIndex = z + 3, Parent = card }, { new("UICorner", { CornerRadius = UDim.new(0.5, 0) }) })
		label(tag, { Size = UDim2.fromScale(1, 1), Text = "→ Overflow", TextSize = math.floor(w * 0.075), TextColor3 = Color3.new(1, 1, 1), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = z + 4 })
	end
	local starRow = new("Frame", { Position = UDim2.new(0, 0, 0, w * 0.98), Size = UDim2.new(1, 0, 0, w * 0.12), BackgroundTransparency = 1, ZIndex = z + 2, Parent = card }, {
		new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Center, SortOrder = Enum.SortOrder.LayoutOrder }),
	})
	label(card, { Position = UDim2.new(0, 0, 0, w * 1.11), Size = UDim2.new(1, 0, 0, w * 0.09), Text = info.Icon .. " " .. res.el .. "  ·  " .. sp.Role .. (res.new and "  ·  NEW!" or ""), TextSize = math.floor(w * 0.065), TextColor3 = info.Color, TextXAlignment = Enum.TextXAlignment.Center, ZIndex = z + 2 })
	return card, starRow
end

local function popStars(row: Frame, n: number, color: Color3, size: number, my: number, delayEach: number)
	for i = 1, n do
		if token ~= my then
			return
		end
		if delayEach > 0 then
			Sfx.play("star", { pitch = 2 ^ ((i - 1) * 2 / 12), vary = 0 })
		end
		local s = label(row, { LayoutOrder = i, Size = UDim2.fromOffset(size, size), Text = "★", TextSize = size, TextColor3 = color, TextStrokeTransparency = 0.6, TextStrokeColor3 = Color3.new(1, 1, 1), ZIndex = row.ZIndex })
		local sc = new("UIScale", { Scale = 2.4, Parent = s })
		tween(sc, 0.22, { Scale = 1 }, Enum.EasingStyle.Back)
		if delayEach > 0 and not skipping then
			task.wait(delayEach)
		end
	end
end

local function single(res, h: Handlers)
	token += 1
	local my = token
	skipping = false
	clearAll()
	gui.Enabled = true
	dim.BackgroundTransparency = 1
	-- the egg is in the 3D world, so the screen only dims lightly until it bursts
	tween(dim, 0.25, { BackgroundTransparency = 0.55 })
	local vp = workspace.CurrentCamera.ViewportSize
	local centre = Vector2.new(vp.X / 2, vp.Y * 0.5)
	local rc = RARITY[res.stars] or RARITY[1]
	local high = res.stars >= 4

	-- the egg: the real Meshy egg for that kind (Regular / Legendary / Eclipse) in a ViewportFrame.
	-- It drops in, wobbles harder and harder while cracks spread over the shell, then bursts
	-- into shell pieces and the monster's card (owner, 2026-11-27).
	local tease = res.stars == 5 and RARITY[4] or rc
	local EGGS = { Regular = "EggRegular", Legendary = "EggLegendary", Eclipse = "EggEclipse" }
	local SHELL = { Regular = Color3.fromRGB(240, 246, 250), Legendary = Color3.fromRGB(255, 186, 70), Eclipse = Color3.fromRGB(140, 104, 214) }
	local eggKind = EGGS[res.kind] and res.kind or "Regular"
	local meshName = EGGS[eggKind]
	-- the egg lives in the real 3D world, just in front of the camera (ViewportFrames don't show
	-- the runtime EditableImage texture, so the egg looked like a flat blob there)
	local scroll = Instance.new("Folder")
	scroll.Name = "HatchEgg"
	scroll.Parent = workspace
	local world = scroll
	local wcam = workspace.CurrentCamera
	local function anchorCF(): CFrame
		-- 12 studs ahead of the camera, a little below centre, facing it
		local cf = wcam.CFrame
		local at = cf.Position + cf.LookVector * 10
		return CFrame.lookAt(at, at + Vector3.new(cf.LookVector.X, 0, cf.LookVector.Z) * -1)
	end
	local backdrop = Instance.new("Part")
	backdrop.Anchored = true
	backdrop.CanCollide = false
	backdrop.CanQuery = false
	backdrop.CastShadow = false
	backdrop.Transparency = 1
	backdrop.Size = Vector3.new(1, 1, 1)
	backdrop.Parent = scroll
	local light = Instance.new("PointLight")
	light.Brightness = 1.2
	light.Range = 14
	light.Color = Color3.new(1, 1, 1)
	light.Parent = backdrop
	-- the uploaded egg in ReplicatedStorage.PropModels, else the baked runtime mesh
	local egg: BasePart? = nil
	local released = false
	local folder = ReplicatedStorage:FindFirstChild("PropModels")
	local tpl = folder and folder:FindFirstChild(meshName)
	local tplPart = tpl and (tpl:IsA("BasePart") and tpl or tpl:FindFirstChildWhichIsA("BasePart", true))
	if tplPart then
		local c = (tplPart :: BasePart):Clone()
		c:ClearAllChildren()
		c.Size = (tplPart :: BasePart).Size * (4.4 / (tplPart :: BasePart).Size.Y)
		egg = c
		released = true
	else
		egg = MeshLoader.get(meshName, 4.4)
	end
	local function release()
		if not released then
			released = true
			if egg and egg:IsA("MeshPart") then
				MeshLoader.release(meshName)
			end
		end
	end
	if not egg then
		local ball = Instance.new("Part")
		ball.Shape = Enum.PartType.Ball
		ball.Size = Vector3.new(3.4, 4.4, 3.4)
		ball.Color = SHELL[eggKind]
		ball.Material = Enum.Material.SmoothPlastic
		egg = ball
		released = true
	end
	local e = egg :: BasePart
	e.Anchored = true
	e.Parent = world
	local baseSize = e.Size
	local st = { lift = 9, tilt = 0, scale = 1, spin = 0.5 }
	local liftV, tiltV, scaleV = Instance.new("NumberValue"), Instance.new("NumberValue"), Instance.new("NumberValue")
	liftV.Value, tiltV.Value, scaleV.Value = 9, 0, 1
	local base = anchorCF()
	backdrop.CFrame = base * CFrame.new(0, 1, 4)
	-- floating world labels draw over 3D: hide them while the egg is up
	local hidden = {}
	for _, d in workspace:GetDescendants() do
		if d:IsA("BillboardGui") and d.Enabled then
			d.Enabled = false
			table.insert(hidden, d)
		end
	end
	scroll.Destroying:Connect(function()
		for _, d in hidden do
			if d.Parent then
				d.Enabled = true
			end
		end
	end)
	-- the rarity glow is a disc behind the egg in 3D (a 2D halo drew over the egg), and it hides
	-- world labels behind it
	local glow = Instance.new("Part")
	glow.Shape = Enum.PartType.Cylinder
	glow.Anchored = true
	glow.CanCollide = false
	glow.CanQuery = false
	glow.CastShadow = false
	glow.Material = Enum.Material.Neon
	glow.Color = tease
	glow.Transparency = 0.45
	glow.Size = Vector3.new(0.2, 0.5, 0.5)
	glow.CFrame = base * CFrame.new(0, 0, 3) * CFrame.Angles(0, math.rad(90), 0) -- behind the egg (base faces the camera)
	glow.Parent = scroll
	TweenService:Create(glow, TweenInfo.new(0.6, Enum.EasingStyle.Back), { Size = Vector3.new(0.2, 7.5, 7.5) }):Play()
	local conn = RunService.RenderStepped:Connect(function(dt)
		st.spin += dt * 0.5
		local k = scaleV.Value
		e.Size = baseSize * k
		e.CFrame = base * CFrame.new(0, liftV.Value - 2.2, 0) * CFrame.Angles(0, 0, math.rad(tiltV.Value)) * CFrame.new(0, e.Size.Y / 2, 0) * CFrame.Angles(0, st.spin, 0)
	end)
	scroll.Destroying:Connect(function()
		conn:Disconnect()
		release()
	end)
	-- cracks: zigzag lines over the shell
	local cracks = new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(centre.X, centre.Y), Size = UDim2.fromOffset(px(130), px(170)), BackgroundTransparency = 1, ZIndex = 11, Parent = stage })
	local function crack(n: number)
		local rnd = Random.new(n * 31 + res.stars)
		local x, y = rnd:NextNumber(0.25, 0.75), rnd:NextNumber(0.25, 0.7)
		for _ = 1, 4 do
			local len = rnd:NextNumber(0.1, 0.2)
			local ang = rnd:NextNumber(-70, 70) + (rnd:NextNumber() < 0.5 and 0 or 180)
			local seg = new("Frame", { AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.fromScale(x, y), Size = UDim2.new(len, 0, 0, px(3)), Rotation = ang, BackgroundColor3 = Color3.fromRGB(70, 50, 40), BorderSizePixel = 0, ZIndex = 12, Parent = cracks })
			new("UIStroke", { Color = Color3.new(1, 1, 1), Thickness = 1, Transparency = 0.3, Parent = seg })
			x += math.cos(math.rad(ang)) * len * 0.8
			y += math.sin(math.rad(ang)) * len * 0.8 * 0.8
		end
		Sfx.play("hit", { pitch = 1.4 + n * 0.1 })
	end
	local halo = new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(centre.X, centre.Y), Size = UDim2.fromOffset(px(60), px(60)), BackgroundColor3 = tease, BackgroundTransparency = 1, ZIndex = 5, Parent = stage }, { new("UICorner", { CornerRadius = UDim.new(0.5, 0) }) })

	task.spawn(function()
		-- 1) the egg drops in and bounces
		TweenService:Create(liftV, TweenInfo.new(0.6, Enum.EasingStyle.Bounce), { Value = 0 }):Play()
		-- (the 2D halo stays hidden while the 3D egg is up)
		if not pause(0.55, my) then
			return
		end
		Sfx.play("scroll_land")
		-- 2) it wobbles, harder each time, and cracks spread
		local sets = high and 3 or 2
		for set = 1, sets do
			if skipping then
				break
			end
			Sfx.play("rattle", { pitch = 1 + set * 0.08 })
			local amp = 8 + set * 5
			for i = 1, 4 do
				TweenService:Create(tiltV, TweenInfo.new(0.07), { Value = (i % 2 == 0 and -1 or 1) * amp }):Play()
				if not pause(0.07, my) then
					return
				end
			end
			TweenService:Create(tiltV, TweenInfo.new(0.08), { Value = 0 }):Play()
			crack(set)
			if not pause(0.28, my) then
				return
			end
		end
		-- 3) a 5★ "upgrades": purple glow turns gold with a crack of lightning
		if res.stars == 5 and not skipping then
			lightning(centre, RARITY[5], 1.2)
			flash(RARITY[5], 0.55)
			shake(px(14), 0.35)
			halo.BackgroundColor3 = rc
			glow.Color = rc
			crack(4)
			if not pause(0.35, my) then
				return
			end
		end
		-- 4) the shell swells and bursts into pieces
		local rayH = rays(stage, UDim2.fromOffset(centre.X, centre.Y), px(high and 620 or 460), rc, 4, high and 16 or 10)
		rayH.BackgroundTransparency = 1
		TweenService:Create(scaleV, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Value = 1.18 }):Play()
		Sfx.play("unroll", { pitch = 1.3 })
		if high and not skipping then
			task.delay(0.15, function()
				if token == my then
					lightning(centre + Vector2.new(-px(60), 0), rc, 1)
					lightning(centre + Vector2.new(px(60), 0), rc, 1)
					shake(px(10), 0.3)
				end
			end)
		end
		if not pause(0.32, my) then
			return
		end
		flash(Color3.new(1, 1, 1), high and 0.9 or 0.6)
		tween(dim, 0.3, { BackgroundTransparency = 0.2 })
		Sfx.play(res.stars >= 5 and "reveal_legend" or res.stars == 4 and "reveal_rare" or "reveal", { pitch = res.stars == 3 and 1.12 or 1, vary = 0 })
		-- shell pieces fly out of the viewport while the card appears
		e.Transparency = 1
		cracks:Destroy()
		local shards = {}
		for i = 1, 14 do
			local w = Instance.new("WedgePart")
			w.Size = Vector3.new(0.25, math.random(6, 12) / 10, math.random(6, 12) / 10)
			w.Color = SHELL[eggKind]:Lerp(Color3.new(1, 1, 1), math.random() * 0.3)
			w.Material = Enum.Material.SmoothPlastic
			w.Anchored = true
			local a = i / 14 * math.pi * 2
			w.CFrame = base * CFrame.new(math.cos(a) * 1.2, math.sin(a * 2) * 1.2, math.sin(a) * 1.2)
			w.Parent = world
			table.insert(shards, { part = w, v = base:VectorToWorldSpace(Vector3.new(math.cos(a) * 9, 6 + math.random() * 6, math.sin(a) * 6 + 3)), r = Vector3.new(math.random() * 8, math.random() * 8, math.random() * 8) })
		end
		local t0 = os.clock()
		local sc2 = RunService.RenderStepped:Connect(function(dt)
			for _, sh in shards do
				sh.v -= Vector3.new(0, 28 * dt, 0)
				sh.part.CFrame = (sh.part.CFrame + sh.v * dt) * CFrame.Angles(sh.r.X * dt, sh.r.Y * dt, sh.r.Z * dt)
				sh.part.Transparency = math.clamp((os.clock() - t0) / 0.7, 0, 1)
			end
		end)
		task.delay(0.75, function()
			sc2:Disconnect()
			if scroll.Parent then
				scroll:Destroy()
			end
		end)
		tween(halo, 0.4, { Size = UDim2.fromOffset(px(520), px(520)), BackgroundTransparency = 0.85 })
		local card, starRow = monsterCard(stage, res, px(300), 10)
		card.Position = UDim2.fromOffset(centre.X, centre.Y)
		local sc = new("UIScale", { Scale = 0.3, Parent = card })
		tween(sc, 0.4, { Scale = 1 }, Enum.EasingStyle.Back)
		sparks(fxLayer, centre, rc, high and 40 or 18, px(high and 360 or 220), 34)
		if not pause(0.3, my) then
			return
		end
		popStars(starRow, res.stars, rc, px(30), my, 0.16)
		if res.stars >= 4 and token == my then
			flash(rc, 0.35)
			shake(px(8), 0.25)
		end
		if token ~= my then
			return
		end
		buttonBar(stage, h, UDim.new(0.44, px(240)), 20)
	end)
end

----------------------------------------------------------------------------------------------
-- Ten reveal

local function multi(list, h: Handlers)
	token += 1
	local my = token
	skipping = false
	clearAll()
	gui.Enabled = true
	dim.BackgroundTransparency = 1
	tween(dim, 0.25, { BackgroundTransparency = 0.15 })
	local vp = workspace.CurrentCamera.ViewportSize
	local cols = 5
	local rows = math.ceil(#list / cols)
	local cw = math.floor(math.min(px(140), (vp.X - px(80)) / cols - px(14)))
	local ch = math.floor(cw * 1.32)
	local gap = px(14)
	local gridW = cols * cw + (cols - 1) * gap
	local gridH = rows * ch + (rows - 1) * gap
	local x0 = (vp.X - gridW) / 2 + cw / 2
	local y0 = vp.Y * 0.43 - gridH / 2 + ch / 2

	local title = label(stage, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0.43, -gridH / 2 - px(58)), Size = UDim2.fromOffset(px(500), px(40)), Text = "Opening " .. #list .. " eggs...", TextSize = px(28), TextColor3 = Color3.new(1, 1, 1), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 20 })
	local skipB = Ui.button({ AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -px(24), 0, px(70)), Size = UDim2.fromOffset(px(110), px(40)), BackgroundColor3 = Color3.fromRGB(60, 62, 90), TextColor3 = Color3.new(1, 1, 1), TextScaled = false, TextSize = px(16), Text = "Skip ▸▸", ZIndex = 25, Parent = stage, Radius = 20 })
	skipB.Activated:Connect(function()
		skipping = true
	end)

	-- sealed card backs fly in
	local slots = {}
	for i, r in list do
		local c = (i - 1) % cols
		local rI = math.floor((i - 1) / cols)
		local pos = Vector2.new(x0 + c * (cw + gap), y0 + rI * (ch + gap))
		local rc = RARITY[r.stars] or RARITY[1]
		-- back glow hints rarity for 3★+; 5★ backs hint purple (the flip reveals gold)
		local hint = r.stars >= 5 and RARITY[4] or r.stars >= 3 and rc or Color3.fromRGB(150, 156, 190)
		local back = new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(vp.X / 2, vp.Y + ch), Size = UDim2.fromOffset(cw, ch), BackgroundColor3 = Color3.fromRGB(42, 44, 74), ZIndex = 10, Parent = stage }, {
			new("UICorner", { CornerRadius = UDim.new(0, math.floor(cw * 0.08)) }),
			new("UIStroke", { Color = hint, Thickness = r.stars >= 4 and 3 or 2 }),
		})
		label(back, { Size = UDim2.fromScale(1, 1), Text = "🥚", TextSize = math.floor(cw * 0.36), ZIndex = 11, TextXAlignment = Enum.TextXAlignment.Center })
		slots[i] = { pos = pos, back = back, rc = rc, hint = hint }
		Sfx.play("flip", { pitch = 0.8 + i * 0.03, vol = 0.6 })
		tween(back, 0.4, { Position = UDim2.fromOffset(pos.X, pos.Y) }, Enum.EasingStyle.Back)
		if not skipping then
			task.wait(0.04)
		end
	end

	task.spawn(function()
		if not pause(0.5, my) then
			return
		end
		-- the rare backs pulse while the common ones flip
		local pulsing = true
		task.spawn(function()
			while pulsing and token == my do
				for i, r in list do
					local s = slots[i]
					if r.stars >= 4 and s.back.Parent then
						local st = s.back:FindFirstChildOfClass("UIStroke")
						if st then
							st.Thickness = 3 + math.abs(math.sin(os.clock() * 6)) * 3
						end
					end
				end
				RunService.RenderStepped:Wait()
			end
		end)
		local function flip(i: number, dramatic: boolean)
			local r, s = list[i], slots[i]
			local t = dramatic and not skipping and 0.14 or 0.08
			Sfx.play("flip", { vary = 0.1 })
			if r.stars >= 5 then
				Sfx.play("reveal_legend", { vary = 0 })
			elseif r.stars == 4 then
				Sfx.play("reveal_rare", { vary = 0 })
			elseif r.stars == 3 then
				Sfx.play("star", { pitch = 1.2, vol = 0.7 })
			end
			tween(s.back, t, { Size = UDim2.fromOffset(0, ch) }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
			task.wait(t)
			s.back:Destroy()
			if r.stars >= 5 then
				rays(stage, UDim2.fromOffset(s.pos.X, s.pos.Y), cw * 2.4, s.rc, 9, 12)
			elseif r.stars == 4 then
				rays(stage, UDim2.fromOffset(s.pos.X, s.pos.Y), cw * 1.8, s.rc, 9, 8)
			end
			local card, starRow = monsterCard(stage, r, cw, 10)
			card.Position = UDim2.fromOffset(s.pos.X, s.pos.Y)
			card.Size = UDim2.fromOffset(0, ch)
			tween(card, t, { Size = UDim2.fromOffset(cw, ch) }, Enum.EasingStyle.Back)
			popStars(starRow, r.stars, s.rc, math.floor(cw * 0.12), my, 0)
			if r.stars >= 3 then
				sparks(fxLayer, s.pos, s.rc, r.stars >= 5 and 30 or r.stars == 4 and 18 or 6, cw * (r.stars >= 4 and 1.8 or 0.8), 34)
			end
		end
		-- commons first, then the rare ones with lightning (biggest last)
		local order = {}
		for i in list do
			table.insert(order, i)
		end
		table.sort(order, function(a, b)
			local sa, sb = list[a].stars >= 4 and list[a].stars or 0, list[b].stars >= 4 and list[b].stars or 0
			if sa ~= sb then
				return sa < sb
			end
			return a < b
		end)
		for _, i in order do
			if token ~= my then
				return
			end
			local r = list[i]
			if r.stars >= 4 and not skipping then
				local s = slots[i]
				title.Text = r.stars >= 5 and "Something legendary stirs..." or "A rare one!"
				-- the build-up: the card trembles, then lightning cracks down
				local start = os.clock()
				while os.clock() - start < 0.45 and not skipping do
					s.back.Rotation = math.sin(os.clock() * 60) * 4
					RunService.RenderStepped:Wait()
				end
				s.back.Rotation = 0
				local strikes = r.stars >= 5 and 3 or 1
				for k = 1, strikes do
					lightning(s.pos + Vector2.new((math.random() - 0.5) * cw * 0.4, 0), s.rc, r.stars >= 5 and 1.25 or 0.9)
					flash(s.rc, r.stars >= 5 and 0.6 or 0.35)
					shake(px(r.stars >= 5 and 16 or 9), 0.3)
					if k < strikes and not pause(0.16, my) then
						return
					end
				end
				if not pause(0.12, my) then
					return
				end
				flip(i, true)
				if r.stars >= 5 then
					flash(Color3.new(1, 1, 1), 0.7)
				end
				if not pause(r.stars >= 5 and 0.7 or 0.4, my) then
					return
				end
			else
				flip(i, false)
				if not skipping and not pause(0.09, my) then
					return
				end
			end
		end
		pulsing = false
		if token ~= my then
			return
		end
		skipB:Destroy()
		-- summary
		local counts = {}
		for _, r in list do
			counts[r.stars] = (counts[r.stars] or 0) + 1
		end
		local parts = {}
		for s = 5, 1, -1 do
			if counts[s] then
				table.insert(parts, string.format('<font color="#%s">%d★ ×%d</font>', RARITY[s]:ToHex(), s, counts[s]))
			end
		end
		title.RichText = true
		title.Text = table.concat(parts, "   ")
		buttonBar(stage, h, UDim.new(0.43, gridH / 2 + px(24)), 20)
	end)
end

----------------------------------------------------------------------------------------------

-- Shows a summon result: one result table, or a list of them. h: { kind, one, ten, done }.
function SummonReveal.show(results, h: Handlers)
	if results.sp then
		single(results, h)
	else
		multi(results, h)
	end
end

function SummonReveal.hide()
	token += 1
	clearAll()
	gui.Enabled = false
	flashF.BackgroundTransparency = 1
end

function SummonReveal.isOpen(): boolean
	return gui.Enabled
end

-- Click / Space skips the current animation ahead.
dim.InputBegan:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
		skipping = true
	end
end)
dim.Active = true
UserInputService.InputBegan:Connect(function(input, processed)
	if gui.Enabled and not processed and input.KeyCode == Enum.KeyCode.Space then
		skipping = true
	end
end)

return SummonReveal

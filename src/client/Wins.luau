-- Small wins (2026-11-27, owner: instantly captivating for younger players): coins fly into
-- the wallet, a big banner for every brand-new monster, and a daily gift box on join.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Monsters = require(Shared.Monsters)
local Config = require(Shared.Config)
local Ui = require(script.Parent.Ui)
local Sfx = require(script.Parent.Sfx)

local C, px, new = Ui.C, Ui.px, Ui.new
local Wins = {}
local player = Players.LocalPlayer

local gui = new("ScreenGui", { Name = "WildWins", DisplayOrder = 70, ResetOnSpawn = false, IgnoreGuiInset = true, Parent = player:WaitForChild("PlayerGui") })

----------------------------------------------------------------------------------------------
-- coins fly to the wallet

Wins.walletPos = function(): Vector2
	return Vector2.new(px(110), px(32))
end

function Wins.coins(worldPos: Vector3, amount: number)
	local cam = workspace.CurrentCamera
	local sp, on = cam:WorldToViewportPoint(worldPos)
	if not on then
		return
	end
	local from = Vector2.new(sp.X, sp.Y)
	local to = Wins.walletPos()
	local n = math.clamp(math.floor(amount / 15) + 2, 2, 7)
	for i = 1, n do
		task.delay((i - 1) * 0.06, function()
			local c = new("TextLabel", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(from.X + math.random(-24, 24), from.Y + math.random(-16, 16)), Size = UDim2.fromOffset(px(26), px(26)), BackgroundTransparency = 1, Text = "💰", TextScaled = true, ZIndex = 5, Parent = gui })
			local mid = UDim2.fromOffset((from.X + to.X) / 2 + math.random(-60, 60), math.min(from.Y, to.Y) - math.random(20, 80))
			local t1 = TweenService:Create(c, TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Position = mid })
			t1:Play()
			t1.Completed:Wait()
			local t2 = TweenService:Create(c, TweenInfo.new(0.32, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Position = UDim2.fromOffset(to.X, to.Y), Size = UDim2.fromOffset(px(14), px(14)) })
			t2:Play()
			t2.Completed:Wait()
			c:Destroy()
			if i == n and Wins.onCoinsArrive then
				Wins.onCoinsArrive()
			end
		end)
	end
end

----------------------------------------------------------------------------------------------
-- NEW MONSTER banner (queued, one at a time)

local banner = new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.28), Size = UDim2.fromOffset(px(520), px(92)), BackgroundColor3 = C.Card, Visible = false, ZIndex = 10, Parent = gui }, {
	new("UICorner", { CornerRadius = UDim.new(0, px(24)) }),
})
local bStroke = Ui.stroke(C.Sun, 4)
bStroke.Parent = banner
local bTop = Ui.text({ Position = UDim2.fromOffset(0, px(10)), Size = UDim2.new(1, 0, 0, px(34)), BackgroundTransparency = 1, TextScaled = false, TextSize = px(30), Text = "NEW MONSTER!", TextColor3 = C.Coral, ZIndex = 11, Parent = banner }, "Title")
local bSub = Ui.text({ Position = UDim2.fromOffset(0, px(48)), Size = UDim2.new(1, 0, 0, px(26)), BackgroundTransparency = 1, TextScaled = false, TextSize = px(18), Text = "", ZIndex = 11, Parent = banner }, "Title")
local queue: { { any } } = {}
local showing = false

local function nextBanner()
	if showing or #queue == 0 then
		return
	end
	showing = true
	local b = table.remove(queue, 1)
	bTop.Text, bSub.Text, bStroke.Color = b[1], b[2], b[3]
	banner.Visible = true
	local sc = new("UIScale", { Scale = 0.3, Parent = banner })
	TweenService:Create(sc, TweenInfo.new(0.45, Enum.EasingStyle.Back), { Scale = 1 }):Play()
	Sfx.play("star")
	task.delay(2.2, function()
		TweenService:Create(sc, TweenInfo.new(0.2), { Scale = 0 }):Play()
		task.wait(0.22)
		sc:Destroy()
		banner.Visible = false
		showing = false
		nextBanner()
	end)
end

function Wins.banner(top: string, sub: string, color: Color3?)
	table.insert(queue, { top, sub, color or C.Sun })
	nextBanner()
end

-- Summon results: a banner for each species+element seen for the first time.
function Wins.summoned(res)
	-- wait for the egg to burst (single) so the banner doesn't spoil the hatch
	task.wait(res.sp and 3.4 or 1)
	for _, r in (res.sp and { res } or res) do
		if r.new then
			local sp = Monsters.Species[r.sp]
			local info = Config.ElementInfo[r.el]
			Wins.banner("NEW MONSTER!", string.format("%s %s %s  %s  joined your Index", info and info.Icon or "", r.el, sp and sp.Name or r.sp, string.rep("★", sp and sp.Stars or 1)), info and info.Color or C.Sun)
		end
	end
end

----------------------------------------------------------------------------------------------
-- daily gift on join

function Wins.dailyGift()
	if not player:GetAttribute("StreakReady") then
		return
	end
	-- never on top of a hatch or the dream
	local SummonReveal = require(script.Parent.SummonReveal)
	while SummonReveal.isOpen() or player:GetAttribute("InIntro") do
		task.wait(1)
	end
	local card = Ui.card({ AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.45), Size = UDim2.fromOffset(px(360), px(250)), ZIndex = 20, Parent = gui }, 26)
	Ui.stroke(C.Sun, 4).Parent = card
	local box = Ui.text({ AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, px(16)), Size = UDim2.fromOffset(px(110), px(110)), BackgroundTransparency = 1, TextScaled = true, Text = "🎁", ZIndex = 21, Parent = card }, "Title")
	Ui.text({ Position = UDim2.fromOffset(0, px(128)), Size = UDim2.new(1, 0, 0, px(30)), BackgroundTransparency = 1, TextScaled = false, TextSize = px(24), Text = "Your daily gift!", ZIndex = 21, Parent = card }, "Title")
	local open = Ui.button({ AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -px(18)), Size = UDim2.fromOffset(px(200), px(50)), BackgroundColor3 = C.Mint, Text = "Open it!", TextScaled = false, TextSize = px(20), ZIndex = 21, Parent = card, Radius = 25 })
	local sc = new("UIScale", { Scale = 0.4, Parent = card })
	TweenService:Create(sc, TweenInfo.new(0.5, Enum.EasingStyle.Back), { Scale = 1 }):Play()
	task.spawn(function()
		while box.Parent do
			box.Rotation = math.sin(os.clock() * 8) * 8
			task.wait()
		end
	end)
	open.Activated:Connect(function()
		local ok = Ui.call("ClaimStreak")
		Sfx.play(ok and "reveal_rare" or "close")
		TweenService:Create(sc, TweenInfo.new(0.25), { Scale = 0 }):Play()
		task.delay(0.3, function()
			card:Destroy()
		end)
	end)
end

function Wins.start()
	-- the gift waits until the player is in the world (not during the intro)
	task.delay(6, function()
		if not player:GetAttribute("InIntro") then
			Wins.dailyGift()
		end
	end)
end

return Wins

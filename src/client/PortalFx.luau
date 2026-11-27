-- Portal travel on the client: a quick fade to the place colour, then back in at the far side.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Sfx = require(script.Parent.Sfx)

local PortalFx = {}

local gui = Instance.new("ScreenGui")
gui.Name = "WildPortal"
gui.IgnoreGuiInset = true
gui.DisplayOrder = 90
gui.ResetOnSpawn = false
gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
local veil = Instance.new("Frame")
veil.Size = UDim2.fromScale(1, 1)
veil.BackgroundColor3 = Color3.fromRGB(250, 248, 255)
veil.BackgroundTransparency = 1
veil.BorderSizePixel = 0
veil.Parent = gui
local title = Instance.new("TextLabel")
title.AnchorPoint = Vector2.new(0.5, 0.5)
title.Position = UDim2.fromScale(0.5, 0.5)
title.Size = UDim2.fromOffset(600, 60)
title.BackgroundTransparency = 1
title.Font = Enum.Font.GothamBold
title.TextSize = 34
title.TextColor3 = Color3.fromRGB(70, 60, 110)
title.TextTransparency = 1
title.Parent = veil

local token = 0

function PortalFx.start()
	local remote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Portal") :: RemoteEvent
	remote.OnClientEvent:Connect(function(msg)
		if typeof(msg) ~= "table" then
			return
		end
		token += 1
		local my = token
		if msg.kind == "go" then
			title.Text = msg.name or ""
			TweenService:Create(veil, TweenInfo.new(0.3), { BackgroundTransparency = 0 }):Play()
			TweenService:Create(title, TweenInfo.new(0.3), { TextTransparency = 0 }):Play()
			Sfx.play("region")
			-- never get stuck behind the veil
			task.delay(2, function()
				if token == my then
					TweenService:Create(veil, TweenInfo.new(0.5), { BackgroundTransparency = 1 }):Play()
					TweenService:Create(title, TweenInfo.new(0.5), { TextTransparency = 1 }):Play()
				end
			end)
		elseif msg.kind == "arrive" then
			task.delay(0.25, function()
				if token == my then
					TweenService:Create(veil, TweenInfo.new(0.55), { BackgroundTransparency = 1 }):Play()
					TweenService:Create(title, TweenInfo.new(0.55), { TextTransparency = 1 }):Play()
				end
			end)
		end
	end)
end

return PortalFx

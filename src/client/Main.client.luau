-- Runs on each player's device when they join.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local Remotes = ReplicatedStorage:WaitForChild("Remotes")

local CreatureView = require(script.Parent.CreatureView)
local WorldFx = require(script.Parent.WorldFx)
local Hud = require(script.Parent.Hud)
local Shelves = require(script.Parent.Shelves)
local Nudge = require(script.Parent.Nudge)

WorldFx.start()
CreatureView.start()
Hud.start()
task.spawn(Shelves.start)
Nudge.start()

Remotes.Fx.OnClientEvent:Connect(function(kind, pos, a, b, c)
	WorldFx.onFx(kind, pos, a, b, c)
	if kind == "RareSpawn" then
		local wing = Config.Wings[b or "FoodCourt"]
		local p = Hud.getProfile()
		if wing and (not p or p.wings[wing.Id]) then
			Hud.toast("A rare sleeper is napping on " .. wing.RareStageName .. "!", "good")
		end
	end
end)

-- Debug bridge for Studio MCP playtests (Studio only).
if game:GetService("RunService"):IsStudio() then
	local Players = game:GetService("Players")
	local bf = Instance.new("BindableFunction")
	bf.Name = "BrainrotClientDebug"
	bf.OnInvoke = function(cmd, a)
		local gui = Players.LocalPlayer.PlayerGui:FindFirstChild("BrainrotHud")
		if cmd == "hud" then
			local m = gui.WakeMeter
			local out = {}
			table.insert(out, "meter=" .. tostring(m.Visible))
			for _, d in m:GetDescendants() do
				if d:IsA("TextLabel") and d.Text ~= "" then
					table.insert(out, "meterText=" .. d.Text)
				end
			end
			table.insert(out, "hint=" .. (gui.Hint.Visible and gui.Hint.Text.Text or ""))
			table.insert(out, "rare=" .. gui.Top.Rare.Card.Value.Text)
			table.insert(out, "coins=" .. gui.Top.Coins.Card.Value.Text)
			table.insert(out, "shop=" .. tostring(gui.Shop.Visible) .. " index=" .. tostring(gui.Collection.Visible))
			table.insert(out, "reveal=" .. tostring(gui.Reveal.Visible))
			for _, d in gui.Reveal:GetDescendants() do
				if d:IsA("TextLabel") and gui.Reveal.Visible then
					table.insert(out, "revealText=" .. d.Text)
				end
			end
			return table.concat(out, " | ")
		elseif cmd == "meshes" then
			local n, list = require(ReplicatedStorage.Shared.MeshLoader).stats()
			return n .. " | " .. list
		elseif cmd == "open" then
			Hud.openPanel(a)
			return "ok"
		elseif cmd == "sprint" then
			Hud.setSprint(a == true)
			return "ok"
		elseif cmd == "views" then
			local out = {}
			for part, v in CreatureView.views do
				table.insert(out, part.Name .. ":" .. tostring(part:GetAttribute("State")) .. ":" .. tostring(v.c.body.ClassName))
			end
			return table.concat(out, ", ")
		end
		return "unknown"
	end
	bf.Parent = game:GetService("ReplicatedStorage")
end

print(`[client] {Config.GameName} loaded`)

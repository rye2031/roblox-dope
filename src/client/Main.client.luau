-- Runs on each player's device when they join.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local Remotes = ReplicatedStorage:WaitForChild("Remotes")

local Ui = require(script.Parent.Ui)
local UnitView = require(script.Parent.UnitView)
local Controls = require(script.Parent.Controls)
local Hud = require(script.Parent.Hud)
local Panels = require(script.Parent.Panels)
local ServerFeed = require(script.Parent.ServerFeed)
local Sfx = require(script.Parent.Sfx)
local Journey = require(script.Parent.Journey)
local LoopsUi = require(script.Parent.LoopsUi)
local ArenaUi = require(script.Parent.ArenaUi)
local PropView = require(script.Parent.PropView)
local AmbientFx = require(script.Parent.AmbientFx)
local Ticker = require(script.Parent.Ticker)
local DayNight = require(script.Parent.DayNight)

Sfx.start(Ui)
UnitView.start()
Controls.start()
Hud.start()
ServerFeed.start()
Journey.start()
LoopsUi.start()
ArenaUi.start()
PropView.start()
AmbientFx.start()
Ticker.start(Journey)
DayNight.start()

Remotes:WaitForChild("Combat").OnClientEvent:Connect(function(events)
	UnitView.onEvents(events)
	Controls.onEvents(events)
end)
Remotes:WaitForChild("Profile").OnClientEvent:Connect(function(p)
	Ui.setProfile(p)
end)
task.spawn(function()
	local ok, p = pcall(function()
		return (Remotes:WaitForChild("GetProfile") :: RemoteFunction):InvokeServer()
	end)
	if ok and p and not Ui.profile then
		Ui.setProfile(p)
	end
end)

-- Debug bridge for Studio MCP playtests (Studio only).
if game:GetService("RunService"):IsStudio() then
	local bf = Instance.new("BindableFunction")
	bf.Name = "WildClientDebug"
	bf.OnInvoke = function(cmd, a, b)
		if cmd == "open" then
			Ui.open(a)
			return "ok"
		elseif cmd == "panel" then
			-- visible text of an open panel
			local p = Ui.panels[a]
			local out = {}
			for _, d in (p and p:GetDescendants() or {}) do
				if (d:IsA("TextLabel") or d:IsA("TextButton")) and d.Text ~= "" and d.Visible then
					table.insert(out, d.Text)
				end
			end
			return table.concat(out, " | ")
		elseif cmd == "views" then
			local out = {}
			for part, v in UnitView.views do
				table.insert(out, part.Name .. ":" .. tostring(part:GetAttribute("Species")) .. ":" .. tostring(part:GetAttribute("State")) .. ":" .. v.body.ClassName)
			end
			return table.concat(out, ", ")
		elseif cmd == "meshes" then
			local n, list = require(ReplicatedStorage.Shared.MeshLoader).stats()
			return n .. " | " .. list
		elseif cmd == "attack" then
			Controls.attack()
			return "ok"
		elseif cmd == "team" then
			Controls.team(a)
			return "ok"
		elseif cmd == "skill" then
			Controls.skill()
			return "ok"
		elseif cmd == "dodge" then
			Controls.dodge()
			return "ok"
		elseif cmd == "reveal" then
			Panels.reveal(a)
			return "ok"
		elseif cmd == "props" then
			return PropView.stats()
		elseif cmd == "arena" then
			return ArenaUi.debugState()
		elseif cmd == "arenafight" then
			return tostring(ArenaUi.debugFight(a))
		elseif cmd == "arenaact" then
			return tostring(ArenaUi.debugAct(a, b))
		elseif cmd == "feedhover" then
			return tostring(ServerFeed.debugHover())
		elseif cmd == "feed5" then
			ServerFeed.add(a)
			return "ok"
		elseif cmd == "hidereveal" then
			require(script.Parent.SummonReveal).hide()
			return "ok"
		elseif cmd == "detail" then
			Panels.showMonster(a)
			return "ok"
		elseif cmd == "feed" then
			Panels.startFeed(a, b)
			return "ok"
		elseif cmd == "swing" then
			local TamerAnim = require(script.Parent.TamerAnim)
			if a then
				TamerAnim.play(Players.LocalPlayer, a, b == "skill", true)
			end
			return TamerAnim.debugState(Players.LocalPlayer)
		elseif cmd == "target" then
			return Controls.target and Controls.target.Name or "none"
		end
		local _ = b
		return "unknown"
	end
	bf.Parent = ReplicatedStorage
end

local _ = Players
print(`[client] {Config.GameName} loaded`)

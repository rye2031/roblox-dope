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
local AutoHunt = require(script.Parent.AutoHunt)
local DungeonUi = require(script.Parent.DungeonUi)
local PortalFx = require(script.Parent.PortalFx)
local Pace = require(script.Parent.Pace)
local Tips = require(script.Parent.Tips)
local Landmarks = require(script.Parent.Landmarks)
local _PassUi = require(script.Parent.PassUi)
local Wins = require(script.Parent.Wins)
local Intro = require(script.Parent.Intro)

Sfx.start(Ui)
UnitView.start()
Controls.start()
Hud.start()
ServerFeed.start()
Journey.start()
LoopsUi.start()
ArenaUi.start()
DungeonUi.start()
PortalFx.start()
Pace.start()
Tips.start()
Landmarks.start()
Wins.start()
Intro.start()
PropView.start()
AmbientFx.start()
Ticker.start(Journey)
DayNight.start()
AutoHunt.start()

Remotes:WaitForChild("Combat").OnClientEvent:Connect(function(events)
	UnitView.onEvents(events)
	Controls.onEvents(events)
	AutoHunt.onEvents(events)
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
		elseif cmd == "auto" then
			if a ~= nil then
				AutoHunt.set(a == true)
			end
			return tostring(AutoHunt.isOn())
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
		elseif cmd == "tip" then
			if a == "ok" then
				Tips.dismiss()
			elseif a then
				Tips.show(a, true)
			end
			return Tips.state()
		elseif cmd == "intro" then
			if a == "pick" then
				Intro.pick(b)
			elseif a == "next" then
				Intro.next()
			end
			return Intro.state()
		elseif cmd == "wins" then
			if a == "banner" then
				Wins.summoned({ sp = "Wyrmlet", el = "Fire", new = true })
			elseif a == "gift" then
				Wins.dailyGift()
			end
			return "ok"
		elseif cmd == "gallery" then
			return require(script.Parent.DebugGallery).show(tonumber(a) or 1)
		elseif cmd == "dungeonui" then
			if a == "party" then
				DungeonUi.debugParty()
				Ui.open("Dungeons")
			elseif a == "open" then
				Ui.open("Dungeons")
			end
			return DungeonUi.debugState()
		elseif cmd == "runes" then
			local RunesUi = require(script.Parent.RunesUi)
			if a == "pick" then
				RunesUi.pick(b)
			else
				Ui.open("Runes")
				RunesUi.debugSelect(a)
			end
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

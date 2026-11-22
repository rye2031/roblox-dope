-- Runs on the Roblox server when the game starts.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Shared.Config)
local Creatures = require(ReplicatedStorage.Shared.Creatures)
local Map = require(script.Parent.Map)
local PlayerData = require(script.Parent.PlayerData)
local Sleepers = require(script.Parent.Sleepers)

local T = Config.Tuning

-- Remove the template baseplate/spawn if the place still has them.
for _, name in { "Baseplate", "SpawnLocation" } do
	local old = workspace:FindFirstChild(name)
	if old then
		old:Destroy()
	end
end

local remoteFolder = Instance.new("Folder")
remoteFolder.Name = "Remotes"
local remotes = {}
for _, n in { "Sprint", "Profile", "Reveal", "Toast", "Fx" } do
	local r = Instance.new("RemoteEvent")
	r.Name = n
	r.Parent = remoteFolder
	remotes[n] = r
end
for _, n in { "Buy", "Equip", "GetProfile" } do
	local r = Instance.new("RemoteFunction")
	r.Name = n
	r.Parent = remoteFolder
	remotes[n] = r
end
remoteFolder.Parent = ReplicatedStorage

Map.setupLighting()
local mapFolder = Map.build()
PlayerData.init(remotes.Profile)
Sleepers.init(remotes, mapFolder)

remotes.Sprint.OnServerEvent:Connect(function(player, on)
	player:SetAttribute("Sprinting", on == true)
	Sleepers.applySpeed(player)
end)

remotes.Buy.OnServerInvoke = function(player, item)
	return PlayerData.buy(player, item)
end

remotes.Equip.OnServerInvoke = function(player, species)
	return PlayerData.equip(player, species)
end

remotes.GetProfile.OnServerInvoke = function(player)
	return PlayerData.get(player)
end

-- Vent doors: a Crab Rangoon (or King Rangoon) buddy pries both open for a few seconds.
local ventDoors = {}
for _, d in mapFolder:GetDescendants() do
	if d:IsA("BasePart") and d:GetAttribute("VentDoor") then
		table.insert(ventDoors, d)
	end
end
local ventOpenUntil = 0
local ventZone
for _, z in mapFolder.Zones:GetChildren() do
	if z:GetAttribute("Kind") == "Vent" then
		ventZone = z
	end
end

local function anyoneInVent(): boolean
	if not ventZone then
		return false
	end
	for _, plr in Players:GetPlayers() do
		local hrp = plr.Character and plr.Character:FindFirstChild("HumanoidRootPart")
		if hrp then
			local rel = ventZone.CFrame:PointToObjectSpace(hrp.Position)
			local h = ventZone.Size / 2 + Vector3.new(1, 0, 2)
			if math.abs(rel.X) <= h.X and math.abs(rel.Y) <= h.Y and math.abs(rel.Z) <= h.Z then
				return true
			end
		end
	end
	return false
end

local function setVent(open: boolean)
	workspace:SetAttribute("VentOpen", open)
	for _, d in ventDoors do
		local closed: CFrame = d:GetAttribute("ClosedCFrame")
		local goal = open and closed - Vector3.new(0, d.Size.Y + 0.2, 0) or closed -- sinks into the floor
		d.CanCollide = not open
		TweenService:Create(d, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { CFrame = goal }):Play()
		local prompt = d:FindFirstChild("VentPrompt")
		if prompt then
			prompt.Enabled = not open
		end
	end
end

for _, d in ventDoors do
	d.VentPrompt.Triggered:Connect(function(player)
		local buddy = player:GetAttribute("Buddy")
		local sp = buddy and Creatures.Species[buddy]
		if not sp or sp.Ability ~= "Vent" then
			remotes.Toast:FireClient(player, "🦀 Only a Crab Rangoon buddy can pry this open. Rescue one, then equip it in 📖", "warn")
			return
		end
		local wasOpen = ventOpenUntil > os.clock()
		ventOpenUntil = os.clock() + T.VentOpenTime
		if not wasOpen then
			setVent(true)
			remotes.Fx:FireAllClients("VentOpen", d.Position, player.UserId)
			task.spawn(function()
				while ventOpenUntil > os.clock() or anyoneInVent() do
					task.wait(0.25)
				end
				setVent(false)
			end)
		end
	end)
end
setVent(false)

local function onPlayer(player: Player)
	PlayerData.create(player)
	player.CharacterAdded:Connect(function(char)
		Sleepers.onCharacter(player, char)
	end)
	if player.Character then
		Sleepers.onCharacter(player, player.Character)
	end
	task.defer(PlayerData.push, player)
end

Players.PlayerAdded:Connect(onPlayer)
for _, p in Players:GetPlayers() do
	onPlayer(p)
end
Players.PlayerRemoving:Connect(function(player)
	PlayerData.remove(player)
end)

-- Debug bridge for Studio MCP playtests (execute_luau runs in a separate Lua state, so it
-- talks to the game through this BindableFunction). Studio only.
if game:GetService("RunService"):IsStudio() then
	local HttpService = game:GetService("HttpService")
	local bf = Instance.new("BindableFunction")
	bf.Name = "BrainrotDebug"
	local function plr(name)
		return Players:FindFirstChild(name) or Players:GetPlayers()[1]
	end
	local function vec(v)
		return { math.floor(v.X * 10) / 10, math.floor(v.Y * 10) / 10, math.floor(v.Z * 10) / 10 }
	end
	bf.OnInvoke = function(cmd, a, b, c)
		if cmd == "state" then
			local out = { sleepers = {}, players = {}, rareAt = workspace:GetAttribute("RareAt") - workspace:GetServerTimeNow(), rareActive = workspace:GetAttribute("RareActive"), ventOpen = workspace:GetAttribute("VentOpen") }
			for id, s in Sleepers.debug.list() do
				out.sleepers[tostring(id)] = { st = s.state, rar = s.rarity, fam = s.family, sp = s.species, wake = math.floor(s.wake), carrier = s.carrier, ex = s.exclusive, vent = s.passedVent, pos = vec(s.pos), speed = math.floor(s.speed or 0), surf = s.surface }
			end
			for _, p in Players:GetPlayers() do
				local hrp = p.Character and p.Character:FindFirstChild("HumanoidRootPart")
				local hum = p.Character and p.Character:FindFirstChildOfClass("Humanoid")
				local pd = PlayerData.get(p)
				out.players[p.Name] = { pos = hrp and vec(hrp.Position), speed = hum and hum.WalkSpeed, carrying = p:GetAttribute("Carrying"), sprint = p:GetAttribute("Sprinting"), coins = pd and pd.coins, rescues = pd and pd.rescues, vent = pd and pd.ventRescues, buddy = pd and pd.buddy, shoes = pd and pd.upgrades.PaddedShoes, collection = pd and pd.collection }
			end
			return HttpService:JSONEncode(out)
		elseif cmd == "grab" then
			return tostring(Sleepers.tryGrab(plr(a), b))
		elseif cmd == "wake" then
			if b >= 100 then
				Sleepers.debug.forceWake(a)
			else
				Sleepers.debug.setWake(a, b)
			end
			return "ok"
		elseif cmd == "forceRare" then
			Sleepers.debug.forceRare()
			return "ok"
		elseif cmd == "tp" then
			local p = plr(a)
			p.Character:PivotTo(CFrame.new(b) * (c or CFrame.identity))
			return "ok"
		elseif cmd == "coins" then
			local pd = PlayerData.get(plr(a))
			pd.coins += b
			PlayerData.push(plr(a))
			return tostring(pd.coins)
		elseif cmd == "give" then
			local pd = PlayerData.get(plr(a))
			PlayerData.record(pd, b, "Normal")
			PlayerData.push(plr(a))
			return "ok"
		elseif cmd == "equip" then
			return tostring(PlayerData.equip(plr(a), b))
		elseif cmd == "buy" then
			return tostring(PlayerData.buy(plr(a), b))
		elseif cmd == "exclusive" then
			-- pretend another player (fake user id b) owns the recovery window for c seconds
			local s = Sleepers.debug.get(a)
			s.exclusiveUser = b
			s.exclusiveUntil = workspace:GetServerTimeNow() + c
			s.part:SetAttribute("ExclusiveId", b)
			s.part:SetAttribute("ExclusiveUntil", s.exclusiveUntil)
			return "ok"
		elseif cmd == "home" then
			Sleepers.debug.home(a)
			return "ok"
		elseif cmd == "drop" then
			Sleepers.drop(plr(a))
			return "ok"
		end
		return "unknown"
	end
	bf.Parent = game:GetService("ServerStorage")
end

print(`[server] {Config.GameName} started`)

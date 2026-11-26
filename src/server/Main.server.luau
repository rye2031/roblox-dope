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
for _, n in { "Buy", "Equip", "GetProfile", "Display", "AutoFill", "Collect" } do
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

-- Hideout shelves + tip jar
remotes.Display.OnServerInvoke = function(player, slot, species, form)
	return PlayerData.setDisplay(player, slot, species, form)
end
remotes.AutoFill.OnServerInvoke = function(player)
	return PlayerData.autoFill(player)
end
remotes.Collect.OnServerInvoke = function(player)
	local ok, msg, n = PlayerData.collect(player)
	if ok then
		remotes.Fx:FireAllClients("Collect", Map.Points.Jar, n, player.UserId)
	end
	return ok, msg
end
task.spawn(function()
	local last = os.clock()
	while true do
		task.wait(2)
		local now = os.clock()
		PlayerData.tick(now - last)
		last = now
	end
end)

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

-- Wing gates: buy the wing at the gate; unlocked characters pass through (collision groups).
local function setPass(player: Player)
	local char = player.Character
	if not char then
		return
	end
	local wing = player:GetAttribute("PassWing")
	local group = wing and ("Pass_" .. wing) or "Default"
	for _, d in char:GetDescendants() do
		if d:IsA("BasePart") then
			d.CollisionGroup = group
		end
	end
end

PlayerData.onPush = function(player: Player)
	Sleepers.applySpeed(player)
	setPass(player)
end

for wingId, gate in Map.Gates do
	local prompt = gate:FindFirstChild("GatePrompt") :: ProximityPrompt
	prompt.Triggered:Connect(function(player)
		local pd = PlayerData.get(player)
		if pd and pd.wings[wingId] then
			remotes.Toast:FireClient(player, `{Config.Wings[wingId].Name} is open for you, walk on through`, "good")
			return
		end
		local ok, msg = PlayerData.buy(player, wingId)
		remotes.Toast:FireClient(player, msg, ok and "good" or "warn")
		if ok then
			remotes.Fx:FireAllClients("Unlock", gate.Position, wingId, player.UserId)
		end
	end)
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
	player.CharacterAdded:Connect(function(char)
		Sleepers.onCharacter(player, char)
		setPass(player)
		char.DescendantAdded:Connect(function(d)
			if d:IsA("BasePart") then
				local wing = player:GetAttribute("PassWing")
				d.CollisionGroup = wing and ("Pass_" .. wing) or "Default"
			end
		end)
	end)
	if player.Character then
		Sleepers.onCharacter(player, player.Character)
	end
	-- loads the saved profile (yields on the DataStore), then sends it to the client
	task.spawn(function()
		if PlayerData.join(player) then
			PlayerData.push(player)
			local mode = player:GetAttribute("SaveMode")
			local earned = player:GetAttribute("OfflineEarned")
			if earned then
				local mins = player:GetAttribute("OfflineMinutes") or 0
				local away = mins >= 60 and string.format("%dh %02dm", mins // 60, mins % 60) or (mins .. " min")
				remotes.Toast:FireClient(player, `While you were away ({away}) your shelves earned {earned} coins. Grab them from the tip jar!`, "good")
				player:SetAttribute("OfflineEarned", nil)
			end
			if mode == "Session" then
				remotes.Toast:FireClient(player, "⚠️ Saving is off here: progress resets when you leave", "warn")
			elseif mode == "Failed" then
				remotes.Toast:FireClient(player, "⚠️ Couldn't load your save. This session won't be saved, so rejoin later", "alert")
			end
		end
	end)
end

Players.PlayerAdded:Connect(onPlayer)
for _, p in Players:GetPlayers() do
	onPlayer(p)
end
Players.PlayerRemoving:Connect(function(player)
	PlayerData.leave(player)
end)

-- Debug bridge for Studio MCP playtests (execute_luau runs in a separate Lua state, so it
-- talks to the game through this BindableFunction). Studio only.
if game:GetService("RunService"):IsStudio() then
	local HttpService = game:GetService("HttpService")
	local bf = Instance.new("BindableFunction")
	bf.Name = "BrainrotDebug"
	local function plr(name)
		return (name and Players:FindFirstChild(name)) or Players:GetPlayers()[1]
	end
	local function vec(v)
		return { math.floor(v.X * 10) / 10, math.floor(v.Y * 10) / 10, math.floor(v.Z * 10) / 10 }
	end
	bf.OnInvoke = function(cmd, a, b, c, ...)
		if cmd == "state" then
			local out = { sleepers = {}, players = {}, rareAt = workspace:GetAttribute("RareAt_FoodCourt") - workspace:GetServerTimeNow(), rareActive = workspace:GetAttribute("RareActive_FoodCourt"), arcadeRareAt = workspace:GetAttribute("RareAt_Arcade") - workspace:GetServerTimeNow(), arcadeRareActive = workspace:GetAttribute("RareActive_Arcade"), ventOpen = workspace:GetAttribute("VentOpen") }
			for id, s in Sleepers.debug.list() do
				out.sleepers[tostring(id)] = { st = s.state, rar = s.rarity, wing = s.wing, fam = s.family, sp = s.species, wake = math.floor(s.wake), carrier = s.carrier, ex = s.exclusive, vent = s.passedVent, pit = s.routes.BallPit == true, pos = vec(s.pos), speed = math.floor(s.speed or 0), surf = s.surface }
			end
			for _, p in Players:GetPlayers() do
				local hrp = p.Character and p.Character:FindFirstChild("HumanoidRootPart")
				local hum = p.Character and p.Character:FindFirstChildOfClass("Humanoid")
				local pd = PlayerData.get(p)
				out.players[p.Name] = { pos = hrp and vec(hrp.Position), speed = hum and hum.WalkSpeed, carrying = p:GetAttribute("Carrying"), sprint = p:GetAttribute("Sprinting"), coins = pd and pd.coins, rescues = pd and pd.rescues, slots = pd and pd.slots, display = pd and pd.display, jar = pd and math.floor(pd.jar * 10) / 10, rate = pd and PlayerData.incomeRate(pd), evo = pd and pd.evo, vent = pd and (pd.evo.KingRangoon or 0), buddy = pd and pd.buddy, shoes = pd and pd.upgrades.PaddedShoes, tracks = pd and pd.tracks, wings = pd and pd.wings, group = hrp and hrp.CollisionGroup, collection = pd and pd.collection }
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
			Sleepers.debug.forceRare(a)
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
		elseif cmd == "save" then
			local Persistence = require(script.Parent.Persistence)
			local p = plr(a)
			local ok = Persistence.save(p.UserId, PlayerData.serialize(PlayerData.get(p)), false)
			return tostring(ok)
		elseif cmd == "peek" then
			local Persistence = require(script.Parent.Persistence)
			return HttpService:JSONEncode(Persistence.peek(plr(a).UserId) or {})
		elseif cmd == "persist" then
			local Persistence = require(script.Parent.Persistence)
			return HttpService:JSONEncode({ available = Persistence.available, reason = Persistence.reason, job = Persistence.jobId(), mode = plr(a):GetAttribute("SaveMode") })
		elseif cmd == "plant" then
			-- write a raw record (JSON) for player a, e.g. a foreign lock or a corrupt profile
			local Persistence = require(script.Parent.Persistence)
			local rec = HttpService:JSONDecode(b)
			if rec.lock and rec.lock.t == "now" then
				rec.lock.t = os.time()
			end
			Persistence.poke(plr(a).UserId, rec)
			return "ok"
		elseif cmd == "rejoin" then
			-- simulate leaving and joining another server: final save + release, then load again
			local p = plr(a)
			PlayerData.leave(p)
			if b then
				-- plant a record while "between servers" (after our final save, before the next load)
				local Persistence = require(script.Parent.Persistence)
				local rec = HttpService:JSONDecode(b)
				if rec.lock and rec.lock.t == "now" then
					rec.lock.t = os.time()
				end
				Persistence.poke(p.UserId, rec)
			end
			local t0 = os.clock()
			local ok = PlayerData.join(p) ~= nil
			PlayerData.push(p)
			return HttpService:JSONEncode({ ok = ok, seconds = math.floor((os.clock() - t0) * 10) / 10, mode = p:GetAttribute("SaveMode") })
		elseif cmd == "reset" then
			-- wipe player a's progress back to a fresh profile (session only until the next save)
			local p = plr(a)
			local pd = PlayerData.get(p)
			local fresh = PlayerData.sanitize(nil)
			for k in pd do
				pd[k] = nil
			end
			for k, v in fresh do
				pd[k] = v
			end
			PlayerData.push(p)
			return "ok"
		elseif cmd == "display" then
			return tostring(PlayerData.setDisplay(plr(a), b, c, (...)))
		elseif cmd == "autofill" then
			return tostring(PlayerData.autoFill(plr(a)))
		elseif cmd == "collect" then
			local ok, msg = PlayerData.collect(plr(a))
			return tostring(ok) .. " " .. msg
		elseif cmd == "jar" then
			-- set the jar (b) and/or pretend the last save was c minutes ago
			local pd = PlayerData.get(plr(a))
			if b then
				pd.jar = b
			end
			if c then
				pd.lastSeen = os.time() - c * 60
			end
			PlayerData.tick(0)
			return string.format("jar=%.1f rate=%.2f cap=%.0f slots=%d", pd.jar, PlayerData.incomeRate(pd), PlayerData.jarCap(pd), pd.slots)
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

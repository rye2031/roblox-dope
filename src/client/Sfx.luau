-- Sound effects. Every sound is a slice of one uploaded bank (SfxBank: start/length per name),
-- played with Sound.PlaybackRegion. UI and reward sounds are 2D; combat sounds play from their
-- spot in the world. Silent until SfxBank.AssetId is set.
--
--   Sfx.play(name, { at = Vector3?, pitch = number?, vary = number?, vol = number? })
--   Sfx.coin()  -- rising pitch for coins picked up in quick succession
local ContentProvider = game:GetService("ContentProvider")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Bank = require(Shared.SfxBank)

local Sfx = {}
local player = Players.LocalPlayer
local ENABLED = type(Bank.AssetId) == "string" and Bank.AssetId ~= ""

-- Relative loudness (the bank is normalised; this is the mix).
local VOL: { [string]: number } = {
	tap = 0.3, open = 0.35, close = 0.25, error = 0.4, toast = 0.3, select = 0.3,
	coin = 0.45, coins = 0.55, essence = 0.4, scroll_get = 0.55, level_up = 0.55, quest_done = 0.6, claim = 0.55, buy = 0.5,
	swing = 0.4, swing_heavy = 0.45, hit = 0.5, hit_heavy = 0.6, crit = 0.55, slam = 0.7, zap = 0.4, bow = 0.45,
	arrow_hit = 0.4, dodge = 0.4, skill_ready = 0.35, hurt = 0.5, poof = 0.45, charge = 0.45, blast = 0.65, warn = 0.45,
	faint = 0.45, revive = 0.45, boss = 0.65, region = 0.45,
	scroll_land = 0.5, rattle = 0.45, unroll = 0.5, reveal = 0.55, reveal_rare = 0.65, reveal_legend = 0.75, star = 0.45,
	flip = 0.4, thunder = 0.7, announce = 0.5,
}
local MAX_VOICES = 5
local MIN_GAP = 0.025 -- seconds between two starts of the same sound

local group = Instance.new("SoundGroup")
group.Name = "WildSfx"
group.Volume = 1
group.Parent = SoundService
local folder2d = Instance.new("Folder")
folder2d.Name = "WildSfx2D"
folder2d.Parent = SoundService

type Voice = { sound: Sound, started: number }
local voices: { [string]: { Voice } } = {}
local lastStart: { [string]: number } = {}
local muted = false

local function newSound(name: string): Sound?
	local slice = Bank.Sounds[name]
	if not slice then
		return nil
	end
	local s = Instance.new("Sound")
	s.Name = name
	s.SoundId = Bank.AssetId
	s.PlaybackRegionsEnabled = true
	s.PlaybackRegion = NumberRange.new(slice[1], slice[1] + slice[2])
	s.SoundGroup = group
	s.RollOffMode = Enum.RollOffMode.InverseTapered
	s.RollOffMinDistance = 14
	s.RollOffMaxDistance = 140
	return s
end

-- Plays a sound. opts.at = world position (3D); otherwise it's 2D.
function Sfx.play(name: string, opts: { [string]: any }?)
	if not ENABLED or muted then
		return
	end
	local o = opts or {}
	local now = os.clock()
	if now - (lastStart[name] or 0) < MIN_GAP then
		return
	end
	lastStart[name] = now
	local list = voices[name]
	if not list then
		list = {}
		voices[name] = list
	end
	-- reuse an idle voice of the same kind and place, else the oldest
	local spatial = o.at ~= nil
	local pick: Voice? = nil
	for _, v in list do
		if not v.sound.IsPlaying and (v.sound.Parent and v.sound.Parent:IsA("Attachment")) == spatial then
			pick = v
			break
		end
	end
	if not pick then
		if #list >= MAX_VOICES then
			table.sort(list, function(a, b)
				return a.started < b.started
			end)
			local old = table.remove(list, 1) :: Voice
			old.sound:Stop()
			local p = old.sound.Parent
			old.sound:Destroy()
			if p and p:IsA("Attachment") then
				p:Destroy()
			end
		end
		local s = newSound(name)
		if not s then
			return
		end
		if spatial then
			local a = Instance.new("Attachment")
			a.Parent = workspace.Terrain
			s.Parent = a
		else
			s.Parent = folder2d
		end
		pick = { sound = s, started = now }
		table.insert(list, pick :: Voice)
	end
	local v = pick :: Voice
	if spatial then
		(v.sound.Parent :: Attachment).WorldPosition = o.at
	end
	local vary = o.vary or 0.04
	v.sound.PlaybackSpeed = (o.pitch or 1) * (1 + (math.random() * 2 - 1) * vary)
	v.sound.Volume = (VOL[name] or 0.5) * (o.vol or 1)
	v.started = now
	v.sound.TimePosition = 0
	v.sound:Play()
end

-- Coins: each pickup within a short window goes a semitone higher (up to an octave).
local coinStreak, coinAt = 0, 0
function Sfx.coin(big: boolean?)
	local now = os.clock()
	coinStreak = now - coinAt < 1.1 and math.min(coinStreak + 1, 12) or 0
	coinAt = now
	Sfx.play(big and "coins" or "coin", { pitch = 2 ^ (coinStreak / 12), vary = 0.01 })
end

function Sfx.setMuted(on: boolean)
	muted = on
	group.Volume = on and 0 or 1
end
function Sfx.isMuted(): boolean
	return muted
end
Sfx.enabled = ENABLED

----------------------------------------------------------------------------------------------
-- Automatic hooks: button taps, panels, toasts, remote results, rewards, profile milestones.

function Sfx.start(Ui)
	if ENABLED then
		task.spawn(function()
			local probe = newSound("tap")
			if probe then
				probe.Parent = folder2d
				pcall(function()
					ContentProvider:PreloadAsync({ probe })
				end)
				probe:Destroy()
			end
		end)
	end

	-- every button gets a little haptic tick (set attribute NoTap on a button to skip it)
	local function hookButton(b: Instance)
		if b:IsA("GuiButton") and not b:GetAttribute("NoTap") then
			b.Activated:Connect(function()
				Sfx.play("tap", { vary = 0.08 })
			end)
		end
	end
	local pg = player:WaitForChild("PlayerGui")
	for _, d in pg:GetDescendants() do
		hookButton(d)
	end
	pg.DescendantAdded:Connect(hookButton)

	-- panels open/close
	local open = Ui.open
	Ui.open = function(name: string?)
		if name then
			Sfx.play("open", { vary = 0.02 })
		else
			Sfx.play("close", { vary = 0.02 })
		end
		return open(name)
	end

	-- toasts: warnings get the soft "nope"
	local toast = Ui.toast
	Ui.toast = function(msg: string, kind: string?)
		if kind == "warn" or kind == "alert" then
			Sfx.play("error")
		elseif kind == "good" then
			Sfx.play("toast")
		end
		return toast(msg, kind)
	end

	-- results of panel actions
	local call = Ui.call
	local ON_OK: { [string]: () -> () } = {
		ClaimQuest = function()
			Sfx.play("claim")
			task.delay(0.1, Sfx.coin, true)
		end,
		ClaimStreak = function()
			Sfx.play("claim")
			task.delay(0.1, Sfx.coin, true)
		end,
		BuyStorage = function()
			Sfx.play("buy")
		end,
		UpgradeWeapon = function()
			Sfx.play("buy")
			task.delay(0.12, Sfx.play, "level_up", { pitch = 1.12 })
		end,
		SetWeapon = function()
			Sfx.play("select")
		end,
		SetTeam = function()
			Sfx.play("select")
		end,
		Lock = function()
			Sfx.play("select", { pitch = 0.8 })
		end,
		Sell = function()
			Sfx.coin(true)
		end,
		Feed = function()
			Sfx.play("essence")
		end,
		Awaken = function()
			Sfx.play("reveal_rare")
		end,
		Overflow = function()
			Sfx.play("select")
		end,
	}
	Ui.call = function(name: string, ...)
		local ok, msg, res = call(name, ...)
		if ok and ON_OK[name] then
			ON_OK[name]()
		end
		return ok, msg, res
	end

	-- kill rewards
	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	remotes:WaitForChild("Reward").OnClientEvent:Connect(function(drops, ups)
		if type(drops) ~= "table" then
			return
		end
		if drops.coins and drops.coins > 0 then
			task.delay(0.15, Sfx.coin)
		end
		if drops.essence then
			task.delay(0.3, Sfx.play, "essence")
		end
		if drops.scroll or drops.legendary then
			task.delay(0.4, Sfx.play, "scroll_get", { pitch = drops.legendary and 1.12 or 1 })
		end
		if type(ups) == "table" and #ups > 0 then
			task.delay(0.5, Sfx.play, "level_up")
		end
	end)

	-- a daily quest just became claimable
	local done: { [string]: boolean } = {}
	local first = true
	Ui.onProfile(function(p)
		for i, q in (p.daily and p.daily.quests) or {} do
			local key = tostring(p.daily.day) .. ":" .. i
			local finished = q.p >= q.n
			if finished and not done[key] and not first then
				Sfx.play("quest_done")
			end
			done[key] = finished
		end
		first = false
	end)

	-- weapon skill back off cooldown
	local readyTimer = 0
	player:GetAttributeChangedSignal("WeaponSkillReady"):Connect(function()
		readyTimer += 1
		local my = readyTimer
		local wait = (player:GetAttribute("WeaponSkillReady") or 0) - workspace:GetServerTimeNow()
		if wait > 0.5 then
			task.delay(wait, function()
				if my == readyTimer then
					Sfx.play("skill_ready")
				end
			end)
		end
	end)

	-- new region, titan arrives
	player:GetAttributeChangedSignal("Region"):Connect(function()
		Sfx.play("region")
	end)
	workspace:GetAttributeChangedSignal("LegendUntil"):Connect(function()
		if (workspace:GetAttribute("LegendUntil") or 0) > os.time() then
			Sfx.play("announce", { pitch = 1.1 })
			task.delay(0.3, Sfx.play, "boss", { pitch = 1.3, vol = 0.7 })
		end
	end)
	workspace:GetAttributeChangedSignal("WorldBossUntil"):Connect(function()
		if (workspace:GetAttribute("WorldBossUntil") or 0) > os.time() then
			Sfx.play("boss")
		end
	end)
end

return Sfx

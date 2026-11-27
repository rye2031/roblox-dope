-- Champion Rifts (2026-11-27): hard mode for the open world. Each of the first four regions
-- has a rift: a crystal ring holding two camps of Lv 44-50 champions (always elite, 4-5★),
-- with much better loot (runes and weapons drop often, Pass XP like a boss). The rift opens
-- after the Eclipse Warden or with a Lv 42 monster; until then its ring pushes you back.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Theme = require(ReplicatedStorage.Shared.Theme)
local PlayerData = require(script.Parent.PlayerData)

local TC = Theme.C
local Rifts = {}
local Y = 2
local RADIUS = 24
local UNLOCK_BOSS, UNLOCK_LEVEL = "TwilightVale", 42

Rifts.List = {
	{ region = "SproutMeadow", pos = Vector3.new(-190, 0, 150), lv = { 44, 46 } },
	{ region = "EmberCanyon", pos = Vector3.new(320, 0, 545), lv = { 45, 47 } },
	{ region = "TideCoast", pos = Vector3.new(-330, 0, 140), lv = { 46, 48 } },
	{ region = "GaleHighlands", pos = Vector3.new(-190, 0, -540), lv = { 48, 50 } },
}

Rifts.debugLocked = setmetatable({}, { __mode = "k" }) -- Studio test: profiles treated as locked
function Rifts.unlocked(p): boolean
	if Rifts.debugLocked[p] then
		return false
	end
	if p.bosses[UNLOCK_BOSS] then
		return true
	end
	for _, m in p.monsters do
		if m.lv >= UNLOCK_LEVEL then
			return true
		end
	end
	return false
end

function Rifts.build(h, World)
	local f = Instance.new("Folder")
	f.Name = "ChampionRifts"
	f.Parent = h.root
	for i, r in Rifts.List do
		local c = Vector3.new(r.pos.X, Y, r.pos.Z)
		-- a ring of tilted crystals and a glowing rune circle on the ground
		for k = 0, 13 do
			local a = k / 14 * math.pi * 2
			local hgt = 7 + (k % 3) * 3
			local cr = h.part({ Name = "RiftCrystal", Size = Vector3.new(2.2, hgt, 2.2), CFrame = CFrame.new(c + Vector3.new(math.cos(a) * RADIUS, hgt / 2 - 0.6, math.sin(a) * RADIUS)) * CFrame.Angles(math.rad(math.cos(a) * -12), a, math.rad(math.sin(a) * 12)), Color = Color3.fromRGB(255, 92, 120), Material = Enum.Material.Neon, Transparency = 0.1 }, f)
			cr:SetAttribute("NoLod", true)
		end
		local ring = h.part({ Name = "RiftRing", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.2, RADIUS * 2, RADIUS * 2), CFrame = CFrame.new(c + Vector3.new(0, 0.12, 0)) * CFrame.Angles(0, 0, math.rad(90)), Color = Color3.fromRGB(120, 30, 60), Material = Enum.Material.Neon, Transparency = 0.75, CanCollide = false, CanQuery = false }, f)
		local e = Instance.new("ParticleEmitter")
		e.Texture = "rbxasset://textures/particles/sparkles_main.dds"
		e.Color = ColorSequence.new(Color3.fromRGB(255, 110, 140), Color3.fromRGB(255, 220, 230))
		e.Rate = 12
		e.Lifetime = NumberRange.new(1.5, 2.5)
		e.Speed = NumberRange.new(1, 4)
		e.Size = NumberSequence.new(0.6, 0)
		e.LightEmission = 0.7
		e.Parent = ring
		h.float("Rift" .. i, c + Vector3.new(0, 20, 0), "CHAMPION RIFT", TC.Coral, 11, { Icon = "🔥", Sub = string.format("Lv %d-%d · opens after the Eclipse Warden", r.lv[1], r.lv[2] + 2), Height = 2.8 })
		-- two champion camps inside (4★ and 5★, always elite)
		for k, off in { Vector3.new(-8, 0, 4), Vector3.new(9, 0, -6) } do
			table.insert(World.Camps, { id = "Rift" .. i .. "_" .. k, region = r.region, pos = c + off, radius = 6, count = k == 1 and 2 or 1, lv = { r.lv[1] + (k - 1) * 2, r.lv[2] + (k - 1) * 2 }, elite = true, stars = k == 1 and 4 or 5, champion = true, hpMult = k == 1 and 4.5 or 6 })
		end
	end
end

function Rifts.init(remotes)
	-- keep players who haven't earned it out of the ring
	local warned: { [Player]: number } = {}
	task.spawn(function()
		while true do
			task.wait(0.25)
			for _, pl in Players:GetPlayers() do
				local hrp = pl.Character and pl.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
				local p = PlayerData.get(pl)
				if hrp and p and not Rifts.unlocked(p) then
					for _, r in Rifts.List do
						local d = Vector3.new(hrp.Position.X - r.pos.X, 0, hrp.Position.Z - r.pos.Z)
						if d.Magnitude < RADIUS + 1 then
							local out = d.Magnitude > 0.5 and d.Unit or Vector3.new(1, 0, 0)
							local to = Vector3.new(r.pos.X, hrp.Position.Y, r.pos.Z) + out * (RADIUS + 6)
							hrp.CFrame = CFrame.lookAt(to, to + out)
							if os.clock() - (warned[pl] or 0) > 3 then
								warned[pl] = os.clock()
								remotes.Toast:FireClient(pl, `The Champion Rift is sealed: beat the Eclipse Warden in Twilight Vale, or get a monster to Lv {UNLOCK_LEVEL}`, "warn")
							end
						end
					end
				end
			end
		end
	end)
end

return Rifts

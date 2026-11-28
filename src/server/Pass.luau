-- Tamer Pass (2026-11-27): a free reward track that fills from normal play. No seasons, no
-- expiry, no paid skips: rewards wait until you claim them, and after the last tier every
-- 400 XP keeps giving a Regular scroll. (Shared/PassData has the tiers.)
--
-- Profile: p.pass = { xp, claimed = { ["<tier>"] = true }, bonus = claimed bonus count }
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PassData = require(ReplicatedStorage.Shared.PassData)
local Config = require(ReplicatedStorage.Shared.Config)
local PlayerData = require(script.Parent.PlayerData)

local Pass = {}
local remotes
local pending: { [Player]: number } = {} -- batch small XP gains into one push

local function state(p)
	p.pass = p.pass or { xp = 0, claimed = {}, bonus = 0 }
	return p.pass
end

function Pass.sanitize(raw, p)
	local r = typeof(raw) == "table" and typeof(raw.pass) == "table" and raw.pass or {}
	local out = { xp = math.max(0, math.floor(tonumber(r.xp) or 0)), claimed = {}, bonus = math.max(0, math.floor(tonumber(r.bonus) or 0)) }
	for k, v in (typeof(r.claimed) == "table" and r.claimed or {}) do
		local t = tonumber(k)
		if t and v == true and t >= 1 and t <= #PassData.Tiers then
			out.claimed[tostring(math.floor(t))] = true
		end
	end
	p.pass = out
end

-- Add pass XP for something the player did (source names are in PassData.Xp).
function Pass.add(player: Player, source: string, mult: number?)
	local p = PlayerData.get(player)
	local amt = PassData.Xp[source]
	if not p or not amt then
		return
	end
	local st = state(p)
	local before = PassData.tierAt(st.xp)
	st.xp += math.floor(amt * (mult or 1))
	local after = PassData.tierAt(st.xp)
	if after > before and remotes then
		remotes.Toast:FireClient(player, string.format("🎖 Tamer Pass tier %d reached! Claim it in the Pass", math.min(after, #PassData.Tiers)), "good")
	end
	-- coalesce: one push per second at most for XP-only changes
	if not pending[player] then
		pending[player] = 1
		task.delay(1, function()
			pending[player] = nil
			if player.Parent then
				PlayerData.push(player)
			end
		end)
	end
end

local function give(p, r)
	p.coins += r.coins or 0
	p.scrolls.Regular += r.scrolls or 0
	p.scrolls.Legendary += r.legendary or 0
	if r.essence then
		local els = { "Fire", "Water", "Wind" }
		local el = els[math.random(1, 3)]
		p.essence[el] = (p.essence[el] or 0) + r.essence
	end
	if r.rune then
		require(script.Parent.RuneBag).give(p, r.rune)
	end
	if r.gear then
		local Gear = require(ReplicatedStorage.Shared.Gear)
		require(script.Parent.GearBag).give(p, Gear.make(Random.new(), r.gear, nil, "Haven"))
	end
	if r.sealed then
		p.sealed.bag[r.sealed] = (p.sealed.bag[r.sealed] or 0) + 1
	end
end

function Pass.claim(player: Player, tier: any): (boolean, string)
	local p = PlayerData.get(player)
	if not p then
		return false, "No profile"
	end
	local st = state(p)
	local reached = PassData.tierAt(st.xp)
	if tier == "bonus" then
		local avail = PassData.bonusAvailable(st.xp) - st.bonus
		if avail <= 0 then
			return false, "No bonus reward yet"
		end
		st.bonus += avail
		p.scrolls.Regular += avail * PassData.Bonus.scrolls
		PlayerData.push(player)
		PlayerData.saveSoon(player)
		return true, string.format("+%d Regular Egg%s", avail * PassData.Bonus.scrolls, avail > 1 and "s" or "")
	end
	if tier == "all" then
		local n = 0
		for i = 1, math.min(reached, #PassData.Tiers) do
			if not st.claimed[tostring(i)] then
				st.claimed[tostring(i)] = true
				give(p, PassData.Tiers[i])
				n += 1
			end
		end
		if n == 0 then
			return false, "Nothing to claim yet"
		end
		PlayerData.push(player)
		PlayerData.saveSoon(player)
		return true, string.format("Claimed %d reward%s", n, n > 1 and "s" or "")
	end
	local t = typeof(tier) == "number" and math.floor(tier) or nil
	if not t or not PassData.Tiers[t] then
		return false, "Unknown reward"
	end
	if t > reached then
		return false, "Reach that tier first"
	end
	if st.claimed[tostring(t)] then
		return false, "Already claimed"
	end
	st.claimed[tostring(t)] = true
	give(p, PassData.Tiers[t])
	PlayerData.push(player)
	PlayerData.saveSoon(player)
	return true, "Claimed: " .. PassData.text(PassData.Tiers[t])
end

function Pass.init(r)
	remotes = r
	local _ = Config
end

return Pass

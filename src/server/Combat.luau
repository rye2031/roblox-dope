-- Real-time, server-authoritative combat for the open world.
--
-- Every monster in the world (your team of 3 and wild monsters) is a "unit": an invisible
-- anchored part in workspace.Units carrying replicated attributes, moved by this module at
-- TickRate. Clients draw the creature, nameplate, HP bar and effects on top of it.
-- Players (Tamers) fight too: their HP is the Humanoid's; their attacks arrive as intents.
--
-- Clients only send intents (attack + aim, weapon skill, dodge, team skill, focus target).
-- Everything else (range, cooldowns, damage, effects, rewards) is decided here.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Monsters = require(Shared.Monsters)
local PlayerData = require(script.Parent.PlayerData)
local Inventory = require(script.Parent.Inventory)
local Quests = require(script.Parent.Quests)
local Story = require(script.Parent.Story)
local Loops = require(script.Parent.Loops)
local World = require(script.Parent.World)

local T = Config.Tuning
local CT = T.Combat
local Combat = {}

local rng = Random.new()
local folder: Folder
local remotes
local units: { [string]: any } = {} -- id -> unit
local teams: { [Player]: { any } } = {} -- player -> { [slot] = unit }
local tamers: { [Player]: any } = {}
local nextId = 0
local events = {}
local now = os.clock

local function emit(e)
	table.insert(events, e)
end

----------------------------------------------------------------------------------------------
-- Tamers (players as combatants)

local function hrpOf(player: Player): BasePart?
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if not hum or hum.Health <= 0 then
		return nil
	end
	return char:FindFirstChild("HumanoidRootPart") :: BasePart?
end

local function tamerOf(player: Player)
	local t = tamers[player]
	if not t then
		t = { kind = "tamer", key = "p" .. player.UserId, player = player, effects = {}, shield = 0, cd = {}, focus = nil, invulnUntil = 0, lastCombat = 0 }
		tamers[player] = t
	end
	local p = PlayerData.get(player)
	t.stats = Config.tamerStats(p and p.weapon.lv or 1)
	return t
end

-- Generic accessors so units and tamers can be treated alike.
local function posOf(e): Vector3?
	if e.kind == "tamer" then
		local hrp = hrpOf(e.player)
		return hrp and hrp.Position
	end
	return e.pos
end

local function alive(e): boolean
	if not e then
		return false
	end
	if e.kind == "tamer" then
		return e.player.Parent ~= nil and hrpOf(e.player) ~= nil
	end
	return e.state ~= "dead" and e.state ~= "fainted" and units[e.id] == e
end

local function maxHpOf(e): number
	if e.kind == "tamer" then
		local hum = e.player.Character and e.player.Character:FindFirstChildOfClass("Humanoid")
		return hum and hum.MaxHealth or 100
	end
	return e.maxHp
end

local function hpOf(e): number
	if e.kind == "tamer" then
		local hum = e.player.Character and e.player.Character:FindFirstChildOfClass("Humanoid")
		return hum and hum.Health or 0
	end
	return e.hp
end

local function keyOf(e): string
	return e.kind == "tamer" and e.key or e.id
end

local function elementOf(e): string
	return e.kind == "tamer" and "None" or e.el
end

-- The Player who owns an entity (team units and tamers); nil for wild monsters.
local function ownerOf(e): Player?
	if e.kind == "tamer" then
		return e.player
	end
	return e.owner
end

----------------------------------------------------------------------------------------------
-- Effects

local function effectValue(e, stat: string): number
	local v = 0
	local t = now()
	for _, fx in e.effects do
		if fx.untilT > t then
			if fx.type == "buff" and fx.stat == stat then
				v += fx.pct
			elseif fx.type == "debuff" and fx.stat == stat then
				v -= fx.pct
			elseif fx.type == "slow" and stat == "spd" then
				v -= fx.pct
			end
		end
	end
	return v
end

local function hasEffect(e, kind: string): boolean
	local t = now()
	for _, fx in e.effects do
		if fx.type == kind and fx.untilT > t then
			return true
		end
	end
	return false
end

local function addEffect(e, fx)
	if e.kind == "unit" and e.boss and fx.type == "stun" then
		fx.dur = fx.dur * 0.4 -- bosses shrug off most of a stun
	end
	table.insert(e.effects, { type = fx.type, stat = fx.stat, pct = fx.pct or 0, untilT = now() + (fx.dur or 0), src = fx.src })
end

local function cleanse(e)
	local keep = {}
	for _, fx in e.effects do
		if fx.type == "buff" then
			table.insert(keep, fx)
		end
	end
	e.effects = keep
end

local function effectList(e): string
	local t = now()
	local seen, out = {}, {}
	for _, fx in e.effects do
		if fx.untilT > t then
			local name = fx.type == "buff" and ("+" .. fx.stat) or fx.type == "debuff" and ("-" .. fx.stat) or fx.type
			if not seen[name] then
				seen[name] = true
				table.insert(out, name)
			end
		end
	end
	if (e.shield or 0) > 0 then
		table.insert(out, "shield")
	end
	return table.concat(out, ",")
end

----------------------------------------------------------------------------------------------
-- Units

local function teamOf(e): { any }
	-- allies an effect with to = "team" reaches
	local out = {}
	if e.kind == "tamer" or e.side == "team" then
		local owner = ownerOf(e)
		for _, u in teams[owner :: Player] or {} do
			if alive(u) then
				table.insert(out, u)
			end
		end
		local t = owner and tamers[owner]
		if t and alive(t) then
			table.insert(out, t)
		end
	else
		for _, u in units do
			if u.side == "wild" and alive(u) and (u.pos - e.pos).Magnitude < 30 then
				table.insert(out, u)
			end
		end
	end
	return out
end

local function hostile(a, b): boolean
	local sa = a.kind == "tamer" and "team" or a.side
	local sb = b.kind == "tamer" and "team" or b.side
	return sa ~= sb
end

local function heightOf(sp: string, boss: boolean?, elite: boolean?): number
	local h = Monsters.Species[sp].Height
	if boss then
		h *= 2.4
	elseif elite then
		h *= 1.35
	end
	return h
end

local function placePart(u)
	local y = World.groundY(u.pos.X, u.pos.Z)
	u.pos = Vector3.new(u.pos.X, y, u.pos.Z)
	local look = u.facing or Vector3.new(0, 0, -1)
	local centre = u.pos + Vector3.new(0, u.size.Y / 2 + (Monsters.Species[u.sp].Hover or 0), 0)
	u.part.CFrame = CFrame.lookAt(centre, centre + Vector3.new(look.X, 0, look.Z))
end

local function syncAttrs(u)
	local p = u.part
	p:SetAttribute("HP", math.max(0, math.floor(u.hp)))
	p:SetAttribute("MaxHP", math.floor(u.maxHp))
	p:SetAttribute("Shield", math.floor(u.shield or 0))
	p:SetAttribute("State", u.state)
	p:SetAttribute("Effects", effectList(u))
	p:SetAttribute("Target", u.target and keyOf(u.target) or nil)
end

local function makeUnit(side: string, sp: string, el: string, lv: number, aw: boolean, sk: { number }, opts)
	nextId += 1
	local id = (side == "team" and "t" or "w") .. nextId
	local stats = Monsters.stats(sp, lv, aw)
	local hpMult = 1
	if side == "wild" then
		hpMult = CT.WildHpMult * (opts.hpMult or (opts.boss and 22 or opts.elite and 3.5 or 1))
		stats.atk = math.floor(stats.atk * CT.WildAtkMult)
		if opts.boss then
			stats.atk = math.floor(stats.atk * 1.5)
			stats.def = math.floor(stats.def * 1.3)
		elseif opts.elite then
			stats.atk = math.floor(stats.atk * 1.25)
		end
	end
	local h = heightOf(sp, opts.boss, opts.elite)
	local part = Instance.new("Part")
	part.Name = id
	part.Size = Vector3.new(h * 0.8, h, h * 0.8)
	part.Transparency = 1
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = true
	part:SetAttribute("Side", side)
	part:SetAttribute("Species", sp)
	part:SetAttribute("Element", el)
	part:SetAttribute("Level", lv)
	part:SetAttribute("Stars", Monsters.Species[sp].Stars)
	part:SetAttribute("Awakened", aw)
	part:SetAttribute("Elite", opts.elite == true)
	part:SetAttribute("Boss", opts.boss == true)
	if opts.owner then
		part:SetAttribute("Owner", opts.owner.UserId)
		part:SetAttribute("Slot", opts.slot)
		part:SetAttribute("Uid", opts.uid)
	end
	local u = {
		kind = "unit", id = id, side = side, sp = sp, el = el, lv = lv, aw = aw, sk = sk,
		stats = stats, maxHp = stats.hp * hpMult, hp = stats.hp * hpMult, baseMaxHp = stats.hp * hpMult,
		shield = 0, shieldUntil = 0, effects = {}, cd = { 0, now() + 2 + rng:NextNumber() * 2, now() + 6 },
		target = nil, threat = {}, contrib = {}, players = 0,
		owner = opts.owner, slot = opts.slot, uid = opts.uid, camp = opts.camp, home = opts.pos, elite = opts.elite, boss = opts.boss,
		pos = opts.pos, facing = Vector3.new(0, 0, -1), size = part.Size, part = part, state = "idle",
		lastCombat = 0, wanderTo = nil, pending = nil,
	}
	units[id] = u
	placePart(u)
	syncAttrs(u)
	part.Parent = folder
	return u
end

local function removeUnit(u)
	units[u.id] = nil
	u.state = "dead"
	if u.part then
		u.part:Destroy()
	end
end

----------------------------------------------------------------------------------------------
-- Damage

local function rewardKill(u)
	local need = u.baseMaxHp * CT.ContributionShare * math.max(1, u.players)
	local R = T.Rewards
	for player, dmg in u.contrib do
		if player.Parent and dmg >= math.min(need, u.maxHp * 0.25) then
			local p = PlayerData.get(player)
			if p then
				local stars = Monsters.Species[u.sp].Stars
				local mult = u.boss and 8 or u.elite and 3 or 1
				local xp = T.KillXp(u.lv, stars) * mult
				local levels = 0
				local ups = {}
				for _, tu in teams[player] or {} do
					if tu.uid then
						local g = Inventory.grantXp(p, tu.uid, xp)
						if g > 0 then
							levels += g
							table.insert(ups, tu.uid)
						end
					end
				end
				local surge = u.el == Loops.surge()
				local coins = math.floor(R.CoinsPerKill(u.lv) * mult * (surge and Config.Loops.Surge.CoinMult or 1))
				p.coins += coins
				p.kills += 1
				local drops = { coins = coins, xp = xp, el = u.el, pos = u.pos }
				if rng:NextNumber() < (u.boss and 1 or u.elite and 0.8 or R.EssenceChance) then
					local n = (u.boss and 8 or u.elite and 3 or 1) * (surge and Config.Loops.Surge.EssenceMult or 1)
					if u.el == "Dark" and Loops.phase() == "night" then
						n *= Config.DayNight.DarkEssenceMult
					end
					p.essence[u.el] = (p.essence[u.el] or 0) + n
					drops.essence = n
				end
				local scrollChance = u.elite and R.EliteScrollChance or R.RegularScrollChance
				if u.boss then
					p.scrolls.Regular += R.BossScrolls
					drops.scroll = "Regular"
					if rng:NextNumber() < 0.25 then
						p.scrolls.Legendary += 1
						drops.legendary = true
					end
				elseif rng:NextNumber() < scrollChance then
					p.scrolls.Regular += 1
					drops.scroll = "Regular"
				end
				Quests.onKill(player, u.el, u.elite)
				Story.event(player, "defeat", { region = u.camp and u.camp.region })
				if levels > 0 then
					Quests.progress(player, "LevelUp", levels)
				end
				if u.boss and Combat.onBossDefeated then
					Combat.onBossDefeated(player, u)
				end
				PlayerData.push(player)
				Combat.refreshTeamStats(player)
				remotes.Reward:FireClient(player, drops, ups)
			end
		end
	end
end

local function die(u)
	if u.side == "team" then
		u.state = "fainted"
		u.hp = 0
		u.faintUntil = now() + CT.FaintRevive
		u.target = nil
		u.effects = {}
		emit({ "faint", u.id })
		syncAttrs(u)
		return
	end
	u.state = "dead"
	emit({ "die", u.id })
	rewardKill(u)
	local camp = u.camp
	task.delay(0.6, function()
		removeUnit(u)
	end)
	if camp and not u.boss then
		task.delay(u.elite and 90 or CT.CommonRespawn, function()
			Combat.spawnWild(camp)
		end)
	end
	if u.boss and Combat.onBossDied then
		Combat.onBossDied(u)
	end
end

local function heal(e, amount: number)
	if amount <= 0 or not alive(e) then
		return
	end
	if e.kind == "tamer" then
		local hum = e.player.Character and e.player.Character:FindFirstChildOfClass("Humanoid")
		if hum then
			hum.Health = math.min(hum.MaxHealth, hum.Health + amount)
			emit({ "heal", e.key, math.floor(amount) })
		end
		return
	end
	e.hp = math.min(e.maxHp, e.hp + amount)
	emit({ "heal", e.id, math.floor(amount) })
end

-- Scale a wild monster's HP when more players join the fight.
local function noteContributor(target, player: Player)
	if target.side ~= "wild" or not player then
		return
	end
	if target.contrib[player] == nil then
		target.contrib[player] = 0
		local n = 0
		for _ in target.contrib do
			n += 1
		end
		target.players = n
		local newMax = target.baseMaxHp * (1 + CT.MobHpPerPlayer * (n - 1))
		if newMax > target.maxHp then
			target.hp *= newMax / target.maxHp
			target.maxHp = newMax
		end
	end
end

-- Apply damage from src (any entity) to dst. Returns damage dealt.
local function damage(src, dst, mult: number, element: string?): number
	if not alive(dst) or not alive(src) then
		return 0
	end
	if dst.kind == "tamer" and now() < dst.invulnUntil then
		emit({ "miss", dst.key })
		return 0
	end
	local atk = src.stats.atk * (1 + effectValue(src, "atk"))
	local def = math.max(0, (dst.stats and dst.stats.def or 0) * (1 + effectValue(dst, "def")))
	local adv = Config.advantage(element or elementOf(src), elementOf(dst))
	local crit = rng:NextNumber() < (src.stats.crit or 0.1)
	local amount = mult * atk * (CT.Mitigation / (CT.Mitigation + def)) * adv * (crit and (src.stats.critDmg or 1.5) or 1) * (0.95 + rng:NextNumber() * 0.1)
	if dst.kind == "tamer" then
		amount *= CT.TamerDamageTaken
	end
	amount = math.max(1, math.floor(amount))
	-- shields absorb first
	local absorbed = 0
	if (dst.shield or 0) > 0 then
		absorbed = math.min(dst.shield, amount)
		dst.shield -= absorbed
	end
	local dealt = amount - absorbed
	if dst.kind == "tamer" then
		local hum = dst.player.Character and dst.player.Character:FindFirstChildOfClass("Humanoid")
		if hum then
			hum:TakeDamage(dealt)
		end
		dst.lastCombat = now()
	else
		dst.hp -= dealt
		dst.lastCombat = now()
	end
	src.lastCombat = now()
	emit({ "hit", keyOf(dst), amount, crit, element or elementOf(src), adv })
	-- threat, contribution and retaliation
	local owner = ownerOf(src)
	if dst.kind == "unit" and dst.side == "wild" then
		if owner then
			noteContributor(dst, owner)
			dst.contrib[owner] += amount
		end
		dst.threat[keyOf(src)] = (dst.threat[keyOf(src)] or 0) + amount * (src.kind == "tamer" and CT.TamerThreat or 1)
		if not dst.target or not alive(dst.target) then
			dst.target = src
		end
		-- pack aggro: campmates join in, going for the attacker's monsters before the Tamer
		local party = owner and teams[owner]
		for _, o in units do
			if o.side == "wild" and o ~= dst and o.camp == dst.camp and not o.target and alive(o) then
				local pick = src
				if src.kind == "tamer" and party then
					local best, bd = nil, math.huge
					for _, tu in party do
						if alive(tu) then
							local d = (tu.pos - o.pos).Magnitude
							if d < bd then
								best, bd = tu, d
							end
						end
					end
					pick = best or src
				end
				o.target = pick
			end
		end
	end
	-- lifesteal
	local ls = effectValue(src, "lifesteal")
	if ls > 0 then
		heal(src, dealt * ls)
	end
	if dst.kind == "unit" and dst.hp <= 0 then
		die(dst)
	end
	return amount
end

----------------------------------------------------------------------------------------------
-- Skills

local function enemiesNear(caster, centre: Vector3, radius: number): { any }
	local out = {}
	for _, u in units do
		if alive(u) and hostile(caster, u) and (u.pos - centre).Magnitude <= radius + u.size.X / 2 then
			table.insert(out, u)
		end
	end
	if caster.kind == "unit" and caster.side == "wild" then
		for _, t in tamers do
			local p = posOf(t)
			if p and alive(t) and (p - centre).Magnitude <= radius + 1.5 then
				table.insert(out, t)
			end
		end
	end
	return out
end
Combat.enemiesNear = enemiesNear

local function applySkillEffects(caster, skill, targets: { any }, power: number)
	for _, fx in skill.Effects do
		local t = fx.type
		if t == "heal" then
			local list = fx.to == "lowest" and {} or teamOf(caster)
			if fx.to == "lowest" then
				local best, ratio = nil, 2
				for _, a in teamOf(caster) do
					local r = hpOf(a) / maxHpOf(a)
					if r < ratio then
						best, ratio = a, r
					end
				end
				list = best and { best } or {}
			elseif fx.to == "self" then
				list = { caster }
			end
			for _, a in list do
				heal(a, maxHpOf(a) * fx.pct * power)
			end
		elseif t == "shield" then
			local list = fx.to == "self" and { caster } or teamOf(caster)
			for _, a in list do
				a.shield = math.max(a.shield or 0, maxHpOf(a) * fx.pct * power)
				a.shieldUntil = now() + fx.dur
			end
		elseif t == "buff" then
			local list = fx.to == "self" and { caster } or teamOf(caster)
			for _, a in list do
				addEffect(a, fx)
			end
		elseif t == "cleanse" then
			for _, a in (fx.to == "self" and { caster } or teamOf(caster)) do
				cleanse(a)
			end
		elseif t == "taunt" then
			for _, u in enemiesNear(caster, posOf(caster) :: Vector3, 22) do
				if u.kind == "unit" then
					u.target = caster
					u.tauntUntil = now() + fx.dur
				end
			end
		else
			-- harmful: burn, stun, slow, debuff, silence (on the damage targets)
			for _, d in targets do
				if alive(d) and (fx.chance == nil or rng:NextNumber() < fx.chance) then
					addEffect(d, { type = t, stat = fx.stat, pct = fx.pct, dur = fx.dur, src = caster })
				end
			end
		end
	end
end

-- Cast skill i (1 = signature, 2 = A, 3 = B) of a unit. Returns true if cast.
local function cast(u, i: number, forced: boolean?): boolean
	local skills = Monsters.skills(u.sp, u.el)
	local skill = skills[i]
	local lvl = u.sk and u.sk[i] or 1
	local power = Monsters.skillPower(lvl)
	if now() < u.cd[i] then
		return false
	end
	if i > 1 and hasEffect(u, "silence") then
		return false
	end
	local target = u.target
	local targets = {}
	if skill.Target ~= "none" then
		if not alive(target) then
			return false
		end
		local tp = posOf(target) :: Vector3
		local range = (Monsters.Species[u.sp].Range == "ranged" and CT.RangedRange or CT.MeleeRange) + u.size.X / 2 + (target.size and target.size.X / 2 or 1)
		if (tp - u.pos).Magnitude > range + (i == 3 and 6 or 0) then
			return false
		end
		if skill.Target == "aoe" then
			targets = enemiesNear(u, tp, skill.Radius)
		else
			targets = { target }
		end
	end
	local spdFactor = 100 / math.max(40, u.stats.spd * (1 + effectValue(u, "spd")))
	u.cd[i] = now() + Monsters.skillCooldown(skill.Cooldown, lvl) * spdFactor
	emit({ "cast", u.id, i, skill.Name, target and posOf(target) or u.pos, u.el, skill.Target == "aoe" and skill.Radius or 0 })
	if skill.Mult > 0 then
		for _ = 1, skill.Hits do
			for _, d in targets do
				damage(u, d, skill.Mult * power, u.el)
			end
		end
	end
	for _, fx in skill.Effects do
		if fx.type == "lifesteal" then
			-- skill lifesteal: heal a share of what this cast dealt (approximate with one hit)
			heal(u, u.stats.atk * skill.Mult * power * fx.pct)
		end
	end
	applySkillEffects(u, skill, targets, power)
	return true
end

----------------------------------------------------------------------------------------------
-- Movement / AI

local function moveToward(u, dest: Vector3, speed: number, dt: number, stopAt: number)
	local d = Vector3.new(dest.X - u.pos.X, 0, dest.Z - u.pos.Z)
	local dist = d.Magnitude
	if dist <= stopAt then
		if dist > 0.01 then
			u.facing = d.Unit
		end
		return true
	end
	local sp = speed * math.max(0.3, 1 + effectValue(u, "spd"))
	local step = math.min(dist - stopAt, sp * dt)
	u.facing = d.Unit
	u.pos += d.Unit * step
	u.state = "move"
	return false
end

local SLOT_OFFSET = { Vector3.new(-5, 0, 5), Vector3.new(5, 0, 5), Vector3.new(0, 0, 9) }

local function nearestThreat(player: Player, from: Vector3)
	local best, bd = nil, 45
	local myKeys = { ["p" .. player.UserId] = true }
	for _, u in teams[player] or {} do
		myKeys[u.id] = true
	end
	for _, w in units do
		if w.side == "wild" and alive(w) and w.target and myKeys[keyOf(w.target)] then
			local d = (w.pos - from).Magnitude
			if d < bd then
				best, bd = w, d
			end
		end
	end
	return best
end

local function updateTeamUnit(u, dt: number)
	local player = u.owner :: Player
	local hrp = hrpOf(player)
	if u.state == "fainted" then
		if now() >= (u.faintUntil or 0) then
			u.state = "idle"
			u.hp = u.maxHp * 0.5
			emit({ "revive", u.id })
			if hrp then
				u.pos = hrp.Position
			end
		end
		syncAttrs(u)
		return
	end
	if not hrp then
		return
	end
	-- burns tick even when not fighting
	local tamer = tamerOf(player)
	if u.target and (not alive(u.target) or (posOf(u.target) - hrp.Position).Magnitude > 90) then
		u.target = nil
	end
	if not u.target then
		local f = tamer.focus
		if f and alive(f) and (posOf(f) - hrp.Position).Magnitude < 70 then
			u.target = f
		else
			u.target = nearestThreat(player, hrp.Position)
		end
	end
	if hasEffect(u, "stun") then
		u.state = "stunned"
		return
	end
	if u.target then
		local tp = posOf(u.target) :: Vector3
		local range = (Monsters.Species[u.sp].Range == "ranged" and CT.RangedRange or CT.MeleeRange) + u.size.X / 2 + (u.target.size and u.target.size.X / 2 or 1)
		local inRange = moveToward(u, tp, CT.FollowSpeed, dt, range * 0.85)
		if inRange then
			u.state = "attack"
			if not cast(u, 2) then
				cast(u, 1)
			end
		end
	else
		-- formation behind the Tamer
		local cf = hrp.CFrame
		local goal = (cf * CFrame.new(SLOT_OFFSET[u.slot] or Vector3.new(0, 0, 6))).Position
		if (goal - u.pos).Magnitude > 90 then
			u.pos = goal
		end
		if moveToward(u, goal, CT.FollowSpeed, dt, 1.5) then
			u.state = "idle"
			u.facing = cf.LookVector
		end
		-- regen out of combat
		if now() - u.lastCombat > 5 and u.hp < u.maxHp then
			u.hp = math.min(u.maxHp, u.hp + u.maxHp * CT.OutOfCombatRegen * dt)
		end
	end
end

local function updateWildUnit(u, dt: number)
	if u.state == "dead" then
		return
	end
	if hasEffect(u, "stun") then
		u.state = "stunned"
		return
	end
	-- pending telegraphed ultimate
	if u.pending then
		if now() >= u.pending.at then
			local skill = Monsters.skills(u.sp, u.el)[3]
			local targets = enemiesNear(u, u.pending.pos, skill.Radius)
			emit({ "cast", u.id, 3, skill.Name, u.pending.pos, u.el, skill.Radius })
			if skill.Mult > 0 then
				for _ = 1, skill.Hits do
					for _, d in targets do
						damage(u, d, skill.Mult * 1.0, u.el)
					end
				end
			end
			applySkillEffects(u, skill, targets, 1)
			u.pending = nil
		end
		return
	end
	local homeDist = (u.pos - u.home).Magnitude
	if u.state == "return" or homeDist > CT.LeashRadius then
		u.state = "return"
		u.target = nil
		u.threat = {}
		u.contrib = {}
		u.players = 0
		u.maxHp = u.baseMaxHp
		if moveToward(u, u.home, CT.WildSpeed * 1.6, dt, 2) then
			u.state = "idle"
			u.hp = u.maxHp
			u.effects = {}
		end
		return
	end
	-- pick the biggest threat that is still around
	if u.target and not alive(u.target) then
		u.threat[keyOf(u.target)] = nil
		u.target = nil
	end
	if (u.tauntUntil or 0) < now() then
		local best, bv = nil, -1
		for k, v in u.threat do
			local e = units[k]
			if not e then
				for _, t in tamers do
					if t.key == k then
						e = t
					end
				end
			end
			if e and alive(e) and v > bv then
				best, bv = e, v
			elseif not (e and alive(e)) then
				u.threat[k] = nil
			end
		end
		if best then
			u.target = best
		end
	end
	if u.target then
		local tp = posOf(u.target)
		if not tp then
			u.target = nil
			return
		end
		local range = (Monsters.Species[u.sp].Range == "ranged" and CT.RangedRange or CT.MeleeRange) + u.size.X / 2 + 1
		if moveToward(u, tp, CT.WildSpeed * (u.boss and 0.8 or 1), dt, range * 0.85) then
			u.state = "attack"
			-- ultimates are telegraphed so players can dodge
			local skill = Monsters.skills(u.sp, u.el)[3]
			if now() >= u.cd[3] and skill.Target == "aoe" then
				u.cd[3] = now() + skill.Cooldown * (u.boss and 0.6 or 1)
				u.pending = { at = now() + (u.boss and 1.6 or 1.2), pos = tp }
				emit({ "telegraph", u.id, tp, skill.Radius, u.boss and 1.6 or 1.2 })
				return
			end
			if not cast(u, 2) then
				cast(u, 1)
			end
		end
	else
		-- roam around the camp
		if not u.wanderTo or rng:NextNumber() < 0.01 then
			local a = rng:NextNumber() * math.pi * 2
			local r = rng:NextNumber() * (u.boss and 8 or 12)
			u.wanderTo = u.home + Vector3.new(math.cos(a) * r, 0, math.sin(a) * r)
		end
		if moveToward(u, u.wanderTo, CT.RoamSpeed, dt, 1) then
			u.state = "idle"
		end
		if u.hp < u.maxHp and now() - u.lastCombat > 6 then
			u.hp = math.min(u.maxHp, u.hp + u.maxHp * (u.boss and 0.015 or 0.1) * dt) -- bosses heal slowly, so a knocked-out team can come back
		end
	end
end

local function tickEffects(e, dt: number)
	local t = now()
	local keep = {}
	for _, fx in e.effects do
		if fx.untilT > t then
			table.insert(keep, fx)
			if fx.type == "burn" then
				local amt = maxHpOf(e) * fx.pct * dt
				if e.kind == "tamer" then
					local hum = e.player.Character and e.player.Character:FindFirstChildOfClass("Humanoid")
					if hum and t >= e.invulnUntil then
						hum:TakeDamage(amt)
					end
				else
					e.hp -= amt
					e.lastCombat = t
					if fx.src and ownerOf(fx.src) and e.side == "wild" then
						local o = ownerOf(fx.src) :: Player
						noteContributor(e, o)
						e.contrib[o] += amt
					end
					if e.hp <= 0 then
						die(e)
					end
				end
			end
		end
	end
	e.effects = keep
	if (e.shield or 0) > 0 and t > (e.shieldUntil or 0) then
		e.shield = 0
	end
end

----------------------------------------------------------------------------------------------
-- Spawning

local function pickWildSpecies(region): string
	local stars = Config.pickWeighted(region.StarWeights, rng:NextNumber())
	local pool = Monsters.byStars(stars)
	return pool[rng:NextInteger(1, #pool)]
end

function Combat.spawnWild(camp)
	local region = World.Regions[camp.region]
	-- top the camp back up to its count
	local n = 0
	for _, u in units do
		if u.camp == camp and u.state ~= "dead" then
			n += 1
		end
	end
	for _ = n + 1, camp.count do
		local a = rng:NextNumber() * math.pi * 2
		local r = rng:NextNumber() * camp.radius
		local pos = camp.pos + Vector3.new(math.cos(a) * r, 0, math.sin(a) * r)
		local sp = camp.species or pickWildSpecies(region)
		local el = camp.element or Config.pickWeighted(Loops.surgeWeights(region.Elements), rng:NextNumber())
		local lv = rng:NextInteger(camp.lv[1], camp.lv[2])
		local nightBonus = Loops.phase() == "night" and Config.DayNight.NightEliteBonus or 0
		local elite = camp.elite or (not camp.boss and rng:NextNumber() < (region.EliteChance or 0) + nightBonus)
		makeUnit("wild", sp, el, lv, false, { 1, 1, 1 }, { pos = pos, camp = camp, elite = elite, boss = camp.boss, hpMult = camp.hpMult })
	end
end

-- Living units of a camp, and removing them without rewards (timed-out world boss).
function Combat.campUnits(camp): { any }
	local out = {}
	for _, u in units do
		if u.camp == camp and u.state ~= "dead" then
			table.insert(out, u)
		end
	end
	return out
end
function Combat.despawnCamp(camp)
	for _, u in Combat.campUnits(camp) do
		emit({ "die", u.id })
		removeUnit(u)
	end
end

-- Build or refresh a player's 3 team units from their profile.
function Combat.syncTeam(player: Player)
	local p = PlayerData.get(player)
	if not p then
		return
	end
	local team = teams[player] or {}
	teams[player] = team
	local hrp = hrpOf(player)
	for slot = 1, T.TeamSize do
		local uid = p.team[slot]
		local m = uid ~= "" and p.monsters[uid] or nil
		local cur = team[slot]
		if cur and (not m or cur.uid ~= uid or cur.el ~= m.el) then
			removeUnit(cur)
			team[slot] = nil
			cur = nil
		end
		if m and not cur then
			local pos = hrp and hrp.Position or World.Points.Spawn
			team[slot] = makeUnit("team", m.sp, m.el, m.lv, m.aw, m.sk, { owner = player, slot = slot, uid = uid, pos = pos })
		end
	end
	Combat.refreshTeamStats(player)
end

-- Level-ups and awakening change stats; keep the HP share.
function Combat.refreshTeamStats(player: Player)
	local p = PlayerData.get(player)
	for _, u in teams[player] or {} do
		local m = p and p.monsters[u.uid]
		if m and (m.lv ~= u.lv or m.aw ~= u.aw or m.sk[1] ~= u.sk[1] or m.sk[2] ~= u.sk[2] or m.sk[3] ~= u.sk[3]) then
			local ratio = u.maxHp > 0 and u.hp / u.maxHp or 1
			u.lv, u.aw, u.sk = m.lv, m.aw, table.clone(m.sk)
			u.stats = Monsters.stats(u.sp, u.lv, u.aw)
			u.maxHp, u.baseMaxHp = u.stats.hp, u.stats.hp
			u.hp = u.maxHp * ratio
			u.part:SetAttribute("Level", u.lv)
			u.part:SetAttribute("Awakened", u.aw)
		end
	end
	-- the Tamer's HP follows the weapon level
	local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if hum and p then
		local max = Config.tamerStats(p.weapon.lv).hp
		if hum.MaxHealth ~= max then
			local r = hum.Health / hum.MaxHealth
			hum.MaxHealth = max
			hum.Health = max * r
		end
	end
end

function Combat.clearTeam(player: Player)
	for _, u in teams[player] or {} do
		removeUnit(u)
	end
	teams[player] = nil
end

-- Move the team next to a point at once (fast travel).
function Combat.warpTeam(player: Player, pos: Vector3)
	for slot, u in teams[player] or {} do
		local a = slot / 3 * math.pi * 2
		u.pos = pos + Vector3.new(math.cos(a) * 5, 0, math.sin(a) * 5)
		u.target = nil
		placePart(u)
	end
end

-- True while the player has fought in the last few seconds.
function Combat.inCombat(player: Player): boolean
	local t = tamers[player]
	return t ~= nil and now() - (t.lastCombat or 0) < 6
end

-- Full heal for the player's team (campfires, respawn).
function Combat.healTeam(player: Player)
	for _, u in teams[player] or {} do
		if u.state == "fainted" then
			u.state = "idle"
		end
		u.hp = u.maxHp
		u.effects = {}
		syncAttrs(u)
	end
end

----------------------------------------------------------------------------------------------
-- Player intents

local WEAPON = T.Weapons

local function flat(v: Vector3): Vector3
	local f = Vector3.new(v.X, 0, v.Z)
	return f.Magnitude > 0.01 and f.Unit or Vector3.new(0, 0, -1)
end

-- First wild unit along a ray from origin (flat), within range.
local function rayHit(origin: Vector3, dir: Vector3, range: number)
	local best, bt = nil, range
	for _, u in units do
		if u.side == "wild" and alive(u) then
			local rel = u.pos + Vector3.new(0, u.size.Y / 2, 0) - origin
			local along = rel:Dot(dir)
			if along > 0 and along < bt then
				local perp = (rel - dir * along).Magnitude
				if perp <= u.size.X / 2 + 1.5 then
					best, bt = u, along
				end
			end
		end
	end
	return best, bt
end

local function setFocus(t, target)
	if target and target.side == "wild" then
		t.focus = target
		for _, u in teams[t.player] or {} do
			if not u.target or not alive(u.target) then
				u.target = target
			end
		end
	end
end

function Combat.attack(player: Player, aim: any)
	local hrp = hrpOf(player)
	local p = PlayerData.get(player)
	if not hrp or not p or typeof(aim) ~= "Vector3" then
		return
	end
	local t = tamerOf(player)
	local w = WEAPON[p.weapon.type]
	if now() < (t.cd.attack or 0) then
		return
	end
	t.cd.attack = now() + w.Cooldown * 0.9 -- small tolerance for latency
	local dir = flat(aim)
	local origin = hrp.Position
	local hits = {}
	if w.Ranged then
		local u, dist = rayHit(origin, dir, w.Range)
		emit({ "shot", t.key, origin, origin + dir * (u and dist or w.Range), p.weapon.type })
		if u then
			table.insert(hits, u)
		end
	else
		local half = math.rad(w.Arc / 2)
		for _, u in units do
			if u.side == "wild" and alive(u) then
				local rel = Vector3.new(u.pos.X - origin.X, 0, u.pos.Z - origin.Z)
				local d = rel.Magnitude - u.size.X / 2
				if d <= w.Range and (rel.Magnitude < 2 or math.acos(math.clamp(rel.Unit:Dot(dir), -1, 1)) <= half) then
					table.insert(hits, u)
				end
			end
		end
		emit({ "swing", t.key, origin, dir, p.weapon.type })
	end
	for _, u in hits do
		damage(t, u, w.Mult, "None")
		if p.weapon.type == "Hammer" and rng:NextNumber() < 0.2 then
			addEffect(u, { type = "stun", dur = 0.5 })
		end
	end
	if hits[1] then
		setFocus(t, hits[1])
	end
	t.lastCombat = now()
end

function Combat.weaponSkill(player: Player, aim: any)
	local hrp = hrpOf(player)
	local p = PlayerData.get(player)
	if not hrp or not p or typeof(aim) ~= "Vector3" then
		return
	end
	local t = tamerOf(player)
	local kind = p.weapon.type
	local s = WEAPON[kind].Skill
	if now() < (t.cd.skill or 0) then
		return
	end
	t.cd.skill = now() + s.Cooldown * 0.95
	player:SetAttribute("WeaponSkillReady", workspace:GetServerTimeNow() + s.Cooldown)
	local origin = hrp.Position
	if kind == "Staff" then
		for _, a in teamOf(t) do
			heal(a, maxHpOf(a) * s.Heal)
		end
		emit({ "wskill", t.key, origin, kind, s.Radius })
		return
	end
	local centre = origin
	if kind == "Bow" then
		local u, dist = rayHit(origin, flat(aim), WEAPON.Bow.Range)
		centre = u and u.pos or origin + flat(aim) * 30
	end
	emit({ "wskill", t.key, centre, kind, s.Radius })
	local hit = enemiesNear(t, centre, s.Radius)
	for _, u in hit do
		damage(t, u, s.Mult, "None")
		if s.Stun then
			addEffect(u, { type = "stun", dur = s.Stun })
		end
	end
	if hit[1] then
		setFocus(t, hit[1])
	end
end

function Combat.dodge(player: Player)
	local t = tamerOf(player)
	if now() < (t.cd.dodge or 0) then
		return false
	end
	t.cd.dodge = now() + T.Tamer.DodgeCooldown * 0.9
	t.invulnUntil = now() + T.Tamer.DodgeTime
	emit({ "dodge", t.key })
	return true
end

function Combat.teamSkill(player: Player, slot: any)
	local u = typeof(slot) == "number" and teams[player] and teams[player][slot]
	if not u or not alive(u) then
		return false
	end
	if not u.target or not alive(u.target) then
		local hrp = hrpOf(player)
		u.target = hrp and nearestThreat(player, hrp.Position) or nil
		if not u.target and hrp then
			-- nearest wild monster within reach
			local best, bd = nil, 40
			for _, w in units do
				if w.side == "wild" and alive(w) then
					local d = (w.pos - hrp.Position).Magnitude
					if d < bd then
						best, bd = w, d
					end
				end
			end
			u.target = best
		end
	end
	local skill = Monsters.skills(u.sp, u.el)[3]
	if skill.Target ~= "none" and not u.target then
		return false
	end
	if cast(u, 3, true) then
		u.part:SetAttribute("CdB", workspace:GetServerTimeNow() + (u.cd[3] - now()))
		Quests.progress(player, "TeamSkill", 1)
		Story.event(player, "ult")
		return true
	end
	return false
end

function Combat.focus(player: Player, unitId: any)
	local u = typeof(unitId) == "string" and units[unitId]
	if u and u.side == "wild" and alive(u) then
		setFocus(tamerOf(player), u)
		for _, tu in teams[player] or {} do
			tu.target = u
		end
	end
end

----------------------------------------------------------------------------------------------
-- Loop

local acc = 0
local function step(dt: number)
	acc += dt
	local tick = 1 / CT.TickRate
	if acc < tick then
		return
	end
	dt = acc
	acc = 0
	for _, t in tamers do
		tickEffects(t, dt)
	end
	for _, u in units do
		if u.state ~= "dead" then
			tickEffects(u, dt)
			if u.state ~= "dead" then
				if u.side == "team" then
					updateTeamUnit(u, dt)
				else
					updateWildUnit(u, dt)
				end
			end
		end
	end
	for _, u in units do
		if u.state ~= "dead" and u.part.Parent then
			placePart(u)
			syncAttrs(u)
		end
	end
	for player, list in teams do
		for _, u in list do
			if u.part.Parent then
				u.part:SetAttribute("CdB", workspace:GetServerTimeNow() + math.max(0, u.cd[3] - now()))
			end
		end
	end
	if #events > 0 then
		remotes.Combat:FireAllClients(events)
		events = {}
	end
end

function Combat.init(r)
	remotes = r
	folder = Instance.new("Folder")
	folder.Name = "Units"
	folder.Parent = workspace
	for _, camp in World.Camps do
		Combat.spawnWild(camp)
	end
	RunService.Heartbeat:Connect(step)
	Players.PlayerRemoving:Connect(function(player)
		Combat.clearTeam(player)
		tamers[player] = nil
	end)
end

-- Debug helpers (Studio playtests)
Combat.debug = {
	units = units,
	teams = teams,
	tamerOf = tamerOf,
	damage = function(id, amount)
		local u = units[id]
		if u then
			u.hp -= amount
			if u.hp <= 0 then
				die(u)
			end
		end
	end,
}

return Combat

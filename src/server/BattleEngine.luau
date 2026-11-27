-- Turn-based 3v3 battle engine for the Arena. Pure and deterministic: the same seed, teams and
-- choices always give the same battle, so the server can replay or check it.
--
-- Turn order is a speed gauge: every tick each monster adds its speed; at 1000 it acts.
-- Skills are the open-world kits read in turns (one turn ~ 2 s): Signature every turn, skill
-- A and the ultimate B on cooldowns; burns, stuns, shields, buffs, debuffs, silence, slow,
-- taunt, lifesteal and cleanse all work. Damage uses the open-world formula.
--
--   local b = BattleEngine.new(seed, attackers, defenders)   -- teams: { {sp, el, lv, aw, sk} }
--   local u = BattleEngine.nextActor(b)                       -- nil when the battle is over
--   BattleEngine.act(b, u, skillIndex, targetUnit)            -- or BattleEngine.aiAct(b, u)
--   b.events (append-only log), b.over, b.winner ("A" | "B")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Monsters = require(Shared.Monsters)
local Runes = require(Shared.Runes)

local BattleEngine = {}

local GAUGE = 1000
local MAX_ACTIONS = 90 -- then the defenders win
local FATIGUE_AFTER = 30 -- sudden death: from here damage climbs and healing fades each action
local FATIGUE_STEP = 0.08

local function fatigue(b): number
	return 1 + math.max(0, b.actions - FATIGUE_AFTER) * FATIGUE_STEP
end
local MITIGATION = Config.Tuning.Combat.Mitigation

local function turnsOf(sec: number?): number
	return math.max(1, math.ceil((sec or 2) / 2))
end

local function emit(b, e)
	table.insert(b.events, e)
end

local function makeUnit(side: string, slot: number, spec)
	local st = Monsters.stats(spec.sp, spec.lv, spec.aw)
	if typeof(spec.bonus) == "table" then
		st = Runes.apply(st, spec.bonus)
	end
	local skills = Monsters.skills(spec.sp, spec.el)
	return {
		side = side,
		slot = slot,
		sp = spec.sp,
		el = spec.el,
		lv = spec.lv,
		aw = spec.aw == true,
		sk = spec.sk or { 1, 1, 1 },
		stats = st,
		hp = st.hp,
		maxHp = st.hp,
		shield = 0,
		gauge = 0,
		cd = { 0, 0, 0 },
		fx = {}, -- { type, stat?, pct?, turns }
		alive = true,
		skills = skills,
	}
end

function BattleEngine.new(seed: number, attackers, defenders)
	local b = { rng = Random.new(seed), seed = seed, units = { A = {}, B = {} }, events = {}, actions = 0, over = false, winner = nil :: string? }
	for i, spec in attackers do
		b.units.A[i] = makeUnit("A", i, spec)
	end
	for i, spec in defenders do
		b.units.B[i] = makeUnit("B", i, spec)
	end
	-- start cooldowns so ultimates aren't free on turn one
	for _, side in { "A", "B" } do
		for _, u in b.units[side] do
			u.cd[3] = 2
		end
	end
	return b
end

local function other(side: string): string
	return side == "A" and "B" or "A"
end

local function alive(b, side: string): { any }
	local out = {}
	for _, u in b.units[side] do
		if u.alive then
			table.insert(out, u)
		end
	end
	return out
end

local function fxValue(u, stat: string): number
	local v = 0
	for _, f in u.fx do
		if f.type == "buff" and f.stat == stat then
			v += f.pct
		elseif (f.type == "debuff" and f.stat == stat) or (f.type == "slow" and stat == "spd") then
			v -= f.pct
		end
	end
	return v
end

local function has(u, t: string): boolean
	for _, f in u.fx do
		if f.type == t then
			return true
		end
	end
	return false
end

local function speed(u): number
	return math.max(10, u.stats.spd * (1 + fxValue(u, "spd")))
end

-- Next unit to act (advances the gauges). nil once the battle is over.
function BattleEngine.nextActor(b)
	if b.over then
		return nil
	end
	for _ = 1, 10000 do
		local best = nil
		for _, side in { "A", "B" } do
			for _, u in b.units[side] do
				if u.alive and u.gauge >= GAUGE and (not best or u.gauge > best.gauge) then
					best = u
				end
			end
		end
		if best then
			best.gauge -= GAUGE
			return best
		end
		for _, side in { "A", "B" } do
			for _, u in b.units[side] do
				if u.alive then
					u.gauge += speed(u)
				end
			end
		end
	end
	return nil
end

local function checkEnd(b)
	if b.over then
		return
	end
	if #alive(b, "B") == 0 then
		b.over, b.winner = true, "A"
	elseif #alive(b, "A") == 0 then
		b.over, b.winner = true, "B"
	elseif b.actions >= MAX_ACTIONS then
		b.over, b.winner = true, "B"
	end
	if b.over then
		emit(b, { "end", b.winner })
	end
end

local function faint(b, u)
	if u.alive and u.hp <= 0 then
		u.hp = 0
		u.alive = false
		u.fx = {}
		emit(b, { "faint", u.side, u.slot })
	end
end

local function heal(b, u, amount: number)
	if not u.alive then
		return
	end
	local before = u.hp
	u.hp = math.min(u.maxHp, u.hp + math.floor(amount / fatigue(b)))
	if u.hp > before then
		emit(b, { "heal", u.side, u.slot, u.hp - before, u.hp })
	end
end

local function hit(b, src, dst, mult: number): number
	if not dst.alive then
		return 0
	end
	local atk = src.stats.atk * (1 + fxValue(src, "atk"))
	local def = math.max(0, dst.stats.def * (1 + fxValue(dst, "def")))
	local adv = Config.advantage(src.el, dst.el)
	local crit = b.rng:NextNumber() < (src.stats.crit or 0.1)
	local amount = mult * atk * (MITIGATION / (MITIGATION + def)) * adv * (crit and (src.stats.critDmg or 1.5) or 1) * (0.95 + b.rng:NextNumber() * 0.1) * fatigue(b)
	amount = math.max(1, math.floor(amount))
	local absorbed = math.min(dst.shield, amount)
	dst.shield -= absorbed
	dst.hp -= amount - absorbed
	emit(b, { "hit", dst.side, dst.slot, amount, crit, adv, math.max(0, dst.hp), dst.shield })
	local ls = fxValue(src, "lifesteal")
	if ls > 0 then
		heal(b, src, (amount - absorbed) * ls)
	end
	faint(b, dst)
	return amount - absorbed
end

local function addFx(b, u, f)
	if not u.alive then
		return
	end
	-- refresh instead of stacking the same effect twice
	for i, g in u.fx do
		if g.type == f.type and g.stat == f.stat then
			table.remove(u.fx, i)
			break
		end
	end
	table.insert(u.fx, f)
	emit(b, { "fx", u.side, u.slot, f.type, f.stat })
end

local function allyTargets(b, caster, to: string?): { any }
	local team = alive(b, caster.side)
	if to == "self" then
		return { caster }
	elseif to == "lowest" then
		table.sort(team, function(x, y)
			return x.hp / x.maxHp < y.hp / y.maxHp
		end)
		return { team[1] }
	end
	return team
end

-- Runs one action. idx 1..3, target = an enemy unit (needed for "enemy"/"aoe" skills).
function BattleEngine.act(b, u, idx: number, target)
	if b.over or not u.alive then
		return
	end
	b.actions += 1
	if b.actions == FATIGUE_AFTER + 1 then
		emit(b, { "fatigue" })
	end
	-- start of turn: effects tick
	for i = #u.fx, 1, -1 do
		local f = u.fx[i]
		if f.type == "burn" then
			local d = math.max(1, math.floor(u.maxHp * f.pct))
			u.hp -= d
			emit(b, { "dot", u.side, u.slot, d, math.max(0, u.hp) })
		end
	end
	faint(b, u)
	if not u.alive then
		checkEnd(b)
		return
	end
	for i = 1, 3 do
		u.cd[i] = math.max(0, u.cd[i] - 1)
	end
	local stunned = has(u, "stun")
	for i = #u.fx, 1, -1 do
		local f = u.fx[i]
		f.turns -= 1
		if f.turns <= 0 then
			table.remove(u.fx, i)
		end
	end
	if stunned then
		emit(b, { "stunned", u.side, u.slot })
		checkEnd(b)
		return
	end
	if has(u, "silence") then
		idx = 1
	end
	if u.cd[idx] > 0 then
		idx = 1
	end
	local skill = u.skills[idx]
	local power = Monsters.skillPower(u.sk[idx] or 1)
	-- taunt: single-target skills must hit the taunting enemy
	local foes = alive(b, other(u.side))
	if #foes == 0 then
		checkEnd(b)
		return
	end
	local taunter = nil
	for _, f in foes do
		if has(f, "taunt") then
			taunter = f
		end
	end
	if not target or not target.alive or target.side == u.side then
		target = foes[1]
	end
	if taunter and skill.Target == "enemy" then
		target = taunter
	end
	emit(b, { "skill", u.side, u.slot, idx, skill.Name, target and target.side, target and target.slot })
	if idx > 1 then
		u.cd[idx] = skill.Turns + (idx == 3 and 2 or 0)
	end
	local hitList = {}
	if skill.Mult > 0 then
		if skill.Target == "aoe" then
			hitList = foes
		elseif skill.Target == "enemy" then
			hitList = { target }
		end
		for _, d in hitList do
			for _ = 1, skill.Hits or 1 do
				local dealt = hit(b, u, d, skill.Mult * power)
				for _, e in skill.Effects do
					if e.type == "lifesteal" and dealt > 0 then
						heal(b, u, dealt * e.pct)
					end
				end
			end
		end
	end
	for _, e in skill.Effects do
		local t = e.type
		if t == "heal" then
			for _, a in allyTargets(b, u, e.to) do
				heal(b, a, a.maxHp * e.pct * power)
			end
		elseif t == "shield" then
			for _, a in allyTargets(b, u, e.to) do
				a.shield += math.floor(a.maxHp * e.pct * power)
				emit(b, { "shield", a.side, a.slot, a.shield })
			end
		elseif t == "cleanse" then
			for _, a in allyTargets(b, u, e.to) do
				for i = #a.fx, 1, -1 do
					local f = a.fx[i]
					if f.type == "burn" or f.type == "stun" or f.type == "silence" or f.type == "slow" or f.type == "debuff" then
						table.remove(a.fx, i)
					end
				end
				emit(b, { "fx", a.side, a.slot, "cleanse" })
			end
		elseif t == "buff" then
			for _, a in allyTargets(b, u, e.to) do
				addFx(b, a, { type = "buff", stat = e.stat, pct = e.pct, turns = turnsOf(e.dur) })
			end
		elseif t == "taunt" then
			addFx(b, u, { type = "taunt", turns = turnsOf(e.dur) })
		elseif t ~= "lifesteal" then
			-- burn, stun, slow, debuff, silence land on the enemies that were hit
			for _, d in hitList do
				if d.alive and (e.chance == nil or b.rng:NextNumber() < e.chance) then
					if t == "burn" then
						addFx(b, d, { type = "burn", pct = e.pct * 2, turns = turnsOf(e.dur) })
					elseif t == "stun" then
						addFx(b, d, { type = "stun", turns = 1 })
					elseif t == "slow" then
						addFx(b, d, { type = "slow", pct = e.pct, turns = turnsOf(e.dur) })
					elseif t == "debuff" then
						addFx(b, d, { type = "debuff", stat = e.stat, pct = e.pct, turns = turnsOf(e.dur) })
					elseif t == "silence" then
						addFx(b, d, { type = "silence", turns = turnsOf(e.dur) })
					end
				end
			end
		end
	end
	checkEnd(b)
end

-- Which skills a unit may use now, and the forced target if a taunt is up.
function BattleEngine.options(b, u): ({ boolean }, any?)
	local ok = { true, u.cd[2] <= 0 and not has(u, "silence"), u.cd[3] <= 0 and not has(u, "silence") }
	local taunter = nil
	for _, f in alive(b, other(u.side)) do
		if has(f, "taunt") then
			taunter = f
		end
	end
	return ok, taunter
end

-- Simple AI: ultimate if ready, else skill A, else Signature; damage goes to the enemy it
-- hurts most (element advantage, then lowest HP); heals wait until someone is hurt.
function BattleEngine.aiChoice(b, u): (number, any)
	local ok = BattleEngine.options(b, u)
	local foes = alive(b, other(u.side))
	table.sort(foes, function(x, y)
		local ax, ay = Config.advantage(u.el, x.el), Config.advantage(u.el, y.el)
		if ax ~= ay then
			return ax > ay
		end
		return x.hp < y.hp
	end)
	local hurt = false
	for _, a in alive(b, u.side) do
		if a.hp < a.maxHp * 0.7 then
			hurt = true
		end
	end
	for _, i in { 3, 2 } do
		if ok[i] then
			local s = u.skills[i]
			local healsOnly = s.Mult == 0 and #s.Effects > 0 and s.Effects[1].type == "heal"
			if not healsOnly or hurt then
				return i, foes[1]
			end
		end
	end
	return 1, foes[1]
end

function BattleEngine.aiAct(b, u)
	local i, t = BattleEngine.aiChoice(b, u)
	BattleEngine.act(b, u, i, t)
end

-- Compact state for the client.
function BattleEngine.snapshot(b)
	local out = { A = {}, B = {}, over = b.over, winner = b.winner }
	for _, side in { "A", "B" } do
		for i, u in b.units[side] do
			local fx = {}
			for _, f in u.fx do
				table.insert(fx, f.type .. (f.stat and (":" .. f.stat) or ""))
			end
			out[side][i] = { sp = u.sp, el = u.el, lv = u.lv, aw = u.aw, hp = u.hp, maxHp = u.maxHp, shield = u.shield, cd = table.clone(u.cd), fx = fx, alive = u.alive }
		end
	end
	return out
end

-- Runs the whole battle with both sides on AI (for bots and "Auto").
function BattleEngine.runToEnd(b)
	for _ = 1, MAX_ACTIONS + 5 do
		local u = BattleEngine.nextActor(b)
		if not u then
			break
		end
		BattleEngine.aiAct(b, u)
	end
end

return BattleEngine

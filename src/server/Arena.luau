-- The Arena: async turn-based 3v3 PvP (design doc §9).
--
-- Every Tamer has an Arena record in its own DataStore (defence team snapshot, rating,
-- wins/losses, recent defences), separate from the session-locked profile so any server
-- can update a defender after a fight. Ratings also go into an OrderedDataStore for
-- matchmaking and the Top Tamers board. When there aren't enough real opponents near your
-- rating, rival bot Tamers fill in.
--
-- A fight runs on BattleEngine on the server. The player picks each of their monsters'
-- skill and target (or Auto); the defending team is AI. Profile: p.arena = { tokens, day,
-- attacks } (daily attempts) — rating lives in the Arena record.
local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Monsters = require(Shared.Monsters)
local PlayerData = require(script.Parent.PlayerData)
local Persistence = require(script.Parent.Persistence)
local BattleEngine = require(script.Parent.BattleEngine)
local Story = require(script.Parent.Story)

local A = Config.Arena
local Arena = {}
local rng = Random.new()

local SUFFIX = "_v1" .. (RunService:IsStudio() and "_Studio" or "")
local recordStore: DataStore? = nil
local ratingStore: OrderedDataStore? = nil

local records: { [number]: any } = {} -- my record, cached for the session
local opponents: { [Player]: { list: { any }, at: number } } = {}
local battles: { [Player]: any } = {}

local BOT_NAMES = { "Rowan", "Juniper", "Quill", "Bramble", "Sorrel", "Tamsin", "Fennick", "Marigold", "Wren", "Ashby", "Clover", "Hollis", "Linden", "Odessa", "Perrin", "Sable" }

----------------------------------------------------------------------------------------------
-- records

local function teamSnapshot(p, uids: { string }?): { any }
	local list = {}
	for _, u in uids or p.team do
		local m = u ~= "" and p.monsters[u]
		if m then
			table.insert(list, { sp = m.sp, el = m.el, lv = m.lv, aw = m.aw, sk = table.clone(m.sk) })
		end
	end
	return list
end

local function teamPower(team): number
	local n = 0
	for _, m in team do
		n += Monsters.power(m.sp, m.lv, m.aw)
	end
	return n
end

local function newRecord(player: Player, p)
	local def = teamSnapshot(p)
	return { name = player.DisplayName, rating = A.StartRating, wins = 0, losses = 0, def = def, power = teamPower(def), log = {} }
end

local function loadRecord(player: Player)
	local cached = records[player.UserId]
	if cached then
		return cached
	end
	local p = PlayerData.get(player)
	local rec = nil
	if recordStore then
		local ok, data = pcall(function()
			return (recordStore :: DataStore):GetAsync("u_" .. player.UserId)
		end)
		if ok and typeof(data) == "table" then
			rec = data
		end
	end
	local fresh = rec == nil
	rec = rec or newRecord(player, p)
	rec.name = player.DisplayName
	if fresh then
		-- join the rating board right away so other Tamers can find this team
		local snap = rec
		task.spawn(function()
			saveRecord(player.UserId, function(old)
				return typeof(old) == "table" and old or snap
			end)
			saveRating(player.UserId, snap.rating)
		end)
	end
	rec.log = rec.log or {}
	records[player.UserId] = rec
	return rec
end

local function saveRecord(userId: number, update: (any) -> any)
	if not recordStore then
		return
	end
	pcall(function()
		(recordStore :: DataStore):UpdateAsync("u_" .. userId, function(old)
			return update(old)
		end)
	end)
end

local function saveRating(userId: number, rating: number)
	if not ratingStore then
		return
	end
	pcall(function()
		(ratingStore :: OrderedDataStore):SetAsync(tostring(userId), math.max(0, math.floor(rating)))
	end)
end

----------------------------------------------------------------------------------------------
-- opponents

local function botTeam(seed: number, rating: number): ({ any }, string)
	local r = Random.new(seed)
	-- harder bots at higher ratings
	local lv = math.clamp(math.floor(6 + (rating - 800) / 25), 4, 40)
	local maxStars = rating < 950 and 3 or rating < 1150 and 4 or 5
	local team = {}
	for i = 1, 3 do
		local stars = r:NextInteger(math.max(1, maxStars - 2), maxStars)
		local pool = Monsters.byStars(stars)
		local sp = pool[r:NextInteger(1, #pool)]
		local el = ({ "Fire", "Water", "Wind" })[r:NextInteger(1, 3)]
		table.insert(team, { sp = sp, el = el, lv = math.clamp(lv + r:NextInteger(-2, 2), 1, 40), aw = lv > 22, sk = { 1, 1, 1 } })
		local _ = i
	end
	return team, BOT_NAMES[r:NextInteger(1, #BOT_NAMES)] .. " (rival)"
end

local function findOpponents(player: Player, rec): { any }
	local list = {}
	local seen = { [player.UserId] = true }
	if ratingStore then
		local ok, page = pcall(function()
			return (ratingStore :: OrderedDataStore):GetSortedAsync(false, 40, math.max(0, rec.rating - A.MatchRange), rec.rating + A.MatchRange):GetCurrentPage()
		end)
		if ok and page then
			local candidates = {}
			for _, e in page do
				local id = tonumber(e.key)
				if id and not seen[id] then
					table.insert(candidates, { id = id, rating = e.value })
				end
			end
			-- shuffle, then load up to 3 defence teams
			for i = #candidates, 2, -1 do
				local j = rng:NextInteger(1, i)
				candidates[i], candidates[j] = candidates[j], candidates[i]
			end
			for _, c in candidates do
				if #list >= 3 then
					break
				end
				local ok2, data = pcall(function()
					return (recordStore :: DataStore):GetAsync("u_" .. c.id)
				end)
				if ok2 and typeof(data) == "table" and typeof(data.def) == "table" and #data.def > 0 then
					seen[c.id] = true
					table.insert(list, { id = c.id, name = data.name or ("Tamer " .. c.id), rating = data.rating or c.rating, power = teamPower(data.def), team = data.def, bot = false })
				end
			end
		end
	end
	-- rival bots fill the rest
	local slot = 0
	while #list < 3 do
		slot += 1
		local seed = (player.UserId * 31 + os.time() // 300 + slot * 977) % 2147483647
		local r = rec.rating + rng:NextInteger(-A.MatchRange // 2, A.MatchRange // 2)
		local team, name = botTeam(seed, r)
		table.insert(list, { id = -slot, name = name, rating = r, power = teamPower(team), team = team, bot = true })
	end
	table.sort(list, function(a, b)
		return a.rating < b.rating
	end)
	return list
end

----------------------------------------------------------------------------------------------
-- daily attempts and tokens

local function arenaState(p)
	local today = Config.today()
	if p.arena.day ~= today then
		p.arena.day = today
		p.arena.attacks = 0
	end
	return p.arena
end

local function unlocked(p): boolean
	return p.bosses[A.UnlockBoss] == true
end

local function publicTeam(team)
	local out = {}
	for _, m in team do
		table.insert(out, { sp = m.sp, el = m.el, lv = m.lv, aw = m.aw })
	end
	return out
end

function Arena.info(player: Player)
	local p = PlayerData.get(player)
	if not p then
		return false, "No profile"
	end
	if not unlocked(p) then
		return true, "ok", { locked = true }
	end
	local rec = loadRecord(player)
	local st = arenaState(p)
	local cache = opponents[player]
	if not cache or os.clock() - cache.at > A.RefreshSeconds then
		cache = { list = findOpponents(player, rec), at = os.clock() }
		opponents[player] = cache
	end
	local opps = {}
	for i, o in cache.list do
		table.insert(opps, { i = i, name = o.name, rating = o.rating, power = o.power, team = publicTeam(o.team), bot = o.bot })
	end
	return true, "ok", {
		rating = rec.rating,
		wins = rec.wins,
		losses = rec.losses,
		def = publicTeam(rec.def),
		defPower = teamPower(rec.def),
		log = rec.log,
		tokens = p.arena.tokens,
		attacksLeft = math.max(0, A.DailyAttacks - st.attacks),
		opponents = opps,
		storeOnline = recordStore ~= nil,
	}
end

function Arena.setDefence(player: Player, uids: any)
	local p = PlayerData.get(player)
	if not p or not unlocked(p) then
		return false, "The Arena opens after the Meadow Guardian"
	end
	if typeof(uids) ~= "table" or #uids < 1 or #uids > 3 then
		return false, "Pick 1 to 3 monsters"
	end
	local seen = {}
	for _, u in uids do
		if typeof(u) ~= "string" or not p.monsters[u] or seen[u] then
			return false, "Bad monster list"
		end
		seen[u] = true
	end
	local rec = loadRecord(player)
	rec.def = teamSnapshot(p, uids)
	rec.power = teamPower(rec.def)
	local snapshot = { name = player.DisplayName, def = rec.def, power = rec.power }
	saveRecord(player.UserId, function(old)
		local r = typeof(old) == "table" and old or { rating = A.StartRating, wins = 0, losses = 0, log = {} }
		r.name, r.def, r.power = snapshot.name, snapshot.def, snapshot.power
		return r
	end)
	saveRating(player.UserId, rec.rating)
	return true, "Defence team saved"
end

----------------------------------------------------------------------------------------------
-- fighting

local function teamUnits(b, side)
	return b.units[side]
end

-- Runs AI turns until it's one of the attacker's monsters' turn (or the end).
local function advance(state)
	local b = state.b
	while not b.over do
		local u = BattleEngine.nextActor(b)
		if not u then
			break
		end
		if u.side == "A" and not state.auto then
			state.pending = u
			return
		end
		BattleEngine.aiAct(b, u)
	end
	state.pending = nil
end

local function pendingInfo(state)
	local u = state.pending
	if not u then
		return nil
	end
	local ok, taunter = BattleEngine.options(state.b, u)
	return { slot = u.slot, ok = ok, taunt = taunter and taunter.slot or nil, cd = table.clone(u.cd) }
end

local function finish(player: Player, state)
	local p = PlayerData.get(player)
	local b = state.b
	local won = b.winner == "A"
	local rec = loadRecord(player)
	local opp = state.opp
	-- Elo
	local expected = 1 / (1 + 10 ^ ((opp.rating - rec.rating) / 400))
	local delta = math.floor(A.K * ((won and 1 or 0) - expected) + 0.5)
	if won and delta < 1 then
		delta = 1
	end
	rec.rating = math.max(0, rec.rating + delta)
	if won then
		rec.wins += 1
	else
		rec.losses += 1
	end
	local tokens = won and A.WinTokens or A.LossTokens
	if won then
		Story.event(player, "arena")
	end
	local coins = won and A.WinCoins or 0
	if p then
		p.arena.tokens += tokens
		p.coins += coins
		PlayerData.push(player)
		PlayerData.saveSoon(player)
	end
	local myRating, myWins, myLosses = rec.rating, rec.wins, rec.losses
	saveRecord(player.UserId, function(old)
		local r = typeof(old) == "table" and old or { log = {} }
		r.name = player.DisplayName
		r.rating, r.wins, r.losses = myRating, myWins, myLosses
		r.def = r.def or rec.def
		r.power = r.power or rec.power
		r.log = r.log or {}
		return r
	end)
	saveRating(player.UserId, myRating)
	if not opp.bot then
		-- the defender's side of it
		local name = player.DisplayName
		local oppDelta = -delta
		saveRecord(opp.id, function(old)
			if typeof(old) ~= "table" then
				return nil
			end
			old.rating = math.max(0, (old.rating or A.StartRating) + oppDelta)
			if won then
				old.losses = (old.losses or 0) + 1
			else
				old.wins = (old.wins or 0) + 1
			end
			old.log = old.log or {}
			table.insert(old.log, 1, { by = name, won = not won, delta = oppDelta, t = os.time() })
			while #old.log > 6 do
				table.remove(old.log)
			end
			task.defer(saveRating, opp.id, old.rating)
			return old
		end)
	end
	opponents[player] = nil -- fresh opponents next time
	battles[player] = nil
	return { won = won, delta = delta, rating = myRating, tokens = tokens, coins = coins }
end

local function response(player: Player, state, fromEvent: number)
	local b = state.b
	local events = {}
	for i = fromEvent, #b.events do
		table.insert(events, b.events[i])
	end
	local out = { events = events, snap = BattleEngine.snapshot(b), pending = pendingInfo(state) }
	if b.over then
		out.result = finish(player, state)
	end
	return out
end

function Arena.fight(player: Player, index: any)
	local p = PlayerData.get(player)
	if not p or not unlocked(p) then
		return false, "The Arena opens after the Meadow Guardian"
	end
	if battles[player] then
		battles[player] = nil
	end
	local st = arenaState(p)
	if st.attacks >= A.DailyAttacks then
		return false, "No Arena fights left today. They refill at 00:00 UTC"
	end
	local cache = opponents[player]
	local opp = cache and typeof(index) == "number" and cache.list[index]
	if not opp then
		return false, "Pick an opponent"
	end
	local mine = teamSnapshot(p)
	if #mine == 0 then
		return false, "You need a team first"
	end
	st.attacks += 1
	PlayerData.push(player)
	local seed = rng:NextInteger(1, 2 ^ 30)
	local b = BattleEngine.new(seed, mine, opp.team)
	local state = { b = b, opp = opp, pending = nil, auto = false }
	battles[player] = state
	advance(state)
	local res = response(player, state, 1)
	res.start = { mine = publicTeam(mine), theirs = publicTeam(opp.team), name = opp.name, rating = opp.rating }
	return true, "ok", res
end

function Arena.act(player: Player, skill: any, target: any)
	local state = battles[player]
	if not state or not state.pending then
		return false, "No fight in progress"
	end
	local b = state.b
	local from = #b.events + 1
	if skill == "auto" then
		state.auto = true
		local u = state.pending
		state.pending = nil
		BattleEngine.aiAct(b, u)
		advance(state)
		return true, "ok", response(player, state, from)
	end
	if typeof(skill) ~= "number" or skill < 1 or skill > 3 then
		return false, "Bad skill"
	end
	local u = state.pending
	local ok = BattleEngine.options(b, u)
	if not ok[skill] then
		skill = 1
	end
	local t = typeof(target) == "number" and teamUnits(b, "B")[target] or nil
	state.pending = nil
	BattleEngine.act(b, u, skill, t)
	advance(state)
	return true, "ok", response(player, state, from)
end

function Arena.forfeit(player: Player)
	local state = battles[player]
	if not state then
		return false, "No fight in progress"
	end
	state.b.over, state.b.winner = true, "B"
	table.insert(state.b.events, { "end", "B" })
	return true, "ok", response(player, state, #state.b.events)
end

function Arena.shop(player: Player, item: any, el: any)
	local p = PlayerData.get(player)
	if not p then
		return false, "No profile"
	end
	local it = typeof(item) == "string" and A.Shop[item]
	if not it then
		return false, "Unknown item"
	end
	if p.arena.tokens < it.cost then
		return false, "Need " .. (it.cost - p.arena.tokens) .. " more tokens"
	end
	if it.essence then
		if typeof(el) ~= "string" or not Config.ElementInfo[el] then
			return false, "Pick an element"
		end
		p.essence[el] = (p.essence[el] or 0) + it.essence
	end
	p.arena.tokens -= it.cost
	p.scrolls.Regular += it.scrolls or 0
	p.scrolls.Legendary += it.legendary or 0
	PlayerData.push(player)
	PlayerData.saveSoon(player)
	return true, "Bought " .. it.name
end

function Arena.handle(player: Player, action: any, a: any, b: any)
	if action == "info" then
		return Arena.info(player)
	elseif action == "defence" then
		return Arena.setDefence(player, a)
	elseif action == "fight" then
		return Arena.fight(player, a)
	elseif action == "act" then
		return Arena.act(player, a, b)
	elseif action == "forfeit" then
		return Arena.forfeit(player)
	elseif action == "shop" then
		return Arena.shop(player, a, b)
	end
	return false, "Unknown action"
end

function Arena.init()
	if Persistence.available then
		local ok, s = pcall(function()
			return DataStoreService:GetDataStore("Wildbound_ArenaTeams" .. SUFFIX)
		end)
		if ok then
			recordStore = s
		end
		local ok2, o = pcall(function()
			return DataStoreService:GetOrderedDataStore("Wildbound_Arena" .. SUFFIX)
		end)
		if ok2 then
			ratingStore = o
		end
	end
	Players.PlayerRemoving:Connect(function(player)
		records[player.UserId] = nil
		opponents[player] = nil
		battles[player] = nil
	end)
end

return Arena

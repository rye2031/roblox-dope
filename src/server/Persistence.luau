-- Saves player progress in a DataStore with a session lock, so a profile is only ever written by
-- the one server that owns it (no rollback or duplication when a player hops servers).
--
-- Record shape (key "u_<UserId>"):
--   { v = schema, data = <profile>, lock = { job = JobId, t = os.time() }?, saved = os.time() }
--
-- Failure policy: if a profile can't be loaded, the session runs on defaults and is NEVER saved,
-- so a DataStore outage can't overwrite good data with an empty profile.
local DataStoreService = game:GetService("DataStoreService")
local RunService = game:GetService("RunService")

local Persistence = {}

local SCHEMA = 1
-- Studio sessions use their own store so test runs never touch live players' saves.
local STORE_NAME = "Wildbound_v1" .. (RunService:IsStudio() and "_Studio" or "")
local LOCK_TIMEOUT = 300 -- seconds; a lock older than this is treated as abandoned (crashed server)
local LOAD_ATTEMPTS = 4
local LOAD_RETRY_WAITS = { 2, 3, 4 } -- seconds; a server releasing on leave finishes in ~1 s
local SAVE_ATTEMPTS = 3
local MIN_WRITE_GAP = 7 -- DataStore allows one write per key every 6 s

Persistence.AUTOSAVE_INTERVAL = 60

local store: DataStore? = nil
Persistence.available = false
Persistence.reason = "not initialised"

local lastWrite: { [number]: number } = {}

local function jobId(): string
	-- JobId is empty in Studio; give Studio a stable-per-session id instead.
	if game.JobId ~= "" then
		return game.JobId
	end
	Persistence._studioJob = Persistence._studioJob or ("studio-" .. tostring(math.random(1, 1e9)))
	return Persistence._studioJob
end
Persistence.jobId = jobId

function Persistence.key(userId: number): string
	return "u_" .. tostring(userId)
end

-- Probe once at startup. In Studio without "Enable Studio Access to API Services" (or in an
-- unpublished place) DataStores throw; we fall back to session-only progress.
function Persistence.init(): boolean
	local ok, err = pcall(function()
		store = DataStoreService:GetDataStore(STORE_NAME)
		return (store :: DataStore):GetAsync("__probe")
	end)
	Persistence.available = ok
	Persistence.reason = ok and "ok" or tostring(err)
	if not ok then
		store = nil
		warn("[Persistence] DataStores unavailable, progress will not save: " .. Persistence.reason)
	end
	return ok
end

local function waitForWriteSlot(userId: number)
	local last = lastWrite[userId]
	if last then
		local gap = os.clock() - last
		if gap < MIN_WRITE_GAP then
			task.wait(MIN_WRITE_GAP - gap)
		end
	end
	lastWrite[userId] = os.clock()
end

-- Claims the session lock and returns (ok, data). data is nil for a brand-new player.
-- ok == false means the profile could not be loaded and this session must not save.
function Persistence.load(userId: number): (boolean, any)
	if not store then
		return false, nil
	end
	local key = Persistence.key(userId)
	local me = jobId()
	for attempt = 1, LOAD_ATTEMPTS do
		local blockedBy = nil
		if attempt == 1 then
			waitForWriteSlot(userId) -- an aborted UpdateAsync writes nothing, so retries skip the gap
		end
		local ok, result = pcall(function()
			return (store :: DataStore):UpdateAsync(key, function(old)
				old = old or {}
				local lock = old.lock
				if lock and lock.job ~= me and os.time() - (lock.t or 0) < LOCK_TIMEOUT and attempt < LOAD_ATTEMPTS then
					-- Another server still owns this profile (usually it is saving on leave).
					blockedBy = lock.job
					return nil
				end
				old.lock = { job = me, t = os.time() }
				old.v = SCHEMA
				return old
			end)
		end)
		if ok and not blockedBy then
			return true, result and result.data or nil
		end
		if not ok then
			warn(`[Persistence] load {key} attempt {attempt} failed: {result}`)
		end
		if attempt < LOAD_ATTEMPTS then
			task.wait(LOAD_RETRY_WAITS[attempt] or 4)
		end
	end
	return false, nil
end

-- Writes the profile. release = true also drops the session lock (player leaving / shutdown).
-- Returns true on success. Refuses to write if another server has taken the lock.
function Persistence.save(userId: number, data: any, release: boolean?): boolean
	if not store then
		return false
	end
	local key = Persistence.key(userId)
	local me = jobId()
	for attempt = 1, SAVE_ATTEMPTS do
		local stolen = false
		waitForWriteSlot(userId)
		local ok, err = pcall(function()
			(store :: DataStore):UpdateAsync(key, function(old)
				old = old or {}
				if old.lock and old.lock.job ~= me then
					stolen = true
					return nil
				end
				old.v = SCHEMA
				old.data = data
				old.saved = os.time()
				old.lock = if release then nil else { job = me, t = os.time() }
				return old
			end)
		end)
		if ok then
			if stolen then
				warn(`[Persistence] {key} is locked by another server; not saving here`)
				return false
			end
			if release then
				lastWrite[userId] = nil
			end
			return true
		end
		warn(`[Persistence] save {key} attempt {attempt} failed: {err}`)
		task.wait(2 * attempt)
	end
	return false
end

-- Drops our lock without touching data (used when a player leaves before their load finished
-- or after a failed load).
function Persistence.release(userId: number)
	if not store then
		return
	end
	local me = jobId()
	pcall(function()
		(store :: DataStore):UpdateAsync(Persistence.key(userId), function(old)
			if not old or not old.lock or old.lock.job ~= me then
				return nil
			end
			old.lock = nil
			return old
		end)
	end)
	lastWrite[userId] = nil
end

-- Raw read for tests and debugging.
function Persistence.peek(userId: number): any
	if not store then
		return nil
	end
	local ok, result = pcall(function()
		return (store :: DataStore):GetAsync(Persistence.key(userId))
	end)
	return ok and result or nil
end

-- Test hook: plant a record (e.g. a foreign lock) directly.
function Persistence.poke(userId: number, record: any)
	if store then
		(store :: DataStore):SetAsync(Persistence.key(userId), record)
	end
end

return Persistence

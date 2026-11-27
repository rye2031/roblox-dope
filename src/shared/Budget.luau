-- Frame budget for heavy client work (texture decodes, recolours, portraits).
-- Only one heavy job runs at a time (`Budget.run`), and it yields to the next frame whenever it
-- has used its slice (`Budget.check` inside long loops), so loading monsters or opening the
-- Index never freezes a frame. Re-entrant: a job that calls another job keeps the slot.
local RunService = game:GetService("RunService")

local Budget = {}

local SLICE = 0.004 -- seconds of heavy work per frame
local owner: thread? = nil
local depth = 0
local sliceStart = os.clock()

local function canYield(): boolean
	return coroutine.isyieldable()
end

-- Call every few hundred iterations inside a heavy loop.
function Budget.check()
	if os.clock() - sliceStart >= SLICE and canYield() then
		RunService.Heartbeat:Wait()
		sliceStart = os.clock()
	end
end

-- Runs fn while holding the heavy-work slot; waits its turn behind other jobs.
function Budget.run<T...>(fn: () -> T...): T...
	local me = coroutine.running()
	if owner == me then
		depth += 1
		local r = table.pack(pcall(fn))
		depth -= 1
		if not r[1] then
			error(r[2], 0)
		end
		return table.unpack(r, 2, r.n)
	end
	while owner ~= nil and canYield() do
		RunService.Heartbeat:Wait()
	end
	owner, depth = me, 1
	sliceStart = os.clock()
	local r = table.pack(pcall(fn))
	owner, depth = nil, 0
	if not r[1] then
		error(r[2], 0)
	end
	return table.unpack(r, 2, r.n)
end

return Budget

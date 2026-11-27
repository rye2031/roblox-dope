-- Tamer's Journey (main story). p.story = { i = current step index, n = progress on it }.
-- Events from other systems (kills, summons, feeds, campfires, talks...) advance the current
-- step; state checks (team size, levels, bosses beaten...) let returning players skip what
-- they've already done. Finishing a step pays its reward and tells the client.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local StoryData = require(ReplicatedStorage.Shared.StoryData)
local PlayerData = require(script.Parent.PlayerData)

local Story = {}
local remote: RemoteEvent
local toast: RemoteEvent

local function stepOf(p)
	return StoryData.Steps[p.story.i]
end

local function count(t): number
	local n = 0
	for _ in t or {} do
		n += 1
	end
	return n
end

-- Steps that can be satisfied by the profile's current state (no event needed).
local function stateDone(player: Player, p, s): boolean
	local k = s.kind
	if k == "team" then
		local n = 0
		for _, uid in p.team do
			if uid ~= "" then
				n += 1
			end
		end
		return n >= s.n
	elseif k == "level" then
		for _, m in p.monsters do
			if m.lv >= s.n then
				return true
			end
		end
		return false
	elseif k == "boss" then
		return p.bosses[s.region] == true
	elseif k == "weapon" then
		return p.weapon.lv >= s.n
	elseif k == "awaken" then
		local n = 0
		for _, m in p.monsters do
			if m.aw then
				n += 1
			end
		end
		return n >= s.n
	elseif k == "index" then
		return count(p.index) >= s.n
	elseif k == "visit" then
		return player:GetAttribute("Region") == s.region
	elseif k == "campfire" then
		return p.campfires[s.region] == true
	elseif k == "summon" then
		return p.story.n >= s.n
	elseif k == "discover" then
		return p.found ~= nil and p.found[s.target] == true
	elseif k == "dungeon" then
		for key, n in (p.dungeon and p.dungeon.clears) or {} do
			if n > 0 and (s.target == nil or key:sub(1, #s.target + 1) == s.target .. ":") then
				return true
			end
		end
		return false
	end
	return false
end

local function grant(player: Player, p, s)
	local r = s.reward or {}
	p.coins += r.coins or 0
	p.scrolls.Regular += r.scrolls or 0
	p.scrolls.Legendary += r.legendary or 0
	local nextStep = StoryData.Steps[p.story.i + 1]
	remote:FireClient(player, { kind = "done", step = p.story.i, reward = StoryData.rewardText(r), chapterDone = not nextStep or nextStep.chapter ~= s.chapter, chapter = s.chapter })
end

-- Finishing the whole story grants the one Eclipse Scroll (never again, even if more
-- chapters are added later).
local function finishCheck(player: Player, p)
	local gate = #StoryData.Steps
	for i, st in StoryData.Steps do
		if st.id == StoryData.EclipseAfter then
			gate = i
		end
	end
	if p.story.i > gate and not p.tutorial.eclipseScroll then
		p.tutorial.eclipseScroll = true
		p.scrolls.Eclipse = 1
		remote:FireClient(player, { kind = "eclipse" })
		PlayerData.saveSoon(player)
	end
end
Story.finishCheck = finishCheck

-- Completes the current step if it's met, repeatedly (returning players skip ahead).
function Story.check(player: Player)
	local p = PlayerData.get(player)
	if not p then
		return
	end
	local advanced = false
	for _ = 1, #StoryData.Steps do
		local s = stepOf(p)
		if not s then
			break
		end
		local met = stateDone(player, p, s) or (s.n ~= nil and s.kind ~= "team" and s.kind ~= "level" and s.kind ~= "weapon" and s.kind ~= "awaken" and s.kind ~= "index" and p.story.n >= s.n)
		if not met then
			break
		end
		grant(player, p, s)
		p.story.i += 1
		p.story.n = 0
		advanced = true
	end
	if advanced then
		finishCheck(player, p)
		PlayerData.push(player)
		PlayerData.saveSoon(player)
	end
end

-- Something happened. data: { region = string?, n = number? }
function Story.event(player: Player, kind: string, data: { [string]: any }?)
	local p = PlayerData.get(player)
	if not p then
		return
	end
	local d = data or {}
	local s = stepOf(p)
	if kind == "campfire" and d.region then
		p.campfires[d.region] = true
	end
	if not s then
		return
	end
	local hit = false
	if s.kind == kind then
		if kind == "defeat" then
			hit = s.region == nil or d.region == s.region
		elseif kind == "visit" or kind == "campfire" or kind == "boss" then
			hit = d.region == s.region
		elseif kind == "titan" or kind == "multi" or kind == "arena" then
			p.story.n = 1
			hit = true
		else
			hit = true
		end
		if hit and kind ~= "titan" and kind ~= "multi" and kind ~= "arena" and kind ~= "visit" and kind ~= "campfire" and kind ~= "boss" then
			p.story.n += d.n or 1
		end
	end
	if hit then
		if s.kind == "titan" or s.kind == "multi" or s.kind == "arena" then
			grant(player, p, s)
			p.story.i += 1
			p.story.n = 0
			finishCheck(player, p)
			PlayerData.push(player)
			PlayerData.saveSoon(player)
		end
		Story.check(player)
		if stepOf(p) == s then
			PlayerData.push(player) -- progress counter changed
		end
	end
end

-- A guide's prompt was used.
function Story.talk(player: Player, npc: string)
	local p = PlayerData.get(player)
	if not p then
		return
	end
	local s = stepOf(p)
	if s and s.kind == "talk" and s.npc == npc then
		remote:FireClient(player, { kind = "dialogue", npc = npc, lines = s.lines })
		grant(player, p, s)
		p.story.i += 1
		p.story.n = 0
		finishCheck(player, p)
		PlayerData.push(player)
		PlayerData.saveSoon(player)
		task.defer(Story.check, player)
		return
	end
	-- not this guide's turn: a hint about what to do now
	local line
	if not s then
		line = "You've done everything I can teach you. Go show the world what your team can do!"
	elseif s.hint then
		line = s.hint
	else
		line = "Your next step: " .. s.text .. "."
	end
	remote:FireClient(player, { kind = "dialogue", npc = npc, lines = { line } })
end

function Story.init(remotes)
	remote = remotes.Story
	toast = remotes.Toast
	local function hook(player: Player)
		player:GetAttributeChangedSignal("Region"):Connect(function()
			local r = player:GetAttribute("Region")
			if r then
				Story.event(player, "visit", { region = r })
			end
		end)
	end
	for _, pl in Players:GetPlayers() do
		hook(pl)
	end
	Players.PlayerAdded:Connect(hook)
	local _ = toast
end

return Story

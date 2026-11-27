-- Rebuilds Meshy models from src/shared/MeshData at runtime with EditableMesh + EditableImage,
-- so the prototype needs no uploaded assets. Each client builds its own templates (Editable
-- content does not replicate). Returns nil when a mesh is missing or the APIs are unavailable;
-- callers fall back to labelled placeholder parts.
local AssetService = game:GetService("AssetService")

local MeshLoader = {}

local MeshData = script.Parent:WaitForChild("MeshData", 5)

local B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local decodeMap = {}
for i = 1, 64 do
	decodeMap[string.byte(B64, i)] = i - 1
end

local Budget = require(script.Parent.Budget)

local function b64decode(s: string): buffer
	local len = #s
	local pad = 0
	if string.byte(s, len) == 61 then
		pad += 1
	end
	if string.byte(s, len - 1) == 61 then
		pad += 1
	end
	local outLen = (len // 4) * 3 - pad
	local out = buffer.create(outLen)
	local o = 0
	local step = 0
	for i = 1, len, 4 do
		step += 1
		if step % 2048 == 0 then
			Budget.check()
		end
		local a, b, c, d = string.byte(s, i, i + 3)
		local n = bit32.bor(
			bit32.lshift(decodeMap[a], 18),
			bit32.lshift(decodeMap[b], 12),
			bit32.lshift(decodeMap[c] or 0, 6),
			decodeMap[d] or 0
		)
		if o < outLen then
			buffer.writeu8(out, o, bit32.rshift(n, 16))
		end
		if o + 1 < outLen then
			buffer.writeu8(out, o + 1, bit32.band(bit32.rshift(n, 8), 255))
		end
		if o + 2 < outLen then
			buffer.writeu8(out, o + 2, bit32.band(n, 255))
		end
		o += 3
	end
	return out
end

local function build(name: string): (MeshPart?, EditableMesh?)
	local mod = MeshData and MeshData:FindFirstChild(name)
	if not mod then
		return nil
	end
	local data = require(mod)
	if not data.Vertices then
		return nil -- texture-only data: the species is uploaded, its model comes from CreatureModels
	end
	local em = AssetService:CreateEditableMesh({})
	local vb = b64decode(data.Vertices)
	local ib = b64decode(data.Indices)
	local q = data.Quant / 32767
	-- The baked data has one vertex per (position, normal, uv) corner, split at texture seams.
	-- EditableMesh keeps positions, normals and UVs as separate lists, so share identical
	-- positions and normals: that roughly halves the mesh memory, and the client's Editable
	-- memory budget only fits all creatures + props this way.
	local vids, nids, uids = table.create(data.VertexCount), table.create(data.VertexCount), table.create(data.VertexCount)
	local posIds: { [number]: number } = {}
	local normIds: { [number]: number } = {}
	local uvIds: { [number]: number } = {}
	for i = 0, data.VertexCount - 1 do
		local o = i * 13
		local ix, iy, iz = buffer.readi16(vb, o), buffer.readi16(vb, o + 2), buffer.readi16(vb, o + 4)
		local jx, jy, jz = buffer.readi8(vb, o + 6), buffer.readi8(vb, o + 7), buffer.readi8(vb, o + 8)
		local u = buffer.readu16(vb, o + 9) / 65535
		local v = buffer.readu16(vb, o + 11) / 65535
		local pk = ((ix + 32768) * 65536 + (iy + 32768)) * 65536 + (iz + 32768)
		local vid = posIds[pk]
		if not vid then
			vid = em:AddVertex(Vector3.new(ix * q, iy * q, iz * q))
			posIds[pk] = vid
		end
		-- normals snapped to 1/32 steps: invisible on these smooth toys, far fewer entries
		jx, jy, jz = math.round(jx / 4), math.round(jy / 4), math.round(jz / 4)
		local nk = (jx + 64) * 16384 + (jy + 64) * 128 + (jz + 64)
		local nid = normIds[nk]
		if not nid then
			nid = em:AddNormal(Vector3.new(jx, jy, jz).Unit)
			normIds[nk] = nid
		end
		local uk = buffer.readu16(vb, o + 9) * 65536 + buffer.readu16(vb, o + 11)
		local uid = uvIds[uk]
		if not uid then
			uid = em:AddUV(Vector2.new(u, v))
			uvIds[uk] = uid
		end
		vids[i + 1] = vid
		nids[i + 1] = nid
		uids[i + 1] = uid
	end
	for t = 0, data.TriangleCount - 1 do
		local a = buffer.readu16(ib, t * 6) + 1
		local b = buffer.readu16(ib, t * 6 + 2) + 1
		local c = buffer.readu16(ib, t * 6 + 4) + 1
		if vids[a] == vids[b] or vids[b] == vids[c] or vids[a] == vids[c] then
			continue -- degenerate after sharing positions
		end
		local fid = em:AddTriangle(vids[a], vids[b], vids[c])
		em:SetFaceNormals(fid, { nids[a], nids[b], nids[c] })
		em:SetFaceUVs(fid, { uids[a], uids[b], uids[c] })
	end
	local mp = AssetService:CreateMeshPartAsync(Content.fromObject(em), { CollisionFidelity = Enum.CollisionFidelity.Box })
	if data.Texture then
		local w, h = data.TextureSize[1], data.TextureSize[2]
		local img = AssetService:CreateEditableImage({ Size = Vector2.new(w, h) })
		img:WritePixelsBuffer(Vector2.zero, Vector2.new(w, h), b64decode(data.Texture))
		mp.TextureContent = Content.fromObject(img)
	end
	mp.Name = name
	mp.Anchored = true
	mp.CanCollide = false
	mp.CanQuery = false
	mp.CanTouch = false
	mp.Massless = true
	mp:SetAttribute("Extents", Vector3.new(data.Extents[1], data.Extents[2], data.Extents[3]))
	return mp, em
end

-- Pool. A client can only hold about 8 EditableMeshes at once (any size; measured in Studio
-- 2026-11-26), so templates are reference-counted and unused ones are evicted to make room.
-- Decorative props ask with optional = true: they only load when there is spare room, and
-- they are the first to be evicted (their clones then go blank) when a creature needs a slot.
local CAP = 7
type Template = { part: MeshPart, em: EditableMesh, refs: number, optional: boolean, lastUse: number }
local templates: { [string]: Template } = {}
local live = 0
local missing: { [string]: boolean } = {}

local function evict(name: string)
	local t = templates[name]
	templates[name] = nil
	live -= 1
	t.part:Destroy()
	t.em:Destroy()
end

local function makeRoom(optional: boolean): boolean
	local limit = optional and CAP - 1 or CAP -- keep one slot spare for creatures
	if live < limit then
		return true
	end
	-- least recently used template nobody is showing
	local best, bestT = nil, math.huge
	for n, t in templates do
		if t.refs <= 0 and t.lastUse < bestT then
			best, bestT = n, t.lastUse
		end
	end
	if not best and not optional then
		-- a creature needs the slot more than a decorative prop
		for n, t in templates do
			if t.optional then
				best = n
				break
			end
		end
	end
	if best then
		evict(best)
	end
	return live < limit
end

-- Returns a fresh MeshPart clone sized so its height is `height` studs, or nil. Call
-- MeshLoader.release(name) when the clone is destroyed.
function MeshLoader.get(name: string, height: number, opts: { optional: boolean? }?): MeshPart?
	if missing[name] then
		return nil
	end
	local optional = opts ~= nil and opts.optional == true
	local t = templates[name]
	if not t then
		if not makeRoom(optional) then
			return nil
		end
		local ok, part, em = pcall(build, name)
		if not ok then
			warn(`[MeshLoader] {name} failed: {part}`)
			return nil
		end
		if not part then
			missing[name] = true
			return nil
		end
		t = { part = part, em = em, refs = 0, optional = optional, lastUse = os.clock() }
		templates[name] = t
		live += 1
	end
	t.refs += 1
	t.lastUse = os.clock()
	local mp = t.part:Clone()
	local ext: Vector3 = t.part:GetAttribute("Extents")
	mp.Size = ext * height
	return mp
end

function MeshLoader.release(name: string)
	local t = templates[name]
	if t then
		t.refs = math.max(0, t.refs - 1)
		t.lastUse = os.clock()
	end
end

function MeshLoader.has(name: string): boolean
	return MeshData ~= nil and MeshData:FindFirstChild(name) ~= nil
end

function MeshLoader.stats()
	local out = {}
	for n, t in templates do
		table.insert(out, n .. ":" .. t.refs .. (t.optional and "o" or ""))
	end
	return live, table.concat(out, " ")
end

MeshLoader.b64decode = b64decode

-- Raw RGBA texture of a baked mesh (for recolouring), cached: (buffer, width, height) or nil.
local texCache: { [string]: any } = {}
function MeshLoader.texture(name: string): (buffer?, number, number)
	local c = texCache[name]
	if c == nil then
		local mod = MeshData and MeshData:FindFirstChild(name)
		if mod then
			local data = require(mod)
			if data.Texture then
				c = Budget.run(function()
					return { b64decode(data.Texture), data.TextureSize[1], data.TextureSize[2] }
				end)
			end
		end
		texCache[name] = c or false
	end
	if not c then
		return nil, 0, 0
	end
	return c[1], c[2], c[3]
end

return MeshLoader

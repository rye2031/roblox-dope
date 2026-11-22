-- Rebuilds Meshy models from src/shared/MeshData at runtime with EditableMesh + EditableImage,
-- so the prototype needs no uploaded assets. Each client builds its own templates (Editable
-- content does not replicate). Returns nil when a mesh is missing or the APIs are unavailable;
-- callers fall back to labelled placeholder parts.
local AssetService = game:GetService("AssetService")

local MeshLoader = {}

local cache: { [string]: MeshPart | false } = {}
local MeshData = script.Parent:WaitForChild("MeshData", 5)

local B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local decodeMap = {}
for i = 1, 64 do
	decodeMap[string.byte(B64, i)] = i - 1
end

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
	for i = 1, len, 4 do
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

local function build(name: string): MeshPart?
	local mod = MeshData and MeshData:FindFirstChild(name)
	if not mod then
		return nil
	end
	local data = require(mod)
	local em = AssetService:CreateEditableMesh({})
	local vb = b64decode(data.Vertices)
	local ib = b64decode(data.Indices)
	local q = data.Quant / 32767
	local vids, nids, uids = table.create(data.VertexCount), table.create(data.VertexCount), table.create(data.VertexCount)
	for i = 0, data.VertexCount - 1 do
		local o = i * 13
		local px = buffer.readi16(vb, o) * q
		local py = buffer.readi16(vb, o + 2) * q
		local pz = buffer.readi16(vb, o + 4) * q
		local nx = buffer.readi8(vb, o + 6) / 127
		local ny = buffer.readi8(vb, o + 7) / 127
		local nz = buffer.readi8(vb, o + 8) / 127
		local u = buffer.readu16(vb, o + 9) / 65535
		local v = buffer.readu16(vb, o + 11) / 65535
		vids[i + 1] = em:AddVertex(Vector3.new(px, py, pz))
		nids[i + 1] = em:AddNormal(Vector3.new(nx, ny, nz).Unit)
		uids[i + 1] = em:AddUV(Vector2.new(u, v))
	end
	for t = 0, data.TriangleCount - 1 do
		local a = buffer.readu16(ib, t * 6) + 1
		local b = buffer.readu16(ib, t * 6 + 2) + 1
		local c = buffer.readu16(ib, t * 6 + 4) + 1
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
	return mp
end

-- Returns a fresh MeshPart clone sized so its height is `height` studs, or nil.
function MeshLoader.get(name: string, height: number): MeshPart?
	if cache[name] == nil then
		local ok, result = pcall(build, name)
		if not ok then
			warn(`[MeshLoader] {name} failed: {result}`)
		end
		cache[name] = (ok and result) or false
	end
	local template = cache[name]
	if not template then
		return nil
	end
	local mp = template:Clone()
	local ext: Vector3 = template:GetAttribute("Extents")
	mp.Size = ext * height
	return mp
end

function MeshLoader.has(name: string): boolean
	return MeshData ~= nil and MeshData:FindFirstChild(name) ~= nil
end

return MeshLoader

-- Creature models for the client, recoloured per element.
--
-- Uploaded species come from ReplicatedStorage/CreatureModels (no limit). Species not uploaded
-- yet are rebuilt at runtime by MeshLoader (pooled, ~7 at once). Each element is a palette
-- repaint of the base texture: luminance is mapped onto the element's dark->light ramp, so the
-- same model reads as Fire, Water, Wind, Light or Dark. Recoloured textures are 256 px
-- EditableImages, cached per species+element.
local AssetService = game:GetService("AssetService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Monsters = require(Shared.Monsters)
local MeshLoader = require(Shared.MeshLoader)

local Models = {}

local SIZE = 256
local baseCache: { [string]: any } = {} -- species -> { buf, w, h } (256 px base texture) | false
local tintCache: { [string]: EditableImage } = {} -- "sp:el" -> image
local loading: { [string]: boolean } = {}

local function uploadedTemplate(sp: string): MeshPart?
	local folder = ReplicatedStorage:FindFirstChild("CreatureModels")
	local def = Monsters.Species[sp]
	local m = folder and def and folder:FindFirstChild(def.Model)
	if not m then
		return nil
	end
	return (m.PrimaryPart or m:FindFirstChildWhichIsA("MeshPart", true)) :: MeshPart?
end

-- 256 px copy of a species' base texture as an RGBA buffer. The baked MeshData texture comes
-- first: it's the same image (and UV layout) as the uploaded model's, already small, and costs
-- no EditableImage memory. Only species without baked data read the uploaded texture, one at a
-- time (a full-size EditableImage is big and the client's image budget is shared).
local reading = false
local function baseTexture(sp: string)
	local c = baseCache[sp]
	if c ~= nil then
		return c or nil
	end
	local def = Monsters.Species[sp]
	local buf, w, h = MeshLoader.texture(def.Model)
	if buf then
		c = { buf, w, h }
	else
		local tpl = uploadedTemplate(sp)
		c = false
		if tpl and tpl.TextureID ~= "" then
			while reading do
				task.wait()
			end
			reading = true
			local ok, res = pcall(function()
				local src = AssetService:CreateEditableImageAsync(Content.fromUri(tpl.TextureID))
				if not src then
					return nil
				end
				local small = AssetService:CreateEditableImage({ Size = Vector2.new(SIZE, SIZE) })
				small:DrawImageTransformed(Vector2.new(SIZE / 2, SIZE / 2), Vector2.new(SIZE / src.Size.X, SIZE / src.Size.Y), 0, src, { CombineType = Enum.ImageCombineType.Overwrite })
				src:Destroy()
				local out = small:ReadPixelsBuffer(Vector2.zero, Vector2.new(SIZE, SIZE))
				small:Destroy()
				return { out, SIZE, SIZE }
			end)
			reading = false
			if not ok or not res then
				warn(`[Models] couldn't read {sp} texture for recolouring: {res}`)
			end
			c = ok and res or false
		end
	end
	baseCache[sp] = c
	return c or nil
end

-- Repaint an RGBA buffer onto an element's colour ramp.
local function tint(src: buffer, w: number, h: number, element: string): buffer
	local info = Config.ElementInfo[element]
	local dr, dg, db = info.Dark.R * 255, info.Dark.G * 255, info.Dark.B * 255
	local lr, lg, lb = info.Light.R * 255, info.Light.G * 255, info.Light.B * 255
	local out = buffer.create(w * h * 4)
	local k = 0.85
	for i = 0, w * h - 1 do
		local o = i * 4
		local r, g, b, a = buffer.readu8(src, o), buffer.readu8(src, o + 1), buffer.readu8(src, o + 2), buffer.readu8(src, o + 3)
		local lum = (0.3 * r + 0.59 * g + 0.11 * b) / 255
		if lum < 0.13 then
			-- keep dark details (eyes, outlines)
			buffer.writeu8(out, o, r)
			buffer.writeu8(out, o + 1, g)
			buffer.writeu8(out, o + 2, b)
		else
			local t = lum ^ 0.85
			local tr, tg, tb = dr + (lr - dr) * t, dg + (lg - dg) * t, db + (lb - db) * t
			buffer.writeu8(out, o, math.clamp(math.floor(r * (1 - k) + tr * k), 0, 255))
			buffer.writeu8(out, o + 1, math.clamp(math.floor(g * (1 - k) + tg * k), 0, 255))
			buffer.writeu8(out, o + 2, math.clamp(math.floor(b * (1 - k) + tb * k), 0, 255))
		end
		buffer.writeu8(out, o + 3, a)
	end
	return out
end

-- Element texture for a species (yields the first time). nil if recolouring isn't possible.
function Models.texture(sp: string, element: string): EditableImage?
	local key = sp .. ":" .. element
	if tintCache[key] then
		return tintCache[key]
	end
	while loading[key] do
		task.wait()
	end
	if tintCache[key] then
		return tintCache[key]
	end
	loading[key] = true
	local base = baseTexture(sp)
	local img = nil
	if base then
		local ok, res = pcall(function()
			local buf = tint(base[1], base[2], base[3], element)
			local im = AssetService:CreateEditableImage({ Size = Vector2.new(base[2], base[3]) })
			im:WritePixelsBuffer(Vector2.zero, Vector2.new(base[2], base[3]), buf)
			return im
		end)
		img = ok and res or nil
	end
	tintCache[key] = img
	loading[key] = nil
	return img
end

-- A MeshPart for a species, `height` studs tall, recoloured for its element (asynchronously).
-- Returns (part, release). Falls back to a coloured ball if no model is available.
function Models.get(sp: string, element: string, height: number): (BasePart, () -> ())
	local def = Monsters.Species[sp]
	local tpl = uploadedTemplate(sp)
	local mp: BasePart? = nil
	local release = function() end
	if tpl then
		local c = tpl:Clone()
		c.Size = tpl.Size * (height / tpl.Size.Y)
		c:ClearAllChildren()
		mp = c
	else
		local r = MeshLoader.get(def.Model, height)
		if r then
			mp = r
			local released = false
			release = function()
				if not released then
					released = true
					MeshLoader.release(def.Model)
				end
			end
		end
	end
	if not mp then
		local ball = Instance.new("Part")
		ball.Shape = Enum.PartType.Ball
		ball.Size = Vector3.new(height, height, height)
		ball.Color = Config.ElementInfo[element].Color
		mp = ball
	end
	local part = mp :: BasePart
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	if part:IsA("MeshPart") then
		task.spawn(function()
			local img = Models.texture(sp, element)
			if img then
				pcall(function()
					(part :: MeshPart).TextureContent = Content.fromObject(img)
				end)
			end
		end)
	end
	return part, release
end

return Models

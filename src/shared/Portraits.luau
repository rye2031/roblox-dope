-- Creature portraits (pre-rendered by scripts/render_portrait.py) as EditableImages for the
-- Index and the reveal card. Images use a separate, larger budget than EditableMeshes, so these
-- screens never compete with the creatures in the world for mesh slots.
local AssetService = game:GetService("AssetService")
local MeshLoader = require(script.Parent.MeshLoader)
local Budget = require(script.Parent.Budget)

local Portraits = {}

local folder = script.Parent:WaitForChild("PortraitData", 5)
local cache: { [string]: EditableImage | false } = {}
local pending: { [string]: boolean } = {}

function Portraits.image(name: string): EditableImage?
	while cache[name] == nil and pending[name] do
		task.wait()
	end
	if cache[name] == nil then
		pending[name] = true
		local ok, img = pcall(Budget.run, function()
			local mod = folder and folder:FindFirstChild(name)
			if not mod then
				return nil
			end
			local data = require(mod)
			local w, h = data.Size[1], data.Size[2]
			local im = AssetService:CreateEditableImage({ Size = Vector2.new(w, h) })
			im:WritePixelsBuffer(Vector2.zero, Vector2.new(w, h), MeshLoader.b64decode(data.Pixels))
			return im
		end)
		if not ok then
			warn(`[Portraits] {name} failed: {img}`)
		end
		cache[name] = (ok and img) or false
		pending[name] = nil
	end
	return cache[name] or nil
end

-- Point an ImageLabel at a portrait. Returns false if the portrait is unavailable.
function Portraits.apply(label: ImageLabel, name: string): boolean
	local img = Portraits.image(name)
	if not img then
		label.Image = ""
		return false
	end
	label.ImageContent = Content.fromObject(img)
	return true
end

return Portraits

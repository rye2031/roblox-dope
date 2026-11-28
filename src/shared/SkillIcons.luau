-- Skill icons (baked by scripts/make_skill_icons.py into SkillIconData/<Group>.luau as 64 px
-- base64 RGBA) as EditableImages, cached. Every element skill, the four weapons, their
-- skills and dodge have one; a monster's signature move uses its portrait instead.
local AssetService = game:GetService("AssetService")
local MeshLoader = require(script.Parent.MeshLoader)
local Budget = require(script.Parent.Budget)

local SkillIcons = {}

local folder = script.Parent:WaitForChild("SkillIconData", 5)
local index: { [string]: string }? = nil -- name -> base64
local cache: { [string]: EditableImage | false } = {}
local pending: { [string]: boolean } = {}

local function lookup(name: string): string?
	if not index then
		local idx = {}
		for _, m in folder and folder:GetChildren() or {} do
			if m:IsA("ModuleScript") then
				for k, v in require(m) :: any do
					idx[k] = v
				end
			end
		end
		index = idx
	end
	return (index :: any)[name]
end

function SkillIcons.has(name: string): boolean
	return lookup(name) ~= nil
end

function SkillIcons.image(name: string): EditableImage?
	while cache[name] == nil and pending[name] do
		task.wait()
	end
	if cache[name] == nil then
		pending[name] = true
		local ok, img = pcall(Budget.run, function()
			local b64 = lookup(name)
			if not b64 then
				return nil
			end
			local im = AssetService:CreateEditableImage({ Size = Vector2.new(64, 64) })
			im:WritePixelsBuffer(Vector2.zero, Vector2.new(64, 64), MeshLoader.b64decode(b64))
			return im
		end)
		if not ok then
			warn(`[SkillIcons] {name} failed: {img}`)
		end
		cache[name] = (ok and img) or false
		pending[name] = nil
	end
	return cache[name] or nil
end

-- Point an ImageLabel/ImageButton at an icon. Returns false if there is none.
function SkillIcons.apply(label: ImageLabel | ImageButton, name: string): boolean
	local img = SkillIcons.image(name)
	if not img then
		label.Image = ""
		return false
	end
	label.ImageContent = Content.fromObject(img)
	return true
end

return SkillIcons

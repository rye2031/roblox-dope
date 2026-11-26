-- One look for every screen and world label: Builder Sans, white rounded cards, dark ink text,
-- one soft pastel accent per element. Used by the HUD (client) and the map's floating labels.
local Theme = {}

local FAMILY = "rbxasset://fonts/families/BuilderSans.json"
Theme.Font = {
	Title = Font.new(FAMILY, Enum.FontWeight.ExtraBold),
	Bold = Font.new(FAMILY, Enum.FontWeight.Bold),
	Body = Font.new(FAMILY, Enum.FontWeight.Medium),
}

Theme.C = {
	Card = Color3.fromRGB(255, 255, 255),
	Soft = Color3.fromRGB(244, 245, 250), -- inset areas on a card
	Line = Color3.fromRGB(226, 229, 238),
	Ink = Color3.fromRGB(38, 42, 58),
	Sub = Color3.fromRGB(118, 124, 145),
	Mute = Color3.fromRGB(190, 194, 208),
	Shadow = Color3.fromRGB(40, 44, 70),

	Mint = Color3.fromRGB(78, 205, 150),
	Sky = Color3.fromRGB(88, 166, 255),
	Peach = Color3.fromRGB(255, 150, 108),
	Lilac = Color3.fromRGB(160, 132, 255),
	Sun = Color3.fromRGB(255, 196, 64),
	Rose = Color3.fromRGB(255, 108, 140),
	Coral = Color3.fromRGB(255, 112, 96),
}

-- Lighter tint of a colour (for card backgrounds behind an accent).
function Theme.tint(c: Color3, k: number?): Color3
	return c:Lerp(Color3.new(1, 1, 1), k or 0.82)
end

function Theme.new(class: string, props: { [string]: any }, children: { Instance }?)
	local i = Instance.new(class)
	for k, v in props do
		if k ~= "Parent" then
			(i :: any)[k] = v
		end
	end
	for _, c in children or {} do
		c.Parent = i
	end
	if props.Parent then
		i.Parent = props.Parent
	end
	return i
end
local new = Theme.new

function Theme.corner(r: number?)
	return new("UICorner", { CornerRadius = UDim.new(0, r or 14) })
end

function Theme.pad(t: number, l: number?, b: number?, r: number?)
	return new("UIPadding", {
		PaddingTop = UDim.new(0, t),
		PaddingLeft = UDim.new(0, l or t),
		PaddingBottom = UDim.new(0, b or t),
		PaddingRight = UDim.new(0, r or l or t),
	})
end

function Theme.stroke(col: Color3?, th: number?, tr: number?)
	return new("UIStroke", {
		Color = col or Theme.C.Line,
		Thickness = th or 1.5,
		Transparency = tr or 0,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	})
end

-- Soft drop shadow: a blurred-looking darker rounded frame offset under a card.
function Theme.shadow(parent: GuiObject, radius: number?, offset: number?)
	local s = new("Frame", {
		Name = "Shadow",
		AnchorPoint = parent.AnchorPoint,
		Position = parent.Position + UDim2.fromOffset(0, offset or 4),
		Size = parent.Size,
		BackgroundColor3 = Theme.C.Shadow,
		BackgroundTransparency = 0.88,
		ZIndex = math.max(0, parent.ZIndex - 1),
		Visible = parent.Visible,
		Parent = parent.Parent,
	}, { Theme.corner(radius) })
	for _, c in parent:GetChildren() do
		if c:IsA("UISizeConstraint") then
			c:Clone().Parent = s
		end
	end
	parent:GetPropertyChangedSignal("Visible"):Connect(function()
		s.Visible = parent.Visible
	end)
	parent:GetPropertyChangedSignal("Position"):Connect(function()
		s.Position = parent.Position + UDim2.fromOffset(0, offset or 4)
	end)
	parent:GetPropertyChangedSignal("Size"):Connect(function()
		s.Size = parent.Size
	end)
	return s
end

-- Text label in the house font. weight: "Title" | "Bold" | "Body"
function Theme.text(props: { [string]: any }, weight: string?)
	props.BackgroundTransparency = props.BackgroundTransparency or 1
	props.FontFace = Theme.Font[weight or "Bold"]
	props.TextColor3 = props.TextColor3 or Theme.C.Ink
	if props.TextScaled == nil then
		props.TextScaled = true
	end
	local children = props.Children
	props.Children = nil
	return new("TextLabel", props, children)
end

function Theme.button(props: { [string]: any })
	props.FontFace = props.FontFace or Theme.Font.Title
	props.TextColor3 = props.TextColor3 or Color3.new(1, 1, 1)
	props.AutoButtonColor = true
	if props.TextScaled == nil then
		props.TextScaled = true
	end
	local children = props.Children or {}
	props.Children = nil
	table.insert(children, Theme.corner(props.Radius or 12))
	props.Radius = nil
	return new("TextButton", props, children)
end

-- A floating world label in the house style: white text on a soft pill, sized in studs so it
-- reads like part of the world. Map builds these; WorldFx makes them bob.
function Theme.floatLabel(adornee: BasePart, text: string, accent: Color3, widthStuds: number, opts: { [string]: any }?)
	opts = opts or {}
	local h = opts.Height or widthStuds * 0.22
	local bb = new("BillboardGui", {
		Name = "FloatLabel",
		Size = UDim2.fromScale(widthStuds, h),
		LightInfluence = 0,
		MaxDistance = opts.MaxDistance or 600,
		AlwaysOnTop = opts.AlwaysOnTop == true,
		Adornee = adornee,
		Parent = adornee,
	})
	bb:SetAttribute("FloatLabel", true)
	local pill = new("Frame", {
		Name = "Pill",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BackgroundTransparency = 0.04,
		Parent = bb,
	}, {
		new("UICorner", { CornerRadius = UDim.new(0.5, 0) }),
		new("UIStroke", { Color = accent, Thickness = 3, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }),
	})
	local dot = new("Frame", {
		Name = "Dot",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0.06, 0, 0.5, 0),
		Size = UDim2.fromScale(0.62, 0.62),
		SizeConstraint = Enum.SizeConstraint.RelativeYY,
		BackgroundColor3 = accent,
		Parent = pill,
	}, { new("UICorner", { CornerRadius = UDim.new(0.5, 0) }) })
	new("TextLabel", {
		Name = "Icon",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Text = opts.Icon or "",
		TextScaled = true,
		FontFace = Theme.Font.Title,
		TextColor3 = Color3.new(1, 1, 1),
		Parent = dot,
	}, { Theme.pad(3) })
	local label = new("TextLabel", {
		Name = "Text",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0.2, 0, 0.5, 0),
		Size = UDim2.new(0.74, 0, 0.62, 0),
		BackgroundTransparency = 1,
		Text = text,
		TextScaled = true,
		FontFace = Theme.Font.Title,
		TextColor3 = Theme.C.Ink,
		TextXAlignment = Enum.TextXAlignment.Center,
		Parent = pill,
	})
	if opts.Sub then
		label.Size = UDim2.new(0.74, 0, 0.44, 0)
		label.Position = UDim2.new(0.2, 0, 0.36, 0)
		new("TextLabel", {
			Name = "Sub",
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.new(0.2, 0, 0.74, 0),
			Size = UDim2.new(0.74, 0, 0.24, 0),
			BackgroundTransparency = 1,
			Text = opts.Sub,
			TextScaled = true,
			FontFace = Theme.Font.Bold,
			TextColor3 = Theme.C.Sub,
			Parent = pill,
		})
	end
	return bb
end

return Theme

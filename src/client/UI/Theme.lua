--[[
	Theme.lua
	Couleurs, police et petits constructeurs d'interface (style cartoon).
	Toutes les tailles sont en échelle (Scale) pour rester lisibles sur mobile.
]]

local Theme = {}

Theme.Font = Enum.Font.FredokaOne
Theme.White = Color3.new(1, 1, 1)
Theme.Dark = Color3.fromRGB(28, 30, 44)
Theme.Panel = Color3.fromRGB(44, 49, 72)
Theme.PanelLight = Color3.fromRGB(70, 78, 112)
Theme.Accent = Color3.fromRGB(255, 200, 60)
Theme.Good = Color3.fromRGB(70, 210, 110)
Theme.Bad = Color3.fromRGB(235, 70, 70)
Theme.Coin = Color3.fromRGB(255, 214, 70)

function Theme.New(className: string, props: { [string]: any }, parent: Instance?): any
	local inst = Instance.new(className)
	for key, value in props do
		(inst :: any)[key] = value
	end
	if parent then
		inst.Parent = parent
	end
	return inst
end

function Theme.Corner(parent: Instance, radius: number?): UICorner
	return Theme.New("UICorner", { CornerRadius = UDim.new(0, radius or 12) }, parent)
end

-- Coins arrondis proportionnels (ex : 0.5 = pilule)
function Theme.CornerScale(parent: Instance, scale: number): UICorner
	return Theme.New("UICorner", { CornerRadius = UDim.new(scale, 0) }, parent)
end

function Theme.Stroke(parent: Instance, thickness: number?, color: Color3?): UIStroke
	return Theme.New("UIStroke", {
		Thickness = thickness or 2.5,
		Color = color or Theme.Dark,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	}, parent)
end

function Theme.Label(parent: Instance, props: { [string]: any }): TextLabel
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Font = Theme.Font
	label.TextScaled = true
	label.TextColor3 = Theme.White
	label.Text = ""
	for key, value in props do
		(label :: any)[key] = value
	end
	label.Parent = parent
	return label
end

function Theme.MaxText(label: TextLabel, size: number)
	Theme.New("UITextSizeConstraint", { MaxTextSize = size }, label)
end

function Theme.FormatTime(seconds: number): string
	seconds = math.max(0, math.floor(seconds + 0.5))
	return string.format("%d:%02d", seconds // 60, seconds % 60)
end

-- Couleur de texte lisible sur un fond donné
function Theme.TextOn(color: Color3): Color3
	local luminance = 0.299 * color.R + 0.587 * color.G + 0.114 * color.B
	return luminance > 0.6 and Theme.Dark or Theme.White
end

return Theme

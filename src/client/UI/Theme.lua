--[[
	Theme.lua
	Couleurs, polices et petits constructeurs d'interface, d'après les captures de
	référence (reference/HUSS_VALLEY_NOTES.md, section A) :
	  - panneaux bleu nuit translucides, coins arrondis ;
	  - textes très gras, titres en italique, contour sombre sur les grands textes ;
	  - pastilles noires en haut, accents dorés et verts.
	Les tailles sont en échelle (Scale) avec de gros boutons pour le mobile.
]]

local Theme = {}

local FAMILY = "rbxasset://fonts/families/GothamSSm.json"

Theme.Font = Enum.Font.GothamBold
Theme.FontBold = Enum.Font.GothamBold
Theme.FontBlack = Enum.Font.GothamBlack
Theme.FaceBold = Font.new(FAMILY, Enum.FontWeight.Bold, Enum.FontStyle.Normal)
Theme.FaceHeavy = Font.new(FAMILY, Enum.FontWeight.Heavy, Enum.FontStyle.Normal)
Theme.FaceTitle = Font.new(FAMILY, Enum.FontWeight.Heavy, Enum.FontStyle.Italic)

Theme.White = Color3.fromRGB(255, 255, 255)
Theme.Dark = Color3.fromRGB(14, 16, 30)
Theme.Outline = Color3.fromRGB(10, 10, 18)
Theme.Panel = Color3.fromRGB(22, 28, 52)
Theme.PanelLight = Color3.fromRGB(40, 50, 86)
Theme.PillColor = Color3.fromRGB(16, 16, 22)
Theme.Accent = Color3.fromRGB(255, 200, 40)
Theme.Gold = Color3.fromRGB(255, 196, 30)
Theme.Good = Color3.fromRGB(70, 220, 90)
Theme.Bad = Color3.fromRGB(235, 50, 50)
Theme.Coin = Color3.fromRGB(255, 200, 50)
Theme.Muted = Color3.fromRGB(175, 185, 205)

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
	return Theme.New("UICorner", { CornerRadius = UDim.new(0, radius or 10) }, parent)
end

function Theme.CornerScale(parent: Instance, scale: number): UICorner
	return Theme.New("UICorner", { CornerRadius = UDim.new(scale, 0) }, parent)
end

function Theme.Stroke(parent: Instance, thickness: number?, color: Color3?, transparency: number?): UIStroke
	return Theme.New("UIStroke", {
		Thickness = thickness or 2,
		Color = color or Theme.Outline,
		Transparency = transparency or 0,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	}, parent)
end

-- Texte de base (gras), sans contour
function Theme.Label(parent: Instance, props: { [string]: any }): TextLabel
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.FontFace = Theme.FaceBold
	label.TextScaled = true
	label.TextColor3 = Theme.White
	label.Text = ""
	for key, value in props do
		(label :: any)[key] = value
	end
	label.Parent = parent
	return label
end

-- Grand texte très gras avec contour sombre (annonces, titres)
function Theme.Title(parent: Instance, props: { [string]: any }): TextLabel
	local label = Theme.Label(parent, props)
	if props.FontFace == nil then
		label.FontFace = Theme.FaceTitle
	end
	label.TextStrokeTransparency = 0
	label.TextStrokeColor3 = Theme.Outline
	return label
end

function Theme.MaxText(label: TextLabel, size: number)
	Theme.New("UITextSizeConstraint", { MaxTextSize = size }, label)
end

function Theme.FormatTime(seconds: number): string
	seconds = math.max(0, math.floor(seconds + 0.5))
	return string.format("%d:%02d", seconds // 60, seconds % 60)
end

function Theme.FormatNumber(n: number): string
	local s = tostring(math.floor(n))
	local formatted = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	if formatted:sub(1, 1) == "," then
		formatted = formatted:sub(2)
	end
	return formatted
end

function Theme.Hex(color: Color3): string
	return string.format("#%02x%02x%02x", math.floor(color.R * 255), math.floor(color.G * 255), math.floor(color.B * 255))
end

function Theme.TextOn(color: Color3): Color3
	local luminance = 0.299 * color.R + 0.587 * color.G + 0.114 * color.B
	return luminance > 0.6 and Theme.Dark or Theme.White
end

-- Pastille (bouton noir arrondi en haut de l'écran)
function Theme.Pill(parent: Instance, text: string, props: { [string]: any }?): TextButton
	local button: TextButton = Theme.New("TextButton", {
		BackgroundColor3 = Theme.PillColor,
		BackgroundTransparency = 0.05,
		Text = "",
		AutoButtonColor = true,
	}, parent)
	Theme.CornerScale(button, 0.5)
	local label = Theme.Label(button, { Name = "Label", Size = UDim2.fromScale(0.8, 0.5), Position = UDim2.fromScale(0.1, 0.25), Text = text, FontFace = Theme.FaceHeavy })
	local _ = label
	if props then
		for key, value in props do
			(button :: any)[key] = value
		end
	end
	return button
end

-- Petite pastille rouge "!" (notification)
function Theme.Badge(parent: Instance): Frame
	local badge: Frame = Theme.New("Frame", {
		Name = "Badge",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.95, 0.12),
		Size = UDim2.fromScale(0.28, 0.5),
		BackgroundColor3 = Theme.Bad,
		Visible = false,
		ZIndex = 3,
	}, parent)
	Theme.New("UIAspectRatioConstraint", { AspectRatio = 1 }, badge)
	Theme.CornerScale(badge, 0.5)
	Theme.Stroke(badge, 1.5, Theme.White)
	Theme.Label(badge, { Size = UDim2.fromScale(0.6, 0.7), Position = UDim2.fromScale(0.2, 0.15), Text = "!", FontFace = Theme.FaceHeavy, ZIndex = 3 })
	return badge
end

return Theme

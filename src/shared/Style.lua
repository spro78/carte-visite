--[[
	Style.lua
	Direction artistique, inspirée de l'ambiance de Huss Valley :
	géométrie simple "gray-box", palette industrielle froide et désaturée,
	brume bleu-gris, lampes chaudes en contrepoint ; les couleurs vives sont
	réservées au gameplay (équipes, objectifs, dangers).

	Style.Environment(color) est appliqué automatiquement par Build.Part à
	toutes les pièces de décor ; une pièce marquée Accent = true garde sa couleur.
]]

local Style = {}

Style.Enabled = true

-- Réglages du filtre de couleur appliqué au décor
Style.Filter = {
	Saturation = 0.55, -- 1 = couleurs d'origine, 0 = gris
	Brightness = 0.92,
	Tint = Color3.fromRGB(176, 190, 208), -- teinte froide
	TintAmount = 0.12,
}

-- Palette nommée (utilisée par le lobby et les maps)
Style.Palette = {
	Concrete = Color3.fromRGB(96, 100, 108),
	ConcreteLight = Color3.fromRGB(150, 155, 163),
	ConcreteDark = Color3.fromRGB(62, 66, 74),
	Steel = Color3.fromRGB(70, 76, 86),
	SteelLight = Color3.fromRGB(165, 172, 182),
	Panel = Color3.fromRGB(190, 196, 204),
	PanelAlt = Color3.fromRGB(172, 178, 188),
	Hazard = Color3.fromRGB(255, 190, 30),
	HazardDark = Color3.fromRGB(35, 35, 40),
	LampWarm = Color3.fromRGB(255, 170, 80),
	Screen = Color3.fromRGB(14, 16, 22),
	ScreenText = Color3.fromRGB(235, 240, 248),
	Rust = Color3.fromRGB(150, 85, 55),
	Wood = Color3.fromRGB(140, 105, 75),
	ContainerBlue = Color3.fromRGB(45, 95, 150),
	ContainerOrange = Color3.fromRGB(205, 110, 45),
}

-- Éclairage global (appliqué au démarrage du serveur)
Style.Lighting = {
	ClockTime = 15.6,
	Brightness = 2.6,
	Ambient = Color3.fromRGB(62, 68, 80),
	OutdoorAmbient = Color3.fromRGB(128, 136, 150),
	EnvironmentDiffuseScale = 1,
	EnvironmentSpecularScale = 0.6,
	GlobalShadows = true,
	ShadowSoftness = 0.25,
	FogColor = Color3.fromRGB(170, 180, 194),
	FogStart = 150,
	FogEnd = 1400,
}

Style.Atmosphere = {
	Density = 0.32,
	Offset = 0.15,
	Color = Color3.fromRGB(196, 205, 216),
	Decay = Color3.fromRGB(104, 112, 126),
	Glare = 0.15,
	Haze = 1.4,
}

Style.ColorCorrection = {
	Brightness = 0.02,
	Contrast = 0.12,
	Saturation = -0.12,
	TintColor = Color3.fromRGB(238, 244, 255),
}

Style.Bloom = {
	Intensity = 0.45,
	Size = 24,
	Threshold = 1.15,
}

-- Filtre de couleur pour le décor
function Style.Environment(color: Color3): Color3
	if not Style.Enabled then
		return color
	end
	local f = Style.Filter
	local gray = 0.299 * color.R + 0.587 * color.G + 0.114 * color.B
	local r = gray + (color.R - gray) * f.Saturation
	local g = gray + (color.G - gray) * f.Saturation
	local b = gray + (color.B - gray) * f.Saturation
	local result = Color3.new(math.clamp(r * f.Brightness, 0, 1), math.clamp(g * f.Brightness, 0, 1), math.clamp(b * f.Brightness, 0, 1))
	return result:Lerp(f.Tint, f.TintAmount)
end

return Style

--[[
	Style.lua
	Direction artistique, d'après les captures de Huss Valley (reference/) :
	style Roblox classique, lumineux et saturé, plein jour, ciel bleu à nuages ;
	sol vert à tenons, pierre gris-bleu, blocs jaunes, arbres en cubes aux couleurs
	d'automne, maisons turquoise à toit vert.

	Style.Environment(color) est appliqué automatiquement par Build.Part à
	toutes les pièces de décor ; une pièce marquée Accent = true garde sa couleur.
]]

local Style = {}

Style.Enabled = true

-- Filtre de couleur appliqué au décor (ici : couleurs légèrement ravivées)
Style.Filter = {
	Saturation = 1.08,
	Brightness = 1.0,
	Tint = Color3.fromRGB(255, 255, 255),
	TintAmount = 0,
}

-- Palette nommée (lobby et maps)
Style.Palette = {
	Grass = Color3.fromRGB(64, 178, 72),
	GrassDark = Color3.fromRGB(48, 150, 58),
	Stone = Color3.fromRGB(150, 160, 182),
	StoneDark = Color3.fromRGB(116, 126, 150),
	BlockYellow = Color3.fromRGB(245, 200, 45),
	Trunk = Color3.fromRGB(110, 75, 50),
	LeafOrange = Color3.fromRGB(255, 132, 38),
	LeafRed = Color3.fromRGB(232, 72, 40),
	LeafYellow = Color3.fromRGB(255, 190, 40),
	HouseWall = Color3.fromRGB(110, 210, 180),
	HouseRoof = Color3.fromRGB(40, 120, 70),
	Garage = Color3.fromRGB(110, 125, 150),
	BoardGray = Color3.fromRGB(118, 124, 136),
	WheelBlue = Color3.fromRGB(30, 120, 240),
	GiftRed = Color3.fromRGB(230, 40, 45),
	PortalDark = Color3.fromRGB(40, 32, 92),
	PortalGlow = Color3.fromRGB(170, 80, 255),
	PadBlue = Color3.fromRGB(70, 130, 230),
	Wood = Color3.fromRGB(125, 85, 55),
	White = Color3.fromRGB(245, 245, 245),
	Screen = Color3.fromRGB(18, 22, 40),
	ScreenText = Color3.fromRGB(245, 248, 255),
	Gold = Color3.fromRGB(255, 205, 50),
}

-- Couleurs des matériaux du Terrain (relief des maps et du lobby)
Style.TerrainColors = {
	Grass = Color3.fromRGB(92, 182, 70),
	LeafyGrass = Color3.fromRGB(72, 158, 58),
	Ground = Color3.fromRGB(176, 132, 86),
	Mud = Color3.fromRGB(112, 84, 58),
	Sand = Color3.fromRGB(226, 186, 128),
	Sandstone = Color3.fromRGB(206, 120, 78),
	Rock = Color3.fromRGB(122, 118, 112),
	Slate = Color3.fromRGB(112, 118, 132),
	Basalt = Color3.fromRGB(70, 66, 74),
	Limestone = Color3.fromRGB(236, 190, 140),
	Snow = Color3.fromRGB(246, 250, 255),
	Cobblestone = Color3.fromRGB(150, 152, 162),
	Pavement = Color3.fromRGB(214, 204, 188),
	Brick = Color3.fromRGB(214, 128, 98),
	Salt = Color3.fromRGB(236, 230, 220),
	Asphalt = Color3.fromRGB(90, 92, 100),
}

Style.Water = {
	Color = Color3.fromRGB(36, 150, 186),
	Transparency = 0.35,
	WaveSize = 0.12,
	WaveSpeed = 8,
	Reflectance = 0.6,
}

-- Éclairage global (appliqué au démarrage du serveur)
Style.Lighting = {
	ClockTime = 13.5,
	Brightness = 3,
	Ambient = Color3.fromRGB(110, 110, 120),
	OutdoorAmbient = Color3.fromRGB(150, 150, 160),
	EnvironmentDiffuseScale = 0.6,
	EnvironmentSpecularScale = 0.3,
	GlobalShadows = true,
	ShadowSoftness = 0.2,
	FogColor = Color3.fromRGB(200, 225, 255),
	FogStart = 400,
	FogEnd = 3000,
}

Style.Atmosphere = {
	Density = 0.18,
	Offset = 0.05,
	Color = Color3.fromRGB(205, 228, 255),
	Decay = Color3.fromRGB(150, 180, 220),
	Glare = 0,
	Haze = 0.6,
}

Style.ColorCorrection = {
	Brightness = 0.03,
	Contrast = 0.06,
	Saturation = 0.15,
	TintColor = Color3.fromRGB(255, 255, 255),
}

Style.Bloom = {
	Intensity = 0.35,
	Size = 20,
	Threshold = 1.4,
}

Style.SunRays = {
	Intensity = 0.04,
	Spread = 0.6,
}

Style.Clouds = {
	Cover = 0.55,
	Density = 0.6,
	Color = Color3.fromRGB(255, 255, 255),
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
	if f.TintAmount > 0 then
		result = result:Lerp(f.Tint, f.TintAmount)
	end
	return result
end

return Style

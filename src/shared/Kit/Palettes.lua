--[[
	Palettes.lua
	Couleurs des « rôles » du kit d'assets (tools/assets) pour chaque carte.
	Un mesh ne porte pas de couleur : chaque pièce a un rôle (Foliage, Rock,
	Path...) et la palette de la carte lui donne sa teinte. Une même forme sert
	donc dans plusieurs ambiances sans être remodélisée.
	Règles de la bible visuelle :
	  - les couleurs d'équipe (orange, jaune, vert vif) restent réservées aux
	    équipes : seuls les rôles Team / TeamDark les prennent (camps) ;
	  - verts de prairie doux, pierre gris-bleu claire, bois chauds, accents
	    de fête saturés mais en petites surfaces.
	Résolution d'un rôle (Palettes.Resolve) :
	  1. attribut KitRole_<rôle> posé sur le modèle (Color3) ;
	  2. Team / TeamDark : couleur de l'équipe indiquée par l'attribut KitTeam ;
	  3. palette de la carte (attribut KitPalette), puis palette Valley.
]]

local Teams = require(script.Parent.Parent.Teams)

local Palettes = {}

local rgb = Color3.fromRGB

Palettes.Valley = {
	-- Herbes et feuillages
	Grass = rgb(116, 190, 86),
	GrassLight = rgb(126, 198, 104),
	GrassDark = rgb(92, 166, 74),
	GrassCool = rgb(98, 178, 104),
	HillGrass = rgb(116, 188, 92),
	HillSlope = rgb(150, 170, 132),
	Moss = rgb(126, 190, 88),
	Foliage = rgb(98, 180, 86),
	FoliageShade = rgb(70, 146, 78),
	FoliageDark = rgb(66, 148, 84),
	FoliageDarkShade = rgb(46, 118, 70),
	FoliageLight = rgb(150, 206, 96),
	Blossom = rgb(246, 176, 204),
	BlossomShade = rgb(214, 136, 172),
	Pine = rgb(54, 132, 98),
	PineShade = rgb(36, 100, 82),
	Trunk = rgb(128, 88, 64),
	Reed = rgb(118, 160, 80),
	Lily = rgb(96, 168, 86),
	-- Pierre et terre
	Rock = rgb(178, 182, 204),
	RockDark = rgb(140, 144, 170),
	Stone = rgb(206, 204, 214),
	Path = rgb(234, 214, 170),
	PathEdge = rgb(204, 178, 134),
	PathStone = rgb(170, 166, 158),
	Dirt = rgb(178, 140, 108),
	Cobble = rgb(222, 216, 206),
	CobbleDark = rgb(190, 182, 172),
	Burrow = rgb(58, 40, 34),
	Water = rgb(96, 182, 226),
	-- Bois et constructions
	Wood = rgb(148, 102, 68),
	WoodLight = rgb(196, 146, 106),
	WoodDark = rgb(100, 68, 50),
	Plank = rgb(184, 136, 98),
	BarnWall = rgb(190, 76, 80),
	BarnDoor = rgb(164, 62, 68),
	Roof = rgb(206, 84, 84),
	RoofDark = rgb(124, 70, 86),
	Wall = rgb(248, 240, 222),
	Cream = rgb(252, 244, 228),
	Cloth = rgb(240, 232, 218),
	Hay = rgb(204, 176, 128),
	Straw = rgb(176, 144, 98),
	Metal = rgb(180, 188, 204),
	LampMetal = rgb(64, 72, 100),
	Rope = rgb(110, 90, 76),
	-- Fête (petites surfaces)
	FairRed = rgb(234, 84, 96),
	FairBlue = rgb(82, 152, 230),
	FairLilac = rgb(166, 136, 232),
	FairTeal = rgb(64, 182, 190),
	Gold = rgb(176, 150, 104),
	Bulb = rgb(255, 244, 214),
	Saddle = rgb(234, 84, 96),
	Zone = rgb(252, 248, 236),
	Flag1 = rgb(234, 84, 96),
	Flag2 = rgb(252, 244, 228),
	Flag3 = rgb(82, 152, 230),
	Fruit = rgb(230, 96, 96),
	-- Objectifs et petits décors
	Egg = rgb(250, 246, 236),
	EggBand = rgb(150, 120, 230),
	Mushroom = rgb(226, 84, 84),
	MushroomSpot = rgb(252, 248, 240),
	Stem = rgb(240, 232, 214),
	Flower1 = rgb(250, 250, 255),
	Flower2 = rgb(238, 132, 178),
	Flower3 = rgb(156, 136, 238),
	Flower4 = rgb(112, 172, 242),
}

-- Réglages de rendu par rôle (le matériau de base vient du manifeste)
Palettes.Finish = {
	Water = { Transparency = 0.12 },
}

local FALLBACK = rgb(200, 200, 200)

-- Couleur d'un rôle pour un modèle placé par Kit.Place
function Palettes.Color(model: Instance?, role: string): Color3
	if model then
		local override = model:GetAttribute("KitRole_" .. role)
		if typeof(override) == "Color3" then
			return override
		end
		if role == "Team" or role == "TeamDark" then
			local def = Teams.Get(model:GetAttribute("KitTeam"))
			if def then
				return role == "Team" and def.Color or def.DarkColor
			end
		end
	end
	local paletteName = model and model:GetAttribute("KitPalette")
	local palette = (type(paletteName) == "string" and (Palettes :: any)[paletteName]) or Palettes.Valley
	return palette[role] or Palettes.Valley[role] or FALLBACK
end

-- Couleur, matériau et transparence d'une pièce
function Palettes.Resolve(model: Instance?, role: string, material: string): (Color3, Enum.Material, number)
	local finish = Palettes.Finish[role]
	local mat = (Enum.Material :: any)[material] or Enum.Material.SmoothPlastic
	return Palettes.Color(model, role), mat, finish and finish.Transparency or 0
end

return Palettes

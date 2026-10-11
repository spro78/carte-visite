--[[
	MapInfo.lua
	Métadonnées d'affichage des maps (partagées serveur/client).
	Le module serveur de chaque map (src/server/Maps/<Id>.lua) doit avoir
	un Id présent ici pour être pris en compte par le vote.
	Pour ajouter une 5e map : une entrée ici + un fichier dans src/server/Maps.
]]

local MapInfo = {}

export type MapDef = {
	Id: string,
	DisplayName: string,
	ModeName: string,
	Tagline: string, -- une phrase affichée au joueur (anglais)
	Color: Color3, -- couleur de la plaque de vote
}

MapInfo.Order = { "TheFarm", "TheCarousel", "TheCanyon", "TheSwamp" }

MapInfo.Defs = {
	TheFarm = {
		Id = "TheFarm",
		DisplayName = "The Farm",
		ModeName = "Golden Egg",
		Tagline = "Bring the golden egg home. First team to 3 wins!",
		Color = Color3.fromRGB(120, 190, 95),
	},
	TheCarousel = {
		Id = "TheCarousel",
		DisplayName = "The Carousel",
		ModeName = "King of the Wheel",
		Tagline = "Hold the spinning wheel. First team to 100 points wins!",
		Color = Color3.fromRGB(230, 120, 190),
	},
	TheCanyon = {
		Id = "TheCanyon",
		DisplayName = "The Canyon",
		ModeName = "Raid",
		Tagline = "Steal eggs from your prey's base. Most eggs wins!",
		Color = Color3.fromRGB(215, 150, 90),
	},
	TheSwamp = {
		Id = "TheSwamp",
		DisplayName = "The Swamp",
		ModeName = "The Pack",
		Tagline = "Pure conversion. Last team standing wins!",
		Color = Color3.fromRGB(80, 140, 120),
	},
} :: { [string]: MapDef }

function MapInfo.Get(id: string?): MapDef?
	if id == nil then
		return nil
	end
	return MapInfo.Defs[id]
end

function MapInfo.IsValid(id: any): boolean
	return type(id) == "string" and MapInfo.Defs[id] ~= nil
end

return MapInfo

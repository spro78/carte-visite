--[[
	Teams.lua
	Définition des trois équipes et de la chaîne de prédation :
	FOX attrape CHICKEN, CHICKEN attrape SNAKE, SNAKE attrape FOX.
	Utilisé par le serveur ET le client.
]]

local Teams = {}

export type TeamId = "FOX" | "CHICKEN" | "SNAKE"

export type TeamDef = {
	Id: TeamId,
	Display: string, -- nom affiché (majuscules)
	Plural: string, -- pluriel affiché
	Color: Color3, -- couleur d'équipe
	Prey: TeamId, -- l'équipe que l'on attrape
	Predator: TeamId, -- l'équipe qui nous attrape
}

-- Ordre canonique (utilisé pour les affichages et la répartition)
Teams.Order = { "FOX", "CHICKEN", "SNAKE" }

-- Règle affichée au joueur
Teams.Rule = "Catch your prey. Run from your hunter."

Teams.Defs = {
	FOX = {
		Id = "FOX",
		Display = "FOX",
		Plural = "FOXES",
		Color = Color3.fromRGB(235, 125, 40),
		Prey = "CHICKEN",
		Predator = "SNAKE",
	},
	CHICKEN = {
		Id = "CHICKEN",
		Display = "CHICKEN",
		Plural = "CHICKENS",
		Color = Color3.fromRGB(250, 225, 95),
		Prey = "SNAKE",
		Predator = "FOX",
	},
	SNAKE = {
		Id = "SNAKE",
		Display = "SNAKE",
		Plural = "SNAKES",
		-- Violet plutôt que vert : le vert est réservé au contour "proie"
		Color = Color3.fromRGB(140, 85, 215),
		Prey = "FOX",
		Predator = "CHICKEN",
	},
} :: { [string]: TeamDef }

-- Couleurs des contours (Highlight) côté client
Teams.PreyOutlineColor = Color3.fromRGB(60, 230, 90) -- vert : ma proie
Teams.PredatorOutlineColor = Color3.fromRGB(240, 50, 50) -- rouge : mon prédateur

function Teams.Get(id: string?): TeamDef?
	if id == nil then
		return nil
	end
	return Teams.Defs[id]
end

function Teams.IsValid(id: any): boolean
	return type(id) == "string" and Teams.Defs[id] ~= nil
end

function Teams.GetPrey(id: string): TeamId?
	local def = Teams.Defs[id]
	return def and def.Prey or nil
end

function Teams.GetPredator(id: string): TeamId?
	local def = Teams.Defs[id]
	return def and def.Predator or nil
end

-- Vrai si "hunterId" a le droit d'attraper "targetId"
function Teams.CanCatch(hunterId: string?, targetId: string?): boolean
	if hunterId == nil or targetId == nil then
		return false
	end
	local def = Teams.Defs[hunterId]
	return def ~= nil and def.Prey == targetId
end

-- Texte du bandeau de rôle : "You are a FOX - Catch CHICKENS - Avoid SNAKES"
function Teams.RoleBanner(id: string): string
	local def = Teams.Defs[id]
	if not def then
		return Teams.Rule
	end
	local prey = Teams.Defs[def.Prey]
	local predator = Teams.Defs[def.Predator]
	return string.format("You are a %s - Catch %s - Avoid %s", def.Display, prey.Plural, predator.Plural)
end

return Teams

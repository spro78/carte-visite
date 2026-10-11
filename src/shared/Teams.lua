--[[
	Teams.lua
	Définition des trois équipes et de la chaîne de prédation :
	FOX attrape CHICKEN, CHICKEN attrape SNAKE, SNAKE attrape FOX.
	Utilisé par le serveur ET le client.
]]

local Teams = {}

export type TeamDef = {
	Id: string,
	Display: string, -- nom affiché (majuscules)
	Plural: string, -- pluriel affiché
	Color: Color3, -- couleur d'équipe
	DarkColor: Color3, -- variante foncée (bordures, textes)
	Prey: string, -- l'équipe que l'on attrape
	Predator: string, -- l'équipe qui nous attrape
}

-- Ordre canonique (affichages, répartition)
Teams.Order = { "FOX", "CHICKEN", "SNAKE" }

-- Règle affichée au joueur
Teams.Rule = "Catch your prey. Run from your hunter."

local defs: { [string]: TeamDef } = {
	FOX = {
		Id = "FOX",
		Display = "FOX",
		Plural = "FOXES",
		Color = Color3.fromRGB(240, 128, 40),
		DarkColor = Color3.fromRGB(150, 65, 15),
		Prey = "CHICKEN",
		Predator = "SNAKE",
	},
	CHICKEN = {
		Id = "CHICKEN",
		Display = "CHICKEN",
		Plural = "CHICKENS",
		Color = Color3.fromRGB(250, 222, 90),
		DarkColor = Color3.fromRGB(160, 120, 20),
		Prey = "SNAKE",
		Predator = "FOX",
	},
	SNAKE = {
		Id = "SNAKE",
		Display = "SNAKE",
		Plural = "SNAKES",
		-- Violet plutôt que vert : le vert est réservé au contour "proie"
		Color = Color3.fromRGB(145, 90, 220),
		DarkColor = Color3.fromRGB(75, 40, 130),
		Prey = "FOX",
		Predator = "CHICKEN",
	},
}
Teams.Defs = defs

-- Couleurs des contours (Highlight) côté client
Teams.PreyOutlineColor = Color3.fromRGB(60, 235, 95) -- vert : ma proie
Teams.PredatorOutlineColor = Color3.fromRGB(245, 50, 50) -- rouge : mon prédateur
Teams.CarrierOutlineColor = Color3.fromRGB(255, 215, 0) -- or : porteur d'objectif (visible par tous)

function Teams.Get(id: any): TeamDef?
	if type(id) ~= "string" then
		return nil
	end
	return defs[id]
end

function Teams.IsValid(id: any): boolean
	return type(id) == "string" and defs[id] ~= nil
end

function Teams.GetPrey(id: string): string?
	local def = defs[id]
	return def and def.Prey or nil
end

function Teams.GetPredator(id: string): string?
	local def = defs[id]
	return def and def.Predator or nil
end

-- Vrai si "hunterId" a le droit d'attraper "targetId"
function Teams.CanCatch(hunterId: string?, targetId: string?): boolean
	if hunterId == nil or targetId == nil then
		return false
	end
	local def = defs[hunterId]
	return def ~= nil and def.Prey == targetId
end

-- Relation vue depuis "myTeam" : "Prey", "Predator", "Ally" ou nil
function Teams.Relation(myTeam: string?, otherTeam: string?): string?
	if myTeam == nil or otherTeam == nil then
		return nil
	end
	if myTeam == otherTeam then
		return "Ally"
	end
	if Teams.CanCatch(myTeam, otherTeam) then
		return "Prey"
	end
	if Teams.CanCatch(otherTeam, myTeam) then
		return "Predator"
	end
	return nil
end

-- Texte du bandeau de rôle : "You are a FOX - Catch CHICKENS - Avoid SNAKES"
function Teams.RoleBanner(id: string): string
	local def = defs[id]
	if not def then
		return Teams.Rule
	end
	local prey = defs[def.Prey]
	local predator = defs[def.Predator]
	return string.format("You are a %s - Catch %s - Avoid %s", def.Display, prey.Plural, predator.Plural)
end

return Teams

--[[
	ModeInfo.lua
	Modes de jeu proposés au vote (partagé serveur/client). Un mode change la
	règle de la manche ; la capture en triangle, la mise à terre, le portage
	et les zones sûres restent les mêmes partout.
	Une « option » de vote associe un mode et une carte : "Carte/Mode"
	(ex. "TheCarousel/EggRun"). Textes écrits en anglais, traduits par
	Shared/Lang.
]]

local Lang = require(script.Parent.Lang)

local ModeInfo = {}

export type ModeDef = {
	Id: string,
	DisplayName: string,
	Tagline: string, -- une phrase (intro de manche, annonce)
	Rules: { string }, -- trois lignes courtes (carte de vote, aide)
	Goal: number?, -- score à atteindre (nil : pas de score)
	Color: Color3, -- couleur de la carte de vote (jamais une couleur d'équipe)
}

ModeInfo.Defs = {
	Chase = {
		Id = "Chase",
		DisplayName = Lang.T("CHASE"),
		Tagline = Lang.T("Catch your prey, dodge your hunter. Last team standing wins!"),
		Rules = {
			Lang.T("Catch your prey, dodge your hunter."),
			Lang.T("Carry downed teammates home."),
			Lang.T("Last team standing wins."),
		},
		Goal = nil,
		Color = Color3.fromRGB(96, 156, 232),
	},
	EggRun = {
		Id = "EggRun",
		DisplayName = Lang.T("EGG RUN"),
		Tagline = Lang.T("Grab painted eggs and run them home. First to 5 wins!"),
		Rules = {
			Lang.T("Grab a painted egg from a nest."),
			Lang.T("Run it into your camp. Carriers can't catch."),
			Lang.T("First team to 5 eggs wins."),
		},
		Goal = 5,
		Color = Color3.fromRGB(168, 136, 232),
	},
	Carousel = {
		Id = "Carousel",
		DisplayName = Lang.T("CAROUSEL"),
		Tagline = Lang.T("Ride the flying horses: outnumber the others under them to score!"),
		Rules = {
			Lang.T("Three flying horses circle the valley."),
			Lang.T("Outnumber others in a horse's ring."),
			Lang.T("First team to 120 points wins."),
		},
		Goal = 120,
		Color = Color3.fromRGB(234, 96, 112),
	},
	-- Modes des cartes historiques (une seule règle par carte)
	GoldenEgg = {
		Id = "GoldenEgg",
		DisplayName = Lang.T("GOLDEN EGG"),
		Tagline = Lang.T("Bring the golden egg home. First team to 3 wins!"),
		Rules = {
			Lang.T("One golden egg spawns in the middle."),
			Lang.T("Carry it to your camp to score."),
			Lang.T("First team to 3 eggs wins."),
		},
		Goal = 3,
		Color = Color3.fromRGB(120, 190, 95),
	},
	Raid = {
		Id = "Raid",
		DisplayName = Lang.T("RAID"),
		Tagline = Lang.T("Steal eggs from your prey's base. Most eggs wins!"),
		Rules = {
			Lang.T("Each camp keeps a pile of eggs."),
			Lang.T("Steal from your prey's camp, bring it home."),
			Lang.T("Most eggs when time runs out wins."),
		},
		Goal = nil,
		Color = Color3.fromRGB(215, 150, 90),
	},
	ThePack = {
		Id = "ThePack",
		DisplayName = Lang.T("THE PACK"),
		Tagline = Lang.T("Pure conversion. Last team standing wins!"),
		Rules = {
			Lang.T("No objective: only the chase."),
			Lang.T("Caught players fall: carry teammates home."),
			Lang.T("Last team standing wins (or biggest team)."),
		},
		Goal = nil,
		Color = Color3.fromRGB(80, 140, 120),
	},
} :: { [string]: ModeDef }

function ModeInfo.Get(id: string?): ModeDef?
	if id == nil then
		return nil
	end
	return ModeInfo.Defs[id]
end

-- "Carte/Mode" -> carte, mode
function ModeInfo.Split(option: any): (string?, string?)
	if type(option) ~= "string" then
		return nil, nil
	end
	local mapId, modeId = string.match(option, "^([%w_]+)/([%w_]+)$")
	return mapId, modeId
end

function ModeInfo.Option(mapId: string, modeId: string): string
	return mapId .. "/" .. modeId
end

return ModeInfo

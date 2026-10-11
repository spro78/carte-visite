--[[
	_Template.lua  (ignoré par MapRegistry : son nom commence par "_")

	AJOUTER UNE MAP EN 4 ÉTAPES
	1. Copier ce fichier dans src/server/Maps/<MonId>.lua et changer Map.Id.
	2. Nom affiché, mode et phrase : une entrée <MonId> dans src/shared/MapInfo.lua.
	3. Disposition et équilibrage : une entrée Config.Maps.<MonId> dans
	   src/shared/Config.lua (voir ci-dessous).
	4. Décor : remplir THEME et Map.Lighting, puis construire les lieux propres
	   à la map dans Map.Build.
	C'est tout : la map entre automatiquement dans le vote et la rotation.

	OÙ SE TROUVE CHAQUE INFORMATION D'UNE MAP
	  Nom, mode, phrase, couleur ......... Shared/MapInfo.lua
	  Limites (taille de la zone) ........ Config.Maps.<Id>.GroundSize (+ BoundaryHeight)
	  Bases des trois équipes ............ Config.Maps.<Id>.BaseRadius / BasePadSize / BaseAngles
	  Points de départ ................... générés par MapBase (8 par camp, tournés vers le centre)
	  Décor commun (relief, sol, chemins,
	    clôture, arbres, style des camps) . THEME ci-dessous (MapBase.ArenaTheme)
	  Ambiance (heure, brume, couleurs) .. Map.Lighting (restaurée en fin de manche)
	  Lieux, mécanisme, mode de jeu ...... ce fichier

	EXEMPLE D'ENTRÉE DANS Config.Maps
	  MyNewMap = {
	      GroundSize = 300,      -- zone de jeu de 300 x 300 studs
	      BaseRadius = 105,      -- camps à 105 studs du centre
	      BasePadSize = 36,      -- plateforme de camp de 36 x 36
	      BaseAngles = { FOX = 90, CHICKEN = 210, SNAKE = 330 }, -- optionnel
	      -- ... valeurs du mode
	  },

	FORMAT COMMUN (vérifié par MapRegistry)
	Map.Id                       -> string, identique à la clé MapInfo
	Map.Build(origin, context)   -> construit toute la géométrie dans un dossier
	Map.GetSpawns(teamId)        -> liste de CFrame pour l'équipe
	Map.StartMode(context)       -> lance la logique du mode (objectif, mécanisme)
	Map.StopMode()               -> arrête la logique (fin de manche)
	Map.Cleanup()                -> détruit la géométrie (le terrain est effacé par RoundService)
	Optionnels : Map.Lighting, Map.OnCapture, Map.OnActorRemoved, Map.ResolveTimeUp,
	             Map.GetBotGoal, Map.IsCarrier (voir Shared/Types.lua)

	Le "context" (voir Shared/Types.lua) donne accès à :
	  context.GetActors()            participants de la manche (joueurs + bots)
	  context.GetTeam(actor)         équipe d'un acteur
	  context.AddScore(teamId, n)    ajoute des points au mode
	  context.GetScore(teamId)
	  context.Announce(text, color)  annonce courte à tous
	  context.EndRound(teamId, reason)  termine la manche (objectif atteint)
	  context.IsRoundActive()

	BOÎTES À OUTILS
	  MapBase    : arène, camps, cachettes (BuildTallGrass, BuildBush, BuildBurrow),
	               mécanismes tournants (NewSpinner, StartSpinner), Polar()
	  Util/Props : arbres, maisons, toits, clôtures, rochers, mobilier...
	  Util/TerrainKit : relief en Terrain (collines, mesas, falaises, mares, chemins)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local MapBase = require(script.Parent.MapBase)
local Props = require(script.Parent.Parent.Util.Props)

local Map = {}
Map.Id = "MyNewMap"

-- Ambiance pendant la manche (propriétés de Lighting + effets)
Map.Lighting = {
	ClockTime = 14,
	Atmosphere = { Density = 0.2, Haze = 0.8 },
}

-- Décor commun construit par MapBase.BuildArena
local THEME: MapBase.ArenaTheme = {
	Seed = 1, -- même décor d'une manche à l'autre
	Floor = Enum.Material.Grass,
	Patches = { Enum.Material.LeafyGrass },
	Path = Enum.Material.Ground,
	RingPath = 80, -- anneau de course autour du centre (nil = aucun)
	Valley = { Ground = Enum.Material.Grass, Hill = Enum.Material.Grass, Rock = Enum.Material.Rock },
	Perimeter = "Fence", -- "Fence" | "Picket" | "Hedge" | "StoneWall" | "Rocks" | "None"
	Trees = { "Round", "Green" },
	TreeCount = 60,
}

local folder: Folder? = nil
local bases: { [string]: MapBase.Base }? = nil
local _running = false

function Map.Build(origin: Vector3, _context)
	local cfg = Config.Maps[Map.Id]
	local f = MapBase.NewFolder("Map_" .. Map.Id)
	-- Sol, relief, limites, clôture, trois camps, chemins, arbres
	bases = MapBase.BuildArena(f, origin, cfg, THEME)
	-- Lieux propres à la map : un repère par secteur entre deux camps (30°, 150°, 270°)
	Props.Well(f, MapBase.Polar(origin, 270, 120))
	-- Cachettes
	MapBase.BuildBush(f, MapBase.Polar(origin, 30, 90), 9)
	f.Parent = workspace
	folder = f
end

function Map.GetSpawns(teamId: string): { CFrame }
	assert(bases, "Map non construite")
	return bases[teamId].Spawns
end

function Map.StartMode(_context)
	_running = true
	-- Boucle du mode ici, en vérifiant "running" et context.IsRoundActive()
end

function Map.StopMode()
	_running = false
end

function Map.Cleanup()
	_running = false
	if folder then
		folder:Destroy()
		folder = nil
	end
	bases = nil
end

return Map

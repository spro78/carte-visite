--[[
	_Template.lua  (ignoré par MapRegistry : son nom commence par "_")

	COMMENT AJOUTER UNE MAP
	1. Copier ce fichier dans src/server/Maps/<MonId>.lua
	2. Ajouter une entrée <MonId> dans src/shared/MapInfo.lua (nom, mode, phrase)
	3. Ajouter ses valeurs d'équilibrage dans Config.Maps.<MonId>
	C'est tout : la map entre automatiquement dans le vote.

	FORMAT COMMUN
	Map.Id                       -> string, identique à la clé MapInfo
	Map.Build(origin, context)   -> construit toute la géométrie dans un dossier
	Map.GetSpawns(teamId)        -> liste de CFrame pour l'équipe
	Map.StartMode(context)       -> lance la logique du mode (objectif, mécanisme)
	Map.StopMode()               -> arrête la logique (fin de manche)
	Map.Cleanup()                -> détruit toute la géométrie

	Le "context" (voir Shared/Types.lua) donne accès à :
	  context.GetActors()            participants de la manche (joueurs + bots)
	  context.GetTeam(actor)         équipe d'un acteur
	  context.AddScore(teamId, n)    ajoute des points au mode
	  context.GetScore(teamId)
	  context.Announce(text, color)  annonce courte à tous
	  context.EndRound(teamId, reason)  termine la manche (objectif atteint)
	  context.IsRoundActive()
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local MapBase = require(script.Parent.MapBase)

local Map = {}
Map.Id = "MyNewMap"

local THEME: MapBase.ArenaTheme = {
	Seed = 1,
	Floor = Enum.Material.Grass,
	Path = Enum.Material.Ground,
	Valley = { Ground = Enum.Material.Grass, Hill = Enum.Material.Grass, Rock = Enum.Material.Rock },
	Perimeter = "Fence",
}

local folder: Folder? = nil
local bases = nil
local _running = false

function Map.Build(origin: Vector3, context)
	local cfg = Config.Maps[Map.Id]
	local f = MapBase.NewFolder("Map_" .. Map.Id)
	bases = MapBase.BuildArena(f, origin, cfg, THEME)
	MapBase.BuildCentralPad(f, origin, 20, Color3.fromRGB(200, 200, 200))
	f.Parent = workspace
	folder = f
end

function Map.GetSpawns(teamId: string): { CFrame }
	assert(bases, "Map non construite")
	return bases[teamId].Spawns
end

function Map.StartMode(context)
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

--[[
	Chase.lua - mode CHASE (poursuite classique)
	Aucun objectif sur la carte : on attrape sa proie, on échappe à son
	chasseur. Un joueur attrapé tombe à terre ; un coéquipier peut le porter
	jusqu'à son camp, sinon il rejoint l'équipe de son chasseur (RescueService).
	Fin de manche (RoundService) : dernière équipe debout, sinon, au chrono,
	l'équipe la plus nombreuse.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Types = require(Shared.Types)

type MapContext = Types.MapContext

local Chase = {}

function Chase.Start(ctx: MapContext, _layout: any)
	-- Pas de score : le HUD affiche la taille des équipes
	ctx.SetScoreInfo(nil, nil)
end

function Chase.Stop() end

function Chase.DebugState()
	return { Mode = "Chase" }
end

return Chase

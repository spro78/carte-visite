--[[
	SafeZoneService.lua
	Zones sûres des camps (Config.SafeZone, géométrie dans MapBase) :
	  - un défenseur dans la zone de SON camp ne peut être ni attrapé ni mordu
	    (CaptureService et AbilityService interrogent IsSafe au moment de l'action) ;
	  - les adversaires peuvent entrer dans la zone (vol d'œufs du Raid), mais
	    n'y sont pas protégés ;
	  - c'est aussi là qu'un coéquipier porté se relève (RescueService).
	L'attribut "SafeZone" du personnage est tenu à jour pour l'interface (pastille
	du HUD, étiquette au-dessus de la tête) : il n'est qu'un reflet, la règle est
	toujours vérifiée ici, à partir de la position actuelle.
]]

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Types = require(Shared.Types)
local ActorService = require(script.Parent.ActorService)
local RoundState = require(script.Parent.RoundState)
local MapBase = require(script.Parent.Parent.Maps.MapBase)

type Actor = Types.Actor

local SafeZoneService = {}

local accumulator = 0

-- Camp d'une équipe sur la carte en cours (nil hors manche)
function SafeZoneService.GetBase(teamId: string?): MapBase.Base?
	local bases = MapBase.ActiveBases
	if not bases or not teamId then
		return nil
	end
	return bases[teamId]
end

-- Vrai si la position est dans la zone sûre du camp de cette équipe
function SafeZoneService.Contains(teamId: string?, position: Vector3): boolean
	local base = SafeZoneService.GetBase(teamId)
	return base ~= nil and MapBase.IsInSafeZone(base, position)
end

-- Vrai si l'acteur est protégé par la zone de son camp (règle serveur)
function SafeZoneService.IsSafe(actor: Actor): boolean
	if not RoundState.IsInRound() or not actor.Team then
		return false
	end
	local character = actor.Character
	if not character or character:GetAttribute("Downed") == true then
		return false
	end
	local position = ActorService.GetPosition(actor)
	return position ~= nil and SafeZoneService.Contains(actor.Team, position)
end

local function update()
	for _, actor in ActorService.GetAll() do
		local character = actor.Character
		if character then
			local safe = RoundState.IsParticipant(actor) and SafeZoneService.IsSafe(actor)
			if (character:GetAttribute("SafeZone") == true) ~= safe then
				character:SetAttribute("SafeZone", safe or nil)
			end
		end
	end
end

function SafeZoneService.Init()
	RunService.Heartbeat:Connect(function(dt)
		accumulator += dt
		if accumulator >= Config.SafeZone.CheckInterval then
			accumulator = 0
			update()
		end
	end)
end

-- Pour les tests : mise à jour immédiate des attributs
SafeZoneService.Update = update

return SafeZoneService

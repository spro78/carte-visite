--[[
	RoundState.lua
	État de manche partagé entre services serveur (évite les require circulaires).
	Seul RoundService écrit ici ; les autres services lisent.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Types = require(Shared.Types)
local ActorService = require(script.Parent.ActorService)

type Actor = Types.Actor

local RoundState = {
	Phase = "Waiting" :: string,
	MapId = nil :: string?,
	Map = nil :: any, -- module de la map en cours
	Participants = {} :: { [string]: boolean }, -- ids d'acteurs engagés dans la manche
}

-- Vrai pendant la manche jouée (après le compte à rebours)
function RoundState.IsActive(): boolean
	return RoundState.Phase == "Round"
end

-- Vrai pendant le compte à rebours ou la manche
function RoundState.IsInRound(): boolean
	return RoundState.Phase == "Countdown" or RoundState.Phase == "Round"
end

function RoundState.IsParticipant(actor: Actor): boolean
	return RoundState.Participants[actor.Id] == true
end

-- Participants encore présents
function RoundState.GetParticipants(): { Actor }
	local list = {}
	for id in RoundState.Participants do
		local actor = ActorService.Get(id)
		if actor then
			table.insert(list, actor)
		end
	end
	return list
end

-- Participants vivants avec une équipe et un personnage
function RoundState.GetActiveParticipants(): { Actor }
	local list = {}
	for id in RoundState.Participants do
		local actor = ActorService.Get(id)
		if actor and actor.Team and ActorService.IsAlive(actor) then
			table.insert(list, actor)
		end
	end
	return list
end

return RoundState

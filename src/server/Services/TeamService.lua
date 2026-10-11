--[[
	TeamService.lua
	Attribution et suivi des équipes des acteurs (joueurs et bots).
	L'équipe est stockée :
	  - dans actor.Team (source de vérité serveur),
	  - dans l'attribut "Team" du personnage (lu par les clients pour les contours),
	  - dans l'attribut "Team" du Player (bandeau de rôle) et dans le service Teams
	    de Roblox (couleur dans la liste des joueurs).
]]

local RobloxTeams = game:GetService("Teams")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Teams = require(Shared.Teams)
local Types = require(Shared.Types)
local AnimalAppearance = require(script.Parent.AnimalAppearance)
local ActorService = require(script.Parent.ActorService)

type Actor = Types.Actor

local TeamService = {}

local robloxTeamObjects: { [string]: Team } = {}

function TeamService.Init()
	for _, id in Teams.Order do
		local def = Teams.Get(id)
		assert(def, "Équipe inconnue : " .. id)
		local team = Instance.new("Team")
		team.Name = def.Display
		team.TeamColor = BrickColor.new(def.Color)
		team.AutoAssignable = false
		team.Parent = RobloxTeams
		robloxTeamObjects[id] = team
	end

	-- Un personnage qui (ré)apparaît reprend l'apparence de son équipe
	ActorService.CharacterAdded:Connect(function(actor: Actor, character: Model)
		character:SetAttribute("Team", actor.Team)
		AnimalAppearance.Apply(character, actor.Team)
	end)
end

-- Définit l'équipe d'un acteur (nil = aucune équipe, lobby/spectateur).
function TeamService.SetTeam(actor: Actor, teamId: string?)
	if teamId ~= nil then
		assert(Teams.IsValid(teamId), "Équipe invalide : " .. tostring(teamId))
	end
	actor.Team = teamId
	local player = actor.Player
	if player then
		player:SetAttribute("Team", teamId)
		if teamId then
			player.Neutral = false
			player.Team = robloxTeamObjects[teamId]
		else
			player.Team = nil
			player.Neutral = true
		end
	end
	local character = actor.Character
	if character then
		character:SetAttribute("Team", teamId)
		AnimalAppearance.Apply(character, teamId)
	end
end

function TeamService.GetTeam(actor: Actor): string?
	return actor.Team
end

-- Mélange de Fisher-Yates
local function shuffle<T>(list: { T }): { T }
	local copy = table.clone(list)
	for i = #copy, 2, -1 do
		local j = math.random(i)
		copy[i], copy[j] = copy[j], copy[i]
	end
	return copy
end

-- Répartition équilibrée : mélange puis tour de rôle à partir d'une équipe au hasard.
function TeamService.AssignBalanced(actorList: { Actor })
	local offset = math.random(#Teams.Order) - 1
	for index, actor in shuffle(actorList) do
		local teamIndex = ((index - 1 + offset) % #Teams.Order) + 1
		TeamService.SetTeam(actor, Teams.Order[teamIndex])
	end
end

-- Équipe la moins nombreuse (égalité tranchée au hasard).
function TeamService.GetSmallestTeam(actorList: { Actor }): string
	local counts = TeamService.GetCounts(actorList)
	local best, bestCount = {}, math.huge
	for _, id in Teams.Order do
		if counts[id] < bestCount then
			best, bestCount = { id }, counts[id]
		elseif counts[id] == bestCount then
			table.insert(best, id)
		end
	end
	return best[math.random(#best)]
end

-- Nombre d'acteurs par équipe.
function TeamService.GetCounts(actorList: { Actor }): { [string]: number }
	local counts = {}
	for _, id in Teams.Order do
		counts[id] = 0
	end
	for _, actor in actorList do
		if actor.Team and counts[actor.Team] then
			counts[actor.Team] += 1
		end
	end
	return counts
end

-- Équipes ayant au moins un membre.
function TeamService.GetNonEmptyTeams(actorList: { Actor }): { string }
	local counts = TeamService.GetCounts(actorList)
	local result = {}
	for _, id in Teams.Order do
		if counts[id] > 0 then
			table.insert(result, id)
		end
	end
	return result
end

-- Équipe la plus nombreuse ; nil en cas d'égalité.
function TeamService.GetLargestTeam(actorList: { Actor }): string?
	local counts = TeamService.GetCounts(actorList)
	local best, bestCount, tie = nil, -1, false
	for _, id in Teams.Order do
		if counts[id] > bestCount then
			best, bestCount, tie = id, counts[id], false
		elseif counts[id] == bestCount then
			tie = true
		end
	end
	if tie then
		return nil
	end
	return best
end

-- Retire tous les acteurs de leur équipe.
function TeamService.ClearAll()
	for _, actor in ActorService.GetAll() do
		TeamService.SetTeam(actor, nil)
	end
end

return TeamService

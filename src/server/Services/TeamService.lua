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

-- Historique des rôles joués par chaque joueur pendant la session (clé :
-- UserId pour un joueur, Id pour un bot) : sert à faire tourner les animaux
local history: { [any]: { [string]: number } } = {}
local lastTeam: { [any]: string } = {}

local function historyKey(actor: Actor): any
	return actor.Player and actor.Player.UserId or actor.Id
end

-- Répartition équilibrée ET tournante :
--   - tailles d'équipes égales à un près (les places en plus tombent au hasard) ;
--   - chacun va de préférence dans l'équipe qu'il a le moins jouée, et jamais
--     deux fois de suite la même s'il y a le choix ; le hasard départage.
-- Au fil des manches, tout le monde joue renard, poule et vipère.
function TeamService.AssignBalanced(actorList: { Actor })
	local n = #actorList
	local teamCount = #Teams.Order
	local base = n // teamCount -- taille minimale d'une équipe
	local extra = n % teamCount -- équipes qui auront une place de plus
	-- Coût d'une équipe pour un joueur : déjà jouée (x10), jouée la manche
	-- précédente (+5)
	local function cost(actor: Actor, team: string): number
		local key = historyKey(actor)
		local played = history[key] or {}
		return (played[team] or 0) * 10 + (lastTeam[key] == team and 5 or 0)
	end
	-- 1. Répartition gloutonne (ordre au hasard), tailles égales à un près
	local filled: { [string]: number } = {}
	for _, id in Teams.Order do
		filled[id] = 0
	end
	local bigTeams = 0
	local function open(id: string): boolean
		return filled[id] < base or (filled[id] == base and bigTeams < extra)
	end
	local assigned: { [Actor]: string } = {}
	local order = shuffle(actorList)
	for _, actor in order do
		local best, bestScore = nil, math.huge
		for _, id in shuffle(Teams.Order) do
			if open(id) then
				local score = cost(actor, id)
				if score < bestScore then
					best, bestScore = id, score
				end
			end
		end
		local team = best or Teams.Order[1]
		if filled[team] == base then
			bigTeams += 1
		end
		filled[team] += 1
		assigned[actor] = team
	end
	-- 2. Échanges deux à deux tant qu'ils réduisent le coût total (les tailles
	-- ne changent pas) : chacun change d'animal dès que c'est possible
	local improved = true
	local guard = 0
	while improved and guard < 50 do
		improved = false
		guard += 1
		for i = 1, #order do
			for j = i + 1, #order do
				local a, b = order[i], order[j]
				local ta, tb = assigned[a], assigned[b]
				if ta ~= tb and cost(a, tb) + cost(b, ta) < cost(a, ta) + cost(b, tb) then
					assigned[a], assigned[b] = tb, ta
					improved = true
				end
			end
		end
	end
	-- 3. Application et mémoire des rôles joués
	for _, actor in order do
		local team = assigned[actor]
		local key = historyKey(actor)
		local played = history[key] or {}
		TeamService.SetTeam(actor, team)
		history[key] = played
		played[team] = (played[team] or 0) + 1
		lastTeam[key] = team
	end
end

-- Pour les tests : rôles joués par un acteur depuis le début de la session
function TeamService.GetHistory(actor: Actor): { [string]: number }
	return history[historyKey(actor)] or {}
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

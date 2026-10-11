--[[
	TeamService.lua
	Attribution et suivi des équipes. L'équipe d'un joueur est stockée dans
	l'attribut "Team" du Player (répliqué automatiquement au client) et
	reflétée dans le service Teams de Roblox (couleur dans la liste des joueurs).
]]

local Players = game:GetService("Players")
local RobloxTeams = game:GetService("Teams")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Teams = require(Shared.Teams)
local AnimalAppearance = require(script.Parent.AnimalAppearance)

local TeamService = {}

TeamService.Attribute = "Team"

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

	local function onPlayerAdded(player: Player)
		player.Neutral = true
	end
	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in Players:GetPlayers() do
		onPlayerAdded(player)
	end
end

-- Définit l'équipe d'un joueur (nil = aucune équipe, lobby/spectateur).
function TeamService.SetTeam(player: Player, teamId: string?)
	if teamId ~= nil then
		assert(Teams.IsValid(teamId), "Équipe invalide : " .. tostring(teamId))
	end
	player:SetAttribute(TeamService.Attribute, teamId)
	if teamId then
		player.Team = robloxTeamObjects[teamId]
		player.Neutral = false
	else
		player.Neutral = true
		player.Team = nil
	end
	if player.Character then
		AnimalAppearance.Apply(player.Character, teamId)
	end
end

function TeamService.GetTeam(player: Player): string?
	local value = player:GetAttribute(TeamService.Attribute)
	if Teams.IsValid(value) then
		return value :: string
	end
	return nil
end

-- Répartition équilibrée : mélange aléatoire puis tour de rôle
-- en partant d'une équipe tirée au hasard.
function TeamService.AssignBalanced(players: { Player })
	local shuffled = table.clone(players)
	for i = #shuffled, 2, -1 do
		local j = math.random(i)
		shuffled[i], shuffled[j] = shuffled[j], shuffled[i]
	end
	local offset = math.random(#Teams.Order) - 1
	for index, player in shuffled do
		local teamIndex = ((index - 1 + offset) % #Teams.Order) + 1
		TeamService.SetTeam(player, Teams.Order[teamIndex])
	end
end

-- Nombre de joueurs par équipe parmi une liste donnée.
function TeamService.GetCounts(players: { Player }): { [string]: number }
	local counts = {}
	for _, id in Teams.Order do
		counts[id] = 0
	end
	for _, player in players do
		local team = TeamService.GetTeam(player)
		if team then
			counts[team] += 1
		end
	end
	return counts
end

-- Liste des équipes ayant au moins un membre parmi les joueurs donnés.
function TeamService.GetNonEmptyTeams(players: { Player }): { string }
	local counts = TeamService.GetCounts(players)
	local result = {}
	for _, id in Teams.Order do
		if counts[id] > 0 then
			table.insert(result, id)
		end
	end
	return result
end

-- Équipe la plus nombreuse ; retourne nil en cas d'égalité.
function TeamService.GetLargestTeam(players: { Player }): string?
	local counts = TeamService.GetCounts(players)
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

-- Retire tout le monde de toutes les équipes.
function TeamService.ClearAll()
	for _, player in Players:GetPlayers() do
		TeamService.SetTeam(player, nil)
	end
end

return TeamService

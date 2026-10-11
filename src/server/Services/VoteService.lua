--[[
	VoteService.lua
	Vote de map pendant l'intermission. Deux moyens de voter :
	  - marcher sur une plaque du lobby (Touched, côté serveur),
	  - cliquer sur un bouton de l'interface (RemoteEvent VoteMap).
	Toute intention est validée ici : phase active, mapId candidat, type string.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared.Remotes)
local MapInfo = require(Shared.MapInfo)

local VoteService = {}

local candidates: { string } = {}
local votes: { [Player]: string } = {}
local active = false
local lobby = nil -- LobbyBuilder

local function refreshLobby()
	if lobby then
		lobby.SetVoteCounts(VoteService.GetCounts())
	end
end

function VoteService.Init(lobbyBuilder)
	lobby = lobbyBuilder

	Remotes.Get("VoteMap").OnServerEvent:Connect(function(player: Player, mapId: any)
		VoteService.CastVote(player, mapId)
	end)

	lobby.OnVotePlateTouched(function(player: Player, index: number)
		local mapId = candidates[index]
		if mapId then
			VoteService.CastVote(player, mapId)
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		if votes[player] then
			votes[player] = nil
			refreshLobby()
		end
	end)
end

function VoteService.StartVote(mapIds: { string })
	candidates = table.clone(mapIds)
	votes = {}
	active = true
	if lobby then
		lobby.SetVoteCandidates(candidates)
	end
	refreshLobby()
end

function VoteService.EndVote()
	active = false
end

function VoteService.IsActive(): boolean
	return active
end

-- Enregistre un vote. Toutes les vérifications sont faites ici.
function VoteService.CastVote(player: Player, mapId: any)
	if not active then
		return
	end
	if typeof(mapId) ~= "string" or not MapInfo.IsValid(mapId) then
		return
	end
	if not table.find(candidates, mapId) then
		return
	end
	if votes[player] == mapId then
		return
	end
	votes[player] = mapId
	refreshLobby()
end

function VoteService.GetCandidates(): { string }
	return candidates
end

function VoteService.GetCounts(): { [string]: number }
	local counts = {}
	for _, id in candidates do
		counts[id] = 0
	end
	for _, id in votes do
		if counts[id] ~= nil then
			counts[id] += 1
		end
	end
	return counts
end

function VoteService.GetPlayerVote(player: Player): string?
	return votes[player]
end

-- Map gagnante : la plus votée, égalité tranchée au hasard.
function VoteService.GetWinner(): string?
	if #candidates == 0 then
		return nil
	end
	local counts = VoteService.GetCounts()
	local best = {}
	local bestCount = -1
	for _, id in candidates do
		local n = counts[id] or 0
		if n > bestCount then
			best = { id }
			bestCount = n
		elseif n == bestCount then
			table.insert(best, id)
		end
	end
	return best[math.random(#best)]
end

-- Map en tête pour l'affichage (nil si aucune voix ou égalité stricte à 0)
function VoteService.GetLeader(): string?
	local counts = VoteService.GetCounts()
	local leader, leaderCount = nil, 0
	for _, id in candidates do
		if (counts[id] or 0) > leaderCount then
			leader, leaderCount = id, counts[id]
		end
	end
	return leader
end

return VoteService

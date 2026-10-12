--[[
	VoteService.lua
	Vote de la prochaine manche pendant l'intermission. On vote pour une
	OPTION : un mode de jeu sur une carte ("Carte/Mode", Shared/ModeInfo).
	Deux moyens de voter :
	  - marcher sur une plaque du lobby (Touched, côté serveur),
	  - cliquer sur une carte de l'interface (RemoteEvent VoteMap).
	Règle (affichée aux joueurs) : une voix par joueur, on peut changer d'avis ;
	l'option la plus votée gagne ; en cas d'égalité (ou sans vote), le mode
	joué il y a le plus longtemps passe (rotation), puis le hasard.
	Toute intention est validée ici : phase active, option candidate, type.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared.Remotes)
local ModeInfo = require(Shared.ModeInfo)
local MapInfo = require(Shared.MapInfo)

local MapRegistry = require(script.Parent.MapRegistry)

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

local function isValidOption(option: any): boolean
	local mapId, modeId = ModeInfo.Split(option)
	return mapId ~= nil and MapInfo.IsValid(mapId) and ModeInfo.Get(modeId) ~= nil
end

function VoteService.Init(lobbyBuilder)
	lobby = lobbyBuilder

	Remotes.Get("VoteMap").OnServerEvent:Connect(function(player: Player, option: any)
		VoteService.CastVote(player, option)
	end)

	lobby.OnVotePlateTouched(function(player: Player, index: number)
		local option = candidates[index]
		if option then
			VoteService.CastVote(player, option)
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		if votes[player] then
			votes[player] = nil
			refreshLobby()
		end
	end)
end

function VoteService.StartVote(options: { string })
	candidates = table.clone(options)
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
function VoteService.CastVote(player: Player, option: any)
	if not active then
		return
	end
	if typeof(option) ~= "string" or not isValidOption(option) then
		return
	end
	if not table.find(candidates, option) then
		return
	end
	if votes[player] == option then
		return
	end
	votes[player] = option
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

-- Tous les joueurs présents et leur choix (nil : pas encore voté), par nom
function VoteService.GetRoster(): { { Name: string, UserId: number, Vote: string? } }
	local roster = {}
	for _, player in Players:GetPlayers() do
		table.insert(roster, { Name = player.DisplayName ~= "" and player.DisplayName or player.Name, UserId = player.UserId, Vote = votes[player] })
	end
	table.sort(roster, function(a, b)
		return a.Name:lower() < b.Name:lower()
	end)
	return roster
end

-- Option gagnante : la plus votée ; en cas d'égalité (ou sans vote), le mode
-- qui attend son tour depuis le plus longtemps (rotation), puis la carte, puis le hasard.
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
	local mostStale = {}
	local staleness = -1
	for _, id in best do
		local mapId, modeId = ModeInfo.Split(id)
		local st = (modeId and math.min(MapRegistry.ModeStaleness(modeId), 1e6) or 0) * 1000 + (mapId and math.min(MapRegistry.Staleness(mapId), 999) or 0)
		if st > staleness then
			mostStale = { id }
			staleness = st
		elseif st == staleness then
			table.insert(mostStale, id)
		end
	end
	return mostStale[math.random(#mostStale)]
end

-- Option en tête pour l'affichage (nil si aucune voix ou égalité stricte à 0)
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

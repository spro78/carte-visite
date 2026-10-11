--[[
	LeaderboardService.lua
	Classements globaux (OrderedDataStore) affichés sur les écrans du lobby :
	victoires et captures. Rafraîchis toutes les LeaderboardRefreshSeconds.
	Les valeurs sont écrites par DataService à chaque sauvegarde.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local DataService = require(script.Parent.DataService)

local LeaderboardService = {}

local nameCache: { [number]: string } = {}

local function nameOf(userId: number): string
	if nameCache[userId] then
		return nameCache[userId]
	end
	local player = Players:GetPlayerByUserId(userId)
	if player then
		nameCache[userId] = player.DisplayName
		return player.DisplayName
	end
	local ok, name = pcall(function()
		return Players:GetNameFromUserIdAsync(userId)
	end)
	local result = ok and name or ("Player " .. userId)
	nameCache[userId] = result
	return result
end

local function fetch(store: OrderedDataStore?): { { any } }?
	if not store then
		return nil
	end
	local ok, pages = pcall(function()
		return store:GetSortedAsync(false, Config.Lobby.LeaderboardSize)
	end)
	if not ok or not pages then
		return nil
	end
	local entries = {}
	for _, item in pages:GetCurrentPage() do
		local userId = tonumber(item.key)
		if userId and type(item.value) == "number" and item.value > 0 then
			table.insert(entries, { nameOf(userId), item.value })
		end
	end
	return entries
end

function LeaderboardService.Refresh(lobby: any)
	local winsStore, capturesStore = DataService.GetLeaderboardStores()
	local wins = fetch(winsStore)
	local captures = fetch(capturesStore)
	if wins then
		lobby.SetLeaderboard("Wins", wins)
	else
		lobby.SetLeaderboard("Wins", {})
	end
	if captures then
		lobby.SetLeaderboard("Captures", captures)
	else
		lobby.SetLeaderboard("Captures", {})
	end
end

function LeaderboardService.Init(lobby: any)
	task.spawn(function()
		task.wait(5)
		while true do
			if DataService.IsStoreAvailable() then
				LeaderboardService.Refresh(lobby)
			else
				lobby.SetLeaderboard("Wins", { { "Leaderboards need", "" }, { "API access enabled", "" } })
				lobby.SetLeaderboard("Captures", { { "Leaderboards need", "" }, { "API access enabled", "" } })
			end
			task.wait(Config.Lobby.LeaderboardRefreshSeconds)
		end
	end)
end

return LeaderboardService

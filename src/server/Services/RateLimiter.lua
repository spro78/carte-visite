--[[
	RateLimiter.lua
	Limite le nombre d'intentions qu'un joueur peut envoyer par seconde,
	pour chaque RemoteEvent. Protège le serveur contre le spam.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)

local RateLimiter = {}

local buckets: { [Player]: { [string]: { count: number, windowStart: number } } } = {}

Players.PlayerRemoving:Connect(function(player)
	buckets[player] = nil
end)

-- Retourne true si l'intention est acceptée.
function RateLimiter.Allow(player: Player, key: string, maxPerSecond: number?): boolean
	local limit = maxPerSecond or Config.Security.RemoteRateLimit
	local now = os.clock()
	local perPlayer = buckets[player]
	if not perPlayer then
		perPlayer = {}
		buckets[player] = perPlayer
	end
	local bucket = perPlayer[key]
	if not bucket or now - bucket.windowStart >= 1 then
		perPlayer[key] = { count = 1, windowStart = now }
		return true
	end
	bucket.count += 1
	return bucket.count <= limit
end

return RateLimiter

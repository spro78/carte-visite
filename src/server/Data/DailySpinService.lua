--[[
	DailySpinService.lua
	Roue de récompense du lobby : gratuite toutes les Config.DailySpin.CooldownHours
	heures. Le serveur tire la récompense (pondérée), l'attribue, puis fait
	tourner la roue jusqu'au bon segment (animation vue par tous).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Remotes = require(Shared.Remotes)
local DataService = require(script.Parent.DataService)

local DailySpinService = {}

local busy: { [Player]: boolean } = {}

local function pickReward(): (number, any)
	local total = 0
	for _, reward in Config.DailySpin.Rewards do
		total += reward.Weight
	end
	local roll = math.random() * total
	for index, reward in Config.DailySpin.Rewards do
		roll -= reward.Weight
		if roll <= 0 then
			return index, reward
		end
	end
	return 1, Config.DailySpin.Rewards[1]
end

local function formatWait(seconds: number): string
	local h = math.floor(seconds / 3600)
	local m = math.floor((seconds % 3600) / 60)
	if h > 0 then
		return string.format("%dh %02dm", h, m)
	end
	return string.format("%dm", math.max(1, m))
end

function DailySpinService.Spin(player: Player, lobby: any)
	if busy[player] then
		return
	end
	local profile = DataService.Get(player)
	if not profile then
		return
	end
	local now = os.time()
	local nextAt = profile.LastSpin + Config.DailySpin.CooldownHours * 3600
	if now < nextAt then
		Remotes.Get("Notify"):FireClient(player, "Next free spin in " .. formatWait(nextAt - now), true)
		return
	end
	busy[player] = true
	local index, reward = pickReward()
	profile.LastSpin = now
	if reward.Kind == "Coins" then
		profile.Coins += reward.Amount
	elseif reward.Kind == "Consumable" and profile.Consumables[reward.Item] ~= nil then
		profile.Consumables[reward.Item] = math.min(Config.Shop.MaxConsumableStack, profile.Consumables[reward.Item] + reward.Amount)
	end
	DataService.MarkChanged(player)
	if lobby and lobby.SpinWheel then
		lobby.SpinWheel(index, Config.DailySpin.SpinSeconds)
	end
	task.delay(Config.DailySpin.SpinSeconds, function()
		busy[player] = nil
		if player.Parent then
			Remotes.Get("Notify"):FireClient(player, "Daily Spin: you won " .. reward.Label .. "!", false)
			Remotes.Get("Effect"):FireClient(player, "Coins", { Amount = reward.Kind == "Coins" and reward.Amount or 0 })
		end
	end)
end

function DailySpinService.Init(lobby: any)
	if lobby and lobby.OnSpinRequested then
		lobby.OnSpinRequested(function(player: Player)
			DailySpinService.Spin(player, lobby)
		end)
	end
	Remotes.Get("RequestSpin").OnServerEvent:Connect(function(player: Player)
		DailySpinService.Spin(player, lobby)
	end)
	game:GetService("Players").PlayerRemoving:Connect(function(player)
		busy[player] = nil
	end)
end

return DailySpinService

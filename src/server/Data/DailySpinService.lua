--[[
	DailySpinService.lua
	Roue de récompense du lobby : gratuite toutes les Config.DailySpin.CooldownHours
	heures. Le serveur tire la récompense (pondérée), l'attribue, puis fait
	tourner la roue jusqu'au bon segment (animation vue par tous).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Lang = require(Shared.Lang)
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
		return Lang.F("%dh %02dm", h, m)
	end
	return Lang.F("%dm", math.max(1, m))
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
		Remotes.Get("Notify"):FireClient(player, Lang.F("Next free spin in %s", formatWait(nextAt - now)), true)
		return
	end
	busy[player] = true
	local index, reward = pickReward()
	profile.LastSpin = now
	local label = Lang.T(reward.Label)
	local coins = 0
	if reward.Kind == "Coins" then
		coins = reward.Amount
	elseif reward.Kind == "XP" then
		DataService.AddXP(player, reward.Amount)
	elseif reward.Kind == "Cosmetic" then
		-- Déjà possédé : on donne des pièces à la place
		if not DataService.GrantCosmetic(player, reward.Category, reward.Item) then
			coins = reward.Fallback or 100
			label = Lang.F("%s (owned: +%d coins)", Lang.T(reward.Label), coins)
		end
	end
	profile.Coins += coins
	DataService.MarkChanged(player)
	if lobby and lobby.SpinWheel then
		lobby.SpinWheel(index, Config.DailySpin.SpinSeconds)
	end
	task.delay(Config.DailySpin.SpinSeconds, function()
		busy[player] = nil
		if player.Parent then
			Remotes.Get("Notify"):FireClient(player, Lang.F("Daily Spin: you won %s!", label), false)
			Remotes.Get("Effect"):FireClient(player, "Coins", { Amount = coins })
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

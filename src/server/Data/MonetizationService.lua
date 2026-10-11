--[[
	MonetizationService.lua
	Emplacements pour les Game Passes et produits Robux, DÉSACTIVÉS tant que
	leurs identifiants valent 0 dans Config.Monetization.
	  - Game Pass VIP : pièces x2 (Config.Monetization.VIPCoinMultiplier)
	  Les pièces ne servent qu'aux cosmétiques : aucun achat ne donne d'avantage en jeu.
	  - Produits Coins500 / Coins1500 : pièces (reçus traités une seule fois)
]]

local Players = game:GetService("Players")
local MarketplaceService = game:GetService("MarketplaceService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Remotes = require(Shared.Remotes)
local DataService = require(script.Parent.DataService)

local MonetizationService = {}

local owned: { [Player]: { [string]: boolean } } = {}

local function passId(key: string): number
	local def = Config.Monetization.GamePasses[key]
	return def and def.Id or 0
end

local function checkPasses(player: Player)
	local result = {}
	for key, def in Config.Monetization.GamePasses do
		if def.Id and def.Id > 0 then
			local ok, has = pcall(function()
				return MarketplaceService:UserOwnsGamePassAsync(player.UserId, def.Id)
			end)
			result[key] = ok and has == true
		end
	end
	owned[player] = result
	player:SetAttribute("VIP", result.VIP == true or nil)
end

function MonetizationService.HasPass(player: Player, key: string): boolean
	local list = owned[player]
	return list ~= nil and list[key] == true
end

function MonetizationService.CoinMultiplier(player: Player): number
	if MonetizationService.HasPass(player, "VIP") then
		return Config.Monetization.VIPCoinMultiplier
	end
	return 1
end

-- Traitement des achats de produits (appelé par Roblox, peut être rappelé)
local function processReceipt(receipt): Enum.ProductPurchaseDecision
	local player = Players:GetPlayerByUserId(receipt.PlayerId)
	if not player then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local profile = DataService.Get(player)
	if not profile or not DataService.IsSaved(player) then
		-- Sans profil sauvegardable, on laisse Roblox réessayer plus tard
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local receiptId = tostring(receipt.PurchaseId)
	if DataService.HasReceipt(player, receiptId) then
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end
	local granted = false
	for _, def in Config.Monetization.Products do
		if def.Id > 0 and def.Id == receipt.ProductId then
			DataService.AddCoins(player, def.Coins, false)
			granted = true
		end
	end
	if not granted then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	DataService.AddReceipt(player, receiptId)
	if not DataService.Save(player, false) then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	Remotes.Get("Notify"):FireClient(player, "Thanks for your purchase!", false)
	return Enum.ProductPurchaseDecision.PurchaseGranted
end

function MonetizationService.Init()
	local anyPass = false
	for _, def in Config.Monetization.GamePasses do
		if def.Id and def.Id > 0 then
			anyPass = true
		end
	end
	local anyProduct = false
	for _, def in Config.Monetization.Products do
		if def.Id and def.Id > 0 then
			anyProduct = true
		end
	end

	if anyPass then
		Players.PlayerAdded:Connect(function(player)
			task.spawn(checkPasses, player)
		end)
		for _, player in Players:GetPlayers() do
			task.spawn(checkPasses, player)
		end
		MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, gamePassId, purchased)
			if purchased then
				for key, def in Config.Monetization.GamePasses do
					if def.Id == gamePassId then
						owned[player] = owned[player] or {}
						owned[player][key] = true
						player:SetAttribute("VIP", owned[player].VIP == true or nil)
					end
				end
			end
		end)
	end
	if anyProduct then
		MarketplaceService.ProcessReceipt = processReceipt
	end
	Players.PlayerRemoving:Connect(function(player)
		owned[player] = nil
	end)
	local _ = passId
end

return MonetizationService

--[[
	ShopService.lua
	Boutique de cosmétiques, entièrement validée côté serveur.
	Catégories (Config.Shop) : Looks (chapeaux), Trails (traînées),
	CatchEffects (effet visuel quand on attrape quelqu'un).
	Rien ne change la vitesse, le dash, la portée ou la survie : les achats
	n'apportent aucun avantage en poursuite.

	Le client envoie seulement ShopPurchase(catégorie, id) et ShopEquip(catégorie, id).
	Prix, solde et possession sont vérifiés ici.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Lang = require(Shared.Lang)
local Remotes = require(Shared.Remotes)
local Types = require(Shared.Types)
local Services = script.Parent.Parent.Services
local ActorService = require(Services.ActorService)
local RateLimiter = require(Services.RateLimiter)
local DataService = require(script.Parent.DataService)
local Cosmetics = require(script.Parent.Cosmetics)

type Actor = Types.Actor

local ShopService = {}

local lastPurchase: { [Player]: number } = {}

local function notify(player: Player, message: string, isError: boolean?)
	Remotes.Get("Notify"):FireClient(player, message, isError == true)
end

local function definitions(category: string): { [string]: any }?
	if DataService.CosmeticFields[category] == nil then
		return nil
	end
	local defs = (Config.Shop :: any)[category]
	return type(defs) == "table" and defs or nil
end

-- Applique chapeau, traînée et effet de capture sur le personnage
local function applyCosmetics(player: Player)
	local profile = DataService.Get(player)
	if not profile then
		return
	end
	local character = player.Character
	if character then
		Cosmetics.Apply(character, profile.EquippedLook, profile.EquippedTrail)
		character:SetAttribute("CatchEffect", profile.EquippedCatchEffect)
	end
end
ShopService.ApplyCosmetics = applyCosmetics

-- ---------------------------------------------------------------------------
-- Achat et équipement
-- ---------------------------------------------------------------------------
local function purchase(player: Player, category: any, itemId: any)
	if type(category) ~= "string" or type(itemId) ~= "string" or #itemId > 40 then
		return
	end
	local now = os.clock()
	if lastPurchase[player] and now - lastPurchase[player] < Config.Shop.PurchaseCooldown then
		return
	end
	lastPurchase[player] = now
	local defs = definitions(category)
	local def = defs and defs[itemId]
	if not def then
		return
	end
	local profile = DataService.Get(player)
	if not profile then
		notify(player, Lang.T("Your profile is still loading."), true)
		return
	end
	local fields = DataService.CosmeticFields[category]
	local owned = (profile :: any)[fields.Owned]
	if owned[itemId] then
		notify(player, Lang.F("You already own %s.", Lang.T(def.Name)), true)
		return
	end
	if profile.Coins < def.Price then
		notify(player, Lang.F("Not enough coins! %s costs %d.", Lang.T(def.Name), def.Price), true)
		return
	end
	profile.Coins -= def.Price
	owned[itemId] = true
	-- Un achat est équipé tout de suite
	;(profile :: any)[fields.Equipped] = itemId
	DataService.MarkChanged(player)
	applyCosmetics(player)
	notify(player, Lang.F("Unlocked %s!", Lang.T(def.Name)))
end

local function equip(player: Player, category: any, itemId: any)
	if type(category) ~= "string" or type(itemId) ~= "string" then
		return
	end
	local defs = definitions(category)
	local profile = DataService.Get(player)
	if not defs or defs[itemId] == nil or not profile then
		return
	end
	local fields = DataService.CosmeticFields[category]
	if not (profile :: any)[fields.Owned][itemId] then
		return
	end
	;(profile :: any)[fields.Equipped] = itemId
	DataService.MarkChanged(player)
	applyCosmetics(player)
end

-- ---------------------------------------------------------------------------
-- Init
-- ---------------------------------------------------------------------------
function ShopService.Init(lobbyBuilder: any)
	Remotes.Get("ShopPurchase").OnServerEvent:Connect(function(player, category, itemId)
		if RateLimiter.Allow(player, "Shop", 6) then
			purchase(player, category, itemId)
		end
	end)
	Remotes.Get("ShopEquip").OnServerEvent:Connect(function(player, category, itemId)
		if RateLimiter.Allow(player, "Equip", 6) then
			equip(player, category, itemId)
		end
	end)

	-- Comptoir du lobby : ouvre la boutique côté client
	if lobbyBuilder and lobbyBuilder.OnShopOpened then
		lobbyBuilder.OnShopOpened(function(player: Player)
			Remotes.Get("OpenShop"):FireClient(player)
		end)
	end

	-- Apparences : réappliquées à chaque apparition et au chargement du profil
	ActorService.CharacterAdded:Connect(function(actor: Actor)
		if actor.Player then
			task.defer(applyCosmetics, actor.Player)
			task.defer(DataService.Replicate, actor.Player) -- niveau/victoires sur le nouveau personnage
		end
	end)
	DataService.ProfileLoaded:Connect(function(player: Player, profile)
		local actor = ActorService.FromPlayer(player)
		if actor then
			actor.Data = profile
		end
		applyCosmetics(player)
	end)
	Players.PlayerRemoving:Connect(function(player)
		lastPurchase[player] = nil
	end)
end

return ShopService

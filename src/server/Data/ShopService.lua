--[[
	ShopService.lua
	Boutique, entièrement validée côté serveur :
	  - Upgrades (améliorations permanentes à niveaux) ;
	  - Consumables (usage unique, stock limité) : bouclier, leurre, boost, piège ;
	  - Looks et Trails (apparences, ajoutées par-dessus l'avatar).
	Le client envoie seulement : ShopPurchase(catégorie, id), ShopEquip(catégorie, id),
	UseConsumable(id). Tout le reste (prix, solde, stock, règles) est vérifié ici.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Remotes = require(Shared.Remotes)
local Teams = require(Shared.Teams)
local Types = require(Shared.Types)
local Services = script.Parent.Parent.Services
local ActorService = require(Services.ActorService)
local AbilityService = require(Services.AbilityService)
local CaptureService = require(Services.CaptureService)
local RoundState = require(Services.RoundState)
local RateLimiter = require(Services.RateLimiter)
local Build = require(script.Parent.Parent.Util.Build)
local DataService = require(script.Parent.DataService)
local Cosmetics = require(script.Parent.Cosmetics)

type Actor = Types.Actor

local ShopService = {}

local lastPurchase: { [Player]: number } = {}
local extraStackProvider: ((Player) -> number)? = nil
type Trap = { Part: BasePart, OwnerId: string, OwnerTeam: string, ExpiresAt: number }
local traps: { Trap } = {}
local decoys: { Model } = {}

local function notify(player: Player, message: string, isError: boolean?)
	Remotes.Get("Notify"):FireClient(player, message, isError == true)
end

function ShopService.SetExtraStackProvider(provider: (Player) -> number)
	extraStackProvider = provider
end

local function maxStack(player: Player): number
	return Config.Shop.MaxConsumableStack + (extraStackProvider and extraStackProvider(player) or 0)
end

-- ---------------------------------------------------------------------------
-- Achats
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
	local profile = DataService.Get(player)
	if not profile then
		notify(player, "Your profile is still loading.", true)
		return
	end
	local price: number? = nil
	local apply: (() -> ())? = nil
	local label = itemId

	if category == "Upgrades" then
		local def = Config.Shop.Upgrades[itemId]
		if not def then
			return
		end
		local level = profile.Upgrades[itemId] or 0
		if level >= #def.Prices then
			notify(player, def.Name .. " is already maxed out!", true)
			return
		end
		price = def.Prices[level + 1]
		label = def.Name .. " level " .. (level + 1)
		apply = function()
			profile.Upgrades[itemId] = level + 1
		end
	elseif category == "Consumables" then
		local def = Config.Shop.Consumables[itemId]
		if not def then
			return
		end
		local count = profile.Consumables[itemId] or 0
		if count >= maxStack(player) then
			notify(player, "You can't carry more " .. def.Name .. ".", true)
			return
		end
		price = def.Price
		label = def.Name
		apply = function()
			profile.Consumables[itemId] = count + 1
		end
	elseif category == "Looks" or category == "Trails" then
		local defs = category == "Looks" and Config.Shop.Looks or Config.Shop.Trails
		local owned = category == "Looks" and profile.OwnedLooks or profile.OwnedTrails
		local def = defs[itemId]
		if not def then
			return
		end
		if owned[itemId] then
			notify(player, "You already own " .. def.Name .. ".", true)
			return
		end
		price = def.Price
		label = def.Name
		apply = function()
			owned[itemId] = true
		end
	else
		return
	end

	if not price or not apply then
		return
	end
	if profile.Coins < price then
		notify(player, "Not enough coins!", true)
		return
	end
	profile.Coins -= price
	apply()
	DataService.MarkChanged(player)
	local actor = ActorService.FromPlayer(player)
	if actor and category == "Upgrades" then
		AbilityService.RefreshCharacter(actor)
	end
	notify(player, "Bought " .. label .. "!")
end

local function applyCosmetics(player: Player)
	local profile = DataService.Get(player)
	if profile and player.Character then
		Cosmetics.Apply(player.Character, profile.EquippedLook, profile.EquippedTrail)
	end
end

local function equip(player: Player, category: any, itemId: any)
	if type(category) ~= "string" or type(itemId) ~= "string" then
		return
	end
	local profile = DataService.Get(player)
	if not profile then
		return
	end
	if category == "Looks" and profile.OwnedLooks[itemId] and Config.Shop.Looks[itemId] then
		profile.EquippedLook = itemId
	elseif category == "Trails" and profile.OwnedTrails[itemId] and Config.Shop.Trails[itemId] then
		profile.EquippedTrail = itemId
	else
		return
	end
	DataService.MarkChanged(player)
	applyCosmetics(player)
end

-- ---------------------------------------------------------------------------
-- Consommables
-- ---------------------------------------------------------------------------
local function spawnDecoy(actor: Actor)
	local character = actor.Character
	local root = ActorService.GetRoot(actor)
	if not character or not root then
		return
	end
	local cfg = Config.Shop.Consumables.Decoy
	local archivable = character.Archivable
	character.Archivable = true
	local clone = character:Clone()
	character.Archivable = archivable
	if not clone then
		return
	end
	-- On ne garde que l'apparence : pas de scripts ni de contour local
	for _, d in clone:GetDescendants() do
		if d:IsA("BaseScript") or d.Name == "HoH_Outline" or d.Name == "HoH_TeamBadge" or d:IsA("ForceField") then
			d:Destroy()
		end
	end
	clone.Name = character.Name
	clone:SetAttribute("Decoy", true)
	clone:SetAttribute("ActorId", nil)
	clone:SetAttribute("Carrier", nil)
	clone:SetAttribute("Frozen", nil)
	local direction = Vector3.new(root.CFrame.LookVector.X, 0, root.CFrame.LookVector.Z)
	direction = direction.Magnitude > 0.1 and direction.Unit or Vector3.new(1, 0, 0)
	clone:PivotTo(root.CFrame * CFrame.new(2.5, 0, 0))
	clone.Parent = workspace
	-- Le leurre porte le tag des acteurs : les clients lui dessinent un contour
	game:GetService("CollectionService"):AddTag(clone, "HoH_Actor")
	local cloneRoot = clone:FindFirstChild("HumanoidRootPart")
	if cloneRoot and cloneRoot:IsA("BasePart") then
		pcall(function()
			cloneRoot:SetNetworkOwner(nil)
		end)
	end
	local humanoid = clone:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.WalkSpeed = cfg.Speed
		humanoid:Move(direction, false)
	end
	table.insert(decoys, clone)
	task.delay(cfg.Duration, function()
		local index = table.find(decoys, clone)
		if index then
			table.remove(decoys, index)
		end
		if clone.Parent then
			local cr = clone:FindFirstChild("HumanoidRootPart")
			if cr and cr:IsA("BasePart") then
				Remotes.Get("Effect"):FireAllClients("Poof", { Position = cr.Position })
			end
			clone:Destroy()
		end
	end)
end

local function placeTrap(actor: Actor): boolean
	local root = ActorService.GetRoot(actor)
	if not root or not actor.Team then
		return false
	end
	local cfg = Config.Shop.Consumables.Trap
	local count = 0
	for _, trap in traps do
		if trap.OwnerId == actor.Id then
			count += 1
		end
	end
	if count >= cfg.MaxActivePerActor then
		ActorService.FireClient(actor, Remotes.Get("Notify"), "You already have " .. cfg.MaxActivePerActor .. " traps placed.", true)
		return false
	end
	local def = Teams.Get(actor.Team)
	local part = Build.Part({
		Name = "Trap",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.2, cfg.Radius * 1.6, cfg.Radius * 1.6),
		CFrame = CFrame.new(root.Position - Vector3.new(0, 2.9, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		Color = def and def.DarkColor or Color3.new(0.2, 0.2, 0.2),
		Material = Enum.Material.DiamondPlate,
		Transparency = 0.35,
		CanCollide = false,
		CanQuery = false,
		Accent = true,
	})
	part:SetAttribute("OwnerTeam", actor.Team)
	part.Parent = workspace
	table.insert(traps, { Part = part, OwnerId = actor.Id, OwnerTeam = actor.Team, ExpiresAt = os.clock() + cfg.LifetimeSeconds })
	return true
end

local function updateTraps()
	if #traps == 0 then
		return
	end
	local cfg = Config.Shop.Consumables.Trap
	local now = os.clock()
	for index = #traps, 1, -1 do
		local trap = traps[index]
		local triggered: Actor? = nil
		if now > trap.ExpiresAt or not trap.Part.Parent or not RoundState.IsActive() then
			trap.Part:Destroy()
			table.remove(traps, index)
			continue
		end
		for _, actor in RoundState.GetActiveParticipants() do
			if actor.Team ~= trap.OwnerTeam then
				local position = ActorService.GetPosition(actor)
				if position then
					local delta = Vector3.new(position.X - trap.Part.Position.X, 0, position.Z - trap.Part.Position.Z)
					if delta.Magnitude <= cfg.Radius and math.abs(position.Y - trap.Part.Position.Y) < 6 then
						triggered = actor
						break
					end
				end
			end
		end
		if triggered then
			local victim = triggered
			ActorService.SetCharacterAttribute(victim, "Frozen", true)
			ActorService.FireClient(victim, Remotes.Get("Announce"), "It's a trap! Frozen!", Color3.fromRGB(150, 210, 255))
			Remotes.Get("Effect"):FireAllClients("Trap", { Position = trap.Part.Position })
			task.delay(cfg.StunSeconds, function()
				-- On ne dégèle que si rien d'autre (compte à rebours) ne gèle l'acteur
				if not RoundState.IsInRound() or RoundState.Phase == "Round" then
					ActorService.SetCharacterAttribute(victim, "Frozen", nil)
				end
			end)
			trap.Part:Destroy()
			table.remove(traps, index)
		end
	end
end

local function useConsumable(player: Player, itemId: any)
	if type(itemId) ~= "string" or not Config.Shop.Consumables[itemId] then
		return
	end
	if not RateLimiter.Allow(player, "Consumable", 4) then
		return
	end
	local actor = ActorService.FromPlayer(player)
	local profile = DataService.Get(player)
	if not actor or not profile or not RoundState.IsActive() or not RoundState.IsParticipant(actor) or not ActorService.IsAlive(actor) then
		return
	end
	if (profile.Consumables[itemId] or 0) <= 0 then
		notify(player, "You don't have any " .. Config.Shop.Consumables[itemId].Name .. ".", true)
		return
	end
	local character = actor.Character :: Model
	local used = true
	if itemId == "Shield" then
		if character:GetAttribute("Shield") == true then
			notify(player, "Your shield is already up.", true)
			return
		end
		character:SetAttribute("Shield", true)
		local duration = Config.Shop.Consumables.Shield.Duration
		task.delay(duration, function()
			if character.Parent then
				character:SetAttribute("Shield", nil)
			end
		end)
	elseif itemId == "SpeedBoost" then
		local cfg = Config.Shop.Consumables.SpeedBoost
		AbilityService.SetSpeedModifier(actor, "Boost", cfg.Multiplier, cfg.Duration)
	elseif itemId == "Decoy" then
		spawnDecoy(actor)
	elseif itemId == "Trap" then
		used = placeTrap(actor)
	end
	if used then
		profile.Consumables[itemId] -= 1
		DataService.MarkChanged(player)
		Remotes.Get("Effect"):FireAllClients("Consumable", { ActorId = actor.Id, Item = itemId })
	end
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
	Remotes.Get("UseConsumable").OnServerEvent:Connect(useConsumable)

	-- Comptoir du lobby : ouvre la boutique côté client
	if lobbyBuilder and lobbyBuilder.OnShopOpened then
		lobbyBuilder.OnShopOpened(function(player: Player)
			Remotes.Get("OpenShop"):FireClient(player)
		end)
	end

	-- Bouclier : bloque la prochaine capture
	CaptureService.AddGuard(function(hunter: Actor, victim: Actor)
		local character = victim.Character
		if character and character:GetAttribute("Shield") == true then
			character:SetAttribute("Shield", nil)
			CaptureService.Protect(character, 1)
			ActorService.FireClient(victim, Remotes.Get("Announce"), "Your shield blocked the catch!", Color3.fromRGB(120, 200, 255))
			ActorService.FireClient(hunter, Remotes.Get("Announce"), "Blocked by a shield!", Color3.fromRGB(120, 200, 255))
			Remotes.Get("Effect"):FireAllClients("ShieldBreak", { Position = ActorService.GetPosition(victim) })
			return false
		end
		return true
	end)

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
			AbilityService.RefreshCharacter(actor)
		end
		applyCosmetics(player)
	end)
	Players.PlayerRemoving:Connect(function(player)
		lastPurchase[player] = nil
	end)

	RunService.Heartbeat:Connect(function()
		updateTraps()
	end)
end

-- Nettoyage de fin de manche
function ShopService.ResetRound()
	for _, trap in traps do
		trap.Part:Destroy()
	end
	table.clear(traps)
	for _, decoy in decoys do
		decoy:Destroy()
	end
	table.clear(decoys)
	for _, actor in ActorService.GetAll() do
		ActorService.SetCharacterAttribute(actor, "Shield", nil)
	end
end

return ShopService

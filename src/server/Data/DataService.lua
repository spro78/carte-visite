--[[
	DataService.lua
	Sauvegarde des profils joueurs avec DataStoreService :
	  pièces, achats (améliorations, consommables, apparences), statistiques.

	Robustesse :
	  - chargement et sauvegarde avec plusieurs tentatives (attente croissante) ;
	  - verrou de session (un autre serveur ne peut pas écraser le profil) ;
	  - si le chargement échoue, le joueur joue en "session seulement" : rien
	    n'est écrit, pour ne jamais écraser ses vraies données ;
	  - sauvegarde automatique régulière et à la fermeture (BindToClose).
	Dans Studio, active "Enable Studio Access to API Services" pour tester la
	sauvegarde (sinon le mode session seulement s'applique automatiquement).
]]

local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Lang = require(Shared.Lang)
local Remotes = require(Shared.Remotes)
local Signal = require(script.Parent.Parent.Util.Signal)

local DataService = {}

DataService.ProfileLoaded = Signal.new() -- (player, profile)
DataService.ProfileChanged = Signal.new() -- (player, profile)

export type Profile = {
	Version: number,
	Coins: number,
	OwnedLooks: { [string]: boolean },
	EquippedLook: string,
	OwnedTrails: { [string]: boolean },
	EquippedTrail: string,
	OwnedCatchEffects: { [string]: boolean },
	EquippedCatchEffect: string,
	Stats: { [string]: number },
	Level: number,
	XP: number,
	LastSpin: number,
	Receipts: { string },
	Lock: { JobId: string, Time: number }?,
}

type Session = {
	Profile: Profile,
	Loaded: boolean, -- false = session seulement (aucune écriture)
	Dirty: boolean,
	Saving: boolean,
	LastSave: number,
}

local SCHEMA_VERSION = 1
local LOCK_TIMEOUT = 600 -- un verrou plus vieux que 10 min est considéré comme abandonné
local MAX_RECEIPTS = 50

local sessions: { [Player]: Session } = {}
local store: DataStore? = nil
local winsStore: OrderedDataStore? = nil
local capturesStore: OrderedDataStore? = nil
local storeAvailable = true

local function log(...)
	if Config.Debug.VerboseLogs then
		print("[Data]", ...)
	end
end

-- Expérience nécessaire pour passer du niveau "level" au suivant
function DataService.XPForLevel(level: number): number
	return 100 + 25 * (level - 1)
end

-- Ajoute de l'expérience ; retourne (niveau avant, niveau après, récompenses
-- gratuites débloquées). Chaque niveau donne des pièces ; certains niveaux
-- offrent un cosmétique (Config.Economy.LevelRewards).
function DataService.AddXP(player: Player, amount: number): (number, number, { string })
	local profile = DataService.Get(player)
	if not profile then
		return 1, 1, {}
	end
	local before = profile.Level
	profile.XP += math.max(0, math.floor(amount))
	while profile.XP >= DataService.XPForLevel(profile.Level) do
		profile.XP -= DataService.XPForLevel(profile.Level)
		profile.Level += 1
	end
	local unlocks = {}
	for level = before + 1, profile.Level do
		profile.Coins += Config.Economy.CoinsPerLevelUp
		table.insert(unlocks, Lang.F("Level %d: +%d coins", level, Config.Economy.CoinsPerLevelUp))
		local reward = Config.Economy.LevelRewards[level]
		if reward and DataService.GrantCosmetic(player, reward.Category, reward.Item) then
			local def = (Config.Shop :: any)[reward.Category][reward.Item]
			table.insert(unlocks, Lang.F("Unlocked %s (free)", Lang.T(def.Name)))
		end
	end
	DataService.MarkChanged(player)
	return before, profile.Level, unlocks
end

-- Profil par défaut
function DataService.DefaultProfile(): Profile
	return {
		Version = SCHEMA_VERSION,
		Coins = Config.Economy.StartingCoins,
		OwnedLooks = { None = true },
		EquippedLook = "None",
		OwnedTrails = { None = true },
		EquippedTrail = "None",
		OwnedCatchEffects = { None = true },
		EquippedCatchEffect = "None",
		Stats = { Wins = 0, Captures = 0, RoundsPlayed = 0, Objectives = 0, TimesCaught = 0, CoinsEarned = 0 },
		Level = 1,
		XP = 0,
		LastSpin = 0,
		Receipts = {},
		Lock = nil,
	}
end

-- Complète un profil chargé avec les champs manquants (nouvelles versions)
local function reconcile(data: any): Profile
	local default = DataService.DefaultProfile()
	if type(data) ~= "table" then
		return default
	end
	for key, value in default do
		if data[key] == nil then
			data[key] = value
		elseif type(value) == "table" and type(data[key]) == "table" and key ~= "Receipts" and key ~= "Lock" then
			for subKey, subValue in value do
				if data[key][subKey] == nil then
					data[key][subKey] = subValue
				end
			end
		end
	end
	if type(data.Coins) ~= "number" or data.Coins ~= data.Coins then
		data.Coins = default.Coins
	end
	data.Version = SCHEMA_VERSION
	return data
end

local function retry<T>(label: string, fn: () -> T): (boolean, T?)
	local delay = Config.Data.RetryDelay
	for attempt = 1, Config.Data.MaxRetries do
		local ok, result = pcall(fn)
		if ok then
			return true, result
		end
		warn(string.format("[Data] %s : tentative %d/%d échouée : %s", label, attempt, Config.Data.MaxRetries, tostring(result)))
		if string.find(tostring(result), "StudioAccessToApisNotAllowed", 1, true) or string.find(tostring(result), "must publish", 1, true) then
			storeAvailable = false
			return false, nil
		end
		if attempt < Config.Data.MaxRetries then
			task.wait(delay)
			delay *= 2
		end
	end
	return false, nil
end

local function keyFor(player: Player): string
	return "Player_" .. player.UserId
end

-- Catégories de cosmétiques -> champs "possédé" / "équipé" du profil
DataService.CosmeticFields = {
	Looks = { Owned = "OwnedLooks", Equipped = "EquippedLook" },
	Trails = { Owned = "OwnedTrails", Equipped = "EquippedTrail" },
	CatchEffects = { Owned = "OwnedCatchEffects", Equipped = "EquippedCatchEffect" },
}

-- Offre un cosmétique (récompense gratuite). Retourne true s'il est nouveau.
function DataService.GrantCosmetic(player: Player, category: string, itemId: string): boolean
	local profile = DataService.Get(player)
	local fields = DataService.CosmeticFields[category]
	local defs = (Config.Shop :: any)[category]
	if not profile or not fields or type(defs) ~= "table" or defs[itemId] == nil then
		return false
	end
	local owned = (profile :: any)[fields.Owned]
	if owned[itemId] then
		return false
	end
	owned[itemId] = true
	DataService.MarkChanged(player)
	return true
end

-- Envoie au client une vue de son profil
function DataService.Replicate(player: Player)
	local session = sessions[player]
	if not session then
		return
	end
	local p = session.Profile
	Remotes.Get("DataUpdate"):FireClient(player, {
		Coins = p.Coins,
		OwnedLooks = p.OwnedLooks,
		EquippedLook = p.EquippedLook,
		OwnedTrails = p.OwnedTrails,
		EquippedTrail = p.EquippedTrail,
		OwnedCatchEffects = p.OwnedCatchEffects,
		EquippedCatchEffect = p.EquippedCatchEffect,
		Stats = p.Stats,
		Level = p.Level,
		XP = p.XP,
		XPNeeded = DataService.XPForLevel(p.Level),
		NextSpinAt = p.LastSpin + Config.DailySpin.CooldownHours * 3600,
		ServerTime = os.time(),
		Saved = session.Loaded,
	})
	-- Étiquette au-dessus de la tête : niveau et victoires
	player:SetAttribute("Level", p.Level)
	player:SetAttribute("Wins", p.Stats.Wins or 0)
	if player.Character then
		player.Character:SetAttribute("Level", p.Level)
		player.Character:SetAttribute("Wins", p.Stats.Wins or 0)
	end
end

local function markChanged(player: Player)
	local session = sessions[player]
	if session then
		session.Dirty = true
		DataService.Replicate(player)
		DataService.ProfileChanged:Fire(player, session.Profile)
	end
end
DataService.MarkChanged = markChanged

-- ---------------------------------------------------------------------------
-- Chargement / sauvegarde
-- ---------------------------------------------------------------------------
local function load(player: Player)
	local profile: Profile? = nil
	local loaded = false
	if store and storeAvailable then
		local jobId = game.JobId ~= "" and game.JobId or "studio"
		for _ = 1, 3 do
			local lockedByOther = false
			local ok, result = retry("Chargement " .. player.Name, function()
				return (store :: DataStore):UpdateAsync(keyFor(player), function(old)
					local data = reconcile(old)
					local lock = data.Lock
					if lock and lock.JobId ~= jobId and os.time() - (lock.Time or 0) < LOCK_TIMEOUT then
						lockedByOther = true
						return nil -- ne rien écrire
					end
					data.Lock = { JobId = jobId, Time = os.time() }
					return data
				end)
			end)
			if ok and result and not lockedByOther then
				profile = reconcile(result)
				loaded = true
				break
			elseif not ok then
				break
			end
			-- Verrouillé par un autre serveur (joueur qui vient de changer de serveur) : on attend
			task.wait(5)
		end
	end
	if player.Parent ~= Players then
		return
	end
	if not profile then
		profile = DataService.DefaultProfile()
		Remotes.Get("Notify"):FireClient(player, Lang.T("Your data couldn't be loaded. Progress won't be saved this session."), true)
		log("Session seulement pour", player.Name)
	end
	sessions[player] = {
		Profile = profile :: Profile,
		Loaded = loaded,
		Dirty = false,
		Saving = false,
		LastSave = os.clock(),
	}
	log("Profil chargé :", player.Name, "pièces =", (profile :: Profile).Coins, loaded and "(sauvegardé)" or "(session)")
	DataService.Replicate(player)
	DataService.ProfileLoaded:Fire(player, profile)
end

-- Sauvegarde (release = libérer le verrou, quand le joueur part)
function DataService.Save(player: Player, release: boolean?): boolean
	local session = sessions[player]
	if not session or not session.Loaded or not store then
		return false
	end
	if session.Saving then
		-- Une sauvegarde est en cours : on attend qu'elle finisse
		local deadline = os.clock() + 15
		while session.Saving and os.clock() < deadline do
			task.wait(0.1)
		end
	end
	session.Saving = true
	local snapshot = table.clone(session.Profile)
	local jobId = game.JobId ~= "" and game.JobId or "studio"
	local ok = retry("Sauvegarde " .. player.Name, function()
		return (store :: DataStore):UpdateAsync(keyFor(player), function(old)
			local current = type(old) == "table" and old or {}
			local lock = current.Lock
			if lock and lock.JobId ~= jobId and os.time() - (lock.Time or 0) < LOCK_TIMEOUT then
				-- Un autre serveur a pris le profil : on n'écrase pas
				return nil
			end
			snapshot.Lock = (not release) and { JobId = jobId, Time = os.time() } or nil
			return snapshot
		end)
	end)
	session.Saving = false
	if ok then
		session.Dirty = false
		session.LastSave = os.clock()
		-- Classements globaux
		local stats = session.Profile.Stats
		if winsStore then
			retry("Classement victoires", function()
				return (winsStore :: OrderedDataStore):SetAsync(tostring(player.UserId), math.floor(stats.Wins or 0))
			end)
		end
		if capturesStore then
			retry("Classement captures", function()
				return (capturesStore :: OrderedDataStore):SetAsync(tostring(player.UserId), math.floor(stats.Captures or 0))
			end)
		end
	end
	return ok
end

-- ---------------------------------------------------------------------------
-- Accès au profil
-- ---------------------------------------------------------------------------
function DataService.Get(player: Player): Profile?
	local session = sessions[player]
	return session and session.Profile or nil
end

function DataService.IsSaved(player: Player): boolean
	local session = sessions[player]
	return session ~= nil and session.Loaded
end

function DataService.AddCoins(player: Player, amount: number, countAsEarned: boolean?)
	local profile = DataService.Get(player)
	if not profile or amount == 0 then
		return
	end
	profile.Coins = math.max(0, math.floor(profile.Coins + amount))
	if countAsEarned and amount > 0 then
		profile.Stats.CoinsEarned = (profile.Stats.CoinsEarned or 0) + amount
	end
	markChanged(player)
end

function DataService.AddStat(player: Player, stat: string, amount: number)
	local profile = DataService.Get(player)
	if not profile then
		return
	end
	profile.Stats[stat] = (profile.Stats[stat] or 0) + amount
	markChanged(player)
end

-- Reçu de produit déjà traité ? (anti double crédit)
function DataService.HasReceipt(player: Player, receiptId: string): boolean
	local profile = DataService.Get(player)
	return profile ~= nil and table.find(profile.Receipts, receiptId) ~= nil
end

function DataService.AddReceipt(player: Player, receiptId: string)
	local profile = DataService.Get(player)
	if not profile then
		return
	end
	table.insert(profile.Receipts, receiptId)
	while #profile.Receipts > MAX_RECEIPTS do
		table.remove(profile.Receipts, 1)
	end
	markChanged(player)
end

function DataService.GetLeaderboardStores(): (OrderedDataStore?, OrderedDataStore?)
	return winsStore, capturesStore
end

function DataService.IsStoreAvailable(): boolean
	return storeAvailable and store ~= nil
end

-- ---------------------------------------------------------------------------
-- Init
-- ---------------------------------------------------------------------------
function DataService.Init()
	local ok, err = pcall(function()
		store = DataStoreService:GetDataStore(Config.Data.StoreName)
		winsStore = DataStoreService:GetOrderedDataStore(Config.Data.LeaderboardWins)
		capturesStore = DataStoreService:GetOrderedDataStore(Config.Data.LeaderboardCaptures)
	end)
	if not ok then
		storeAvailable = false
		warn("[Data] DataStore indisponible : " .. tostring(err))
	end

	Players.PlayerAdded:Connect(function(player)
		task.spawn(load, player)
	end)
	for _, player in Players:GetPlayers() do
		task.spawn(load, player)
	end
	Players.PlayerRemoving:Connect(function(player)
		if sessions[player] then
			DataService.Save(player, true)
			sessions[player] = nil
		end
	end)

	Remotes.Get("RequestData").OnServerEvent:Connect(function(player)
		DataService.Replicate(player)
	end)

	-- Sauvegarde automatique
	task.spawn(function()
		while true do
			task.wait(Config.Data.AutoSaveInterval)
			for player, session in sessions do
				if session.Dirty and session.Loaded then
					task.spawn(DataService.Save, player, false)
				end
			end
		end
	end)

	-- Fermeture du serveur : on sauvegarde tout le monde en parallèle
	game:BindToClose(function()
		if RunService:IsStudio() and not DataService.IsStoreAvailable() then
			return
		end
		local pending = 0
		for player in sessions do
			pending += 1
			task.spawn(function()
				DataService.Save(player, true)
				pending -= 1
			end)
		end
		local deadline = os.clock() + 25
		while pending > 0 and os.clock() < deadline do
			task.wait(0.1)
		end
	end)
end

return DataService

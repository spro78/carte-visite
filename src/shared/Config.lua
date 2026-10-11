--[[
	Config.lua
	Toutes les valeurs d'équilibrage et de réglage du jeu, au même endroit.
	Aucune autre partie du code ne doit contenir de "nombre magique" lié au gameplay.
]]

local Config = {}

-- ---------------------------------------------------------------------------
-- Boucle de manche
-- ---------------------------------------------------------------------------
Config.Round = {
	MinPlayersToStart = 1, -- une manche peut se lancer avec un seul vrai joueur (bots en phase 4)
	IntermissionSeconds = 20, -- lobby + vote de map
	CountdownSeconds = 5, -- compte à rebours, bases protégées
	BaseProtectionSeconds = 3, -- protection supplémentaire après le "GO!"
	RoundSeconds = 240, -- durée maximale d'une manche (4 minutes)
	ResultsSeconds = 10, -- écran de résultats
	VoteCandidates = 3, -- nombre de maps proposées au vote
	MinTeamsForLastStanding = 2, -- "dernière équipe debout" seulement si >= 2 équipes au départ
	StateBroadcastInterval = 1, -- secondes entre deux envois d'état aux clients
}

-- ---------------------------------------------------------------------------
-- Équipes et bots
-- ---------------------------------------------------------------------------
Config.Teams = {
	TargetSizeWithBots = 4, -- chaque équipe est complétée jusqu'à 4 membres (phase 4)
}

Config.Bots = {
	FleeDistance = 30, -- fuir le prédateur s'il est à moins de X studs
	ReactionTimeMin = 0.25, -- secondes de temps de réaction
	ReactionTimeMax = 0.8,
	PathRecomputeInterval = 0.6,
	MistakeChance = 0.15, -- probabilité de "mauvaise" décision à chaque réflexion
}

-- ---------------------------------------------------------------------------
-- Capture / conversion (phase 2)
-- ---------------------------------------------------------------------------
Config.Capture = {
	Range = 6, -- distance max (studs) vérifiée côté serveur
	CooldownSeconds = 1.0, -- temps de recharge entre deux captures d'un même chasseur
	InvincibilitySeconds = 2, -- invincibilité après conversion ou respawn
	MaxClientDistanceTolerance = 2, -- marge ajoutée pour la latence
}

-- ---------------------------------------------------------------------------
-- Déplacement (phase 2) - sensation à inertie
-- ---------------------------------------------------------------------------
Config.Movement = {
	MaxSpeed = 20,
	Acceleration = 45, -- studs/s² pour atteindre la vitesse max
	Deceleration = 70, -- studs/s² pour s'arrêter
	DashDistance = 18,
	DashDuration = 0.22,
	DashCooldown = 3,
	StopCooldown = 0.5, -- arrêt instantané (feinte)
	JumpPower = 50,
}

-- ---------------------------------------------------------------------------
-- Capacités par animal (phase 2)
-- ---------------------------------------------------------------------------
Config.Abilities = {
	FOX = {
		Name = "Sprint",
		Duration = 2.0,
		SpeedMultiplier = 1.5,
		Cooldown = 8,
	},
	CHICKEN = {
		Name = "Glide Jump",
		DoubleJumpPower = 45,
		GlideGravityScale = 0.3,
		GlideMaxDuration = 2.5,
		Cooldown = 6,
	},
	SNAKE = {
		Name = "Bite",
		Range = 8,
		SlowDuration = 2.0,
		SlowMultiplier = 0.6,
		Cooldown = 8,
	},
}

-- ---------------------------------------------------------------------------
-- Monde : positions des zones
-- ---------------------------------------------------------------------------
Config.World = {
	LobbyOrigin = Vector3.new(0, 0, 0), -- centre du sol du lobby
	MapOrigin = Vector3.new(0, 0, 2000), -- centre des maps (loin du lobby)
	RespawnHeight = 3, -- hauteur ajoutée au point d'apparition
}

-- ---------------------------------------------------------------------------
-- Lobby (carré, fermé)
-- ---------------------------------------------------------------------------
Config.Lobby = {
	Size = 140, -- côté du carré (studs)
	WallHeight = 26,
	WallThickness = 3,
	FloorColor = Color3.fromRGB(120, 190, 95),
	PathColor = Color3.fromRGB(215, 200, 160),
	WallColor = Color3.fromRGB(240, 235, 220),
	WallTrimColor = Color3.fromRGB(230, 90, 70),
	AccentColor = Color3.fromRGB(255, 200, 60),
	PanelColor = Color3.fromRGB(45, 50, 70),
	VotePlateSize = 12,
}

-- ---------------------------------------------------------------------------
-- Maps (une entrée par map, les valeurs de mode arrivent en phases 3 et 5)
-- ---------------------------------------------------------------------------
Config.Maps = {
	TheFarm = {
		GroundSize = 420,
		BaseRadius = 150,
		BasePadSize = 44,
		-- Mode Golden Egg
		PointsToWin = 3,
		CarrierSpeedMultiplier = 0.85,
		-- Mécanisme : bras tournant
		ArmLength = 70,
		ArmRotationSeconds = 6,
		ArmLaunchForce = 180,
		RagdollSeconds = 1.5,
	},
	TheCarousel = {
		GroundSize = 400,
		BaseRadius = 150,
		BasePadSize = 44,
		-- Mode King of the Wheel
		PointsToWin = 100,
		PlatformRadius = 45,
		SpeedSteps = { 0.5, 1.0, 1.8, 2.8 }, -- radians/seconde par palier
		StepDurationSeconds = 15,
		EjectForce = 160,
	},
	TheCanyon = {
		GroundSize = 440,
		BaseRadius = 160,
		BasePadSize = 48,
		-- Mode Raid
		EggsPerBase = 5,
		-- Mécanisme : catapulte tournante
		CatapultRotationSeconds = 8,
		CatapultForce = 220,
	},
	TheSwamp = {
		GroundSize = 400,
		BaseRadius = 140,
		BasePadSize = 44,
		-- Mécanismes : tourniquet + geysers
		TurnstileRotationSeconds = 5,
		TurnstileReleaseForce = 140,
		GeyserIntervalSeconds = 12,
		GeyserForce = 120,
	},
}

-- ---------------------------------------------------------------------------
-- Économie (phase 6)
-- ---------------------------------------------------------------------------
Config.Economy = {
	CoinsPerCapture = 5,
	CoinsPerObjective = 10,
	CoinsForSurvival = 3, -- par minute survécue sans être attrapé
	CoinsForWin = 25,
	CoinsForParticipation = 5,
}

Config.Shop = {
	Upgrades = {}, -- rempli en phase 6
	Consumables = {}, -- rempli en phase 6
}

-- ---------------------------------------------------------------------------
-- Monétisation : emplacements réservés, identifiants à remplir plus tard.
-- Un identifiant à 0 = désactivé.
-- ---------------------------------------------------------------------------
Config.Monetization = {
	GamePasses = {
		-- VIP = 0,
	},
	Products = {
		-- Coins500 = 0,
	},
}

-- ---------------------------------------------------------------------------
-- Sauvegarde (phase 6)
-- ---------------------------------------------------------------------------
Config.Data = {
	StoreName = "HuntOrHide_PlayerData_v1",
	LeaderboardWins = "HuntOrHide_Wins_v1",
	LeaderboardCaptures = "HuntOrHide_Captures_v1",
	AutoSaveInterval = 120,
	MaxRetries = 3,
}

-- ---------------------------------------------------------------------------
-- Debug : raccourcis pour tester vite dans Studio
-- ---------------------------------------------------------------------------
Config.Debug = {
	FastRounds = false, -- true = intermission et manche raccourcies
	FastIntermissionSeconds = 8,
	FastRoundSeconds = 45,
	FastResultsSeconds = 5,
	VerboseLogs = true,
}

-- ---------------------------------------------------------------------------
-- Accesseurs qui tiennent compte du mode Debug
-- ---------------------------------------------------------------------------
function Config.GetIntermissionSeconds(): number
	if Config.Debug.FastRounds then
		return Config.Debug.FastIntermissionSeconds
	end
	return Config.Round.IntermissionSeconds
end

function Config.GetRoundSeconds(): number
	if Config.Debug.FastRounds then
		return Config.Debug.FastRoundSeconds
	end
	return Config.Round.RoundSeconds
end

function Config.GetResultsSeconds(): number
	if Config.Debug.FastRounds then
		return Config.Debug.FastResultsSeconds
	end
	return Config.Round.ResultsSeconds
end

return Config

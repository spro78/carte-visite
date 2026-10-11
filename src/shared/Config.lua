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
	MinPlayersToStart = 1, -- une manche peut se lancer avec un seul vrai joueur (les bots complètent)
	IntermissionSeconds = 20, -- lobby + vote de map
	CountdownSeconds = 5, -- compte à rebours, bases protégées
	BaseProtectionSeconds = 2, -- protection supplémentaire après le "GO!"
	RoundSeconds = 240, -- durée maximale d'une manche (4 minutes)
	ResultsSeconds = 10, -- écran de résultats
	VoteCandidates = 3, -- nombre de maps proposées au vote
	MinTeamsForLastStanding = 2, -- "dernière équipe debout" seulement si >= 2 équipes au départ
	StateBroadcastInterval = 1, -- secondes entre deux envois d'état aux clients
	FreezeDuringCountdown = true, -- les joueurs ne peuvent pas quitter leur base pendant le décompte
}

-- ---------------------------------------------------------------------------
-- Apparence des joueurs
--   "Accessories" : chacun garde son avatar Roblox ; on ajoute les attributs de
--              l'animal (oreilles + queue de renard, crête + plumes de poule,
--              capuche + queue de vipère) et un foulard aux couleurs de l'équipe.
--   "Avatar" : avatar strictement intact ; l'animal se lit par le contour
--              (vert/rouge) et le badge au-dessus de la tête.
--   "Animal" : teinte d'équipe complète + museau/bec (module AnimalAppearance).
-- ---------------------------------------------------------------------------
Config.Appearance = {
	Mode = "Accessories",
	ShowTeamBadge = true, -- badge "FOX / CHICKEN / SNAKE" au-dessus de la tête
	BadgeMaxDistance = 140,
}

-- ---------------------------------------------------------------------------
-- Équipes et bots
-- ---------------------------------------------------------------------------
Config.Teams = {
	TargetSizeWithBots = 4, -- chaque équipe est complétée jusqu'à 4 membres par des bots
}

Config.Bots = {
	Enabled = true,
	JoinerReplacesBot = true, -- un joueur qui arrive en cours de manche prend la place d'un bot
	FleeDistance = 28, -- fuir le prédateur s'il est à moins de X studs
	ChaseDistance = 90, -- au-delà, la proie est ignorée au profit de l'objectif
	ThinkInterval = 0.35, -- secondes entre deux décisions
	ReactionTimeMin = 0.3, -- temps de réaction (secondes)
	ReactionTimeMax = 0.8,
	MistakeChance = 0.22, -- probabilité de "mauvaise" décision à chaque réflexion
	AimError = 7, -- erreur de visée (studs) sur la position de la cible
	SpeedMultiplier = 0.82, -- les bots sont plus lents que la vitesse max d'un joueur
	DashChance = 0.35, -- probabilité d'utiliser le dash quand c'est utile
	AbilityChance = 0.3,
	PathRecomputeInterval = 0.8,
	DirectChaseDistance = 25, -- en dessous, on fonce sans pathfinding
	WanderRadius = 40,
	HideChance = 0.35, -- probabilité de filer vers une cachette quand on fuit
	LeadSeconds = 0.3, -- anticipation de la position de la proie
	StuckSeconds = 1.5,
	-- Gabarit des bots : R6 (classique, comme Huss Valley) ou R15
	RigType = "R6",
	-- Animations par défaut de Roblox (modifiables)
	Animations = {
		R6 = {
			Idle = "rbxassetid://180435571",
			Walk = "rbxassetid://180426354",
			Run = "rbxassetid://180426354",
			Jump = "rbxassetid://125750702",
			Fall = "rbxassetid://180436148",
		},
		R15 = {
			Idle = "rbxassetid://507766666",
			Walk = "rbxassetid://507777826",
			Run = "rbxassetid://507767714",
			Jump = "rbxassetid://507765000",
			Fall = "rbxassetid://507767968",
		},
	},
}

-- ---------------------------------------------------------------------------
-- Capture / conversion
-- ---------------------------------------------------------------------------
Config.Capture = {
	Range = 5.5, -- distance max (studs) entre les centres, vérifiée côté serveur
	ClientTolerance = 1.5, -- marge accordée aux intentions de capture envoyées par le client (latence)
	CooldownSeconds = 1.0, -- temps de recharge entre deux captures d'un même chasseur
	InvincibilitySeconds = 2, -- invincibilité après conversion ou réapparition
	CheckInterval = 0.1, -- fréquence de la détection serveur
	MaxVerticalGap = 6, -- écart vertical max pour une capture
}

-- ---------------------------------------------------------------------------
-- Déplacement - sensation à inertie
-- ---------------------------------------------------------------------------
Config.Movement = {
	MaxSpeed = 21,
	Acceleration = 42, -- studs/s² : environ 0,5 s pour atteindre la vitesse max
	Deceleration = 48, -- studs/s² : glissade d'environ 0,45 s au relâchement
	TurnAcceleration = 70, -- accélération utilisée pour changer de direction
	AirControl = 0.6, -- part du contrôle conservée en l'air
	DashDistance = 16,
	DashDuration = 0.2,
	DashCooldown = 2.5,
	DashEndSpeedFactor = 0.7, -- vitesse conservée à la fin du dash (part de MaxSpeed)
	StopCooldown = 0.35, -- arrêt instantané (feinte)
	JumpPower = 50,
}

-- ---------------------------------------------------------------------------
-- Contrôles (modifiables). Les boutons tactiles sont créés par l'interface.
-- ---------------------------------------------------------------------------
Config.Controls = {
	DashLeft = { Enum.KeyCode.Q, Enum.KeyCode.ButtonL1 },
	DashRight = { Enum.KeyCode.E, Enum.KeyCode.ButtonR1 },
	Stop = { Enum.KeyCode.F, Enum.KeyCode.ButtonB },
	Ability = { Enum.KeyCode.R, Enum.KeyCode.ButtonX },
	Consumables = { Enum.KeyCode.One, Enum.KeyCode.Two, Enum.KeyCode.Three, Enum.KeyCode.Four },
}

-- ---------------------------------------------------------------------------
-- Capacités par animal
-- ---------------------------------------------------------------------------
Config.Abilities = {
	FOX = {
		Name = "Sprint",
		Description = "Run 50% faster for 2 seconds",
		Duration = 2.0,
		SpeedMultiplier = 1.5,
		Cooldown = 8,
	},
	CHICKEN = {
		Name = "Glide Jump",
		Description = "Jump again in the air and glide",
		DoubleJumpPower = 55,
		GlideFallSpeed = 9, -- vitesse de chute max pendant le vol plané
		GlideMaxDuration = 2.5,
		GlideForwardBoost = 6, -- poussée horizontale pendant le vol plané
		Cooldown = 6,
	},
	SNAKE = {
		Name = "Bite",
		Description = "Slow the closest enemy for 2 seconds",
		Range = 9,
		SlowDuration = 2.0,
		SlowMultiplier = 0.55,
		Cooldown = 7,
	},
}

-- ---------------------------------------------------------------------------
-- Cachettes
-- ---------------------------------------------------------------------------
Config.Hiding = {
	CheckInterval = 0.2,
	RevealDistance = 7, -- un ennemi à moins de X studs voit quand même le contour
}

-- ---------------------------------------------------------------------------
-- Éjections (bras, catapulte, geyser...) : ragdoll court
-- ---------------------------------------------------------------------------
Config.Launch = {
	DefaultRagdollSeconds = 1.2,
	Cooldown = 0.8, -- un même acteur ne peut pas être éjecté deux fois de suite trop vite
}

-- ---------------------------------------------------------------------------
-- Monde : positions des zones
-- ---------------------------------------------------------------------------
Config.World = {
	LobbyOrigin = Vector3.new(0, 0, 0), -- centre du sol du lobby
	MapOrigin = Vector3.new(0, 0, 2000), -- centre des maps (loin du lobby)
	RespawnHeight = 3, -- hauteur ajoutée au point d'apparition
	KillHeight = -60, -- sous cette hauteur (relative au sol de la map), on réapparaît à sa base
}

-- ---------------------------------------------------------------------------
-- Lobby (carré, fermé)
-- ---------------------------------------------------------------------------
Config.Lobby = {
	Size = 150, -- côté du carré (studs)
	WallHeight = 36,
	WallThickness = 3,
	FloorColor = Color3.fromRGB(120, 190, 95),
	PathColor = Color3.fromRGB(222, 205, 165),
	WallColor = Color3.fromRGB(245, 238, 222),
	WallTrimColor = Color3.fromRGB(232, 92, 70),
	AccentColor = Color3.fromRGB(255, 200, 60),
	PanelColor = Color3.fromRGB(38, 42, 64),
	VotePlateSize = 12,
	LeaderboardRefreshSeconds = 60,
	LeaderboardSize = 10,
}

-- ---------------------------------------------------------------------------
-- Roue de récompense du lobby (gratuite toutes les X heures)
-- ---------------------------------------------------------------------------
Config.DailySpin = {
	CooldownHours = 4,
	SpinSeconds = 3.5,
	-- Récompenses : Kind = "Coins" ou "Consumable" ; Weight = probabilité relative
	Rewards = {
		{ Kind = "Coins", Amount = 25, Weight = 30, Label = "25 coins" },
		{ Kind = "Consumable", Item = "Shield", Amount = 1, Weight = 15, Label = "Shield" },
		{ Kind = "Coins", Amount = 75, Weight = 20, Label = "75 coins" },
		{ Kind = "Consumable", Item = "Trap", Amount = 1, Weight = 12, Label = "Trap" },
		{ Kind = "Coins", Amount = 150, Weight = 10, Label = "150 coins" },
		{ Kind = "Consumable", Item = "SpeedBoost", Amount = 2, Weight = 8, Label = "2 Boosts" },
		{ Kind = "Coins", Amount = 500, Weight = 3, Label = "500 coins" },
		{ Kind = "Consumable", Item = "Decoy", Amount = 2, Weight = 2, Label = "2 Decoys" },
	},
}

-- ---------------------------------------------------------------------------
-- Maps : valeurs d'équilibrage de chaque mode et mécanisme
-- ---------------------------------------------------------------------------
Config.Maps = {
	TheFarm = {
		GroundSize = 300,
		BaseRadius = 105,
		BasePadSize = 36,
		-- Mode Golden Egg
		PointsToWin = 3,
		CarrierSpeedMultiplier = 0.85,
		EggPickupRange = 5,
		EggRespawnDelay = 3,
		EggDropPickupDelay = 1, -- délai avant de pouvoir ramasser un œuf tombé
		-- Mécanisme : bras tournant au ras du sol
		ArmLength = 62,
		ArmWidth = 4,
		ArmRotationSeconds = 7, -- durée d'un tour complet
		ArmLaunchSpeed = 110, -- vitesse horizontale donnée au joueur touché
		ArmLaunchUpSpeed = 75,
		RagdollSeconds = 1.6,
	},
	TheCarousel = {
		GroundSize = 300,
		BaseRadius = 110,
		BasePadSize = 36,
		-- Mode King of the Wheel
		PointsToWin = 100,
		PlatformRadius = 34,
		PlatformHeight = 2,
		SpeedSteps = { 0.35, 0.7, 1.15, 1.7 }, -- radians/seconde par palier
		StepDurationSeconds = 12,
		EjectSpeed = 95,
		EjectUpSpeed = 60,
		PauseAfterEject = 3,
	},
	TheCanyon = {
		GroundSize = 320,
		BaseRadius = 115,
		BasePadSize = 40,
		-- Mode Raid
		EggsPerBase = 5,
		EggPickupRange = 5,
		CarrierSpeedMultiplier = 0.9, -- un voleur d'œuf est un peu plus lent
		CarrierVisible = true, -- un voleur d'œuf est entouré en or pour tout le monde
		-- Mécanisme : catapulte tournante
		CatapultRotationSeconds = 9,
		CatapultArmLength = 16,
		CatapultFlightSeconds = 2.4,
		CatapultRange = 110, -- distance de lancer
		CatapultCooldown = 1.5,
	},
	TheSwamp = {
		GroundSize = 300,
		BaseRadius = 105,
		BasePadSize = 36,
		-- Mécanismes : tourniquet + geysers
		TurnstileRadius = 22,
		TurnstileRotationSeconds = 4.5,
		TurnstileHoldSeconds = 1.0,
		TurnstileFlightSeconds = 2.2,
		GeyserCount = 6,
		GeyserRadius = 5,
		GeyserIntervalSeconds = 10,
		GeyserWarningSeconds = 1.5,
		GeyserUpSpeed = 120,
	},
}

-- ---------------------------------------------------------------------------
-- Économie
-- ---------------------------------------------------------------------------
Config.Economy = {
	CoinsPerCapture = 5,
	CoinsPerObjective = 10, -- œuf ramené, œuf volé...
	CoinsPerSurvivalMinute = 3, -- par minute passée sans être attrapé
	CoinsForWin = 25,
	CoinsForParticipation = 5,
	StartingCoins = 50,
	XPPerRound = 20, -- expérience de base par manche (+ 1 XP par pièce gagnée)
}

-- ---------------------------------------------------------------------------
-- Boutique
-- Upgrades : améliorations permanentes à niveaux. Consumables : usage unique.
-- Looks : apparences (cosmétique).
-- ---------------------------------------------------------------------------
Config.Shop = {
	Upgrades = {
		DashCooldown = {
			Name = "Quick Dash",
			Description = "Dash cooldown -10% per level",
			Prices = { 150, 350, 700 },
			PerLevel = 0.10,
		},
		CaptureRange = {
			Name = "Long Reach",
			Description = "Catch range +0.4 studs per level",
			Prices = { 200, 450, 900 },
			PerLevel = 0.4,
		},
		Speed = {
			Name = "Swift Paws",
			Description = "Top speed +3% per level",
			Prices = { 250, 550, 1100 },
			PerLevel = 0.03,
		},
	},
	UpgradeOrder = { "DashCooldown", "CaptureRange", "Speed" },
	Consumables = {
		Shield = {
			Name = "Shield",
			Description = "Blocks the next catch",
			Price = 60,
			Duration = 20, -- le bouclier disparaît après X secondes s'il n'a pas servi
		},
		Decoy = {
			Name = "Decoy",
			Description = "Drops a fake you that runs away",
			Price = 40,
			Duration = 6,
			Speed = 18,
		},
		SpeedBoost = {
			Name = "Speed Boost",
			Description = "+30% speed for 5 seconds",
			Price = 35,
			Duration = 5,
			Multiplier = 1.3,
		},
		Trap = {
			Name = "Trap",
			Description = "A hidden trap that freezes an enemy",
			Price = 50,
			StunSeconds = 2,
			LifetimeSeconds = 60,
			Radius = 3.5,
			MaxActivePerActor = 2,
		},
	},
	ConsumableOrder = { "Shield", "Decoy", "SpeedBoost", "Trap" },
	MaxConsumableStack = 9,
	Looks = {
		None = { Name = "No Hat", Price = 0 },
		Crown = { Name = "Crown", Price = 300 },
		TopHat = { Name = "Top Hat", Price = 200 },
		PartyHat = { Name = "Party Hat", Price = 120 },
		Halo = { Name = "Halo", Price = 400 },
	},
	LookOrder = { "None", "PartyHat", "TopHat", "Crown", "Halo" },
	Trails = {
		None = { Name = "No Trail", Price = 0 },
		Sparkle = { Name = "Sparkle Trail", Price = 150, Colors = { Color3.fromRGB(255, 255, 255), Color3.fromRGB(255, 240, 150) } },
		Fire = { Name = "Fire Trail", Price = 250, Colors = { Color3.fromRGB(255, 220, 80), Color3.fromRGB(255, 70, 30) } },
		Rainbow = { Name = "Rainbow Trail", Price = 500, Colors = { Color3.fromRGB(255, 80, 80), Color3.fromRGB(255, 220, 80), Color3.fromRGB(80, 220, 120), Color3.fromRGB(80, 160, 255), Color3.fromRGB(190, 100, 255) } },
	},
	TrailOrder = { "None", "Sparkle", "Fire", "Rainbow" },
	PurchaseCooldown = 0.5, -- anti-spam des achats
}

-- ---------------------------------------------------------------------------
-- Monétisation : emplacements réservés, identifiants à remplir plus tard.
-- Un identifiant à 0 = désactivé (aucun bouton, aucun traitement).
-- ---------------------------------------------------------------------------
Config.Monetization = {
	GamePasses = {
		VIP = { Id = 0, Name = "VIP", Description = "x2 coins every round" },
		ExtraConsumableSlot = { Id = 0, Name = "Big Pockets", Description = "Carry 2 more of each item" },
	},
	Products = {
		Coins500 = { Id = 0, Coins = 500 },
		Coins1500 = { Id = 0, Coins = 1500 },
	},
	VIPCoinMultiplier = 2,
}

-- ---------------------------------------------------------------------------
-- Sauvegarde
-- ---------------------------------------------------------------------------
Config.Data = {
	StoreName = "HuntOrHide_PlayerData_v1",
	LeaderboardWins = "HuntOrHide_Wins_v1",
	LeaderboardCaptures = "HuntOrHide_Captures_v1",
	AutoSaveInterval = 120,
	MaxRetries = 4,
	RetryDelay = 1.5,
}

-- ---------------------------------------------------------------------------
-- Sons : identifiants à remplacer par tes propres sons si tu veux.
-- Les sons "rbxasset://" sont fournis avec le client Roblox.
-- ---------------------------------------------------------------------------
Config.Sounds = {
	Capture = "rbxasset://sounds/electronicpingshort.wav",
	Caught = "rbxasset://sounds/uuhhh.mp3",
	Dash = "rbxasset://sounds/swoosh.wav",
	Ability = "rbxasset://sounds/swoosh.wav",
	Launch = "rbxasset://sounds/Rocket whoosh 01.wav",
	Score = "rbxasset://sounds/electronicpingshort.wav",
	Countdown = "rbxasset://sounds/clickfast.wav",
	Go = "rbxasset://sounds/electronicpingshort.wav",
	Button = "rbxasset://sounds/button.wav",
	Coins = "rbxasset://sounds/electronicpingshort.wav",
	Win = "rbxasset://sounds/victory.wav",
	Geyser = "rbxasset://sounds/collide.wav",
	Volume = 0.5,
}

-- ---------------------------------------------------------------------------
-- Sécurité (anti-triche simple, phase 8)
-- ---------------------------------------------------------------------------
Config.Security = {
	RemoteRateLimit = 12, -- intentions max par seconde et par joueur (par remote)
	SpeedCheckInterval = 0.5,
	SpeedTolerance = 1.6, -- multiplicateur de tolérance sur la vitesse max théorique
	MaxSpeedViolations = 6, -- au-delà, le joueur est replacé (pas d'exclusion automatique)
}

-- ---------------------------------------------------------------------------
-- Debug : raccourcis pour tester vite dans Studio
-- ---------------------------------------------------------------------------
Config.Debug = {
	FastRounds = false, -- true = intermission et manche raccourcies
	FastIntermissionSeconds = 8,
	FastRoundSeconds = 60,
	FastResultsSeconds = 5,
	ForceMap = nil :: string?, -- ex : "TheFarm" pour toujours jouer cette map (tests)
	DisableBots = false, -- true = pas de bots (tests)
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

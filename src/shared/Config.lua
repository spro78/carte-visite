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
	IntermissionSeconds = 20, -- lobby + vote de map (cahier des charges : 20 s)
	CountdownSeconds = 5, -- compte à rebours, bases protégées
	BaseProtectionSeconds = 2, -- protection supplémentaire après le "GO!"
	RoundSeconds = 240, -- durée maximale d'une manche (4 minutes)
	ResultsSeconds = 10, -- écran de résultats
	VoteCandidates = 3, -- options (mode + carte) proposées au vote
	-- Cartes de la rotation. Carousel Valley est la carte héroïque refaite avec
	-- le kit 3D ; les autres reviendront quand elles auront reçu le même
	-- traitement (elles restent jouables en les ajoutant ici).
	MapPool = { "TheCarousel" },
	MinTeamsForLastStanding = 2, -- "dernière équipe debout" seulement si >= 2 équipes au départ
	StateBroadcastInterval = 1, -- secondes entre deux envois d'état aux clients
	FreezeDuringCountdown = true, -- les joueurs ne peuvent pas quitter leur base pendant le décompte
	-- Arrivée en cours de manche : le joueur prend la place d'un bot s'il y en a un
	-- (Config.Bots.JoinerReplacesBot), sinon il attend en spectateur (cahier des
	-- charges). Mettre une durée > 0 pour le faire entrer dans la plus petite
	-- équipe pendant les N premières secondes (désactivé par défaut).
	LateJoinSeconds = 0,
}

-- ---------------------------------------------------------------------------
-- Apparence des joueurs
--   "Avatar" (défaut) : l'avatar Roblox reste entièrement intact (corps,
--              vêtements, accessoires, couleurs). L'équipe se lit au contour
--              lumineux aux couleurs de l'équipe (renards orange, poules jaunes,
--              vipères vertes) et à l'étiquette au-dessus de la tête.
--   "Accessories" : ajoute les attributs de l'animal et un foulard d'équipe.
--   "Animal" : teinte d'équipe complète + museau/bec (module AnimalAppearance).
-- ---------------------------------------------------------------------------
Config.Appearance = {
	Mode = "Avatar",
	ShowTeamBadge = true, -- badge "FOX / CHICKEN / SNAKE" au-dessus de la tête
	BadgeMaxDistance = 90,
	-- Contours affichés en même temps (Roblox en rend 31 au plus) : le sien, les
	-- coéquipiers à terre, puis les plus proches. À baisser si les appareils
	-- modestes peinent (à mesurer sur appareil).
	MaxOutlines = 28,
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
	RescueRange = 120, -- un bot va chercher un coéquipier à terre à moins de X studs
	RescueChance = 0.8, -- probabilité qu'un bot aille le porter (tirée une fois par mise à terre)
	SafeZoneRefugeDistance = 60, -- un bot poursuivi près de son camp fuit vers sa zone sûre
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
-- Kit d'assets 3D modélisés dans Blender (tools/assets, src/shared/Kit)
--   Chaque client construit les meshes à la volée (EditableMesh) tant qu'ils
--   n'ont pas été importés dans Studio (dossier ReplicatedStorage.HoH_KitMeshes,
--   procédure dans tools/assets/README.md). Les collisions sont des volumes
--   simples posés par le serveur, identiques dans les deux cas.
-- ---------------------------------------------------------------------------
Config.Kit = {
	-- À passer à true si, dans Studio, les meshes construits à la volée
	-- apparaissent retournés (faces avant invisibles)
	FlipWinding = false,
	-- Pièces posées par image sur le client (lissage du chargement ; les
	-- meshes sont préparés pendant le lobby, il ne reste que des copies)
	PiecesPerFrame = 80,
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
-- Mise à terre, portage et réanimation (pas de prison)
--   Un joueur attrapé est À TERRE : il ne bouge plus et ne peut plus être
--   attrapé. Un coéquipier peut le PORTER jusqu'à la zone sûre de leur base,
--   où il se relève dans son équipe. Si personne ne le porte à temps (ou si
--   aucun coéquipier n'est debout), il rejoint l'équipe qui l'a attrapé.
-- ---------------------------------------------------------------------------
Config.Rescue = {
	BleedOutSeconds = 15, -- temps à terre avant de rejoindre l'équipe du chasseur
	DropGraceSeconds = 5, -- temps minimum restant quand un porteur lâche son coéquipier
	PickupRange = 7, -- distance (studs) pour ramasser un coéquipier à terre
	CarrySpeedMultiplier = 0.8, -- un porteur est un peu plus lent
	ReviveProtectionSeconds = 2, -- invincibilité après la réanimation
}

-- ---------------------------------------------------------------------------
-- Zone sûre de chaque camp : autour et derrière la plateforme. Un défenseur
-- dans la zone de SON camp ne peut être ni attrapé ni mordu ; les adversaires
-- peuvent y entrer (vol d'œufs du Raid) mais n'y sont pas protégés.
-- Distances en studs, dans le repère du camp (l'avant regarde le centre).
-- ---------------------------------------------------------------------------
Config.SafeZone = {
	SideMargin = 8, -- de chaque côté de la plateforme
	FrontMargin = 4, -- devant la plateforme (vers le centre)
	BackDepth = 24, -- derrière la plateforme (réduit si la limite de la carte est plus proche)
	Height = 16, -- hauteur couverte au-dessus du sol
	CheckInterval = 0.1,
	-- Protection gardée un instant après la sortie de la zone : tant que le
	-- HUD du joueur affiche SAFE ZONE (avec le décalage du réseau), il ne peut
	-- pas être attrapé
	ExitGraceSeconds = 0.5,
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
	Carry = { Enum.KeyCode.C, Enum.KeyCode.ButtonY }, -- porter / lâcher un coéquipier à terre
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
	-- Récompenses : Kind = "Coins" | "XP" | "Cosmetic" (si déjà possédé : pièces
	-- à la place) ; Weight = probabilité relative. Rien qui aide en poursuite.
	Rewards = {
		{ Kind = "Coins", Amount = 25, Weight = 30, Label = "25 coins" },
		{ Kind = "XP", Amount = 60, Weight = 18, Label = "60 XP" },
		{ Kind = "Coins", Amount = 75, Weight = 20, Label = "75 coins" },
		{ Kind = "Cosmetic", Category = "Looks", Item = "PartyHat", Fallback = 120, Weight = 8, Label = "Party Hat" },
		{ Kind = "Coins", Amount = 150, Weight = 10, Label = "150 coins" },
		{ Kind = "XP", Amount = 150, Weight = 8, Label = "150 XP" },
		{ Kind = "Coins", Amount = 500, Weight = 3, Label = "500 coins" },
		{ Kind = "Cosmetic", Category = "Trails", Item = "Rainbow", Fallback = 500, Weight = 2, Label = "Rainbow Trail" },
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
		-- Carte héroïque « Carousel Valley » : disposition dans Kit/Layouts
		-- (générée depuis Blender ; test_visual vérifie l'égalité)
		GroundSize = 300,
		BaseRadius = 110,
		BasePadSize = 36,
		AmbientTurnSeconds = 90, -- tour du manège hors mode Carousel
		NestRadius = 64, -- nids du mode Egg Run : sur la piste, face à chaque lieu
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
-- Modes de jeu (src/server/Modes ; textes dans Shared/ModeInfo)
-- ---------------------------------------------------------------------------
Config.Modes = {
	EggRun = {
		EggsToWin = 5,
		ActiveEggs = 3, -- œufs en jeu en même temps (un par nid au plus)
		CarrierSpeedMultiplier = 0.85, -- un porteur d'œuf est plus lent
		PickupRange = 5,
		RespawnDelay = 4, -- délai avant qu'un nid vide reçoive un nouvel œuf
		DropPickupDelay = 1, -- délai avant de pouvoir ramasser un œuf tombé
		DropReturnSeconds = 20, -- un œuf tombé et laissé seul retourne au nid
	},
	Carousel = {
		PointsToWin = 120,
		TurnSeconds = 48, -- tour complet des chevaux volants (environ 8 studs/s)
		ZoneRadius = 10, -- anneau sous chaque cheval
		ScoreInterval = 1, -- secondes entre deux points
		ReverseEverySeconds = 60, -- le manège change de sens (0 = jamais)
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
	CoinsPerLevelUp = 40, -- cadeau à chaque niveau
	-- Cosmétiques offerts à certains niveaux (gratuits, pour tout le monde)
	LevelRewards = {
		[3] = { Category = "CatchEffects", Item = "Confetti" },
		[5] = { Category = "Trails", Item = "Sparkle" },
		[8] = { Category = "Looks", Item = "TopHat" },
		[12] = { Category = "CatchEffects", Item = "Stars" },
		[20] = { Category = "Looks", Item = "Crown" },
	},
}

-- ---------------------------------------------------------------------------
-- Boutique : UNIQUEMENT des cosmétiques, à prix affiché en pièces.
-- Aucun achat ne change la vitesse, le dash, la portée ou la survie : en
-- poursuite, seule l'adresse compte. Les pièces se gagnent en jouant.
--   Looks       : chapeaux (par-dessus l'avatar)
--   Trails      : traînée derrière le joueur
--   CatchEffects: effet visuel quand TU attrapes quelqu'un
-- ---------------------------------------------------------------------------
Config.Shop = {
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
	CatchEffects = {
		None = { Name = "Classic Pop", Price = 0, Colors = { Color3.fromRGB(255, 255, 255) } },
		Confetti = { Name = "Confetti", Price = 150, Colors = { Color3.fromRGB(255, 90, 110), Color3.fromRGB(255, 220, 80), Color3.fromRGB(90, 200, 255), Color3.fromRGB(140, 230, 120) } },
		Stars = { Name = "Star Burst", Price = 250, Colors = { Color3.fromRGB(255, 230, 120), Color3.fromRGB(255, 255, 255) } },
		Hearts = { Name = "Hearts", Price = 300, Colors = { Color3.fromRGB(255, 110, 160), Color3.fromRGB(255, 180, 210) } },
		Lightning = { Name = "Lightning", Price = 450, Colors = { Color3.fromRGB(150, 220, 255), Color3.fromRGB(255, 255, 255) } },
	},
	CatchEffectOrder = { "None", "Confetti", "Stars", "Hearts", "Lightning" },
	PurchaseCooldown = 0.5, -- anti-spam des achats
}

-- ---------------------------------------------------------------------------
-- Monétisation : emplacements réservés, identifiants à remplir plus tard.
-- Un identifiant à 0 = désactivé (aucun bouton, aucun traitement).
-- ---------------------------------------------------------------------------
Config.Monetization = {
	GamePasses = {
		VIP = { Id = 0, Name = "VIP", Description = "x2 coins every round (cosmetics only)" },
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
	Carry = "rbxasset://sounds/swoosh.wav",
	Revive = "rbxasset://sounds/electronicpingshort.wav",
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
	ForceMode = nil :: string?, -- ex : "EggRun" (avec ForceMap, ou sur la carte gagnante)
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

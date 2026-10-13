--[[
	Main.server.lua
	Point d'entrée serveur : crée les RemoteEvents, construit le lobby, charge
	les maps, initialise les services puis lance la boucle de manche.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared.Remotes)

-- Les RemoteEvents doivent exister avant que les services ne les demandent
Remotes.Init()

local Services = script.Parent:WaitForChild("Services")
local LobbyBuilder = require(Services.LobbyBuilder)
local LightingSetup = require(Services.LightingSetup)
local MapRegistry = require(Services.MapRegistry)
local ActorService = require(Services.ActorService)
local TeamService = require(Services.TeamService)
local VoteService = require(Services.VoteService)
local AbilityService = require(Services.AbilityService)
local CaptureService = require(Services.CaptureService)
local SafeZoneService = require(Services.SafeZoneService)
local RescueService = require(Services.RescueService)
local RoundService = require(Services.RoundService)
local HideService = require(Services.HideService)
local BotService = require(script.Parent:WaitForChild("Bots"):WaitForChild("BotService"))
local DataFolder = script.Parent:WaitForChild("Data")
local DataService = require(DataFolder.DataService)
local EconomyService = require(DataFolder.EconomyService)
local ShopService = require(DataFolder.ShopService)
local MonetizationService = require(DataFolder.MonetizationService)
local LeaderboardService = require(DataFolder.LeaderboardService)
local DailySpinService = require(DataFolder.DailySpinService)

LightingSetup.Apply()
-- Kit 3D : meshes importés dans Studio, s'il y en a (avant toute carte)
require(script.Parent:WaitForChild("Util"):WaitForChild("Kit")).Init()
LobbyBuilder.Build()
MapRegistry.Init(script.Parent:WaitForChild("Maps"))

-- Les services s'abonnent aux signaux avant que les acteurs n'existent
TeamService.Init()
VoteService.Init(LobbyBuilder)
AbilityService.Init()
CaptureService.Init()
SafeZoneService.Init()
RescueService.Init()
RoundService.Init()
HideService.Init()
DataService.Init()
ShopService.Init(LobbyBuilder)
MonetizationService.Init()
LeaderboardService.Init(LobbyBuilder)
DailySpinService.Init(LobbyBuilder)
EconomyService.SetMultiplierProvider(MonetizationService.CoinMultiplier)
ActorService.Init()

RoundService.SetBotProvider(BotService)
RoundService.SetRewardHandler(EconomyService)
RoundService.Start()

print("[HuntOrHide] Server ready")

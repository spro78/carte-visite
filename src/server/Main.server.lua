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
local RoundService = require(Services.RoundService)
local HideService = require(Services.HideService)
local BotService = require(script.Parent:WaitForChild("Bots"):WaitForChild("BotService"))

LightingSetup.Apply()
LobbyBuilder.Build()
MapRegistry.Init(script.Parent:WaitForChild("Maps"))

-- Les services s'abonnent aux signaux avant que les acteurs n'existent
TeamService.Init()
VoteService.Init(LobbyBuilder)
AbilityService.Init()
CaptureService.Init()
RoundService.Init()
HideService.Init()
ActorService.Init()

RoundService.SetBotProvider(BotService)
RoundService.Start()

print("[HuntOrHide] Server ready")

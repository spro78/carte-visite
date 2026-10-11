--[[
	Main.server.lua
	Point d'entrée serveur : crée les RemoteEvents, construit le lobby,
	charge les maps et lance la boucle de manche.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared.Remotes)

-- Les RemoteEvents doivent exister avant que les services ne les demandent
Remotes.Init()

local Services = script.Parent:WaitForChild("Services")
local LobbyBuilder = require(Services.LobbyBuilder)
local TeamService = require(Services.TeamService)
local VoteService = require(Services.VoteService)
local MapRegistry = require(Services.MapRegistry)
local RoundService = require(Services.RoundService)

LobbyBuilder.Build()
MapRegistry.Init(script.Parent:WaitForChild("Maps"))
TeamService.Init()
VoteService.Init(LobbyBuilder)
RoundService.Init()
RoundService.Start()

print("[HuntOrHide] Server ready")

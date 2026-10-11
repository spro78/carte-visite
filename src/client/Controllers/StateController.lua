--[[
	StateController.lua
	Reçoit l'état du serveur et pilote le HUD. Envoie les intentions
	du joueur (vote) au serveur. Aucune décision de jeu n'est prise ici.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared.Remotes)
local Types = require(Shared.Types)

local StateController = {}

local player = Players.LocalPlayer
local currentState: Types.GameState? = nil

function StateController.GetState(): Types.GameState?
	return currentState
end

function StateController.Init(HUD)
	local stateUpdate = Remotes.Get("StateUpdate")
	local announceEvent = Remotes.Get("Announce")
	local voteMap = Remotes.Get("VoteMap")

	stateUpdate.OnClientEvent:Connect(function(state: Types.GameState)
		currentState = state
		HUD.UpdateState(state)
	end)

	announceEvent.OnClientEvent:Connect(function(text: string, color: Color3?)
		HUD.Announce(text, color)
	end)

	HUD.OnVote(function(mapId: string)
		voteMap:FireServer(mapId)
	end)

	local function refreshRole()
		HUD.SetRole(player:GetAttribute("Team"))
		if currentState then
			HUD.UpdateState(currentState)
		end
	end
	player:GetAttributeChangedSignal("Team"):Connect(refreshRole)
	refreshRole()
end

return StateController

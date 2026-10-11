--[[
	StateController.lua
	Reçoit l'état du serveur et pilote le HUD. Envoie les intentions du joueur
	(vote) au serveur. Aucune décision de jeu n'est prise ici.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared.Remotes)
local Types = require(Shared.Types)

local StateController = {}

local player = Players.LocalPlayer
local currentState: Types.GameState? = nil
local listeners: { (Types.GameState) -> () } = {}

function StateController.GetState(): Types.GameState?
	return currentState
end

function StateController.OnState(callback: (Types.GameState) -> ())
	table.insert(listeners, callback)
end

function StateController.Init(HUD: any)
	Remotes.Get("StateUpdate").OnClientEvent:Connect(function(state: Types.GameState)
		currentState = state
		HUD.UpdateState(state)
		for _, callback in listeners do
			task.spawn(callback, state)
		end
	end)

	Remotes.Get("Announce").OnClientEvent:Connect(function(text: string, color: Color3?)
		HUD.Announce(text, color)
	end)

	Remotes.Get("RoundReward").OnClientEvent:Connect(function(reward)
		HUD.SetRoundReward(reward)
		if currentState then
			HUD.UpdateState(currentState)
		end
	end)

	local voteMap = Remotes.Get("VoteMap")
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

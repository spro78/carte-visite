--[[
	Main.client.lua
	Point d'entrée client : construit l'interface et branche les contrôleurs.
	Le client n'envoie que des intentions ; le serveur décide de tout.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Remotes = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Remotes"))

local Controllers = script.Parent:WaitForChild("Controllers")
local UI = script.Parent:WaitForChild("UI")

local HUD = require(UI:WaitForChild("HUD"))
local ActionBar = require(UI:WaitForChild("ActionBar"))
local ObjectiveArrow = require(UI:WaitForChild("ObjectiveArrow"))
local ShopUI = require(UI:WaitForChild("ShopUI"))
local StateController = require(Controllers:WaitForChild("StateController"))
local MovementController = require(Controllers:WaitForChild("MovementController"))
local OutlineController = require(Controllers:WaitForChild("OutlineController"))
local MechanicsController = require(Controllers:WaitForChild("MechanicsController"))
local DataController = require(Controllers:WaitForChild("DataController"))

StateController.Init(HUD)
MovementController.Init()
OutlineController.Init()
MechanicsController.Init()
ObjectiveArrow.Init(HUD.Screen)
ActionBar.Init(HUD.Screen, HUD.BottomRow, {
	DashLeft = function()
		MovementController.Dash(-1)
	end,
	DashRight = function()
		MovementController.Dash(1)
	end,
	Stop = MovementController.Stop,
	Ability = MovementController.Ability,
}, MovementController.GetCooldowns)
HUD.Rescale() -- la barre de dash existe maintenant
ShopUI.Init(HUD.Screen, HUD.Pills.SHOP)
DataController.Init(HUD, ShopUI)

-- Pastille SPIN : tourner la roue de récompense
HUD.Pills.SPIN.Activated:Connect(function()
	Remotes.Get("RequestSpin"):FireServer()
end)

-- Boutique et roue hors manche
StateController.OnState(function(state)
	local inRound = (state.Phase == "Countdown" or state.Phase == "Round") and Players.LocalPlayer:GetAttribute("Team") ~= nil
	ShopUI.SetButtonVisible(not inRound)
	HUD.Pills.SPIN.Visible = not inRound
end)

print("[HuntOrHide] Client ready")

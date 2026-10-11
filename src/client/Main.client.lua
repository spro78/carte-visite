--[[
	Main.client.lua
	Point d'entrée client : construit l'interface et branche les contrôleurs.
	Le client n'envoie que des intentions ; le serveur décide de tout.
]]

local Controllers = script.Parent:WaitForChild("Controllers")
local UI = script.Parent:WaitForChild("UI")

local HUD = require(UI:WaitForChild("HUD"))
local ActionBar = require(UI:WaitForChild("ActionBar"))
local StateController = require(Controllers:WaitForChild("StateController"))
local MovementController = require(Controllers:WaitForChild("MovementController"))
local OutlineController = require(Controllers:WaitForChild("OutlineController"))
local MechanicsController = require(Controllers:WaitForChild("MechanicsController"))
local ObjectiveArrow = require(UI:WaitForChild("ObjectiveArrow"))
local ShopUI = require(UI:WaitForChild("ShopUI"))
local Inventory = require(UI:WaitForChild("Inventory"))
local DataController = require(Controllers:WaitForChild("DataController"))
local Players = game:GetService("Players")

StateController.Init(HUD)
MovementController.Init()
OutlineController.Init()
MechanicsController.Init()
ObjectiveArrow.Init(HUD.Screen)
ActionBar.Init(HUD.Screen, {
	DashLeft = function()
		MovementController.Dash(-1)
	end,
	DashRight = function()
		MovementController.Dash(1)
	end,
	Stop = MovementController.Stop,
	Ability = MovementController.Ability,
}, MovementController.GetCooldowns)

ShopUI.Init(HUD.Screen)
Inventory.Init(HUD.Screen)
DataController.Init(HUD, ShopUI, Inventory)

-- Boutique hors manche, barre d'objets pendant la manche
StateController.OnState(function(state)
	local inRound = (state.Phase == "Countdown" or state.Phase == "Round") and Players.LocalPlayer:GetAttribute("Team") ~= nil
	ShopUI.SetButtonVisible(not inRound)
	Inventory.SetVisible(inRound)
end)

print("[HuntOrHide] Client ready")

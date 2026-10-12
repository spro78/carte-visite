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
local KillFeed = require(UI:WaitForChild("KillFeed"))
local StateController = require(Controllers:WaitForChild("StateController"))
local MovementController = require(Controllers:WaitForChild("MovementController"))
local OutlineController = require(Controllers:WaitForChild("OutlineController"))
local RescueController = require(Controllers:WaitForChild("RescueController"))
local MechanicsController = require(Controllers:WaitForChild("MechanicsController"))
local KitController = require(Controllers:WaitForChild("KitController"))
local DataController = require(Controllers:WaitForChild("DataController"))
local EffectsController = require(Controllers:WaitForChild("EffectsController"))

StateController.Init(HUD)
MovementController.Init()
OutlineController.Init()
MechanicsController.Init()
KitController.Init()
ObjectiveArrow.Init(HUD.Screen)
-- Actions : déplacement (dash, stop, capacité) + porter un coéquipier à terre
local function actionInfo()
	local info: { [string]: any } = MovementController.GetCooldowns()
	info.Carry = RescueController.GetActionInfo()
	return info
end
ActionBar.Init(HUD.Screen, HUD.BottomRow, {
	DashLeft = function()
		MovementController.Dash(-1)
	end,
	DashRight = function()
		MovementController.Dash(1)
	end,
	Stop = MovementController.Stop,
	Ability = MovementController.Ability,
	Carry = RescueController.Carry,
}, actionInfo, HUD.SetTouchMode)
RescueController.Init(HUD)
HUD.Rescale() -- le dock des médaillons existe maintenant
ShopUI.Init(HUD.Screen, HUD.Pills.SHOP)
DataController.Init(HUD, ShopUI)
KillFeed.Init(HUD.Screen)
EffectsController.Init(KillFeed, HUD)

-- Pastille SPIN : tourner la roue de récompense
HUD.Pills.SPIN.Activated:Connect(function()
	Remotes.Get("RequestSpin"):FireServer()
end)

-- Boutique et roue hors manche
StateController.OnState(function(state)
	local inRound = (state.Phase == "Countdown" or state.Phase == "Round") and Players.LocalPlayer:GetAttribute("Team") ~= nil
	ShopUI.SetButtonVisible(not inRound)
	HUD.Pills.SPIN.Visible = not inRound
	ActionBar.SetPhase(state.Phase)
	EffectsController.OnState(state)
	-- Le fil des captures appartient à la manche : vidé et masqué hors manche
	-- (il ne doit jamais contredire l'écran de résultats)
	if state.Phase ~= "Round" then
		KillFeed.Clear()
	end
	KillFeed.SetVisible(state.Phase == "Round")
end)

print("[HuntOrHide] Client ready")

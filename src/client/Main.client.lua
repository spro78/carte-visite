--[[
	Main.client.lua
	Point d'entrée client : construit le HUD et branche les contrôleurs.
	Phase 2 : MovementController (inertie, dash, arrêt), OutlineController
	(contours vert/rouge), AbilityController.
]]

local HUD = require(script.Parent:WaitForChild("UI"):WaitForChild("HUD"))
local StateController = require(script.Parent:WaitForChild("Controllers"):WaitForChild("StateController"))

StateController.Init(HUD)

print("[HuntOrHide] Client ready")

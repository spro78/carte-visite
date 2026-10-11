--[[
	DataController.lua
	Reçoit le profil du joueur (pièces, objets, achats) et les messages du
	serveur, et met à jour l'interface (HUD, boutique).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared.Remotes)
local Theme = require(script.Parent.Parent:WaitForChild("UI"):WaitForChild("Theme"))

local DataController = {}

local profile: { [string]: any } = {}

function DataController.Get(): { [string]: any }
	return profile
end

function DataController.Init(HUD: any, ShopUI: any)
	Remotes.Get("DataUpdate").OnClientEvent:Connect(function(data)
		if type(data) ~= "table" then
			return
		end
		profile = data
		HUD.SetProfile(data)
		ShopUI.SetProfile(data)
	end)
	Remotes.Get("Notify").OnClientEvent:Connect(function(message: string, isError: boolean?)
		HUD.Notify(message, isError and Theme.Bad or Theme.Good)
	end)
	Remotes.Get("RequestData"):FireServer()
end

return DataController

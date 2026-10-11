--[[
	Remotes.lua
	Liste unique des RemoteEvents. Le serveur les crée (Remotes.Init),
	le client les attend (Remotes.Get).
	Convention : le client n'envoie que des INTENTIONS, le serveur valide tout.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Remotes = {}

local FOLDER_NAME = "Remotes"

Remotes.Names = {
	-- Serveur -> Client
	StateUpdate = "StateUpdate", -- état complet de la partie (phase, chrono, scores...)
	Announce = "Announce", -- annonce courte au centre de l'écran
	-- Client -> Serveur
	VoteMap = "VoteMap", -- intention de voter pour une map (string mapId)
	-- Phase 2 (déclarés maintenant pour éviter de modifier ce fichier plus tard)
	RequestDash = "RequestDash", -- intention de dash (direction -1 / 1)
	RequestStop = "RequestStop", -- intention d'arrêt instantané
	RequestAbility = "RequestAbility", -- intention d'utiliser sa capacité
	CaptureAttempt = "CaptureAttempt", -- intention de capture (cible)
	-- Phase 6
	ShopPurchase = "ShopPurchase",
	UseConsumable = "UseConsumable",
}

local folder: Folder? = nil

-- À appeler une seule fois, côté serveur, au démarrage.
function Remotes.Init()
	assert(RunService:IsServer(), "Remotes.Init doit être appelé côté serveur")
	if ReplicatedStorage:FindFirstChild(FOLDER_NAME) then
		folder = ReplicatedStorage:FindFirstChild(FOLDER_NAME) :: Folder
		return
	end
	local newFolder = Instance.new("Folder")
	newFolder.Name = FOLDER_NAME
	for _, name in Remotes.Names do
		local event = Instance.new("RemoteEvent")
		event.Name = name
		event.Parent = newFolder
	end
	newFolder.Parent = ReplicatedStorage
	folder = newFolder
end

-- Retourne le RemoteEvent demandé (attend sa création si besoin).
function Remotes.Get(name: string): RemoteEvent
	assert(Remotes.Names[name] ~= nil, "RemoteEvent inconnu : " .. tostring(name))
	local f = folder or ReplicatedStorage:WaitForChild(FOLDER_NAME, 30)
	assert(f, "Dossier Remotes introuvable dans ReplicatedStorage")
	folder = f :: Folder
	local event = f:WaitForChild(name, 30)
	assert(event, "RemoteEvent introuvable : " .. name)
	return event :: RemoteEvent
end

return Remotes

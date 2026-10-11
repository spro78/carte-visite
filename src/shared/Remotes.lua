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
	StateUpdate = "StateUpdate", -- état de la partie (phase, chrono, scores...)
	Announce = "Announce", -- annonce courte au centre de l'écran
	Effect = "Effect", -- effet visuel/sonore (capture, éjection, capacité...)
	Launch = "Launch", -- éjection du personnage du joueur (vitesse, ragdoll)
	DataUpdate = "DataUpdate", -- pièces, inventaire, améliorations du joueur
	RoundReward = "RoundReward", -- pièces gagnées à la fin de la manche
	OpenShop = "OpenShop", -- ouvre la boutique (comptoir du lobby)
	Notify = "Notify", -- petit message au joueur (achat, erreur de sauvegarde...)
	-- Client -> Serveur (intentions)
	VoteMap = "VoteMap", -- (mapId: string)
	RequestDash = "RequestDash", -- (side: -1 | 1)
	RequestAbility = "RequestAbility", -- ()
	CaptureAttempt = "CaptureAttempt", -- (target: Model)
	ShopPurchase = "ShopPurchase", -- (category: string, itemId: string)
	ShopEquip = "ShopEquip", -- (category: string, itemId: string)
	UseConsumable = "UseConsumable", -- (itemId: string)
	RequestData = "RequestData", -- () : redemande l'état de son profil
	RequestSpin = "RequestSpin", -- () : tourner la roue de récompense
}

local folder: Instance? = nil

-- À appeler une seule fois, côté serveur, au démarrage.
function Remotes.Init()
	assert(RunService:IsServer(), "Remotes.Init doit être appelé côté serveur")
	local existing = ReplicatedStorage:FindFirstChild(FOLDER_NAME)
	if existing then
		folder = existing
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
	folder = f
	local event = f:WaitForChild(name, 30)
	assert(event and event:IsA("RemoteEvent"), "RemoteEvent introuvable : " .. name)
	return event
end

return Remotes

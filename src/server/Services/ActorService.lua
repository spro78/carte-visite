--[[
	ActorService.lua
	Registre des "acteurs" : tout ce qui peut chasser et être chassé.
	Un acteur est soit un vrai joueur, soit un bot. Tous les systèmes de jeu
	(capture, capacités, objectifs, bots) travaillent sur des acteurs, ce qui
	garantit que les bots suivent exactement les mêmes règles que les joueurs.

	Le personnage d'un acteur porte des attributs répliqués, lus par les clients :
	  ActorId, DisplayName, Team, IsBot, SpeedMult, DashCooldown, Hidden, Carrier...
	et le tag CollectionService "HoH_Actor".
]]

local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Types = require(Shared.Types)
local Signal = require(script.Parent.Parent.Util.Signal)

type Actor = Types.Actor

local ActorService = {}

ActorService.Tag = "HoH_Actor"
ActorService.ActorAdded = Signal.new() -- (actor)
ActorService.ActorRemoving = Signal.new() -- (actor)
ActorService.CharacterAdded = Signal.new() -- (actor, character)

local actors: { [string]: Actor } = {}
local byPlayer: { [Player]: Actor } = {}
local byCharacter: { [Model]: Actor } = {}
local botCounter = 0

local function tagCharacter(actor: Actor, character: Model)
	character:SetAttribute("ActorId", actor.Id)
	character:SetAttribute("DisplayName", actor.Name)
	character:SetAttribute("IsBot", actor.IsBot)
	character:SetAttribute("Team", actor.Team)
	CollectionService:AddTag(character, ActorService.Tag)
end

local function bindCharacter(actor: Actor, character: Model)
	if actor.Character and actor.Character ~= character then
		byCharacter[actor.Character] = nil
	end
	actor.Character = character
	byCharacter[character] = actor
	tagCharacter(actor, character)
	character.Destroying:Connect(function()
		if byCharacter[character] == actor then
			byCharacter[character] = nil
		end
		if actor.Character == character then
			actor.Character = nil
		end
	end)
	ActorService.CharacterAdded:Fire(actor, character)
end

local function newActor(id: string, name: string, player: Player?, isBot: boolean): Actor
	return {
		Id = id,
		Name = name,
		Player = player,
		IsBot = isBot,
		Character = nil,
		Team = nil,
		RoundCaptures = 0,
		RoundObjectives = 0,
		LastCaughtAt = 0,
		Data = nil,
	}
end

local function onPlayerAdded(player: Player)
	local actor = newActor("P" .. player.UserId, player.DisplayName, player, false)
	actors[actor.Id] = actor
	byPlayer[player] = actor
	player.CharacterAdded:Connect(function(character)
		bindCharacter(actor, character)
	end)
	if player.Character then
		bindCharacter(actor, player.Character)
	end
	ActorService.ActorAdded:Fire(actor)
end

local function onPlayerRemoving(player: Player)
	local actor = byPlayer[player]
	if not actor then
		return
	end
	ActorService.ActorRemoving:Fire(actor)
	byPlayer[player] = nil
	actors[actor.Id] = nil
	if actor.Character then
		byCharacter[actor.Character] = nil
	end
end

function ActorService.Init()
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	for _, player in Players:GetPlayers() do
		onPlayerAdded(player)
	end
end

-- ---------------------------------------------------------------------------
-- Bots
-- ---------------------------------------------------------------------------
function ActorService.AddBot(name: string): Actor
	botCounter += 1
	local actor = newActor("B" .. botCounter, name, nil, true)
	actors[actor.Id] = actor
	ActorService.ActorAdded:Fire(actor)
	return actor
end

-- Associe un personnage (modèle) à un bot.
function ActorService.SetBotCharacter(actor: Actor, character: Model)
	assert(actor.IsBot, "SetBotCharacter réservé aux bots")
	bindCharacter(actor, character)
end

function ActorService.RemoveBot(actor: Actor)
	if not actors[actor.Id] then
		return
	end
	ActorService.ActorRemoving:Fire(actor)
	actors[actor.Id] = nil
	local character = actor.Character
	if character then
		byCharacter[character] = nil
		actor.Character = nil
		character:Destroy()
	end
end

-- ---------------------------------------------------------------------------
-- Requêtes
-- ---------------------------------------------------------------------------
function ActorService.GetAll(): { Actor }
	local list = {}
	for _, actor in actors do
		table.insert(list, actor)
	end
	return list
end

function ActorService.GetBots(): { Actor }
	local list = {}
	for _, actor in actors do
		if actor.IsBot then
			table.insert(list, actor)
		end
	end
	return list
end

function ActorService.Get(id: string): Actor?
	return actors[id]
end

function ActorService.FromPlayer(player: Player): Actor?
	return byPlayer[player]
end

function ActorService.FromCharacter(character: Instance?): Actor?
	if character == nil or not character:IsA("Model") then
		return nil
	end
	return byCharacter[character]
end

-- Acteur à partir d'une Part touchée (membre d'un personnage).
function ActorService.FromPart(part: Instance): Actor?
	local model = part:FindFirstAncestorOfClass("Model")
	while model do
		local actor = byCharacter[model]
		if actor then
			return actor
		end
		model = model:FindFirstAncestorOfClass("Model")
	end
	return nil
end

function ActorService.GetRoot(actor: Actor): BasePart?
	local character = actor.Character
	if not character then
		return nil
	end
	local root = character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return root
	end
	return nil
end

function ActorService.GetHumanoid(actor: Actor): Humanoid?
	local character = actor.Character
	return character and character:FindFirstChildOfClass("Humanoid") or nil
end

function ActorService.IsAlive(actor: Actor): boolean
	local humanoid = ActorService.GetHumanoid(actor)
	return humanoid ~= nil and humanoid.Health > 0 and ActorService.GetRoot(actor) ~= nil
end

function ActorService.GetPosition(actor: Actor): Vector3?
	local root = ActorService.GetRoot(actor)
	return root and root.Position or nil
end

-- Pose un attribut sur le personnage (s'il existe).
function ActorService.SetCharacterAttribute(actor: Actor, name: string, value: any)
	if actor.Character then
		actor.Character:SetAttribute(name, value)
	end
end

-- Envoie un événement au client de l'acteur (sans effet pour un bot).
function ActorService.FireClient(actor: Actor, remote: RemoteEvent, ...: any)
	if actor.Player and actor.Player.Parent == Players then
		remote:FireClient(actor.Player, ...)
	end
end

return ActorService

--[[
	BotService.lua
	Fournisseur de bots pour RoundService :
	  - SpawnForRound : complète chaque équipe jusqu'à Config.Teams.TargetSizeWithBots
	    membres (une manche peut donc se jouer avec un seul vrai joueur) ;
	  - TakeSeat : un vrai joueur qui arrive en cours de manche prend la place
	    d'un bot (le bot est retiré) ;
	  - Cleanup : retire tous les bots en fin de manche.
	Les bots sont des acteurs comme les autres : ils peuvent être attrapés et
	convertis, utilisent le dash et leur capacité.
]]

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Teams = require(Shared.Teams)
local Types = require(Shared.Types)
local Services = script.Parent.Parent.Services
local ActorService = require(Services.ActorService)
local TeamService = require(Services.TeamService)
local RoundState = require(Services.RoundState)
local BotNames = require(script.Parent.BotNames)
local BotAppearance = require(script.Parent.BotAppearance)
local BotBrain = require(script.Parent.BotBrain)

type Actor = Types.Actor

local BotService = {}

local brains: { [string]: BotBrain.Brain } = {}
local connection: RBXScriptConnection? = nil
local random = Random.new()

local function takenNames(): { [string]: boolean }
	local taken = {}
	for _, actor in ActorService.GetAll() do
		taken[actor.Name] = true
		if actor.Player then
			taken[actor.Player.Name] = true
		end
	end
	return taken
end

local function getSpawn(teamId: string): CFrame
	local map = RoundState.Map
	if map then
		local spawns = map.GetSpawns(teamId)
		if spawns and #spawns > 0 then
			return spawns[random:NextInteger(1, #spawns)]
		end
	end
	return CFrame.new(Config.World.MapOrigin + Vector3.new(0, 5, 0))
end

local function spawnCharacter(actor: Actor, teamId: string)
	local character = BotAppearance.CreateCharacter(actor.Name)
	character:PivotTo(getSpawn(teamId) * CFrame.new(random:NextNumber(-3, 3), 0, random:NextNumber(-3, 3)))
	character.Parent = workspace
	local root = character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		pcall(function()
			root:SetNetworkOwner(nil) -- le serveur simule les bots
		end)
	end
	ActorService.SetBotCharacter(actor, character)
	TeamService.SetTeam(actor, teamId)

	local old = brains[actor.Id]
	if old then
		old:Destroy()
	end
	brains[actor.Id] = BotBrain.new(actor)

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.Died:Connect(function()
			-- Réapparition à la base si la manche continue
			task.delay(2, function()
				if ActorService.Get(actor.Id) and actor.Character == character and RoundState.IsInRound() and actor.Team then
					character:Destroy()
					spawnCharacter(actor, actor.Team)
				end
			end)
		end)
	end
end

local function startLoop()
	if connection then
		return
	end
	connection = RunService.Heartbeat:Connect(function(dt)
		for id, brain in brains do
			if ActorService.Get(id) == nil then
				brain:Destroy()
				brains[id] = nil
				continue
			end
			local ok, err = pcall(BotBrain.Step, brain, dt)
			if not ok then
				warn("[Bots] " .. tostring(err))
			end
		end
	end)
end

local function removeBot(actor: Actor)
	local brain = brains[actor.Id]
	if brain then
		brain:Destroy()
		brains[actor.Id] = nil
	end
	ActorService.RemoveBot(actor)
end

-- ---------------------------------------------------------------------------
-- Interface "fournisseur de bots" attendue par RoundService
-- ---------------------------------------------------------------------------
function BotService.SpawnForRound(humans: { Actor }, _context: any): { Actor }
	local spawned = {}
	if not Config.Bots.Enabled or Config.Debug.DisableBots then
		return spawned
	end
	local counts = TeamService.GetCounts(humans)
	local taken = takenNames()
	for _, teamId in Teams.Order do
		local missing = Config.Teams.TargetSizeWithBots - counts[teamId]
		for _ = 1, missing do
			local name = BotNames.Generate(taken)
			taken[name] = true
			local actor = ActorService.AddBot(name)
			spawnCharacter(actor, teamId)
			table.insert(spawned, actor)
		end
	end
	if #spawned > 0 then
		startLoop()
	end
	if Config.Debug.VerboseLogs then
		print(string.format("[Bots] %d bot(s) ajouté(s)", #spawned))
	end
	return spawned
end

-- Un vrai joueur prend la place d'un bot. Retourne l'équipe (ou nil si aucun bot).
function BotService.TakeSeat(_playerActor: Actor): (string?, CFrame?)
	local bots = ActorService.GetBots()
	if #bots == 0 then
		return nil, nil
	end
	-- On retire un bot de l'équipe qui compte le plus de bots
	local perTeam: { [string]: { Actor } } = {}
	for _, bot in bots do
		if bot.Team then
			perTeam[bot.Team] = perTeam[bot.Team] or {}
			table.insert(perTeam[bot.Team], bot)
		end
	end
	local bestTeam, bestCount = nil, 0
	for _, teamId in Teams.Order do
		local list = perTeam[teamId]
		if list and #list > bestCount then
			bestTeam, bestCount = teamId, #list
		end
	end
	if not bestTeam then
		return nil, nil
	end
	local list = perTeam[bestTeam]
	local bot = list[random:NextInteger(1, #list)]
	RoundState.Participants[bot.Id] = nil
	removeBot(bot)
	return bestTeam, nil
end

function BotService.Cleanup()
	for _, bot in ActorService.GetBots() do
		removeBot(bot)
	end
	for id, brain in brains do
		brain:Destroy()
		brains[id] = nil
	end
	if connection then
		connection:Disconnect()
		connection = nil
	end
end

-- Pour les tests
function BotService.GetBrain(actor: Actor): BotBrain.Brain?
	return brains[actor.Id]
end

return BotService

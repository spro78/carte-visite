--[[
	RoundService.lua
	Machine à états de la partie :
	  Waiting -> Intermission (vote) -> Countdown -> Round -> Results -> Waiting...
	Le serveur décide de tout : il envoie l'état aux clients chaque seconde.

	Points d'extension (branchés par Main.server.lua) :
	  RoundService.SetBotProvider(provider)   -- phase 4 : bots
	  RoundService.SetRewardHandler(handler)  -- phase 6 : pièces et statistiques
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Teams = require(Shared.Teams)
local MapInfo = require(Shared.MapInfo)
local Remotes = require(Shared.Remotes)
local Types = require(Shared.Types)

local ActorService = require(script.Parent.ActorService)
local TeamService = require(script.Parent.TeamService)
local VoteService = require(script.Parent.VoteService)
local MapRegistry = require(script.Parent.MapRegistry)
local LobbyBuilder = require(script.Parent.LobbyBuilder)
local RoundState = require(script.Parent.RoundState)
local CaptureService = require(script.Parent.CaptureService)
local AbilityService = require(script.Parent.AbilityService)
local LaunchService = require(script.Parent.LaunchService)
local MapBase = require(script.Parent.Parent.Maps.MapBase)

type Actor = Types.Actor
type GameState = Types.GameState

local RoundService = {}

-- ---------------------------------------------------------------------------
-- État interne
-- ---------------------------------------------------------------------------
local state: GameState = {
	Phase = "Waiting",
	TimeLeft = 0,
	MapId = nil,
	Candidates = {},
	Votes = {},
	TeamCounts = {},
	Scores = {},
	ScoreGoal = nil,
	ScoreLabel = nil,
	Winner = nil,
	WinReason = nil,
	WinDetail = nil,
	BestHunter = nil,
	BestHunterCaptures = nil,
}

local initialTeamCount = 0
local roundEndRequest: { Winner: string?, Reason: string }? = nil
local roundStartedAt = 0
local objectivesFolder: Folder
local botProvider: any = nil
local rewardHandler: any = nil
local savedLighting: { [string]: any }? = nil
local cleanupCallbacks: { () -> () } = {}

local StateUpdate: RemoteEvent
local Announce: RemoteEvent

-- ---------------------------------------------------------------------------
-- Utilitaires
-- ---------------------------------------------------------------------------
local function log(...)
	if Config.Debug.VerboseLogs then
		print("[RoundService]", ...)
	end
end

local function formatTime(seconds: number): string
	seconds = math.max(0, math.floor(seconds + 0.5))
	return string.format("%d:%02d", seconds // 60, seconds % 60)
end

-- Ambiance lumineuse propre à la map (Map.Lighting), restaurée au nettoyage.
-- Les clés simples sont des propriétés de Lighting ; les sous-tables
-- Atmosphere / ColorCorrection / Bloom / SunRays / Clouds règlent les effets
-- correspondants (créés par LightingSetup).
local EFFECT_CLASSES = {
	Atmosphere = "Atmosphere",
	ColorCorrection = "ColorCorrectionEffect",
	Bloom = "BloomEffect",
	SunRays = "SunRaysEffect",
}

local function lightingTarget(key: string): Instance?
	local Lighting = game:GetService("Lighting")
	if key == "Clouds" then
		return workspace.Terrain:FindFirstChildOfClass("Clouds")
	end
	local className = EFFECT_CLASSES[key]
	if className then
		return Lighting:FindFirstChildOfClass(className)
	end
	return nil
end

-- Applique des valeurs sur une instance et retourne les anciennes valeurs
local function applyProps(target: Instance, values: { [string]: any }): { [string]: any }
	local previous = {}
	for key, value in values do
		local ok, current = pcall(function()
			return (target :: any)[key]
		end)
		if ok then
			previous[key] = current
			pcall(function()
				(target :: any)[key] = value
			end)
		end
	end
	return previous
end

local function applyLighting(preset: { [string]: any }?)
	local Lighting = game:GetService("Lighting")
	if preset then
		local saved: { [string]: any } = {}
		local plain: { [string]: any } = {}
		for key, value in preset do
			if type(value) == "table" then
				local target = lightingTarget(key)
				if target then
					saved[key] = applyProps(target, value)
				end
			else
				plain[key] = value
			end
		end
		saved.__Lighting = applyProps(Lighting, plain)
		savedLighting = saved
	elseif savedLighting then
		for key, values in savedLighting do
			local target = if key == "__Lighting" then Lighting else lightingTarget(key)
			if target then
				applyProps(target, values)
			end
		end
		savedLighting = nil
	end
end

local function setPhase(phase: string)
	state.Phase = phase
	RoundState.Phase = phase
end

local function announce(text: string, color: Color3?)
	Announce:FireAllClients(text, color)
end

local function announceTo(actor: Actor, text: string, color: Color3?)
	ActorService.FireClient(actor, Announce, text, color)
end

-- Texte du panneau géant du lobby selon la phase
local function updateLobbyBoard()
	local mapDef = MapInfo.Get(state.MapId)
	local mapText = mapDef and (mapDef.DisplayName .. " - " .. mapDef.ModeName) or ""
	if state.Phase == "Waiting" then
		LobbyBuilder.SetBoard("Waiting for players...", "--:--", "")
	elseif state.Phase == "Intermission" then
		local leader = MapInfo.Get(VoteService.GetLeader())
		LobbyBuilder.SetBoard("Next round in", formatTime(state.TimeLeft), leader and ("Leading: " .. leader.DisplayName) or "Vote for a map!")
	elseif state.Phase == "Countdown" then
		LobbyBuilder.SetBoard("Round starting", formatTime(state.TimeLeft), mapText)
	elseif state.Phase == "Round" then
		LobbyBuilder.SetBoard("Round in progress", formatTime(state.TimeLeft), mapText)
	elseif state.Phase == "Results" then
		local winnerDef = Teams.Get(state.Winner)
		LobbyBuilder.SetBoard(winnerDef and (winnerDef.Plural .. " WIN!") or "DRAW!", formatTime(state.TimeLeft), mapText)
	end
end

local function broadcastState()
	state.TeamCounts = TeamService.GetCounts(RoundState.GetParticipants())
	state.Candidates = VoteService.GetCandidates()
	state.Votes = VoteService.GetCounts()
	StateUpdate:FireAllClients(state)
	updateLobbyBoard()
end

-- Chronomètre d'une phase : envoie l'état chaque seconde.
local function runTimer(seconds: number, shouldBreak: (() -> boolean)?)
	local endTime = os.clock() + seconds
	while true do
		local left = endTime - os.clock()
		state.TimeLeft = math.max(0, math.ceil(left))
		broadcastState()
		if left <= 0 then
			break
		end
		if shouldBreak and shouldBreak() then
			break
		end
		task.wait(math.min(Config.Round.StateBroadcastInterval, left))
	end
end

-- ---------------------------------------------------------------------------
-- Personnages : téléportation, protection, gel
-- ---------------------------------------------------------------------------
local function teleport(actor: Actor, cframe: CFrame)
	local character = actor.Character
	if character and character:FindFirstChild("HumanoidRootPart") then
		character:PivotTo(cframe)
		local root = ActorService.GetRoot(actor)
		if root then
			root.AssemblyLinearVelocity = Vector3.zero
		end
	end
end

local function getBaseSpawn(teamId: string): CFrame?
	local map = RoundState.Map
	if not map then
		return nil
	end
	local spawns = map.GetSpawns(teamId)
	if not spawns or #spawns == 0 then
		return nil
	end
	return spawns[math.random(#spawns)]
end

local function teleportToBase(actor: Actor)
	if not actor.Team then
		return
	end
	local cframe = getBaseSpawn(actor.Team)
	if cframe then
		teleport(actor, cframe)
	end
end

local function teleportToLobby(actor: Actor)
	teleport(actor, LobbyBuilder.GetSpawnCFrame())
end

local function setFrozen(actor: Actor, frozen: boolean)
	ActorService.SetCharacterAttribute(actor, "Frozen", frozen or nil)
end

-- Un personnage (ré)apparaît
local function onCharacterAdded(actor: Actor, character: Model)
	local root = character:WaitForChild("HumanoidRootPart", 10)
	if not root then
		return
	end
	local deadline = os.clock() + 5
	while not character:IsDescendantOf(workspace) and os.clock() < deadline do
		task.wait()
	end
	task.wait()
	if actor.Character ~= character then
		return
	end
	character:SetAttribute("Carrier", nil)
	if RoundState.IsParticipant(actor) and RoundState.IsInRound() then
		teleportToBase(actor)
		CaptureService.Protect(character, Config.Capture.InvincibilitySeconds)
		if state.Phase == "Countdown" and Config.Round.FreezeDuringCountdown then
			setFrozen(actor, true)
		end
		if RoundState.Map and RoundState.Map.OnActorRemoved then
			-- Une réapparition fait perdre ce que l'acteur portait
			RoundState.Map.OnActorRemoved(actor)
		end
	elseif not actor.IsBot then
		teleportToLobby(actor)
	end
end

-- ---------------------------------------------------------------------------
-- Objectifs (flèche) : répliqués via des attributs
-- ---------------------------------------------------------------------------
local function setTeamObjective(teamId: string, position: Vector3?)
	objectivesFolder:SetAttribute(teamId, position)
end

local function clearObjectives()
	for _, id in Teams.Order do
		objectivesFolder:SetAttribute(id, nil)
	end
	for _, actor in ActorService.GetAll() do
		ActorService.SetCharacterAttribute(actor, "ObjectiveTarget", nil)
		ActorService.SetCharacterAttribute(actor, "Carrier", nil)
	end
end

-- ---------------------------------------------------------------------------
-- Contexte fourni aux maps
-- ---------------------------------------------------------------------------
local context: Types.MapContext = {
	Origin = Config.World.MapOrigin,
	GetActors = RoundState.GetParticipants,
	GetTeam = function(actor: Actor)
		return actor.Team
	end,
	GetRoot = ActorService.GetRoot,
	AddScore = function(teamId: string, amount: number)
		if not Teams.IsValid(teamId) then
			return
		end
		state.Scores[teamId] = (state.Scores[teamId] or 0) + amount
		broadcastState()
	end,
	SetScore = function(teamId: string, value: number)
		if not Teams.IsValid(teamId) then
			return
		end
		state.Scores[teamId] = value
		broadcastState()
	end,
	GetScore = function(teamId: string)
		return state.Scores[teamId] or 0
	end,
	SetScoreInfo = function(goal: number?, label: string?)
		state.ScoreGoal = goal
		state.ScoreLabel = label
	end,
	Announce = announce,
	AnnounceTo = announceTo,
	RewardObjective = function(actor: Actor, reason: string)
		actor.RoundObjectives += 1
		if rewardHandler and rewardHandler.OnObjective then
			rewardHandler.OnObjective(actor, reason)
		end
	end,
	Launch = function(actor: Actor, velocity: Vector3, ragdoll: number?)
		LaunchService.Launch(actor, velocity, ragdoll)
	end,
	SetSpeedModifier = function(actor: Actor, key: string, multiplier: number?)
		AbilityService.SetSpeedModifier(actor, key, multiplier)
	end,
	SetObjective = setTeamObjective,
	SetActorObjective = function(actor: Actor, position: Vector3?)
		ActorService.SetCharacterAttribute(actor, "ObjectiveTarget", position)
	end,
	SetCarrier = function(actor: Actor, carrying: boolean)
		ActorService.SetCharacterAttribute(actor, "Carrier", carrying or nil)
		if carrying then
			ActorService.SetCharacterAttribute(actor, "Hidden", nil)
		end
	end,
	EndRound = function(winnerTeam: string?, reason: string)
		if state.Phase ~= "Round" or roundEndRequest then
			return
		end
		roundEndRequest = { Winner = winnerTeam, Reason = reason or "Objective" }
	end,
	IsRoundActive = function()
		return state.Phase == "Round"
	end,
}

-- ---------------------------------------------------------------------------
-- Phases
-- ---------------------------------------------------------------------------
local function resetResults()
	state.MapId = nil
	state.Winner = nil
	state.WinReason = nil
	state.WinDetail = nil
	state.BestHunter = nil
	state.BestHunterCaptures = nil
	state.Podium = nil
	state.Scores = {}
	state.ScoreGoal = nil
	state.ScoreLabel = nil
end

local function waitForPlayers()
	setPhase("Waiting")
	resetResults()
	while #Players:GetPlayers() < Config.Round.MinPlayersToStart do
		state.TimeLeft = 0
		broadcastState()
		task.wait(1)
	end
end

-- Retourne false si l'intermission a été annulée (plus assez de joueurs).
local function intermission(): boolean
	setPhase("Intermission")
	VoteService.StartVote(MapRegistry.PickRotation(Config.Round.VoteCandidates))
	log("Intermission, candidates:", table.concat(VoteService.GetCandidates(), ", "))

	runTimer(Config.GetIntermissionSeconds(), function()
		return #Players:GetPlayers() < Config.Round.MinPlayersToStart
	end)

	if #Players:GetPlayers() < Config.Round.MinPlayersToStart then
		VoteService.EndVote()
		return false
	end
	state.MapId = VoteService.GetWinner()
	local forced = Config.Debug.ForceMap
	if forced and MapRegistry.Get(forced) then
		state.MapId = forced
	end
	VoteService.EndVote()
	if state.MapId then
		MapRegistry.MarkPlayed(state.MapId)
	end
	local chosen = MapInfo.Get(state.MapId)
	if chosen then
		announce("Next map: " .. chosen.DisplayName .. " (" .. chosen.ModeName .. ")", chosen.Color)
	end
	return state.MapId ~= nil
end

local function setupRound()
	local mapId = state.MapId :: string
	local map = MapRegistry.Get(mapId)
	assert(map, "Map introuvable : " .. tostring(mapId))
	log("Building map", mapId)
	RoundState.MapId = mapId
	RoundState.Map = map
	map.Build(Config.World.MapOrigin, context)
	if map.Lighting then
		applyLighting(map.Lighting)
	end

	CaptureService.ResetRound()
	table.clear(RoundState.Participants)
	state.Scores = {}
	for _, id in Teams.Order do
		state.Scores[id] = 0
	end
	state.ScoreGoal = nil
	state.ScoreLabel = nil
	roundEndRequest = nil
	clearObjectives()

	-- Participants : tous les vrais joueurs présents
	local humans: { Actor } = {}
	for _, player in Players:GetPlayers() do
		local actor = ActorService.FromPlayer(player)
		if actor then
			table.insert(humans, actor)
		end
	end
	for _, actor in humans do
		RoundState.Participants[actor.Id] = true
		actor.RoundCaptures = 0
		actor.RoundObjectives = 0
		actor.LastCaughtAt = os.clock()
		actor.BestSurvival = 0
	end
	TeamService.AssignBalanced(humans)

	-- Bots : complètent chaque équipe (phase 4)
	if botProvider then
		local bots = botProvider.SpawnForRound(humans, context)
		for _, bot in bots do
			RoundState.Participants[bot.Id] = true
			bot.RoundCaptures = 0
			bot.RoundObjectives = 0
			bot.LastCaughtAt = os.clock()
			bot.BestSurvival = 0
		end
	end

	local participants = RoundState.GetParticipants()
	initialTeamCount = #TeamService.GetNonEmptyTeams(participants)

	local protection = Config.Round.CountdownSeconds + Config.Round.BaseProtectionSeconds
	for _, actor in participants do
		teleportToBase(actor)
		AbilityService.ResetCooldowns(actor)
		AbilityService.ClearModifiers(actor)
		if actor.Character then
			CaptureService.Protect(actor.Character, protection)
		end
		if Config.Round.FreezeDuringCountdown then
			setFrozen(actor, true)
		end
		local def = Teams.Get(actor.Team)
		if def then
			announceTo(actor, "You are a " .. def.Display .. "!", def.Color)
		end
	end
end

local function countdown()
	setPhase("Countdown")
	local mapDef = MapInfo.Get(state.MapId)
	if mapDef then
		task.delay(1.5, function()
			if state.Phase == "Countdown" then
				announce(mapDef.Tagline, Color3.fromRGB(255, 230, 150))
			end
		end)
	end
	runTimer(Config.Round.CountdownSeconds)
	for _, actor in RoundState.GetParticipants() do
		setFrozen(actor, false)
	end
	announce("GO!")
end

-- Vrai si une seule équipe (ou aucune) a encore des membres
local function checkLastTeamStanding(): boolean
	if initialTeamCount < Config.Round.MinTeamsForLastStanding then
		return false
	end
	local list = RoundState.GetParticipants()
	if #list == 0 then
		roundEndRequest = { Winner = nil, Reason = "Draw" }
		return true
	end
	local nonEmpty = TeamService.GetNonEmptyTeams(list)
	if #nonEmpty <= 1 then
		roundEndRequest = { Winner = nonEmpty[1], Reason = "LastStanding" }
		return true
	end
	return false
end

-- Phrase qui explique la victoire, écrite là où la règle est appliquée
-- (le client l'affiche telle quelle : pas de déduction côté client).
local function plural(teamId: string?): string
	local def = Teams.Get(teamId)
	return def and def.Plural or "?"
end

local function determineWinner()
	local list = RoundState.GetParticipants()
	local counts = TeamService.GetCounts(list)
	if roundEndRequest then
		state.Winner = roundEndRequest.Winner or "DRAW"
		state.WinReason = roundEndRequest.Winner and roundEndRequest.Reason or "Draw"
		local winner = roundEndRequest.Winner
		if state.WinReason == "LastStanding" then
			state.WinDetail = plural(winner) .. " converted everyone!"
		elseif state.WinReason == "Objective" then
			state.WinDetail = string.format("%s reached the goal: %d %s", plural(winner), state.Scores[winner :: string] or 0, state.ScoreLabel or "points")
		else
			state.WinDetail = "Nobody left in the round"
		end
		return
	end
	-- Fin du chrono : la map peut avoir sa propre règle (ex : Raid = plus d'œufs)
	local map = RoundState.Map
	if map and map.ResolveTimeUp then
		local winner = map.ResolveTimeUp()
		if winner then
			state.Winner = winner
			state.WinReason = "TimeUp"
			state.WinDetail = string.format("Time's up: %s had the most %s (%d)", plural(winner), state.ScoreLabel or "points", state.Scores[winner] or 0)
			return
		end
	end
	-- Sinon : équipe la plus nombreuse (règle de base), puis meilleur score, sinon égalité
	local largest = TeamService.GetLargestTeam(list)
	if largest then
		state.Winner = largest
		state.WinReason = "TimeUp"
		state.WinDetail = string.format("Time's up: %s were the biggest team (%d)", plural(largest), counts[largest] or 0)
		return
	end
	local bestTeam, bestScore, tie = nil, -1, false
	for _, id in Teams.Order do
		local score = state.Scores[id] or 0
		if score > bestScore then
			bestTeam, bestScore, tie = id, score, false
		elseif score == bestScore then
			tie = true
		end
	end
	if bestTeam and not tie and bestScore > 0 then
		state.Winner = bestTeam
		state.WinReason = "TimeUp"
		state.WinDetail = string.format("Time's up: teams were tied in size, %s had the best score (%d)", plural(bestTeam), bestScore)
	else
		state.Winner = "DRAW"
		state.WinReason = "Draw"
		state.WinDetail = "Time's up with equal teams: no winner"
	end
end

local function computeBestHunter()
	local best, bestCount = nil, 0
	for _, actor in RoundState.GetParticipants() do
		if actor.RoundCaptures > bestCount then
			best, bestCount = actor, actor.RoundCaptures
		end
	end
	state.BestHunter = best and best.Name or nil
	state.BestHunterCaptures = best and bestCount or nil

	-- Podium : meilleur joueur, plus longue survie, captures
	local now = os.clock()
	local rows = {}
	for _, actor in RoundState.GetParticipants() do
		local survival = math.max(actor.BestSurvival or 0, now - actor.LastCaughtAt)
		table.insert(rows, {
			Actor = actor,
			Survival = survival,
			Catches = actor.RoundCaptures,
			Score = actor.RoundCaptures * 10 + actor.RoundObjectives * 15 + survival / 5,
		})
	end
	local function top(key: string, format: (any) -> string)
		table.sort(rows, function(a, b)
			return a[key] > b[key]
		end)
		local list = {}
		for i = 1, math.min(3, #rows) do
			local row = rows[i]
			local userId = row.Actor.Player and row.Actor.Player.UserId or 0
			table.insert(list, { Name = row.Actor.Name, UserId = userId, Value = format(row), Team = row.Actor.Team })
		end
		return list
	end
	state.Podium = {
		MVP = top("Score", function(row)
			return string.format("%d pts", math.floor(row.Score))
		end),
		Survival = top("Survival", function(row)
			return string.format("%.1fs", row.Survival)
		end),
		Catches = top("Catches", function(row)
			return tostring(row.Catches)
		end),
	}
end

local function playRound()
	setPhase("Round")
	roundStartedAt = os.clock()
	log("Round started on", state.MapId)
	local map = RoundState.Map
	map.StartMode(context)
	runTimer(Config.GetRoundSeconds(), function()
		return roundEndRequest ~= nil or checkLastTeamStanding()
	end)
	map.StopMode()
	determineWinner()
	computeBestHunter()
	log("Round over. Winner:", state.Winner, "Reason:", state.WinReason, "Scores:", state.Scores.FOX, state.Scores.CHICKEN, state.Scores.SNAKE)
end

local function results()
	setPhase("Results")
	local winnerDef = Teams.Get(state.Winner)
	if winnerDef then
		announce(winnerDef.Plural .. " WIN!", winnerDef.Color)
	else
		announce("It's a draw!")
	end
	if rewardHandler and rewardHandler.OnRoundEnd then
		local ok, err = pcall(rewardHandler.OnRoundEnd, RoundState.GetParticipants(), state.Winner, os.clock() - roundStartedAt)
		if not ok then
			warn("[RoundService] Erreur de récompense : " .. tostring(err))
		end
	end
	runTimer(Config.GetResultsSeconds())
end

local function cleanup()
	local map = RoundState.Map
	if map then
		local ok, err = pcall(map.Cleanup)
		if not ok then
			warn("[RoundService] Erreur de nettoyage de la map : " .. tostring(err))
		end
	end
	-- Relief en Terrain de la map (commun à toutes les maps)
	local okTerrain, errTerrain = pcall(MapBase.ClearArena, Config.World.MapOrigin)
	if not okTerrain then
		warn("[RoundService] Erreur de nettoyage du terrain : " .. tostring(errTerrain))
	end
	RoundState.Map = nil
	RoundState.MapId = nil
	applyLighting(nil)
	clearObjectives()
	if botProvider then
		botProvider.Cleanup()
	end
	for _, callback in cleanupCallbacks do
		local ok, err = pcall(callback)
		if not ok then
			warn("[RoundService] Erreur de nettoyage : " .. tostring(err))
		end
	end
	table.clear(RoundState.Participants)
	TeamService.ClearAll()
	for _, actor in ActorService.GetAll() do
		AbilityService.ClearModifiers(actor)
		AbilityService.ResetCooldowns(actor)
		setFrozen(actor, false)
	end
	for _, player in Players:GetPlayers() do
		-- Rechargement du personnage : retour propre au lobby
		player:LoadCharacter()
	end
	resetResults()
	setPhase("Waiting")
	log("Cleanup done")
end

-- ---------------------------------------------------------------------------
-- Arrivées et départs en cours de manche
-- ---------------------------------------------------------------------------
local function onActorAdded(actor: Actor)
	if actor.IsBot or not RoundState.IsInRound() then
		return
	end
	-- Un joueur arrive en cours de manche : il prend la place d'un bot si possible,
	-- sinon il attend dans le lobby en spectateur.
	task.delay(1, function()
		if not RoundState.IsInRound() or RoundState.IsParticipant(actor) or ActorService.Get(actor.Id) == nil then
			return
		end
		local team: string?, cframe: CFrame? = nil, nil
		if botProvider and Config.Bots.JoinerReplacesBot then
			team, cframe = botProvider.TakeSeat(actor)
		end
		-- Pas de bot à remplacer : on rejoint quand même la plus petite équipe
		-- encore en jeu, si la manche n'est pas trop avancée (arrivée rapide).
		if not team then
			local elapsed = RoundState.Phase == "Round" and (os.clock() - roundStartedAt) or 0
			if Config.Round.LateJoinSeconds > 0 and elapsed <= Config.Round.LateJoinSeconds then
				local participants = RoundState.GetParticipants()
				local counts = TeamService.GetCounts(participants)
				local best: string? = nil
				for _, id in TeamService.GetNonEmptyTeams(participants) do
					if best == nil or (counts[id] or 0) < (counts[best] or 0) then
						best = id
					end
				end
				team = best
			end
		end
		do
			if team then
				RoundState.Participants[actor.Id] = true
				actor.RoundCaptures = 0
				actor.RoundObjectives = 0
				actor.LastCaughtAt = os.clock()
				actor.BestSurvival = 0
				TeamService.SetTeam(actor, team)
				if cframe then
					teleport(actor, cframe)
				else
					teleportToBase(actor)
				end
				if actor.Character then
					CaptureService.Protect(actor.Character, Config.Capture.InvincibilitySeconds + 1)
				end
				local def = Teams.Get(team)
				if def then
					announceTo(actor, "You joined as a " .. def.Display .. "!", def.Color)
				end
				broadcastState()
				return
			end
		end
		announceTo(actor, "A round is in progress. You'll join the next one!")
	end)
end

local function onActorRemoving(actor: Actor)
	if RoundState.Participants[actor.Id] then
		if RoundState.Map and RoundState.Map.OnActorRemoved then
			RoundState.Map.OnActorRemoved(actor)
		end
		RoundState.Participants[actor.Id] = nil
	end
	LaunchService.Forget(actor)
end

-- Réapparition si chute hors de la map (ou du lobby)
local fallAccumulator = 0
local function checkFalls(dt: number)
	fallAccumulator += dt
	if fallAccumulator < 0.5 then
		return
	end
	fallAccumulator = 0
	local mapFloor = Config.World.MapOrigin.Y + Config.World.KillHeight
	local lobbyFloor = Config.World.LobbyOrigin.Y + Config.World.KillHeight
	for _, actor in ActorService.GetAll() do
		local position = ActorService.GetPosition(actor)
		if position then
			if RoundState.IsParticipant(actor) and RoundState.IsInRound() then
				if position.Y < mapFloor then
					teleportToBase(actor)
					if actor.Character then
						CaptureService.Protect(actor.Character, 1)
					end
				end
			elseif position.Y < lobbyFloor and not actor.IsBot then
				teleportToLobby(actor)
			end
		end
	end
end

-- ---------------------------------------------------------------------------
-- API publique
-- ---------------------------------------------------------------------------
function RoundService.GetPhase(): string
	return state.Phase
end

function RoundService.GetState(): GameState
	return state
end

function RoundService.GetContext(): Types.MapContext
	return context
end

function RoundService.SetBotProvider(provider: any)
	botProvider = provider
end

function RoundService.SetRewardHandler(handler: any)
	rewardHandler = handler
end

-- Fonction appelée au nettoyage de chaque fin de manche
function RoundService.OnCleanup(callback: () -> ())
	table.insert(cleanupCallbacks, callback)
end

function RoundService.Broadcast()
	broadcastState()
end

-- ---------------------------------------------------------------------------
-- Démarrage
-- ---------------------------------------------------------------------------
function RoundService.Init()
	StateUpdate = Remotes.Get("StateUpdate")
	Announce = Remotes.Get("Announce")

	local folder = Instance.new("Folder")
	folder.Name = "HoH_Objectives"
	folder.Parent = ReplicatedStorage
	objectivesFolder = folder

	ActorService.CharacterAdded:Connect(onCharacterAdded)
	ActorService.ActorAdded:Connect(onActorAdded)
	ActorService.ActorRemoving:Connect(onActorRemoving)
	for _, actor in ActorService.GetAll() do
		if actor.Character then
			task.spawn(onCharacterAdded, actor, actor.Character)
		end
	end

	CaptureService.Captured:Connect(function(hunter: Actor, victim: Actor)
		local map = RoundState.Map
		if map and map.OnCapture then
			map.OnCapture(hunter, victim)
		end
		if rewardHandler and rewardHandler.OnCapture then
			rewardHandler.OnCapture(hunter, victim)
		end
		broadcastState()
	end)

	RunService.Heartbeat:Connect(checkFalls)
end

function RoundService.Start()
	task.spawn(function()
		while true do
			waitForPlayers()
			if intermission() then
				local ok, err = pcall(function()
					setupRound()
					countdown()
					playRound()
					results()
				end)
				if not ok then
					warn("[RoundService] Erreur pendant la manche : " .. tostring(err))
					announce("Round error, returning to lobby")
				end
				cleanup()
			end
			task.wait(1)
		end
	end)
end

return RoundService

--[[
	RoundService.lua
	Machine à états de la partie :
	  Waiting -> Intermission (vote) -> Countdown -> Round -> Results -> Waiting...
	Le serveur décide de tout : il envoie l'état complet aux clients chaque seconde.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Teams = require(Shared.Teams)
local MapInfo = require(Shared.MapInfo)
local Remotes = require(Shared.Remotes)
local Types = require(Shared.Types)

local TeamService = require(script.Parent.TeamService)
local VoteService = require(script.Parent.VoteService)
local MapRegistry = require(script.Parent.MapRegistry)
local LobbyBuilder = require(script.Parent.LobbyBuilder)
local AnimalAppearance = require(script.Parent.AnimalAppearance)

local RoundService = {}

type GameState = Types.GameState

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
	Winner = nil,
	WinReason = nil,
	BestHunter = nil,
	BestHunterCaptures = nil,
}

local participants: { [Player]: boolean } = {} -- joueurs engagés dans la manche en cours
local captures: { [Player]: number } = {} -- captures par joueur (alimenté en phase 2)
local initialTeamCount = 0
local currentMap = nil
local roundEndRequest: { Winner: string?, Reason: string }? = nil

local StateUpdate: RemoteEvent
local Announce: RemoteEvent

local PROTECTED_UNTIL_ATTR = "ProtectedUntil"

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

local function getParticipantList(): { Player }
	local list = {}
	for player in participants do
		if player.Parent == Players then
			table.insert(list, player)
		end
	end
	return list
end

local function announce(text: string, color: Color3?)
	Announce:FireAllClients(text, color)
end

local function announceTo(player: Player, text: string, color: Color3?)
	Announce:FireClient(player, text, color)
end

local function isRoundPhase(): boolean
	return state.Phase == "Countdown" or state.Phase == "Round"
end

-- Texte du panneau géant du lobby selon la phase
local function updateLobbyBoard()
	local mapDef = MapInfo.Get(state.MapId)
	local mapText = mapDef and (mapDef.DisplayName .. " - " .. mapDef.ModeName) or ""
	if state.Phase == "Waiting" then
		local missing = Config.Round.MinPlayersToStart - #Players:GetPlayers()
		LobbyBuilder.SetBoard("Waiting for players...", "--:--", missing > 0 and string.format("Need %d more", missing) or "")
	elseif state.Phase == "Intermission" then
		local leader = MapInfo.Get(VoteService.GetLeader())
		LobbyBuilder.SetBoard("Next round in", formatTime(state.TimeLeft), leader and ("Leading: " .. leader.DisplayName) or "Vote for a map!")
	elseif state.Phase == "Countdown" then
		LobbyBuilder.SetBoard("Round starting", formatTime(state.TimeLeft), mapText)
	elseif state.Phase == "Round" then
		LobbyBuilder.SetBoard("Round in progress", formatTime(state.TimeLeft), mapText)
	elseif state.Phase == "Results" then
		local winnerDef = Teams.Get(state.Winner)
		local title = winnerDef and (winnerDef.Plural .. " WIN!") or "DRAW!"
		LobbyBuilder.SetBoard(title, formatTime(state.TimeLeft), mapText)
	end
end

local function broadcastState()
	state.TeamCounts = TeamService.GetCounts(getParticipantList())
	state.Candidates = VoteService.GetCandidates()
	state.Votes = VoteService.GetCounts()
	StateUpdate:FireAllClients(state)
	updateLobbyBoard()
end

-- Chronomètre d'une phase : envoie l'état chaque seconde.
-- shouldBreak() permet d'interrompre la phase plus tôt.
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
-- Personnages : téléportation et protection
-- ---------------------------------------------------------------------------
local function teleportCharacter(player: Player, cframe: CFrame)
	local character = player.Character
	if not character then
		return
	end
	local root = character:FindFirstChild("HumanoidRootPart")
	if not root then
		return
	end
	character:PivotTo(cframe)
end

local function teleportToBase(player: Player)
	local team = TeamService.GetTeam(player)
	if not team or not currentMap then
		return
	end
	local spawns = currentMap.GetSpawns(team)
	teleportCharacter(player, spawns[math.random(#spawns)])
end

local function teleportToLobby(player: Player)
	teleportCharacter(player, LobbyBuilder.GetSpawnCFrame())
end

-- Protection (ForceField visible + attribut lu par la capture en phase 2)
local function giveProtection(character: Model, seconds: number)
	local until_ = os.clock() + seconds
	character:SetAttribute(PROTECTED_UNTIL_ATTR, until_)
	local existing = character:FindFirstChildOfClass("ForceField")
	if existing then
		existing:Destroy()
	end
	local field = Instance.new("ForceField")
	field.Visible = true
	field.Parent = character
	task.delay(seconds, function()
		if field.Parent == character and (character:GetAttribute(PROTECTED_UNTIL_ATTR) or 0) <= until_ then
			field:Destroy()
		end
	end)
end

function RoundService.IsProtected(character: Model): boolean
	local until_ = character:GetAttribute(PROTECTED_UNTIL_ATTR)
	return type(until_) == "number" and until_ > os.clock()
end

local function onCharacterAdded(player: Player, character: Model)
	-- Attendre que le personnage soit placé dans le monde avant de le déplacer
	local root = character:WaitForChild("HumanoidRootPart", 10)
	if not root then
		return
	end
	local deadline = os.clock() + 5
	while not character:IsDescendantOf(workspace) and os.clock() < deadline do
		task.wait()
	end
	task.wait()
	if player.Character ~= character then
		return
	end

	if participants[player] and isRoundPhase() then
		AnimalAppearance.Apply(character, TeamService.GetTeam(player))
		teleportToBase(player)
		giveProtection(character, Config.Capture.InvincibilitySeconds)
	else
		AnimalAppearance.Apply(character, nil)
		teleportToLobby(player)
	end
end

local function onPlayerAdded(player: Player)
	captures[player] = captures[player] or 0
	player.CharacterAdded:Connect(function(character)
		onCharacterAdded(player, character)
	end)
	if player.Character then
		task.spawn(onCharacterAdded, player, player.Character)
	end
	if isRoundPhase() then
		-- Arrivée en cours de manche : spectateur dans le lobby
		task.delay(2, function()
			if player.Parent == Players and isRoundPhase() and not participants[player] then
				announceTo(player, "A round is in progress. You'll join the next one!")
			end
		end)
	end
end

local function onPlayerRemoving(player: Player)
	participants[player] = nil
	captures[player] = nil
end

-- ---------------------------------------------------------------------------
-- Contexte fourni aux maps
-- ---------------------------------------------------------------------------
local context: Types.MapContext = {
	Origin = Config.World.MapOrigin,
	GetParticipants = getParticipantList,
	GetTeam = TeamService.GetTeam,
	AddScore = function(teamId, amount)
		if not Teams.IsValid(teamId) then
			return
		end
		state.Scores[teamId] = (state.Scores[teamId] or 0) + amount
		broadcastState()
	end,
	GetScore = function(teamId)
		return state.Scores[teamId] or 0
	end,
	Announce = announce,
	EndRound = function(winnerTeam, reason)
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
local function waitForPlayers()
	state.Phase = "Waiting"
	state.MapId = nil
	state.Winner = nil
	state.WinReason = nil
	state.BestHunter = nil
	state.BestHunterCaptures = nil
	state.Scores = {}
	while #Players:GetPlayers() < Config.Round.MinPlayersToStart do
		state.TimeLeft = 0
		broadcastState()
		task.wait(1)
	end
end

-- Retourne false si l'intermission a été annulée (plus assez de joueurs).
local function intermission(): boolean
	state.Phase = "Intermission"
	VoteService.StartVote(MapRegistry.PickRandom(Config.Round.VoteCandidates))
	log("Intermission, candidates:", table.concat(VoteService.GetCandidates(), ", "))

	runTimer(Config.GetIntermissionSeconds(), function()
		return #Players:GetPlayers() < Config.Round.MinPlayersToStart
	end)

	if #Players:GetPlayers() < Config.Round.MinPlayersToStart then
		VoteService.EndVote()
		return false
	end
	state.MapId = VoteService.GetWinner()
	VoteService.EndVote()
	return state.MapId ~= nil
end

local function setupRound()
	currentMap = MapRegistry.Get(state.MapId)
	assert(currentMap, "Map introuvable : " .. tostring(state.MapId))
	log("Building map", state.MapId)
	currentMap.Build(Config.World.MapOrigin, context)

	participants = {}
	captures = {}
	state.Scores = {}
	for _, id in Teams.Order do
		state.Scores[id] = 0
	end
	roundEndRequest = nil

	local players = Players:GetPlayers()
	for _, player in players do
		participants[player] = true
		captures[player] = 0
	end
	TeamService.AssignBalanced(players)
	initialTeamCount = #TeamService.GetNonEmptyTeams(players)

	local protection = Config.Round.CountdownSeconds + Config.Round.BaseProtectionSeconds
	for _, player in players do
		teleportToBase(player)
		if player.Character then
			giveProtection(player.Character, protection)
		end
		local team = TeamService.GetTeam(player)
		local def = Teams.Get(team)
		if def then
			announceTo(player, "You are a " .. def.Display .. "!", def.Color)
		end
	end
end

local function countdown()
	state.Phase = "Countdown"
	runTimer(Config.Round.CountdownSeconds)
	announce("GO!")
end

-- Vrai si une seule équipe (ou aucune) a encore des membres
local function checkLastTeamStanding(): boolean
	if initialTeamCount < Config.Round.MinTeamsForLastStanding then
		return false
	end
	local list = getParticipantList()
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

local function determineWinner()
	if roundEndRequest then
		state.Winner = roundEndRequest.Winner or "DRAW"
		state.WinReason = roundEndRequest.Reason
		return
	end
	-- Fin du chrono : équipe la plus nombreuse, puis meilleur score, sinon égalité
	local list = getParticipantList()
	local largest = TeamService.GetLargestTeam(list)
	if largest then
		state.Winner = largest
		state.WinReason = "TimeUp"
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
	else
		state.Winner = "DRAW"
		state.WinReason = "Draw"
	end
end

local function computeBestHunter()
	local best, bestCount = nil, 0
	for player, count in captures do
		if count > bestCount and player.Parent == Players then
			best, bestCount = player, count
		end
	end
	if best then
		state.BestHunter = best.DisplayName
		state.BestHunterCaptures = bestCount
	else
		state.BestHunter = nil
		state.BestHunterCaptures = nil
	end
end

local function playRound()
	state.Phase = "Round"
	log("Round started on", state.MapId)
	currentMap.StartMode(context)
	runTimer(Config.GetRoundSeconds(), function()
		return roundEndRequest ~= nil or checkLastTeamStanding()
	end)
	currentMap.StopMode()
	determineWinner()
	computeBestHunter()
	log("Round over. Winner:", state.Winner, "Reason:", state.WinReason)
end

local function results()
	state.Phase = "Results"
	local winnerDef = Teams.Get(state.Winner)
	if winnerDef then
		announce(winnerDef.Plural .. " WIN!", winnerDef.Color)
	else
		announce("It's a draw!")
	end
	runTimer(Config.GetResultsSeconds())
end

local function cleanup()
	if currentMap then
		currentMap.Cleanup()
		currentMap = nil
	end
	participants = {}
	TeamService.ClearAll()
	for _, player in Players:GetPlayers() do
		-- Rechargement du personnage : retour propre au lobby
		player:LoadCharacter()
	end
	state.MapId = nil
	state.Scores = {}
	log("Cleanup done")
end

-- ---------------------------------------------------------------------------
-- API publique (utilisée par les phases suivantes)
-- ---------------------------------------------------------------------------
function RoundService.GetPhase(): string
	return state.Phase
end

function RoundService.GetState(): GameState
	return state
end

function RoundService.IsParticipant(player: Player): boolean
	return participants[player] == true
end

function RoundService.GetParticipants(): { Player }
	return getParticipantList()
end

function RoundService.GetContext(): Types.MapContext
	return context
end

-- Enregistre une capture (phase 2) et met à jour l'état.
function RoundService.RecordCapture(hunter: Player)
	if captures[hunter] ~= nil then
		captures[hunter] += 1
	end
end

function RoundService.GiveProtection(character: Model, seconds: number)
	giveProtection(character, seconds)
end

function RoundService.Announce(text: string, color: Color3?)
	announce(text, color)
end

function RoundService.AnnounceTo(player: Player, text: string, color: Color3?)
	announceTo(player, text, color)
end

-- ---------------------------------------------------------------------------
-- Démarrage
-- ---------------------------------------------------------------------------
function RoundService.Init()
	StateUpdate = Remotes.Get("StateUpdate")
	Announce = Remotes.Get("Announce")

	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	for _, player in Players:GetPlayers() do
		onPlayerAdded(player)
	end
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

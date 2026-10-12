--!nocheck
--[[
	test_carousel.luau : CAROUSEL VALLEY, carte héroïque (simulation).
	Vérifie avec le vrai code serveur et client, sur trois vraies manches :
	  - le vote présente trois modes distincts (CHASE, EGG RUN, CAROUSEL) avec
	    leur règle, le nombre de voix, le nom des votants et tous les joueurs ;
	  - l'option gagnante (mode + carte) est celle qui est jouée, l'égalité va
	    au mode joué il y a le plus longtemps ;
	  - le décompte présente la composition des trois équipes ;
	  - EGG RUN : œufs dans les nids, ramassage, porteur ralenti, dépôt dans la
	    zone sûre de son camp, œuf lâché si le porteur est attrapé, victoire ;
	  - CAROUSEL : trois anneaux mobiles sous les chevaux volants, points à la
	    majorité, égalité sans point, anneau aux couleurs du détenteur, sens qui
	    s'inverse, piste jamais dans une zone sûre, victoire ;
	  - CHASE : pas de score, fin à la dernière équipe debout ;
	  - rotation équitable des équipes : personne ne garde le même animal deux
	    manches de suite.
	Ne remplace pas un test dans Roblox Studio (collisions réelles des volumes
	du kit, meshes construits par EditableMesh, sensation en vraie partie).
]]
local H = require("./harness")
local World, Engine = H.World, H.Engine
local roblox = H.Roblox
local Vector3 = roblox.Vector3
local check, section = H.check, H.section

local server = H.boot(function(Config)
	Config.Debug.DisableBots = true
	Config.Modes.EggRun.EggsToWin = 2
	Config.Modes.EggRun.DropReturnSeconds = 6
	Config.Modes.Carousel.PointsToWin = 14
	Config.Modes.Carousel.ReverseEverySeconds = 5
end)
local Config = server.Config
local Teams = server.Teams
local O = Config.World.MapOrigin
local services = World.game.ServerScriptService.Server.Services
local VoteService = H.require(services.VoteService)
local SafeZoneService = H.require(services.SafeZoneService)
local MapBase = H.require(World.game.ServerScriptService.Server.Maps.MapBase)
local Map = H.require(World.game.ServerScriptService.Server.Maps.TheCarousel)
local CarouselMode = H.require(World.game.ServerScriptService.Server.Modes.Carousel)

local names = { "Alice", "Bob", "Carl", "Dana", "Eve", "Finn" }
local players = {}
for i, name in names do
	players[name] = World.AddPlayer(name, { client = i == 1 })
end
local alice = players.Alice
local function actor(name)
	return server.ActorService.FromPlayer(players[name])
end
local function root(name)
	return players[name].Character.HumanoidRootPart
end
local function state()
	return server.RoundService.GetState()
end
local function hud()
	return alice.PlayerGui:FindFirstChild("HuntOrHideHUD")
end
local roundTeams = {} -- [manche] = { nom = équipe attribuée }
local function recordTeams(round)
	roundTeams[round] = {}
	for _, name in names do
		roundTeams[round][name] = actor(name).Team
	end
end
-- Tout le monde loin de tout (aucune capture parasite)
local function parkAll(except)
	for i, name in names do
		if not (except and except[name]) then
			local a = math.rad(i * 60)
			H.teleport(actor(name), O + Vector3.new(math.cos(a) * 140, 3, math.sin(a) * 140 * 0.2 - 130))
		end
	end
end
local function voteFor(name, modeId)
	local option = nil
	for _, candidate in VoteService.GetCandidates() do
		if string.sub(candidate, -#modeId - 1) == "/" .. modeId then
			option = candidate
		end
	end
	H.onServer(function()
		VoteService.CastVote(players[name], option)
	end)
	return option
end

-- ---------------------------------------------------------------------------
section("Vote : trois modes, leur règle et tous les joueurs")
check(H.advanceUntil(function()
	return H.phase() == "Intermission"
end, 60), "intermission")
Engine.Advance(1.2)
local candidates = VoteService.GetCandidates()
local modes = {}
for _, option in candidates do
	local mapId, modeId = string.match(option, "^(.-)/(.-)$")
	if mapId == "TheCarousel" then
		modes[modeId] = true
	end
end
check(#candidates == 3 and modes.Chase and modes.EggRun and modes.Carousel, "options : " .. table.concat(candidates, ", "))
local panel = hud().VotePanel
check(panel.Visible, "panneau de vote affiché")
local cards = {}
for i = 1, 3 do
	local card = panel:FindFirstChild("Vote" .. i, true)
	cards[i] = card
end
local okCards = true
for _, card in cards do
	local rules = card:FindFirstChild("Rules")
	local mode = card:FindFirstChild("ModeName")
	if not (card.Visible and mode and mode.Text ~= "" and rules and #rules.Text > 30) then
		okCards = false
	end
end
check(okCards, "chaque carte : nom du mode, carte, règle en trois lignes")
-- Alice vote à la souris, Bob et Carl par les plaques/remote
local eggCard
for _, card in cards do
	if card.ModeName.Text == "EGG RUN" then
		eggCard = card
	end
end
eggCard.Activated:Fire()
voteFor("Bob", "EggRun")
voteFor("Carl", "Carousel")
Engine.Advance(1.2)
check(string.find(VoteService.GetPlayerVote(alice) or "", "EggRun", 1, true) ~= nil, "le clic d'Alice compte pour EGG RUN (serveur)")
local votesText = eggCard:FindFirstChild("Votes").Text
check(string.find(votesText, "2 votes", 1, true) and string.find(votesText, "Alice", 1, true) and string.find(votesText, "Bob", 1, true), "carte EGG RUN : " .. votesText)
local rosterText = panel:FindFirstChild("Roster").Text
check(string.find(rosterText, "6 players", 1, true) and string.find(rosterText, "Dana", 1, true), "tous les joueurs listés, ceux qu'on attend nommés : " .. rosterText)
-- Plaques du lobby : nom du mode
local lobby = World.workspace:FindFirstChild("Lobby", true)
local plateText = {}
for _, d in World.workspace:GetDescendants() do
	if string.sub(d.Name, 1, 10) == "VoteScreen" and d:FindFirstChildOfClass("SurfaceGui") then
		for _, label in d:FindFirstChildOfClass("SurfaceGui"):GetChildren() do
			if label:IsA("TextLabel") then
				plateText[label.Text] = true
			end
		end
	end
end
check(plateText["EGG RUN"] and plateText["CAROUSEL"] and plateText["CHASE"] and plateText["Carousel Valley"], "écrans du lobby : modes et carte")

check(H.advanceUntil(function()
	return H.phase() == "Countdown"
end, 30), "décompte")
check(state().MapId == "TheCarousel" and state().ModeId == "EggRun", "option gagnante jouée : " .. tostring(state().ModeId) .. " sur " .. tostring(state().MapId))
Engine.Advance(0.6)
local lineup = hud():FindFirstChild("Lineup")
local listed = 0
for _, teamId in Teams.Order do
	local column = lineup and lineup:FindFirstChild(teamId)
	local text = column and column:FindFirstChild("Names") and column.Names.Text or ""
	for _, name in names do
		if string.find(text, name, 1, true) then
			listed += 1
		end
	end
end
check(lineup and lineup.Visible and listed == 6, string.format("décompte : composition des équipes (%d joueurs sur 6)", listed))
recordTeams(1)
local counts = {}
for _, name in names do
	counts[actor(name).Team] = (counts[actor(name).Team] or 0) + 1
end
check(counts.FOX == 2 and counts.CHICKEN == 2 and counts.SNAKE == 2, "équipes équilibrées (2 / 2 / 2)")

-- ---------------------------------------------------------------------------
section("EGG RUN")
check(H.advanceUntil(function()
	return H.phase() == "Round"
end, 10), "manche lancée")
parkAll()
Engine.Advance(2.5)
local debug = Map.DebugState().Mode
check(debug and debug.Mode == "EggRun" and #debug.Eggs == 3, "trois œufs en jeu")
local inNests = true
for _, egg in debug.Eggs do
	if egg.State ~= "Nest" then
		inNests = false
	end
end
check(inNests, "chacun dans un nid (un nid entre chaque paire de camps)")
check(state().ScoreGoal == Config.Modes.EggRun.EggsToWin and state().ScoreLabel == "eggs", "objectif affiché : " .. tostring(state().ScoreGoal) .. " " .. tostring(state().ScoreLabel))
-- Alice ramasse un œuf
local target = debug.Eggs[1].Position
H.teleport(actor("Alice"), Vector3.new(target.X, O.Y + 3, target.Z) + Vector3.new(1.5, 0, 0))
Engine.Advance(0.4)
check(Map.IsCarrier(actor("Alice")) and alice.Character:GetAttribute("Carrier") == true, "Alice porte un œuf")
check(math.abs((alice.Character:GetAttribute("SpeedMult") or 1) - Config.Modes.EggRun.CarrierSpeedMultiplier) < 0.01, "porteuse ralentie")
check(typeof(alice.Character:GetAttribute("ObjectiveTarget")) == "Vector3", "la flèche pointe vers son camp")
-- Elle rentre dans la zone sûre de son camp : +1
local myTeam = actor("Alice").Team
local base = MapBase.ActiveBases[myTeam]
H.teleport(actor("Alice"), base.CFrame:PointToWorldSpace(Vector3.new(0, 0, 4)) + Vector3.new(0, 3, 0))
Engine.Advance(0.4)
check(state().Scores[myTeam] == 1 and not Map.IsCarrier(actor("Alice")), "œuf déposé dans le camp : 1 œuf pour " .. myTeam)
check(alice.Character:GetAttribute("Carrier") == nil and math.abs((alice.Character:GetAttribute("SpeedMult") or 1) - 1) < 0.01, "plus porteuse, vitesse normale")
Engine.Advance(Config.Modes.EggRun.RespawnDelay + 0.5)
check(#Map.DebugState().Mode.Eggs == 3, "un nouvel œuf remplace celui marqué")
-- Porteuse attrapée : l'œuf tombe
parkAll()
Engine.Advance(0.3)
debug = Map.DebugState().Mode
local egg2
for _, egg in debug.Eggs do
	if egg.State == "Nest" then
		egg2 = egg
	end
end
H.teleport(actor("Alice"), Vector3.new(egg2.Position.X, O.Y + 3, egg2.Position.Z) + Vector3.new(1.5, 0, 0))
Engine.Advance(0.4)
check(Map.IsCarrier(actor("Alice")), "Alice reprend un œuf")
local hunterName
for _, name in names do
	if Teams.CanCatch(actor(name).Team, myTeam) then
		hunterName = name
	end
end
Engine.Advance(1.5) -- fin de la protection du chasseur éventuelle
H.teleport(actor(hunterName), root("Alice").Position + Vector3.new(2, 0, 0))
Engine.Advance(0.5)
H.teleport(actor(hunterName), O + Vector3.new(0, 3, -140))
local dropped = nil
for _, egg in Map.DebugState().Mode.Eggs do
	if egg.State == "Dropped" then
		dropped = egg
	end
end
check(alice.Character:GetAttribute("Downed") == true or actor("Alice").Team ~= myTeam, "Alice est attrapée par " .. hunterName)
check(dropped ~= nil and not Map.IsCarrier(actor("Alice")), "l'œuf tombe au sol")
Engine.Advance(Config.Modes.EggRun.DropReturnSeconds + 1)
local back = true
for _, egg in Map.DebugState().Mode.Eggs do
	if egg.State == "Dropped" then
		back = false
	end
end
check(back, "un œuf laissé seul retourne dans un nid")
-- Un coéquipier d'Alice marque le second œuf : victoire
local mate
for _, name in names do
	if name ~= "Alice" and actor(name).Team == myTeam and players[name].Character:GetAttribute("Downed") ~= true then
		mate = name
	end
end
debug = Map.DebugState().Mode
local egg3
for _, egg in debug.Eggs do
	if egg.State == "Nest" then
		egg3 = egg
	end
end
if mate and egg3 then
	H.teleport(actor(mate), Vector3.new(egg3.Position.X, O.Y + 3, egg3.Position.Z) + Vector3.new(1.5, 0, 0))
	Engine.Advance(0.4)
	H.teleport(actor(mate), base.CFrame:PointToWorldSpace(Vector3.new(0, 0, 4)) + Vector3.new(0, 3, 0))
end
check(H.advanceUntil(function()
	return H.phase() == "Results"
end, 6), "deuxième œuf : fin de manche")
check(state().Winner == myTeam and state().WinReason == "Objective", "victoire de " .. tostring(state().Winner) .. " (" .. tostring(state().WinDetail) .. ")")

-- ---------------------------------------------------------------------------
section("Manche 2 : vote CAROUSEL")
check(H.advanceUntil(function()
	return H.phase() == "Intermission"
end, 60), "retour au lobby")
Engine.Advance(1)
for _, name in names do
	voteFor(name, "Carousel")
end
check(H.advanceUntil(function()
	return H.phase() == "Countdown"
end, 30), "décompte")
check(state().ModeId == "Carousel", "mode joué : " .. tostring(state().ModeId))
recordTeams(2)
check(H.advanceUntil(function()
	return H.phase() == "Round"
end, 10), "manche lancée")

section("CAROUSEL")
parkAll()
Engine.Advance(2.5)
local spinner = Map.DebugState().Spinner
local zones = Map.DebugState().Zones
check(#zones == 3, "trois anneaux sous les chevaux volants")
check(math.abs(spinner:GetAttribute("SpinSpeed") - math.pi * 2 / Config.Modes.Carousel.TurnSeconds) < 1e-3, string.format("le manège tourne : un tour en %d s", Config.Modes.Carousel.TurnSeconds))
check(state().ScoreGoal == Config.Modes.Carousel.PointsToWin, "objectif : " .. tostring(state().ScoreGoal) .. " points")
-- Les anneaux ne passent jamais dans une zone sûre
local unsafe = 0
for k = 0, 71 do
	local a = k / 72 * math.pi * 2
	local p = O + Vector3.new(math.cos(a), 0, -math.sin(a)) * 62 + Vector3.new(0, 3, 0)
	for _, teamId in Teams.Order do
		for _, dx in { -10, 0, 10 } do
			if H.onServer(function()
				return SafeZoneService.Contains(teamId, p + Vector3.new(dx, 0, 0))
			end) then
				unsafe += 1
			end
		end
	end
end
check(unsafe == 0, "la piste des chevaux ne traverse aucune zone sûre")
-- Alice suit l'anneau 1 : son équipe marque chaque seconde
myTeam = actor("Alice").Team
local function zonePos(i)
	return H.onServer(function()
		return CarouselMode.ZonePosition(i)
	end)
end
local before = state().Scores[myTeam] or 0
for _ = 1, 4 do
	local p = zonePos(1)
	H.teleport(actor("Alice"), Vector3.new(p.X, O.Y + 3, p.Z))
	Engine.Advance(1)
end
local after = state().Scores[myTeam] or 0
check(after - before >= 3, string.format("%s tient l'anneau : %d -> %d points", myTeam, before, after))
check(zones[1]:GetAttribute("HeldBy") == myTeam and zones[1]:GetAttribute("KitRole_Zone") == Teams.Get(myTeam).Color, "l'anneau prend la couleur de l'équipe qui le tient")
-- Égalité : un adversaire entre dans l'anneau
local rival
for _, name in names do
	if actor(name).Team ~= myTeam and not rival then
		rival = name
	end
end
local sA, sB = state().Scores[myTeam], state().Scores[actor(rival).Team]
-- (à 12 studs l'un de l'autre, hors de portée de capture, tous deux dans l'anneau)
for _ = 1, 2 do
	local p = zonePos(1)
	H.teleport(actor("Alice"), Vector3.new(p.X + 6, O.Y + 3, p.Z))
	H.teleport(actor(rival), Vector3.new(p.X - 6, O.Y + 3, p.Z))
	Engine.Advance(1)
end
check(state().Scores[myTeam] == sA and state().Scores[actor(rival).Team] == sB, "égalité dans l'anneau : aucun point")
check(zones[1]:GetAttribute("HeldBy") == nil, "anneau disputé : neutre")
parkAll()
-- Le manège change de sens
local s0 = spinner:GetAttribute("SpinSpeed")
Engine.Advance(Config.Modes.Carousel.ReverseEverySeconds + 0.5)
check(spinner:GetAttribute("SpinSpeed") == -s0, "le manège change de sens")
-- Victoire : Alice suit l'anneau jusqu'au bout
myTeam = actor("Alice").Team
local won = H.advanceUntil(function()
	if H.phase() ~= "Round" then
		return true
	end
	local p = zonePos(2)
	H.teleport(actor("Alice"), Vector3.new(p.X, O.Y + 3, p.Z))
	return false
end, 60, 0.5)
check(won and state().Winner == myTeam and state().WinReason == "Objective", "victoire aux points de " .. tostring(state().Winner) .. " (" .. tostring(state().WinDetail) .. ")")

-- ---------------------------------------------------------------------------
section("Manche 3 : égalité au vote -> le mode joué il y a le plus longtemps (CHASE)")
check(H.advanceUntil(function()
	return H.phase() == "Intermission"
end, 60), "retour au lobby")
Engine.Advance(1)
check(H.advanceUntil(function()
	return H.phase() == "Countdown"
end, 30), "décompte sans aucun vote")
check(state().ModeId == "Chase", "sans vote : CHASE, jamais joué (" .. tostring(state().ModeId) .. ")")
recordTeams(3)
check(H.advanceUntil(function()
	return H.phase() == "Round"
end, 10), "manche lancée")
section("CHASE")
Engine.Advance(1)
check(state().ScoreGoal == nil, "pas de score : la poursuite seule")
check(#Map.DebugState().Zones == 0, "pas d'anneaux au sol hors mode Carousel")
-- Tout le monde devient renard : dernière équipe debout
H.onServer(function()
	for _, name in names do
		server.TeamService.SetTeam(actor(name), "FOX")
	end
end)
check(H.advanceUntil(function()
	return H.phase() == "Results"
end, 5), "fin de manche")
check(state().WinReason == "LastStanding" and state().Winner == "FOX", "dernière équipe debout : " .. tostring(state().WinDetail))

-- ---------------------------------------------------------------------------
section("Rotation équitable des équipes")
local repeats = 0
for _, name in names do
	if roundTeams[1][name] == roundTeams[2][name] then
		repeats += 1
	end
	if roundTeams[2][name] == roundTeams[3][name] then
		repeats += 1
	end
end
check(repeats == 0, "personne ne garde le même animal deux manches de suite (" .. repeats .. " répétitions)")
local all3 = 0
for _, name in names do
	local seen = {}
	for r = 1, 3 do
		seen[roundTeams[r][name]] = true
	end
	if seen.FOX and seen.CHICKEN and seen.SNAKE then
		all3 += 1
	end
end
check(all3 >= 4, string.format("en trois manches, %d joueurs sur 6 ont joué les trois animaux", all3))

H.finish()

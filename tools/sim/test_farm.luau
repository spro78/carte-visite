--!nocheck
-- Scénario THE FARM : œuf d'or, porteur, points, bras tournant, cachettes.
local H = require("./harness")
local World, Engine = H.World, H.Engine
local Vector3 = H.Roblox.Vector3

local server = H.boot(function(Config)
	Config.Debug.ForceMap = "TheFarm"
	Config.Debug.DisableBots = true
end)
local check, section = H.check, H.section

local alice = World.AddPlayer("Alice", { client = true })
local bob = World.AddPlayer("Bob")
local carl = World.AddPlayer("Carl")

section("Lancement de THE FARM")
check(H.advanceUntil(function()
	return H.phase() == "Round"
end, 60), "manche lancée")
local Farm = H.require(World.game.ServerScriptService.Server.Maps.TheFarm)
local O = server.Config.World.MapOrigin
local cfg = server.Config.Maps.TheFarm
check(World.workspace:FindFirstChild("Map_TheFarm") ~= nil, "la map est construite")
local debug = Farm.DebugState()
check(debug.State == "Center", "œuf au centre")
check(debug.Egg ~= nil and (debug.Egg.Position - O).Magnitude < 4, "œuf positionné au nid")
local state = server.RoundService.GetState()
check(state.ScoreGoal == 3 and state.ScoreLabel == "eggs", "objectif de score : 3 eggs")
local objectives = World.game.ReplicatedStorage:FindFirstChild("HoH_Objectives")
check(objectives and typeof(objectives:GetAttribute("FOX")) == "Vector3", "objectif publié pour la flèche")

local function actorOf(player)
	return server.ActorService.FromPlayer(player)
end
local A, B, C = actorOf(alice), actorOf(bob), actorOf(carl)
local bases = {}
for _, team in { "FOX", "CHICKEN", "SNAKE" } do
	local Teams = server.Teams
	bases[team] = H.onServer(function()
		local MapBase = World.Require(World.game.ServerScriptService.Server.Maps.MapBase)
		return MapBase.BasePosition(O, team, cfg.BaseRadius)
	end)
end

-- Écarte tout le monde pour éviter des captures parasites
local function park()
	H.teleport(A, O + Vector3.new(-120, 3, -120))
	H.teleport(B, O + Vector3.new(120, 3, -120))
	H.teleport(C, O + Vector3.new(-120, 3, 120))
end

section("Ramassage et porteur")
park()
Engine.Advance(3)
local armAngle = Farm.DebugState().Arm and server.Mechanics.GetAngle(Farm.DebugState().Arm) or 0
-- On amène Alice sur l'œuf, à l'opposé du bras pour ne pas être éjectée
H.teleport(A, O + Vector3.new(0, 3, 2))
Engine.Advance(0.3)
debug = Farm.DebugState()
check(debug.State == "Carried" and debug.Carrier == A, "Alice porte l'œuf")
check(alice.Character:GetAttribute("Carrier") == true, "attribut Carrier (contour or pour tous)")
check(math.abs((alice.Character:GetAttribute("SpeedMult") or 1) - cfg.CarrierSpeedMultiplier) < 0.01, "porteur ralenti de 15 %")
check(typeof(alice.Character:GetAttribute("ObjectiveTarget")) == "Vector3", "la flèche du porteur pointe vers sa base")
check(debug.Egg.Parent == alice.Character, "l'œuf est soudé au personnage")

section("Point marqué")
H.teleport(A, bases[A.Team] + Vector3.new(0, 4, 0))
Engine.Advance(0.3)
check(server.RoundService.GetState().Scores[A.Team] == 1, "équipe " .. A.Team .. " : 1 point")
check(alice.Character:GetAttribute("Carrier") == nil, "plus porteur après avoir marqué")
check(math.abs((alice.Character:GetAttribute("SpeedMult") or 1) - 1) < 0.01, "vitesse normale rétablie")
check(H.advanceUntil(function()
	return Farm.DebugState().State == "Center"
end, cfg.EggRespawnDelay + 2), "un nouvel œuf réapparaît au centre")

section("Porteur attrapé : l'œuf tombe")
park()
Engine.Advance(1)
-- Bob prend l'œuf puis son prédateur le touche
H.teleport(B, O + Vector3.new(0, 3, 2))
Engine.Advance(0.3)
check(Farm.DebugState().Carrier == B, "Bob porte l'œuf")
local predatorTeam = server.Teams.GetPredator(B.Team)
local predator = (A.Team == predatorTeam and A) or (C.Team == predatorTeam and C) or nil
if predator then
	Engine.Advance(2.5) -- fin d'invincibilité éventuelle
	local root = bob.Character.HumanoidRootPart.Position
	H.teleport(B, Vector3.new(root.X, 3, root.Z) + Vector3.new(30, 0, 30))
	Engine.Advance(0.1)
	local bobPos = bob.Character.HumanoidRootPart.Position
	H.teleport(predator, bobPos + Vector3.new(2, 0, 0))
	Engine.Advance(0.4)
	debug = Farm.DebugState()
	check(B.Team == predator.Team, "Bob a été converti")
	check(debug.State == "Dropped", "l'œuf est tombé au sol")
	check(debug.Egg and debug.Egg.Anchored and (debug.Egg.Position - bobPos).Magnitude < 8, "l'œuf est posé près du lieu de capture")
else
	check(false, "pas de prédateur pour Bob dans ce tirage")
end

section("Bras tournant")
park()
Engine.Advance(1)
local armModel = Farm.DebugState().Arm
local launchesBefore = Engine.RemoteCalls["Launch:FireClient"] or 0
-- On place Alice juste devant le bras, à mi-longueur
local angle = server.Mechanics.GetAngle(armModel) + 0.25
local dir = server.Mechanics.Direction(angle)
H.teleport(A, O + dir * 35 + Vector3.new(0, 3, 0))
local startPos = alice.Character.HumanoidRootPart.Position
check(H.advanceUntil(function()
	return (Engine.RemoteCalls["Launch:FireClient"] or 0) > launchesBefore
end, 2, 1 / 30), "le serveur éjecte le joueur touché")
Engine.Advance(0.1)
check(alice.Character:GetAttribute("Ragdoll") == true, "ragdoll appliqué par le client")
Engine.Advance(1)
local flown = (alice.Character.HumanoidRootPart.Position - startPos).Magnitude
check(flown > 40, string.format("vol à travers la map (%.0f studs)", flown))
-- Un joueur qui saute assez haut n'est pas touché
park()
Engine.Advance(2)
local before2 = Engine.RemoteCalls["Launch:FireClient"] or 0
angle = server.Mechanics.GetAngle(armModel) + 0.2
dir = server.Mechanics.Direction(angle)
H.teleport(A, O + dir * 35 + Vector3.new(0, 9, 0))
H.onServer(function()
	alice.Character.HumanoidRootPart.Anchored = true -- maintenu en l'air (saut)
end)
Engine.Advance(0.6)
H.onServer(function()
	alice.Character.HumanoidRootPart.Anchored = false
end)
check((Engine.RemoteCalls["Launch:FireClient"] or 0) == before2, "sauter par-dessus le bras évite l'éjection")

section("Cachettes")
park()
Engine.Advance(1.5)
local grassPos
for _, d in World.workspace:GetDescendants() do
	if d.Name == "HidingZone_Grass" then
		grassPos = Vector3.new(d.Position.X, O.Y, d.Position.Z)
		break
	end
end
H.teleport(B, grassPos + Vector3.new(0, 3, 0))
Engine.Advance(0.5)
check(bob.Character:GetAttribute("Hidden") == true, "Bob est caché dans les hautes herbes")
H.teleport(B, grassPos + Vector3.new(20, 3, 0))
Engine.Advance(0.5)
check(bob.Character:GetAttribute("Hidden") == nil, "Bob n'est plus caché en sortant")

section("Victoire par objectif")
local team = A.Team
local function bring()
	H.advanceUntil(function()
		return Farm.DebugState().State == "Center" or Farm.DebugState().State == "Dropped"
	end, 10)
	local eggPos = Farm.DebugState().Egg.Position
	park()
	H.teleport(A, Vector3.new(eggPos.X, 3, eggPos.Z))
	Engine.Advance(0.3)
	H.teleport(A, bases[A.Team] + Vector3.new(0, 4, 0))
	Engine.Advance(0.3)
end
local final = nil
for _ = 1, 4 do
	if H.phase() ~= "Round" then
		break
	end
	bring()
	if (server.RoundService.GetState().Scores[A.Team] or 0) >= 3 then
		break
	end
end
check(H.advanceUntil(function()
	if H.phase() == "Results" then
		final = table.clone(server.RoundService.GetState())
		return true
	end
	return false
end, 5, 0.1), "la manche se termine")
check(final and final.WinReason == "Objective", "raison : objectif (" .. tostring(final and final.WinReason) .. ")")
check(final and final.Winner == team, "vainqueur : " .. tostring(final and final.Winner) .. " (attendu " .. tostring(team) .. ")")
check(final and type(final.WinDetail) == "string" and string.find(final.WinDetail, "reached the goal: 3 eggs", 1, true) ~= nil, "explication : " .. tostring(final and final.WinDetail))

section("Nettoyage")
check(H.advanceUntil(function()
	return H.phase() == "Intermission"
end, 30), "retour au lobby")
check(World.workspace:FindFirstChild("Map_TheFarm") == nil, "map détruite")

H.finish()

--!nocheck
-- Scénario THE CANYON : vol d'œufs, dépôt, capture du voleur, catapulte.
local H = require("./harness")
local World, Engine = H.World, H.Engine
local Vector3 = H.Roblox.Vector3
local server = H.boot(function(Config)
	Config.Debug.ForceMap = "TheCanyon"
	Config.Debug.DisableBots = true
end)
local check, section = H.check, H.section

local alice = World.AddPlayer("Alice", { client = true })
local bob = World.AddPlayer("Bob")
local carl = World.AddPlayer("Carl")
section("Lancement")
check(H.advanceUntil(function()
	return H.phase() == "Round"
end, 60), "manche lancée sur THE CANYON")
local Canyon = H.require(World.game.ServerScriptService.Server.Maps.TheCanyon)
local MapBase = H.require(World.game.ServerScriptService.Server.Maps.MapBase)
local cfg = server.Config.Maps.TheCanyon
local O = server.Config.World.MapOrigin
local Teams = server.Teams
local A = server.ActorService.FromPlayer(alice)
local B = server.ActorService.FromPlayer(bob)
local C = server.ActorService.FromPlayer(carl)
local eggs = Canyon.DebugState().Eggs
check(eggs.FOX == 5 and eggs.CHICKEN == 5 and eggs.SNAKE == 5, "5 œufs par base")
local scores = server.RoundService.GetState().Scores
check(scores.FOX == 5 and scores.CHICKEN == 5, "le score affiché = œufs dans la base")
local function basePos(team)
	return MapBase.BasePosition(O, team, cfg.BaseRadius)
end
local function park()
	H.teleport(A, O + Vector3.new(-60, 3, -40))
	H.teleport(B, O + Vector3.new(60, 3, -40))
	H.teleport(C, O + Vector3.new(0, 3, 60))
end
park()
Engine.Advance(3)

section("On ne vole que chez sa proie")
local predatorTeam = Teams.GetPredator(A.Team)
H.teleport(A, basePos(predatorTeam) + Vector3.new(0, 3, 0))
Engine.Advance(0.4)
check(not Canyon.IsCarrier(A), "rien à voler dans la base de son prédateur")
local preyTeam = Teams.GetPrey(A.Team)
-- On éloigne les membres de l'équipe proie pour éviter une capture parasite
H.teleport(A, basePos(preyTeam) + Vector3.new(0, 3, 0))
Engine.Advance(0.4)
check(Canyon.IsCarrier(A), "Alice vole un œuf chez sa proie (" .. preyTeam .. ")")
check(Canyon.DebugState().Eggs[preyTeam] == 4, "la base volée passe à 4 œufs")
check(alice.Character:GetAttribute("Carrier") == true, "le voleur est visible de tous")

section("Dépôt dans sa base")
H.teleport(A, basePos(A.Team) + Vector3.new(0, 3, 0))
Engine.Advance(0.4)
check(not Canyon.IsCarrier(A), "œuf déposé")
check(Canyon.DebugState().Eggs[A.Team] == 6, "sa base passe à 6 œufs")
check(server.RoundService.GetState().Scores[A.Team] == 6, "score mis à jour")

section("Voleur attrapé : l'œuf retourne chez lui")
park()
Engine.Advance(0.5)
H.teleport(A, basePos(preyTeam) + Vector3.new(0, 3, 0))
Engine.Advance(0.4)
check(Canyon.IsCarrier(A), "Alice vole un second œuf")
local hunter = (B.Team == predatorTeam and B) or (C.Team == predatorTeam and C)
H.teleport(A, O + Vector3.new(80, 3, 80))
Engine.Advance(0.2)
H.teleport(hunter, alice.Character.HumanoidRootPart.Position + Vector3.new(2, 0, 0))
Engine.Advance(0.4)
check(A.Team == predatorTeam, "Alice est convertie")
check(Canyon.DebugState().Eggs[preyTeam] == 4, "l'œuf est rendu à sa base d'origine (4)")

section("Catapulte")
park()
Engine.Advance(2.5)
local catapult = Canyon.DebugState().Catapult
local angle = server.Mechanics.GetAngle(catapult)
local aim = server.Mechanics.Direction(angle)
local bucket = O + aim * cfg.CatapultArmLength
local launchesBefore = Engine.RemoteCalls["Launch:FireClient"] or 0
H.teleport(A, bucket + Vector3.new(0, 6, 0))
H.onServer(function()
	alice.Character.HumanoidRootPart.Anchored = true
end)
Engine.Advance(0.05)
H.onServer(function()
	alice.Character.HumanoidRootPart.Anchored = false
end)
check((Engine.RemoteCalls["Launch:FireClient"] or 0) > launchesBefore, "sauter dans le godet lance le joueur")
local startPos = alice.Character.HumanoidRootPart.Position
Engine.Advance(cfg.CatapultFlightSeconds + 0.3)
local landed = alice.Character.HumanoidRootPart.Position
local travel = Vector3.new(landed.X - startPos.X, 0, landed.Z - startPos.Z)
check(travel.Magnitude > 60, string.format("vol de %.0f studs", travel.Magnitude))
check(travel.Magnitude > 1 and travel.Unit:Dot(aim) > 0.85, "dans la direction visée par la catapulte")

section("Fin au chrono : plus d'œufs gagne")
local leader = Canyon.ResolveTimeUp()
check(leader ~= nil, "vainqueur au chrono : " .. tostring(leader))
check(H.advanceUntil(function()
	return H.phase() == "Intermission"
end, 260, 1), "retour au lobby")
check(World.workspace:FindFirstChild("Map_TheCanyon") == nil, "map nettoyée")
H.finish()

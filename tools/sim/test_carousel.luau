--!nocheck
-- Scénario THE CAROUSEL : points sur la plateforme, paliers et éjection.
local H = require("./harness")
local World, Engine = H.World, H.Engine
local Vector3 = H.Roblox.Vector3
local server = H.boot(function(Config)
	Config.Debug.ForceMap = "TheCarousel"
	Config.Debug.DisableBots = true
end)
local check, section = H.check, H.section

local alice = World.AddPlayer("Alice", { client = true })
local bob = World.AddPlayer("Bob")
local carl = World.AddPlayer("Carl")
section("Lancement")
check(H.advanceUntil(function()
	return H.phase() == "Round"
end, 60), "manche lancée sur THE CAROUSEL")
local Carousel = H.require(World.game.ServerScriptService.Server.Maps.TheCarousel)
local cfg = server.Config.Maps.TheCarousel
local O = server.Config.World.MapOrigin
local A = server.ActorService.FromPlayer(alice)
local B = server.ActorService.FromPlayer(bob)
local C = server.ActorService.FromPlayer(carl)
check(server.RoundService.GetState().ScoreGoal == 100, "objectif : 100 points")
local wheel = Carousel.DebugState().Wheel
check(wheel and wheel:GetAttribute("SpinSpeed") > 0, "la plateforme tourne")
check(wheel:GetAttribute("SpinCollide") == true, "plateforme marquée comme praticable (entraîne les joueurs)")

section("Points : l'équipe la plus nombreuse sur la roue")
Engine.Advance(3)
local function onWheel(actor, offset)
	H.onServer(function()
		actor.Character:PivotTo(H.Roblox.CFrame.new(O + Vector3.new(offset, cfg.PlatformHeight + 3, 0)))
	end)
end
local function park(actor, x)
	H.teleport(actor, O + Vector3.new(x, 3, -130))
end
onWheel(A, 5)
park(B, 60)
park(C, -60)
local before = server.RoundService.GetState().Scores[A.Team] or 0
Engine.Advance(3.2)
local after = server.RoundService.GetState().Scores[A.Team] or 0
check(after - before >= 3, string.format("%s gagne 1 point par seconde (%d -> %d)", A.Team, before, after))
-- Égalité : personne ne marque
onWheel(B, -5)
local sA, sB = server.RoundService.GetState().Scores[A.Team], server.RoundService.GetState().Scores[B.Team]
Engine.Advance(2.2)
local sA2, sB2 = server.RoundService.GetState().Scores[A.Team], server.RoundService.GetState().Scores[B.Team]
check(sA2 == sA and sB2 == sB, "égalité sur la roue : aucun point")

section("Accélération puis éjection")
local speeds = {}
local launched = false
local launchesBefore = Engine.RemoteCalls["Launch:FireClient"] or 0
park(B, 60)
for _ = 1, 70 do
	-- Alice reste sur la roue (elle est replacée si besoin)
	if not launched then
		onWheel(A, 6)
	end
	Engine.Advance(1)
	speeds[wheel:GetAttribute("SpinSpeed")] = true
	if (Engine.RemoteCalls["Launch:FireClient"] or 0) > launchesBefore then
		launched = true
		break
	end
end
local n = 0
for _ in speeds do
	n += 1
end
check(n >= #cfg.SpeedSteps, "la roue passe par " .. n .. " vitesses")
check(launched, "tout le monde est éjecté au dernier palier")
Engine.Advance(0.2)
check(alice.Character:GetAttribute("Ragdoll") == true, "ragdoll pendant l'éjection")

section("Fin")
check(H.advanceUntil(function()
	return H.phase() == "Intermission"
end, 260, 1), "la manche se termine et revient au lobby")
check(World.workspace:FindFirstChild("Map_TheCarousel") == nil, "map nettoyée")
H.finish()

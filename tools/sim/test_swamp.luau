--!nocheck
-- Scénario THE SWAMP : tourniquet qui relâche vers un camp, geysers.
local H = require("./harness")
local World, Engine = H.World, H.Engine
local Vector3 = H.Roblox.Vector3
local server = H.boot(function(Config)
	Config.Debug.ForceMap = "TheSwamp"
	Config.Debug.DisableBots = true
end)
local check, section = H.check, H.section

local alice = World.AddPlayer("Alice", { client = true })
local bob = World.AddPlayer("Bob")
local carl = World.AddPlayer("Carl")
section("Lancement")
check(H.advanceUntil(function()
	return H.phase() == "Round"
end, 60), "manche lancée sur THE SWAMP")
local Swamp = H.require(World.game.ServerScriptService.Server.Maps.TheSwamp)
local MapBase = H.require(World.game.ServerScriptService.Server.Maps.MapBase)
local cfg = server.Config.Maps.TheSwamp
local O = server.Config.World.MapOrigin
local A = server.ActorService.FromPlayer(alice)
local B = server.ActorService.FromPlayer(bob)
local C = server.ActorService.FromPlayer(carl)
check(server.RoundService.GetState().ScoreLabel == nil, "pas de score : conversion pure")
local atmosphere = World.game.Lighting:FindFirstChildOfClass("Atmosphere")
check(World.game.Lighting.ClockTime == 18.1 and atmosphere and atmosphere.Density == 0.4, "ambiance du marais appliquée (crépuscule, brume)")
local function park()
	H.teleport(A, O + Vector3.new(-120, 3, -100))
	H.teleport(B, O + Vector3.new(120, 3, -100))
	H.teleport(C, O + Vector3.new(0, 3, 130))
end
park()
Engine.Advance(3)

section("Tourniquet")
local ts = Swamp.DebugState().Turnstile
local angle = server.Mechanics.GetAngle(ts) + 0.3
H.teleport(A, O + server.Mechanics.Direction(angle) * 12 + Vector3.new(0, 3, 0))
check(H.advanceUntil(function()
	return alice.Character:GetAttribute("Frozen") == true
end, 2, 1 / 30), "Alice est attrapée par le tourniquet")
local launchesBefore = Engine.RemoteCalls["Launch:FireClient"] or 0
check(H.advanceUntil(function()
	return (Engine.RemoteCalls["Launch:FireClient"] or 0) > launchesBefore
end, cfg.TurnstileHoldSeconds + 0.5, 0.1), "puis relâchée")
check(alice.Character:GetAttribute("Frozen") == nil, "elle peut de nouveau bouger")
Engine.Advance(cfg.TurnstileFlightSeconds + 0.2)
local landed = alice.Character.HumanoidRootPart.Position
local nearestCamp = math.huge
for _, team in { "FOX", "CHICKEN", "SNAKE" } do
	local d = (Vector3.new(landed.X, 0, landed.Z) - MapBase.BasePosition(O, team, cfg.BaseRadius)).Magnitude
	nearestCamp = math.min(nearestCamp, d)
end
check(nearestCamp < 25, string.format("elle atterrit dans un camp (à %.0f studs du centre du camp)", nearestCamp))

section("Geysers")
park()
Engine.Advance(1)
local geysers = Swamp.DebugState().Geysers
check(#geysers == cfg.GeyserCount, #geysers .. " geysers")
local gotLaunched = false
local before = Engine.RemoteCalls["Launch:FireClient"] or 0
for i = 1, 6 do
	-- Alice se tient sur un geyser différent à chaque cycle
	local g = geysers[(i % #geysers) + 1]
	for _ = 1, math.ceil(cfg.GeyserIntervalSeconds * 4) do
		H.teleport(A, g.Position + Vector3.new(0, 3, 0))
		Engine.Advance(0.25)
		if (Engine.RemoteCalls["Launch:FireClient"] or 0) > before then
			gotLaunched = true
			break
		end
	end
	if gotLaunched then
		break
	end
end
check(gotLaunched, "un geyser propulse Alice en l'air")
local vy = alice.Character.HumanoidRootPart.AssemblyLinearVelocity.Y
check(vy > 40, string.format("vers le haut (vitesse verticale %.0f)", vy))

section("Dernière équipe debout")
park()
Engine.Advance(3)
-- Conversions en chaîne jusqu'à ce qu'il ne reste qu'une équipe
for _ = 1, 6 do
	if H.phase() ~= "Round" then
		break
	end
	local actors = server.RoundState.GetParticipants()
	for _, hunter in actors do
		for _, victim in actors do
			if server.Teams.CanCatch(hunter.Team, victim.Team) then
				Engine.Advance(2.5)
				H.teleport(victim, hunter.Character.HumanoidRootPart.Position + Vector3.new(2, 0, 0))
				Engine.Advance(0.3)
			end
		end
	end
end
local final
check(H.advanceUntil(function()
	if H.phase() == "Results" then
		final = table.clone(server.RoundService.GetState())
		return true
	end
	return false
end, 10, 0.1), "la manche se termine")
check(final and final.WinReason == "LastStanding", "raison : dernière équipe debout (" .. tostring(final and final.WinReason) .. ")")
check(final and type(final.WinDetail) == "string" and string.find(final.WinDetail, "converted everyone", 1, true) ~= nil, "explication : " .. tostring(final and final.WinDetail))
check(H.advanceUntil(function()
	return H.phase() == "Intermission"
end, 30, 1), "retour au lobby")
check(World.game.Lighting.ClockTime ~= 18.1 and World.game.Lighting:FindFirstChildOfClass("Atmosphere").Density ~= 0.4, "ambiance lumineuse restaurée")
H.finish()

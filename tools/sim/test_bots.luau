--!nocheck
-- Scénario BOTS : manche avec un seul vrai joueur, bots qui chassent et convertissent.
local H = require("./harness")
local World, Engine = H.World, H.Engine
local Vector3 = H.Roblox.Vector3

local server = H.boot(function(Config)
	Config.Debug.ForceMap = "TheFarm"
	-- Pas de fin par l'objectif pendant l'observation : une manche gagnée en
	-- trois œufs pouvait finir avant le premier portage (0 sauvetage)
	Config.Maps.TheFarm.PointsToWin = 99
end)
local check, section = H.check, H.section
local BotService = H.require(World.game.ServerScriptService.Server.Bots.BotService)

section("Une manche avec un seul vrai joueur")
local solo = World.AddPlayer("Solo", { client = true })
check(H.advanceUntil(function()
	return H.phase() == "Countdown"
end, 40), "la manche démarre avec 1 joueur")
local participants = server.RoundState.GetParticipants()
check(#participants == 12, "12 participants (1 joueur + 11 bots) : " .. #participants)
local counts = server.TeamService.GetCounts(participants)
check(counts.FOX == 4 and counts.CHICKEN == 4 and counts.SNAKE == 4, string.format("4 par équipe (%d/%d/%d)", counts.FOX, counts.CHICKEN, counts.SNAKE))
local bots = server.ActorService.GetBots()
local names = {}
local unique = true
for _, bot in bots do
	if names[bot.Name] then
		unique = false
	end
	names[bot.Name] = true
end
check(unique, "pseudos uniques : " .. table.concat((function()
	local list = {}
	for i = 1, math.min(5, #bots) do
		list[i] = bots[i].Name
	end
	return list
end)(), ", ") .. "...")
local okLooks = true
for _, bot in bots do
	local c = bot.Character
	if not c or c:GetAttribute("Animal") == nil or c.Humanoid.DisplayName ~= bot.Name then
		okLooks = false
	end
end
check(okLooks, "chaque bot a un personnage, un animal et son pseudo affiché")
check(bots[1].Character.HumanoidRootPart:GetNetworkOwner() == nil, "physique des bots gérée par le serveur")

section("Les bots jouent")
check(H.advanceUntil(function()
	return H.phase() == "Round"
end, 10), "manche lancée")
local startPositions = {}
for _, bot in bots do
	startPositions[bot.Id] = bot.Character.HumanoidRootPart.Position
end
Engine.Advance(6)
local moved = 0
for _, bot in bots do
	if bot.Character and (bot.Character.HumanoidRootPart.Position - startPositions[bot.Id]).Magnitude > 15 then
		moved += 1
	end
end
check(moved >= #bots * 0.7, string.format("les bots se déplacent (%d/%d)", moved, #bots))
local modes = {}
for _, bot in bots do
	local brain = BotService.GetBrain(bot)
	if brain then
		modes[brain.Mode] = (modes[brain.Mode] or 0) + 1
	end
end
local modeList = {}
for mode, n in modes do
	table.insert(modeList, mode .. "=" .. n)
end
print("    modes : " .. table.concat(modeList, " "))
check((modes.Objective or 0) + (modes.Chase or 0) + (modes.Flee or 0) > 0, "les bots chassent, fuient ou visent l'objectif")

section("Un joueur arrive en cours de manche et remplace un bot")
if H.phase() == "Round" then
	local before = #server.ActorService.GetBots()
	local late = World.AddPlayer("Latecomer")
	Engine.Advance(2)
	local lateActor = server.ActorService.FromPlayer(late)
	check(#server.ActorService.GetBots() == before - 1, "un bot a été retiré")
	check(lateActor and lateActor.Team ~= nil and server.RoundState.IsParticipant(lateActor), "le nouveau joueur joue dans l'équipe du bot (" .. tostring(lateActor and lateActor.Team) .. ")")
else
	check(true, "(manche déjà terminée, test sauté)")
end

local dashes = Engine.RemoteCalls["Effect:FireAllClients"] or 0
local totalCaptures = 0
local eggTaken = false
local Farm = H.require(World.game.ServerScriptService.Server.Maps.TheFarm)
local RescueService = H.require(World.game.ServerScriptService.Server.Services.RescueService)
local soloActor = server.ActorService.FromPlayer(solo)
-- Sauvetages et conversions des bots (règle : à terre -> portage ou conversion)
local revived, converted, carries = 0, 0, 0
H.onServer(function()
	RescueService.Revived:Connect(function(_, rescuer)
		if rescuer then
			revived += 1
		end
	end)
	RescueService.Converted:Connect(function()
		converted += 1
	end)
end)
local downSince = {}
local longestWait = 0
-- Le joueur reste immobile dans un coin (spectateur passif)
H.teleport(soloActor, server.Config.World.MapOrigin + Vector3.new(-140, 3, -140))
for t = 1, 150 do
	Engine.Advance(1)
	if H.phase() ~= "Round" then
		break
	end
	if Farm.DebugState().State == "Carried" then
		eggTaken = true
	end
	-- Temps passé à terre sans être porté (chrono serveur : jamais plus que BleedOutSeconds)
	local now = Engine.Now()
	local current = {}
	for _, entry in RescueService.GetDowned() do
		if entry.Carrier then
			carries += 1
			downSince[entry.Actor.Id] = nil
		else
			current[entry.Actor.Id] = true
			downSince[entry.Actor.Id] = downSince[entry.Actor.Id] or now
			longestWait = math.max(longestWait, now - downSince[entry.Actor.Id])
		end
	end
	for id in downSince do
		if not current[id] then
			downSince[id] = nil
		end
	end
	if t >= 60 and eggTaken and revived > 0 then
		break
	end
end
for _, actor in server.RoundState.GetParticipants() do
	totalCaptures += actor.RoundCaptures
end
check(totalCaptures > 0, "des bots attrapent (" .. totalCaptures .. " captures)")
print(string.format("    à terre : %d sauvetages par des bots, %d conversions, %d s de portage observées, plus longue attente au sol %.0f s", revived, converted, carries, longestWait))
check(revived > 0, "des bots portent leurs coéquipiers à terre jusqu'au camp (" .. revived .. " sauvetages)")
check(longestWait <= server.Config.Rescue.BleedOutSeconds + 1.5, string.format("personne ne reste au sol plus de %d s sans être porté (max %.0f s)", server.Config.Rescue.BleedOutSeconds, longestWait))
check(eggTaken, "un bot a ramassé l'œuf d'or")
local st = server.RoundService.GetState()
local scores = st.Scores
print(string.format("    scores : FOX=%d CHICKEN=%d SNAKE=%d, phase=%s, fin=%s, temps restant=%s", scores.FOX or 0, scores.CHICKEN or 0, scores.SNAKE or 0, H.phase(), tostring(st.WinReason), tostring(st.TimeLeft)))
local launches = 0
for k, v in Engine.RemoteCalls do
	if k == "Effect:FireAllClients" then
		launches = v
	end
end
check(launches > dashes, "effets envoyés (dash, capacités, captures)")

section("Fin de manche : les bots sont retirés")
check(H.advanceUntil(function()
	return H.phase() == "Intermission"
end, 260, 1), "retour au lobby")
check(#server.ActorService.GetBots() == 0, "plus aucun bot")
local leftovers = 0
for _, c in World.workspace:GetChildren() do
	if c:GetAttribute("IsBot") then
		leftovers += 1
	end
end
check(leftovers == 0, "aucun personnage de bot ne reste dans le monde")

H.finish()

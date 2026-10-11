--!nocheck
--[[
	test.luau : scénarios de test exécutés dans le faux Roblox.
	Usage : lune run tools/sim/test.luau <sourcemap.json>
	Code de sortie 1 si une erreur d'exécution ou une assertion échoue.
]]

local process = require("@lune/process")
local World = require("./world")
local Engine = World.Engine
local roblox = Engine.Roblox
local Vector3, CFrame, Enum = roblox.Vector3, roblox.CFrame, roblox.Enum

Engine.Quiet = true
World.LoadSourcemap(process.args[1] or "sourcemap.json")
Engine.Run("server", function()
	local Config = World.Require(World.game.ReplicatedStorage.Shared.Config)
	Config.Debug.DisableBots = true
end)

local failures = {}
local passes = 0
local function check(condition, message)
	if condition then
		passes += 1
		print("  \27[32mOK\27[0m   " .. message)
	else
		table.insert(failures, message)
		print("  \27[31mFAIL\27[0m " .. message)
	end
end

local function section(name)
	print("\n== " .. name)
end

local server = {}
Engine.Run("server", function()
	World.StartServer()
end)
Engine.Advance(0.5)
Engine.Run("server", function()
	local services = World.game.ServerScriptService.Server.Services
	server.RoundState = World.Require(services.RoundState)
	server.ActorService = World.Require(services.ActorService)
	server.RoundService = World.Require(services.RoundService)
	server.TeamService = World.Require(services.TeamService)
	server.Config = World.Require(World.game.ReplicatedStorage.Shared.Config)
end)

local function advanceUntil(predicate, maxSeconds, step)
	local t = 0
	while t < maxSeconds do
		if predicate() then
			return true
		end
		Engine.Advance(step or 0.25)
		t += step or 0.25
	end
	return predicate()
end

local function phase()
	return server.RoundState.Phase
end

-- ---------------------------------------------------------------------------
section("Démarrage et lobby")
local alice = World.AddPlayer("Alice", { client = true })
local bob = World.AddPlayer("Bob")
local carl = World.AddPlayer("Carl")
Engine.Advance(2)
check(World.workspace:FindFirstChild("Lobby") ~= nil, "le lobby est construit")
check(alice.Character ~= nil and alice.Character:IsDescendantOf(World.workspace), "Alice a un personnage")
check(alice.PlayerGui:FindFirstChild("HuntOrHideHUD") ~= nil, "le HUD client est créé")
check(phase() == "Intermission", "phase Intermission (vote) : " .. tostring(phase()))
local lobbyPos = alice.Character.HumanoidRootPart.Position
check(math.abs(lobbyPos.Z) < 80, "Alice est dans le lobby")

-- Vote par le client (intention validée par le serveur)
Engine.Run(alice, function()
	local Remotes = World.Require(World.game.ReplicatedStorage.Shared.Remotes)
	Remotes.Get("VoteMap"):FireServer("NotAMap")
	Remotes.Get("VoteMap"):FireServer(123)
end)
Engine.Advance(0.2)

-- ---------------------------------------------------------------------------
section("Début de manche")
check(advanceUntil(function()
	return phase() == "Countdown"
end, 40), "passage au compte à rebours")
local participants = server.RoundState.GetParticipants()
check(#participants >= 3, "au moins 3 participants (" .. #participants .. ")")
for _, actor in participants do
	check(actor.Team ~= nil, actor.Name .. " a une équipe : " .. tostring(actor.Team))
end
check(alice:GetAttribute("Team") ~= nil, "l'attribut Team du joueur est répliqué")
local aliceChar = alice.Character
check(aliceChar:GetAttribute("Frozen") == true, "joueurs gelés pendant le décompte")
check(aliceChar:GetAttribute("Animal") == alice:GetAttribute("Team"), "animal attribué au personnage")
local parts = aliceChar:FindFirstChild("AnimalParts")
check(parts ~= nil and parts:FindFirstChild("Scarf") ~= nil, "attributs d'animal et foulard d'équipe ajoutés")
check(aliceChar.Head:GetAttribute("HoH_OriginalColor") == nil, "l'avatar Roblox garde ses couleurs (aucune teinte)")
check(aliceChar.HumanoidRootPart.Position.Z > 1500, "Alice est téléportée sur la map")

check(advanceUntil(function()
	return phase() == "Round"
end, 10), "passage en manche")
check(aliceChar:GetAttribute("Frozen") == nil, "dégel au GO")

-- ---------------------------------------------------------------------------
section("Déplacement à inertie")
do
	local hum = aliceChar.Humanoid
	local maxSpeed = server.Config.Movement.MaxSpeed
	World.SetMoveVector(alice, Vector3.new(0, 0, -1))
	Engine.Advance(0.2)
	local early = hum.WalkSpeed
	Engine.Advance(1.0)
	local full = hum.WalkSpeed
	World.SetMoveVector(alice, Vector3.zero)
	Engine.Advance(0.15)
	local sliding = hum.WalkSpeed
	Engine.Advance(1.0)
	local stopped = hum.WalkSpeed
	check(early > 2 and early < maxSpeed * 0.7, string.format("accélération progressive (%.1f après 0,2 s)", early))
	check(math.abs(full - maxSpeed) < 0.5, string.format("vitesse max atteinte (%.1f / %d)", full, maxSpeed))
	check(sliding > 3, string.format("glissade au relâchement (%.1f après 0,15 s)", sliding))
	check(stopped < 0.1, "arrêt complet après la glissade")
	World.SetMoveVector(alice, Vector3.new(0, 0, -1))
	Engine.Advance(1.0)
	local before = hum.WalkSpeed
	World.PressKey(alice, Enum.KeyCode.F, true)
	Engine.Advance(1 / 30)
	-- La touche avant reste enfoncée : on repart aussitôt, mais depuis zéro
	check(before > 20 and hum.WalkSpeed < 3, string.format("arrêt instantané (feinte) avec F : %.1f -> %.1f", before, hum.WalkSpeed))
	World.SetMoveVector(alice, Vector3.zero)
	Engine.Advance(0.5)
end

-- ---------------------------------------------------------------------------
section("Dash et capacité (client -> serveur)")
Engine.Advance(3) -- fin de la protection
World.PressKey(alice, Enum.KeyCode.E, true)
World.PressKey(alice, Enum.KeyCode.E, false)
Engine.Advance(0.1)
check(type(aliceChar:GetAttribute("DashReadyAt")) == "number", "le serveur a validé le dash (DashReadyAt)")
check((Engine.RemoteCalls["RequestDash:FireServer"] or 0) == 1, "une seule intention de dash envoyée")
World.PressKey(alice, Enum.KeyCode.E, true)
Engine.Advance(0.1)
check((Engine.RemoteCalls["RequestDash:FireServer"] or 0) == 1, "pas de second dash pendant la recharge")
World.PressKey(alice, Enum.KeyCode.R, true)
Engine.Advance(0.1)
check(type(aliceChar:GetAttribute("AbilityReadyAt")) == "number", "le serveur a validé la capacité (AbilityReadyAt)")
if alice:GetAttribute("Team") == "FOX" then
	check((aliceChar:GetAttribute("SpeedMult") or 1) > 1.2, "le sprint du renard augmente la vitesse")
end

-- ---------------------------------------------------------------------------
section("Capture et conversion")
Engine.Advance(3) -- une poule qui vient de planer doit d'abord atterrir
local actors = server.RoundState.GetParticipants()
local hunter, victim
for _, a in actors do
	for _, b in actors do
		if a ~= b and a.Team and b.Team and a.Team ~= b.Team then
			local Teams = nil
			Engine.Run("server", function()
				Teams = World.Require(World.game.ReplicatedStorage.Shared.Teams)
			end)
			if Teams.CanCatch(a.Team, b.Team) then
				hunter, victim = a, b
			end
		end
	end
end
check(hunter ~= nil, "un couple chasseur/proie existe")
if hunter and victim then
	local hunterTeam = hunter.Team
	local before = hunter.RoundCaptures
	-- On place la proie juste à côté du chasseur
	Engine.Run("server", function()
		local root = hunter.Character.HumanoidRootPart
		victim.Character:PivotTo(root.CFrame * CFrame.new(3, 0, 0))
	end)
	Engine.Advance(0.5)
	check(victim.Team == hunterTeam, victim.Name .. " converti en " .. tostring(hunterTeam))
	check(victim.Character:GetAttribute("Team") == hunterTeam, "attribut Team du personnage mis à jour")
	check(hunter.RoundCaptures == before + 1, "capture comptée pour " .. hunter.Name)
	check(victim.Character:FindFirstChildOfClass("ForceField") ~= nil, "invincibilité visible après conversion")
end

-- ---------------------------------------------------------------------------
section("Contours côté client")
Engine.Advance(0.5)
local myTeam = alice:GetAttribute("Team")
local okOutline = true
local seen = 0
for _, actor in server.RoundState.GetParticipants() do
	if actor.Character and actor.Player ~= alice then
		local h = actor.Character:FindFirstChild("HoH_Outline")
		local Teams
		Engine.Run("server", function()
			Teams = World.Require(World.game.ReplicatedStorage.Shared.Teams)
		end)
		local relation = Teams.Relation(myTeam, actor.Team)
		local enabled = h ~= nil and h.Enabled
		if relation == "Ally" and enabled then
			okOutline = false
		end
		if relation == "Prey" and not (enabled and h.OutlineColor == Teams.PreyOutlineColor) then
			okOutline = false
		end
		if relation == "Predator" and not (enabled and h.OutlineColor == Teams.PredatorOutlineColor) then
			okOutline = false
		end
		seen += 1
	end
end
check(okOutline, "proie en vert, prédateur en rouge, alliés sans contour (" .. seen .. " vérifiés)")

-- ---------------------------------------------------------------------------
section("Fin de manche et retour au lobby")
check(advanceUntil(function()
	return phase() == "Results"
end, 300, 1), "écran de résultats atteint")
local state = server.RoundService.GetState()
check(state.Winner ~= nil, "un vainqueur est désigné : " .. tostring(state.Winner) .. " (" .. tostring(state.WinReason) .. ")")
check(advanceUntil(function()
	return phase() == "Intermission"
end, 40), "retour à l'intermission")
Engine.Advance(1)
local mapLeft = false
for _, c in World.workspace:GetChildren() do
	if string.sub(c.Name, 1, 4) == "Map_" then
		mapLeft = true
	end
end
check(not mapLeft, "la map est nettoyée")
check(alice:GetAttribute("Team") == nil, "plus d'équipe dans le lobby")
check(alice.Character and math.abs(alice.Character.HumanoidRootPart.Position.Z) < 80, "Alice est revenue au lobby")

-- ---------------------------------------------------------------------------
section("Joueur qui part en cours de manche")
check(advanceUntil(function()
	return phase() == "Round"
end, 60), "nouvelle manche")
World.RemovePlayer(carl)
Engine.Advance(2)
check(server.ActorService.FromPlayer(carl) == nil, "acteur retiré")

-- ---------------------------------------------------------------------------
print(string.format("\n%d vérifications OK, %d échec(s), %d erreur(s) d'exécution, %d avertissement(s)", passes, #failures, #Engine.Errors, #World.Warnings))
for _, w in World.Warnings do
	print("  warn: " .. w)
end
for _, e in Engine.Errors do
	print(e)
end
process.exit((#failures > 0 or #Engine.Errors > 0) and 1 or 0)

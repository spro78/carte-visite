--!nocheck
--[[
	test_rescue.luau : tranche verticale jouable sur THE CANYON (simulation).
	Vérifie avec le vrai code serveur et client :
	  - avatars intacts et contour lumineux aux couleurs de l'équipe ;
	  - zones sûres des trois camps : géométrie, repère au sol, protection
	    vérifiée par le serveur (capture et morsure refusées), adversaires non
	    protégés chez les autres, pastille du HUD et étiquette "SAFE" ;
	  - capture -> à terre (couché, ancré, immobile, même équipe, chrono) ;
	  - portage à la touche C par le client, soudure qui suit le porteur, mains
	    prises, lâcher et reprise, réanimation dans la zone sûre ;
	  - conversion au bout du chrono, sans coéquipier debout, après un reset ;
	  - porteur attrapé : le coéquipier porté retombe avec un chrono minimum ;
	  - HUD sans chevauchement avec la pastille d'état sur 4 écrans de PC.
	Ce que ce test ne remplace pas : un essai dans Roblox Studio (physique réelle
	de la soudure et de l'ancrage, propriété réseau, rendu des Highlights,
	animations, sensation en vraie partie).
]]
local H = require("./harness")
local Layout = require("./layout")
local World, Engine = H.World, H.Engine
local roblox = H.Roblox
local Vector2, Vector3, CFrame, Enum = roblox.Vector2, roblox.Vector3, roblox.CFrame, roblox.Enum
local check, section = H.check, H.section

local server = H.boot(function(Config)
	Config.Debug.ForceMap = "TheCanyon"
	Config.Debug.DisableBots = true
end)
local Config = server.Config
local Teams = server.Teams
local O = Config.World.MapOrigin
local services = World.game.ServerScriptService.Server.Services
local RescueService = H.require(services.RescueService)
local SafeZoneService = H.require(services.SafeZoneService)
local MapBase = H.require(World.game.ServerScriptService.Server.Maps.MapBase)

local alice = World.AddPlayer("Alice", { client = true })
local others = {}
for _, name in { "Bob", "Carl", "Dana", "Eve", "Finn" } do
	others[name] = World.AddPlayer(name)
end
local players = { Alice = alice, Bob = others.Bob, Carl = others.Carl, Dana = others.Dana, Eve = others.Eve, Finn = others.Finn }
local function actor(name)
	return server.ActorService.FromPlayer(players[name])
end
local function char(name)
	return players[name].Character
end
local function root(name)
	return char(name).HumanoidRootPart
end

-- Équipes du scénario (posées par le serveur, comme un tirage)
local function setTeams(map)
	H.onServer(function()
		for name, team in map do
			server.TeamService.SetTeam(actor(name), team)
		end
	end)
end

-- Tout le monde loin de tout le monde (aucune capture parasite)
local PARK = {
	Alice = Vector3.new(-140, 3, -140),
	Bob = Vector3.new(140, 3, -140),
	Carl = Vector3.new(-140, 3, 60),
	Dana = Vector3.new(140, 3, 60),
	Eve = Vector3.new(-60, 3, -150),
	Finn = Vector3.new(60, 3, -150),
}
local function park(except)
	for name, offset in PARK do
		if not (except and except[name]) and char(name) and char(name):GetAttribute("Downed") ~= true then
			H.teleport(actor(name), O + offset)
		end
	end
end

-- Point dans le repère d'un camp (x : côté, z : vers l'arrière), à hauteur d'un joueur debout
local function zonePoint(team, x, z)
	local base = MapBase.ActiveBases[team]
	return base.CFrame:PointToWorldSpace(Vector3.new(x, 0, z)) + Vector3.new(0, 3, 0)
end
-- Plein champ, loin des camps et des zones sûres
local OPEN = O + Vector3.new(60, 3, -40)

local function status(player)
	local hud = player.PlayerGui:FindFirstChild("HuntOrHideHUD")
	local pill = hud and hud:FindFirstChild("Status")
	local label = pill and pill:FindFirstChild("Text")
	return pill and pill.Visible and label and label.Text or nil, pill
end

local function feedHas(player, text)
	local hud = player.PlayerGui:FindFirstChild("HuntOrHideHUD")
	local feed = hud and hud:FindFirstChild("KillFeed")
	for _, line in feed and feed:GetChildren() or {} do
		local label = line:FindFirstChild("Text")
		if label and string.find(label.Text, text, 1, true) then
			return true
		end
	end
	return false
end

local function serverNow()
	return H.onServer(function()
		return World.workspace:GetServerTimeNow()
	end)
end

-- ---------------------------------------------------------------------------
section("Lancement de THE CANYON (6 joueurs, sans bots)")
check(H.advanceUntil(function()
	return H.phase() == "Countdown"
end, 60), "décompte")
setTeams({ Alice = "FOX", Bob = "FOX", Finn = "FOX", Carl = "SNAKE", Dana = "SNAKE", Eve = "CHICKEN" })
-- Personne ne reste sur la plateforme d'un autre camp (sinon le Raid lui fait
-- voler un œuf dès le GO, et un porteur d'œuf a les mains prises)
park()
check(H.advanceUntil(function()
	return H.phase() == "Round"
end, 10), "manche lancée")
Engine.Advance(3) -- fin de la protection d'apparition
park()
Engine.Advance(0.5)

-- ---------------------------------------------------------------------------
section("Avatars intacts, contour aux couleurs de l'équipe")
local okAvatar, okOutline, seen = true, true, 0
for name in players do
	local c = char(name)
	if c:FindFirstChild("AnimalParts") ~= nil or c.Head:GetAttribute("HoH_OriginalColor") ~= nil then
		okAvatar = false
	end
	local h = c:FindFirstChild("HoH_Outline")
	local def = Teams.Get(c:GetAttribute("Team"))
	if not (h and h.Enabled and def and h.OutlineColor == def.Color and h.FillTransparency == 1 and h.DepthMode == Enum.HighlightDepthMode.AlwaysOnTop) then
		okOutline = false
	end
	seen += 1
end
check(okAvatar, "aucun ajout ni recoloration sur les " .. seen .. " avatars")
check(okOutline, "contour lumineux seul (sans remplissage), couleur de l'équipe : renards orange, poules jaunes, vipères vertes")
check(Teams.Defs.FOX.Color == roblox.Color3.fromRGB(240, 128, 40) and Teams.Defs.CHICKEN.Color == roblox.Color3.fromRGB(250, 222, 90) and Teams.Defs.SNAKE.Color.G > 0.9 and Teams.Defs.SNAKE.Color.R < 0.3, "SNAKE garde son nom et devient vert")

-- ---------------------------------------------------------------------------
section("Zones sûres : géométrie et repère au sol")
local cfg = Config.Maps.TheCanyon
local half = cfg.GroundSize / 2
for _, team in Teams.Order do
	local base = MapBase.ActiveBases[team]
	local zone = base.Safe
	check(zone.HalfWidth > base.Radius and zone.Back > base.Radius + 4 and zone.Front >= base.Radius, string.format("%s : zone autour (±%d) et derrière (%d) la plateforme (%d)", team, zone.HalfWidth, zone.Back, base.Radius))
	local inside = true
	for _, corner in { { -zone.HalfWidth, zone.Back }, { zone.HalfWidth, zone.Back } } do
		local p = base.CFrame:PointToWorldSpace(Vector3.new(corner[1], 0, corner[2]))
		if math.abs(p.X - O.X) > half or math.abs(p.Z - O.Z) > half then
			inside = false
		end
	end
	check(inside, team .. " : la zone tient dans la carte")
	local camp = World.workspace:FindFirstChild("Map_TheCanyon"):FindFirstChild(team .. "_Camp")
	local dashes, label = 0, nil
	for _, d in camp:GetDescendants() do
		if d.Name == "SafeZoneDash" then
			dashes += 1
		elseif d.Name == "SafeZoneLabel" then
			label = d
		end
	end
	check(dashes >= 24 and label ~= nil, string.format("%s : liseré pointillé (%d tirets) et mention SAFE ZONE au sol", team, dashes))
end

-- ---------------------------------------------------------------------------
section("Zone sûre : protection vérifiée par le serveur")
local capsCarl = actor("Carl").RoundCaptures
H.teleport(actor("Alice"), zonePoint("FOX", 0, MapBase.ActiveBases.FOX.Radius + 10)) -- derrière la plateforme
Engine.Advance(0.3)
H.teleport(actor("Carl"), root("Alice").Position + Vector3.new(2, 0, 0))
Engine.Advance(0.6)
check(char("Alice"):GetAttribute("Downed") == nil and actor("Carl").RoundCaptures == capsCarl, "un chasseur collé à un défenseur dans SA zone ne l'attrape pas")
check(char("Alice"):GetAttribute("SafeZone") == true and char("Carl"):GetAttribute("SafeZone") == nil, "attribut SafeZone : défenseur oui, adversaire non")
check(H.onServer(function()
	return server.CaptureService.CanCapture(actor("Carl"), actor("Alice"), 2)
end) == false, "CanCapture refuse la capture (serveur)")
local text = status(alice)
check(text ~= nil and string.find(text, "SAFE ZONE", 1, true) ~= nil, "HUD d'Alice : " .. tostring(text))
-- Morsure de la vipère sur un défenseur à l'abri : sans effet
H.onServer(function()
	char("Carl"):SetAttribute("AbilityReadyAt", nil)
	server.AbilityService.TryAbility(actor("Carl"), true)
end)
Engine.Advance(0.1)
check(char("Alice"):GetAttribute("SlowedUntil") == nil, "la morsure ne touche pas un défenseur dans sa zone")
-- Étiquette vue par Alice au-dessus d'un coéquipier protégé
H.teleport(actor("Bob"), zonePoint("FOX", 8, MapBase.ActiveBases.FOX.Radius + 6))
Engine.Advance(0.5)
local bobTag = char("Bob").Head:FindFirstChild("HoH_TeamBadge")
local bobChip = bobTag and bobTag.Row.Team
check(bobChip and bobChip.Text == "SAFE", "étiquette au-dessus de Bob : " .. tostring(bobChip and bobChip.Text))
-- Un adversaire dans la zone d'un AUTRE camp n'est pas protégé (vol du Raid)
local capsBob = actor("Bob").RoundCaptures
H.teleport(actor("Eve"), zonePoint("FOX", -8, MapBase.ActiveBases.FOX.Radius + 6))
Engine.Advance(0.1)
H.teleport(actor("Bob"), root("Eve").Position + Vector3.new(2, 0, 0))
Engine.Advance(0.4)
check(char("Eve"):GetAttribute("Downed") == true or actor("Eve").Team == "FOX", "une poule entrée dans le camp des renards s'y fait attraper")
check(actor("Bob").RoundCaptures == capsBob + 1, "capture comptée pour Bob")
-- Eve était seule poule : sans coéquipier debout, elle rejoint aussitôt les renards
Engine.Advance(0.3)
check(actor("Eve").Team == "FOX" and char("Eve"):GetAttribute("Downed") == nil, "sans coéquipier pour la porter : conversion immédiate (renard)")

-- ---------------------------------------------------------------------------
section("Capture en plein champ : à terre")
setTeams({ Alice = "FOX", Bob = "FOX", Finn = "FOX", Carl = "SNAKE", Dana = "SNAKE", Eve = "CHICKEN" })
park()
Engine.Advance(2.5)
local carlCaps = actor("Carl").RoundCaptures
H.teleport(actor("Bob"), OPEN)
Engine.Advance(0.2)
local bobPos = root("Bob").Position
H.teleport(actor("Carl"), bobPos + Vector3.new(2, 0, 0))
Engine.Advance(0.3)
H.teleport(actor("Carl"), O + PARK.Carl)
local bob = char("Bob")
check(bob:GetAttribute("Downed") == true, "Bob est à terre")
check(actor("Bob").Team == "FOX", "il reste dans son équipe (FOX)")
check(actor("Carl").RoundCaptures == carlCaps + 1, "capture comptée pour Carl")
check(bob.HumanoidRootPart.Anchored and math.abs(bob.HumanoidRootPart.CFrame.UpVector.Y) < 0.2, "couché au sol (racine ancrée, corps à l'horizontale)")
check(bob.HumanoidRootPart.Position.Y < 2 and (Vector3.new(bob.HumanoidRootPart.Position.X, 0, bob.HumanoidRootPart.Position.Z) - Vector3.new(bobPos.X, 0, bobPos.Z)).Magnitude < 1, "là où il a été attrapé")
local untilTime = bob:GetAttribute("DownedUntil")
check(type(untilTime) == "number" and math.abs(untilTime - serverNow() - Config.Rescue.BleedOutSeconds) < 1.5, string.format("chrono de %ds publié", Config.Rescue.BleedOutSeconds))
check(bob:GetAttribute("DownedBy") == "Carl", "on sait qui l'a mis à terre")
check(H.onServer(function()
	return server.CaptureService.CanCapture(actor("Carl"), actor("Bob"), 5)
end) == false, "un joueur à terre ne peut plus être attrapé")
check(H.onServer(function()
	return #server.RoundState.GetActiveParticipants()
end) == 5, "il ne compte plus parmi les joueurs actifs (captures, morsures, bots)")
check(feedHas(alice, "Carl") and feedHas(alice, "Bob"), "le fil des captures d'Alice montre Carl > Bob")
-- Marqueur HELP et étiquette DOWN vus par une coéquipière
Engine.Advance(0.3)
local help = bob.Head:FindFirstChild("HoH_Help")
local helpText = help and help.Pill:FindFirstChild("Text")
check(help and help.Enabled and help.AlwaysOnTop and helpText and string.find(helpText.Text, "HELP", 1, true) ~= nil, "marqueur HELP au-dessus de Bob pour Alice : " .. tostring(helpText and helpText.Text))
check(bob.Head.HoH_TeamBadge.Row.Team.Text == "DOWN", "étiquette DOWN")
text = status(alice)
check(text ~= nil and string.find(text, "Bob is down", 1, true) ~= nil, "consigne de secours dans le HUD d'Alice : " .. tostring(text))

-- ---------------------------------------------------------------------------
section("Portage à la touche C (client d'Alice)")
H.teleport(actor("Alice"), root("Bob").Position + Vector3.new(4, 2.1, 0))
Engine.Advance(0.4)
text = status(alice)
check(text ~= nil and string.find(text, "Press C to carry Bob", 1, true) ~= nil, "à portée : " .. tostring(text))
local hud = alice.PlayerGui.HuntOrHideHUD
local carryDock = hud.BottomCenter:FindFirstChild("Carry")
check(carryDock and carryDock.Visible and carryDock.KeyBadge.Key.Text == "C" and carryDock.Medallion.Main.Text == "CARRY", "médaillon CARRY avec la puce C dans le dock")
do
	local camera = World.workspace.CurrentCamera
	for _, size in { { 1280, 720 }, { 1366, 768 }, { 1440, 900 }, { 1920, 1080 } } do
		local viewport = Vector2.new(size[1], size[2])
		camera.ViewportSize = viewport
		Engine.Advance(0.05)
		local problems, count = Layout.HudProblems(hud, viewport)
		check(#problems == 0, string.format("HUD avec consigne et CARRY %dx%d : %d blocs sans chevauchement", size[1], size[2], count) .. (#problems > 0 and ("\n      " .. table.concat(problems, "\n      ")) or ""))
	end
	camera.ViewportSize = Vector2.new(1280, 720)
	Engine.Advance(0.05)
end
World.PressKey(alice, Enum.KeyCode.C, true)
World.PressKey(alice, Enum.KeyCode.C, false)
Engine.Advance(0.2)
check(bob:GetAttribute("CarriedBy") == "Alice" and char("Alice"):GetAttribute("Carrying") == "Bob", "Alice porte Bob (intention validée par le serveur)")
check(bob:GetAttribute("DownedUntil") == nil, "chrono suspendu pendant le portage")
check(math.abs((char("Alice"):GetAttribute("SpeedMult") or 1) - Config.Rescue.CarrySpeedMultiplier) < 0.01, "porteuse ralentie (x" .. Config.Rescue.CarrySpeedMultiplier .. ")")
check(typeof(char("Alice"):GetAttribute("ObjectiveTarget")) == "Vector3", "la flèche d'objectif pointe vers son camp")
local weld = bob.HumanoidRootPart:FindFirstChild("HoH_CarryWeld")
check(weld and weld.Part0 == root("Alice") and not bob.HumanoidRootPart.Anchored, "Bob est soudé sur l'épaule d'Alice")
check(H.onServer(function()
	return root("Bob"):GetNetworkOwner()
end) == alice, "propriété réseau : la porteuse")
text = status(alice)
check(text ~= nil and string.find(text, "CARRYING Bob", 1, true) ~= nil, "HUD : " .. tostring(text))
check(carryDock.Visible and carryDock.Medallion.Main.Text == "DROP", "le médaillon devient DROP")
-- Le corps suit la porteuse
local start = root("Alice").Position
World.SetMoveVector(alice, Vector3.new(1, 0, 0))
Engine.Advance(1)
World.SetMoveVector(alice, Vector3.zero)
Engine.Advance(0.6)
local moved = (root("Alice").Position - start).Magnitude
local gap = (root("Bob").Position - root("Alice").Position).Magnitude
check(moved > 8 and gap < 3, string.format("Bob suit Alice (%.0f studs parcourus, écart %.1f)", moved, gap))
check(math.abs(root("Bob").CFrame.UpVector.Y) < 0.2, "porté à l'horizontale")
-- Mains prises : Alice ne peut pas attraper une poule pendant le portage
setTeams({ Eve = "CHICKEN", Finn = "CHICKEN" })
Engine.Advance(2.2) -- fin de la protection d'Eve après sa conversion
local aliceCaps = actor("Alice").RoundCaptures
H.teleport(actor("Eve"), root("Alice").Position + Vector3.new(-2.5, 0, 0))
Engine.Advance(0.5)
check(actor("Alice").RoundCaptures == aliceCaps and char("Eve"):GetAttribute("Downed") == nil, "une porteuse n'attrape personne (mains prises)")
H.teleport(actor("Eve"), O + PARK.Eve)
setTeams({ Eve = "CHICKEN", Finn = "FOX" })

-- Lâcher puis reprendre
World.PressKey(alice, Enum.KeyCode.C, true)
World.PressKey(alice, Enum.KeyCode.C, false)
Engine.Advance(0.3)
check(bob:GetAttribute("CarriedBy") == nil and char("Alice"):GetAttribute("Carrying") == nil and bob.HumanoidRootPart.Anchored, "C de nouveau : Alice lâche Bob, qui retombe à terre")
local left = (bob:GetAttribute("DownedUntil") or 0) - serverNow()
check(left >= Config.Rescue.DropGraceSeconds - 0.5, string.format("chrono relancé (%.1f s restantes)", left))
check(math.abs((char("Alice"):GetAttribute("SpeedMult") or 1) - 1) < 0.01, "vitesse normale rétablie")
World.PressKey(alice, Enum.KeyCode.C, true)
World.PressKey(alice, Enum.KeyCode.C, false)
Engine.Advance(0.3)
check(bob:GetAttribute("CarriedBy") == "Alice", "et le reprend")

-- ---------------------------------------------------------------------------
section("Réanimation dans la zone sûre du camp")
local objectivesBefore = actor("Alice").RoundObjectives
H.teleport(actor("Alice"), zonePoint("FOX", 0, -(MapBase.ActiveBases.FOX.Radius + 2)))
Engine.Advance(0.4)
check(bob:GetAttribute("Downed") == nil and actor("Bob").Team == "FOX", "Bob se relève dans son équipe (FOX)")
check(not bob.HumanoidRootPart.Anchored and bob.HumanoidRootPart:FindFirstChild("HoH_CarryWeld") == nil and bob.HumanoidRootPart.CFrame.UpVector.Y > 0.9, "debout, plus soudé ni ancré")
check(H.onServer(function()
	return MapBase.IsInBase(MapBase.ActiveBases.FOX, root("Bob").Position, 1)
end), "sur la plateforme de son camp")
check(bob:FindFirstChildOfClass("ForceField") ~= nil, "protection visible après la réanimation")
check(char("Alice"):GetAttribute("Carrying") == nil and math.abs((char("Alice"):GetAttribute("SpeedMult") or 1) - 1) < 0.01, "Alice ne porte plus rien")
check(actor("Alice").RoundObjectives == objectivesBefore + 1, "sauvetage compté comme objectif pour Alice")
Engine.Advance(0.2)
check(feedHas(alice, "saved"), "fil : « Alice saved Bob »")
check(H.onServer(function()
	return root("Bob"):GetNetworkOwner()
end) == players.Bob, "propriété réseau rendue à Bob")

-- ---------------------------------------------------------------------------
section("Alice à terre : son HUD")
park()
Engine.Advance(2.5)
H.teleport(actor("Alice"), OPEN)
Engine.Advance(0.2)
H.teleport(actor("Carl"), root("Alice").Position + Vector3.new(2, 0, 0))
Engine.Advance(0.3)
H.teleport(actor("Carl"), O + PARK.Carl)
Engine.Advance(0.3)
check(char("Alice"):GetAttribute("Downed") == true, "Alice est à terre")
local pill
text, pill = status(alice)
check(text ~= nil and string.find(text, "YOU'RE DOWN", 1, true) ~= nil and pill:FindFirstChild("Timer").Visible, "HUD : " .. tostring(text) .. " + jauge du chrono")
local dockVisible = false
for _, m in hud.BottomCenter:GetChildren() do
	if m:IsA("Frame") and m.Visible then
		dockVisible = true
	end
end
check(not dockVisible, "aucune action à terre (dock vide)")
local before = root("Alice").Position
World.SetMoveVector(alice, Vector3.new(0, 0, -1))
Engine.Advance(1)
World.SetMoveVector(alice, Vector3.zero)
check((root("Alice").Position - before).Magnitude < 0.05, "Alice ne peut pas bouger")
-- Disposition du HUD avec la pastille d'état (et une annonce) sur 4 écrans de PC
H.onServer(function()
	World.Require(World.game.ReplicatedStorage.Shared.Remotes).Get("Announce"):FireAllClients("CHICKEN stole an egg from the SNAKES!", roblox.Color3.fromRGB(250, 222, 90))
end)
Engine.Advance(0.2)
local camera = World.workspace.CurrentCamera
for _, size in { { 1280, 720 }, { 1366, 768 }, { 1440, 900 }, { 1920, 1080 } } do
	local viewport = Vector2.new(size[1], size[2])
	camera.ViewportSize = viewport
	Engine.Advance(0.05)
	local problems, count, rects = Layout.HudProblems(hud, viewport)
	local st = rects[hud.Status]
	check(#problems == 0 and st and st.Visible, string.format("HUD à terre %dx%d : %d blocs sans chevauchement", size[1], size[2], count) .. (#problems > 0 and ("\n      " .. table.concat(problems, "\n      ")) or ""))
	if st then
		check(st.Y + st.H <= viewport.Y * 0.3, string.format("[%dx%d] pastille dans le haut de l'écran (bas à %d px)", size[1], size[2], math.floor(st.Y + st.H)))
	end
end
camera.ViewportSize = Vector2.new(1280, 720)
-- Bob vient la porter (bot ou joueur : même règle côté serveur)
H.teleport(actor("Bob"), root("Alice").Position + Vector3.new(3, 2.1, 0))
Engine.Advance(0.1)
check(H.onServer(function()
	return RescueService.TryCarry(actor("Bob"))
end), "Bob ramasse Alice")
Engine.Advance(0.3)
text = status(alice)
check(text ~= nil and string.find(text, "CARRIED HOME by Bob", 1, true) ~= nil, "HUD : " .. tostring(text))
H.teleport(actor("Bob"), zonePoint("FOX", 0, 0))
Engine.Advance(0.4)
check(char("Alice"):GetAttribute("Downed") == nil and actor("Alice").Team == "FOX", "Alice se relève dans son camp")

-- ---------------------------------------------------------------------------
section("Personne ne vient : conversion au bout du chrono")
park()
Engine.Advance(2.5)
H.teleport(actor("Finn"), OPEN)
Engine.Advance(0.2)
local finnPos = root("Finn").Position
H.teleport(actor("Carl"), finnPos + Vector3.new(2, 0, 0))
Engine.Advance(0.3)
H.teleport(actor("Carl"), O + PARK.Carl)
check(char("Finn"):GetAttribute("Downed") == true, "Finn est à terre (Alice et Bob sont debout)")
Engine.Advance(Config.Rescue.BleedOutSeconds - 4)
check(char("Finn"):GetAttribute("Downed") == true and actor("Finn").Team == "FOX", string.format("après %ds : toujours renard, toujours à terre", Config.Rescue.BleedOutSeconds - 4))
Engine.Advance(4.5)
check(actor("Finn").Team == "SNAKE" and char("Finn"):GetAttribute("Downed") == nil, "chrono écoulé : Finn rejoint les vipères (équipe de Carl)")
local finnNow = root("Finn").Position
check((Vector3.new(finnNow.X, 0, finnNow.Z) - Vector3.new(finnPos.X, 0, finnPos.Z)).Magnitude < 4 and finnNow.Y > 2, "il se relève sur place")
check(char("Finn"):FindFirstChildOfClass("ForceField") ~= nil, "protection visible après la conversion")
Engine.Advance(0.2)
check(feedHas(alice, "joined the"), "fil : « Finn joined the SNAKES »")

-- ---------------------------------------------------------------------------
section("Porteur attrapé, puis plus aucun renard debout")
setTeams({ Finn = "FOX" })
park()
Engine.Advance(2.5)
H.teleport(actor("Bob"), OPEN)
Engine.Advance(0.2)
H.teleport(actor("Carl"), root("Bob").Position + Vector3.new(2, 0, 0))
Engine.Advance(0.3)
H.teleport(actor("Carl"), O + PARK.Carl)
H.teleport(actor("Finn"), root("Bob").Position + Vector3.new(3, 2.1, 0))
Engine.Advance(0.1)
check(H.onServer(function()
	return RescueService.TryCarry(actor("Finn"))
end), "Finn ramasse Bob")
Engine.Advance(1.5) -- fin de la protection de Carl
H.teleport(actor("Carl"), root("Finn").Position + Vector3.new(-2.5, 0, 0))
Engine.Advance(0.3)
H.teleport(actor("Carl"), O + PARK.Carl)
check(char("Finn"):GetAttribute("Downed") == true, "le porteur (Finn) est attrapé")
check(char("Bob"):GetAttribute("CarriedBy") == nil and char("Bob"):GetAttribute("Downed") == true and root("Bob").Anchored, "Bob retombe à terre")
left = (char("Bob"):GetAttribute("DownedUntil") or 0) - serverNow()
check(left >= Config.Rescue.DropGraceSeconds - 0.5, string.format("avec au moins %ds de chrono (%.1f)", Config.Rescue.DropGraceSeconds, left))
check(actor("Bob").Team == "FOX" and actor("Finn").Team == "FOX", "tous deux toujours renards (Alice est debout)")
-- Alice, dernière renarde debout, se fait attraper : plus personne pour porter
Engine.Advance(1)
H.teleport(actor("Alice"), OPEN + Vector3.new(-30, 0, 20))
Engine.Advance(0.2)
H.teleport(actor("Carl"), root("Alice").Position + Vector3.new(2, 0, 0))
Engine.Advance(0.5)
check(actor("Alice").Team == "SNAKE" and actor("Bob").Team == "SNAKE" and actor("Finn").Team == "SNAKE", "plus aucun renard debout : les trois rejoignent aussitôt les vipères")
check(char("Alice"):GetAttribute("Downed") == nil and char("Bob"):GetAttribute("Downed") == nil and char("Finn"):GetAttribute("Downed") == nil, "personne ne reste à terre")
check(#RescueService.GetDowned() == 0, "aucun état « à terre » restant côté serveur")

-- ---------------------------------------------------------------------------
section("Réapparaître à terre (reset) vaut abandon")
setTeams({ Alice = "FOX", Bob = "FOX", Finn = "SNAKE", Carl = "SNAKE", Dana = "CHICKEN", Eve = "CHICKEN" })
park()
Engine.Advance(2.5)
H.teleport(actor("Dana"), OPEN)
Engine.Advance(0.2)
H.teleport(actor("Bob"), root("Dana").Position + Vector3.new(2, 0, 0))
Engine.Advance(0.3)
H.teleport(actor("Bob"), O + PARK.Bob)
check(char("Dana"):GetAttribute("Downed") == true and actor("Dana").Team == "CHICKEN", "Dana (poule) est à terre, Eve est debout")
H.onServer(function()
	players.Dana:LoadCharacter()
end)
Engine.Advance(1)
check(actor("Dana").Team == "FOX" and char("Dana"):GetAttribute("Downed") == nil, "après un reset, Dana a rejoint les renards (pas de résurrection gratuite)")
check(#RescueService.GetDowned() == 0, "état nettoyé")

-- ---------------------------------------------------------------------------
section("Fin de manche : tout le monde debout")
park()
Engine.Advance(2.5)
H.teleport(actor("Eve"), OPEN)
Engine.Advance(0.2)
H.teleport(actor("Alice"), root("Eve").Position + Vector3.new(2, 0, 0))
Engine.Advance(0.3)
H.teleport(actor("Alice"), O + PARK.Alice)
check(char("Eve"):GetAttribute("Downed") == true or actor("Eve").Team == "FOX", "Eve attrapée par Alice")
check(H.advanceUntil(function()
	return H.phase() == "Results"
end, 300, 1), "écran de résultats")
local stillDown = 0
for name in players do
	local c = char(name)
	if c and (c:GetAttribute("Downed") or c.HumanoidRootPart.Anchored) then
		stillDown += 1
	end
end
check(stillDown == 0, "personne n'est resté à terre ni ancré")
check(H.advanceUntil(function()
	return H.phase() == "Intermission"
end, 40, 1), "retour au lobby")
check(MapBase.ActiveBases == nil, "camps de la manche oubliés (pas de zone sûre au lobby)")

H.finish()

--!nocheck
--[[
	scenes.luau : fait tourner le jeu simulé et exporte des scènes pour le rendu.
	Usage : lune run tools/sim/scenes.luau <sourcemap.json> <sortie.json> [groupe]
	Groupes : lobby, maps, round (défaut : tous)
]]

local process = require("@lune/process")
local fs = require("@lune/fs")
local serde = require("@lune/serde")
local World = require("./world")
local Export = require("./export")
World.Shared.HoH_Language = nil -- rendus dans la langue du jeu (Config.Language)
local Engine = World.Engine
local roblox = Engine.Roblox
local Vector3 = roblox.Vector3

local sourcemap = process.args[1] or "sourcemap.json"
local outPath = process.args[2] or "tools/preview/out/scenes.json"
local group = process.args[3] or "all"
-- Graine du hasard, pour rejouer une mise en scène : SIM_SEED=<entier>
local seed = tonumber(process.env.SIM_SEED)
if seed then
	math.randomseed(seed)
end
local forcedMap = process.args[4] -- map imposée pour les groupes round, mobile et players

Engine.Quiet = true
World.LoadSourcemap(sourcemap)
if group == "modes" then
	-- Groupe "modes" : carte héroïque, mode imposé par le 4e argument
	Engine.Run("server", function()
		local Config = World.Require(World.game.ReplicatedStorage.Shared.Config)
		Config.Debug.ForceMap = "TheCarousel"
		Config.Debug.ForceMode = forcedMap or "Carousel"
	end)
elseif forcedMap then
	Engine.Run("server", function()
		World.Require(World.game.ReplicatedStorage.Shared.Config).Debug.ForceMap = forcedMap
	end)
end
Engine.Run("server", function()
	World.StartServer()
end)

local scenes = {}
local hero
local function v(t)
	return { t.X, t.Y, t.Z }
end

-- Groupes "mobile" et "rescue_mobile" : appareil tactile simulé (pas de
-- clavier), vues de téléphone
local touchDevice = group == "mobile" or group == "rescue_mobile"
if touchDevice then
	World.Input.TouchEnabled = true
	World.Input.KeyboardEnabled = false
	World.Input.MouseEnabled = false
end

-- Taille d'écran : comme sur un vrai appareil, le changement prévient le HUD,
-- le fil des captures et les boutons tactiles
local function setViewport(w, h)
	local cam = World.workspace.CurrentCamera
	cam.ViewportSize = roblox.Vector2.new(w, h)
end

local function addScene(name, caption, center, radius, camera, extra)
	if extra and extra.hud then
		-- (hud = true : exporter l'interface du héros à la taille demandée)
		setViewport(extra.width or 1280, extra.height or 720)
		-- La caméra simulée prend la place de la caméra du rendu : les repères
		-- de l'interface projetés dans le monde (flèche d'objectif) tombent juste
		if camera and camera.position and camera.target and not camera.ortho then
			local cam = World.workspace.CurrentCamera
			cam.CFrame = roblox.CFrame.lookAt(Vector3.new(table.unpack(camera.position)), Vector3.new(table.unpack(camera.target)))
			cam.FieldOfView = camera.fov or 70
			Engine.Advance(1 / 30)
		end
		extra.hud = Export.PlayerGui(hero)
	end
	local data = Export.Parts(center, radius)
	local scene = {
		name = name,
		caption = caption,
		width = extra and extra.width or 1280,
		height = extra and extra.height or 720,
		center = v(center),
		shadowExtent = radius,
		parts = data.parts,
		meshes = data.meshes,
		highlights = data.highlights,
		terrain = data.terrain,
		terrainColors = data.terrainColors,
		water = data.water,
		lighting = data.lighting,
		camera = camera,
		sky = extra and extra.sky,
		hud = extra and extra.hud,
		hudScale = extra and extra.hudScale,
		coreTouch = extra and extra.hud ~= nil and touchDevice or nil,
	}
	table.insert(scenes, scene)
	print(string.format("scene %-28s parts=%d", name, #data.parts))
end

local Config
Engine.Run("server", function()
	Config = World.Require(World.game.ReplicatedStorage.Shared.Config)
end)

-- Caméra par défaut de Roblox (ClassicCamera) : derrière le personnage, à 12,5 studs
-- du point suivi (racine + 1,5 stud), inclinée de 15° vers le bas, champ vertical 70°
local function robloxCamera(player)
	local root = player.Character:FindFirstChild("HumanoidRootPart")
	local cf = root.CFrame
	local focus = cf.Position + Vector3.new(0, 1.5, 0)
	local look = (cf * roblox.CFrame.Angles(math.rad(-15), 0, 0)).LookVector
	return { position = v(focus - look * 12.5), target = v(focus), fov = 70 }
end

local function serverPhase()
	local phase
	Engine.Run("server", function()
		phase = World.Require(World.game.ServerScriptService.Server.Services.RoundState).Phase
	end)
	return phase
end

local function waitFor(predicate, maxSeconds)
	local t = 0
	while t < maxSeconds and not predicate() do
		Engine.Advance(0.5)
		t += 0.5
	end
end

-- Le joueur ferme les règles (bouton X)
local function closeHelp()
	local help = hero.PlayerGui.HuntOrHideHUD:FindFirstChild("Help")
	if help and help.Visible then
		for _, child in help:GetChildren() do
			if child:IsA("TextButton") and child.Text == "X" then
				child.Activated:Fire()
			end
		end
	end
	Engine.Advance(0.1)
end

-- Met une vraie poursuite au premier plan : on cherche un chasseur et sa proie
-- (bots) proches l'un de l'autre et on place le héros derrière eux, tourné vers
-- eux. Les positions des bots, les contours et le HUD restent ceux de la simulation.
local function stageChase()
	local actors, Teams
	Engine.Run("server", function()
		actors = World.Require(World.game.ServerScriptService.Server.Services.RoundState).GetParticipants()
		Teams = World.Require(World.game.ReplicatedStorage.Shared.Teams)
	end)
	local pairs = {}
	for _, a in actors do
		for _, b in actors do
			local ra = a.Character and a.Character:FindFirstChild("HumanoidRootPart")
			local rb = b.Character and b.Character:FindFirstChild("HumanoidRootPart")
			if a ~= b and ra and rb and a.Team and b.Team and a.Player ~= hero and b.Player ~= hero and Teams.CanCatch(a.Team, b.Team) then
				local d = (ra.Position - rb.Position).Magnitude
				-- En terrain ouvert, entre le centre et les camps (pas dans un camp)
				local O = Config.World.MapOrigin
				local da = Vector3.new(ra.Position.X - O.X, 0, ra.Position.Z - O.Z).Magnitude
				local db = Vector3.new(rb.Position.X - O.X, 0, rb.Position.Z - O.Z).Magnitude
				local open = da > 30 and da < 88 and db > 30 and db < 88
				if open and d > 4 then
					table.insert(pairs, { ra.Position, rb.Position, d })
				end
			end
		end
	end
	table.sort(pairs, function(x, y)
		return x[3] < y[3]
	end)
	-- Le plus proche couple dont la vue n'est pas bouchée par le décor (caméra
	-- par défaut de Roblox, derrière le héros)
	for _, pair in pairs do
		local hunter, prey = pair[1], pair[2]
		local dir = Vector3.new(prey.X - hunter.X, 0, prey.Z - hunter.Z).Unit
		-- Héros en retrait et décalé sur le côté, regard parallèle à la poursuite :
		-- les deux bots apparaissent à côté de lui, pas cachés derrière son avatar
		local spot = hunter - dir * 12 + Vector3.new(-dir.Z, 0, dir.X) * 7
		Engine.Run("server", function()
			hero.Character:PivotTo(roblox.CFrame.lookAt(Vector3.new(spot.X, hunter.Y, spot.Z), Vector3.new(spot.X + dir.X, hunter.Y, spot.Z + dir.Z)))
		end)
		Engine.Advance(0.25)
		local cam = robloxCamera(hero)
		local from = Vector3.new(table.unpack(cam.target))
		local to = Vector3.new(table.unpack(cam.position))
		local blocked = false
		Engine.Run("server", function()
			local params = Engine.Types.RaycastParams.new()
			params.FilterType = roblox.Enum.RaycastFilterType.Exclude
			params.FilterDescendantsInstances = { hero.Character }
			local hit = World.workspace:Raycast(from, to - from, params)
			blocked = hit ~= nil and hit.Instance.Transparency < 0.5
		end)
		if not blocked then
			return true
		end
	end
	return false
end

local function playerCamera(player, back, up)
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	local cf = root.CFrame
	local pos = cf.Position - cf.LookVector * back + Vector3.new(0, up, 0)
	return { position = v(pos), target = v(cf.Position + cf.LookVector * 20 + Vector3.new(0, 2, 0)), fov = 70 }
end

-- Le lobby avec quelques joueurs
Engine.Advance(1)
hero = World.AddPlayer("Malcom", { client = true })
local others = {}
for i, name in { "PixelPanda", "Zoey_Plays", "NinjaKai" } do
	others[i] = World.AddPlayer(name)
end
Engine.Advance(4)

if group == "all" or group == "lobby" then
	local L = Config.World.LobbyOrigin
	addScene("lobby_overview", "Lobby (generated by LobbyBuilder) - overview", L, 120, { position = { 95, 85, 120 }, target = { 0, 2, -5 }, fov = 55 })
	addScene("lobby_north", "Lobby - giant board and vote plates", L, 120, { position = { 0, 14, 10 }, target = { 0, 10, -60 }, fov = 65 })
	addScene("lobby_south", "Lobby - who catches who panel", L, 120, { position = { 0, 12, 20 }, target = { 0, 13, 66 }, fov = 60 })
	addScene("lobby_east_west", "Lobby - shop (left) and leaderboards (right)", L, 120, { position = { 0, 30, 60 }, target = { 0, 6, 0 }, fov = 75 })
	addScene("lobby_leaderboards", "Lobby - leaderboard walls and daily spin", L, 120, { position = { -20, 12, 10 }, target = { -58, 10, 5 }, fov = 75 })
	addScene("lobby_shop", "Lobby - giant gift box (shop)", L, 120, { position = { 22, 10, 6 }, target = { 52, 6, -6 }, fov = 70 })
	addScene("lobby_top", "Lobby - top-down", L, 120, { position = { 0, 300, 0.01 }, target = { 0, 0, 0 }, ortho = 160, up = { 0, 0, -1 } })
	addScene("hud_lobby_pc", "HUD in the lobby during the vote (PC 1280x720)", L, 120, playerCamera(hero, 14, 6), { hud = Export.PlayerGui(hero) })
	-- Vue joueur réelle : caméra par défaut de Roblox au spawn, règles affichées
	-- (première visite), puis fermées comme le ferait le joueur
	addScene("lobby_player_first_visit_pc", "Lobby, player view at spawn, first visit (PC 1280x720)", L, 120, robloxCamera(hero), { hud = true })
	closeHelp()
	addScene("lobby_player_pc", "Lobby, player view at spawn (PC 1280x720)", L, 120, robloxCamera(hero), { hud = true })
end

if group == "players" then
	-- Vues à hauteur de joueur pendant une vraie manche (map imposée en argument)
	local O = Config.World.MapOrigin
	local id = forcedMap or "map"
	waitFor(function()
		return hero:GetAttribute("Team") ~= nil and serverPhase() == "Countdown"
	end, 120)
	Engine.Advance(1)
	addScene(id .. "_player_spawn_pc", id .. " - player view at spawn (PC 1280x720)", O, 300, robloxCamera(hero), { hud = true })
	waitFor(function()
		return serverPhase() == "Round"
	end, 20)
	-- Le héros observe la manche sans être attrapé pendant l'attente (la mise en
	-- scène le déplace ensuite : il ne doit pas être à terre)
	Engine.Run("server", function()
		local CaptureService = World.Require(World.game.ServerScriptService.Server.Services.CaptureService)
		CaptureService.Protect(hero.Character, 40)
	end)
	Engine.Advance(14)
	stageChase()
	addScene(id .. "_player_chase_pc", id .. " - chase in the foreground (PC 1280x720)", O, 300, robloxCamera(hero), { hud = true })
end

if group == "modes" then
	-- Vote, composition des équipes et mode en jeu sur Carousel Valley
	local O = Config.World.MapOrigin
	local L = Config.World.LobbyOrigin
	local modeId = forcedMap or "Carousel"
	local VoteService
	Engine.Run("server", function()
		VoteService = World.Require(World.game.ServerScriptService.Server.Services.VoteService)
	end)
	closeHelp()
	waitFor(function()
		return serverPhase() == "Intermission"
	end, 60)
	Engine.Advance(1)
	-- Les autres joueurs votent (leurs noms s'affichent sous chaque carte)
	Engine.Run("server", function()
		local candidates = VoteService.GetCandidates()
		for i, p in others do
			VoteService.CastVote(p, candidates[(i % #candidates) + 1])
		end
		VoteService.CastVote(hero, candidates[2])
	end)
	Engine.Advance(1.2)
	addScene("modes_vote_pc", "Lobby vote: three modes, rules, votes and every player (PC 1280x720)", L, 120, robloxCamera(hero), { hud = true })
	addScene("modes_vote_phone", "Lobby vote on a phone (844x390)", L, 120, robloxCamera(hero), { hud = true, width = 844, height = 390 })
	addScene("modes_vote_portrait", "Lobby vote on a phone in portrait (390x844)", L, 120, robloxCamera(hero), { hud = true, width = 390, height = 844 })
	waitFor(function()
		return serverPhase() == "Countdown"
	end, 40)
	Engine.Advance(1)
	addScene("modes_lineup_pc", "Countdown: every player listed by team (" .. modeId .. ")", O, 300, robloxCamera(hero), { hud = true })
	waitFor(function()
		return serverPhase() == "Round"
	end, 20)
	local srv = {}
	Engine.Run("server", function()
		local services = World.game.ServerScriptService.Server.Services
		srv.ActorService = World.Require(services.ActorService)
		srv.CaptureService = World.Require(services.CaptureService)
		srv.Map = World.Require(World.game.ServerScriptService.Server.Maps.TheCarousel)
		srv.Carousel = World.Require(World.game.ServerScriptService.Server.Modes.Carousel)
		srv.CaptureService.Protect(hero.Character, 60)
	end)
	Engine.Advance(4)
	local function place(position, look)
		Engine.Run("server", function()
			local p = Vector3.new(position.X, O.Y + 3, position.Z)
			hero.Character:PivotTo(roblox.CFrame.lookAt(p, Vector3.new(look.X, p.Y, look.Z)))
		end)
		Engine.Advance(0.3)
	end
	if modeId == "EggRun" then
		-- Un nid hors de la butte du moulin (le simulateur ne gère pas le relief)
		local eggs = srv.Map.DebugState().Mode.Eggs
		local egg = eggs[1]
		for _, e in eggs do
			local deg = math.deg(math.atan2(e.Position.Z - O.Z, e.Position.X - O.X)) % 360
			if e.State == "Nest" and math.abs(deg - 30) > 20 then
				egg = e
			end
		end
		local p = egg.Position
		local away = Vector3.new(p.X - O.X, 0, p.Z - O.Z).Unit
		local side = Vector3.new(-away.Z, 0, away.X)
		-- Le long de la piste (dégagée par construction), décalé vers le centre :
		-- l'œuf apparaît à côté de l'avatar et la caméra ne heurte aucun décor
		place(p - side * 12 - away * 4, p + side * 6 - away * 4)
		addScene("modes_eggrun_nest_pc", "EGG RUN: a painted egg in its nest, arrow to the nearest egg", O, 300, robloxCamera(hero), { hud = true })
		place(p + side * 1.2, p + side * 12)
		Engine.Advance(0.3)
		addScene("modes_eggrun_carrier_pc", "EGG RUN: carrying an egg home (slower, visible to all)", O, 300, robloxCamera(hero), { hud = true })
		addScene("modes_eggrun_carrier_phone", "EGG RUN on a phone (844x390)", O, 300, robloxCamera(hero), { hud = true, width = 844, height = 390 })
	elseif modeId == "Carousel" then
		-- Bots dans les anneaux : les anneaux prennent la couleur de l'équipe
		local zonePositions = {}
		Engine.Run("server", function()
			for i = 1, 3 do
				zonePositions[i] = srv.Carousel.ZonePosition(i, 2.2)
			end
		end)
		local bots = {}
		Engine.Run("server", function()
			for _, a in srv.ActorService.GetAll() do
				if a.IsBot and a.Character then
					table.insert(bots, a)
				end
			end
		end)
		Engine.Run("server", function()
			for i, a in bots do
				local z = zonePositions[(i % 2) + 2]
				if i <= 6 and z then
					a.Character:PivotTo(roblox.CFrame.new(z + Vector3.new((i % 3 - 1) * 5, 3, (i % 2) * 4)))
				end
			end
		end)
		local z1 = zonePositions[1]
		local inward = Vector3.new(O.X - z1.X, 0, O.Z - z1.Z).Unit
		-- Au bord intérieur de l'anneau, tourné vers son centre : le cheval
		-- volant est au-dessus, l'anneau aux couleurs de l'équipe devant
		place(z1 + inward * 7, z1 - inward * 30)
		Engine.Advance(1.6)
		addScene("modes_carousel_ring_pc", "CAROUSEL: holding a ring under a flying horse", O, 300, robloxCamera(hero), { hud = true })
		addScene("modes_carousel_ring_phone", "CAROUSEL on a phone (844x390)", O, 300, robloxCamera(hero), { hud = true, width = 844, height = 390 })
		addScene("modes_carousel_aerial", "CAROUSEL: three moving rings around the valley", O, 300, { position = { O.X + 90, 110, O.Z + 110 }, target = { O.X, 0, O.Z }, fov = 55 })
	else
		stageChase()
		addScene("modes_chase_pc", "CHASE: pure chase on Carousel Valley", O, 300, robloxCamera(hero), { hud = true })
	end
end

if group == "mobile" then
	-- Appareil tactile simulé : vraies interfaces du jeu, contrôles Roblox dessinés
	local L = Config.World.LobbyOrigin
	closeHelp()
	addScene("phone_lobby", "Phone 844x390 (touch): lobby at spawn, vote", L, 120, robloxCamera(hero), { hud = true, width = 844, height = 390 })
	waitFor(function()
		return hero:GetAttribute("Team") ~= nil and serverPhase() == "Round"
	end, 120)
	Engine.Advance(6)
	local O = Config.World.MapOrigin
	Engine.Run("server", function()
		local Remotes = World.Require(World.game.ReplicatedStorage.Shared.Remotes)
		Remotes.Get("Announce"):FireAllClients("The egg went back to the CHICKENS!", roblox.Color3.fromRGB(255, 214, 60))
	end)
	Engine.Advance(0.3)
	stageChase()
	addScene("phone_round", "Phone 844x390 (touch): in round, map announcement", O, 300, robloxCamera(hero), { hud = true, width = 844, height = 390 })
	addScene("phone_round_portrait", "Phone 390x844 portrait (touch): in round", O, 300, robloxCamera(hero), { hud = true, width = 390, height = 844 })
	addScene("phone_round_se", "Small phone 667x375 (touch): in round", O, 300, robloxCamera(hero), { hud = true, width = 667, height = 375 })
	addScene("tablet_round", "Tablet 1024x768 (touch): in round", O, 300, robloxCamera(hero), { hud = true, width = 1024, height = 768 })
	waitFor(function()
		return serverPhase() == "Results"
	end, 400)
	Engine.Advance(1)
	addScene("phone_results", "Phone 844x390 (touch): end of round", L, 120, robloxCamera(hero), { hud = true, width = 844, height = 390 })
end

if group == "rescue" or group == "rescue_mobile" then
	-- Tranche verticale (map imposée en argument, The Canyon) : contours d'équipe,
	-- zone sûre, coéquipier à terre, portage, joueur à terre. Les bots sont figés
	-- le temps de la mise en scène ; tout le reste est le vrai code du jeu.
	local O = Config.World.MapOrigin
	local id = forcedMap or "map"
	closeHelp()
	waitFor(function()
		return hero:GetAttribute("Team") ~= nil and serverPhase() == "Round"
	end, 120)
	Engine.Advance(3)
	local srv = {}
	Engine.Run("server", function()
		local services = World.game.ServerScriptService.Server.Services
		srv.ActorService = World.Require(services.ActorService)
		srv.RescueService = World.Require(services.RescueService)
		srv.SafeZoneService = World.Require(services.SafeZoneService)
		srv.Teams = World.Require(World.game.ReplicatedStorage.Shared.Teams)
	end)
	local me = srv.ActorService.FromPlayer(hero)
	local myTeam = me.Team
	local preyTeam, predatorTeam = srv.Teams.GetPrey(myTeam), srv.Teams.GetPredator(myTeam)
	local pick = {}
	for _, bot in srv.ActorService.GetBots() do
		if bot.Character then
			pick[bot.Team] = pick[bot.Team] or {}
			table.insert(pick[bot.Team], bot)
		end
	end
	local function server(fn)
		Engine.Run("server", fn)
	end
	local function freezeBots()
		server(function()
			for _, bot in srv.ActorService.GetBots() do
				if bot.Character then
					bot.Character:SetAttribute("Frozen", true)
				end
			end
		end)
	end
	local function place(actor, position, lookAt)
		server(function()
			local p = Vector3.new(position.X, O.Y + 3, position.Z)
			local target = lookAt and Vector3.new(lookAt.X, p.Y, lookAt.Z) or (p + Vector3.new(0, 0, -1))
			actor.Character:PivotTo(roblox.CFrame.lookAt(p, target))
		end)
	end
	-- Tout le reste loin de la scène (aucune capture ni portage parasite)
	local function clearStage(keep)
		local i = 0
		for _, bot in srv.ActorService.GetBots() do
			if bot.Character and not keep[bot] then
				i += 1
				place(bot, O + Vector3.new(-150 + (i % 6) * 12, 0, -150 + (i // 6) * 12))
			end
		end
	end
	freezeBots()
	local mate = pick[myTeam] and pick[myTeam][1]
	local mate2 = pick[myTeam] and pick[myTeam][2]
	local hunter = pick[predatorTeam] and pick[predatorTeam][1]
	local prey = pick[preyTeam] and pick[preyTeam][1]
	local base = srv.SafeZoneService.GetBase(myTeam)
	local toCenter = Vector3.new(O.X - base.Center.X, 0, O.Z - base.Center.Z).Unit
	local side = Vector3.new(-toCenter.Z, 0, toCenter.X)
	local w, h = 1280, 720
	if touchDevice then
		w, h = 844, 390
	end
	local suffix = touchDevice and "_phone" or "_pc"

	if not touchDevice then
		-- 1. Contours des trois équipes en plein champ
		local spot = O + Vector3.new(60, 0, -40)
		local forward = Vector3.new(0, 0, 1)
		clearStage({ [mate] = true, [hunter] = true, [prey] = true })
		-- Les trois bots en arc devant le héros : celui du milieu se voit au-dessus
		-- de sa tête, les deux autres de part et d'autre (aucun caché)
		place(me, spot, spot + forward)
		place(mate, spot + forward * 13 - Vector3.new(8, 0, 0), spot)
		place(hunter, spot + forward * 17, spot)
		place(prey, spot + forward * 13 + Vector3.new(8, 0, 0), spot)
		Engine.Advance(0.5)
		addScene(id .. "_outlines" .. suffix, "Intact avatars, glow-only team outlines (FOX orange, CHICKEN yellow, SNAKE green)", O, 300, robloxCamera(hero), { hud = true, width = w, height = h })

		-- 2. Zone sûre du camp : liseré au sol, SAFE pour le défenseur, chasseur dehors
		clearStage({ [mate] = true, [hunter] = true })
		local inZone = base.Center - toCenter * (base.Radius + 8)
		place(me, inZone, O)
		place(mate, base.Center + side * 8 - toCenter * 4, O)
		place(hunter, base.Center + toCenter * (base.Safe.Front + 3), base.Center)
		Engine.Advance(0.6)
		local camPos = base.Center + toCenter * (base.Safe.Front + 26) + side * 14 + Vector3.new(0, 22, 0)
		addScene(id .. "_safe_zone" .. suffix, "Camp safe zone: dashed border and SAFE ZONE on the ground; defenders show SAFE, the hunter outside cannot catch them", O, 300, { position = { camPos.X, camPos.Y, camPos.Z }, target = { base.Center.X, O.Y + 2, base.Center.Z }, fov = 60 }, { hud = true, width = w, height = h })
	end

	-- 3. Coéquipier à terre : marqueur HELP, étiquette DOWN, consigne de portage
	clearStage({ [mate] = true, [hunter] = true })
	local field = O + Vector3.new(50, 0, -20)
	place(mate, field, field + Vector3.new(1, 0, 0))
	place(hunter, field + Vector3.new(30, 0, 18), field)
	server(function()
		srv.RescueService.Down(mate, hunter)
	end)
	-- Le héros à côté du corps, regard parallèle : la caméra voit le corps
	local approach = field + Vector3.new(-4.5, 0, -3)
	place(me, approach, approach + Vector3.new(0.35, 0, 1))
	Engine.Advance(0.6)
	addScene(id .. "_teammate_down" .. suffix, "Teammate down: HELP marker, DOWN tag, carry prompt" .. (touchDevice and " and CARRY button" or " (C) and CARRY medallion"), O, 300, robloxCamera(hero), { hud = true, width = w, height = h })
	if touchDevice then
		addScene(id .. "_teammate_down_portrait", "Teammate down, phone portrait 390x844: CARRY button and status chip", O, 300, robloxCamera(hero), { hud = true, width = 390, height = 844 })
	end

	-- 4. Portage : le corps sur l'épaule, flèche vers le camp
	if touchDevice then
		hero.PlayerGui.HuntOrHideHUD.TouchActions.Carry.Activated:Fire()
	else
		World.PressKey(hero, roblox.Enum.KeyCode.C, true)
		World.PressKey(hero, roblox.Enum.KeyCode.C, false)
	end
	Engine.Advance(0.4)
	server(function()
		local root = me.Character.HumanoidRootPart
		local p = root.Position
		me.Character:PivotTo(roblox.CFrame.lookAt(p, Vector3.new(base.Center.X, p.Y, base.Center.Z)))
	end)
	Engine.Advance(0.3)
	local root = hero.Character.HumanoidRootPart
	local cf = root.CFrame
	addScene(id .. "_carry" .. suffix, "Carrying a teammate home, player camera: status chip, DROP, arrow to the camp", O, 300, robloxCamera(hero), { hud = true, width = w, height = h })
	if not touchDevice then
		-- Vue de profil pour lire la pose : corps à plat ventre sur l'épaule droite
		local side = cf.Position + cf.RightVector * 9 - cf.LookVector * 2 + Vector3.new(0, 2.5, 0)
		addScene(id .. "_carry_side" .. suffix, "Carry pose seen from the side: teammate face down on the right shoulder, head behind", O, 300, { position = { side.X, side.Y, side.Z }, target = { cf.Position.X, cf.Position.Y + 1.2, cf.Position.Z }, fov = 55 }, { hud = true, width = w, height = h })
	end

	if not touchDevice then
		-- 5. Le héros à terre : chrono et consigne, un coéquipier arrive
		if touchDevice == false then
			World.PressKey(hero, roblox.Enum.KeyCode.C, true)
			World.PressKey(hero, roblox.Enum.KeyCode.C, false)
		end
		Engine.Advance(0.3)
		clearStage({ [mate2] = true, [hunter] = true })
		local lie = O + Vector3.new(-40, 0, -50)
		place(me, lie, lie + Vector3.new(0, 0, 1))
		server(function()
			srv.RescueService.Down(me, hunter)
		end)
		if mate2 then
			place(mate2, lie + Vector3.new(9, 0, 7), lie)
		end
		Engine.Advance(3)
		local body = hero.Character.HumanoidRootPart.Position
		addScene(id .. "_you_are_down" .. suffix, "You are down: timer chip and gauge, no action buttons, a teammate comes to carry you", O, 300, { position = { body.X - 4, body.Y + 9, body.Z - 11 }, target = { body.X, body.Y, body.Z + 2 }, fov = 65 }, { hud = true, width = w, height = h })
	end
end

-- Construit une map seule au point d'origine des maps, avec son ambiance
-- (comme RoundService pendant la manche). Retourne la fonction de nettoyage.
local function buildMapAlone(id)
	local mapsFolder = World.game.ServerScriptService.Server.Maps
	local O = Config.World.MapOrigin
	local module = mapsFolder:FindFirstChild(id)
	if not module then
		return nil
	end
	local saved = {}
	local map
	Engine.Run("server", function()
		map = World.Require(module)
		local ctx = {
			Origin = O,
			GetParticipants = function()
				return {}
			end,
			GetTeam = function()
				return nil
			end,
			AddScore = function() end,
			GetScore = function()
				return 0
			end,
			Announce = function() end,
			EndRound = function() end,
			IsRoundActive = function()
				return true
			end,
		}
		map.Build(O, ctx)
		local Lighting = World.game:GetService("Lighting")
		for key, value in map.Lighting or {} do
			if type(value) == "table" then
				local cls = ({ Atmosphere = "Atmosphere", ColorCorrection = "ColorCorrectionEffect", Bloom = "BloomEffect", SunRays = "SunRaysEffect" })[key]
				local target = cls and Lighting:FindFirstChildOfClass(cls)
				if target then
					saved[target] = saved[target] or {}
					for k2, v2 in value do
						saved[target][k2] = target[k2]
						target[k2] = v2
					end
				end
			else
				saved[Lighting] = saved[Lighting] or {}
				saved[Lighting][key] = Lighting[key]
				Lighting[key] = value
			end
		end
	end)
	-- (les clients construisent leurs meshes locaux pendant ce temps)
	Engine.Advance(8)
	return function()
		Engine.Run("server", function()
			map.Cleanup()
			for target, values in saved do
				for k2, v2 in values do
					target[k2] = v2
				end
			end
		end)
	end
end

if group == "all" or group == "maps" then
	local O = Config.World.MapOrigin
	for _, id in { "TheFarm", "TheCarousel", "TheCanyon", "TheSwamp" } do
		local cleanup = buildMapAlone(id)
		if cleanup then
			local size = Config.Maps[id].GroundSize
			addScene("map_" .. id, id .. " - overview", O, size, {
				position = { O.X + size * 0.5, size * 0.42, O.Z + size * 0.62 },
				target = { O.X, 0, O.Z },
				fov = 50,
			})
			addScene("map_" .. id .. "_ground", id .. " - ground level", O, size, {
				position = { O.X - size * 0.12, 9, O.Z + size * 0.3 },
				target = { O.X, 3, O.Z },
				fov = 70,
			})
			addScene("map_" .. id .. "_top", id .. " - top-down", O, size, { position = { O.X, 600, O.Z + 0.01 }, target = { O.X, 0, O.Z }, ortho = size * 1.05, up = { 0, 0, -1 } })
			cleanup()
		end
	end
end

-- Groupe "hero" : cadrages fixes de la carte héroïque, identiques d'une
-- version à l'autre (avant/après au même cadrage). Map : 4e argument
-- (TheCarousel par défaut). Les positions ne dépendent que de l'origine, de la
-- taille de la carte et de l'emplacement des camps.
if group == "hero" then
	local id = forcedMap or "TheCarousel"
	local O = Config.World.MapOrigin
	local cfg = Config.Maps[id]
	local size, r = cfg.GroundSize, cfg.BaseRadius
	local function polar(degrees, radius, y)
		local a = math.rad(degrees)
		return { O.X + math.cos(a) * radius, y, O.Z + math.sin(a) * radius }
	end
	local cleanup = buildMapAlone(id)
	if cleanup then
		-- Vue d'ensemble aérienne de 3/4
		addScene("hero_" .. id .. "_overview", id .. " - aerial 3/4 view", O, size, { position = { O.X + size * 0.5, size * 0.42, O.Z + size * 0.62 }, target = { O.X, 0, O.Z }, fov = 50 })
		-- À hauteur de joueur, depuis l'entrée du camp des renards vers le centre
		addScene("hero_" .. id .. "_from_fox_camp", id .. " - player height, from the FOX camp entrance towards the centre", O, size, { position = polar(90, r - cfg.BasePadSize / 2 - 4, 8), target = polar(90, 0, 4), fov = 70 })
		-- Depuis le centre vers le camp des poules
		addScene("hero_" .. id .. "_to_chicken_camp", id .. " - player height, from the centre towards the CHICKEN camp", O, size, { position = polar(30, 22, 8), target = polar(210, r, 6), fov = 70 })
		-- Entre deux camps (renards et poules), en hauteur, vers le centre
		addScene("hero_" .. id .. "_lane", id .. " - between the FOX and CHICKEN camps, looking at the centre", O, size, { position = polar(128, r * 1.25, 20), target = polar(300, r * 0.15, 0), fov = 60 })
		-- Plan du dessus
		addScene("hero_" .. id .. "_top", id .. " - top-down", O, size, { position = { O.X, 600, O.Z + 0.01 }, target = { O.X, 0, O.Z }, ortho = size * 1.05, up = { 0, 0, -1 } })
		cleanup()
	end
end

if group == "all" or group == "round" then
	-- Une vraie manche simulée : on attend la phase Round
	local t = 0
	while t < 120 do
		Engine.Advance(1)
		t += 1
		local folder = nil
		for _, c in World.workspace:GetChildren() do
			if string.sub(c.Name, 1, 4) == "Map_" then
				folder = c
			end
		end
		if folder and hero:GetAttribute("Team") ~= nil then
			break
		end
	end
	Engine.Advance(20)
	local O = Config.World.MapOrigin
	addScene("round_overview", "A simulated round in progress", O, 300, { position = { O.X + 160, 140, O.Z + 200 }, target = { O.X, 0, O.Z }, fov = 50 })
	addScene("hud_round_pc", "In-round HUD (PC 1280x720)", O, 300, playerCamera(hero, 14, 6), { hud = Export.PlayerGui(hero) })
	addScene("hud_round_phone", "In-round HUD (phone 844x390)", O, 300, playerCamera(hero, 14, 6), { hud = Export.PlayerGui(hero), width = 844, height = 390 })

	-- Gros plan sur les animaux : on aligne un acteur de chaque équipe
	local byTeam = {}
	for _, p in World.game.Players:GetPlayers() do
		local team = p:GetAttribute("Team")
		if team and not byTeam[team] and p ~= hero then
			byTeam[team] = p
		end
	end
	local x = -7
	local spot = O + Vector3.new(0, 3, 40)
	for _, team in { "FOX", "CHICKEN", "SNAKE" } do
		local p = byTeam[team]
		if p and p.Character then
			Engine.Run("server", function()
				p.Character:PivotTo(roblox.CFrame.lookAt(spot + Vector3.new(x, 0, 0), spot + Vector3.new(x, 0, -10)) * roblox.CFrame.Angles(0, math.rad(25), 0))
			end)
		end
		x += 7
	end
	Engine.Run("server", function()
		hero.Character:PivotTo(roblox.CFrame.lookAt(spot + Vector3.new(0, 0, -12), spot))
	end)
	Engine.Advance(0.5)
	addScene("animals_closeup", "Animal looks + outlines seen by " .. tostring(hero:GetAttribute("Team")) .. " (green = prey, red = hunter)", O, 120, {
		position = { spot.X + 2, spot.Y + 4, spot.Z - 14 },
		target = { spot.X, spot.Y + 0.5, spot.Z },
		fov = 50,
	}, { hud = Export.PlayerGui(hero) })
end

if group == "all" or group == "round" or group == "results" then
	-- Écran de résultats (podium) : on attend la fin de la manche
	local t = 0
	while t < 400 do
		Engine.Advance(1)
		t += 1
		local RoundState = World.Require and nil
		local phase = nil
		Engine.Run("server", function()
			phase = World.Require(World.game.ServerScriptService.Server.Services.RoundState).Phase
		end)
		if phase == "Results" then
			break
		end
	end
	Engine.Advance(1)
	local L = Config.World.LobbyOrigin
	addScene("hud_results_pc", "End of round: podium, coins and XP (PC 1280x720)", L, 120, playerCamera(hero, 14, 6), { hud = Export.PlayerGui(hero) })
	addScene("hud_results_phone", "End of round on a phone (844x390)", L, 120, playerCamera(hero, 14, 6), { hud = Export.PlayerGui(hero), width = 844, height = 390 })
end

fs.writeFile(outPath, serde.encode("json", scenes))
print("errors:", #Engine.Errors, "warnings:", #World.Warnings)
for _, e in Engine.Errors do
	print(e)
end
process.exit(#Engine.Errors > 0 and 1 or 0)

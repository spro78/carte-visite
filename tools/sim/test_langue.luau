--!nocheck
--[[
	test_langue.luau : version française (langue par défaut, Config.Language).
	Joue une manche sur Carousel Valley en français, avec le vrai code serveur
	et client, et vérifie :
	  - lobby : menus, vote (modes, carte, voix, joueurs), aide des nouveaux
	    joueurs (règle, rôle de chaque équipe, commandes), panneau du lobby ;
	  - manche : noms d'équipes, composition, ruban de rôle, ligne d'objectif,
	    marquages ZONE SÛRE et CAMP, pastille de zone sûre, coéquipier à terre
	    (consigne, étiquette, marqueur SOS), portage, fil des captures,
	    résultats et récompenses ;
	  - aucun texte affiché resté en anglais (mots anglais courants), aucun
	    texte demandé sans traduction (Lang.Missing, serveur et client) ;
	  - HUD sans chevauchement sur 4 écrans de PC et un téléphone, et textes
	    sur une ligne assez grands pour être lus (estimation : la police réelle
	    n'est pas simulée).
	Ne remplace pas un test dans Roblox Studio (police, accents, rendu réel).
]]
local H = require("./harness")
local Layout = require("./layout")
local World, Engine = H.World, H.Engine
World.Shared.HoH_Language = nil -- langue du jeu (Config.Language = "fr")
local roblox = H.Roblox
local Vector2, Vector3 = roblox.Vector2, roblox.Vector3
local check, section = H.check, H.section

local server = H.boot(function(Config)
	Config.Debug.ForceMap = "TheCarousel"
	Config.Debug.ForceMode = "Chase"
	Config.Debug.DisableBots = true
	Config.Debug.FastRounds = true
end)
local Config = server.Config
local O = Config.World.MapOrigin
local MapBase = H.require(World.game.ServerScriptService.Server.Maps.MapBase)
local LangPath = World.game.ReplicatedStorage.Shared.Lang

local alice = World.AddPlayer("Alice", { client = true })
local players = { Alice = alice }
for _, name in { "Bob", "Carl", "Dana", "Eve", "Finn" } do
	players[name] = World.AddPlayer(name)
end
local function actor(name)
	return server.ActorService.FromPlayer(players[name])
end
local function char(name)
	return players[name].Character
end
local function hud()
	return alice.PlayerGui:FindFirstChild("HuntOrHideHUD")
end
local function status()
	local pill = hud():FindFirstChild("Status")
	local label = pill and pill:FindFirstChild("Text")
	return pill and pill.Visible and label and label.Text or nil
end

-- ---------------------------------------------------------------------------
-- Textes affichés et mots anglais
-- ---------------------------------------------------------------------------
local GUI_CLASSES = { Frame = true, TextLabel = true, TextButton = true, TextBox = true, ImageLabel = true, ImageButton = true, ScrollingFrame = true, CanvasGroup = true }
local TEXT_CLASSES = { TextLabel = true, TextButton = true, TextBox = true }
local function shown(gui)
	local node = gui
	while node do
		local class = node.ClassName
		if class == "ScreenGui" or class == "BillboardGui" or class == "SurfaceGui" then
			return node.Enabled ~= false
		end
		if GUI_CLASSES[class] and node.Visible == false then
			return false
		end
		node = node.Parent
	end
	return true
end
local function plain(text)
	return (string.gsub(text, "<[^>]+>", ""))
end

-- Mots qui n'existent qu'en anglais dans les textes du jeu
local ENGLISH = {}
for _, word in {
	"the", "you", "your", "you're", "catch", "catches", "caught", "carry", "carrying", "carried", "round", "waiting",
	"player", "players", "coins", "level", "shop", "spin", "help", "win", "wins", "won", "team", "next", "soon",
	"safe", "down", "saved", "joined", "nobody", "home", "egg", "eggs", "objective", "draw", "back", "loading",
	"daily", "practice", "who", "hats", "trails", "equip", "buy", "owned", "need", "more", "free", "unlocked",
	"hunter", "prey", "fox", "foxes", "chicken", "chickens", "snake", "snakes", "ability", "dash", "drop", "go",
	"ready", "longest", "run", "time's", "teammate", "hold", "base", "tap", "press", "avoid", "everyone", "voted",
	"first", "last", "standing", "points!", "flying", "horses", "valley", "chase", "carousel",
} do
	ENGLISH[word] = true
end
local function englishWords(text)
	local found = {}
	for word in string.gmatch(string.lower(plain(text)), "[%a']+") do
		if ENGLISH[word] then
			table.insert(found, word)
		end
	end
	return found
end

local offenders = {}
local seen = {}
local function scan(moment)
	local roots = { alice.PlayerGui, World.workspace }
	for _, rootInst in roots do
		for _, d in rootInst:GetDescendants() do
			if TEXT_CLASSES[d.ClassName] and d.Text ~= "" and shown(d) then
				local words = englishWords(d.Text)
				if #words > 0 then
					local key = d.Text
					if not seen[key] then
						seen[key] = true
						table.insert(offenders, string.format("[%s] %s : « %s » (%s)", moment, d.Name, plain(d.Text), table.concat(words, ", ")))
					end
				end
			end
		end
	end
end

-- Taille estimée d'un texte sur une ligne (TextScaled) : la plus grande taille
-- qui tient dans le cadre, plafonnée par UITextSizeConstraint
local function estimatedSize(label, rect)
	local text = plain(label.Text)
	local length = utf8.len(text) or #text
	if length == 0 then
		return nil
	end
	local size = math.min(rect.H, rect.W / (length * 0.55))
	local constraint = label:FindFirstChildOfClass("UITextSizeConstraint")
	if constraint then
		size = math.min(size, constraint.MaxTextSize)
	end
	return size
end
local function smallTexts(viewport, minimum)
	local small = {}
	local rects = Layout.Rects(hud(), viewport)
	for gui, rect in rects do
		if gui.ClassName == "TextLabel" and rect.Visible and gui.Text ~= "" and not gui.TextWrapped and not string.find(gui.Text, "\n", 1, true) and rect.W > 0 then
			local size = estimatedSize(gui, rect)
			if size and size < minimum then
				table.insert(small, string.format("%s « %s » %.1f px", gui.Name, plain(gui.Text), size))
			end
		end
	end
	return small
end

local function checkLayout(label)
	local camera = World.workspace.CurrentCamera
	local saved = camera.ViewportSize
	for _, size in { { 1280, 720 }, { 1366, 768 }, { 1440, 900 }, { 1920, 1080 }, { 844, 390 } } do
		local viewport = Vector2.new(size[1], size[2])
		camera.ViewportSize = viewport
		local problems, count = Layout.HudProblems(hud(), viewport)
		check(#problems == 0, string.format("HUD %s %dx%d : %d blocs sans chevauchement", label, size[1], size[2], count) .. (#problems > 0 and ("\n      " .. table.concat(problems, "\n      ")) or ""))
		local phone = size[2] < 500
		local small = smallTexts(viewport, phone and 9 or 11)
		check(#small == 0, string.format("HUD %s %dx%d : textes d'une ligne lisibles (%s px au moins)", label, size[1], size[2], phone and "9" or "11") .. (#small > 0 and ("\n      " .. table.concat(small, "\n      ")) or ""))
	end
	camera.ViewportSize = saved
end

local function worldText(text)
	for _, d in World.workspace:GetDescendants() do
		if TEXT_CLASSES[d.ClassName] and d.Text == text then
			return d
		end
	end
	return nil
end

-- ---------------------------------------------------------------------------
section("Lobby en français")
check(H.advanceUntil(function()
	return H.phase() == "Intermission" and hud() ~= nil and hud().VotePanel.Visible
end, 30), "vote ouvert")
Engine.Advance(1)
local h = hud()
check(h.Pills.SHOP.Label.Text == "BOUTIQUE" and h.Pills.SPIN.Label.Text == "ROUE" and h.Pills.HELP.Label.Text == "AIDE", "menus : BOUTIQUE, ROUE, AIDE")
check(h.VotePanel.VoteTitle.Text == "VOTE POUR LE PROCHAIN MODE", "titre du vote : " .. h.VotePanel.VoteTitle.Text)
local modeNames = {}
local cardsOk = true
for i = 1, 3 do
	local card = h.VotePanel.Cards["Vote" .. i]
	modeNames[card.ModeName.Text] = true
	if card.MapName.Text ~= "sur Vallée du Manège" or not string.find(card.Votes.Text, "vote", 1, true) then
		cardsOk = false
	end
end
check(modeNames["POURSUITE"] and modeNames["COURSE AUX ŒUFS"] and modeNames["MANÈGE"], "cartes de vote : POURSUITE, COURSE AUX ŒUFS, MANÈGE")
check(cardsOk, "chaque carte : « sur Vallée du Manège » et le nombre de voix")
check(string.find(h.VotePanel.Roster.Text, "6 joueurs", 1, true) ~= nil and string.find(h.VotePanel.Roster.Text, "on attend", 1, true) ~= nil, "liste des joueurs : " .. plain(h.VotePanel.Roster.Text))
check(h.TopCenter.Main.Text == "Vote pour le prochain mode !", "ruban : " .. h.TopCenter.Main.Text)
local help = h.Help
local rules = help.Rules.Text
check(help.Visible, "l'aide s'ouvre pour un nouveau joueur")
check(string.find(rules, "Attrape ta proie", 1, true) and string.find(rules, "Le RENARD attrape la POULE, la POULE attrape la VIPÈRE, la VIPÈRE attrape le RENARD", 1, true)
	and string.find(rules, "ZONE SÛRE", 1, true) and string.find(rules, "C : porter un coéquipier", 1, true), "aide : règle, rôle de chaque équipe, zone sûre et commandes")
check(worldText("POULE, POULE, RENARD, VIPÈRE") ~= nil, "panneau du lobby : POULE, POULE, RENARD, VIPÈRE")
check(worldText("QUI ATTRAPE QUI ?") ~= nil, "panneau « QUI ATTRAPE QUI ? »")
scan("lobby")
checkLayout("lobby")
help.Visible = false

-- ---------------------------------------------------------------------------
section("Composition des équipes et début de manche")
check(H.advanceUntil(function()
	return H.phase() == "Countdown"
end, 40), "décompte")
H.onServer(function()
	for name, team in { Alice = "FOX", Bob = "FOX", Carl = "SNAKE", Dana = "SNAKE", Eve = "CHICKEN", Finn = "CHICKEN" } do
		server.TeamService.SetTeam(actor(name), team)
	end
end)
Engine.Advance(1.2)
h = hud()
local chips = {}
for _, teamId in { "FOX", "CHICKEN", "SNAKE" } do
	local label = h.Teams[teamId].Chip:FindFirstChildOfClass("TextLabel")
	chips[teamId] = label and label.Text
end
check(chips.FOX == "RENARD" and chips.CHICKEN == "POULE" and chips.SNAKE == "VIPÈRE", string.format("tableau des équipes : %s, %s, %s", tostring(chips.FOX), tostring(chips.CHICKEN), tostring(chips.SNAKE)))
check(string.find(h.Lineup.FOX.TeamName.Text, "RENARDS", 1, true) ~= nil and string.find(h.Lineup.FOX.Names.Text, "Alice (toi)", 1, true) ~= nil, "composition : " .. plain(h.Lineup.FOX.TeamName.Text) .. " / " .. plain(h.Lineup.FOX.Names.Text))
local ribbon = plain(h.TopCenter.Main.Text)
check(ribbon == "RENARD  ·  attrape les POULES  ·  fuis les VIPÈRES", "ruban de rôle : " .. ribbon)
check(string.find(h.TopCenter.Sub.Text, "POURSUITE", 1, true) ~= nil, "ligne d'objectif : " .. h.TopCenter.Sub.Text)
scan("décompte")
checkLayout("décompte")
check(H.advanceUntil(function()
	return H.phase() == "Round"
end, 15), "manche lancée")
Engine.Advance(3)

-- ---------------------------------------------------------------------------
section("Marquages au sol et zone sûre")
local safeLabels, campSigns = 0, 0
for _, d in World.workspace:GetDescendants() do
	if TEXT_CLASSES[d.ClassName] then
		if d.Text == "ZONE SÛRE" then
			safeLabels += 1
		elseif d.Text == "CAMP RENARD" or d.Text == "CAMP POULE" or d.Text == "CAMP VIPÈRE" then
			campSigns += 1
		end
	end
end
check(safeLabels == 3, "« ZONE SÛRE » au sol des trois camps (" .. safeLabels .. ")")
check(campSigns >= 3, "panneaux CAMP RENARD / POULE / VIPÈRE (" .. campSigns .. ")")
local function zonePoint(team, x, z)
	local base = MapBase.ActiveBases[team]
	return base.CFrame:PointToWorldSpace(Vector3.new(x, 0, z)) + Vector3.new(0, 3, 0)
end
H.teleport(actor("Alice"), zonePoint("FOX", 0, 4))
H.teleport(actor("Bob"), zonePoint("FOX", 6, 4))
Engine.Advance(0.6)
check(status() == "ZONE SÛRE · personne ne peut t'attraper ici", "pastille : " .. tostring(status()))
local badge = char("Bob").Head:FindFirstChild("HoH_TeamBadge")
local badgeText = badge and badge.Row.Team.Text
check(badgeText == "À L'ABRI", "étiquette au-dessus de Bob (vue par Alice) : " .. tostring(badgeText))

-- ---------------------------------------------------------------------------
section("Coéquipier à terre, portage, fil des captures")
local OPEN = O + Vector3.new(60, 3, -40)
-- Hors de la zone depuis plus que le délai de grâce (Config.SafeZone.ExitGraceSeconds)
H.teleport(actor("Alice"), O + Vector3.new(-140, 3, -140))
H.teleport(actor("Bob"), OPEN)
Engine.Advance(Config.SafeZone.ExitGraceSeconds + 0.5)
H.teleport(actor("Carl"), char("Bob").HumanoidRootPart.Position + Vector3.new(2, 0, 0))
Engine.Advance(0.3)
H.teleport(actor("Carl"), O + Vector3.new(-140, 3, 60))
check(char("Bob"):GetAttribute("Downed") == true, "Bob est à terre")
H.teleport(actor("Alice"), OPEN + Vector3.new(30, 0, 0))
Engine.Advance(0.4)
local text = status()
check(text ~= nil and string.find(text, "Bob est à terre", 1, true) ~= nil and string.find(text, "à porter au camp", 1, true) ~= nil, "consigne : " .. tostring(text))
local bobBadge = char("Bob").Head:FindFirstChild("HoH_TeamBadge")
check(bobBadge and bobBadge.Row.Team.Text == "À TERRE", "étiquette de Bob : " .. tostring(bobBadge and bobBadge.Row.Team.Text))
local marker = char("Bob").Head:FindFirstChild("HoH_Help")
local markerText = marker and marker.Pill:FindFirstChild("Text")
check(markerText and string.sub(plain(markerText.Text), 1, 3) == "SOS", "marqueur : " .. tostring(markerText and plain(markerText.Text)))
H.teleport(actor("Alice"), char("Bob").HumanoidRootPart.Position + Vector3.new(4, 2.1, 0))
Engine.Advance(0.4)
text = status()
check(text == "Appuie sur C pour porter Bob", "à portée : " .. tostring(text))
local carryDock = hud().BottomCenter:FindFirstChild("Carry")
check(carryDock and carryDock.Medallion.Main.Text == "PORTER", "médaillon : " .. tostring(carryDock and carryDock.Medallion.Main.Text))
local feedText = ""
for _, line in hud().KillFeed:GetChildren() do
	local label = line:FindFirstChild("Text")
	if label then
		feedText ..= plain(label.Text) .. " | "
	end
end
check(string.find(feedText, "Carl", 1, true) and string.find(feedText, "Bob", 1, true), "fil : " .. feedText)
scan("à terre")
checkLayout("coéquipier à terre")
-- Personne ne vient : Bob rejoint les VIPÈRES au bout du chrono
H.teleport(actor("Alice"), O + Vector3.new(-140, 3, -140))
Engine.Advance(Config.Rescue.BleedOutSeconds + 1)
feedText = ""
for _, line in hud().KillFeed:GetChildren() do
	local label = line:FindFirstChild("Text")
	if label then
		feedText ..= plain(label.Text) .. " | "
	end
end
check(string.find(feedText, "Bob  rejoint les  VIPÈRES", 1, true) ~= nil, "fil : « Bob rejoint les VIPÈRES » (" .. feedText .. ")")
scan("manche")

-- ---------------------------------------------------------------------------
section("Résultats")
check(H.advanceUntil(function()
	return H.phase() == "Results"
end, 120, 1), "fin de manche")
Engine.Advance(1)
local results = hud().Results
local title = results.Banner.Title.Text
local reason = results.Banner.Reason.Text
check(string.sub(title, 1, 13) == "VICTOIRE DES " or title == "ÉGALITÉ !", "titre : " .. title)
check(string.find(reason, "Temps écoulé", 1, true) ~= nil or string.find(reason, "Les ", 1, true) ~= nil, "raison : " .. reason)
local awards = {}
for _, card in results.Awards:GetChildren() do
	if card:IsA("Frame") then
		for _, child in card:GetChildren() do
			if child.ClassName == "TextLabel" and child.Text ~= "" then
				awards[child.Text] = true
			end
		end
	end
end
check(awards["STAR DE LA MANCHE"] and awards["MEILLEUR SURVIVANT"] and awards["MEILLEUR CHASSEUR"], "distinctions : STAR DE LA MANCHE, MEILLEUR SURVIVANT, MEILLEUR CHASSEUR")
scan("résultats")
checkLayout("résultats")

-- ---------------------------------------------------------------------------
section("Aucun texte resté en anglais")
check(#offenders == 0, "textes affichés sans mot anglais" .. (#offenders > 0 and ("\n      " .. table.concat(offenders, "\n      ")) or ""))
local missingServer = {}
for key in H.require(LangPath).Missing do
	table.insert(missingServer, key)
end
local missingClient = {}
Engine.Run(alice, function()
	for key in World.Require(LangPath).Missing do
		table.insert(missingClient, key)
	end
end)
check(#missingServer == 0, "serveur : tout texte demandé est traduit" .. (#missingServer > 0 and (" (manque : " .. table.concat(missingServer, " | ") .. ")") or ""))
check(#missingClient == 0, "client : tout texte demandé est traduit" .. (#missingClient > 0 and (" (manque : " .. table.concat(missingClient, " | ") .. ")") or ""))

H.finish()

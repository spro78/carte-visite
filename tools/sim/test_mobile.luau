--!nocheck
--[[
	test_mobile.luau : appareil tactile simulé (téléphone et tablette, sans clavier).
	Vérifie, avec le vrai code client :
	  - que les boutons tactiles apparaissent et que les indications clavier disparaissent ;
	  - qu'aucun bouton ne recouvre le bouton de saut de Roblox (géométrie du module
	    TouchJump), ne sort de l'écran ni ne descend sous 44 px (cible tactile minimale) ;
	  - que les blocs de l'interface ne se chevauchent pas ;
	  - qu'un appui sur chaque bouton envoie la bonne intention et que le SERVEUR l'applique
	    (dash, capacité, vote).
	Ce qui reste hors de portée : le rendu réel des contrôles Roblox (joystick, saut),
	les encoches (zones sûres) et la sensation au doigt sur un vrai appareil.
]]
local H = require("./harness")
local Layout = require("./layout")
local World, Engine = H.World, H.Engine
local Vector2, Vector3 = H.Roblox.Vector2, H.Roblox.Vector3
local check, section = H.check, H.section

-- Appareil tactile : pas de clavier ni de souris
World.Input.TouchEnabled = true
World.Input.KeyboardEnabled = false
World.Input.MouseEnabled = false

local server = H.boot(function(Config)
	Config.Debug.ForceMap = "TheFarm"
end)

local camera = World.workspace.CurrentCamera
local function setScreen(w, h)
	camera.ViewportSize = Vector2.new(w, h)
	Engine.Advance(0.1)
end

-- Bouton de saut de Roblox (PlayerModule > TouchJump), en pixels
local function robloxJump(viewport)
	local small = math.min(viewport.X, viewport.Y) <= 500
	local size = small and 70 or 120
	local x = viewport.X - (size * 1.5 - 10)
	local y = viewport.Y - (small and (size + 20) or (size * 1.75))
	return { X = x, Y = y, W = size, H = size }
end

setScreen(844, 390)
local tess = World.AddPlayer("Tess", { client = true })
Engine.Advance(3)
local hud = tess.PlayerGui:WaitForChild("HuntOrHideHUD")
local touch = hud:FindFirstChild("TouchActions")

local ACTIONS = { "DashLeft", "DashRight", "Stop", "Ability" }

local function checkNoOverlap(label, viewport)
	local problems, count, rects = Layout.HudProblems(hud, viewport)
	check(#problems == 0, label .. " : " .. count .. " blocs, aucun chevauchement" .. (#problems > 0 and ("\n      " .. table.concat(problems, "\n      ")) or ""))
	return rects
end

-- ---------------------------------------------------------------------------
section("Lobby sur téléphone (844x390, tactile)")
check(H.advanceUntil(function()
	return H.phase() == "Intermission"
end, 40), "intermission (vote)")
Engine.Advance(1)
local viewport = Vector2.new(844, 390)
local rects = checkNoOverlap("lobby téléphone", viewport)
local voteButton = hud.VotePanel:FindFirstChild("Vote1", true)
check(voteButton and rects[voteButton] and rects[voteButton].Visible, "les cartes de vote sont affichées")
check(voteButton and rects[voteButton].H >= 44, string.format("carte de vote assez grande pour le doigt (%d px)", voteButton and math.floor(rects[voteButton].H) or 0))
local help = hud:FindFirstChild("Help")
local rules = help and help:FindFirstChild("Rules")
check(rules and not string.find(rules.Text, "Q / E", 1, true) and string.find(rules.Text, "DASH buttons", 1, true) ~= nil, "les règles expliquent les boutons tactiles, pas les touches")
-- Appui sur la première carte de vote : le serveur compte le vote
local VoteService = H.require(World.game.ServerScriptService.Server.Services.VoteService)
local candidates = VoteService.GetCandidates()
voteButton.Activated:Fire()
Engine.Advance(0.2)
check(VoteService.GetPlayerVote(tess) == candidates[1], "un appui sur la carte de vote est compté par le serveur (" .. tostring(candidates[1]) .. ")")
local touchVisibleInLobby = false
for _, action in ACTIONS do
	local button = touch and touch:FindFirstChild(action)
	if button and rects[button] and rects[button].Visible then
		touchVisibleInLobby = true
	end
end
check(not touchVisibleInLobby, "pas de boutons d'action au lobby")

-- ---------------------------------------------------------------------------
section("Manche sur téléphone (844x390, tactile)")
check(H.advanceUntil(function()
	return H.phase() == "Round" and tess:GetAttribute("Team") ~= nil and tess.Character ~= nil
end, 60), "Tess joue une manche")
Engine.Advance(3.5) -- fin de la protection d'apparition
-- Une annonce de la map pendant la poursuite
H.onServer(function()
	World.Require(World.game.ReplicatedStorage.Shared.Remotes).Get("Announce"):FireAllClients("The egg went back to the CHICKENS!", H.Roblox.Color3.fromRGB(255, 220, 40))
end)
Engine.Advance(0.3)

local function checkTouchScreen(w, h)
	setScreen(w, h)
	local vp = Vector2.new(w, h)
	local r = checkNoOverlap(string.format("manche %dx%d", w, h), vp)
	local jump = robloxJump(vp)
	for _, action in ACTIONS do
		local button = touch and touch:FindFirstChild(action)
		local rect = button and r[button]
		local ok = rect ~= nil and rect.Visible
		check(ok, string.format("[%dx%d] bouton %s affiché", w, h, action))
		if ok then
			check(rect.W >= 44 and rect.H >= 44, string.format("[%dx%d] %s : %d px (44 px minimum)", w, h, action, math.floor(rect.W)))
			check(Layout.Inside(rect, vp, 0), string.format("[%dx%d] %s dans l'écran %s", w, h, action, Layout.Describe(rect)))
			check(Layout.Overlap(rect, jump) == 0, string.format("[%dx%d] %s ne couvre pas le saut Roblox %s", w, h, action, Layout.Describe(jump)))
		end
	end
	return r
end

local r = checkTouchScreen(844, 390) -- iPhone 14
checkTouchScreen(667, 375) -- iPhone SE
checkTouchScreen(800, 360) -- Android courant
checkTouchScreen(1024, 768) -- iPad
setScreen(844, 390)
r = Layout.Rects(hud, viewport)

local announce = hud.Announce
check(r[announce] and r[announce].Visible, "l'annonce est affichée")
if r[announce] then
	local a = r[announce]
	check(a.Y + a.H <= viewport.Y * 0.42, string.format("l'annonce reste dans le haut de l'écran (bas à %d px sur 390)", math.floor(a.Y + a.H)))
	check(a.W <= viewport.X * 0.4, string.format("l'annonce est une pastille étroite (%d px sur 844)", math.floor(a.W)))
end
check(not (r[hud.BottomCenter] and r[hud.BottomCenter].Visible), "pas de carte « R » en tactile")
local dashBar = hud:FindFirstChild("DashBar")
check(not (dashBar and r[dashBar] and r[dashBar].Visible), "pas de barre « Q / E » en tactile")
check(not (r[hud.Currency] and r[hud.Currency].Visible), "coin bas-gauche libre pour le joystick pendant la manche")

-- ---------------------------------------------------------------------------
section("Appuis sur les boutons tactiles -> serveur")
local char = tess.Character
World.SetMoveVector(tess, Vector3.new(0, 0, -1))
Engine.Advance(1)
local dashCalls = Engine.RemoteCalls["RequestDash:FireServer"] or 0
touch.DashLeft.Activated:Fire()
Engine.Advance(0.1)
check((Engine.RemoteCalls["RequestDash:FireServer"] or 0) == dashCalls + 1, "◀ DASH envoie une intention de dash")
check(type(char:GetAttribute("DashReadyAt")) == "number", "le serveur a validé le dash (DashReadyAt)")
Engine.Advance(0.2)
-- Recharge visible sur le bouton
local seconds = nil
for _, d in touch.DashLeft:GetDescendants() do
	if d:IsA("TextLabel") and d.Visible and tonumber(d.Text) then
		seconds = d.Text
	end
end
check(seconds ~= nil, "le bouton affiche la recharge (" .. tostring(seconds) .. " s)")

touch.Ability.Activated:Fire()
Engine.Advance(0.1)
check(type(char:GetAttribute("AbilityReadyAt")) == "number", "ABILITY : le serveur a validé la capacité (AbilityReadyAt)")

Engine.Advance(1.5)
local root = char.HumanoidRootPart
local hum = char:FindFirstChildOfClass("Humanoid")
local before = hum.WalkSpeed
touch:FindFirstChild("Stop").Activated:Fire()
Engine.Advance(1 / 30)
check(before > 5 and hum.WalkSpeed < 3, string.format("STOP : arrêt net (%.1f -> %.1f)", before, hum.WalkSpeed))
World.SetMoveVector(tess, Vector3.zero)
local _ = root

-- ---------------------------------------------------------------------------
section("Fin de manche sur téléphone")
check(H.advanceUntil(function()
	return H.phase() == "Results"
end, 400, 1), "écran de résultats")
Engine.Advance(1)
r = checkNoOverlap("résultats téléphone", viewport)
local anyTouch = false
for _, action in ACTIONS do
	if r[touch[action]] and r[touch[action]].Visible then
		anyTouch = true
	end
end
check(not anyTouch, "pas de boutons d'action sur les résultats")

H.finish()

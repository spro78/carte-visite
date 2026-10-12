--!nocheck
--[[
	test_kit.luau : affichage du kit 3D quand la mémoire des meshes manque.
	Reproduit la panne vue dans Roblox Studio : « Failed to create empty
	EditableMesh ... memory budget », puis des blocs géants à la place des
	meshes (paroi brune au spawn, grandes surfaces vertes). Le simulateur
	refuse, comme Roblox, de créer un EditableMesh au-delà d'un budget.
	Vérifie, avec le vrai code serveur et client :
	  - aucune erreur d'exécution, une seule alerte claire dans la sortie ;
	  - l'essentiel est construit d'abord (camps, objectifs, manège, sol,
	    repères), le décor lointain en dernier ;
	  - un asset sans meshes n'est jamais remplacé par un bloc de sa taille :
	    seuls ses volumes de collision deviennent visibles (plus une boule de
	    feuillage pour les arbres).
	(Avec assez de mémoire, tout est en meshes : test_carousel le vérifie.)
	Ne remplace pas un test dans Roblox Studio : le budget réel dépend de
	l'appareil.
]]
local H = require("./harness")
local World, Engine = H.World, H.Engine
local check, section = H.check, H.section

local BUDGET = 80 -- meshes vivants autorisés (le PC de Malcolm en a construit une centaine)

local server = H.boot(function(Config)
	Config.Debug.DisableBots = true
	Config.Debug.ForceMap = "TheCarousel"
	Config.Debug.ForceMode = "Chase"
	Config.Debug.FastRounds = true
end)
local Manifest = H.require(World.game.ReplicatedStorage.Shared.Kit.Manifest)

World.EditableBudget = BUDGET
local alice = World.AddPlayer("Alice", { client = true })
World.AddPlayer("Bob", {})

local function controller(player)
	local result
	Engine.Run(player, function()
		result = World.Require(player.PlayerScripts.Client.Controllers.KitController)
	end)
	return result
end

local function mapFolder()
	return World.game.Workspace:FindFirstChild("Map_TheCarousel")
end

local function kitModels()
	local models = {}
	local folder = mapFolder()
	if folder then
		for _, d in folder:GetDescendants() do
			if d.ClassName == "Model" and d:GetAttribute("KitAsset") then
				table.insert(models, d)
			end
		end
	end
	return models
end

-- Attendre la carte, puis que le client ait tout traité
section("Carte construite avec un budget de " .. BUDGET .. " meshes")
local built = H.advanceUntil(function()
	return mapFolder() ~= nil
end, 120)
check(built, "Carousel Valley construite")
local kc = controller(alice)
local total = #kitModels()
local done = H.advanceUntil(function()
	local stats = kc.GetStats()
	return stats.Assets + stats.Simplified >= total
end, 60)
local stats = kc.GetStats()
check(done, string.format("le client a traité les %d assets (%d en meshes, %d simplifiés)", total, stats.Assets, stats.Simplified))
check(World.EditableRefused > 0 and stats.Simplified > 0, string.format("le budget est bien atteint (%d créations refusées)", World.EditableRefused))
check(World.EditableLive <= BUDGET, string.format("jamais plus de %d meshes vivants (%d)", BUDGET, World.EditableLive))

section("Pas d'erreur, une seule alerte")
check(#Engine.Errors == 0, "aucune erreur d'exécution (" .. #Engine.Errors .. ")")
local budgetWarnings = 0
for _, w in World.Warnings do
	if string.find(w, "Limite mémoire des meshes", 1, true) then
		budgetWarnings += 1
	end
end
check(budgetWarnings == 1, "une seule alerte « limite mémoire » dans la sortie (" .. budgetWarnings .. ")")
local summary = false
for _, line in World.Prints do
	if string.find(line, "[Kit] Décors affichés par ce joueur", 1, true) then
		summary = true
	end
end
check(summary, "bilan des décors affichés écrit dans la sortie")

section("L'essentiel d'abord")
local function hasMeshes(model)
	for _, child in model:GetChildren() do
		if child.ClassName == "MeshPart" and child:GetAttribute("KitLocal") then
			return true
		end
	end
	return false
end
local essentials = { CampPad = true, CampGate = true, CampFlag = true, FoxDen = true, ChickenCoop = true, SnakeHollow = true, CarouselArm = true, CarouselHub = true, ValleyGround = true }
local missingEssentials = {}
local hillsBuilt = 0
for _, model in kitModels() do
	local asset = model:GetAttribute("KitAsset")
	if essentials[asset] and not hasMeshes(model) then
		missingEssentials[asset] = true
	end
	if string.sub(asset, 1, 11) == "ValleyHills" and hasMeshes(model) then
		hillsBuilt += 1
	end
end
local missingList = {}
for asset in missingEssentials do
	table.insert(missingList, asset)
end
check(#missingList == 0, "camps, manège et sol affichés en meshes" .. (#missingList > 0 and (" (manquants : " .. table.concat(missingList, ", ") .. ")") or ""))
check(hillsBuilt == 0, "les collines lointaines passent en dernier (" .. hillsBuilt .. " construites)")

section("Jamais de bloc géant à la place d'un mesh")
local blocks, hiddenColliders, ballsTooBig = {}, 0, 0
for _, model in kitModels() do
	local def = Manifest[model:GetAttribute("KitAsset")]
	local simplified = not hasMeshes(model)
	for _, child in model:GetChildren() do
		if child:GetAttribute("KitLocal") and child.ClassName ~= "MeshPart" then
			if not child:GetAttribute("KitSimplified") then
				table.insert(blocks, model.Name)
			elseif child.Size.X > 16 then
				ballsTooBig += 1
			end
		end
		if simplified and child.Name == "KitCollider" and child.Transparency > 0.5 then
			hiddenColliders += 1
		end
	end
	if simplified and def and #def.Colliders == 0 then
		-- rien à montrer : aucun bloc ne doit avoir été posé
		for _, child in model:GetChildren() do
			if child:GetAttribute("KitLocal") and not child:GetAttribute("KitSimplified") then
				table.insert(blocks, model.Name)
			end
		end
	end
end
check(#blocks == 0, "aucun bloc de remplacement de la taille d'une pièce" .. (#blocks > 0 and (" (" .. table.concat(blocks, ", ", 1, math.min(#blocks, 5)) .. ")") or ""))
check(hiddenColliders == 0, "les obstacles des décors simplifiés restent visibles (pas de mur invisible)")
check(ballsTooBig == 0, "feuillages simplifiés de taille raisonnable")

H.finish()

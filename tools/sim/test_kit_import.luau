--!nocheck
--[[
	test_kit_import.luau : kit 3D importé dans Studio (vrais meshes Roblox).
	Après « Import 3D » de assets/kit/HoH_Kit.fbx, Studio dépose un modèle
	« HoH_Kit » dans Workspace, rempli de MeshParts nommés Asset__Pièce.
	Vérifie, avec le vrai code serveur et client :
	  - le serveur le trouve sans qu'on le renomme, le range dans ServerStorage
	    (il disparaît du monde) et écrit le bilan dans la sortie ;
	  - la carte est posée avec des copies de ces MeshParts, aux bonnes
	    tailles, sans collision (les collisions restent les volumes simples) ;
	  - aucun joueur ne construit de mesh lui-même (aucun EditableMesh, donc
	    aucun budget mémoire en jeu).
	Ne remplace pas un test dans Roblox Studio (axes et échelle de l'import).
]]
local H = require("./harness")
local World, Engine = H.World, H.Engine
local check, section = H.check, H.section
local Instance = Engine.Instance

local pieceCount = 0
local server = H.boot(function(Config)
	Config.Debug.DisableBots = true
	Config.Debug.ForceMap = "TheCarousel"
	Config.Debug.ForceMode = "Chase"
	Config.Debug.FastRounds = true
	-- Ce que l'import de Studio dépose dans Workspace
	local Manifest = World.Require(World.game.ReplicatedStorage.Shared.Kit.Manifest)
	local import = Instance.new("Model")
	import.Name = "HoH_Kit"
	for _, def in Manifest do
		for _, piece in def.Pieces do
			local part = Instance.new("MeshPart")
			part.Name = piece.Mesh
			part.Size = piece.Size * 0.28 -- unité de fichier différente : le jeu corrige la taille
			part.Anchored = true
			part.Parent = import
			pieceCount += 1
		end
	end
	import.Parent = World.game.Workspace
end)

section("Kit importé repéré au démarrage")
local ServerStorage = World.game:GetService("ServerStorage")
check(World.game.Workspace:FindFirstChild("HoH_Kit") == nil, "le modèle importé n'est plus dans le monde")
check(ServerStorage:FindFirstChild("HoH_Kit") ~= nil, "il est rangé dans ServerStorage")
local reported = false
for _, line in World.Prints do
	if string.find(line, string.format("Kit importé trouvé (HoH_Kit) : %d/%d", pieceCount, pieceCount), 1, true) then
		reported = true
	end
end
check(reported, "bilan dans la sortie : " .. pieceCount .. "/" .. pieceCount .. " pièces")

section("Carte posée avec les meshes importés")
World.AddPlayer("Alice", { client = true })
World.AddPlayer("Bob", {})
local built = H.advanceUntil(function()
	return World.game.Workspace:FindFirstChild("Map_TheCarousel") ~= nil
end, 120)
check(built, "Carousel Valley construite")
Engine.Advance(3)
local folder = World.game.Workspace:FindFirstChild("Map_TheCarousel")
local Manifest = H.require(World.game.ReplicatedStorage.Shared.Kit.Manifest)
local models, withMeshes, tagged, wrongSize, colliding = 0, 0, 0, 0, 0
local CollectionService = World.game:GetService("CollectionService")
for _, d in folder:GetDescendants() do
	if d.ClassName == "Model" and d:GetAttribute("KitAsset") then
		models += 1
		if CollectionService:HasTag(d, "HoH_Kit") then
			tagged += 1
		end
		local def = Manifest[d:GetAttribute("KitAsset")]
		local scale = d:GetAttribute("KitScale") or 1
		local count = 0
		for _, child in d:GetChildren() do
			if child.ClassName == "MeshPart" then
				count += 1
				local piece
				for _, p in def.Pieces do
					if p.Mesh == child.Name then
						piece = p
					end
				end
				if not piece or (child.Size - piece.Size * scale).Magnitude > 0.01 then
					wrongSize += 1
				end
				if child.CanCollide then
					colliding += 1
				end
			end
		end
		if count == #def.Pieces then
			withMeshes += 1
		end
	end
end
check(models > 400 and withMeshes == models, string.format("%d/%d assets posés avec toutes leurs pièces importées", withMeshes, models))
check(wrongSize == 0, "chaque copie a la taille du manifeste (" .. wrongSize .. " écarts)")
check(colliding == 0, "les meshes ne collisionnent pas (les volumes simples s'en chargent)")
check(tagged == 0, "aucun asset laissé à construire par les joueurs")
check(World.EditableMeshes == 0, "aucun EditableMesh créé (" .. World.EditableMeshes .. ")")
local kitWarnings = 0
for _, w in World.Warnings do
	if string.find(w, "[Kit]", 1, true) then
		kitWarnings += 1
	end
end
check(kitWarnings == 0, "aucune alerte du kit dans la sortie")

section("Contrôle physique écrit dans la sortie (vraies requêtes dans Studio)")
local selfCheck = nil
for _, line in World.Prints do
	if string.find(line, "[Carousel Valley] contrôle physique", 1, true) then
		selfCheck = line
	end
end
for _, w in World.Warnings do
	if string.find(w, "[Carousel Valley] contrôle physique", 1, true) then
		selfCheck = w
	end
end
check(selfCheck ~= nil and string.sub(selfCheck, -4) == ": OK", "bilan : " .. tostring(selfCheck))

H.finish()

--[[
	KitController.lua
	Affiche les assets du kit (tools/assets) posés par le serveur que le
	serveur n'a pas pu copier depuis un kit importé (modèles tagués "HoH_Kit",
	voir src/server/Util/Kit.lua) : chaque pièce devient un MeshPart construit
	ici (EditableMesh, KitMesh.GetTemplate), sans collision, coloré par la
	palette de la carte. Une pièce n'est créée qu'une fois, les placements
	suivants en sont des copies qui partagent son mesh.
	Le serveur garde les collisions (volumes simples) : ce qui est construit ici
	n'est que visuel.

	Budget mémoire : Roblox limite la mémoire des EditableMesh sur chaque
	appareil. On construit donc d'abord l'essentiel (camps, objectifs, manège,
	sol et repères), puis les couverts, la végétation, les petits décors et les
	collines. Un asset est affiché en entier ou pas du tout : si ses meshes ne
	peuvent pas être construits, on montre seulement ses volumes de collision
	(jamais un bloc de la taille de toute la pièce) et une boule de feuillage
	pour les arbres et buissons. Une ligne dans la sortie dit ce qui a été
	construit, et comment tout afficher (importer le kit dans Studio).
]]

local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Manifest = require(Shared.Kit.Manifest)
local Palettes = require(Shared.Kit.Palettes)
local KitMesh = require(Shared.Kit.KitMesh)

local KitController = {}

local TAG = "HoH_Kit"
local queue: { Model } = {}
local queued: { [Model]: boolean } = {}
local sorted = true
local stats = { Assets = 0, Simplified = 0 }
local reported = false

-- Ordre de construction (1 = d'abord)
local CATEGORY_PRIORITY: { [string]: number } = {
	Camp = 1,
	Objective = 1,
	Ride = 1,
	Landmark = 2,
	Terrain = 2,
	Cover = 3,
	Fence = 3,
	Tree = 4,
	Rock = 4,
	Bush = 4,
	Decor = 5,
}
local FAR_ASSETS: { [string]: boolean } = {
	TreeFarRound = true,
	TreeFarPine = true,
}

local function priorityOf(model: Model): number
	local assetName = model:GetAttribute("KitAsset")
	if type(assetName) ~= "string" then
		return 9
	end
	if FAR_ASSETS[assetName] or string.sub(assetName, 1, 11) == "ValleyHills" then
		return 6 -- décor lointain, hors de l'aire de jeu
	end
	local def = Manifest[assetName]
	return def and CATEGORY_PRIORITY[def.Category] or 5
end

-- Feuillages remplacés par une boule quand le mesh manque (arbres, buissons)
local FOLIAGE_ROLES: { [string]: boolean } = {
	Foliage = true,
	FoliageDark = true,
	FoliageLight = true,
	Blossom = true,
	Pine = true,
}

-- Recolore les pièces d'un rôle quand le serveur change sa couleur
local function recolor(model: Model, attribute: string)
	local role = string.match(attribute, "^KitRole_(.+)$")
	if not role and attribute ~= "KitTeam" and attribute ~= "KitPalette" then
		return
	end
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") and part.Name ~= "KitPivot" then
			local partRole = part:GetAttribute("KitRole")
			if type(partRole) == "string" and (role == nil or partRole == role) then
				part.Color = Palettes.Color(model, partRole)
			end
		end
	end
end

local function placePiece(model: Model, pivot: BasePart, piece: Manifest.Piece, scale: number, part: BasePart, category: string)
	local color, material, transparency = Palettes.Resolve(model, piece.Role, piece.Material)
	part.Name = piece.Mesh
	part.Size = piece.Size * scale
	part.CFrame = pivot.CFrame * CFrame.new(piece.Center * scale)
	part.Color = color
	part.Material = material
	part.Transparency = transparency
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = KitMesh.Occludes(category, piece.Size * scale)
	part.CanTouch = false
	part.CastShadow = piece.Shadow
	part:SetAttribute("KitMesh", piece.Mesh)
	part:SetAttribute("KitRole", piece.Role)
	part:SetAttribute("KitLocal", true) -- (créée par ce client : déjà à la bonne place)
	if model:GetAttribute("KitMovable") == true then
		-- Objet porté (œuf) : les pièces suivent le pivot quand le serveur le déplace
		part.Anchored = false
		part.Massless = true
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = pivot
		weld.Part1 = part
		weld.Parent = part
	end
	part.Parent = model
end

-- Asset sans meshes (budget épuisé) : ses volumes de collision deviennent
-- visibles (on ne traverse pas un obstacle invisible) et les feuillages
-- deviennent des boules ; rien d'autre n'est dessiné
local function simplify(model: Model, def: Manifest.AssetDef, pivot: BasePart, scale: number)
	local mainRole = def.Pieces[1] and def.Pieces[1].Role or "Wood"
	for _, piece in def.Pieces do
		if not FOLIAGE_ROLES[piece.Role] then
			mainRole = piece.Role
			break
		end
	end
	for _, child in model:GetChildren() do
		if child:IsA("BasePart") and child.Name == "KitCollider" then
			child.Transparency = 0
			child.Color = Palettes.Color(model, mainRole)
			child.Material = Enum.Material.SmoothPlastic
		end
	end
	for _, piece in def.Pieces do
		if FOLIAGE_ROLES[piece.Role] then
			local ball = Instance.new("Part")
			ball.Shape = Enum.PartType.Ball
			placePiece(model, pivot, piece, scale, ball, def.Category)
			local size = piece.Size * scale * 0.85
			ball.Size = Vector3.one * math.min(size.X, size.Y, size.Z)
			ball:SetAttribute("KitSimplified", true)
		end
	end
end

local function warnBudget()
	if reported then
		return
	end
	reported = true
	warn(string.format(
		"[Kit] Limite mémoire des meshes atteinte après %d pièces (%d triangles) : les décors restants sont simplifiés. Pour tout afficher, importer assets/kit/HoH_Kit.fbx dans Studio (reference/TEST_STUDIO.md, §1).",
		KitMesh.Built,
		KitMesh.BuiltTriangles
	))
end

-- Construit un asset en entier (ou le simplifie) ; retourne le nombre de pièces
local function build(model: Model): number
	if model.Parent == nil or model:GetAttribute("KitBuilt") == true then
		return 0
	end
	local def = Manifest[model:GetAttribute("KitAsset") :: string]
	local pivot = model:FindFirstChild("KitPivot")
	if not def or not pivot or not pivot:IsA("BasePart") then
		return 0
	end
	model:SetAttribute("KitBuilt", true) -- (attribut local au client)
	model.AttributeChanged:Connect(function(attribute)
		recolor(model, attribute)
	end)
	local scale = model:GetAttribute("KitScale")
	scale = type(scale) == "number" and scale or 1
	-- D'abord tous les modèles de pièces : tout ou rien
	local templates: { MeshPart } = {}
	local complete = true
	for i, piece in def.Pieces do
		local template = KitMesh.GetTemplate(piece.Mesh)
		if not template then
			complete = false
			break
		end
		templates[i] = template
	end
	if model.Parent == nil then
		return 0
	end
	if not complete then
		if KitMesh.BudgetReached then
			warnBudget()
		elseif KitMesh.LastError and not reported then
			reported = true
			warn("[Kit] Meshes non construits (" .. tostring(KitMesh.LastError) .. ") : décors simplifiés. Importer assets/kit/HoH_Kit.fbx dans Studio (reference/TEST_STUDIO.md, §1).")
		end
		simplify(model, def, pivot, scale)
		stats.Simplified += 1
		return #def.Pieces
	end
	for i, piece in def.Pieces do
		placePiece(model, pivot, piece, scale, templates[i]:Clone(), def.Category)
	end
	stats.Assets += 1
	return #def.Pieces
end

local function enqueue(instance: Instance)
	if instance:IsA("Model") and not queued[instance] then
		queued[instance] = true
		table.insert(queue, instance)
		sorted = false
	end
end

-- Ordre : priorité, puis distance à la caméra (ce qu'on voit d'abord)
local function sortQueue()
	local camera = workspace.CurrentCamera
	local eye = camera and camera.CFrame.Position or Vector3.zero
	local keys: { [Model]: number } = {}
	for _, model in queue do
		local pivot = model:FindFirstChild("KitPivot")
		local distance = pivot and pivot:IsA("BasePart") and (pivot.Position - eye).Magnitude or 1e6
		keys[model] = priorityOf(model) * 1e7 + math.min(distance, 9e6)
	end
	table.sort(queue, function(a, b)
		return keys[a] < keys[b]
	end)
	sorted = true
end

-- Bilan dans la sortie, une fois la carte affichée
local function report()
	print(string.format(
		"[Kit] Décors affichés par ce joueur : %d assets en meshes, %d simplifiés (meshes construits ici : %d pièces, %d triangles)",
		stats.Assets,
		stats.Simplified,
		KitMesh.Built,
		KitMesh.BuiltTriangles
	))
end

-- Un seul fil de construction : quelques pièces par image (pas de gel au
-- chargement d'une carte), la création d'un mesh pouvant attendre
local function worker()
	local busy = false
	while true do
		if #queue == 0 then
			if busy then
				busy = false
				report()
			end
			RunService.Heartbeat:Wait()
			continue
		end
		busy = true
		if not sorted then
			sortQueue()
		end
		local done = 0
		while #queue > 0 and done < Config.Kit.PiecesPerFrame do
			local model = table.remove(queue, 1) :: Model
			queued[model] = nil
			done += math.max(1, build(model))
		end
		RunService.Heartbeat:Wait()
	end
end

function KitController.Init()
	for _, model in CollectionService:GetTagged(TAG) do
		enqueue(model)
	end
	CollectionService:GetInstanceAddedSignal(TAG):Connect(enqueue)
	task.spawn(worker)
end

-- Pour les tests : construit tout ce qui attend, tout de suite
function KitController.Flush()
	if not sorted then
		sortQueue()
	end
	while #queue > 0 do
		local model = table.remove(queue, 1) :: Model
		queued[model] = nil
		build(model)
	end
end

function KitController.GetStats(): { Assets: number, Simplified: number }
	return stats
end

return KitController

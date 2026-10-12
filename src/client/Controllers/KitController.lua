--[[
	KitController.lua
	Construit localement les meshes des assets du kit (tools/assets) posés par
	le serveur (modèles tagués "HoH_Kit", voir src/server/Util/Kit.lua) :
	chaque pièce devient un MeshPart (EditableMesh -> CreateMeshPartAsync), sans
	collision, coloré par la palette de la carte. Une pièce n'est créée qu'une
	fois, les placements suivants en sont des copies.
	Le serveur garde les collisions (volumes simples) : ce qui est construit ici
	n'est que visuel. Si EditableMesh est refusé (expérience publiée sans
	l'option « Allow Mesh & Image APIs »), on prévient une fois dans la sortie
	et on pose des blocs aux bonnes dimensions pour rester jouable.
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
local warned = false

local function buildPiece(model: Model, pivot: BasePart, piece: Manifest.Piece, scale: number)
	local template = KitMesh.GetTemplate(piece.Mesh)
	if model.Parent == nil then
		return
	end
	local part: BasePart
	if template then
		part = template:Clone()
	else
		if not warned then
			warned = true
			warn("[Kit] Meshes non construits (" .. tostring(KitMesh.LastError) .. ") : importer assets/kit/HoH_Kit.fbx dans Studio (tools/assets/README.md). Blocs de remplacement en attendant.")
		end
		local block = Instance.new("Part")
		block.TopSurface = Enum.SurfaceType.Smooth
		block.BottomSurface = Enum.SurfaceType.Smooth
		part = block
	end
	local color, material, transparency = Palettes.Resolve(model, piece.Role, piece.Material)
	part.Name = piece.Mesh
	part.Size = piece.Size * scale
	part.CFrame = pivot.CFrame * CFrame.new(piece.Center * scale)
	part.Color = color
	part.Material = material
	part.Transparency = transparency
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
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

-- Recolore les pièces d'un rôle quand le serveur change sa couleur
local function recolor(model: Model, attribute: string)
	local role = string.match(attribute, "^KitRole_(.+)$")
	if not role and attribute ~= "KitTeam" and attribute ~= "KitPalette" then
		return
	end
	for _, part in model:GetChildren() do
		if part:IsA("BasePart") and part.Name ~= "KitPivot" then
			local partRole = part:GetAttribute("KitRole")
			if type(partRole) == "string" and (role == nil or partRole == role) then
				part.Color = Palettes.Color(model, partRole)
			end
		end
	end
end

local function build(model: Model, budget: { n: number })
	if model.Parent == nil or model:GetAttribute("KitBuilt") == true then
		return
	end
	local def = Manifest[model:GetAttribute("KitAsset") :: string]
	local pivot = model:FindFirstChild("KitPivot")
	if not def or not pivot or not pivot:IsA("BasePart") then
		return
	end
	model:SetAttribute("KitBuilt", true) -- (attribut local au client)
	model.AttributeChanged:Connect(function(attribute)
		recolor(model, attribute)
	end)
	local scale = model:GetAttribute("KitScale")
	scale = type(scale) == "number" and scale or 1
	for _, piece in def.Pieces do
		buildPiece(model, pivot, piece, scale)
		budget.n += 1
	end
end

local function enqueue(instance: Instance)
	if instance:IsA("Model") and not queued[instance] then
		queued[instance] = true
		table.insert(queue, instance)
	end
end

-- Un seul fil de construction : quelques pièces par image (pas de gel au
-- chargement d'une carte), la création d'un mesh pouvant attendre
local function worker()
	while true do
		if #queue == 0 then
			RunService.Heartbeat:Wait()
			continue
		end
		local budget = { n = 0 }
		while #queue > 0 and budget.n < Config.Kit.PiecesPerFrame do
			local model = table.remove(queue, 1) :: Model
			queued[model] = nil
			build(model, budget)
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
	local budget = { n = -math.huge }
	while #queue > 0 do
		local model = table.remove(queue, 1) :: Model
		queued[model] = nil
		build(model, budget)
	end
end

return KitController

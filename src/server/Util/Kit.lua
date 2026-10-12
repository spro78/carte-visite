--[[
	Kit.lua
	Pose des assets du kit 3D (modélisés dans Blender, tools/assets) dans une
	carte. Pour chaque placement, le serveur crée :
	  - un modèle avec un pivot invisible (KitPivot) et les attributs qui
	    décrivent l'asset (KitAsset, KitScale, KitPalette, KitTeam, KitRole_*) ;
	  - les volumes de collision simples du manifeste (pièces invisibles), qui
	    sont la seule géométrie physique : identique pour tous les clients ;
	  - les meshes visibles, copiés depuis le kit importé dans Studio (modèle
	    « HoH_Kit » ou « HoH_KitMeshes », voir Kit.Init) ; sinon le modèle est
	    tagué et chaque client les construit lui-même (KitController,
	    EditableMesh, limité par le budget mémoire de l'appareil).
	Un modèle posé dans un mécanisme tournant (MapBase.NewSpinner) tourne avec
	lui : les pièces visibles sont des descendants du modèle.
]]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Manifest = require(Shared.Kit.Manifest)
local Palettes = require(Shared.Kit.Palettes)
local KitMesh = require(Shared.Kit.KitMesh)

local Kit = {}

Kit.Tag = "HoH_Kit"

export type PlaceOptions = {
	Scale: number?, -- échelle uniforme (défaut 1)
	Palette: string?, -- palette de la carte (défaut Valley)
	Team: string?, -- équipe d'un élément de camp (rôles Team / TeamDark)
	Roles: { [string]: Color3 }?, -- couleurs imposées pour certains rôles
	Collide: boolean?, -- false : aucune collision (décor lointain, éléments mobiles)
	Movable: boolean?, -- pièces soudées au pivot (objet porté, ex. un œuf)
	Name: string?,
}

-- Au démarrage du serveur : repère le kit importé (Import 3D de
-- assets/kit/HoH_Kit.fbx), le range dans ServerStorage s'il a été déposé
-- dans le monde, et écrit dans la sortie ce qui sera utilisé
function Kit.Init()
	local root = KitMesh.FindImportedRoot()
	if root and root:IsDescendantOf(workspace) then
		root.Parent = game:GetService("ServerStorage")
	end
	KitMesh.SetImportedRoot(root)
	local total, found = 0, 0
	local missing = {}
	for assetName, def in Manifest do
		for _, piece in def.Pieces do
			total += 1
			if KitMesh.GetImported(piece.Mesh) then
				found += 1
			elseif #missing < 5 then
				table.insert(missing, assetName)
			end
		end
	end
	if not root then
		print("[Kit] Pas de kit importé : chaque joueur construira les meshes (limite mémoire possible). Importer assets/kit/HoH_Kit.fbx : reference/TEST_STUDIO.md")
	elseif found == total then
		print(string.format("[Kit] Kit importé trouvé (%s) : %d/%d pièces, meshes Roblox utilisés partout", root.Name, found, total))
	else
		print(string.format("[Kit] Kit importé incomplet (%s) : %d/%d pièces ; les assets incomplets seront construits par les joueurs (ex. %s)", root.Name, found, total, table.concat(missing, ", ")))
	end
end

function Kit.Get(assetName: string): Manifest.AssetDef?
	return Manifest[assetName]
end

function Kit.Has(assetName: string): boolean
	return Manifest[assetName] ~= nil
end

-- Volume de collision invisible
local function collider(model: Model, spec: Manifest.Collider, cframe: CFrame, scale: number)
	local part: BasePart
	local rel = CFrame.new(spec.CFrame.Position * scale) * spec.CFrame.Rotation
	local size = spec.Size * scale
	if spec.Shape == "Wedge" then
		part = Instance.new("WedgePart")
	else
		local p = Instance.new("Part")
		if spec.Shape == "Ball" then
			p.Shape = Enum.PartType.Ball
		elseif spec.Shape == "Cylinder" then
			-- Cylindre debout : Roblox oriente les cylindres sur l'axe X
			p.Shape = Enum.PartType.Cylinder
			rel = rel * CFrame.Angles(0, 0, math.pi / 2)
		elseif spec.Shape == "CylinderX" then
			p.Shape = Enum.PartType.Cylinder
		end
		part = p
	end
	part.Name = "KitCollider"
	part.Size = size
	part.CFrame = cframe * rel
	part.Anchored = true
	part.Transparency = 1
	part.CanCollide = true
	part.CanQuery = true
	part.CanTouch = false
	part.CastShadow = false
	part.Parent = model
end

-- Copie des meshes importés dans Studio (s'ils sont tous présents)
local function cloneImported(model: Model, def: Manifest.AssetDef, cframe: CFrame, scale: number): boolean
	local templates = {}
	for i, piece in def.Pieces do
		local template = KitMesh.GetImported(piece.Mesh)
		if not template then
			return false
		end
		templates[i] = template
	end
	for i, piece in def.Pieces do
		local part = templates[i]:Clone()
		local color, material, transparency = Palettes.Resolve(model, piece.Role, piece.Material)
		part.Name = piece.Mesh
		part.Size = piece.Size * scale
		part.CFrame = cframe * CFrame.new(piece.Center * scale)
		part.Color = color
		part.Material = material
		part.Transparency = transparency
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = KitMesh.Occludes(def.Category, piece.Size * scale)
		part.CanTouch = false
		part.CastShadow = piece.Shadow
		part:SetAttribute("KitMesh", piece.Mesh)
		part:SetAttribute("KitRole", piece.Role)
		if model:GetAttribute("KitMovable") == true then
			part.Anchored = false
			part.Massless = true
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = model.PrimaryPart
			weld.Part1 = part
			weld.Parent = part
		end
		part.Parent = model
	end
	return true
end

-- Pose un asset ; cframe = position au sol et orientation (avant = -Z)
function Kit.Place(parent: Instance, assetName: string, cframe: CFrame, options: PlaceOptions?): Model
	local def = Manifest[assetName]
	assert(def, "Asset inconnu dans le kit : " .. tostring(assetName))
	local opts: PlaceOptions = options or {}
	local scale = opts.Scale or 1
	local model = Instance.new("Model")
	model.Name = opts.Name or assetName
	local pivot = Instance.new("Part")
	pivot.Name = "KitPivot"
	pivot.Size = Vector3.new(0.2, 0.2, 0.2)
	pivot.CFrame = cframe
	pivot.Transparency = 1
	pivot.Anchored = true
	pivot.CanCollide = false
	pivot.CanQuery = false
	pivot.CanTouch = false
	pivot.CastShadow = false
	pivot.Parent = model
	model.PrimaryPart = pivot
	model:SetAttribute("KitAsset", assetName)
	model:SetAttribute("KitScale", scale)
	if opts.Palette then
		model:SetAttribute("KitPalette", opts.Palette)
	end
	if opts.Team then
		model:SetAttribute("KitTeam", opts.Team)
	end
	if opts.Roles then
		for role, color in opts.Roles do
			model:SetAttribute("KitRole_" .. role, color)
		end
	end
	if opts.Movable then
		model:SetAttribute("KitMovable", true)
	end
	if opts.Collide ~= false then
		for _, spec in def.Colliders do
			collider(model, spec, cframe, scale)
		end
	end
	if not cloneImported(model, def, cframe, scale) then
		CollectionService:AddTag(model, Kit.Tag)
	end
	model.Parent = parent
	return model
end

-- Change la couleur d'un rôle sur un asset posé (ex. anneau d'une zone tenue
-- par une équipe). Les clients recolorent leurs pièces (KitController).
function Kit.SetRoleColor(model: Model, role: string, color: Color3?)
	model:SetAttribute("KitRole_" .. role, color)
	for _, part in model:GetChildren() do
		if part:IsA("BasePart") and part:GetAttribute("KitRole") == role then
			part.Color = Palettes.Color(model, role)
		end
	end
end

-- Point d'ancrage d'un asset posé (ex. moyeu des ailes du moulin)
function Kit.Anchor(assetName: string, anchor: string, cframe: CFrame, scale: number?): Vector3?
	local def = Manifest[assetName]
	local point = def and def.Anchors[anchor]
	if not point then
		return nil
	end
	return cframe:PointToWorldSpace(point * (scale or 1))
end

return Kit

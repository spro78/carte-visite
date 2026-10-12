--[[
	KitMesh.lua
	Géométrie des assets du kit (modélisés dans Blender, tools/assets) :
	  - décode les données compactes des modules Meshes/<Asset> (base64 :
	    sommets int16 normalisés sur la boîte de la pièce, triangles uint16) ;
	  - construit un EditableMesh (côté client), puis un MeshPart modèle.
	Les modèles construits sont gardés en cache : chaque pièce n'est créée
	qu'une fois et les placements en font des copies (même mesh partagé).
	Si les meshes ont été importés dans Studio (dossier ReplicatedStorage
	HoH_KitMeshes, voir tools/assets/README.md), ce sont eux qui servent.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(script.Parent.Parent.Config)
local Manifest = require(script.Parent.Manifest)

local KitMesh = {}

KitMesh.ImportedFolderName = "HoH_KitMeshes"

export type Geometry = {
	Positions: { Vector3 }, -- centrées sur la boîte de la pièce, taille d'origine
	Triangles: { number }, -- indices à partir de 1, par trois
	Size: Vector3,
}

-- Taille d'origine de chaque pièce (boîte englobante dans Blender)
local pieceSize: { [string]: Vector3 } = {}
for _, def in Manifest do
	for _, piece in def.Pieces do
		pieceSize[piece.Mesh] = piece.Size
	end
end

-- ---------------------------------------------------------------------------
-- Base64 -> buffer
-- ---------------------------------------------------------------------------
local B64: { [number]: number } = {}
do
	local alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
	for i = 1, #alphabet do
		B64[string.byte(alphabet, i)] = i - 1
	end
end

function KitMesh.Decode(s: string): buffer
	local len = #s
	local pad = 0
	if string.sub(s, -2) == "==" then
		pad = 2
	elseif string.sub(s, -1) == "=" then
		pad = 1
	end
	local size = (len // 4) * 3 - pad
	local out = buffer.create(size)
	local o = 0
	for i = 1, len, 4 do
		local a, b, c, d = string.byte(s, i, i + 3)
		local n = (B64[a] or 0) * 262144 + (B64[b] or 0) * 4096 + (B64[c or 61] or 0) * 64 + (B64[d or 61] or 0)
		if o < size then
			buffer.writeu8(out, o, n // 65536)
		end
		if o + 1 < size then
			buffer.writeu8(out, o + 1, (n // 256) % 256)
		end
		if o + 2 < size then
			buffer.writeu8(out, o + 2, n % 256)
		end
		o += 3
	end
	return out
end

-- ---------------------------------------------------------------------------
-- Géométrie d'une pièce
-- ---------------------------------------------------------------------------
local geometryCache: { [string]: Geometry } = {}

local function assetOf(meshName: string): string
	return (string.match(meshName, "^(.-)__") or meshName)
end

function KitMesh.GetData(meshName: string): { N: number, V: string, T: string }?
	local folder = script.Parent:FindFirstChild("Meshes")
	local module = folder and folder:FindFirstChild(assetOf(meshName))
	if not module or not module:IsA("ModuleScript") then
		return nil
	end
	local data = (require :: any)(module)
	return data[meshName]
end

function KitMesh.GetGeometry(meshName: string): Geometry?
	local cached = geometryCache[meshName]
	if cached then
		return cached
	end
	local data = KitMesh.GetData(meshName)
	local size = pieceSize[meshName]
	if not data or not size then
		return nil
	end
	local v = KitMesh.Decode(data.V)
	local t = KitMesh.Decode(data.T)
	local half = size / 2
	local positions = table.create(data.N)
	for i = 0, data.N - 1 do
		local x = buffer.readi16(v, i * 6) / 32767
		local y = buffer.readi16(v, i * 6 + 2) / 32767
		local z = buffer.readi16(v, i * 6 + 4) / 32767
		positions[i + 1] = Vector3.new(x * half.X, y * half.Y, z * half.Z)
	end
	local count = buffer.len(t) // 2
	local triangles = table.create(count)
	local flip = Config.Kit.FlipWinding
	for i = 0, count - 1, 3 do
		local a = buffer.readu16(t, i * 2) + 1
		local b = buffer.readu16(t, i * 2 + 2) + 1
		local c = buffer.readu16(t, i * 2 + 4) + 1
		if flip then
			a, c = c, a
		end
		triangles[i + 1] = a
		triangles[i + 2] = b
		triangles[i + 3] = c
	end
	local geometry = { Positions = positions, Triangles = triangles, Size = size }
	geometryCache[meshName] = geometry
	return geometry
end

-- Une pièce visible doit-elle être vue par la caméra ? Invisicam
-- (StarterPlayer.DevCameraOcclusionMode) rend transparent ce qui cache le
-- joueur : murs, arbres, rochers, repères. Les sols, collines et éléments
-- plats en sont exclus (ils clignoteraient sous les pieds).
local OCCLUDING_CATEGORIES = { Landmark = true, Cover = true, Fence = true, Tree = true, Rock = true, Bush = true, Camp = true, Ride = true, Decor = true }

function KitMesh.Occludes(category: string, pieceSize: Vector3): boolean
	return OCCLUDING_CATEGORIES[category] == true and pieceSize.Y >= 1.5
end

-- ---------------------------------------------------------------------------
-- Meshes importés dans Studio (chemin recommandé : vrais assets Roblox)
-- ---------------------------------------------------------------------------
-- L'import de assets/kit/HoH_Kit.fbx (Import 3D) crée un modèle « HoH_Kit »
-- dans Workspace. Le serveur le trouve sous l'un de ces noms, où qu'il soit
-- (Workspace, ServerStorage, ReplicatedStorage), et le range dans
-- ServerStorage au démarrage (Kit.Init) : rien à renommer.
KitMesh.ImportedNames = { KitMesh.ImportedFolderName, "HoH_Kit" }

function KitMesh.FindImportedRoot(): Instance?
	local containers: { Instance } = { ReplicatedStorage, workspace }
	local ok, serverStorage = pcall(function()
		return game:GetService("ServerStorage")
	end)
	if ok and serverStorage then
		table.insert(containers, 1, serverStorage)
	end
	for _, container in containers do
		for _, name in KitMesh.ImportedNames do
			local found = container:FindFirstChild(name)
			if found and found:FindFirstChildWhichIsA("MeshPart", true) then
				return found
			end
		end
	end
	return nil
end

local importedRoot: Instance? = nil
local importedIndex: { [string]: MeshPart } = {}

-- Index des MeshParts importés par nom (Asset__Pièce)
function KitMesh.SetImportedRoot(root: Instance?)
	importedRoot = root
	table.clear(importedIndex)
	if root then
		for _, item in root:GetDescendants() do
			if item:IsA("MeshPart") and importedIndex[item.Name] == nil then
				importedIndex[item.Name] = item
			end
		end
	end
end

function KitMesh.GetImported(meshName: string): MeshPart?
	if importedRoot == nil or importedRoot.Parent == nil then
		local root = KitMesh.FindImportedRoot()
		if root ~= importedRoot then
			KitMesh.SetImportedRoot(root)
		end
	end
	return importedIndex[meshName]
end

-- ---------------------------------------------------------------------------
-- Meshes construits par le client (EditableMesh), à défaut d'import
-- ---------------------------------------------------------------------------
-- Roblox limite la mémoire des EditableMesh côté client (budget propre à
-- l'appareil) : CreateEditableMesh renvoie nil quand il est épuisé. On
-- construit donc chaque pièce une seule fois, on la recopie en mesh de taille
-- fixe (plus économe, recommandé par Roblox) et on libère l'original ; au
-- premier refus, on s'arrête net : les pièces restantes ne sont pas affichées
-- (KitController montre alors leurs volumes de collision, jamais un bloc
-- géant à la place du mesh).
local templates: { [string]: MeshPart | false } = {}
local building: { [string]: boolean } = {}

KitMesh.BudgetReached = false
KitMesh.Built = 0 -- pièces construites par ce client
KitMesh.BuiltTriangles = 0
KitMesh.LastError = nil :: string?

local function buildEditable(AssetService: any, geometry: Geometry): any?
	local mesh = AssetService:CreateEditableMesh()
	if not mesh then
		return nil
	end
	local ids = table.create(#geometry.Positions)
	local normals = table.create(#geometry.Positions)
	for i, p in geometry.Positions do
		ids[i] = mesh:AddVertex(p)
		-- Normale calculée automatiquement, partagée par les faces du sommet
		-- (les arêtes vives sont déjà des sommets distincts dans les données)
		normals[i] = mesh:AddNormal()
	end
	local tris = geometry.Triangles
	for i = 1, #tris, 3 do
		local face = mesh:AddTriangle(ids[tris[i]], ids[tris[i + 1]], ids[tris[i + 2]])
		mesh:SetFaceNormals(face, { normals[tris[i]], normals[tris[i + 1]], normals[tris[i + 2]] })
	end
	return mesh
end

local function createTemplate(meshName: string, geometry: Geometry): MeshPart?
	local AssetService = game:GetService("AssetService")
	-- (dans une expérience publiée sans l'option « Enable Mesh / Image APIs »,
	-- la création lève une erreur : on la garde comme raison, sans planter)
	local built, growable = pcall(buildEditable, AssetService, geometry)
	if not built then
		KitMesh.LastError = tostring(growable)
		return nil
	end
	if not growable then
		KitMesh.BudgetReached = true
		KitMesh.LastError = "budget mémoire des meshes épuisé"
		return nil
	end
	-- Copie de taille fixe, puis libération de l'original
	local ok, fixed = pcall(function()
		return AssetService:CreateEditableMeshAsync(Content.fromObject(growable))
	end)
	growable:Destroy()
	if not ok then
		KitMesh.LastError = tostring(fixed)
		return nil
	end
	if not fixed then
		KitMesh.BudgetReached = true
		KitMesh.LastError = "budget mémoire des meshes épuisé"
		return nil
	end
	local created, part = pcall(function()
		return AssetService:CreateMeshPartAsync(Content.fromObject(fixed), {
			CollisionFidelity = Enum.CollisionFidelity.Box,
			RenderFidelity = Enum.RenderFidelity.Automatic,
		})
	end)
	if not created or not part then
		fixed:Destroy()
		KitMesh.LastError = tostring(part)
		return nil
	end
	part.Name = meshName
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	KitMesh.Built += 1
	KitMesh.BuiltTriangles += #geometry.Triangles // 3
	return part
end

-- Retourne le MeshPart modèle de la pièce (peut attendre la création) ou nil.
-- Les copies d'un même modèle partagent son mesh (multi-référence).
function KitMesh.GetTemplate(meshName: string): MeshPart?
	local imported = KitMesh.GetImported(meshName)
	if imported then
		return imported
	end
	local cached = templates[meshName]
	if cached ~= nil then
		return cached or nil
	end
	while building[meshName] do
		task.wait()
	end
	cached = templates[meshName]
	if cached ~= nil then
		return cached or nil
	end
	if KitMesh.BudgetReached then
		return nil
	end
	building[meshName] = true
	local geometry = KitMesh.GetGeometry(meshName)
	local result: MeshPart? = nil
	if geometry then
		result = createTemplate(meshName, geometry)
	end
	-- Un refus de budget n'est pas définitif pour cette pièce en particulier :
	-- on ne mémorise l'échec que pour les autres causes
	if result then
		templates[meshName] = result
	elseif not KitMesh.BudgetReached then
		templates[meshName] = false
	end
	building[meshName] = nil
	return result
end

return KitMesh

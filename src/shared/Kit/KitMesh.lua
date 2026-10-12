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

-- ---------------------------------------------------------------------------
-- MeshPart modèle d'une pièce (client)
-- ---------------------------------------------------------------------------
local templates: { [string]: MeshPart | false } = {}
local building: { [string]: boolean } = {}

-- Mesh importé dans Studio (dossier ReplicatedStorage.HoH_KitMeshes)
function KitMesh.GetImported(meshName: string): MeshPart?
	local folder = ReplicatedStorage:FindFirstChild(KitMesh.ImportedFolderName)
	local found = folder and folder:FindFirstChild(meshName, true)
	if found and found:IsA("MeshPart") then
		return found
	end
	return nil
end

local function buildEditable(geometry: Geometry): any
	local AssetService = game:GetService("AssetService")
	local mesh = AssetService:CreateEditableMesh({})
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

-- Retourne le MeshPart modèle de la pièce (peut attendre la création) ou nil
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
	building[meshName] = true
	local result: MeshPart | false = false
	local geometry = KitMesh.GetGeometry(meshName)
	if geometry then
		local ok, part = pcall(function()
			local AssetService = game:GetService("AssetService")
			local editable = buildEditable(geometry)
			return AssetService:CreateMeshPartAsync(Content.fromObject(editable), {
				CollisionFidelity = Enum.CollisionFidelity.Box,
				RenderFidelity = Enum.RenderFidelity.Automatic,
			})
		end)
		if ok and part then
			part.Name = meshName
			part.Anchored = true
			part.CanCollide = false
			part.CanQuery = false
			part.CanTouch = false
			result = part
		else
			KitMesh.LastError = tostring(part)
		end
	end
	templates[meshName] = result
	building[meshName] = nil
	return result or nil
end

KitMesh.LastError = nil :: string?

return KitMesh

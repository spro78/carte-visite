--[[
	TerrainKit.lua
	Génération de relief avec le Terrain Roblox (sol, chemins, collines,
	falaises, lacs). Tout est construit par le code.

	Règles :
	  - La zone de jeu reste plate : le dessus du terrain est à origin.Y
	    (multiple de 4, aligné sur la grille des voxels).
	  - Le relief (collines, montagnes, falaises, eau) est autour de la zone de
	    jeu, derrière les limites invisibles.
	  - Clear() efface une région (remplissage d'air) au nettoyage de la map.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Style = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Style"))

local TerrainKit = {}

local VOXEL = 4

local function terrain(): Terrain
	return workspace.Terrain
end

-- Relief mémorisé (sphères des collines) pour connaître la hauteur du sol
-- sans lancer de rayon (poser des arbres et des maisons sur les collines).
local spheres: { { X: number, Y: number, Z: number, R: number } } = {}
local baseHeight = 0

function TerrainKit.ResetRelief(groundY: number)
	table.clear(spheres)
	baseHeight = groundY
end

function TerrainKit.HeightAt(x: number, z: number): number
	local best = baseHeight
	for _, s in spheres do
		local dx, dz = x - s.X, z - s.Z
		local d2 = dx * dx + dz * dz
		if d2 < s.R * s.R then
			local h = s.Y + math.sqrt(s.R * s.R - d2)
			if h > best then
				best = h
			end
		end
	end
	return best
end

-- Point au sol (hauteur du relief) à la verticale de p
function TerrainKit.Ground(p: Vector3): Vector3
	return Vector3.new(p.X, TerrainKit.HeightAt(p.X, p.Z), p.Z)
end

local function remember(center: Vector3, radius: number)
	table.insert(spheres, { X = center.X, Y = center.Y, Z = center.Z, R = radius })
end

-- Couleurs des matériaux du terrain (communes au lobby et aux maps)
function TerrainKit.ApplyPalette()
	local t = terrain()
	for name, color in Style.TerrainColors do
		local material = (Enum.Material :: any)[name]
		if material then
			t:SetMaterialColor(material, color)
		end
	end
	local water = Style.Water
	t.WaterColor = water.Color
	t.WaterTransparency = water.Transparency
	t.WaterWaveSize = water.WaveSize
	t.WaterWaveSpeed = water.WaveSpeed
	t.WaterReflectance = water.Reflectance
end

-- Efface le terrain d'une région (boîte centrée sur center)
function TerrainKit.Clear(center: Vector3, size: Vector3)
	terrain():FillBlock(CFrame.new(center), size, Enum.Material.Air)
end

-- Dalle plate : le dessus est à topY
function TerrainKit.Slab(center: Vector3, sizeX: number, sizeZ: number, topY: number, depth: number, material: Enum.Material)
	terrain():FillBlock(CFrame.new(center.X, topY - depth / 2, center.Z), Vector3.new(sizeX, depth, sizeZ), material)
end

-- Recouvre la couche du dessus (épaisseur d'un voxel) d'un autre matériau,
-- sans changer la hauteur : chemins, plaques de terre, sable...
function TerrainKit.Paint(cframe: CFrame, sizeX: number, sizeZ: number, topY: number, material: Enum.Material)
	local cf = CFrame.new(cframe.Position.X, topY - VOXEL / 2, cframe.Position.Z) * cframe.Rotation
	terrain():FillBlock(cf, Vector3.new(sizeX, VOXEL, sizeZ), material)
end

-- Disque peint (même principe)
function TerrainKit.PaintDisc(center: Vector3, radius: number, topY: number, material: Enum.Material)
	terrain():FillCylinder(CFrame.new(center.X, topY - VOXEL / 2, center.Z), VOXEL, radius, material)
end

-- Chemin peint passant par une suite de points (coins arrondis)
function TerrainKit.Path(points: { Vector3 }, width: number, topY: number, material: Enum.Material)
	for i = 1, #points - 1 do
		local a, b = points[i], points[i + 1]
		local flatA = Vector3.new(a.X, topY, a.Z)
		local flatB = Vector3.new(b.X, topY, b.Z)
		local length = (flatB - flatA).Magnitude
		if length > 0.5 then
			local mid = (flatA + flatB) / 2
			TerrainKit.Paint(CFrame.lookAt(mid, flatB), width, length, topY, material)
		end
	end
	for _, p in points do
		TerrainKit.PaintDisc(p, width / 2, topY, material)
	end
end

-- Colline douce : calotte de sphère qui dépasse de height au-dessus de baseY
function TerrainKit.Hill(center: Vector3, radius: number, height: number, baseY: number, material: Enum.Material)
	local h = math.min(height, radius * 0.95)
	local c = Vector3.new(center.X, baseY + h - radius, center.Z)
	terrain():FillBall(c, radius, material)
	remember(c, radius)
end

-- Colline allongée faite de plusieurs calottes le long d'un segment
function TerrainKit.Ridge(from: Vector3, to: Vector3, radius: number, height: number, baseY: number, material: Enum.Material, random: Random)
	local delta = to - from
	local steps = math.max(1, math.ceil(delta.Magnitude / (radius * 0.7)))
	for i = 0, steps do
		local p = from + delta * (i / steps)
		local r = radius * random:NextNumber(0.8, 1.15)
		TerrainKit.Hill(p, r, height * random:NextNumber(0.75, 1.1), baseY, material)
	end
end

-- Rocher ou éperon rocheux (boules de roche qui sortent du sol ou d'une colline)
function TerrainKit.Boulder(center: Vector3, radius: number, material: Enum.Material?)
	terrain():FillBall(center, radius, material or Enum.Material.Rock)
	remember(center, radius)
end

-- Falaise : blocs de roche inclinés empilés (aspect taillé)
function TerrainKit.Cliff(base: CFrame, width: number, height: number, depth: number, material: Enum.Material?, random: Random)
	local mat = material or Enum.Material.Rock
	local layers = math.max(1, math.floor(height / 10))
	for i = 0, layers - 1 do
		local k = 1 - i / (layers + 1) * 0.5
		local y = (i + 0.5) * height / layers
		local cf = base * CFrame.new(random:NextNumber(-2, 2), y, random:NextNumber(-1, 1) + i * 1.5)
			* CFrame.Angles(random:NextNumber(-0.08, 0.08), random:NextNumber(-0.15, 0.15), random:NextNumber(-0.08, 0.08))
		terrain():FillBlock(cf, Vector3.new(width * k, height / layers + 4, depth * k), mat)
	end
end

-- Lac ou mare : creuse une cuvette, la remplit d'eau et borde de sable.
-- La surface de l'eau est un peu sous le niveau du sol.
function TerrainKit.Pond(center: Vector3, radius: number, depth: number, topY: number, shore: Enum.Material?)
	local t = terrain()
	-- Rive
	t:FillCylinder(CFrame.new(center.X, topY - VOXEL / 2, center.Z), VOXEL, radius + 6, shore or Enum.Material.Sand)
	-- Cuvette
	t:FillBall(Vector3.new(center.X, topY - depth + radius * 0.15, center.Z), radius, shore or Enum.Material.Sand)
	t:FillCylinder(CFrame.new(center.X, topY - depth / 2, center.Z), depth, radius, Enum.Material.Air)
	-- Eau (surface 1 stud sous le sol)
	t:FillCylinder(CFrame.new(center.X, topY - 1 - (depth - 1) / 2, center.Z), depth - 1, radius, Enum.Material.Water)
end

-- Rivière droite entre deux points (surface sous le niveau du sol)
function TerrainKit.River(from: Vector3, to: Vector3, width: number, depth: number, topY: number)
	local t = terrain()
	local flatA = Vector3.new(from.X, topY, from.Z)
	local flatB = Vector3.new(to.X, topY, to.Z)
	local mid = (flatA + flatB) / 2
	local length = (flatB - flatA).Magnitude
	local cf = CFrame.lookAt(mid, flatB)
	t:FillBlock(cf * CFrame.new(0, -VOXEL / 2, 0), Vector3.new(width + 10, VOXEL, length), Enum.Material.Sand)
	t:FillBlock(cf * CFrame.new(0, -depth / 2, 0), Vector3.new(width, depth, length), Enum.Material.Air)
	t:FillBlock(cf * CFrame.new(0, -depth / 2 - 1, 0), Vector3.new(width, depth - 2, length), Enum.Material.Water)
	t:FillBlock(cf * CFrame.new(0, -depth - 2, 0), Vector3.new(width + 4, 4, length), Enum.Material.Sand)
end

-- Anneau de relief autour d'une zone carrée de jeu : talus herbeux, puis
-- collines et montagnes avec éperons rocheux. Ferme l'horizon ("vallée").
export type ValleyTheme = {
	Ground: Enum.Material, -- sol de la vallée
	Hill: Enum.Material, -- herbe des collines
	Rock: Enum.Material, -- roche des montagnes
	Peak: Enum.Material?, -- sommet (neige, roche claire...)
	Height: number?, -- hauteur max des montagnes
	Gap: number?, -- distance entre le bord de la zone de jeu et le pied des collines
	RockChance: number?,
	Mountains: boolean?, -- grandes montagnes lointaines (défaut : oui)
}
function TerrainKit.Valley(origin: Vector3, playSize: number, theme: ValleyTheme, random: Random)
	local topY = origin.Y
	local half = playSize / 2
	local gap = theme.Gap or 24
	local height = theme.Height or 90
	-- Sol plat de la vallée (déborde largement)
	local outer = playSize + 2 * (gap + 260)
	TerrainKit.Slab(origin, outer, outer, topY, 16, theme.Ground)

	-- Premier rang : talus doux juste derrière la limite
	local ring1 = half + gap + 26
	for i = 0, 35 do
		local a = i / 36 * math.pi * 2
		local d = ring1 / math.max(math.abs(math.cos(a)), math.abs(math.sin(a))) -- suit le carré
		d = math.min(d, ring1 * 1.25)
		local p = origin + Vector3.new(math.cos(a) * d, 0, math.sin(a) * d)
		TerrainKit.Hill(p, random:NextNumber(34, 46), random:NextNumber(12, 20), topY, theme.Hill)
	end
	-- Deuxième rang : grandes collines
	local ring2 = ring1 + 60
	for i = 0, 23 do
		local a = (i + 0.5) / 24 * math.pi * 2
		local d = ring2 + random:NextNumber(-10, 20)
		local p = origin + Vector3.new(math.cos(a) * d, 0, math.sin(a) * d)
		TerrainKit.Hill(p, random:NextNumber(60, 80), random:NextNumber(height * 0.4, height * 0.6), topY, theme.Hill)
	end
	-- Troisième rang : montagnes avec roche
	local ring3 = ring2 + 110
	for i = 0, 17 do
		local a = (i + random:NextNumber(-0.2, 0.2)) / 18 * math.pi * 2
		local d = ring3 + random:NextNumber(-20, 30)
		local p = origin + Vector3.new(math.cos(a) * d, 0, math.sin(a) * d)
		local r = random:NextNumber(85, 120)
		local h = random:NextNumber(height * 0.75, height)
		TerrainKit.Hill(p, r, h, topY, theme.Hill)
		-- Arêtes rocheuses qui affleurent sur le flanc tourné vers la vallée
		local inward = (origin - p).Unit
		for k = 1, 3 do
			local along = inward * random:NextNumber(r * 0.25, r * 0.6)
			local side = Vector3.new(-inward.Z, 0, inward.X) * random:NextNumber(-r * 0.4, r * 0.4)
			local q = p + along + side
			local rr = random:NextNumber(9, 16) * (k == 1 and 1.3 or 1)
			TerrainKit.Boulder(Vector3.new(q.X, TerrainKit.HeightAt(q.X, q.Z) - rr * 0.35, q.Z), rr, theme.Rock)
		end
		if theme.Peak then
			TerrainKit.Boulder(Vector3.new(p.X, topY + h - 6, p.Z), random:NextNumber(14, 22), theme.Peak)
		end
	end
	-- Quatrième rang : grandes montagnes lointaines (profondeur, brume)
	if theme.Mountains ~= false then
		local ring4 = ring3 + 170
		for i = 0, 15 do
			local a = (i + random:NextNumber(-0.25, 0.25)) / 16 * math.pi * 2
			local d = ring4 + random:NextNumber(-30, 40)
			local p = origin + Vector3.new(math.cos(a) * d, 0, math.sin(a) * d)
			local r = random:NextNumber(130, 175)
			local h = random:NextNumber(height * 1.3, height * 1.9)
			TerrainKit.Hill(p, r, h, topY, theme.Hill)
			local inward = (origin - p).Unit
			for k = 1, 2 do
				local q = p + inward * random:NextNumber(r * 0.2, r * 0.45) + Vector3.new(-inward.Z, 0, inward.X) * random:NextNumber(-r * 0.4, r * 0.4)
				local rr = random:NextNumber(18, 30)
				TerrainKit.Boulder(Vector3.new(q.X, TerrainKit.HeightAt(q.X, q.Z) - rr * 0.3, q.Z), rr, theme.Rock)
			end
			local top = Vector3.new(p.X, topY + h, p.Z)
			TerrainKit.Boulder(top - Vector3.new(0, 14, 0), random:NextNumber(26, 34), theme.Peak or theme.Rock)
		end
	end
	-- Rochers épars qui affleurent sur les talus
	local chance = theme.RockChance or 0.5
	for i = 0, 27 do
		if random:NextNumber() < chance then
			local a = i / 28 * math.pi * 2 + random:NextNumber(-0.1, 0.1)
			local d = ring1 + random:NextNumber(-10, 40)
			local p = origin + Vector3.new(math.cos(a) * d, 0, math.sin(a) * d)
			local rr = random:NextNumber(5, 10)
			TerrainKit.Boulder(Vector3.new(p.X, TerrainKit.HeightAt(p.X, p.Z) - rr * 0.4, p.Z), rr, theme.Rock)
		end
	end
end

-- Hauteur approximative du relief créé par Valley à une distance donnée du
-- centre (pour poser des arbres sur les collines sans lancer de rayon).
function TerrainKit.ValleyRing(playSize: number, gap: number?): (number, number, number)
	local half = playSize / 2
	local ring1 = half + (gap or 24) + 26
	return ring1, ring1 + 60, ring1 + 170
end

return TerrainKit

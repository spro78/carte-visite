--[[
	Ground.lua
	Sol et relief des maps en pièces (Parts), d'après la bible visuelle
	(reference/BIBLE_VISUELLE.md) :
	  - plateau de jeu à tenons, en bandes de deux tons (on lit sa vitesse) ;
	  - aplats colorés (zones, abords des camps), chemins lisses, mares ;
	  - buttes et crêtes en strates, terrasses de blocs autour de la zone de jeu.
	Le Terrain n'est plus utilisé : sol net, aucune texture bruitée, et tout
	disparaît avec le dossier de la map.

	Ground.Begin(parent, groundY, colors) ouvre un chantier (dossier "Ground").
	Les fonctions de dessin reçoivent une matière comme couleur logique
	(Enum.Material.Sand...) : la couleur réelle vient de la palette de la map
	(colors[nom de la matière]) ou, à défaut, de Style.TerrainColors.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Style = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Style"))
local Build = require(script.Parent.Build)

local Ground = {}

export type BackdropTheme = {
	Side: Color3, -- côtés des gradins
	Top: Color3, -- dessus des gradins
	Strata: { Color3 }?, -- bandes horizontales (bas -> haut), sinon Side
	Material: Enum.Material?, -- matière des côtés (SmoothPlastic par défaut)
	Heights: { number }?, -- hauteur de chaque gradin (défaut 12, 26, 48)
	Depths: { number }?, -- profondeur de chaque gradin (défaut 30, 40, 70)
	Gap: number?, -- distance entre la limite de jeu et le premier gradin
}

type Solid = { CFrame: CFrame, Half: Vector3, Top: number }

local folder: Instance? = nil
local baseY = 0
local palette: { [string]: Color3 } = {}
local layer = 0
local solids: { Solid } = {}
local terraceTops: { Solid } = {}

-- ---------------------------------------------------------------------------
-- Chantier
-- ---------------------------------------------------------------------------
function Ground.Begin(parent: Instance, groundY: number, colors: { [string]: Color3 }?)
	local f = Instance.new("Folder")
	f.Name = "Ground"
	f.Parent = parent
	folder = f
	baseY = groundY
	palette = colors or {}
	layer = 0
	table.clear(solids)
	table.clear(terraceTops)
end

function Ground.Folder(): Instance
	assert(folder, "Ground.Begin doit être appelé avant de construire")
	return folder
end

function Ground.ColorOf(material: Enum.Material): Color3
	return palette[material.Name] or Style.TerrainColors[material.Name] or Color3.fromRGB(140, 140, 140)
end

-- Hauteur de la prochaine plaque : chaque aplat est un peu plus haut que le
-- précédent (pas de scintillement entre faces confondues), sans dépasser 0,5 stud
local function nextTop(topY: number): number
	layer = layer % 20 + 1
	return topY + 0.06 + layer * 0.02
end

-- CFrame à plat (seul le cap est gardé) à la hauteur y
local function flat(cframe: CFrame, y: number): CFrame
	local look = cframe.LookVector
	local yaw = math.atan2(-look.X, -look.Z)
	return CFrame.new(cframe.Position.X, y, cframe.Position.Z) * CFrame.Angles(0, yaw, 0)
end

local function remember(list: { Solid }, cframe: CFrame, size: Vector3, top: number)
	table.insert(list, { CFrame = cframe, Half = size / 2, Top = top })
end

-- Hauteur du sol (dessus du plus haut bloc solide) en (x, z)
function Ground.HeightAt(x: number, z: number): number
	local best = baseY
	for _, solid in solids do
		if solid.Top > best then
			local p = solid.CFrame:PointToObjectSpace(Vector3.new(x, solid.CFrame.Position.Y, z))
			if math.abs(p.X) <= solid.Half.X and math.abs(p.Z) <= solid.Half.Z then
				best = solid.Top
			end
		end
	end
	return best
end

function Ground.At(p: Vector3): Vector3
	return Vector3.new(p.X, Ground.HeightAt(p.X, p.Z), p.Z)
end

-- ---------------------------------------------------------------------------
-- Plateau et aplats
-- ---------------------------------------------------------------------------

-- Plateau de jeu carré à tenons, en bandes alternées (colorA / colorB)
function Ground.Board(center: Vector3, size: number, colorA: Color3, colorB: Color3?, stripe: number?)
	local width = stripe or 24
	local count = math.max(1, math.ceil(size / width))
	local total = count * width
	for i = 0, count - 1 do
		local x = center.X - total / 2 + width * (i + 0.5)
		Build.Part({
			Name = "Board",
			Size = Vector3.new(width, 2, total),
			CFrame = CFrame.new(x, baseY - 1, center.Z),
			Color = (i % 2 == 1 and colorB) or colorA,
			Studs = true,
		}, Ground.Folder())
	end
end

-- Aplat rectangulaire (matière logique ou couleur explicite)
function Ground.Paint(cframe: CFrame, sizeX: number, sizeZ: number, topY: number, material: Enum.Material, color: Color3?): Part
	local top = nextTop(topY)
	return Build.Part({
		Name = "Plate_" .. material.Name,
		Size = Vector3.new(sizeX, 0.2, sizeZ),
		CFrame = flat(cframe, top - 0.1),
		Color = color or Ground.ColorOf(material),
		Studs = true,
	}, Ground.Folder())
end

-- Aplat rond
function Ground.PaintDisc(center: Vector3, radius: number, topY: number, material: Enum.Material, color: Color3?): Part
	local top = nextTop(topY)
	return Build.VerticalCylinder(Vector3.new(center.X, top - 0.1, center.Z), radius, 0.2, {
		Name = "Disc_" .. material.Name,
		Color = color or Ground.ColorOf(material),
		Material = Enum.Material.Plastic,
	}, Ground.Folder())
end

-- Chemin lisse le long d'une ligne brisée (segments + jonctions rondes)
function Ground.Path(points: { Vector3 }, width: number, topY: number, material: Enum.Material, color: Color3?)
	local top = nextTop(topY)
	local c = color or Ground.ColorOf(material)
	local f = Ground.Folder()
	for i = 1, #points do
		local p = Vector3.new(points[i].X, top - 0.1, points[i].Z)
		Build.VerticalCylinder(p, width / 2, 0.2, { Name = "PathJoint", Color = c, Material = Enum.Material.SmoothPlastic }, f)
		local nextPoint = points[i + 1]
		if nextPoint then
			local q = Vector3.new(nextPoint.X, top - 0.1, nextPoint.Z)
			local length = (q - p).Magnitude
			if length > 0.05 then
				Build.Part({
					Name = "Path_" .. material.Name,
					Size = Vector3.new(width, 0.2, length),
					CFrame = CFrame.lookAt((p + q) / 2, q),
					Color = c,
					Material = Enum.Material.SmoothPlastic,
				}, f)
			end
		end
	end
end

-- Mare : berge, eau claire à plat (décor : on marche dessus)
function Ground.Pond(center: Vector3, radius: number, _depth: number, topY: number, shore: Enum.Material?)
	local f = Ground.Folder()
	Ground.PaintDisc(center, radius + 4, topY, shore or Enum.Material.Sand)
	local top = nextTop(topY)
	Build.VerticalCylinder(Vector3.new(center.X, top - 0.1, center.Z), radius, 0.2, {
		Name = "Water",
		Color = Style.Water.Color,
		Material = Enum.Material.Glass,
		Transparency = 0.2,
		Reflectance = 0.15,
		Accent = true,
	}, f)
end

-- ---------------------------------------------------------------------------
-- Relief en blocs
-- ---------------------------------------------------------------------------

-- Butte : blocs empilés en strates qui rétrécissent un peu vers le haut,
-- dessus plat (couleur top). Solide (on ne la traverse pas).
function Ground.Butte(cframe: CFrame, width: number, depth: number, height: number, strata: { Color3 }, top: Color3?, random: Random?, material: Enum.Material?): Model
	local model = Instance.new("Model")
	model.Name = "Butte"
	local rng = random or Random.new()
	local base = flat(cframe, baseY)
	local n = math.max(1, #strata)
	local y = 0
	local w, d = width, depth
	for i = 1, n do
		local h = height / n * (i == n and 1 or rng:NextNumber(0.85, 1.15))
		if i == n then
			h = height - y
		end
		local cf = base * CFrame.new(rng:NextNumber(-0.6, 0.6), y + h / 2, rng:NextNumber(-0.6, 0.6))
		local size = Vector3.new(w, h, d)
		Build.Part({ Name = "Stratum", Size = size, CFrame = cf, Color = strata[i] or strata[1], Material = material or Enum.Material.SmoothPlastic }, model)
		remember(solids, cf, size, baseY + y + h)
		y += h
		w = math.max(4, w - rng:NextNumber(1, 3))
		d = math.max(4, d - rng:NextNumber(1, 3))
	end
	if top then
		Build.Part({ Name = "ButteTop", Size = Vector3.new(w + 1.5, 0.8, d + 1.5), CFrame = base * CFrame.new(0, height + 0.4, 0), Color = top, Studs = true }, model)
	end
	model.Parent = Ground.Folder()
	return model
end

-- Crête : suite de buttes de hauteurs variées entre deux points
function Ground.Ridge(from: Vector3, to: Vector3, width: number, height: number, strata: { Color3 }, top: Color3?, random: Random?)
	local rng = random or Random.new()
	local delta = Vector3.new(to.X - from.X, 0, to.Z - from.Z)
	local length = delta.Magnitude
	local count = math.max(1, math.floor(length / (width * 0.8)))
	local dir = length > 0 and delta.Unit or Vector3.new(0, 0, -1)
	for k = 0, count - 1 do
		local t = (k + 0.5) / count
		local p = from + delta * t
		local cf = CFrame.lookAt(p, p + dir)
		Ground.Butte(cf, width * rng:NextNumber(0.8, 1.1), length / count + 2, height * rng:NextNumber(0.75, 1.15), strata, top, rng)
	end
end

-- Terrasses de blocs autour de la zone de jeu (fond du décor)
function Ground.Terraces(center: Vector3, playSize: number, theme: BackdropTheme, random: Random)
	local heights = theme.Heights or { 12, 26, 48 }
	local depths = theme.Depths or { 30, 40, 70 }
	local inner = playSize / 2 + (theme.Gap or 14)
	local f = Ground.Folder()
	local model = Instance.new("Model")
	model.Name = "Terraces"
	-- Sol extérieur sous les gradins (le plateau de jeu le recouvre au centre)
	local outer = 2 * inner
	for _, d in depths do
		outer += 2 * d
	end
	Build.Part({ Name = "OuterGround", Size = Vector3.new(outer + 40, 2, outer + 40), CFrame = CFrame.new(center.X, baseY - 1.1, center.Z), Color = theme.Top, Studs = true }, model)
	for tier = 1, #heights do
		local depth = depths[tier] or depths[#depths]
		local height = heights[tier]
		local mid = inner + depth / 2
		-- Les quatre côtés couvrent aussi les coins
		local span = 2 * (inner + depth)
		for side = 0, 3 do
			local yaw = side * math.pi / 2
			local rot = CFrame.Angles(0, yaw, 0)
			local x = -span / 2
			while x < span / 2 do
				local length = math.min(random:NextNumber(26, 58), span / 2 - x)
				if length < 8 then
					break
				end
				local h = height * random:NextNumber(0.85, 1.18)
				local dz = random:NextNumber(-3, 3)
				local cf = CFrame.new(center) * rot * CFrame.new(x + length / 2, 0, -(mid + dz))
				local size = Vector3.new(length + 0.5, h, depth + 2)
				local strata = theme.Strata
				if strata and #strata > 0 then
					local y = 0
					for i, color in strata do
						local sh = (i == #strata) and (h - y) or h / #strata
						Build.Part({ Name = "Terrace", Size = Vector3.new(size.X, sh, size.Z), CFrame = CFrame.new(cf.Position.X, baseY + y + sh / 2 - 0.5, cf.Position.Z) * rot, Color = color, Material = theme.Material or Enum.Material.SmoothPlastic }, model)
						y += sh
					end
				else
					Build.Part({ Name = "Terrace", Size = size, CFrame = CFrame.new(cf.Position.X, baseY + h / 2 - 0.5, cf.Position.Z) * rot, Color = theme.Side, Material = theme.Material or Enum.Material.SmoothPlastic }, model)
				end
				local topCf = CFrame.new(cf.Position.X, baseY + h - 0.1, cf.Position.Z) * rot
				local topSize = Vector3.new(size.X + 0.6, 1.2, size.Z + 0.6)
				Build.Part({ Name = "TerraceTop", Size = topSize, CFrame = topCf, Color = theme.Top, Studs = true }, model)
				local solidCf = CFrame.new(cf.Position.X, baseY, cf.Position.Z) * rot
				remember(solids, solidCf, topSize, baseY + h + 0.5)
				if tier < #heights then
					remember(terraceTops, solidCf, Vector3.new(size.X - 4, 0, size.Z - 6), baseY + h + 0.5)
				end
				x += length
			end
		end
		inner += depth
	end
	model.Parent = f
end

-- Points au hasard sur le dessus des terrasses basses (pour y planter des arbres)
function Ground.TerraceSpots(count: number, random: Random): { Vector3 }
	local spots = {}
	if #terraceTops == 0 then
		return spots
	end
	for _ = 1, count do
		local top = terraceTops[random:NextInteger(1, #terraceTops)]
		local p = top.CFrame * CFrame.new(random:NextNumber(-top.Half.X, top.Half.X), 0, random:NextNumber(-top.Half.Z, top.Half.Z))
		table.insert(spots, Vector3.new(p.Position.X, top.Top, p.Position.Z))
	end
	return spots
end

return Ground

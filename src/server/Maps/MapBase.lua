--[[
	MapBase.lua
	Briques communes à toutes les maps : sol, limites invisibles, trois bases en
	triangle autour d'une zone centrale, cachettes (hautes herbes, buissons,
	terriers), décors (clôtures, bottes de foin, arbres, rochers) et mécanismes
	tournants. Chaque module de map appelle ces fonctions dans Build().
]]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Teams = require(Shared.Teams)
local Config = require(Shared.Config)
local Mechanics = require(Shared.Mechanics)
local Build = require(script.Parent.Parent.Util.Build)

local MapBase = {}

MapBase.HidingTag = "HoH_HidingSpot"

export type Base = {
	Team: string,
	Center: Vector3, -- centre de la base (au niveau du sol)
	CFrame: CFrame, -- orienté vers le centre de la map
	Pad: Part,
	Spawns: { CFrame },
	Radius: number, -- demi-côté de la plateforme
}

-- Angles (degrés) des trois bases autour du centre
MapBase.BaseAngles = { FOX = 90, CHICKEN = 210, SNAKE = 330 }

local random = Random.new()

function MapBase.NewFolder(name: string): Folder
	local folder = Instance.new("Folder")
	folder.Name = name
	return folder
end

-- Sol carré centré sur origin, surface supérieure à origin.Y.
function MapBase.BuildGround(folder: Instance, origin: Vector3, size: number, color: Color3, material: Enum.Material?): Part
	local ground = Build.Part({
		Name = "Ground",
		Size = Vector3.new(size, 4, size),
		Position = origin + Vector3.new(0, -2, 0),
		Color = color,
		Studs = material == nil or material == Enum.Material.Grass,
	}, folder)
	if material and material ~= Enum.Material.Grass then
		ground.Material = material
	end
	return ground
end

-- Quatre murs invisibles (et un plafond bas) pour qu'on ne sorte pas de la map.
function MapBase.BuildBoundary(folder: Instance, origin: Vector3, size: number, height: number)
	local half = size / 2
	local specs = {
		{ Vector3.new(0, 0, -half), Vector3.new(size, height, 2) },
		{ Vector3.new(0, 0, half), Vector3.new(size, height, 2) },
		{ Vector3.new(-half, 0, 0), Vector3.new(2, height, size) },
		{ Vector3.new(half, 0, 0), Vector3.new(2, height, size) },
	}
	for index, spec in specs do
		Build.Part({
			Name = "Boundary" .. index,
			Size = spec[2],
			Position = origin + spec[1] + Vector3.new(0, height / 2, 0),
			Transparency = 1,
			CanQuery = false,
		}, folder)
	end
end

-- Position d'une base (angle en degrés autour du centre)
function MapBase.BasePosition(origin: Vector3, teamId: string, radius: number): Vector3
	local angle = math.rad(MapBase.BaseAngles[teamId])
	return origin + Vector3.new(math.cos(angle) * radius, 0, math.sin(angle) * radius)
end

-- Trois bases disposées en triangle. Retourne bases[teamId].
function MapBase.BuildBases(folder: Instance, origin: Vector3, radius: number, padSize: number): { [string]: Base }
	local bases = {}
	for _, teamId in Teams.Order do
		local def = Teams.Get(teamId)
		assert(def)
		local center = MapBase.BasePosition(origin, teamId, radius)
		local facing = CFrame.lookAt(center, Vector3.new(origin.X, center.Y, origin.Z))
		local rotation = facing - facing.Position

		local halfPad = padSize / 2
		local function at(x: number, y: number, z: number): CFrame
			return CFrame.new(center) * rotation * CFrame.new(x, y, z)
		end
		local light = def.Color:Lerp(Color3.new(1, 1, 1), 0.35)

		-- Plateforme du camp (couleur d'équipe, à tenons) et bordure
		local pad = Build.Part({
			Name = teamId .. "_BasePad",
			Size = Vector3.new(padSize, 1, padSize),
			CFrame = at(0, 0.5, 0),
			Color = def.Color,
			Studs = true,
			Accent = true,
		}, folder)
		pad:SetAttribute("Team", teamId)
		pad:SetAttribute("BasePad", true)
		Build.Part({ Name = teamId .. "_BaseBorder", Size = Vector3.new(padSize + 3, 0.7, padSize + 3), CFrame = at(0, 0.35, 0), Color = def.DarkColor, Studs = true, Accent = true }, folder)
		-- Damier clair au centre (lisibilité)
		for i = -1, 1 do
			for j = -1, 1 do
				if (i + j) % 2 == 0 then
					Build.Part({ Name = "Tile", Size = Vector3.new(5, 0.12, 5), CFrame = at(i * 5, 1.06, j * 5), Color = light, Accent = true, CanCollide = false, CanQuery = false }, folder)
				end
			end
		end

		-- Arche d'entrée tournée vers le centre, avec la bannière du camp
		local front = -halfPad + 1.5
		for _, side in { -1, 1 } do
			Build.Part({ Name = "ArchPillar", Size = Vector3.new(3, 13, 3), CFrame = at(side * 9, 7, front), Color = light, Studs = true, Accent = true }, folder)
			Build.Part({ Name = "ArchCap", Size = Vector3.new(4, 1.2, 4), CFrame = at(side * 9, 14, front), Color = def.DarkColor, Studs = true, Accent = true }, folder)
		end
		local beam = Build.Part({ Name = teamId .. "_ArchBeam", Size = Vector3.new(22, 4, 1.6), CFrame = at(0, 12, front), Color = def.DarkColor, Accent = true }, folder)
		Build.SurfaceLabel(beam, Enum.NormalId.Front, def.Display .. " CAMP", { TextColor3 = Color3.new(1, 1, 1), TextStrokeTransparency = 0.2, Font = Enum.Font.GothamBlack })
		Build.SurfaceLabel(beam, Enum.NormalId.Back, def.Display .. " CAMP", { TextColor3 = Color3.new(1, 1, 1), TextStrokeTransparency = 0.2, Font = Enum.Font.GothamBlack })
		-- Fanions sous l'arche
		for k = -4, 4 do
			Build.Part({ Name = "Pennant", Size = Vector3.new(1.2, 1.4, 0.15), CFrame = at(k * 2, 9.4 + math.abs(k) * 0.12, front) * CFrame.Angles(0, 0, math.rad(45)), Color = k % 2 == 0 and def.Color or Color3.new(1, 1, 1), Accent = true, CanCollide = false, CanQuery = false }, folder)
		end

		-- Murets : arrière complet, côtés partiels (on entre par l'avant et les côtés)
		Build.Part({ Name = "CampWall", Size = Vector3.new(padSize + 3, 3.5, 2), CFrame = at(0, 1.75, halfPad + 1.5), Color = def.DarkColor, Studs = true, Accent = true }, folder)
		for _, side in { -1, 1 } do
			Build.Part({ Name = "CampWall", Size = Vector3.new(2, 3.5, padSize * 0.45), CFrame = at(side * (halfPad + 1.5), 1.75, halfPad * 0.55), Color = def.DarkColor, Studs = true, Accent = true }, folder)
			-- Drapeaux aux coins arrière
			Build.Part({ Name = "FlagPole", Size = Vector3.new(0.6, 16, 0.6), CFrame = at(side * (halfPad - 1), 8, halfPad - 1), Color = Color3.fromRGB(235, 235, 235) }, folder)
			Build.Part({ Name = "Flag", Size = Vector3.new(0.2, 3.4, 5), CFrame = at(side * (halfPad - 1), 14.2, halfPad - 3.5), Color = def.Color, Accent = true, CanCollide = false }, folder)
		end
		-- Tente du camp
		local tentCf = at(-halfPad * 0.45, 0, halfPad * 0.55)
		for _, side in { -1, 1 } do
			Build.Part({ Name = "Tent", Size = Vector3.new(0.4, 6.5, 8), CFrame = tentCf * CFrame.new(side * 2.1, 3, 0) * CFrame.Angles(0, 0, math.rad(side * 33)), Color = def.Color, Material = Enum.Material.Fabric, Accent = true }, folder)
		end
		-- Caisses
		Build.Part({ Name = "Crate", Size = Vector3.new(3, 3, 3), CFrame = at(halfPad * 0.55, 2.5, halfPad * 0.6) * CFrame.Angles(0, 0.3, 0), Color = Color3.fromRGB(170, 120, 70), Material = Enum.Material.WoodPlanks }, folder)
		Build.Part({ Name = "Crate", Size = Vector3.new(2.4, 2.4, 2.4), CFrame = at(halfPad * 0.55 - 3, 2.2, halfPad * 0.6 + 0.5) * CFrame.Angles(0, -0.2, 0), Color = Color3.fromRGB(160, 110, 65), Material = Enum.Material.WoodPlanks }, folder)

		-- Points d'apparition : cercle au centre de la base, tournés vers le centre de la map
		local spawns = {}
		local spawnCount = 8
		for i = 1, spawnCount do
			local a = (i / spawnCount) * math.pi * 2
			local offset = Vector3.new(math.cos(a) * padSize * 0.25, 0, math.sin(a) * padSize * 0.25)
			local position = center + offset + Vector3.new(0, 1 + Config.World.RespawnHeight, 0)
			table.insert(spawns, CFrame.lookAt(position, Vector3.new(origin.X, position.Y, origin.Z)))
		end

		bases[teamId] = {
			Team = teamId,
			Center = center,
			CFrame = facing,
			Pad = pad,
			Spawns = spawns,
			Radius = halfPad,
		}
	end
	return bases
end

-- Vrai si la position est sur la plateforme de la base (dans son repère).
function MapBase.IsInBase(base: Base, position: Vector3, margin: number?): boolean
	local localPos = base.CFrame:PointToObjectSpace(position)
	local limit = base.Radius + (margin or 0)
	return math.abs(localPos.X) <= limit and math.abs(localPos.Z) <= limit and localPos.Y < 12
end

-- Zone centrale ronde
function MapBase.BuildCentralPad(folder: Instance, origin: Vector3, radius: number, color: Color3, material: Enum.Material?): Part
	return Build.VerticalCylinder(origin + Vector3.new(0, 0.25, 0), radius, 0.5, {
		Name = "CentralPad",
		Color = color,
		Material = material or Enum.Material.SmoothPlastic,
	}, folder)
end

-- ---------------------------------------------------------------------------
-- Cachettes : une zone invisible taguée + un décor qui masque le joueur
-- ---------------------------------------------------------------------------
local function hidingZone(folder: Instance, cframe: CFrame, size: Vector3, kind: string): Part
	local zone = Build.Part({
		Name = "HidingZone_" .. kind,
		Size = size,
		CFrame = cframe,
		Transparency = 1,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
	}, folder)
	zone:SetAttribute("HidingKind", kind)
	CollectionService:AddTag(zone, MapBase.HidingTag)
	return zone
end

-- Hautes herbes : un massif de brins + une zone de cachette
function MapBase.BuildTallGrass(folder: Instance, position: Vector3, radius: number, color: Color3?)
	local base = color or Color3.fromRGB(95, 165, 70)
	local model = Instance.new("Model")
	model.Name = "TallGrass"
	local blades = math.floor(radius * 3.2)
	for i = 1, blades do
		local a = random:NextNumber(0, math.pi * 2)
		local r = math.sqrt(random:NextNumber()) * radius
		local height = random:NextNumber(5.5, 7.5)
		local p = position + Vector3.new(math.cos(a) * r, height / 2, math.sin(a) * r)
		Build.Part({
			Name = "Blade",
			Size = Vector3.new(random:NextNumber(0.9, 1.5), height, 0.3),
			CFrame = CFrame.new(p) * CFrame.Angles(random:NextNumber(-0.15, 0.15), random:NextNumber(0, math.pi), random:NextNumber(-0.2, 0.2)),
			Color = base:Lerp(Color3.fromRGB(200, 210, 90), random:NextNumber(0, 0.35)),
			Material = Enum.Material.Grass,
			CanCollide = false,
			CanQuery = false,
			CastShadow = false,
		}, model)
	end
	-- Coeur dense pour cacher complètement le joueur
	Build.VerticalCylinder(position + Vector3.new(0, 2.6, 0), radius * 0.65, 5.2, {
		Name = "GrassCore",
		Color = base,
		Material = Enum.Material.Grass,
		CanCollide = false,
		CanQuery = false,
		Transparency = 0.05,
	}, model)
	model.Parent = folder
	hidingZone(folder, CFrame.new(position + Vector3.new(0, 3, 0)), Vector3.new(radius * 2, 6, radius * 2), "Grass")
	return model
end

-- Buisson : grappe de cubes de feuillage, traversable (style "cubique")
function MapBase.BuildBush(folder: Instance, position: Vector3, size: number, color: Color3?)
	local model = Instance.new("Model")
	model.Name = "Bush"
	local leafColor = color or Color3.fromRGB(60, 150, 60)
	local cubes = {
		{ Vector3.new(0, size * 0.32, 0), size * 0.72, 0.3 },
		{ Vector3.new(size * 0.28, size * 0.22, size * 0.12), size * 0.5, 0.9 },
		{ Vector3.new(-size * 0.25, size * 0.2, -size * 0.18), size * 0.52, -0.5 },
		{ Vector3.new(size * 0.05, size * 0.5, -size * 0.2), size * 0.42, 1.3 },
	}
	for i, spec in cubes do
		Build.Part({
			Name = "Leaves",
			Size = Vector3.new(spec[2], spec[2], spec[2]),
			CFrame = CFrame.new(position + spec[1]) * CFrame.Angles(spec[3] * 0.4, spec[3], spec[3] * 0.3),
			Color = leafColor:Lerp(Color3.new(0, 0, 0), (i - 1) * 0.05),
			Studs = true,
			CanCollide = false,
			CanQuery = false,
		}, model)
	end
	model.Parent = folder
	hidingZone(folder, CFrame.new(position + Vector3.new(0, 2.5, 0)), Vector3.new(size * 0.85, 5, size * 0.85), "Bush")
	return model
end

-- Terrier : un monticule avec une entrée ; se tenir dans le trou cache le joueur
function MapBase.BuildBurrow(folder: Instance, position: Vector3, color: Color3?)
	local model = Instance.new("Model")
	model.Name = "Burrow"
	local dirt = color or Color3.fromRGB(120, 85, 55)
	Build.Part({
		Name = "Mound",
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(14, 14, 14),
		Position = position + Vector3.new(0, -3.5, 0),
		Color = dirt,
		Material = Enum.Material.Ground,
		CanCollide = false,
		CanQuery = false,
	}, model)
	Build.VerticalCylinder(position + Vector3.new(0, 3.55, 0), 3.2, 0.2, {
		Name = "Hole",
		Color = Color3.fromRGB(25, 18, 12),
		CanCollide = false,
		CanQuery = false,
	}, model)
	model.Parent = folder
	hidingZone(folder, CFrame.new(position + Vector3.new(0, 2.5, 0)), Vector3.new(9, 6, 9), "Burrow")
	return model
end

-- ---------------------------------------------------------------------------
-- Décors
-- ---------------------------------------------------------------------------
function MapBase.BuildFence(folder: Instance, from: Vector3, to: Vector3, color: Color3?)
	local wood = color or Color3.fromRGB(165, 115, 70)
	local delta = to - from
	local length = delta.Magnitude
	local mid = (from + to) / 2
	local cf = CFrame.lookAt(mid, mid + delta)
	for _, h in { 1.4, 2.8 } do
		Build.Part({
			Name = "FenceRail",
			Size = Vector3.new(0.4, 0.5, length),
			CFrame = cf + Vector3.new(0, h, 0),
			Color = wood,
			Material = Enum.Material.Wood,
		}, folder)
	end
	local posts = math.max(2, math.floor(length / 8) + 1)
	for i = 0, posts - 1 do
		local p = from + delta * (i / (posts - 1))
		Build.Part({
			Name = "FencePost",
			Size = Vector3.new(0.8, 3.6, 0.8),
			Position = p + Vector3.new(0, 1.8, 0),
			Color = wood:Lerp(Color3.new(0, 0, 0), 0.15),
			Material = Enum.Material.Wood,
		}, folder)
	end
end

function MapBase.BuildHayBale(folder: Instance, position: Vector3, yaw: number?)
	Build.Part({
		Name = "HayBale",
		Size = Vector3.new(5, 4, 4),
		CFrame = CFrame.new(position + Vector3.new(0, 2, 0)) * CFrame.Angles(0, yaw or 0, 0),
		Color = Color3.fromRGB(245, 200, 45),
		Studs = true,
	}, folder)
end

-- Arbre "en cubes" : tronc carré et feuillage de gros cubes aux couleurs d'automne
local LEAF_COLORS = {
	Color3.fromRGB(255, 132, 38),
	Color3.fromRGB(232, 72, 40),
	Color3.fromRGB(255, 190, 40),
	Color3.fromRGB(250, 110, 50),
}
function MapBase.BuildTree(folder: Instance, position: Vector3, scale: number?, leafColor: Color3?)
	local s = scale or 1
	Build.Part({
		Name = "Trunk",
		Size = Vector3.new(2.2, 11, 2.2) * s,
		CFrame = CFrame.new(position + Vector3.new(0, 5.5 * s, 0)) * CFrame.Angles(0, random:NextNumber(0, 1.5), 0),
		Color = Color3.fromRGB(110, 75, 50),
		Material = Enum.Material.Wood,
	}, folder)
	local cubes = {
		{ Vector3.new(0, 13, 0), 8.5 },
		{ Vector3.new(3.5, 11, 2), 6.5 },
		{ Vector3.new(-3.2, 11.5, -1.5), 6.5 },
		{ Vector3.new(1, 16.5, -1), 6 },
		{ Vector3.new(-1.5, 10, 3.5), 5.5 },
	}
	for i, spec in cubes do
		local size = spec[2] * s
		Build.Part({
			Name = "Leaves",
			Size = Vector3.new(size, size, size),
			CFrame = CFrame.new(position + spec[1] * s) * CFrame.Angles(random:NextNumber(-0.5, 0.5), random:NextNumber(0, 1.5), random:NextNumber(-0.5, 0.5)),
			Color = leafColor or LEAF_COLORS[(i % #LEAF_COLORS) + 1],
			Studs = true,
		}, folder)
	end
end

-- Pile de blocs jaunes à tenons (obstacles cubiques)
function MapBase.BuildBlockStack(folder: Instance, position: Vector3, count: number?, color: Color3?)
	local n = count or 3
	for i = 1, n do
		local size = 4
		local offset = Vector3.new(((i - 1) % 2) * size, math.floor((i - 1) / 2) * size + size / 2, 0)
		if i == 3 then
			offset = Vector3.new(size / 2, size * 1.5, 0)
		end
		Build.Part({
			Name = "Block",
			Size = Vector3.new(size, size, size),
			CFrame = CFrame.new(position + offset),
			Color = color or Color3.fromRGB(245, 200, 45),
			Studs = true,
		}, folder)
	end
end

function MapBase.BuildRock(folder: Instance, position: Vector3, size: Vector3, color: Color3?)
	return Build.Part({
		Name = "Rock",
		Size = size,
		CFrame = CFrame.new(position + Vector3.new(0, size.Y / 2 - 0.5, 0)) * CFrame.Angles(random:NextNumber(-0.15, 0.15), random:NextNumber(0, math.pi), random:NextNumber(-0.15, 0.15)),
		Color = color or Color3.fromRGB(140, 135, 130),
		Material = Enum.Material.Slate,
	}, folder)
end

-- Bordure décorative tout autour (clôture) avec ouvertures nulles : la limite
-- invisible fait le reste.
function MapBase.BuildPerimeterFence(folder: Instance, origin: Vector3, size: number, color: Color3?)
	local half = size / 2 - 2
	local corners = {
		origin + Vector3.new(-half, 0, -half),
		origin + Vector3.new(half, 0, -half),
		origin + Vector3.new(half, 0, half),
		origin + Vector3.new(-half, 0, half),
	}
	for i = 1, 4 do
		MapBase.BuildFence(folder, corners[i], corners[i % 4 + 1], color)
	end
end

-- Chemins de terre des camps vers le centre
function MapBase.BuildPaths(folder: Instance, origin: Vector3, bases: { [string]: Base }, color: Color3?, innerRadius: number?)
	for _, base in bases do
		local from = base.Center
		local dir = Vector3.new(origin.X - from.X, 0, origin.Z - from.Z)
		local length = dir.Magnitude - (innerRadius or 10) - base.Radius
		if length <= 2 then
			continue
		end
		local unit = dir.Unit
		local start = from + unit * (base.Radius + 1)
		local mid = start + unit * (length / 2)
		Build.Part({
			Name = "Path",
			Size = Vector3.new(10, 0.16, length),
			CFrame = CFrame.lookAt(mid + Vector3.new(0, 0.08, 0), mid + unit + Vector3.new(0, 0.08, 0)),
			Color = color or Color3.fromRGB(205, 165, 105),
			Studs = true,
			CanCollide = false,
		}, folder)
		-- Bordures de petits pavés
		for k = 0, math.floor(length / 6) do
			for _, side in { -1, 1 } do
				local p = start + unit * (k * 6 + 3) + Vector3.new(-unit.Z, 0, unit.X) * side * 5.6
				Build.Part({ Name = "PathStone", Size = Vector3.new(1.2, 0.5, 1.2), CFrame = CFrame.new(p + Vector3.new(0, 0.25, 0)) * CFrame.Angles(0, k, 0), Color = Color3.fromRGB(165, 165, 175), CanCollide = false, CanQuery = false }, folder)
			end
		end
	end
end

-- Plaques d'herbe d'une teinte différente pour casser l'aplat du sol
function MapBase.BuildGrassPatches(folder: Instance, origin: Vector3, size: number, color: Color3, count: number)
	local half = size / 2 - 20
	for i = 1, count do
		local p = origin + Vector3.new(random:NextNumber(-half, half), 0.03, random:NextNumber(-half, half))
		local w = random:NextNumber(14, 30)
		Build.Part({
			Name = "GrassPatch",
			Size = Vector3.new(w, 0.05, w * random:NextNumber(0.6, 1)),
			CFrame = CFrame.new(p) * CFrame.Angles(0, random:NextNumber(0, math.pi), 0),
			Color = color:Lerp(Color3.new(1, 1, 1), (i % 3) * 0.04),
			Studs = true,
			CanCollide = false,
			CanQuery = false,
		}, folder)
	end
end

-- Massif de fleurs (petits cubes colorés, décoratif)
local FLOWER_COLORS = {
	Color3.fromRGB(255, 80, 90), Color3.fromRGB(255, 220, 70), Color3.fromRGB(255, 255, 255),
	Color3.fromRGB(190, 110, 255), Color3.fromRGB(255, 150, 200),
}
function MapBase.BuildFlowers(folder: Instance, center: Vector3, count: number?, radius: number?)
	local r = radius or 4
	for _ = 1, count or 8 do
		local a = random:NextNumber(0, math.pi * 2)
		local d = math.sqrt(random:NextNumber()) * r
		local p = center + Vector3.new(math.cos(a) * d, 0, math.sin(a) * d)
		Build.Part({ Name = "Stem", Size = Vector3.new(0.2, 1.1, 0.2), Position = p + Vector3.new(0, 0.55, 0), Color = Color3.fromRGB(60, 140, 50), CanCollide = false, CanQuery = false, CastShadow = false }, folder)
		Build.Part({ Name = "Flower", Size = Vector3.new(0.8, 0.8, 0.8), CFrame = CFrame.new(p + Vector3.new(0, 1.3, 0)) * CFrame.Angles(0, a, 0.4), Color = FLOWER_COLORS[random:NextInteger(1, #FLOWER_COLORS)], CanCollide = false, CanQuery = false, CastShadow = false, Accent = true }, folder)
	end
end

-- Lampadaire (lanterne chaude)
function MapBase.BuildLamp(folder: Instance, position: Vector3)
	Build.Part({ Name = "LampPost", Size = Vector3.new(0.8, 11, 0.8), Position = position + Vector3.new(0, 5.5, 0), Color = Color3.fromRGB(50, 55, 65), Material = Enum.Material.Metal }, folder)
	Build.Part({ Name = "LampArm", Size = Vector3.new(0.5, 0.5, 2.6), Position = position + Vector3.new(0, 10.8, 1.1), Color = Color3.fromRGB(50, 55, 65), Material = Enum.Material.Metal }, folder)
	local lantern = Build.Part({ Name = "Lantern", Size = Vector3.new(1.4, 1.8, 1.4), Position = position + Vector3.new(0, 9.8, 2.2), Color = Color3.fromRGB(255, 200, 110), Material = Enum.Material.Neon, CanCollide = false }, folder)
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 200, 120)
	light.Range = 18
	light.Brightness = 1.2
	light.Parent = lantern
end

-- Environnement autour de la zone de jeu : sol extérieur, collines en gradins et
-- arbres en couronne (la map ne flotte plus dans le ciel, l'horizon est rempli).
export type SurroundTheme = {
	Ground: Color3,
	Hill: Color3,
	HillTop: Color3?,
	Trees: boolean?,
	TreeColor: Color3?,
	Material: Enum.Material?,
}
function MapBase.BuildSurroundings(folder: Instance, origin: Vector3, size: number, theme: SurroundTheme)
	local outer = Build.Part({
		Name = "OuterGround",
		Size = Vector3.new(size * 6, 2, size * 6),
		Position = origin + Vector3.new(0, -1.08, 0),
		Color = theme.Ground,
		Studs = theme.Material == nil,
		CanQuery = false,
	}, folder)
	if theme.Material then
		outer.Material = theme.Material
	end
	local half = size / 2
	local count = 28
	for i = 0, count - 1 do
		local a = i / count * math.pi * 2 + random:NextNumber(-0.05, 0.05)
		local dist = half * math.sqrt(2) + random:NextNumber(30, 70)
		local base = origin + Vector3.new(math.cos(a) * dist, 0, math.sin(a) * dist)
		local w = random:NextNumber(50, 80)
		local h = random:NextNumber(14, 34)
		local cf = CFrame.lookAt(base, Vector3.new(origin.X, base.Y, origin.Z))
		-- Colline en 3 gradins
		for step = 0, 2 do
			local k = 1 - step * 0.28
			Build.Part({
				Name = "Hill",
				Size = Vector3.new(w * k, h / 3, w * 0.7 * k),
				CFrame = cf * CFrame.new(0, h / 6 + step * h / 3, step * 3),
				Color = (step == 2 and theme.HillTop or theme.Hill):Lerp(Color3.new(0, 0, 0), step * 0.04),
				Studs = theme.Material == nil,
				CanQuery = false,
			}, folder)
		end
		if theme.Trees and i % 2 == 0 then
			MapBase.BuildTree(folder, base + cf.LookVector * (w * 0.45), random:NextNumber(0.9, 1.3), theme.TreeColor)
		end
	end
end

-- ---------------------------------------------------------------------------
-- Mécanismes tournants
-- ---------------------------------------------------------------------------

-- Crée un modèle "spinner" dont le pivot est le centre de rotation.
-- Les Parts ajoutées au modèle tournent avec lui (animation côté client).
function MapBase.NewSpinner(folder: Instance, name: string, pivot: CFrame): Model
	local model = Instance.new("Model")
	model.Name = name
	local anchor = Build.Part({
		Name = "Pivot",
		Size = Vector3.new(0.2, 0.2, 0.2),
		CFrame = pivot,
		Transparency = 1,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
	}, model)
	model.PrimaryPart = anchor
	model:SetAttribute("SpinBase", pivot)
	model.Parent = folder
	return model
end

function MapBase.StartSpinner(model: Model, speed: number)
	Mechanics.SetSpin(model, speed, 0)
	CollectionService:AddTag(model, Mechanics.SpinnerTag)
end

return MapBase

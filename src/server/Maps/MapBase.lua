--[[
	MapBase.lua
	Système commun à toutes les maps. Une map décrit son THÈME (relief, sol,
	chemins, clôture, végétation, style des camps) et MapBase construit tout ce
	qui est partagé :

	  MapBase.BuildArena(folder, origin, cfg, theme) -> bases
	    - sol de jeu plat en Terrain + plaques de matières variées
	    - vallée autour (talus, collines, montagnes, rochers) et arbres
	    - limites invisibles + clôture décorative du thème
	    - trois camps d'équipe en triangle (couleurs d'équipe, balise visible
	      de loin, points d'apparition)
	    - chemins des camps vers le centre et anneau de course
	  MapBase.ClearArena(origin)   -> efface le terrain de la map (appelé par
	                                  RoundService au nettoyage, pour toutes les maps)

	La map ne construit ensuite QUE ce qui lui est propre : ses lieux, son
	mécanisme et son mode de jeu. Les briques réutilisables (cachettes,
	mécanismes tournants) sont aussi ici ; les décors sont dans Util/Props.
]]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Teams = require(Shared.Teams)
local Config = require(Shared.Config)
local Mechanics = require(Shared.Mechanics)
local Build = require(script.Parent.Parent.Util.Build)
local Props = require(script.Parent.Parent.Util.Props)
local TerrainKit = require(script.Parent.Parent.Util.TerrainKit)

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

-- Thème d'une map (voir BuildArena)
export type ArenaTheme = {
	Seed: number,
	Floor: Enum.Material, -- matière du sol de jeu
	Patches: { Enum.Material }?, -- plaques de matière pour casser l'aplat
	PatchCount: number?,
	Path: Enum.Material, -- chemins
	PathWidth: number?,
	RingPath: number?, -- rayon de l'anneau de course autour du centre (nil = pas d'anneau)
	CenterRadius: number?, -- les chemins s'arrêtent à ce rayon du centre
	Valley: TerrainKit.ValleyTheme,
	Perimeter: string?, -- "Fence" | "Picket" | "Hedge" | "StoneWall" | "Rocks" | "None"
	PerimeterColor: Color3?,
	Trees: { string }?, -- styles d'arbres (Props.Tree)
	TreeCount: number?,
	TreeScale: number?,
	Camp: CampTheme?,
	TerrainColors: { [string]: Color3 }?, -- couleurs de matières propres à la map
}

export type CampTheme = {
	Wall: Enum.Material?, -- matière des murets du camp
	WallColor: Color3?, -- sinon couleur foncée de l'équipe
	Ground: Enum.Material?, -- terrain sous le camp
}

-- Angles (degrés) des trois bases autour du centre
MapBase.BaseAngles = { FOX = 90, CHICKEN = 210, SNAKE = 330 }

local random = Random.new()

function MapBase.NewFolder(name: string): Folder
	local folder = Instance.new("Folder")
	folder.Name = name
	return folder
end

-- Graine commune (décors identiques d'une manche à l'autre)
function MapBase.Seed(seed: number)
	random = Random.new(seed)
	Props.Seed(seed)
end

function MapBase.Random(): Random
	return random
end

-- Position polaire autour d'un centre (angle en degrés, sens de BaseAngles)
function MapBase.Polar(origin: Vector3, degrees: number, radius: number): Vector3
	local a = math.rad(degrees)
	return origin + Vector3.new(math.cos(a) * radius, 0, math.sin(a) * radius)
end

-- ---------------------------------------------------------------------------
-- Sol, limites, vallée
-- ---------------------------------------------------------------------------

-- Taille totale de la région de terrain d'une map (pour ClearArena)
local ARENA_EXTENT = 1600
local ARENA_HEIGHT = 320

function MapBase.ClearArena(origin: Vector3)
	TerrainKit.Clear(origin + Vector3.new(0, ARENA_HEIGHT / 2 - 40, 0), Vector3.new(ARENA_EXTENT, ARENA_HEIGHT, ARENA_EXTENT))
	TerrainKit.ApplyPalette()
end

-- Murs invisibles (et pas de plafond) pour qu'on ne sorte pas de la map.
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

-- Clôture décorative tout autour, selon le style du thème
function MapBase.BuildPerimeter(folder: Instance, origin: Vector3, size: number, style: string?, color: Color3?)
	if style == nil or style == "None" then
		return
	end
	local half = size / 2 - 2
	local corners = {
		origin + Vector3.new(-half, 0, -half),
		origin + Vector3.new(half, 0, -half),
		origin + Vector3.new(half, 0, half),
		origin + Vector3.new(-half, 0, half),
	}
	for i = 1, 4 do
		local a, b = corners[i], corners[i % 4 + 1]
		if style == "Fence" then
			Props.Fence(folder, a, b, color)
		elseif style == "Picket" then
			Props.PicketFence(folder, a, b, color)
		elseif style == "Hedge" then
			Props.Hedge(folder, a, b, 5, color)
		elseif style == "StoneWall" then
			Props.StoneWall(folder, a, b, 3, color)
		elseif style == "Rocks" then
			local delta = b - a
			local n = math.floor(delta.Magnitude / 9)
			for k = 0, n do
				Props.Rock(folder, a + delta * (k / n), random:NextNumber(4, 7), color)
			end
		end
	end
end

-- Arbres posés sur le relief autour de la zone de jeu
local function plantSurroundingTrees(folder: Instance, origin: Vector3, size: number, theme: ArenaTheme)
	local count = theme.TreeCount or 60
	local kinds = theme.Trees or { "Block", "Round", "Pine" }
	local ring1, ring2 = TerrainKit.ValleyRing(size, theme.Valley.Gap)
	local half = size / 2
	for i = 1, count do
		local a = random:NextNumber(0, math.pi * 2)
		-- Distance : dans la bande entre la clôture et les grandes collines
		local edge = half / math.max(math.abs(math.cos(a)), math.abs(math.sin(a)))
		local inner = math.min(edge + 8, ring1 - 10)
		local d = random:NextNumber(inner, ring2 + 20)
		local p = origin + Vector3.new(math.cos(a) * d, 0, math.sin(a) * d)
		local ground = TerrainKit.Ground(p)
		Props.Tree(folder, ground - Vector3.new(0, 0.6, 0), (theme.TreeScale or 1) * random:NextNumber(0.85, 1.35), kinds)
	end
end

-- ---------------------------------------------------------------------------
-- Camps d'équipe
-- ---------------------------------------------------------------------------

-- Position d'une base (angle en degrés autour du centre ; angles propres à la
-- map si fournis, sinon MapBase.BaseAngles)
function MapBase.BasePosition(origin: Vector3, teamId: string, radius: number, angles: { [string]: number }?): Vector3
	local list = angles or MapBase.BaseAngles
	return MapBase.Polar(origin, list[teamId] or MapBase.BaseAngles[teamId], radius)
end

-- Trois camps disposés en triangle. Retourne bases[teamId].
function MapBase.BuildBases(folder: Instance, origin: Vector3, radius: number, padSize: number, camp: CampTheme?, angles: { [string]: number }?): { [string]: Base }
	local bases = {}
	local style: CampTheme = camp or {}
	for _, teamId in Teams.Order do
		local def = Teams.Get(teamId)
		assert(def)
		local center = MapBase.BasePosition(origin, teamId, radius, angles)
		local facing = CFrame.lookAt(center, Vector3.new(origin.X, center.Y, origin.Z))
		local rotation = facing - facing.Position
		local model = Instance.new("Model")
		model.Name = teamId .. "_Camp"

		local halfPad = padSize / 2
		local function at(x: number, y: number, z: number): CFrame
			return CFrame.new(center) * rotation * CFrame.new(x, y, z)
		end
		local light = def.Color:Lerp(Color3.new(1, 1, 1), 0.4)
		local wallColor = style.WallColor or def.DarkColor
		local wallMaterial = style.Wall or Enum.Material.WoodPlanks

		-- Terrain du camp (sous la plateforme)
		if style.Ground then
			TerrainKit.Paint(facing, padSize + 16, padSize + 16, origin.Y, style.Ground)
		end

		-- Plateforme (couleur d'équipe) et bordure
		local pad = Build.Part({
			Name = teamId .. "_BasePad",
			Size = Vector3.new(padSize, 1, padSize),
			CFrame = at(0, 0.5, 0),
			Color = def.Color,
			Studs = true,
			Accent = true,
		}, model)
		pad:SetAttribute("Team", teamId)
		pad:SetAttribute("BasePad", true)
		Build.Part({ Name = "BaseBorder", Size = Vector3.new(padSize + 3, 0.7, padSize + 3), CFrame = at(0, 0.35, 0), Color = def.DarkColor, Accent = true }, model)
		-- Emblème au sol : disque clair avec le nom de l'équipe (lisible d'en haut)
		Build.Part({ Name = "Emblem", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.12, 16, 16), CFrame = at(0, 1.02, 0) * CFrame.Angles(0, 0, math.rad(90)), Color = light, Accent = true, CanCollide = false, CanQuery = false }, model)
		local label = Build.Part({ Name = "EmblemText", Size = Vector3.new(14, 0.05, 5), CFrame = at(0, 1.1, 0) * CFrame.Angles(0, math.pi, 0), Transparency = 1, CanCollide = false, CanQuery = false }, model)
		Build.SurfaceLabel(label, Enum.NormalId.Top, def.Display, { TextColor3 = def.DarkColor, TextStrokeTransparency = 1, Font = Enum.Font.GothamBlack })

		-- Arche d'entrée tournée vers le centre, bannière du camp
		local front = -halfPad + 1.5
		for _, side in { -1, 1 } do
			Build.Part({ Name = "ArchPillar", Size = Vector3.new(3, 12, 3), CFrame = at(side * 9.5, 6.5, front), Color = wallColor, Material = wallMaterial, Accent = style.WallColor == nil }, model)
			Build.Part({ Name = "ArchBase", Size = Vector3.new(4, 1.2, 4), CFrame = at(side * 9.5, 1.1, front), Color = def.DarkColor, Accent = true }, model)
			Build.Part({ Name = "ArchCap", Size = Vector3.new(4.2, 1.2, 4.2), CFrame = at(side * 9.5, 13.1, front), Color = def.Color, Accent = true }, model)
			local lamp = Build.Part({ Name = "ArchLamp", Shape = Enum.PartType.Ball, Size = Vector3.new(2, 2, 2), CFrame = at(side * 9.5, 14.6, front), Color = light, Material = Enum.Material.Neon, Accent = true, CanCollide = false }, model)
			local glow = Instance.new("PointLight")
			glow.Color = def.Color
			glow.Range = 14
			glow.Brightness = 0.8
			glow.Parent = lamp
		end
		local beam = Build.Part({ Name = teamId .. "_ArchBeam", Size = Vector3.new(23, 3.6, 1.6), CFrame = at(0, 11.2, front), Color = def.DarkColor, Accent = true }, model)
		for _, face in { Enum.NormalId.Front, Enum.NormalId.Back } do
			Build.SurfaceLabel(beam, face, def.Display .. " CAMP", { TextColor3 = Color3.new(1, 1, 1), TextStrokeTransparency = 0.3, Font = Enum.Font.GothamBlack })
		end
		Props.Bunting(model, (at(-9.5, 9.4, front - 0.4)).Position, (at(9.5, 9.4, front - 0.4)).Position, { def.Color, Color3.new(1, 1, 1) }, 1.4)

		-- Murets : arrière complet, côtés partiels (on entre par l'avant et les côtés)
		local function wall(cf: CFrame, size: Vector3)
			Build.Part({ Name = "CampWall", Size = size, CFrame = cf, Color = wallColor, Material = wallMaterial, Accent = style.WallColor == nil }, model)
			Build.Part({ Name = "CampWallCap", Size = size + Vector3.new(0.5, -size.Y + 0.5, 0.5), CFrame = cf * CFrame.new(0, size.Y / 2 + 0.25, 0), Color = def.Color, Accent = true }, model)
		end
		wall(at(0, 1.75, halfPad + 1.5), Vector3.new(padSize + 3, 3.5, 2))
		for _, side in { -1, 1 } do
			wall(at(side * (halfPad + 1.5), 1.75, halfPad * 0.55), Vector3.new(2, 3.5, padSize * 0.45))
		end

		-- Balise visible de loin : grand mât, drapeau, anneau lumineux
		local beaconCf = at(0, 0, halfPad + 4)
		Build.Part({ Name = "BeaconBase", Size = Vector3.new(4, 2, 4), CFrame = beaconCf * CFrame.new(0, 1, 0), Color = def.DarkColor, Accent = true }, model)
		Build.Part({ Name = "BeaconPole", Size = Vector3.new(0.9, 30, 0.9), CFrame = beaconCf * CFrame.new(0, 16, 0), Color = Color3.fromRGB(240, 240, 240), Material = Enum.Material.Metal }, model)
		Build.Part({ Name = "BeaconFlag", Size = Vector3.new(10, 6, 0.3), CFrame = beaconCf * CFrame.new(5.4, 27.5, 0), Color = def.Color, Material = Enum.Material.Fabric, Accent = true, CanCollide = false }, model)
		Build.Part({ Name = "BeaconFlagStripe", Size = Vector3.new(10, 1.2, 0.34), CFrame = beaconCf * CFrame.new(5.4, 25.4, 0), Color = Color3.new(1, 1, 1), Accent = true, CanCollide = false }, model)
		local orb = Build.Part({ Name = "BeaconOrb", Shape = Enum.PartType.Ball, Size = Vector3.new(2.4, 2.4, 2.4), CFrame = beaconCf * CFrame.new(0, 31.6, 0), Color = light, Material = Enum.Material.Neon, Accent = true, CanCollide = false }, model)
		local orbLight = Instance.new("PointLight")
		orbLight.Color = def.Color
		orbLight.Range = 20
		orbLight.Brightness = 1
		orbLight.Parent = orb

		-- Tente du camp (toit en pente) et matériel
		local tentCf = at(-halfPad * 0.5, 1, halfPad * 0.55) * CFrame.Angles(0, math.rad(90), 0)
		Props.Roof(model, tentCf, { Width = 8, Depth = 7, Rise = 5.5, Color = def.Color, Gable = light, Overhang = 0.4, Thickness = 0.35 })
		Build.Part({ Name = "TentFloor", Size = Vector3.new(8, 0.2, 7), CFrame = tentCf * CFrame.new(0, 0.1, 0), Color = def.DarkColor, Accent = true, CanCollide = false }, model)
		Props.Crate(model, at(halfPad * 0.55, 1, halfPad * 0.62) * CFrame.Angles(0, 0.3, 0), 3)
		Props.Crate(model, at(halfPad * 0.55 - 3.2, 1, halfPad * 0.66) * CFrame.Angles(0, -0.2, 0), 2.4)
		Props.Barrel(model, (at(halfPad * 0.62, 1, halfPad * 0.2)).Position)

		-- Points d'apparition : cercle au centre de la base, tournés vers le centre de la map
		local spawns = {}
		local spawnCount = 8
		for i = 1, spawnCount do
			local a = (i / spawnCount) * math.pi * 2
			local offset = Vector3.new(math.cos(a) * padSize * 0.25, 0, math.sin(a) * padSize * 0.25)
			local position = center + offset + Vector3.new(0, 1 + Config.World.RespawnHeight, 0)
			table.insert(spawns, CFrame.lookAt(position, Vector3.new(origin.X, position.Y, origin.Z)))
		end

		model.Parent = folder
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

-- Chemins de terrain des camps vers le centre (+ anneau de course)
function MapBase.BuildPaths(origin: Vector3, bases: { [string]: Base }, theme: ArenaTheme)
	local width = theme.PathWidth or 12
	local inner = theme.CenterRadius or 10
	for _, base in bases do
		local dir = Vector3.new(origin.X - base.Center.X, 0, origin.Z - base.Center.Z)
		local length = dir.Magnitude - inner
		if length > 2 then
			local unit = dir.Unit
			local side = Vector3.new(-unit.Z, 0, unit.X)
			-- Léger S pour un tracé naturel
			local points = {}
			for k = 0, 4 do
				local t = k / 4
				local wobble = math.sin(t * math.pi * 2) * 5 * (1 - t)
				table.insert(points, base.Center + unit * (length * t) + side * wobble)
			end
			TerrainKit.Path(points, width, origin.Y, theme.Path)
		end
	end
	if theme.RingPath then
		local points = {}
		for k = 0, 36 do
			local a = k / 36 * math.pi * 2
			table.insert(points, origin + Vector3.new(math.cos(a), 0, math.sin(a)) * theme.RingPath)
		end
		TerrainKit.Path(points, width * 0.8, origin.Y, theme.Path)
	end
end

-- ---------------------------------------------------------------------------
-- Arène complète
-- ---------------------------------------------------------------------------
-- Disposition d'une map (Config.Maps.<Id>) : limites et bases
export type ArenaConfig = {
	GroundSize: number, -- côté de la zone de jeu carrée (limites invisibles)
	BaseRadius: number, -- distance des camps au centre
	BasePadSize: number, -- côté de la plateforme d'un camp
	BaseAngles: { [string]: number }?, -- angle (degrés) de chaque camp ; défaut : 90 / 210 / 330
	BoundaryHeight: number?, -- hauteur des murs invisibles (défaut 90)
}

function MapBase.BuildArena(folder: Instance, origin: Vector3, cfg: ArenaConfig, theme: ArenaTheme): { [string]: Base }
	MapBase.Seed(theme.Seed)
	TerrainKit.ResetRelief(origin.Y)
	local size = cfg.GroundSize
	MapBase.ClearArena(origin)
	TerrainKit.ApplyOverrides(theme.TerrainColors)
	-- Vallée + sol de jeu plat
	if theme.Valley.Style == "Canyon" then
		TerrainKit.Canyon(origin, size, theme.Valley, random)
	else
		TerrainKit.Valley(origin, size, theme.Valley, random)
	end
	TerrainKit.Slab(origin, size + 8, size + 8, origin.Y, 16, theme.Floor)
	-- Plaques de matières (variations du sol)
	if theme.Patches and #theme.Patches > 0 then
		local half = size / 2 - 16
		for i = 1, theme.PatchCount or 18 do
			local p = origin + Vector3.new(random:NextNumber(-half, half), 0, random:NextNumber(-half, half))
			local material = theme.Patches[(i - 1) % #theme.Patches + 1]
			TerrainKit.PaintDisc(p, random:NextNumber(8, 18), origin.Y, material)
		end
	end
	MapBase.BuildBoundary(folder, origin, size, cfg.BoundaryHeight or 90)
	MapBase.BuildPerimeter(folder, origin, size, theme.Perimeter, theme.PerimeterColor)
	local bases = MapBase.BuildBases(folder, origin, cfg.BaseRadius, cfg.BasePadSize, theme.Camp, cfg.BaseAngles)
	MapBase.BuildPaths(origin, bases, theme)
	local trees = Instance.new("Folder")
	trees.Name = "Surroundings"
	trees.Parent = folder
	plantSurroundingTrees(trees, origin, size, theme)
	return bases
end

-- Zone centrale ronde (Part)
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

-- Hautes herbes : massif dense de brins effilés (on peut s'y cacher)
function MapBase.BuildTallGrass(folder: Instance, position: Vector3, radius: number, color: Color3?)
	local base = color or Color3.fromRGB(104, 178, 70)
	local tip = base:Lerp(Color3.fromRGB(226, 220, 110), 0.45)
	local model = Instance.new("Model")
	model.Name = "TallGrass"
	local blades = math.floor(radius * radius * 1.6)
	for _ = 1, blades do
		local a = random:NextNumber(0, math.pi * 2)
		local r = math.sqrt(random:NextNumber()) * radius
		local height = random:NextNumber(5.5, 8) * (1 - r / radius * 0.3)
		local p = position + Vector3.new(math.cos(a) * r, height / 2, math.sin(a) * r)
		Build.Wedge({
			Name = "Blade",
			Size = Vector3.new(0.35, height, random:NextNumber(0.9, 1.4)),
			CFrame = CFrame.new(p) * CFrame.Angles(0, random:NextNumber(0, math.pi * 2), 0) * CFrame.Angles(random:NextNumber(-0.12, 0.12), 0, random:NextNumber(-0.18, 0.18)),
			Color = base:Lerp(tip, random:NextNumber(0, 0.6)),
			CanCollide = false,
			CanQuery = false,
			CanTouch = false,
			CastShadow = false,
		}, model)
	end
	model.Parent = folder
	TerrainKit.PaintDisc(position, radius + 2, position.Y, Enum.Material.LeafyGrass)
	hidingZone(folder, CFrame.new(position + Vector3.new(0, 3, 0)), Vector3.new(radius * 1.8, 6, radius * 1.8), "Grass")
	return model
end

-- Buisson : grosses boules de feuillage, traversable
function MapBase.BuildBush(folder: Instance, position: Vector3, size: number, color: Color3?)
	local model = Props.Bush(folder, position, size, color, true)
	hidingZone(folder, CFrame.new(position + Vector3.new(0, 2.5, 0)), Vector3.new(size * 0.85, 5, size * 0.85), "Bush")
	return model
end

-- Terrier : monticule de terre avec une entrée sombre ; s'y tenir cache le joueur
function MapBase.BuildBurrow(folder: Instance, position: Vector3, color: Color3?)
	local model = Instance.new("Model")
	model.Name = "Burrow"
	local dirt = color or Color3.fromRGB(150, 108, 70)
	for i = 0, 5 do
		local a = i / 6 * math.pi * 2
		local d = 4.6
		Build.Part({
			Name = "Mound",
			Shape = Enum.PartType.Ball,
			Size = Vector3.new(5.5, 3.4, 5.5),
			Position = position + Vector3.new(math.cos(a) * d, 0.6, math.sin(a) * d),
			Color = dirt:Lerp(Color3.new(0, 0, 0), (i % 2) * 0.08),
			Material = Enum.Material.Ground,
			CanCollide = false,
			CanQuery = false,
		}, model)
	end
	Build.VerticalCylinder(position + Vector3.new(0, 0.12, 0), 3.4, 0.2, {
		Name = "Hole",
		Color = Color3.fromRGB(28, 20, 14),
		CanCollide = false,
		CanQuery = false,
	}, model)
	Props.GrassTuft(model, position + Vector3.new(5.5, 0, 2))
	Props.GrassTuft(model, position + Vector3.new(-4.5, 0, -4))
	model.Parent = folder
	hidingZone(folder, CFrame.new(position + Vector3.new(0, 2.5, 0)), Vector3.new(8, 6, 8), "Burrow")
	return model
end

-- ---------------------------------------------------------------------------
-- Raccourcis vers Props (compatibilité)
-- ---------------------------------------------------------------------------
function MapBase.BuildFence(folder: Instance, from: Vector3, to: Vector3, color: Color3?)
	Props.Fence(folder, from, to, color)
end

function MapBase.BuildHayBale(folder: Instance, position: Vector3, yaw: number?)
	Props.HayBale(folder, position, yaw)
end

function MapBase.BuildTree(folder: Instance, position: Vector3, scale: number?, _leafColor: Color3?)
	Props.Tree(folder, position, scale)
end

function MapBase.BuildRock(folder: Instance, position: Vector3, size: Vector3, color: Color3?)
	return Props.Rock(folder, position, math.max(size.X, size.Z), color)
end

function MapBase.BuildFlowers(folder: Instance, center: Vector3, count: number?, radius: number?)
	Props.Flowers(folder, center, count, radius)
end

function MapBase.BuildLamp(folder: Instance, position: Vector3)
	Props.Lamp(folder, position)
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

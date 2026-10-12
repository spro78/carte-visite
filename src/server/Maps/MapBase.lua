--[[
	MapBase.lua
	Système commun à toutes les maps. Une map décrit son THÈME (relief, sol,
	chemins, clôture, végétation, style des camps) et MapBase construit tout ce
	qui est partagé :

	  MapBase.BuildArena(folder, origin, cfg, theme) -> bases
	    - plateau de jeu à tenons en bandes de deux tons (Util/Ground)
	    - terrasses de blocs autour (fond du décor) et arbres en cubes dessus
	    - limites invisibles + clôture décorative du thème
	    - trois camps d'équipe en triangle (couleurs d'équipe, balise visible
	      de loin, points d'apparition) et leur zone sûre (liseré au sol)
	    - chemins des camps vers le centre et anneau de course
	  MapBase.ClearArena(origin)   -> efface un éventuel ancien Terrain de la map
	                                  (appelé par RoundService au nettoyage)
	Direction artistique commune : reference/BIBLE_VISUELLE.md.

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
local Ground = require(script.Parent.Parent.Util.Ground)

local MapBase = {}

MapBase.HidingTag = "HoH_HidingSpot"

-- Zone sûre d'un camp, dans le repère du camp (-Z local = vers le centre de la carte)
export type SafeZone = {
	HalfWidth: number, -- demi-largeur (X local)
	Front: number, -- étendue devant le centre du camp (vers le centre de la carte)
	Back: number, -- étendue derrière le centre du camp
	Height: number, -- hauteur couverte au-dessus du sol
}

export type Base = {
	Team: string,
	Center: Vector3, -- centre de la base (au niveau du sol)
	CFrame: CFrame, -- orienté vers le centre de la map
	Pad: Part,
	Spawns: { CFrame },
	Radius: number, -- demi-côté de la plateforme
	Safe: SafeZone, -- zone où les défenseurs sont protégés (Config.SafeZone)
}

-- Thème d'une map (voir BuildArena et la bible visuelle)
export type ArenaTheme = {
	Seed: number,
	Board: Color3, -- sol de jeu (bandes claires)
	BoardAlt: Color3?, -- bandes foncées (sinon une teinte un peu plus sombre)
	Stripe: number?, -- largeur des bandes (studs)
	Path: Enum.Material, -- chemins (couleur via GroundColors)
	PathWidth: number?,
	RingPath: number?, -- rayon de l'anneau de course autour du centre (nil = pas d'anneau)
	CenterRadius: number?, -- les chemins s'arrêtent à ce rayon du centre
	Backdrop: Ground.BackdropTheme, -- terrasses du fond
	Perimeter: string?, -- "Fence" | "Picket" | "Hedge" | "StoneWall" | "Rocks" | "None"
	PerimeterColor: Color3?,
	Trees: { string }?, -- styles d'arbres (Props.Tree), plantés sur les terrasses
	TreeCount: number?,
	TreeScale: number?,
	Camp: CampTheme?,
	GroundColors: { [string]: Color3 }?, -- couleur de chaque matière logique des aplats
}

export type CampTheme = {
	Wall: Enum.Material?, -- matière des murets du camp
	WallColor: Color3?, -- sinon couleur foncée de l'équipe
	Ground: Enum.Material?, -- aplat sous le camp (matière logique)
}

-- Angles (degrés) des trois bases autour du centre
MapBase.BaseAngles = { FOX = 90, CHICKEN = 210, SNAKE = 330 }

-- Camps de la carte en cours (lus par SafeZoneService et RescueService) ;
-- remis à nil au nettoyage de l'arène
MapBase.ActiveBases = nil :: { [string]: Base }?

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
	MapBase.ActiveBases = nil
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

-- Arbres en cubes plantés sur les terrasses du fond (jamais dans la zone de jeu)
local function plantSurroundingTrees(folder: Instance, theme: ArenaTheme)
	local count = theme.TreeCount or 60
	local kinds = theme.Trees or { "Block" }
	for _, spot in Ground.TerraceSpots(count, random) do
		Props.Tree(folder, spot - Vector3.new(0, 0.2, 0), (theme.TreeScale or 1) * random:NextNumber(0.9, 1.4), kinds)
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

-- Distance (studs) de p jusqu'au bord du carré de demi-côté "half" centré sur
-- origin, en avançant dans la direction d (horizontale, unitaire)
local function distanceToEdge(origin: Vector3, p: Vector3, d: Vector3, half: number): number
	local best = math.huge
	local rx, rz = p.X - origin.X, p.Z - origin.Z
	if math.abs(d.X) > 1e-6 then
		local t = ((d.X > 0 and half or -half) - rx) / d.X
		if t >= 0 then
			best = math.min(best, t)
		end
	end
	if math.abs(d.Z) > 1e-6 then
		local t = ((d.Z > 0 and half or -half) - rz) / d.Z
		if t >= 0 then
			best = math.min(best, t)
		end
	end
	return best
end

-- Zone sûre d'un camp : la plateforme, une marge sur les côtés et devant, et
-- une bande derrière, raccourcie si la limite de la carte est plus proche
local function safeZoneFor(origin: Vector3, facing: CFrame, halfPad: number, bounds: number?): SafeZone
	local cfg = Config.SafeZone
	local halfWidth = halfPad + cfg.SideMargin
	local back = halfPad + cfg.BackDepth
	if bounds then
		local backDir = -Vector3.new(facing.LookVector.X, 0, facing.LookVector.Z).Unit
		local side = Vector3.new(facing.RightVector.X, 0, facing.RightVector.Z).Unit
		local room = math.huge
		for _, offset in { -halfWidth, 0, halfWidth } do
			room = math.min(room, distanceToEdge(origin, facing.Position + side * offset, backDir, bounds - 3))
		end
		back = math.clamp(room - 1, halfPad + 6, back)
	end
	return { HalfWidth = halfWidth, Front = halfPad + cfg.FrontMargin, Back = back, Height = cfg.Height }
end

-- Repère au sol de la zone sûre : liseré pointillé aux couleurs de l'équipe et
-- mention "SAFE ZONE" à l'entrée (visible en approchant du camp)
local function buildSafeZoneMarker(model: Instance, at: (number, number, number) -> CFrame, zone: SafeZone, def: Teams.TeamDef)
	local color = def.Color:Lerp(Color3.new(1, 1, 1), 0.25)
	local w, f, b = zone.HalfWidth, zone.Front, zone.Back
	local corners = { { -w, -f }, { w, -f }, { w, b }, { -w, b } }
	local DASH, GAP = 3, 1.6
	for i = 1, 4 do
		local a, c = corners[i], corners[i % 4 + 1]
		local dx, dz = c[1] - a[1], c[2] - a[2]
		local length = math.sqrt(dx * dx + dz * dz)
		local count = math.max(1, math.floor((length + GAP) / (DASH + GAP)))
		local step = length / count
		for k = 0, count - 1 do
			local t = (k + 0.5) * step / length
			local x, z = a[1] + dx * t, a[2] + dz * t
			local along = math.abs(dx) > math.abs(dz)
			Build.Part({
				Name = "SafeZoneDash",
				Size = along and Vector3.new(DASH, 0.12, 0.8) or Vector3.new(0.8, 0.12, DASH),
				CFrame = at(x, 0.5, z),
				Color = color,
				Accent = true,
				CanCollide = false,
				CanQuery = false,
				CanTouch = false,
				CastShadow = false,
			}, model)
		end
	end
	local label = Build.Part({ Name = "SafeZoneLabel", Size = Vector3.new(14, 0.05, 2.6), CFrame = at(0, 0.6, -(f - 1.5)) * CFrame.Angles(0, math.pi, 0), Transparency = 1, CanCollide = false, CanQuery = false, CanTouch = false }, model)
	Build.SurfaceLabel(label, Enum.NormalId.Top, "SAFE ZONE", { TextColor3 = color, TextStrokeTransparency = 0.4, Font = Enum.Font.FredokaOne })
end

-- Trois camps disposés en triangle. Retourne bases[teamId].
-- bounds : demi-côté de la zone de jeu (limite la profondeur de la zone sûre)
function MapBase.BuildBases(folder: Instance, origin: Vector3, radius: number, padSize: number, camp: CampTheme?, angles: { [string]: number }?, bounds: number?): { [string]: Base }
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

		-- Aplat sous le camp
		if style.Ground then
			Ground.Paint(facing, padSize + 16, padSize + 16, origin.Y, style.Ground)
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

		-- (Pas de tente ni de caisses dans le camp : la caméra du joueur qui
		-- apparaît doit voir la carte, pas le décor ; bible visuelle §4 et §6)

		-- Points d'apparition : cercle au centre de la base, tournés vers le centre de la map
		local spawns = {}
		local spawnCount = 8
		for i = 1, spawnCount do
			local a = (i / spawnCount) * math.pi * 2
			local offset = Vector3.new(math.cos(a) * padSize * 0.25, 0, math.sin(a) * padSize * 0.25)
			local position = center + offset + Vector3.new(0, 1 + Config.World.RespawnHeight, 0)
			table.insert(spawns, CFrame.lookAt(position, Vector3.new(origin.X, position.Y, origin.Z)))
		end

		-- Zone sûre autour et derrière le camp, et son repère au sol
		local zone = safeZoneFor(origin, facing, halfPad, bounds)
		buildSafeZoneMarker(model, at, zone, def)

		model.Parent = folder
		bases[teamId] = {
			Team = teamId,
			Center = center,
			CFrame = facing,
			Pad = pad,
			Spawns = spawns,
			Radius = halfPad,
			Safe = zone,
		}
	end
	MapBase.ActiveBases = bases
	return bases
end

-- Vrai si la position est sur la plateforme de la base (dans son repère).
function MapBase.IsInBase(base: Base, position: Vector3, margin: number?): boolean
	local localPos = base.CFrame:PointToObjectSpace(position)
	local limit = base.Radius + (margin or 0)
	return math.abs(localPos.X) <= limit and math.abs(localPos.Z) <= limit and localPos.Y < 12
end

-- Vrai si la position est dans la zone sûre du camp (autour et derrière la plateforme)
function MapBase.IsInSafeZone(base: Base, position: Vector3): boolean
	local zone = base.Safe
	local p = base.CFrame:PointToObjectSpace(position)
	return math.abs(p.X) <= zone.HalfWidth and p.Z >= -zone.Front and p.Z <= zone.Back and p.Y > -4 and p.Y < zone.Height
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
			Ground.Path(points, width, origin.Y, theme.Path)
		end
	end
	if theme.RingPath then
		local points = {}
		for k = 0, 36 do
			local a = k / 36 * math.pi * 2
			table.insert(points, origin + Vector3.new(math.cos(a), 0, math.sin(a)) * theme.RingPath)
		end
		Ground.Path(points, width * 0.8, origin.Y, theme.Path)
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
	local size = cfg.GroundSize
	MapBase.ClearArena(origin)
	-- Plateau de jeu à tenons + terrasses de blocs autour
	Ground.Begin(folder, origin.Y, theme.GroundColors)
	Ground.Board(origin, size + 8, theme.Board, theme.BoardAlt or theme.Board:Lerp(Color3.new(0, 0, 0), 0.07), theme.Stripe)
	Ground.Terraces(origin, size, theme.Backdrop, random)
	MapBase.BuildBoundary(folder, origin, size, cfg.BoundaryHeight or 90)
	MapBase.BuildPerimeter(folder, origin, size, theme.Perimeter, theme.PerimeterColor)
	local bases = MapBase.BuildBases(folder, origin, cfg.BaseRadius, cfg.BasePadSize, theme.Camp, cfg.BaseAngles, size / 2)
	MapBase.BuildPaths(origin, bases, theme)
	local trees = Instance.new("Folder")
	trees.Name = "Surroundings"
	trees.Parent = folder
	plantSurroundingTrees(trees, theme)
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
	Ground.PaintDisc(position, radius + 2, position.Y, Enum.Material.LeafyGrass)
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

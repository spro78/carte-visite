--[[
	TheCarousel.lua - carte héroïque « Carousel Valley »
	Une vallée de prairie fermée par des collines, un manège au centre dont les
	trois bras portent des chevaux volants qui font le tour de la vallée.
	Tout le décor vient du kit 3D modélisé dans Blender (tools/assets) :
	collines, sols peints, camps, moulin sur sa butte, grange traversable,
	ruisseau et son pont, arbres, rochers, foin, étals.
	Trois modes jouables par tout le serveur (src/server/Modes, ModeInfo) :
	  Chase    : poursuite pure, dernière équipe debout ;
	  EggRun   : œufs peints dans des nids, à ramener dans son camp ;
	  Carousel : les chevaux volants tournent ; être plus nombreux que les
	             autres sous un cheval rapporte des points.
	Disposition (Layouts.CarouselValley, généré depuis Blender) :
	  centre    : place pavée et manège (rayon 15) ;
	  piste     : anneau dégagé à 62 studs, parcouru par les chevaux ;
	  allées    : du centre vers chaque camp (jamais encombrées) ;
	  secteurs  : butte du moulin (30°), grange et foin (150°), ruisseau (270°) ;
	  camps     : renards 90°, poules 210°, vipères 330°, à 110 studs ;
	  horizon   : grande roue sur les collines (292°), montgolfières.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Mechanics = require(Shared.Mechanics)
local Types = require(Shared.Types)
local Layouts = require(Shared.Kit.Layouts)
local Palettes = require(Shared.Kit.Palettes)
local MapBase = require(script.Parent.MapBase)
local Kit = require(script.Parent.Parent.Util.Kit)
local Modes = script.Parent.Parent:WaitForChild("Modes")

type Actor = Types.Actor
type MapContext = Types.MapContext

local Map = {}
Map.Id = "TheCarousel"
Map.Modes = { "Chase", "EggRun", "Carousel" }

-- Plein jour doux : soleil haut, ombres adoucies, brume bleutée au loin
-- (bible visuelle, §2 : lumineux, jamais sombre)
Map.Lighting = {
	ClockTime = 14.3,
	GeographicLatitude = 28,
	Brightness = 3.1,
	Ambient = Color3.fromRGB(96, 100, 112),
	OutdoorAmbient = Color3.fromRGB(168, 172, 184),
	EnvironmentDiffuseScale = 1,
	EnvironmentSpecularScale = 0.35,
	ShadowSoftness = 0.55,
	Atmosphere = { Density = 0.22, Offset = 0.08, Haze = 0.55, Glare = 0, Color = Color3.fromRGB(206, 226, 252), Decay = Color3.fromRGB(140, 176, 226) },
	ColorCorrection = { TintColor = Color3.fromRGB(255, 252, 246), Saturation = 0.1, Contrast = 0.05, Brightness = 0.02 },
	Bloom = { Intensity = 0.35, Size = 22, Threshold = 1.6 },
}

local cfg = Config.Maps.TheCarousel
local L = Layouts.CarouselValley
local PALETTE = "Valley"

local folder: Folder? = nil
local bases: { [string]: MapBase.Base }? = nil
local origin = Vector3.zero
local spinner: Model? = nil
local zones: { Model } = {}
local nests: { Vector3 } = {}
local activeMode: any = nil
local random = Random.new(2203)

-- ---------------------------------------------------------------------------
-- Outils de placement
-- ---------------------------------------------------------------------------
local function polar(degrees: number, radius: number): Vector3
	return MapBase.Polar(origin, degrees, radius)
end

-- Pose un asset au sol, tourné vers un point (ou d'un lacet en degrés)
local function place(parent: Instance, asset: string, position: Vector3, facing: Vector3 | number | nil, options: Kit.PlaceOptions?): Model
	local cframe: CFrame
	if typeof(facing) == "Vector3" then
		local target = Vector3.new(facing.X, position.Y, facing.Z)
		cframe = (target - position).Magnitude > 0.01 and CFrame.lookAt(position, target) or CFrame.new(position)
	else
		cframe = CFrame.new(position) * CFrame.Angles(0, math.rad((facing :: number?) or 0), 0)
	end
	local opts: Kit.PlaceOptions = options or {}
	opts.Palette = opts.Palette or PALETTE
	return Kit.Place(parent, asset, cframe, opts)
end

local function randomYaw(): number
	return random:NextNumber(0, 360)
end

-- Une rangée de segments (clôture, muret) entre deux points
local function row(parent: Instance, asset: string, a: Vector3, b: Vector3, segment: number)
	local delta = b - a
	local length = delta.Magnitude
	local count = math.max(1, math.floor(length / segment + 0.5))
	local step = length / count
	local dir = delta.Unit
	for i = 0, count - 1 do
		local p = a + dir * (step * (i + 0.5))
		local cframe = CFrame.lookAt(p, p + Vector3.new(-dir.Z, 0, dir.X))
		Kit.Place(parent, asset, cframe, { Palette = PALETTE, Scale = step / segment * 1.04, Name = asset })
	end
end

-- ---------------------------------------------------------------------------
-- Sol, collines et limites
-- ---------------------------------------------------------------------------
local function buildGround(f: Folder)
	local floor = Instance.new("Part")
	floor.Name = "ValleyFloor"
	floor.Size = Vector3.new(L.ValleyEdge * 2 + 80, 2, L.ValleyEdge * 2 + 80)
	floor.CFrame = CFrame.new(origin - Vector3.new(0, 1, 0))
	floor.Anchored = true
	floor.Material = Enum.Material.SmoothPlastic
	floor.Color = Palettes.Valley.Grass
	floor.TopSurface = Enum.SurfaceType.Smooth
	floor.BottomSurface = Enum.SurfaceType.Smooth
	floor.Parent = f
	MapBase.BuildBoundary(f, origin, cfg.GroundSize, 90)
	place(f, "ValleyGround", origin, 0, { Collide = false })
	local hills = Instance.new("Folder")
	hills.Name = "Hills"
	hills.Parent = f
	for k = 1, 6 do
		place(hills, "ValleyHills" .. k, origin, 0, { Collide = false })
	end
	-- Arbres des collines : silhouettes lointaines (peu de triangles), quelques
	-- grands arbres au pied des pentes
	local count = 0
	for i, spot in L.HillTrees do
		if count >= 120 then
			break
		end
		local x, y, z, d = spot[1], spot[2], spot[3], spot[4]
		local near = d < 26
		local asset
		if near then
			asset = (i % 3 == 0) and "TreePine" or ((i % 3 == 1) and "TreeOak" or "TreeWide")
		else
			asset = (i % 2 == 0) and "TreeFarPine" or "TreeFarRound"
		end
		place(hills, asset, origin + Vector3.new(x, y, z), randomYaw(), { Collide = false, Scale = random:NextNumber(0.95, 1.35) })
		count += 1
	end
	-- Montgolfières au-dessus des collines (repères mémorables)
	place(hills, "HotAirBalloon", polar(200, 250) + Vector3.new(0, 62, 0), 20, { Collide = false })
	place(hills, "HotAirBalloon", polar(55, 290) + Vector3.new(0, 84, 0), 140, { Collide = false, Scale = 1.2, Roles = { FairRed = Palettes.Valley.FairBlue } })
	-- Grande roue sur les collines, derrière le ruisseau : repère visible des
	-- trois camps, hors de l'aire de jeu (aucune collision)
	place(hills, "BigWheel", origin + L.BigWheel, origin, { Collide = false, Name = "BigWheel" })
end

-- ---------------------------------------------------------------------------
-- Centre : manège, place, guirlandes, étals
-- ---------------------------------------------------------------------------
local RIDE_SADDLES = { Palettes.Valley.FairRed, Palettes.Valley.FairBlue, Palettes.Valley.FairLilac }

local function buildCarousel(f: Folder)
	place(f, "CarouselHub", origin, 0, { Name = "CarouselHub" })
	-- Bras tournants (animés par chaque client, angle publié par le serveur)
	local arms = MapBase.NewSpinner(f, "CarouselArms", CFrame.new(origin))
	table.clear(zones)
	for i = 0, 2 do
		local angle = i * math.pi * 2 / 3
		local base = CFrame.new(origin) * CFrame.Angles(0, angle, 0)
		Kit.Place(arms, "CarouselArm", base, { Palette = PALETTE, Collide = false, Name = "Arm" .. (i + 1), Roles = { Saddle = RIDE_SADDLES[i + 1] } })
		local zone = Kit.Place(arms, "ZoneRing", base * CFrame.new(L.TrackRadius, 0.18, 0), { Palette = PALETTE, Collide = false, Name = "Ride" .. (i + 1) })
		zone:SetAttribute("RideAngle", angle)
		table.insert(zones, zone)
	end
	-- Le manège tourne doucement en permanence (il vit, même hors mode Carousel)
	MapBase.StartSpinner(arms, math.pi * 2 / cfg.AmbientTurnSeconds)
	spinner = arms
end

local function buildPlaza(f: Folder)
	local plaza = Instance.new("Folder")
	plaza.Name = "Plaza"
	plaza.Parent = f
	-- Réverbères autour de la place (jamais dans l'axe d'une allée)
	local lamps = {}
	for i = 0, 8 do
		local deg = 15 + i * 40
		local p = polar(deg, L.PlazaRadius + 1.5)
		place(plaza, "LampPost", p, deg + 90)
		table.insert(lamps, p)
	end
	-- Guirlandes de fanions entre réverbères voisins (à 7 studs : on passe dessous)
	for i = 1, #lamps do
		local a = lamps[i] + Vector3.new(0, 7.6, 0)
		local b = lamps[i % #lamps + 1] + Vector3.new(0, 7.6, 0)
		local mid = (a + b) / 2
		local dir = (b - a)
		local cf = CFrame.lookAt(mid, mid + Vector3.new(-dir.Z, 0, dir.X))
		Kit.Place(plaza, "Bunting", cf, { Palette = PALETTE, Collide = false, Scale = dir.Magnitude / 16 })
	end
	-- Bancs et fleurs au bord de la place
	for _, deg in { 55, 175, 295 } do
		place(plaza, "Bench", polar(deg, L.PlazaRadius + 4), origin)
		place(plaza, "FlowerPatch", polar(deg + 14, L.PlazaRadius + 5), randomYaw(), { Collide = false })
		place(plaza, "FlowerPatch", polar(deg - 14, L.PlazaRadius + 5), randomYaw(), { Collide = false })
	end
	-- Étals de fête entre les allées (couvertures près du centre)
	for k, deg in { 30, 150, 270 } do
		local p = polar(deg, 39)
		place(plaza, "MarketStall", p, origin, { Roles = { FairRed = RIDE_SADDLES[k] } })
		place(plaza, "Barrel", polar(deg + 9, 41), randomYaw())
		place(plaza, "Crate", polar(deg - 9, 42), randomYaw())
	end
	-- Poteaux indicateurs vers les camps, au début de chaque allée
	for _, deg in L.BaseAngles do
		place(plaza, "Signpost", polar(deg + 11, L.PlazaRadius + 7), deg)
	end
end

-- ---------------------------------------------------------------------------
-- Les trois lieux entre les camps
-- ---------------------------------------------------------------------------
local function buildKnoll(f: Folder)
	local spot = polar(L.Knoll.Angle, L.Knoll.Radius)
	local m = Instance.new("Folder")
	m.Name = "WindmillKnoll"
	m.Parent = f
	place(m, "Knoll", spot, origin, { Name = "Knoll" })
	local mill = place(m, "Windmill", spot + Vector3.new(0, L.Knoll.Height, 0), origin, { Name = "Windmill" })
	-- Ailes du moulin : elles tournent autour de l'axe avant (même mécanisme
	-- que le manège : l'axe de rotation est l'axe Y du pivot)
	local millCf = mill:GetPivot()
	local hub = Kit.Anchor("Windmill", "Hub", millCf)
	if hub then
		local base = CFrame.fromMatrix(hub, millCf.RightVector, millCf.LookVector)
		local blades = MapBase.NewSpinner(m, "WindmillBlades", base)
		Kit.Place(blades, "WindmillBlades", base * CFrame.Angles(math.pi / 2, 0, 0), { Palette = PALETTE, Collide = false })
		MapBase.StartSpinner(blades, math.pi * 2 / 7)
	end
	-- Verger au pied de la butte, côté extérieur
	for i, deg in { 14, 22, 38, 46 } do
		place(m, i % 2 == 0 and "TreeBlossom" or "TreeOak", polar(deg, L.Knoll.Radius + 30 + (i % 2) * 6), randomYaw(), { Scale = random:NextNumber(0.9, 1.1) })
	end
	place(m, "HayBale", polar(L.Knoll.Angle - 14, 84), randomYaw())
	place(m, "HayBale", polar(L.Knoll.Angle + 15, 85), randomYaw())
	place(m, "RockMedium", polar(L.Knoll.Angle + 22, 120), randomYaw())
	place(m, "Bush", polar(L.Knoll.Angle - 22, 118), randomYaw())
	MapBase.AddHidingZone(m, CFrame.new(polar(L.Knoll.Angle - 22, 118) + Vector3.new(0, 2.5, 0)), Vector3.new(6, 5, 6), "Bush")
end

local function buildBarn(f: Folder)
	local spot = polar(L.Barn.Angle, L.Barn.Radius)
	local m = Instance.new("Folder")
	m.Name = "BarnYard"
	m.Parent = f
	-- Portes dans l'axe tangent : la grange est un couloir entre deux allées
	local radial = (spot - origin).Unit
	local tangent = Vector3.new(-radial.Z, 0, radial.X)
	place(m, "Barn", spot, spot + tangent, { Name = "Barn" })
	-- Foin et charrette devant les portes, enclos à l'arrière
	place(m, "HayStack", spot + tangent * 26 - radial * 6, randomYaw())
	place(m, "HayStack", spot - tangent * 26 - radial * 4, randomYaw())
	place(m, "HayCart", spot - radial * 20 + tangent * 8, spot + tangent * 40)
	place(m, "HayBale", polar(L.Barn.Angle + 16, 82), randomYaw())
	place(m, "HayBale", polar(L.Barn.Angle - 15, 83), randomYaw())
	place(m, "Well", spot + radial * 24 + tangent * 18, randomYaw())
	local back = spot + radial * 26
	row(m, "Fence", back - tangent * 18, back + tangent * 6, 8.6)
	row(m, "Fence", back + tangent * 6, back + tangent * 6 - radial * 14, 8.6)
	place(m, "TreeWide", spot + radial * 34 - tangent * 22, randomYaw())
	place(m, "TreeOak", spot + radial * 38 + tangent * 26, randomYaw())
end

local function buildCreek(f: Folder)
	local spot = polar(L.Creek.Angle, L.Creek.Radius)
	local m = Instance.new("Folder")
	m.Name = "Creek"
	m.Parent = f
	local radial = (spot - origin).Unit
	local tangent = Vector3.new(-radial.Z, 0, radial.X)
	-- Le ruisseau s'étire le long du cercle ; le pont le franchit vers l'extérieur
	place(m, "Creek", spot, spot - radial, { Name = "Creek" })
	place(m, "Bridge", spot, spot + tangent, { Name = "Bridge" })
	for _, k in { -1, 1 } do
		place(m, "RockLarge", spot + tangent * k * 27 + radial * 2, randomYaw())
		place(m, "RockSmall", spot + tangent * k * 14 - radial * 8, randomYaw(), { Collide = false })
		place(m, "GrassTuft", spot + tangent * k * 18 + radial * 7, randomYaw(), { Collide = false })
		place(m, "GrassTuft", spot + tangent * k * 9 - radial * 7, randomYaw(), { Collide = false })
	end
	place(m, "TreeTall", spot + radial * 16 + tangent * 14, randomYaw())
	place(m, "TreeBlossom", spot + radial * 18 - tangent * 16, randomYaw())
	place(m, "Log", polar(L.Creek.Angle - 14, 83), polar(L.Creek.Angle, 140))
	place(m, "RockMedium", polar(L.Creek.Angle + 15, 82), randomYaw())
	place(m, "Mushrooms", spot + radial * 10 + tangent * 22, randomYaw(), { Collide = false })
end

-- ---------------------------------------------------------------------------
-- Champ autour : couvertures, lisière d'arbres, clôture du domaine
-- ---------------------------------------------------------------------------
-- Vrai si le point gêne une allée, la piste, un camp ou un lieu
local function blocked(p: Vector3, margin: number): boolean
	local rel = Vector3.new(p.X - origin.X, 0, p.Z - origin.Z)
	local r = rel.Magnitude
	if r < L.PlazaRadius + 8 + margin or math.abs(r - L.TrackRadius) < L.TrackWidth / 2 + 4 + margin then
		return true
	end
	local deg = math.deg(math.atan2(rel.Z, rel.X)) % 360
	for _, base in L.BaseAngles do
		local d = math.abs((deg - base + 180) % 360 - 180)
		if d < 90 and r * math.sin(math.rad(d)) < L.LaneWidth / 2 + 5 + margin then
			return true
		end
		if (p - polar(base, L.BaseRadius)).Magnitude < 42 + margin then
			return true
		end
	end
	for _, spot in { L.Knoll, L.Barn, L.Creek } do
		if (p - polar(spot.Angle, spot.Radius)).Magnitude < 30 + margin then
			return true
		end
	end
	return false
end

local COVER = {
	{ "Bush", 0.28 },
	{ "RockMedium", 0.2 },
	{ "HayBale", 0.14 },
	{ "Crate", 0.1 },
	{ "BushFlower", 0.14 },
	{ "StoneWall", 0.14 },
}

local function pick(list: { { any } }): string
	local roll = random:NextNumber()
	local acc = 0
	for _, entry in list do
		acc += entry[2]
		if roll <= acc then
			return entry[1]
		end
	end
	return list[1][1]
end

local function buildField(f: Folder)
	local field = Instance.new("Folder")
	field.Name = "Field"
	field.Parent = f
	-- Couvertures de poursuite entre la piste et les camps (deux par secteur)
	for _, deg in { 30, 150, 270 } do
		for _, offset in { -26, 26 } do
			local p = polar(deg + offset, 84)
			if not blocked(p, -2) then
				local asset = pick(COVER)
				place(field, asset, p, randomYaw())
				if asset == "Bush" or asset == "BushFlower" then
					MapBase.AddHidingZone(field, CFrame.new(p + Vector3.new(0, 2.5, 0)), Vector3.new(6, 5, 6), "Bush")
				end
			end
		end
	end
	-- Lisière : arbres, rochers et buissons jusqu'à la clôture du domaine
	local half = cfg.GroundSize / 2
	local placed = 0
	for _ = 1, 900 do
		if placed >= 70 then
			break
		end
		local p = origin + Vector3.new(random:NextNumber(-half + 6, half - 6), 0, random:NextNumber(-half + 6, half - 6))
		local r = (p - origin).Magnitude
		if r < 118 or blocked(p, 4) then
			continue
		end
		local roll = random:NextNumber()
		local asset
		if roll < 0.18 then
			asset = "TreePine"
		elseif roll < 0.34 then
			asset = "TreeOak"
		elseif roll < 0.46 then
			asset = "TreeWide"
		elseif roll < 0.54 then
			asset = "TreeBlossom"
		elseif roll < 0.62 then
			asset = "TreePineTall"
		elseif roll < 0.74 then
			asset = "Bush"
		elseif roll < 0.82 then
			asset = "RockLarge"
		elseif roll < 0.9 then
			asset = "FlowerPatch"
		else
			asset = "Stump"
		end
		place(field, asset, p, randomYaw(), { Scale = asset:sub(1, 4) == "Tree" and random:NextNumber(0.9, 1.25) or 1, Collide = asset ~= "FlowerPatch" })
		placed += 1
	end
	-- Petits décors partout (sans collision) : touffes, fleurs, champignons
	for _ = 1, 60 do
		local p = origin + Vector3.new(random:NextNumber(-half + 4, half - 4), 0, random:NextNumber(-half + 4, half - 4))
		if not blocked(p, 0) then
			local roll = random:NextNumber()
			place(field, roll < 0.55 and "GrassTuft" or (roll < 0.85 and "FlowerPatch" or "Shrub"), p, randomYaw(), { Collide = false })
		end
	end
	-- Clôture du domaine le long des limites (les murs invisibles sont derrière)
	local fence = Instance.new("Folder")
	fence.Name = "Perimeter"
	fence.Parent = f
	local e = half - 1.5
	local corners = { origin + Vector3.new(-e, 0, -e), origin + Vector3.new(e, 0, -e), origin + Vector3.new(e, 0, e), origin + Vector3.new(-e, 0, e) }
	for i = 1, 4 do
		row(fence, "Fence", corners[i], corners[i % 4 + 1], 8.6)
	end
end

-- ---------------------------------------------------------------------------
-- Nids (mode Egg Run) : un par lieu, devant lui, entre deux camps
-- ---------------------------------------------------------------------------
local function buildNests(f: Folder)
	table.clear(nests)
	for _, deg in { L.Knoll.Angle, L.Barn.Angle, L.Creek.Angle } do
		local p = polar(deg, cfg.NestRadius)
		place(f, "Nest", p, randomYaw(), { Collide = false, Name = "Nest" })
		table.insert(nests, p)
	end
end

-- ---------------------------------------------------------------------------
-- Construction
-- ---------------------------------------------------------------------------
function Map.Build(mapOrigin: Vector3, _context: MapContext)
	origin = mapOrigin
	random = Random.new(2203)
	local f = MapBase.NewFolder("Map_" .. Map.Id)
	MapBase.ClearArena(origin)
	buildGround(f)
	bases = MapBase.BuildBases(f, origin, cfg.BaseRadius, cfg.BasePadSize, { Kit = true }, nil, cfg.GroundSize / 2)
	buildCarousel(f)
	buildPlaza(f)
	buildKnoll(f)
	buildBarn(f)
	buildCreek(f)
	buildField(f)
	buildNests(f)
	f.Parent = workspace
	folder = f
	-- Bilan dans la sortie (Studio : premier contrôle du protocole de test)
	local assets, colliders = 0, 0
	for _, item in f:GetDescendants() do
		if item:IsA("Model") and item:GetAttribute("KitAsset") ~= nil then
			assets += 1
		elseif item.Name == "KitCollider" then
			colliders += 1
		end
	end
	print(string.format("[Carousel Valley] carte construite : %d assets du kit, %d volumes de collision", assets, colliders))
	-- Contrôle physique réel (sortie) : apparitions, bordure, piste des chevaux
	task.delay(1, function()
		if folder ~= f or not bases then
			return
		end
		MapBase.SelfCheck("Carousel Valley", origin, cfg.GroundSize / 2, f, bases, function(report, problems)
			local _, overlap = MapBase.ClearanceParams()
			local free = 0
			for k = 0, 71 do
				local a = k / 72 * math.pi * 2
				local p = origin + Vector3.new(math.cos(a), 0, math.sin(a)) * L.TrackRadius + Vector3.new(0, 3.5, 0)
				local hits = workspace:GetPartBoundsInBox(CFrame.new(p), Vector3.new(3, 5, 3), overlap)
				if #hits == 0 then
					free += 1
				else
					table.insert(problems, string.format("piste gênée à %d° par %s", k * 5, hits[1].Name))
				end
			end
			table.insert(report, string.format("piste libre %d/72", free))
		end)
	end)
end

function Map.GetSpawns(teamId: string): { CFrame }
	assert(bases, "Map non construite")
	return bases[teamId].Spawns
end

-- ---------------------------------------------------------------------------
-- Modes : la carte fournit ses repères, le module du mode fait la règle
-- ---------------------------------------------------------------------------
local function layout()
	return {
		Origin = origin,
		Folder = folder,
		Bases = bases,
		Spinner = spinner,
		Zones = zones,
		TrackRadius = L.TrackRadius,
		Nests = nests,
		AmbientSpeed = math.pi * 2 / cfg.AmbientTurnSeconds,
		HalfSize = cfg.GroundSize / 2,
	}
end

function Map.StartMode(ctx: MapContext, modeId: string?)
	local id = modeId or "Carousel"
	local module = Modes:FindFirstChild(id)
	assert(module and module:IsA("ModuleScript"), "Mode inconnu : " .. tostring(id))
	activeMode = (require :: any)(module)
	-- Les anneaux sous les chevaux ne servent qu'au mode Carousel : ailleurs,
	-- les chevaux tournent seuls (décor vivant), sans zone au sol
	if id ~= "Carousel" then
		for _, zone in zones do
			zone:Destroy()
		end
		table.clear(zones)
	end
	activeMode.Start(ctx, layout())
end

function Map.StopMode()
	if activeMode then
		activeMode.Stop()
	end
	if spinner then
		Mechanics.SetSpin(spinner, math.pi * 2 / cfg.AmbientTurnSeconds)
	end
end

function Map.Cleanup()
	Map.StopMode()
	activeMode = nil
	if folder then
		folder:Destroy()
		folder = nil
	end
	spinner = nil
	bases = nil
	table.clear(zones)
	table.clear(nests)
end

function Map.OnCapture(hunter: Actor, victim: Actor)
	if activeMode and activeMode.OnCapture then
		activeMode.OnCapture(hunter, victim)
	end
end

function Map.OnActorRemoved(actor: Actor)
	if activeMode and activeMode.OnActorRemoved then
		activeMode.OnActorRemoved(actor)
	end
end

function Map.ResolveTimeUp(): string?
	if activeMode and activeMode.ResolveTimeUp then
		return activeMode.ResolveTimeUp()
	end
	return nil
end

function Map.GetBotGoal(actor: Actor): Vector3?
	if activeMode and activeMode.GetBotGoal then
		return activeMode.GetBotGoal(actor)
	end
	return nil
end

function Map.IsCarrier(actor: Actor): boolean
	if activeMode and activeMode.IsCarrier then
		return activeMode.IsCarrier(actor)
	end
	return false
end

function Map.DebugState()
	return {
		Spinner = spinner,
		Zones = zones,
		Nests = nests,
		Mode = activeMode and activeMode.DebugState and activeMode.DebugState() or nil,
	}
end

return Map

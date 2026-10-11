--[[
	TheCarousel.lua - mode "King of the Wheel"
	  - Une grande plateforme tourne au centre. Chaque seconde, l'équipe qui a
	    le plus de membres dessus gagne 1 point. Première à 100 gagne.
	  - Mécanisme : la plateforme accélère par paliers, puis éjecte tout le monde
	    et repart lentement.
	Thème : "Sunset Fair", fête foraine au soleil couchant (grande roue,
	chapiteau traversable, allée des jeux, autos tamponneuses, tour de chute).
]]

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Teams = require(Shared.Teams)
local Mechanics = require(Shared.Mechanics)
local Types = require(Shared.Types)
local MapBase = require(script.Parent.MapBase)
local Build = require(script.Parent.Parent.Util.Build)
local Props = require(script.Parent.Parent.Util.Props)
local Ground = require(script.Parent.Parent.Util.Ground)

type Actor = Types.Actor
type MapContext = Types.MapContext

local Map = {}
Map.Id = "TheCarousel"
-- Après-midi doré mais bien clair (bible visuelle, §2 : jamais de carte sombre)
Map.Lighting = {
	ClockTime = 16.1,
	Brightness = 2.9,
	OutdoorAmbient = Color3.fromRGB(170, 158, 160),
	Atmosphere = { Density = 0.22, Haze = 0.9, Color = Color3.fromRGB(255, 226, 200), Decay = Color3.fromRGB(240, 170, 140) },
	ColorCorrection = { TintColor = Color3.fromRGB(255, 246, 236), Saturation = 0.16, Contrast = 0.06 },
}

local cfg = Config.Maps.TheCarousel
-- Rayures de fête : rouge, bleu, menthe et crème (pas de jaune : couleur des poules)
local STRIPES = {
	Color3.fromRGB(235, 70, 90), Color3.fromRGB(250, 245, 235), Color3.fromRGB(90, 160, 235),
	Color3.fromRGB(250, 245, 235), Color3.fromRGB(96, 206, 172), Color3.fromRGB(250, 245, 235),
}

-- Pelouse claire de fête, allées crème, terrasses gris-bleu à cerisiers
local THEME: MapBase.ArenaTheme = {
	Seed = 2203,
	Board = Color3.fromRGB(116, 198, 98),
	BoardAlt = Color3.fromRGB(104, 184, 88),
	Path = Enum.Material.Brick,
	PathWidth = 12,
	RingPath = 84,
	CenterRadius = 50,
	Backdrop = { Side = Color3.fromRGB(122, 136, 172), Top = Color3.fromRGB(104, 186, 90), Heights = { 12, 24, 42 } },
	Perimeter = "Picket",
	Trees = { "Blossom", "Blossom", "Green" },
	TreeCount = 80,
	Camp = { Wall = Enum.Material.SmoothPlastic },
	GroundColors = {
		Brick = Color3.fromRGB(236, 224, 202), -- allées crème
		Pavement = Color3.fromRGB(246, 240, 228), -- place du manège
		Sand = Color3.fromRGB(232, 214, 176), -- sciure du chapiteau
		LeafyGrass = Color3.fromRGB(84, 166, 76),
	},
}

local folder: Folder? = nil
local bases: { [string]: MapBase.Base }? = nil
local origin = Vector3.zero
local context: MapContext? = nil
local running = false
local connection: RBXScriptConnection? = nil
local wheel: Model? = nil
local scoreAccumulator = 0
local onPlatform: { [string]: boolean } = {}
local cycleThread: thread? = nil

-- ---------------------------------------------------------------------------
-- Construction
-- ---------------------------------------------------------------------------
local CREAM = Color3.fromRGB(252, 246, 234)
local RED = Color3.fromRGB(232, 64, 84)
local BLUE = Color3.fromRGB(70, 150, 236)
local GOLD = Color3.fromRGB(255, 200, 60)
local MINT = Color3.fromRGB(96, 214, 176)
-- Rose de fête (le violet est réservé aux vipères)
local PINK = Color3.fromRGB(240, 120, 170)

local function deco(props: { [string]: any }): { [string]: any }
	props.CanCollide = false
	props.CanQuery = false
	return props
end

-- Ampoule lumineuse (Neon + petite lumière ponctuelle optionnelle)
local function bulb(parent: Instance, position: Vector3, color: Color3, size: number?, light: boolean?)
	local s = size or 0.8
	local part = Build.Part(deco({ Name = "Bulb", Shape = Enum.PartType.Ball, Size = Vector3.new(s, s, s), Position = position, Color = color, Material = Enum.Material.Neon, CastShadow = false }), parent)
	if light then
		local point = Instance.new("PointLight")
		point.Color = color
		point.Range = 12
		point.Brightness = 0.7
		point.Parent = part
	end
	return part
end

-- Guirlande d'ampoules affaissée entre deux points
local function buildLightString(parent: Instance, a: Vector3, b: Vector3, count: number)
	local prev = a
	for i = 1, count do
		local t = i / count
		local p = a:Lerp(b, t) - Vector3.new(0, math.sin(t * math.pi) * 2.5, 0)
		local mid = (prev + p) / 2
		Build.Part(deco({ Name = "Wire", Size = Vector3.new(0.08, 0.08, (p - prev).Magnitude), CFrame = CFrame.lookAt(mid, p), Color = Color3.fromRGB(40, 40, 46), CastShadow = false }), parent)
		bulb(parent, p - Vector3.new(0, 0.4, 0), STRIPES[(i % #STRIPES) + 1], 0.7, false)
		prev = p
	end
end

-- Mât de guirlandes (poteau rayé + boule dorée)
local function buildMast(parent: Instance, ground: Vector3, height: number)
	for k = 0, math.floor(height / 2) - 1 do
		Build.Part({ Name = "MastSegment", Size = Vector3.new(0.7, 2, 0.7), Position = ground + Vector3.new(0, 1 + k * 2, 0), Color = k % 2 == 0 and RED or CREAM }, parent)
	end
	Build.Part(deco({ Name = "MastTop", Shape = Enum.PartType.Ball, Size = Vector3.new(1.4, 1.4, 1.4), Position = ground + Vector3.new(0, height + 0.4, 0), Color = GOLD, Material = Enum.Material.Metal }), parent)
end

-- Grande roue (repère visible de toute la map)
local function buildFerrisWheel(parent: Instance, position: Vector3, yaw: number)
	local base = CFrame.new(position) * CFrame.Angles(0, yaw, 0)
	local radius = 26
	local axle = base * CFrame.new(0, radius + 7, 0)
	Build.Part({ Name = "FerrisDeck", Size = Vector3.new(22, 1.2, 12), CFrame = base * CFrame.new(0, 0.6, 0), Color = Color3.fromRGB(70, 74, 92), Material = Enum.Material.DiamondPlate }, parent)
	for _, side in { -1, 1 } do
		for _, lean in { -1, 1 } do
			Build.Part({ Name = "FerrisLeg", Size = Vector3.new(1.6, radius + 10, 1.6), CFrame = axle * CFrame.new(lean * 8, -(radius + 7) / 2, side * 3.5) * CFrame.Angles(0, 0, math.rad(lean * -15)), Color = CREAM, Material = Enum.Material.Metal }, parent)
		end
		Build.Part(deco({ Name = "FerrisBrace", Size = Vector3.new(14, 0.8, 0.8), CFrame = axle * CFrame.new(0, -(radius + 7) * 0.55, side * 3.5), Color = CREAM, Material = Enum.Material.Metal }), parent)
	end
	local pivot = axle * CFrame.Angles(math.rad(90), 0, 0) -- axe horizontal
	local spinner = MapBase.NewSpinner(parent, "FerrisWheel", pivot)
	local spokes = 16
	for i = 0, spokes - 1 do
		local a = i / spokes * math.pi * 2
		local arm = pivot * CFrame.Angles(0, a, 0)
		Build.Part(deco({ Name = "Spoke", Size = Vector3.new(radius, 0.45, 0.45), CFrame = arm * CFrame.new(radius / 2, 0, 0), Color = CREAM }), spinner)
		local rimCf = pivot * CFrame.Angles(0, a + math.pi / spokes, 0) * CFrame.new(radius, 0, 0)
		Build.Part(deco({ Name = "Rim", Size = Vector3.new(0.8, 0.8, 2 * math.pi * radius / spokes + 0.4), CFrame = rimCf, Color = STRIPES[(i % #STRIPES) + 1] }), spinner)
		Build.Part(deco({ Name = "RimInner", Size = Vector3.new(0.5, 0.5, 2 * math.pi * (radius - 3) / spokes + 0.3), CFrame = pivot * CFrame.Angles(0, a + math.pi / spokes, 0) * CFrame.new(radius - 3, 0, 0), Color = CREAM }), spinner)
		bulb(spinner, (rimCf * CFrame.new(0.7, 0, 0)).Position, i % 2 == 0 and Color3.fromRGB(255, 230, 140) or Color3.fromRGB(255, 140, 180), 0.9, false)
		if i % 2 == 0 then
			-- Nacelle : cabine arrondie avec toit
			local cabin = arm * CFrame.new(radius, 0, 0)
			Build.Part(deco({ Name = "Cabin", Shape = Enum.PartType.Ball, Size = Vector3.new(3.4, 3.4, 3.4), CFrame = cabin * CFrame.new(0, 0, 0), Color = STRIPES[((i // 2) % #STRIPES) + 1] }), spinner)
		end
	end
	Build.Part(deco({ Name = "Hub", Shape = Enum.PartType.Cylinder, Size = Vector3.new(2.5, 5, 5), CFrame = pivot * CFrame.Angles(0, 0, math.rad(90)), Color = GOLD, Material = Enum.Material.Metal }), spinner)
	MapBase.StartSpinner(spinner, 0.12)
	-- Guichet
	local booth = base * CFrame.new(9, 0, -9)
	Build.Part({ Name = "Booth", Size = Vector3.new(5, 6, 4), CFrame = booth * CFrame.new(0, 3, 0), Color = RED }, parent)
	Props.Roof(parent, booth * CFrame.new(0, 6, 0), { Width = 5, Depth = 4, Rise = 1.6, Color = CREAM, Gable = RED, Overhang = 0.6, Thickness = 0.4 })
	Props.Window(parent, booth * CFrame.new(0, 3.6, -2.05), 2.6, 1.8, CREAM, nil)
end

-- Chapiteau traversable : murs rayés en cercle avec deux grandes entrées
-- (raccourci entre deux zones), toit conique, piste au centre.
local function buildBigTop(parent: Instance, center: Vector3, entranceDir: Vector3)
	local model = Instance.new("Model")
	model.Name = "BigTop"
	local R, wallH, peak = 17, 9, 25
	local segments = 28
	local entry = math.atan2(entranceDir.Z, entranceDir.X)
	for i = 0, segments - 1 do
		local a = (i + 0.5) / segments * math.pi * 2
		local d1 = math.abs(Mechanics.AngleDelta(a, entry))
		local d2 = math.abs(Mechanics.AngleDelta(a, entry + math.pi))
		if d1 > 0.3 and d2 > 0.3 then
			local p = center + Vector3.new(math.cos(a) * R, wallH / 2, math.sin(a) * R)
			Build.Part({
				Name = "TentWall",
				Size = Vector3.new(2 * math.pi * R / segments + 0.3, wallH, 0.6),
				CFrame = CFrame.lookAt(p, Vector3.new(center.X, p.Y, center.Z)),
				Color = i % 2 == 0 and RED or CREAM,
				Material = Enum.Material.Fabric,
			}, model)
		end
	end
	-- Toit conique : panneaux inclinés rayés
	local panels = 20
	local rise = peak - wallH
	local slope = math.atan2(rise, R)
	local length = math.sqrt(R * R + rise * rise) + 1.6
	for i = 0, panels - 1 do
		local a = (i + 0.5) / panels * math.pi * 2
		local mid = center + Vector3.new(math.cos(a) * R * 0.5, wallH + rise / 2, math.sin(a) * R * 0.5)
		local look = CFrame.lookAt(mid, Vector3.new(center.X, mid.Y, center.Z))
		Build.Part(deco({
			Name = "TentRoof",
			Size = Vector3.new(2 * math.pi * R / panels * 0.62, 0.5, length),
			CFrame = look * CFrame.Angles(slope, 0, 0) * CFrame.new(0, 0.3, 0.8),
			Color = i % 2 == 0 and RED or CREAM,
			Material = Enum.Material.Fabric,
		}), model)
		-- Lambrequin
		local v = center + Vector3.new(math.cos(a) * (R + 1), wallH - 0.6, math.sin(a) * (R + 1))
		Build.Part(deco({ Name = "Valance", Size = Vector3.new(2 * math.pi * (R + 1) / panels, 1.6, 0.2), CFrame = CFrame.lookAt(v, Vector3.new(center.X, v.Y, center.Z)), Color = i % 2 == 0 and GOLD or RED, Material = Enum.Material.Fabric }), model)
	end
	Build.VerticalCylinder(center + Vector3.new(0, peak / 2, 0), 0.9, peak + 2, { Name = "KingPole", Color = CREAM }, model)
	Build.Part(deco({ Name = "PoleFlag", Size = Vector3.new(0.2, 2.4, 4), CFrame = CFrame.new(center + Vector3.new(0, peak + 2.6, 2)), Color = GOLD }), model)
	-- Piste intérieure
	Build.VerticalCylinder(center + Vector3.new(0, 0.6, 0), 7, 1.2, { Name = "RingCurb", Color = RED }, model)
	Build.VerticalCylinder(center + Vector3.new(0, 0.65, 0), 6.2, 1.25, { Name = "RingSawdust", Color = Color3.fromRGB(236, 206, 150), Material = Enum.Material.Sand }, model)
	Build.VerticalCylinder(center + Vector3.new(0, 2, 0), 1.6, 2.6, { Name = "Podium", Color = BLUE }, model)
	Build.Part(deco({ Name = "PodiumStar", Shape = Enum.PartType.Ball, Size = Vector3.new(1.4, 1.4, 1.4), Position = center + Vector3.new(0, 3.9, 0), Color = GOLD, Material = Enum.Material.Neon }), model)
	-- Cadres d'entrée avec enseigne
	for _, dirSign in { 1, -1 } do
		local dir = Vector3.new(math.cos(entry), 0, math.sin(entry)) * dirSign
		local side = Vector3.new(-dir.Z, 0, dir.X)
		local door = center + dir * (R + 0.4)
		for _, s in { -1, 1 } do
			Build.Part({ Name = "EntrancePost", Size = Vector3.new(1.2, wallH + 2, 1.2), Position = door + side * s * 5.4 + Vector3.new(0, (wallH + 2) / 2, 0), Color = GOLD, Material = Enum.Material.Metal }, model)
		end
		local sign = Build.Part(deco({ Name = "EntranceSign", Size = Vector3.new(12, 2.4, 0.5), CFrame = CFrame.lookAt(door + Vector3.new(0, wallH + 1.6, 0), door + dir + Vector3.new(0, wallH + 1.6, 0)) * CFrame.Angles(0, math.pi, 0), Color = PINK }), model)
		for _, face in { Enum.NormalId.Front, Enum.NormalId.Back } do
			Build.SurfaceLabel(sign, face, "BIG TOP", { TextColor3 = GOLD, TextStrokeTransparency = 0.3, Font = Enum.Font.GothamBlack })
		end
		for k = -2, 2 do
			bulb(model, door + side * k * 2.4 + Vector3.new(0, wallH + 3.1, 0), Color3.fromRGB(255, 230, 140), 0.6, k == 0)
		end
	end
	model.Parent = parent
	Ground.PaintDisc(center, R + 3, center.Y, Enum.Material.Sand)
end

-- Allée des jeux : deux rangées de stands face à face (couloir de poursuite)
local function buildMidway(parent: Instance, center: Vector3, along: Vector3)
	local model = Instance.new("Model")
	model.Name = "Midway"
	local side = Vector3.new(-along.Z, 0, along.X)
	local colors = { RED, BLUE, GOLD, MINT, PINK, RED }
	Ground.Paint(CFrame.lookAt(center, center + along), 14, 50, center.Y, Enum.Material.Pavement)
	for row = -1, 1, 2 do
		for k = -1, 1 do
			local p = center + along * (k * 15) + side * row * 10
			local cf = CFrame.lookAt(p, p - side * row)
			local color = colors[(k + 2) + (row + 1) // 2 * 3]
			Props.Stall(model, cf, 10, 6, color, CREAM)
			-- Lots à gagner sur le comptoir
			for j = -1, 1 do
				local item = (cf * CFrame.new(j * 2.6, 3.7, -1.6)).Position
				if (k + j) % 2 == 0 then
					Build.Part(deco({ Name = "Plush", Shape = Enum.PartType.Ball, Size = Vector3.new(1.6, 1.6, 1.6), Position = item + Vector3.new(0, 0.3, 0), Color = STRIPES[((k + j + 3) % #STRIPES) + 1], Accent = true }), model)
				else
					for b = 0, 2 do
						Build.VerticalCylinder(item + Vector3.new((b - 1) * 0.6, 0.6, 0), 0.25, 1.2, deco({ Name = "Bottle", Color = Color3.fromRGB(110, 200, 140), Material = Enum.Material.Glass, Transparency = 0.2 }), model)
					end
				end
			end
		end
	end
	-- Fanions en travers de l'allée
	for k = -1, 1 do
		local p = center + along * (k * 15 + 7.5)
		Props.Bunting(model, p + side * 10 + Vector3.new(0, 9, 0), p - side * 10 + Vector3.new(0, 9, 0), { RED, GOLD, BLUE, CREAM }, 1.5)
	end
	local signPos = center - along * 26 + side * 6
	Props.Sign(model, CFrame.lookAt(signPos, signPos - along), "GAMES", PINK)
	model.Parent = parent
end

-- Autos tamponneuses : pavillon ouvert, murets bas (on saute par-dessus), voitures
local function buildBumperCars(parent: Instance, center: Vector3, yaw: number)
	local model = Instance.new("Model")
	model.Name = "BumperCars"
	local cf = CFrame.new(center) * CFrame.Angles(0, yaw, 0)
	local w, d = 30, 22
	Build.Part({ Name = "Floor", Size = Vector3.new(w, 0.4, d), CFrame = cf * CFrame.new(0, 0.2, 0), Color = Color3.fromRGB(60, 64, 80), Material = Enum.Material.DiamondPlate }, model)
	-- Murets (jaunes et noirs) avec ouvertures
	for _, side in { -1, 1 } do
		for _, x in { -w / 2 + 5, w / 2 - 5 } do
			Build.Part({ Name = "Bumper", Size = Vector3.new(10, 1.6, 0.8), CFrame = cf * CFrame.new(x, 0.8, side * d / 2), Color = GOLD }, model)
		end
		Build.Part({ Name = "Bumper", Size = Vector3.new(0.8, 1.6, d * 0.35), CFrame = cf * CFrame.new(side * w / 2, 0.8, -d * 0.3), Color = GOLD }, model)
		Build.Part({ Name = "Bumper", Size = Vector3.new(0.8, 1.6, d * 0.35), CFrame = cf * CFrame.new(side * w / 2, 0.8, d * 0.3), Color = GOLD }, model)
	end
	-- Toit sur poteaux, bord lumineux
	for _, x in { -w / 2, 0, w / 2 } do
		for _, z in { -d / 2, d / 2 } do
			Build.Part({ Name = "RoofPost", Size = Vector3.new(0.8, 12, 0.8), CFrame = cf * CFrame.new(x, 6, z), Color = CREAM, Material = Enum.Material.Metal }, model)
		end
	end
	Build.Part(deco({ Name = "Canopy", Size = Vector3.new(w + 2, 1, d + 2), CFrame = cf * CFrame.new(0, 12.5, 0), Color = PINK }), model)
	for _, z in { -1, 1 } do
		Build.Part(deco({ Name = "CanopyEdge", Size = Vector3.new(w + 2.2, 0.4, 0.4), CFrame = cf * CFrame.new(0, 12, z * (d / 2 + 1.1)), Color = Color3.fromRGB(255, 230, 140), Material = Enum.Material.Neon }), model)
	end
	local sign = Build.Part(deco({ Name = "BumperSign", Size = Vector3.new(16, 3, 0.5), CFrame = cf * CFrame.new(0, 14.6, -d / 2 - 1), Color = RED }), model)
	Build.SurfaceLabel(sign, Enum.NormalId.Front, "BUMPER CARS", { TextColor3 = CREAM, TextStrokeTransparency = 0.4, Font = Enum.Font.GothamBlack })
	-- Voitures (obstacles)
	local spots = { { -8, -4, 0.4 }, { 3, 5, 2.2 }, { 9, -5, -1 }, { -3, 6, 3.6 }, { -10, 4, -2.4 } }
	for i, s in spots do
		local car = cf * CFrame.new(s[1], 0, s[2]) * CFrame.Angles(0, s[3], 0)
		local color = STRIPES[((i * 2) % #STRIPES) + 1]
		if color == CREAM or color == STRIPES[2] then
			color = BLUE
		end
		Build.Part({ Name = "CarBody", Size = Vector3.new(3.6, 1.6, 5), CFrame = car * CFrame.new(0, 1.2, 0), Color = color }, model)
		Build.Part(deco({ Name = "CarBumper", Size = Vector3.new(4.2, 0.8, 5.6), CFrame = car * CFrame.new(0, 0.7, 0), Color = Color3.fromRGB(40, 40, 46) }), model)
		Build.Part(deco({ Name = "CarSeat", Size = Vector3.new(2.6, 1.6, 1), CFrame = car * CFrame.new(0, 2.6, 1.4), Color = Color3.fromRGB(40, 40, 46) }), model)
		Build.Part(deco({ Name = "CarPole", Size = Vector3.new(0.2, 9, 0.2), CFrame = car * CFrame.new(0, 6.8, 2), Color = CREAM, Material = Enum.Material.Metal }), model)
	end
	model.Parent = parent
end

-- Tour de chute : très haute, visible de loin
local function buildDropTower(parent: Instance, ground: Vector3)
	local model = Instance.new("Model")
	model.Name = "DropTower"
	local h = 56
	Build.VerticalCylinder(ground + Vector3.new(0, 1, 0), 7, 2, { Name = "TowerBase", Color = Color3.fromRGB(70, 74, 92), Material = Enum.Material.DiamondPlate }, model)
	for k = 0, 6 do
		Build.Part({ Name = "TowerSection", Size = Vector3.new(3.4, h / 7, 3.4), Position = ground + Vector3.new(0, 2 + (k + 0.5) * h / 7, 0), Color = k % 2 == 0 and BLUE or CREAM }, model)
	end
	-- Anneau de sièges arrêté en hauteur
	Build.VerticalCylinder(ground + Vector3.new(0, h * 0.62, 0), 5.4, 2, deco({ Name = "SeatRing", Color = CREAM, Material = Enum.Material.Metal }), model)
	for i = 0, 7 do
		local a = i / 8 * math.pi * 2
		Build.Part(deco({ Name = "Seat", Size = Vector3.new(1.6, 2.2, 1.2), CFrame = CFrame.lookAt(ground + Vector3.new(math.cos(a) * 5.8, h * 0.62 - 1.4, math.sin(a) * 5.8), ground + Vector3.new(0, h * 0.62 - 1.4, 0)), Color = RED }), model)
	end
	Build.Part(deco({ Name = "TowerCap", Size = Vector3.new(5, 2, 5), Position = ground + Vector3.new(0, h + 3, 0), Color = RED }), model)
	bulb(model, ground + Vector3.new(0, h + 4.8, 0), Color3.fromRGB(255, 90, 90), 1.6, true)
	for k = 1, 6 do
		bulb(model, ground + Vector3.new(1.75, 2 + k * h / 7, 0), Color3.fromRGB(255, 230, 140), 0.6, false)
	end
	model.Parent = parent
end

-- Tasses tournantes (manège décoratif, derrière une barrière)
local function buildTeacups(parent: Instance, center: Vector3)
	Build.VerticalCylinder(center + Vector3.new(0, 0.5, 0), 11, 1, { Name = "TeacupDeck", Color = MINT }, parent)
	local spinner = MapBase.NewSpinner(parent, "Teacups", CFrame.new(center + Vector3.new(0, 1, 0)))
	for i = 0, 3 do
		local a = i / 4 * math.pi * 2
		local p = center + Vector3.new(math.cos(a) * 6.5, 2.2, math.sin(a) * 6.5)
		local color = ({ RED, BLUE, GOLD, PINK })[i + 1]
		Build.VerticalCylinder(p, 2.4, 2.6, deco({ Name = "Cup", Color = color }), spinner)
		Build.VerticalCylinder(p + Vector3.new(0, 1.35, 0), 2.6, 0.3, deco({ Name = "CupRim", Color = CREAM }), spinner)
		Build.Part(deco({ Name = "CupHandle", Size = Vector3.new(0.5, 1.6, 1.4), CFrame = CFrame.new(p + Vector3.new(math.cos(a) * 2.7, 0.2, math.sin(a) * 2.7)) * CFrame.Angles(0, -a, 0), Color = CREAM }), spinner)
	end
	Build.VerticalCylinder(center + Vector3.new(0, 3, 0), 1.4, 4, deco({ Name = "Teapot", Color = CREAM }), spinner)
	MapBase.StartSpinner(spinner, 0.5)
	local r = 12.5
	for i = 0, 11 do
		local a1, a2 = i / 12 * math.pi * 2, (i + 1) / 12 * math.pi * 2
		Props.PicketFence(parent, center + Vector3.new(math.cos(a1) * r, 0, math.sin(a1) * r), center + Vector3.new(math.cos(a2) * r, 0, math.sin(a2) * r), CREAM)
	end
end

-- Arche d'entrée de la fête (repère de coin)
local function buildEntranceArch(parent: Instance, ground: Vector3, facing: Vector3)
	local cf = CFrame.lookAt(ground, Vector3.new(facing.X, ground.Y, facing.Z))
	for _, s in { -1, 1 } do
		local tower = cf * CFrame.new(s * 9, 0, 0)
		Build.Part({ Name = "ArchTower", Size = Vector3.new(4, 14, 4), CFrame = tower * CFrame.new(0, 7, 0), Color = s < 0 and RED or BLUE }, parent)
		Props.Roof(parent, tower * CFrame.new(0, 14, 0), { Width = 4.6, Depth = 4.6, Rise = 3.4, Color = GOLD, Gable = CREAM, Overhang = 0.4, Thickness = 0.4 })
	end
	local sign = Build.Part({ Name = "ArchSign", Size = Vector3.new(16, 4, 1), CFrame = cf * CFrame.new(0, 12, 0), Color = PINK }, parent)
	for _, face in { Enum.NormalId.Front, Enum.NormalId.Back } do
		Build.SurfaceLabel(sign, face, "SUNSET FAIR", { TextColor3 = GOLD, TextStrokeTransparency = 0.3, Font = Enum.Font.GothamBlack })
	end
	for k = -3, 3 do
		bulb(parent, (cf * CFrame.new(k * 2.2, 14.3, 0)).Position, Color3.fromRGB(255, 230, 140), 0.6, false)
	end
	-- Ballons
	for i = 1, 6 do
		local a = i * 1.1
		local p = (cf * CFrame.new(-12 + math.cos(a) * 1.4, 10 + i * 0.7, math.sin(a) * 1.4)).Position
		Build.Part(deco({ Name = "Balloon", Shape = Enum.PartType.Ball, Size = Vector3.new(2, 2.4, 2), Position = p, Color = STRIPES[(i % #STRIPES) + 1], Accent = true }), parent)
		local anchor = (cf * CFrame.new(-12, 1.5, 0)).Position
		local mid = (p + anchor) / 2
		Build.Part(deco({ Name = "String", Size = Vector3.new(0.06, 0.06, (p - anchor).Magnitude), CFrame = CFrame.lookAt(mid, p), Color = CREAM, CastShadow = false }), parent)
	end
end

-- Chariot à pop-corn (petit obstacle)
local function buildPopcornCart(parent: Instance, ground: Vector3, yaw: number)
	local cf = CFrame.new(ground) * CFrame.Angles(0, yaw, 0)
	Build.Part({ Name = "CartBase", Size = Vector3.new(4, 2.6, 2.6), CFrame = cf * CFrame.new(0, 1.9, 0), Color = RED }, parent)
	for _, x in { -1.4, 1.4 } do
		Build.Part(deco({ Name = "CartStripe", Size = Vector3.new(0.5, 2.62, 2.62), CFrame = cf * CFrame.new(x, 1.9, 0), Color = CREAM }), parent)
	end
	Build.Part(deco({ Name = "Glass", Size = Vector3.new(3.4, 2.4, 2.2), CFrame = cf * CFrame.new(0, 4.4, 0), Color = Color3.fromRGB(220, 240, 255), Material = Enum.Material.Glass, Transparency = 0.5 }), parent)
	Build.Part(deco({ Name = "Popcorn", Size = Vector3.new(3.2, 1.2, 2), CFrame = cf * CFrame.new(0, 3.9, 0), Color = Color3.fromRGB(255, 236, 160) }), parent)
	Props.Roof(parent, cf * CFrame.new(0, 5.6, 0), { Width = 4.4, Depth = 3, Rise = 1.2, Color = RED, Gable = CREAM, Overhang = 0.3, Thickness = 0.3 })
	for _, x in { -1.5, 1.5 } do
		Build.Part(deco({ Name = "Wheel", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.4, 1.6, 1.6), CFrame = cf * CFrame.new(x, 0.8, 1.4) * CFrame.Angles(0, math.rad(90), 0), Color = Color3.fromRGB(40, 40, 46) }), parent)
	end
end

-- Montagnes russes sur les collines (grande silhouette) : boucle fermée,
-- piliers jusqu'au relief, wagons colorés
local function buildCoaster(parent: Instance, center: Vector3, rx: number, rz: number)
	local model = Instance.new("Model")
	model.Name = "RollerCoaster"
	local steps = 64
	local points = {}
	for i = 0, steps do
		local t = i / steps * math.pi * 2
		local x = center.X + math.cos(t) * rx
		local z = center.Z + math.sin(t) * rz
		local ground = Ground.HeightAt(x, z)
		local y = math.max(ground + 6, center.Y + 22 + 16 * math.sin(t * 2) + 8 * math.sin(t * 3 + 1))
		points[i + 1] = Vector3.new(x, y, z)
	end
	for i = 1, steps do
		local a, b = points[i], points[i + 1]
		local cf = CFrame.lookAt((a + b) / 2, b)
		local length = (b - a).Magnitude
		for _, x in { -1.4, 1.4 } do
			Build.Part(deco({ Name = "Rail", Size = Vector3.new(0.5, 0.5, length + 0.3), CFrame = cf * CFrame.new(x, 0, 0), Color = RED, Material = Enum.Material.Metal }), model)
		end
		Build.Part(deco({ Name = "Spine", Size = Vector3.new(0.8, 0.8, length + 0.3), CFrame = cf * CFrame.new(0, -0.9, 0), Color = CREAM, Material = Enum.Material.Metal }), model)
		Build.Part(deco({ Name = "Tie", Size = Vector3.new(3.4, 0.3, 0.5), CFrame = cf * CFrame.new(0, -0.3, 0), Color = CREAM }), model)
		if i % 3 == 0 then
			local ground = Ground.HeightAt(a.X, a.Z)
			local h = a.Y - ground
			if h > 2 then
				Build.Part(deco({ Name = "Pillar", Size = Vector3.new(0.9, h, 0.9), Position = Vector3.new(a.X, ground + h / 2 - 1, a.Z), Color = CREAM, Material = Enum.Material.Metal }), model)
			end
		end
	end
	-- Train de 3 wagons
	for k = 0, 2 do
		local a, b = points[8 + k * 2], points[9 + k * 2]
		local cf = CFrame.lookAt(a, b)
		local color = ({ GOLD, BLUE, MINT })[k + 1]
		Build.Part(deco({ Name = "Car", Size = Vector3.new(3.4, 1.8, 3.6), CFrame = cf * CFrame.new(0, 1.2, 0), Color = color }), model)
		Build.Part(deco({ Name = "CarSeat", Size = Vector3.new(3, 1.2, 1), CFrame = cf * CFrame.new(0, 2.4, 1.2), Color = Color3.fromRGB(40, 40, 46) }), model)
	end
	model.Parent = parent
end

-- Chaises volantes : couronne tournante, chaînes et sièges (manège animé)
local function buildSwingRide(parent: Instance, ground: Vector3)
	Build.VerticalCylinder(ground + Vector3.new(0, 0.6, 0), 14, 1.2, { Name = "SwingDeck", Color = PINK }, parent)
	Build.VerticalCylinder(ground + Vector3.new(0, 1.25, 0), 12.5, 0.15, { Name = "SwingDeckRing", Color = CREAM, CanCollide = false }, parent)
	Build.VerticalCylinder(ground + Vector3.new(0, 9, 0), 1.6, 16, { Name = "SwingMast", Color = CREAM }, parent)
	local spinner = MapBase.NewSpinner(parent, "SwingRide", CFrame.new(ground + Vector3.new(0, 16, 0)))
	Build.VerticalCylinder(ground + Vector3.new(0, 17, 0), 9, 1.4, deco({ Name = "Crown", Color = RED }), spinner)
	for i = 0, 15 do
		local a = i / 16 * math.pi * 2
		Build.Part(deco({ Name = "CrownStripe", Size = Vector3.new(0.6, 1.5, 3.4), CFrame = CFrame.new(ground + Vector3.new(math.cos(a) * 9.05, 17, math.sin(a) * 9.05)) * CFrame.Angles(0, -a, 0), Color = i % 2 == 0 and GOLD or CREAM }), spinner)
		bulb(spinner, ground + Vector3.new(math.cos(a) * 9.3, 16.1, math.sin(a) * 9.3), Color3.fromRGB(255, 230, 140), 0.5, false)
	end
	Props.Roof(spinner, CFrame.new(ground + Vector3.new(0, 17.7, 0)), { Width = 12, Depth = 12, Rise = 4, Color = RED, Gable = CREAM, Overhang = 0.5, Thickness = 0.4 })
	-- Sièges projetés vers l'extérieur (chaînes inclinées par la vitesse)
	for i = 0, 11 do
		local a = i / 12 * math.pi * 2
		local top = ground + Vector3.new(math.cos(a) * 8, 16.3, math.sin(a) * 8)
		local seat = ground + Vector3.new(math.cos(a) * 11.5, 8.2, math.sin(a) * 11.5)
		local mid = (top + seat) / 2
		Build.Part(deco({ Name = "Chain", Size = Vector3.new(0.12, 0.12, (seat - top).Magnitude), CFrame = CFrame.lookAt(mid, seat), Color = Color3.fromRGB(190, 190, 200), Material = Enum.Material.Metal }), spinner)
		Build.Part(deco({ Name = "Seat", Size = Vector3.new(1.6, 0.4, 1.6), CFrame = CFrame.new(seat) * CFrame.Angles(0, -a, 0), Color = STRIPES[(i % #STRIPES) + 1] }), spinner)
	end
	MapBase.StartSpinner(spinner, 0.9)
end

-- Montgolfières au-dessus des collines
local function buildBalloon(parent: Instance, position: Vector3, colorA: Color3, colorB: Color3)
	local model = Instance.new("Model")
	model.Name = "HotAirBalloon"
	Build.Part(deco({ Name = "Envelope", Shape = Enum.PartType.Ball, Size = Vector3.new(18, 21, 18), Position = position, Color = colorA }), model)
	for k = -1, 1 do
		Build.VerticalCylinder(position + Vector3.new(0, k * 4.5, 0), 9.15 * math.cos(math.asin(math.min(0.95, math.abs(k * 4.5) / 10.5))), 1.6, deco({ Name = "Band", Color = colorB }), model)
	end
	Build.Wedge(deco({ Name = "Skirt", Size = Vector3.new(6, 3, 3), CFrame = CFrame.new(position + Vector3.new(0, -11, 0)), Color = colorB }), model)
	Build.Part(deco({ Name = "Basket", Size = Vector3.new(3.4, 2.6, 3.4), Position = position + Vector3.new(0, -16, 0), Color = Color3.fromRGB(150, 104, 60), Material = Enum.Material.WoodPlanks }), model)
	for _, x in { -1.5, 1.5 } do
		for _, z in { -1.5, 1.5 } do
			local a, b = position + Vector3.new(x * 2.2, -9, z * 2.2), position + Vector3.new(x, -14.8, z)
			Build.Part(deco({ Name = "Rope", Size = Vector3.new(0.1, 0.1, (b - a).Magnitude), CFrame = CFrame.lookAt((a + b) / 2, b), Color = Color3.fromRGB(80, 70, 60) }), model)
		end
	end
	model.Parent = parent
end

-- Poteau indicateur au bord de la place : flèches vers les zones
local function buildSignpost(parent: Instance, ground: Vector3, targets: { { Label: string, Target: Vector3, Color: Color3 } })
	Build.Part({ Name = "SignPole", Size = Vector3.new(0.8, 12, 0.8), Position = ground + Vector3.new(0, 6, 0), Color = CREAM }, parent)
	Build.Part(deco({ Name = "SignTop", Shape = Enum.PartType.Ball, Size = Vector3.new(1.6, 1.6, 1.6), Position = ground + Vector3.new(0, 12.4, 0), Color = GOLD, Material = Enum.Material.Metal }), parent)
	for i, t in targets do
		local y = 11 - i * 2.4
		local dir = Vector3.new(t.Target.X - ground.X, 0, t.Target.Z - ground.Z).Unit
		local cf = CFrame.lookAt(ground + Vector3.new(0, y, 0), ground + Vector3.new(0, y, 0) + dir)
		local board = Build.Part(deco({ Name = "Arrow", Size = Vector3.new(0.3, 1.8, 7), CFrame = cf * CFrame.new(0, 0, -3.6) * CFrame.Angles(0, math.rad(90), 0) * CFrame.Angles(0, math.rad(90), 0), Color = t.Color }), parent)
		Build.Wedge(deco({ Name = "ArrowTip", Size = Vector3.new(0.3, 1.8, 1.6), CFrame = cf * CFrame.new(0, 0, -7.9), Color = t.Color }), parent)
		for _, face in { Enum.NormalId.Right, Enum.NormalId.Left } do
			Build.SurfaceLabel(board, face, t.Label, { TextColor3 = CREAM, TextStrokeTransparency = 0.5, Font = Enum.Font.GothamBlack })
		end
	end
end

-- Pavés colorés de la place centrale (anneau autour du manège)
local function buildPlaza(parent: Instance)
	Ground.PaintDisc(origin, cfg.PlatformRadius + 22, origin.Y, Enum.Material.Pavement)
	Ground.PaintDisc(origin, cfg.PlatformRadius + 9, origin.Y, Enum.Material.Brick)
	local r = cfg.PlatformRadius + 6
	local count = 40
	for i = 0, count - 1 do
		local a = i / count * math.pi * 2
		local p = origin + Vector3.new(math.cos(a) * r, 0.08, math.sin(a) * r)
		Build.Part(deco({
			Name = "PlazaTile",
			Size = Vector3.new(4.2, 0.16, 2 * math.pi * r / count - 0.4),
			CFrame = CFrame.lookAt(p, p + Vector3.new(-math.sin(a), 0, math.cos(a))),
			Color = STRIPES[(i % #STRIPES) + 1],
			Accent = true,
		}), parent)
	end
end

local function buildWheel(parent: Instance): Model
	local spinner = MapBase.NewSpinner(parent, "Carousel", CFrame.new(origin))
	spinner:SetAttribute("SpinCollide", true)
	local radius = cfg.PlatformRadius
	local top = cfg.PlatformHeight
	-- Socle fixe (bordure)
	Build.VerticalCylinder(origin + Vector3.new(0, top / 2 - 0.3, 0), radius + 2, top - 0.6, {
		Name = "WheelSkirt",
		Color = Color3.fromRGB(52, 108, 150),
		Material = Enum.Material.SmoothPlastic,
	}, parent)
	-- Plateforme tournante : un cylindre (forme symétrique, collision identique côté serveur)
	Build.VerticalCylinder(origin + Vector3.new(0, top - 0.4, 0), radius, 0.8, {
		Name = "WheelFloor",
		Color = Color3.fromRGB(245, 230, 200),
		Material = Enum.Material.WoodPlanks,
	}, spinner)
	-- Quartiers colorés (décor plat)
	for i = 0, 11 do
		local a = (i + 0.5) / 12 * math.pi * 2
		local p = origin + Vector3.new(math.cos(a) * radius * 0.55, top + 0.02, -math.sin(a) * radius * 0.55)
		Build.Part({
			Name = "WheelSlice",
			Accent = true,
			Size = Vector3.new(radius * 0.8, 0.05, radius * 0.22),
			CFrame = CFrame.new(p) * CFrame.Angles(0, a, 0),
			Color = STRIPES[(i % #STRIPES) + 1],
			CanCollide = false,
			CanQuery = false,
		}, spinner)
	end
	-- Chevaux de bois sur poteaux (décor, traversables)
	for i = 0, 7 do
		local a = i / 8 * math.pi * 2
		local p = origin + Vector3.new(math.cos(a) * radius * 0.75, 0, -math.sin(a) * radius * 0.75)
		Build.Part({ Name = "HorsePole", Size = Vector3.new(0.4, 14, 0.4), Position = p + Vector3.new(0, top + 7, 0), Color = Color3.fromRGB(255, 215, 80), Material = Enum.Material.Metal, CanCollide = false, CanQuery = false }, spinner)
		local horseCf = CFrame.new(p + Vector3.new(0, top + 4, 0)) * CFrame.Angles(0, a + math.pi / 2, 0)
		Build.Part({ Name = "HorseBody", Size = Vector3.new(1.4, 1.6, 3.6), CFrame = horseCf, Color = STRIPES[(i % #STRIPES) + 1], CanCollide = false, CanQuery = false }, spinner)
		Build.Part({ Name = "HorseHead", Size = Vector3.new(1, 1.8, 1.2), CFrame = horseCf * CFrame.new(0, 1.2, -1.8) * CFrame.Angles(math.rad(-20), 0, 0), Color = STRIPES[(i % #STRIPES) + 1], CanCollide = false, CanQuery = false }, spinner)
	end
	-- Mât central et toit
	Build.VerticalCylinder(origin + Vector3.new(0, top + 8, 0), 2.2, 16, { Name = "CenterMast", Color = Color3.fromRGB(235, 70, 90), CanCollide = false, CanQuery = false }, spinner)
	-- Toit conique : anneaux rayés de plus en plus petits
	for i = 0, 6 do
		local r = radius * (1.02 - i * 0.14)
		Build.VerticalCylinder(origin + Vector3.new(0, top + 16.5 + i * 1.3, 0), r, 1.3, {
			Name = "Canopy",
			Color = STRIPES[(i % #STRIPES) + 1],
			Material = Enum.Material.Fabric,
			CanCollide = false,
			CanQuery = false,
		}, spinner)
	end
	-- Lambrequin festonné sous le bord du toit
	for i = 0, 23 do
		local a = i / 24 * math.pi * 2
		Build.Part({
			Name = "Valance",
			Size = Vector3.new(radius * 0.27, 1.6, 0.3),
			CFrame = CFrame.new(origin + Vector3.new(math.cos(a) * radius, top + 15.2, -math.sin(a) * radius)) * CFrame.Angles(0, a + math.pi / 2, 0),
			Color = i % 2 == 0 and Color3.fromRGB(235, 70, 90) or Color3.fromRGB(250, 245, 235),
			Material = Enum.Material.Fabric,
			CanCollide = false,
			CanQuery = false,
		}, spinner)
	end
	Build.Part({ Name = "RoofBall", Shape = Enum.PartType.Ball, Size = Vector3.new(4, 4, 4), Position = origin + Vector3.new(0, top + 26.5, 0), Color = Color3.fromRGB(255, 205, 50), Material = Enum.Material.Metal, CanCollide = false, CanQuery = false }, spinner)
	Build.Part({ Name = "RoofFlag", Size = Vector3.new(0.2, 2.2, 3.5), Position = origin + Vector3.new(0, top + 30, 1.7), Color = Color3.fromRGB(235, 70, 90), CanCollide = false, CanQuery = false }, spinner)
	Build.Part({ Name = "RoofPole", Size = Vector3.new(0.3, 4, 0.3), Position = origin + Vector3.new(0, top + 29.5, 0), Color = Color3.fromRGB(240, 240, 240), CanCollide = false, CanQuery = false }, spinner)
	-- Ampoules sur le pourtour
	for i = 0, 23 do
		local a = i / 24 * math.pi * 2
		Build.Part({
			Name = "Bulb",
			Shape = Enum.PartType.Ball,
			Size = Vector3.new(0.8, 0.8, 0.8),
			Position = origin + Vector3.new(math.cos(a) * (radius - 0.6), top + 0.4, -math.sin(a) * (radius - 0.6)),
			Color = i % 2 == 0 and Color3.fromRGB(255, 230, 120) or Color3.fromRGB(255, 120, 160),
			Material = Enum.Material.Neon,
			CanCollide = false,
			CanQuery = false,
		}, spinner)
	end
	-- Rampes d'accès fixes
	for i = 0, 2 do
		local a = math.rad(30 + i * 120)
		local dir = Vector3.new(math.cos(a), 0, math.sin(a))
		local p = origin + dir * (radius + 5)
		Build.Part({
			Name = "Ramp",
			Size = Vector3.new(8, 0.6, 9),
			CFrame = CFrame.lookAt(p + Vector3.new(0, top / 2, 0), origin + Vector3.new(0, top / 2, 0)) * CFrame.Angles(math.rad(-12), 0, 0),
			Color = Color3.fromRGB(150, 100, 70),
			Material = Enum.Material.WoodPlanks,
		}, parent)
	end
	Mechanics.SetSpin(spinner, 0, 0)
	return spinner
end

function Map.Build(mapOrigin: Vector3, _context: MapContext)
	origin = mapOrigin
	local f = MapBase.NewFolder("Map_" .. Map.Id)
	bases = MapBase.BuildArena(f, origin, cfg, THEME)
	buildPlaza(f)
	wheel = buildWheel(f)

	-- Guirlandes lumineuses entre des mâts autour du manège
	local masts = {}
	for i = 0, 5 do
		local a = (i + 0.5) / 6 * math.pi * 2
		local p = origin + Vector3.new(math.cos(a), 0, math.sin(a)) * (cfg.PlatformRadius + 14)
		buildMast(f, p, 12)
		table.insert(masts, p)
	end
	for i = 1, #masts do
		buildLightString(f, masts[i] + Vector3.new(0, 11.6, 0), masts[i % #masts + 1] + Vector3.new(0, 11.6, 0), 12)
	end

	-- Lieux (un par secteur entre deux camps + coins)
	buildFerrisWheel(f, MapBase.Polar(origin, 270, 126), 0)
	buildBigTop(f, MapBase.Polar(origin, 30, 116), Vector3.new(-math.sin(math.rad(30)), 0, math.cos(math.rad(30))))
	local midwayCenter = MapBase.Polar(origin, 150, 114)
	buildMidway(f, midwayCenter, Vector3.new(-math.sin(math.rad(150)), 0, math.cos(math.rad(150))))
	buildBumperCars(f, MapBase.Polar(origin, 45, 172), math.rad(-45))
	buildEntranceArch(f, MapBase.Polar(origin, 135, 176), origin)
	buildDropTower(f, MapBase.Polar(origin, 225, 170))
	buildTeacups(f, MapBase.Polar(origin, 315, 166))
	buildSwingRide(f, MapBase.Polar(origin, 0, 128))

	-- Grandes silhouettes au-delà de la clôture : montagnes russes, montgolfières
	buildCoaster(f, MapBase.Polar(origin, 300, 250) + Vector3.new(0, origin.Y, 0), 70, 40)
	buildBalloon(f, MapBase.Polar(origin, 200, 260) + Vector3.new(0, 70, 0), RED, GOLD)
	buildBalloon(f, MapBase.Polar(origin, 245, 320) + Vector3.new(0, 95, 0), BLUE, CREAM)
	buildBalloon(f, MapBase.Polar(origin, 20, 300) + Vector3.new(0, 80, 0), MINT, PINK)
	buildBalloon(f, MapBase.Polar(origin, 120, 330) + Vector3.new(0, 105, 0), GOLD, RED)

	-- Poteau indicateur au bord de la place
	buildSignpost(f, MapBase.Polar(origin, 300, cfg.PlatformRadius + 24), {
		{ Label = "BIG TOP", Target = MapBase.Polar(origin, 30, 116), Color = RED },
		{ Label = "GAMES", Target = MapBase.Polar(origin, 150, 114), Color = BLUE },
		{ Label = "FERRIS WHEEL", Target = MapBase.Polar(origin, 270, 126), Color = PINK },
	})

	-- Obstacles du cercle intérieur : chariots, caisses de lots, ballons
	-- (entre les couloirs des camps, jamais dessus)
	for i = 0, 5 do
		local deg = i * 60
		local p = MapBase.Polar(origin, deg, 84)
		if i % 2 == 0 then
			buildPopcornCart(f, p, math.rad(-deg))
		else
			Props.CrateStack(f, p, math.rad(deg))
		end
	end

	-- Cachettes : massifs fleuris et hautes herbes en bordure
	for _, deg in { 0, 120, 240 } do
		MapBase.BuildBush(f, MapBase.Polar(origin, deg, 70), 9, Color3.fromRGB(80, 164, 84))
		MapBase.BuildBush(f, MapBase.Polar(origin, deg + 12, 104), 8, Color3.fromRGB(70, 150, 80))
	end
	for _, deg in { 60, 180, 300 } do
		MapBase.BuildTallGrass(f, MapBase.Polar(origin, deg, 138), 6)
	end

	-- Lampadaires à l'entrée des camps (de part et d'autre du chemin)
	for _, base in bases :: { [string]: MapBase.Base } do
		local toCenter = (origin - base.Center).Unit
		local side = Vector3.new(-toCenter.Z, 0, toCenter.X)
		local p = base.Center + toCenter * (base.Radius + 12)
		Props.Lamp(f, p + side * 9, math.atan2(toCenter.X, toCenter.Z))
		Props.Lamp(f, p - side * 9, math.atan2(toCenter.X, toCenter.Z))
	end

	f.Parent = workspace
	folder = f
end

function Map.GetSpawns(teamId: string): { CFrame }
	assert(bases, "Map non construite")
	return bases[teamId].Spawns
end

-- ---------------------------------------------------------------------------
-- Logique
-- ---------------------------------------------------------------------------
local function isOnPlatform(position: Vector3): boolean
	local rel = Vector3.new(position.X - origin.X, 0, position.Z - origin.Z)
	local height = position.Y - origin.Y - cfg.PlatformHeight
	return rel.Magnitude <= cfg.PlatformRadius + 0.5 and height > -0.5 and height < 8
end

local function awardPoint()
	local ctx = context
	if not ctx then
		return
	end
	local counts: { [string]: number } = {}
	table.clear(onPlatform)
	for _, actor in ctx.GetActors() do
		local root = ctx.GetRoot(actor)
		if root and actor.Team and isOnPlatform(root.Position) then
			counts[actor.Team] = (counts[actor.Team] or 0) + 1
			onPlatform[actor.Id] = true
		end
	end
	local best, bestCount, tie = nil, 0, false
	for _, teamId in Teams.Order do
		local n = counts[teamId] or 0
		if n > bestCount then
			best, bestCount, tie = teamId, n, false
		elseif n == bestCount and n > 0 then
			tie = true
		end
	end
	if best and not tie then
		ctx.AddScore(best, 1)
		local total = ctx.GetScore(best)
		if total % 25 == 0 and total < cfg.PointsToWin then
			local def = Teams.Get(best)
			if def then
				ctx.Announce(string.format("%s team: %d points!", def.Display, total), def.Color)
			end
		end
		if total >= cfg.PointsToWin then
			ctx.EndRound(best, "Objective")
		end
	end
end

local function eject()
	local ctx = context
	if not ctx then
		return
	end
	for _, actor in ctx.GetActors() do
		local root = ctx.GetRoot(actor)
		if root and isOnPlatform(root.Position) then
			local rel = Vector3.new(root.Position.X - origin.X, 0, root.Position.Z - origin.Z)
			local dir = rel.Magnitude > 0.5 and rel.Unit or Mechanics.Direction(math.random() * math.pi * 2)
			ctx.Launch(actor, dir * cfg.EjectSpeed + Vector3.new(0, cfg.EjectUpSpeed, 0), 1.4)
		end
	end
end

-- Cycle du mécanisme : paliers d'accélération puis éjection
local function runCycle()
	while running do
		for index, speed in cfg.SpeedSteps do
			if not running or not wheel then
				return
			end
			Mechanics.SetSpin(wheel, speed)
			if context and index > 1 then
				context.Announce(index == #cfg.SpeedSteps and "The wheel is spinning FAST!" or "The wheel speeds up!", Color3.fromRGB(255, 200, 90))
			end
			task.wait(cfg.StepDurationSeconds)
		end
		if not running then
			return
		end
		if context then
			context.Announce("HOLD ON... EJECT!", Color3.fromRGB(255, 90, 90))
		end
		task.wait(1)
		if not running then
			return
		end
		eject()
		if wheel then
			Mechanics.SetSpin(wheel, 0.15)
		end
		task.wait(cfg.PauseAfterEject)
	end
end

function Map.StartMode(ctx: MapContext)
	context = ctx
	running = true
	scoreAccumulator = 0
	ctx.SetScoreInfo(cfg.PointsToWin, "points")
	for _, teamId in Teams.Order do
		ctx.SetObjective(teamId, origin + Vector3.new(0, cfg.PlatformHeight, 0))
	end
	if wheel then
		MapBase.StartSpinner(wheel, cfg.SpeedSteps[1])
	end
	cycleThread = task.spawn(runCycle)
	connection = RunService.Heartbeat:Connect(function(dt)
		if not running then
			return
		end
		scoreAccumulator += dt
		if scoreAccumulator >= 1 then
			scoreAccumulator -= 1
			awardPoint()
		end
	end)
end

function Map.StopMode()
	running = false
	if connection then
		connection:Disconnect()
		connection = nil
	end
	if cycleThread then
		pcall(task.cancel, cycleThread)
		cycleThread = nil
	end
	if wheel then
		Mechanics.SetSpin(wheel, 0)
	end
end

function Map.Cleanup()
	Map.StopMode()
	if folder then
		folder:Destroy()
		folder = nil
	end
	wheel = nil
	bases = nil
	context = nil
	table.clear(onPlatform)
end

-- Les bots visent un point de la plateforme
function Map.GetBotGoal(actor: Actor): Vector3?
	if onPlatform[actor.Id] then
		-- Déjà dessus : rester vers le centre
		local a = math.random() * math.pi * 2
		return origin + Vector3.new(math.cos(a), 0, math.sin(a)) * cfg.PlatformRadius * 0.4 + Vector3.new(0, cfg.PlatformHeight, 0)
	end
	return origin + Vector3.new(0, cfg.PlatformHeight, 0)
end

function Map.IsOnPlatform(actor: Actor): boolean
	return onPlatform[actor.Id] == true
end

function Map.DebugState()
	return { Wheel = wheel, OnPlatform = onPlatform }
end

return Map

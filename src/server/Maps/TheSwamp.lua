--[[
	TheSwamp.lua - mode "The Pack"
	  - Conversion pure : aucune autre règle. Dernière équipe debout
	    (sinon, à la fin du chrono, l'équipe la plus nombreuse gagne).
	  - Mécanismes :
	      * un tourniquet central attrape les joueurs (ils restent bloqués un
	        court instant) puis les relâche vers un des trois camps au hasard ;
	      * des geysers propulsent en l'air à intervalles réguliers (ils
	        bouillonnent avant d'éclater).
	Thème : "Firefly Bayou", marais au crépuscule : cabane sur pilotis (on
	court dessous), bateau à aubes échoué, cercle de champignons lumineux,
	saules pleureurs, passerelles éclairées, lucioles, eau du bayou autour.
]]

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Teams = require(Shared.Teams)
local Mechanics = require(Shared.Mechanics)
local Remotes = require(Shared.Remotes)
local Types = require(Shared.Types)
local MapBase = require(script.Parent.MapBase)
local Build = require(script.Parent.Parent.Util.Build)
local Props = require(script.Parent.Parent.Util.Props)
local Ground = require(script.Parent.Parent.Util.Ground)

type Actor = Types.Actor
type MapContext = Types.MapContext

local Map = {}
Map.Id = "TheSwamp"
-- Bayou de jour : lumière fraîche et verte, brume légère (bible visuelle, §2)
Map.Lighting = {
	ClockTime = 12.8,
	Brightness = 2.7,
	OutdoorAmbient = Color3.fromRGB(150, 168, 162),
	Atmosphere = { Density = 0.25, Haze = 1, Color = Color3.fromRGB(205, 232, 220), Decay = Color3.fromRGB(140, 180, 170) },
	ColorCorrection = { TintColor = Color3.fromRGB(242, 255, 248), Saturation = 0.12, Contrast = 0.05 },
	Bloom = { Intensity = 0.4, Threshold = 1.3 },
}

local cfg = Config.Maps.TheSwamp
local ARM_COUNT = 4
local ARM_HEIGHT = 3
local SAFE_JUMP_HEIGHT = 6.5

-- Mousse vert-bleu à tenons, chemins de vase, gradins vert sapin bas
local THEME: MapBase.ArenaTheme = {
	Seed = 4409,
	Board = Color3.fromRGB(82, 156, 112),
	BoardAlt = Color3.fromRGB(72, 142, 102),
	Path = Enum.Material.Mud,
	PathWidth = 8,
	CenterRadius = 26,
	Backdrop = { Side = Color3.fromRGB(58, 100, 88), Top = Color3.fromRGB(92, 152, 98), Heights = { 10, 22, 40 }, Gap = 22 },
	Perimeter = "None",
	Trees = { "Green", "Pine", "Green" },
	TreeCount = 90,
	Camp = { Wall = Enum.Material.WoodPlanks },
	GroundColors = {
		LeafyGrass = Color3.fromRGB(66, 134, 84),
		Mud = Color3.fromRGB(122, 102, 78),
	},
}

local folder: Folder? = nil
local bases: { [string]: MapBase.Base }? = nil
local origin = Vector3.zero
local context: MapContext? = nil
local running = false
local connection: RBXScriptConnection? = nil
local turnstile: Model? = nil
local lastAngle = 0
local geysers: { { Position: Vector3, Water: Part, Bubbles: ParticleEmitter, Spray: ParticleEmitter } } = {}
local geyserThread: thread? = nil
local grabbed: { [string]: boolean } = {}
local preyTick = 0

-- ---------------------------------------------------------------------------
-- Construction
-- ---------------------------------------------------------------------------
local BARK = Color3.fromRGB(86, 70, 58)
local PLANK = Color3.fromRGB(132, 98, 70)
local PLANK_DARK = Color3.fromRGB(96, 72, 54)
local MOSS = Color3.fromRGB(104, 150, 86)
local GLOW_A = Color3.fromRGB(120, 230, 255)
-- Lueurs cyan et rose (le violet est réservé aux vipères)
local GLOW_B = Color3.fromRGB(255, 150, 196)

local function deco(props: { [string]: any }): { [string]: any }
	props.CanCollide = false
	props.CanQuery = false
	return props
end

local function glow(parent: Instance, position: Vector3, color: Color3, size: number, range: number?)
	local part = Build.Part(deco({ Name = "Glow", Shape = Enum.PartType.Ball, Size = Vector3.new(size, size, size), Position = position, Color = color, Material = Enum.Material.Neon, CastShadow = false }), parent)
	if range then
		local light = Instance.new("PointLight")
		light.Color = color
		light.Range = range
		light.Brightness = 1.1
		light.Parent = part
	end
	return part
end

-- Arbre mort tordu avec mousse espagnole pendante
local function buildDeadTree(parent: Instance, position: Vector3, height: number)
	local random = MapBase.Random()
	local model = Instance.new("Model")
	model.Name = "DeadTree"
	local lean = CFrame.Angles(random:NextNumber(-0.08, 0.08), random:NextNumber(0, math.pi * 2), random:NextNumber(-0.08, 0.08))
	local base = CFrame.new(position) * lean
	Build.Part({ Name = "Trunk", Size = Vector3.new(2.4, height, 2.4), CFrame = base * CFrame.new(0, height / 2, 0), Color = BARK, Material = Enum.Material.Wood }, model)
	Build.Part({ Name = "Roots", Size = Vector3.new(5, 1.6, 5), CFrame = base * CFrame.new(0, 0.6, 0) * CFrame.Angles(0, 0.78, 0), Color = BARK, Material = Enum.Material.Wood }, model)
	for i = 1, 4 do
		local a = i * 1.7
		local y = height * (0.5 + i * 0.11)
		local branch = base * CFrame.new(0, y, 0) * CFrame.Angles(0, a, 0) * CFrame.Angles(0, 0, math.rad(55)) * CFrame.new(0, 3, 0)
		Build.Part(deco({ Name = "Branch", Size = Vector3.new(0.8, 6, 0.8), CFrame = branch, Color = BARK, Material = Enum.Material.Wood }), model)
		-- Mousse pendante
		local tip = branch * CFrame.new(0, 2.6, 0)
		Build.Wedge(deco({ Name = "Moss", Size = Vector3.new(0.2, 4, 1.6), CFrame = CFrame.new(tip.Position - Vector3.new(0, 2, 0)) * CFrame.Angles(0, a, 0) * CFrame.Angles(math.pi, 0, 0), Color = MOSS:Lerp(Color3.fromRGB(170, 190, 140), 0.3), CastShadow = false }), model)
	end
	model.Parent = parent
end

-- Saule pleureur : couronne de boules et rideaux de feuillage
local function buildWillow(parent: Instance, position: Vector3, scale: number)
	local model = Instance.new("Model")
	model.Name = "Willow"
	local s = scale
	Build.VerticalCylinder(position + Vector3.new(0, 6 * s, 0), 1.6 * s, 12 * s, { Name = "WillowTrunk", Color = BARK, Material = Enum.Material.Wood }, model)
	local leaf = Color3.fromRGB(102, 162, 84)
	for i, b in { { 0, 15, 0, 13 }, { 4, 13.5, 2, 9 }, { -4, 13.5, -2, 9 }, { 2, 14, -4, 8 }, { -2, 14, 4, 8 } } do
		Build.Part({ Name = "WillowCrown", Shape = Enum.PartType.Ball, Size = Vector3.new(b[4], b[4] * 0.6, b[4]) * s, Position = position + Vector3.new(b[1], b[2], b[3]) * s, Color = leaf:Lerp(Color3.new(1, 1, 1), (i % 2) * 0.06), CanCollide = i == 1 }, model)
	end
	for i = 0, 17 do
		local a = i / 18 * math.pi * 2
		local r = 7 * s
		local h = (7 + (i % 3) * 1.5) * s
		Build.Wedge(deco({
			Name = "Drape",
			Size = Vector3.new(1.6, h, 0.6),
			CFrame = CFrame.new(position + Vector3.new(math.cos(a) * r, 13 * s - h / 2, math.sin(a) * r)) * CFrame.Angles(0, -a + math.pi / 2, 0) * CFrame.Angles(math.pi, 0, 0),
			Color = leaf:Lerp(Color3.new(0, 0, 0), 0.1 + (i % 2) * 0.06),
			CastShadow = false,
		}), model)
	end
	model.Parent = parent
end

-- Cabane sur pilotis : on peut courir dessous (raccourci entre les poteaux)
local function buildStiltShack(parent: Instance, center: Vector3)
	local model = Instance.new("Model")
	model.Name = "StiltShack"
	local cf = CFrame.lookAt(center, Vector3.new(origin.X, center.Y, origin.Z))
	local floorY = 10
	local w, d = 18, 14
	for _, x in { -w / 2 + 1, 0, w / 2 - 1 } do
		for _, z in { -d / 2 + 1, d / 2 - 1 } do
			Build.Part({ Name = "Stilt", Size = Vector3.new(1.2, floorY, 1.2), CFrame = cf * CFrame.new(x, floorY / 2, z), Color = PLANK_DARK, Material = Enum.Material.Wood }, model)
		end
	end
	for _, z in { -d / 2 + 1, d / 2 - 1 } do
		Build.Part(deco({ Name = "Brace", Size = Vector3.new(w, 0.6, 0.6), CFrame = cf * CFrame.new(0, floorY * 0.45, z) * CFrame.Angles(0, 0, 0.45), Color = PLANK_DARK, Material = Enum.Material.Wood }), model)
	end
	Build.Part({ Name = "Deck", Size = Vector3.new(w + 6, 1, d + 4), CFrame = cf * CFrame.new(0, floorY, -2), Color = PLANK, Material = Enum.Material.WoodPlanks }, model)
	Build.Part({ Name = "Cabin", Size = Vector3.new(w - 2, 9, d - 2), CFrame = cf * CFrame.new(0, floorY + 5, 1), Color = Color3.fromRGB(110, 132, 120), Material = Enum.Material.WoodPlanks }, model)
	Props.Roof(model, cf * CFrame.new(0, floorY + 9.5, 1), { Width = w, Depth = d, Rise = 5, Color = Color3.fromRGB(150, 110, 80), Gable = Color3.fromRGB(110, 132, 120), Overhang = 1.4, Material = Enum.Material.CorrodedMetal })
	Props.Door(model, cf * CFrame.new(-3, floorY + 0.5, -d / 2 + 1.9), 3.6, 6.5, PLANK_DARK, Color3.fromRGB(220, 210, 180))
	Props.Window(model, cf * CFrame.new(4, floorY + 5, -d / 2 + 1.9), 3, 2.6, Color3.fromRGB(220, 210, 180), Color3.fromRGB(70, 120, 110))
	-- Lumière chaude à la fenêtre
	glow(model, (cf * CFrame.new(4, floorY + 5, -d / 2 + 2.3)).Position, Color3.fromRGB(255, 196, 110), 1.6, 20)
	-- Garde-corps, échelle, chaise à bascule, corde à linge
	for _, x in { -w / 2 - 2.5, w / 2 + 2.5 } do
		Build.Part({ Name = "Railing", Size = Vector3.new(0.4, 2.4, d + 4), CFrame = cf * CFrame.new(x, floorY + 1.7, -2), Color = PLANK_DARK, Material = Enum.Material.Wood }, model)
	end
	Build.Part({ Name = "Ladder", Size = Vector3.new(3, floorY + 1, 0.4), CFrame = cf * CFrame.new(w / 2 - 2, floorY / 2, -d / 2 - 4.6) * CFrame.Angles(math.rad(-14), 0, 0), Color = PLANK, Material = Enum.Material.WoodPlanks }, model)
	Build.Part(deco({ Name = "Chair", Size = Vector3.new(2, 2.6, 2), CFrame = cf * CFrame.new(-7, floorY + 1.8, -6), Color = Color3.fromRGB(150, 90, 60), Material = Enum.Material.Wood }), model)
	local lineA, lineB = (cf * CFrame.new(-w / 2 - 2, floorY + 7, -5)).Position, (cf * CFrame.new(-w / 2 - 2, floorY + 7, 6)).Position
	Props.Bunting(model, lineA, lineB, { Color3.fromRGB(240, 236, 220), Color3.fromRGB(200, 90, 80), Color3.fromRGB(110, 150, 200) }, 1.2)
	-- Lanterne suspendue sous le porche
	glow(model, (cf * CFrame.new(-w / 2, floorY + 7.5, -7)).Position, Color3.fromRGB(255, 200, 120), 1.2, 16)
	model.Parent = parent
	Ground.PaintDisc(center, 16, center.Y, Enum.Material.Mud)
end

-- Bateau à aubes échoué, penché dans une flaque
local function buildWreck(parent: Instance, center: Vector3)
	local model = Instance.new("Model")
	model.Name = "Wreck"
	local cf = CFrame.lookAt(center, Vector3.new(origin.X, center.Y, origin.Z)) * CFrame.Angles(0, math.rad(70), 0) * CFrame.Angles(0, 0, math.rad(12))
	Build.VerticalCylinder(center + Vector3.new(0, 0.07, 0), 17, 0.14, deco({ Name = "Puddle", Color = Color3.fromRGB(60, 120, 110), Material = Enum.Material.Glass, Transparency = 0.15, Accent = true }), model)
	Build.Part({ Name = "Hull", Size = Vector3.new(9, 4, 22), CFrame = cf * CFrame.new(0, 1.6, 0), Color = Color3.fromRGB(236, 230, 214), Material = Enum.Material.WoodPlanks }, model)
	Build.Wedge({ Name = "Bow", Size = Vector3.new(9, 4, 5), CFrame = cf * CFrame.new(0, 1.6, -13.5) * CFrame.Angles(math.pi, 0, 0), Color = Color3.fromRGB(236, 230, 214), Material = Enum.Material.WoodPlanks }, model)
	Build.Part(deco({ Name = "HullStripe", Size = Vector3.new(9.2, 0.8, 22.2), CFrame = cf * CFrame.new(0, 2.8, 0), Color = Color3.fromRGB(196, 60, 66) }), model)
	Build.Part({ Name = "Cabin", Size = Vector3.new(7, 4.5, 9), CFrame = cf * CFrame.new(0, 5.8, 3), Color = Color3.fromRGB(236, 230, 214), Material = Enum.Material.WoodPlanks }, model)
	Build.Part(deco({ Name = "CabinRoof", Size = Vector3.new(8, 0.6, 10), CFrame = cf * CFrame.new(0, 8.3, 3), Color = Color3.fromRGB(196, 60, 66) }), model)
	for _, x in { -1.6, 1.6 } do
		Build.VerticalCylinder((cf * CFrame.new(x, 11, 5)).Position, 0.6, 6, deco({ Name = "Smokestack", Color = Color3.fromRGB(50, 50, 56), Material = Enum.Material.Metal }), model)
	end
	-- Roue à aubes à l'arrière
	local wheel = cf * CFrame.new(0, 4, 12.5)
	Build.Part(deco({ Name = "Paddlewheel", Shape = Enum.PartType.Cylinder, Size = Vector3.new(6, 8, 8), CFrame = wheel * CFrame.Angles(0, 0, 0), Color = Color3.fromRGB(196, 60, 66) }), model)
	for i = 0, 5 do
		Build.Part(deco({ Name = "Paddle", Size = Vector3.new(6.4, 0.4, 8.4), CFrame = wheel * CFrame.Angles(i / 6 * math.pi, 0, 0), Color = PLANK_DARK }), model)
	end
	-- Nénuphars autour
	local random = MapBase.Random()
	for _ = 1, 9 do
		local a = random:NextNumber(0, math.pi * 2)
		local r = random:NextNumber(10, 16)
		local p = center + Vector3.new(math.cos(a) * r, 0.16, math.sin(a) * r)
		Build.VerticalCylinder(p, random:NextNumber(1, 1.8), 0.1, deco({ Name = "LilyPad", Color = Color3.fromRGB(96, 168, 80) }), model)
		if random:NextNumber() < 0.4 then
			Build.Part(deco({ Name = "LilyFlower", Shape = Enum.PartType.Ball, Size = Vector3.new(0.8, 0.5, 0.8), Position = p + Vector3.new(0, 0.3, 0), Color = Color3.fromRGB(255, 170, 210), Accent = true }), model)
		end
	end
	model.Parent = parent
end

-- Cercle de champignons géants lumineux (piliers pour tourner autour)
local function buildMushroomRing(parent: Instance, center: Vector3)
	local model = Instance.new("Model")
	model.Name = "MushroomRing"
	local random = MapBase.Random()
	local count = 7
	for i = 0, count - 1 do
		local a = i / count * math.pi * 2 + random:NextNumber(-0.1, 0.1)
		local r = 16 + random:NextNumber(-2, 2)
		local p = center + Vector3.new(math.cos(a) * r, 0, math.sin(a) * r)
		local h = random:NextNumber(6, 12)
		local capR = random:NextNumber(3.2, 5)
		local color = i % 2 == 0 and GLOW_A or GLOW_B
		Build.VerticalCylinder(p + Vector3.new(0, h / 2, 0), 1.1, h, { Name = "MushStem", Color = Color3.fromRGB(236, 230, 214) }, model)
		Build.Part({ Name = "MushCap", Shape = Enum.PartType.Ball, Size = Vector3.new(capR * 2, capR * 0.9, capR * 2), Position = p + Vector3.new(0, h + capR * 0.2, 0), Color = color:Lerp(Color3.fromRGB(40, 92, 104), 0.3), Material = Enum.Material.SmoothPlastic, CanCollide = false }, model)
		-- Points lumineux sur le chapeau + lumière
		for k = 0, 3 do
			local b = k / 4 * math.pi * 2 + a
			glow(model, p + Vector3.new(math.cos(b) * capR * 0.6, h + capR * 0.42, math.sin(b) * capR * 0.6), color, 0.7, nil)
		end
		glow(model, p + Vector3.new(0, h - 0.4, 0), color, 0.8, 18)
	end
	-- Pierre centrale moussue
	Props.Rock(model, center, 4, Color3.fromRGB(110, 120, 110))
	for k = 0, 11 do
		local a = k / 12 * math.pi * 2
		glow(model, center + Vector3.new(math.cos(a) * 9, 0.4, math.sin(a) * 9), k % 2 == 0 and GLOW_A or GLOW_B, 0.5, nil)
	end
	model.Parent = parent
	Ground.PaintDisc(center, 22, center.Y, Enum.Material.LeafyGrass)
end

-- Passerelle en planches (posée au sol, poteaux et cordes sur les côtés)
local function buildBoardwalk(parent: Instance, from: Vector3, to: Vector3)
	local delta = Vector3.new(to.X - from.X, 0, to.Z - from.Z)
	local length = delta.Magnitude
	local cf = CFrame.lookAt(from, from + delta)
	for k = 0, math.floor(length / 2.2) do
		Build.Part(deco({ Name = "Plank", Size = Vector3.new(7, 0.4, 2), CFrame = cf * CFrame.new(0, 0.25, -k * 2.2) * CFrame.Angles(0, (k % 3 - 1) * 0.03, 0), Color = PLANK:Lerp(PLANK_DARK, (k % 2) * 0.5), Material = Enum.Material.WoodPlanks }), parent)
	end
	for k = 0, math.floor(length / 10) do
		for _, x in { -3.8, 3.8 } do
			Build.Part({ Name = "Post", Size = Vector3.new(0.6, 3, 0.6), CFrame = cf * CFrame.new(x, 1.5, -k * 10), Color = PLANK_DARK, Material = Enum.Material.Wood }, parent)
		end
		if k % 2 == 1 then
			glow(parent, (cf * CFrame.new(3.8, 3.4, -k * 10)).Position, Color3.fromRGB(255, 196, 110), 0.9, 12)
		end
	end
	for _, x in { -3.8, 3.8 } do
		Build.Part(deco({ Name = "Rope", Size = Vector3.new(0.15, 0.15, length), CFrame = cf * CFrame.new(x, 2.6, -length / 2), Color = Color3.fromRGB(190, 170, 130) }), parent)
	end
end

-- Roseaux et quenouilles (bordure de la zone de jeu)
local function buildCattails(parent: Instance, ground: Vector3)
	local random = MapBase.Random()
	for _ = 1, 5 do
		local p = ground + Vector3.new(random:NextNumber(-1.6, 1.6), 0, random:NextNumber(-1.6, 1.6))
		local h = random:NextNumber(4, 6.5)
		Build.Part(deco({ Name = "Reed", Size = Vector3.new(0.25, h, 0.25), CFrame = CFrame.new(p + Vector3.new(0, h / 2, 0)) * CFrame.Angles(random:NextNumber(-0.1, 0.1), 0, random:NextNumber(-0.1, 0.1)), Color = Color3.fromRGB(110, 150, 70), CastShadow = false }), parent)
		Build.Part(deco({ Name = "Cattail", Size = Vector3.new(0.6, 1.4, 0.6), Position = p + Vector3.new(0, h - 0.5, 0), Color = Color3.fromRGB(120, 80, 50), CastShadow = false }), parent)
	end
end

-- Lucioles : particules + quelques points lumineux fixes
local function buildFireflies(parent: Instance, position: Vector3)
	local host = Build.Part(deco({ Name = "Fireflies", Size = Vector3.new(14, 4, 14), Position = position + Vector3.new(0, 4, 0), Transparency = 1 }), parent)
	local fx = Instance.new("ParticleEmitter")
	fx.Color = ColorSequence.new(Color3.fromRGB(230, 255, 140))
	fx.LightEmission = 1
	fx.Size = NumberSequence.new(0.25)
	fx.Lifetime = NumberRange.new(3, 5)
	fx.Rate = 6
	fx.Speed = NumberRange.new(0.5, 1.5)
	fx.SpreadAngle = Vector2.new(180, 180)
	fx.Parent = host
	local random = MapBase.Random()
	for _ = 1, 6 do
		glow(parent, position + Vector3.new(random:NextNumber(-7, 7), random:NextNumber(1.5, 6), random:NextNumber(-7, 7)), Color3.fromRGB(230, 255, 140), 0.35, nil)
	end
end

local function buildTurnstile(parent: Instance): Model
	local spinner = MapBase.NewSpinner(parent, "Turnstile", CFrame.new(origin))
	local radius = cfg.TurnstileRadius
	Build.VerticalCylinder(origin + Vector3.new(0, 4, 0), 2.5, 8, { Name = "TurnstileHub", Color = Color3.fromRGB(95, 75, 60), Material = Enum.Material.Wood, CanCollide = false, CanQuery = false }, spinner)
	Build.Part({ Name = "TurnstileCap", Shape = Enum.PartType.Ball, Size = Vector3.new(5, 5, 5), Position = origin + Vector3.new(0, 8.5, 0), Color = Color3.fromRGB(170, 210, 90), Material = Enum.Material.Neon, CanCollide = false, CanQuery = false }, spinner)
	for i = 0, ARM_COUNT - 1 do
		local a = i / ARM_COUNT * math.pi * 2
		local dir = Mechanics.Direction(a)
		local mid = origin + dir * (radius / 2 + 1.5) + Vector3.new(0, ARM_HEIGHT / 2 + 0.3, 0)
		Build.Part({
			Name = "TurnstileArm",
			Size = Vector3.new(radius - 3, ARM_HEIGHT, 1.6),
			CFrame = CFrame.lookAt(mid, mid + Vector3.new(-dir.Z, 0, dir.X)) * CFrame.Angles(0, math.rad(90), 0),
			Color = i % 2 == 0 and Color3.fromRGB(120, 95, 70) or Color3.fromRGB(150, 120, 85),
			Material = Enum.Material.WoodPlanks,
			CanCollide = false,
			CanQuery = false,
		}, spinner)
		Build.Part({
			Name = "TurnstileVine",
			Size = Vector3.new(radius - 3, 0.5, 1.8),
			CFrame = CFrame.lookAt(mid + Vector3.new(0, ARM_HEIGHT / 2, 0), mid + Vector3.new(-dir.Z, 0, dir.X) + Vector3.new(0, ARM_HEIGHT / 2, 0)) * CFrame.Angles(0, math.rad(90), 0),
			Color = Color3.fromRGB(110, 160, 80),
			Material = Enum.Material.Grass,
			CanCollide = false,
			CanQuery = false,
		}, spinner)
	end
	Mechanics.SetSpin(spinner, 0, 0)
	return spinner
end

local function buildGeyser(parent: Instance, position: Vector3)
	Build.VerticalCylinder(position + Vector3.new(0, 0.3, 0), cfg.GeyserRadius, 0.6, { Name = "GeyserRim", Color = Color3.fromRGB(110, 105, 95), Material = Enum.Material.Slate }, parent)
	Build.VerticalCylinder(position + Vector3.new(0, 0.62, 0), cfg.GeyserRadius - 1, 0.1, { Name = "GeyserPool", Color = Color3.fromRGB(150, 210, 200), Material = Enum.Material.Glass, Transparency = 0.2, CanCollide = false, CanQuery = false }, parent)
	local water = Build.VerticalCylinder(position + Vector3.new(0, 15, 0), cfg.GeyserRadius - 1.2, 30, {
		Name = "GeyserColumn",
		Color = Color3.fromRGB(200, 240, 240),
		Material = Enum.Material.Glass,
		Transparency = 1,
		CanCollide = false,
		CanQuery = false,
	}, parent)
	local emitterHost = Build.Part({ Name = "GeyserEmitter", Size = Vector3.new(1, 1, 1), Position = position + Vector3.new(0, 0.8, 0), Transparency = 1, CanCollide = false, CanQuery = false }, parent)
	local bubbles = Instance.new("ParticleEmitter")
	bubbles.Name = "Bubbles"
	bubbles.Color = ColorSequence.new(Color3.fromRGB(220, 255, 240))
	bubbles.Size = NumberSequence.new(0.6, 0.2)
	bubbles.Speed = NumberRange.new(2, 5)
	bubbles.Lifetime = NumberRange.new(0.5, 1)
	bubbles.Rate = 0
	bubbles.SpreadAngle = Vector2.new(25, 25)
	bubbles.Parent = emitterHost
	local spray = Instance.new("ParticleEmitter")
	spray.Name = "Spray"
	spray.Color = ColorSequence.new(Color3.fromRGB(235, 255, 255))
	spray.Size = NumberSequence.new(1.6, 0.4)
	spray.Speed = NumberRange.new(50, 70)
	spray.Lifetime = NumberRange.new(0.6, 0.9)
	spray.Rate = 0
	spray.SpreadAngle = Vector2.new(8, 8)
	spray.Parent = emitterHost
	table.insert(geysers, { Position = position, Water = water, Bubbles = bubbles, Spray = spray })
end

function Map.Build(mapOrigin: Vector3, _context: MapContext)
	origin = mapOrigin
	table.clear(geysers)
	local f = MapBase.NewFolder("Map_" .. Map.Id)
	bases = MapBase.BuildArena(f, origin, cfg, THEME)
	turnstile = buildTurnstile(f)
	-- Îlot de boue autour du tourniquet
	Ground.PaintDisc(origin, cfg.TurnstileRadius + 4, origin.Y, Enum.Material.Mud)

	-- Geysers sur deux anneaux
	for i = 0, cfg.GeyserCount - 1 do
		local deg = i * (360 / cfg.GeyserCount) + 30
		local r = (i % 2 == 0) and 48 or 70
		buildGeyser(f, MapBase.Polar(origin, deg, r))
	end

	-- Lieux (un par secteur entre deux camps + coins)
	buildStiltShack(f, MapBase.Polar(origin, 270, 124))
	buildWreck(f, MapBase.Polar(origin, 30, 118))
	buildMushroomRing(f, MapBase.Polar(origin, 150, 116))
	for _, deg in { 45, 135, 225, 315 } do
		buildWillow(f, MapBase.Polar(origin, deg, 172), 1.15)
	end
	for _, spec in { { 10, 140 }, { 70, 150 }, { 110, 142 }, { 190, 146 }, { 250, 160 }, { 290, 150 }, { 350, 162 } } do
		buildDeadTree(f, MapBase.Polar(origin, spec[1], spec[2]), 14 + (spec[1] % 3) * 3)
	end

	-- Passerelles des camps vers le centre, lanternes
	for _, base in bases :: { [string]: MapBase.Base } do
		local toCenter = (origin - base.Center).Unit
		local start = base.Center + toCenter * (base.Radius + 2)
		buildBoardwalk(f, start, origin - toCenter * (cfg.TurnstileRadius + 8))
		local side = Vector3.new(-toCenter.Z, 0, toCenter.X)
		Props.Lamp(f, base.Center + toCenter * (base.Radius + 12) + side * 9, math.atan2(toCenter.X, toCenter.Z))
		Props.Lamp(f, base.Center + toCenter * (base.Radius + 12) - side * 9, math.atan2(toCenter.X, toCenter.Z))
	end

	-- Cachettes : roseaux, buissons, terriers
	for _, deg in { 0, 120, 240 } do
		MapBase.BuildTallGrass(f, MapBase.Polar(origin, deg, 96), 7, Color3.fromRGB(86, 128, 64))
		MapBase.BuildTallGrass(f, MapBase.Polar(origin, deg + 25, 58), 5, Color3.fromRGB(86, 128, 64))
	end
	for _, deg in { 125, 245, 5 } do
		MapBase.BuildBurrow(f, MapBase.Polar(origin, deg, 80), Color3.fromRGB(96, 74, 54))
	end
	for _, deg in { 60, 180, 300 } do
		MapBase.BuildBush(f, MapBase.Polar(origin, deg, 100), 9, Color3.fromRGB(70, 118, 64))
	end
	-- Troncs couchés (obstacles bas : on saute par-dessus)
	for i = 0, 5 do
		local deg = i * 60 + 45
		local p = MapBase.Polar(origin, deg, 36)
		Build.Part({ Name = "Log", Shape = Enum.PartType.Cylinder, Size = Vector3.new(10, 2.6, 2.6), CFrame = CFrame.new(p + Vector3.new(0, 1.3, 0)) * CFrame.Angles(0, math.rad(-deg) + math.pi / 2, 0), Color = BARK, Material = Enum.Material.Wood }, f)
		Build.Part({ Name = "LogMoss", Size = Vector3.new(8, 0.4, 1.6), CFrame = CFrame.new(p + Vector3.new(0, 2.6, 0)) * CFrame.Angles(0, math.rad(-deg) + math.pi / 2, 0), Color = MOSS, CanCollide = false, CanQuery = false }, f)
	end

	-- Bordure : roseaux et quenouilles le long de la limite, lucioles
	local random = MapBase.Random()
	local half = cfg.GroundSize / 2 - 4
	for i = 0, 23 do
		local t = (i + random:NextNumber(0, 0.6)) / 24
		local side = i % 4
		local along = (t * 4 % 1) * 2 - 1
		local p = side == 0 and Vector3.new(along * half, 0, -half) or side == 1 and Vector3.new(half, 0, along * half) or side == 2 and Vector3.new(-along * half, 0, half) or Vector3.new(-half, 0, -along * half)
		buildCattails(f, origin + p)
	end
	for _, deg in { 20, 95, 165, 230, 305 } do
		buildFireflies(f, MapBase.Polar(origin, deg, 90 + (deg % 3) * 15))
	end
	-- Eau du bayou tout autour, entre la limite et les gradins (douves)
	local moat = cfg.GroundSize / 2 + 4
	for side = 0, 3 do
		local rot = CFrame.Angles(0, side * math.pi / 2, 0)
		Build.Part({ Name = "BayouWater", Size = Vector3.new(cfg.GroundSize + 44, 0.3, 18), CFrame = CFrame.new(origin) * rot * CFrame.new(0, -0.05, -(moat + 9)), Color = Color3.fromRGB(56, 150, 156), Material = Enum.Material.Glass, Transparency = 0.15, Reflectance = 0.15, Accent = true }, f)
	end

	f.Parent = workspace
	folder = f
end

function Map.GetSpawns(teamId: string): { CFrame }
	assert(bases, "Map non construite")
	return bases[teamId].Spawns
end

-- ---------------------------------------------------------------------------
-- Tourniquet
-- ---------------------------------------------------------------------------
local function releaseTowardRandomCamp(actor: Actor)
	local ctx = context
	if not ctx or not bases then
		grabbed[actor.Id] = nil
		return
	end
	local root = ctx.GetRoot(actor)
	if actor.Character then
		actor.Character:SetAttribute("Frozen", nil)
	end
	grabbed[actor.Id] = nil
	if not root then
		return
	end
	local campTeam = Teams.Order[math.random(#Teams.Order)]
	local target = bases[campTeam].Center + Vector3.new(math.random(-8, 8), 3, math.random(-8, 8))
	local t = cfg.TurnstileFlightSeconds
	local gravity = workspace.Gravity
	local delta = target - root.Position
	local velocity = Vector3.new(delta.X / t, (delta.Y + 0.5 * gravity * t * t) / t, delta.Z / t)
	ctx.Launch(actor, velocity, 1.2)
	local def = Teams.Get(campTeam)
	if def then
		ctx.AnnounceTo(actor, "Flying to the " .. def.Display .. " camp!", def.Color)
	end
end

local function grab(actor: Actor)
	if grabbed[actor.Id] then
		return
	end
	grabbed[actor.Id] = true
	if actor.Character then
		actor.Character:SetAttribute("Frozen", true)
	end
	local ctx = context
	local root = ctx and ctx.GetRoot(actor)
	if root then
		Remotes.Get("Effect"):FireAllClients("Grab", { Position = root.Position })
	end
	task.delay(cfg.TurnstileHoldSeconds, function()
		if running then
			releaseTowardRandomCamp(actor)
		else
			grabbed[actor.Id] = nil
			if actor.Character then
				actor.Character:SetAttribute("Frozen", nil)
			end
		end
	end)
end

local function updateTurnstile()
	local ctx = context
	local spinner = turnstile
	if not ctx or not spinner then
		return
	end
	local angle = Mechanics.GetAngle(spinner)
	local swept = math.max(0, angle - lastAngle)
	lastAngle = angle
	if swept <= 0 then
		return
	end
	for _, actor in ctx.GetActors() do
		if grabbed[actor.Id] then
			continue
		end
		local root = ctx.GetRoot(actor)
		local character = actor.Character
		if not root or not character or character:GetAttribute("Ragdoll") == true then
			continue
		end
		local p = root.Position
		local rel = Vector3.new(p.X - origin.X, 0, p.Z - origin.Z)
		local r = rel.Magnitude
		if r < 2.5 or r > cfg.TurnstileRadius + 1.5 or p.Y - origin.Y > SAFE_JUMP_HEIGHT then
			continue
		end
		local actorAngle = Mechanics.AngleOf(origin, p)
		local margin = 1.8 / math.max(r, 1)
		for i = 0, ARM_COUNT - 1 do
			local armAngle = angle + i / ARM_COUNT * math.pi * 2
			local d = Mechanics.AngleDelta(actorAngle, armAngle)
			if d <= margin and d >= -(swept + margin) then
				grab(actor)
				break
			end
		end
	end
end

-- ---------------------------------------------------------------------------
-- Geysers
-- ---------------------------------------------------------------------------
local function erupt(geyser)
	local ctx = context
	if not ctx then
		return
	end
	geyser.Bubbles.Rate = 0
	geyser.Spray.Rate = 120
	geyser.Water.Transparency = 0.35
	Remotes.Get("Effect"):FireAllClients("Geyser", { Position = geyser.Position })
	for _, actor in ctx.GetActors() do
		local root = ctx.GetRoot(actor)
		if root then
			local delta = Vector3.new(root.Position.X - geyser.Position.X, 0, root.Position.Z - geyser.Position.Z)
			if delta.Magnitude <= cfg.GeyserRadius + 0.5 then
				local drift = delta.Magnitude > 0.2 and delta.Unit * 12 or Vector3.zero
				ctx.Launch(actor, Vector3.new(drift.X, cfg.GeyserUpSpeed, drift.Z), 1.6)
			end
		end
	end
	task.delay(1.2, function()
		geyser.Spray.Rate = 0
		geyser.Water.Transparency = 1
	end)
end

local function runGeysers()
	while running do
		task.wait(math.max(0.5, cfg.GeyserIntervalSeconds - cfg.GeyserWarningSeconds))
		if not running then
			return
		end
		-- La moitié des geysers (au hasard) se préparent
		local active = {}
		for _, geyser in geysers do
			if math.random() < 0.5 then
				table.insert(active, geyser)
				geyser.Bubbles.Rate = 40
			end
		end
		if #active == 0 and #geysers > 0 then
			local g = geysers[math.random(#geysers)]
			g.Bubbles.Rate = 40
			table.insert(active, g)
		end
		task.wait(cfg.GeyserWarningSeconds)
		if not running then
			return
		end
		for _, geyser in active do
			erupt(geyser)
		end
	end
end

-- ---------------------------------------------------------------------------
-- Mode
-- ---------------------------------------------------------------------------
-- Flèche : vers le groupe de proies visibles le plus proche du centre de l'équipe
local function updatePreyObjectives()
	local ctx = context
	if not ctx then
		return
	end
	local sums: { [string]: Vector3 } = {}
	local counts: { [string]: number } = {}
	for _, actor in ctx.GetActors() do
		local root = ctx.GetRoot(actor)
		local team = actor.Team
		if root and team and not (actor.Character and actor.Character:GetAttribute("Hidden") == true) then
			sums[team] = (sums[team] or Vector3.zero) + root.Position
			counts[team] = (counts[team] or 0) + 1
		end
	end
	for _, teamId in Teams.Order do
		local prey = Teams.GetPrey(teamId)
		if prey and counts[prey] and counts[prey] > 0 then
			ctx.SetObjective(teamId, sums[prey] / counts[prey])
		else
			ctx.SetObjective(teamId, nil)
		end
	end
end

function Map.StartMode(ctx: MapContext)
	context = ctx
	running = true
	ctx.SetScoreInfo(nil, nil)
	if turnstile then
		MapBase.StartSpinner(turnstile, math.pi * 2 / cfg.TurnstileRotationSeconds)
		lastAngle = Mechanics.GetAngle(turnstile)
	end
	geyserThread = task.spawn(runGeysers)
	preyTick = 0
	connection = RunService.Heartbeat:Connect(function(dt)
		if not running then
			return
		end
		updateTurnstile()
		preyTick += dt
		if preyTick >= 1 then
			preyTick = 0
			updatePreyObjectives()
		end
	end)
end

function Map.StopMode()
	running = false
	if connection then
		connection:Disconnect()
		connection = nil
	end
	if geyserThread then
		pcall(task.cancel, geyserThread)
		geyserThread = nil
	end
	if turnstile then
		Mechanics.SetSpin(turnstile, 0)
	end
	local ctx = context
	if ctx then
		for _, actor in ctx.GetActors() do
			if grabbed[actor.Id] and actor.Character then
				actor.Character:SetAttribute("Frozen", nil)
			end
		end
	end
	table.clear(grabbed)
end

function Map.Cleanup()
	Map.StopMode()
	if folder then
		folder:Destroy()
		folder = nil
	end
	table.clear(geysers)
	turnstile = nil
	bases = nil
	context = nil
end

function Map.OnActorRemoved(actor: Actor)
	grabbed[actor.Id] = nil
end

function Map.DebugState()
	return { Turnstile = turnstile, Geysers = geysers, Grabbed = grabbed }
end

return Map

--[[
	TheFarm.lua - mode "Golden Egg"
	  - Un œuf d'or apparaît au centre. Le ramener à sa base marque 1 point.
	    Première équipe à 3 points gagne.
	  - Le porteur est visible par tous (contour or) et 15 % plus lent.
	    S'il est attrapé, l'œuf tombe au sol.
	  - Mécanisme : un bras géant tourne au ras du sol et propulse violemment
	    tout joueur touché (ragdoll court, vol à travers la map). On peut sauter
	    par-dessus.
]]

local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")
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
Map.Id = "TheFarm"

local cfg = Config.Maps.TheFarm
local ARM_INNER_RADIUS = 8
local ARM_HEIGHT = 2.6
local EGG_HEIGHT = 2.2
local SAFE_JUMP_HEIGHT = 6.1 -- au-dessus (hauteur du centre du personnage), le bras passe dessous

local folder: Folder? = nil
local bases: { [string]: MapBase.Base }? = nil
local origin = Vector3.zero
local context: MapContext? = nil
local running = false
local connection: RBXScriptConnection? = nil

local arm: Model? = nil
local lastArmAngle = 0

local egg: Part? = nil
local eggWeld: WeldConstraint? = nil
local eggState = "None" -- "Center" | "Carried" | "Dropped" | "Waiting"
local carrier: Actor? = nil
local carrierLastPosition: Vector3? = nil -- dernière position connue du porteur
local pickupAllowedAt = 0
local eggTick = 0

-- ---------------------------------------------------------------------------
-- Construction
-- ---------------------------------------------------------------------------
local RED = Color3.fromRGB(198, 60, 50)
local WHITE = Color3.fromRGB(246, 244, 238)
-- Paille ocre clair : ne se confond pas avec le jaune des poules (bible visuelle, §1)
local HAY = Color3.fromRGB(214, 184, 120)

-- Thème commun de la map (MapBase.BuildArena, reference/BIBLE_VISUELLE.md) :
-- prairie verte à tenons, chemins de terre claire, terrasses gris-bleu à dessus d'herbe
local THEME: MapBase.ArenaTheme = {
	Seed = 1201,
	Board = Color3.fromRGB(98, 188, 84),
	BoardAlt = Color3.fromRGB(86, 172, 74),
	Path = Enum.Material.Ground,
	PathWidth = 12,
	RingPath = 78,
	CenterRadius = 64,
	Backdrop = { Side = Color3.fromRGB(112, 130, 166), Top = Color3.fromRGB(92, 176, 78), Heights = { 12, 26, 46 } },
	Perimeter = "Fence",
	Trees = { "Block", "Green", "Block", "Green" },
	TreeCount = 80,
	Camp = { Wall = Enum.Material.WoodPlanks },
	GroundColors = {
		Ground = Color3.fromRGB(216, 190, 146), -- terre claire (chemins, aire de battage)
		LeafyGrass = Color3.fromRGB(72, 156, 64), -- herbe du verger et des cachettes
		Mud = Color3.fromRGB(150, 112, 78), -- potager
		Sand = Color3.fromRGB(226, 208, 160), -- berge de la mare
		Pavement = Color3.fromRGB(222, 214, 198),
	},
}

-- Grange rouge ouverte aux deux bouts : on la traverse (raccourci).
-- Faîtage selon X ; portes aux pignons (x = ±w/2).
local function buildBarn(parent: Instance, center: Vector3)
	local model = Instance.new("Model")
	model.Name = "BigRedBarn"
	local w, d, h = 38, 22, 14
	local cf = CFrame.new(center)
	local doorW, doorH = 12, 11
	Build.Part({ Name = "BarnFloor", Size = Vector3.new(w, 0.4, d), CFrame = cf * CFrame.new(0, 0.2, 0), Color = Color3.fromRGB(150, 112, 74), Material = Enum.Material.WoodPlanks }, model)
	-- Longs murs
	for _, side in { -1, 1 } do
		Build.Part({ Name = "BarnWall", Size = Vector3.new(w, h, 1.2), CFrame = cf * CFrame.new(0, h / 2, side * (d / 2 - 0.6)), Color = RED, Material = Enum.Material.WoodPlanks }, model)
		for _, x in { -w * 0.3, 0, w * 0.3 } do
			Props.Window(model, cf * CFrame.Angles(0, side > 0 and math.pi or 0, 0) * CFrame.new(x, h * 0.6, -d / 2 - 0.1), 3.4, 3.4, WHITE, nil)
		end
	end
	-- Pignons percés d'une grande porte
	for _, side in { -1, 1 } do
		local gx = side * (w / 2 - 0.6)
		local pierW = (d - doorW) / 2
		for _, z in { -1, 1 } do
			Build.Part({ Name = "BarnGableWall", Size = Vector3.new(1.2, h, pierW), CFrame = cf * CFrame.new(gx, h / 2, z * (doorW / 2 + pierW / 2)), Color = RED, Material = Enum.Material.WoodPlanks }, model)
		end
		Build.Part({ Name = "BarnLintel", Size = Vector3.new(1.2, h - doorH, doorW), CFrame = cf * CFrame.new(gx, doorH + (h - doorH) / 2, 0), Color = RED, Material = Enum.Material.WoodPlanks }, model)
		-- Encadrement blanc + battants ouverts en croix
		local face = cf * CFrame.new(side * (w / 2 + 0.05), 0, 0)
		Build.Part({ Name = "DoorTrim", Size = Vector3.new(0.4, 0.8, doorW + 1.6), CFrame = face * CFrame.new(0, doorH + 0.4, 0), Color = WHITE, CanCollide = false }, model)
		for _, z in { -1, 1 } do
			Build.Part({ Name = "DoorTrim", Size = Vector3.new(0.4, doorH, 0.8), CFrame = face * CFrame.new(0, doorH / 2, z * (doorW / 2 + 0.4)), Color = WHITE, CanCollide = false }, model)
			-- Battant ouvert contre la façade
			local leaf = face * CFrame.new(side * 0.4, doorH / 2, z * (doorW / 2 + 0.9 + doorW / 4))
			Build.Part({ Name = "DoorLeaf", Size = Vector3.new(0.4, doorH, doorW / 2), CFrame = leaf, Color = RED:Lerp(Color3.new(0, 0, 0), 0.1), Material = Enum.Material.WoodPlanks }, model)
			for _, rot in { 1, -1 } do
				Build.Part({ Name = "DoorCross", Size = Vector3.new(0.45, math.sqrt(doorH * doorH + (doorW / 2) ^ 2) - 0.6, 0.6), CFrame = leaf * CFrame.new(side * 0.1, 0, 0) * CFrame.Angles(rot * math.atan2(doorW / 2, doorH), 0, 0), Color = WHITE, CanCollide = false }, model)
			end
		end
		-- Lucarne du fenil au-dessus de la porte
		Props.Window(model, cf * CFrame.Angles(0, side * math.pi / 2, 0) * CFrame.new(0, h + 3.2, -w / 2 - 0.2), 4, 3.6, WHITE, nil)
	end
	Props.Roof(model, cf * CFrame.new(0, h, 0), { Width = w, Depth = d, Rise = 8.5, Color = Color3.fromRGB(96, 70, 58), Gable = RED, Overhang = 1.8 })
	-- Girouette coq sur le faîtage
	Build.Part({ Name = "VanePole", Size = Vector3.new(0.3, 4, 0.3), CFrame = cf * CFrame.new(0, h + 10.8, 0), Color = Color3.fromRGB(60, 60, 66), Material = Enum.Material.Metal, CanCollide = false }, model)
	Build.Part({ Name = "VaneArrow", Size = Vector3.new(4, 0.3, 0.3), CFrame = cf * CFrame.new(0, h + 12, 0), Color = Color3.fromRGB(60, 60, 66), Material = Enum.Material.Metal, CanCollide = false }, model)
	Build.Part({ Name = "VaneRooster", Size = Vector3.new(2, 1.8, 0.2), CFrame = cf * CFrame.new(0.4, h + 13.4, 0), Color = Color3.fromRGB(60, 60, 66), Material = Enum.Material.Metal, CanCollide = false }, model)
	-- Intérieur : bottes de foin le long des murs, lanternes
	for _, x in { -13, -6, 6, 13 } do
		for _, side in { -1, 1 } do
			Props.HayBale(model, center + Vector3.new(x, 0.4, side * (d / 2 - 3)), 0)
		end
	end
	Props.HayBale(model, center + Vector3.new(-13, 3.4, d / 2 - 3), 0)
	Props.HayBale(model, center + Vector3.new(6, 3.4, -(d / 2 - 3)), 0)
	for _, x in { -9, 9 } do
		local lantern = Build.Part({ Name = "BarnLantern", Size = Vector3.new(1, 1.4, 1), CFrame = cf * CFrame.new(x, h - 2.5, 0), Color = Color3.fromRGB(255, 210, 120), Material = Enum.Material.Neon, CanCollide = false }, model)
		local light = Instance.new("PointLight")
		light.Color = Color3.fromRGB(255, 200, 120)
		light.Range = 18
		light.Brightness = 1.2
		light.Parent = lantern
		Build.Part({ Name = "LanternChain", Size = Vector3.new(0.15, 2.5, 0.15), CFrame = cf * CFrame.new(x, h - 0.6, 0), Color = Color3.fromRGB(60, 60, 66), CanCollide = false }, model)
	end
	-- Panneau "THE BIG RED BARN" au-dessus d'une porte (lisible depuis le centre)
	local sign = Build.Part({ Name = "BarnSign", Size = Vector3.new(0.4, 2.2, 10), CFrame = cf * CFrame.new(w / 2 + 0.3, doorH + 1.6, 0), Color = WHITE, CanCollide = false }, model)
	Build.SurfaceLabel(sign, Enum.NormalId.Right, "BIG RED BARN", { TextColor3 = RED, TextStrokeTransparency = 1, Font = Enum.Font.GothamBlack })
	model.Parent = parent
end

local function buildSilo(parent: Instance, position: Vector3)
	local metal = Color3.fromRGB(206, 212, 218)
	Build.VerticalCylinder(position + Vector3.new(0, 14, 0), 6, 28, { Name = "Silo", Color = metal, Material = Enum.Material.Metal }, parent)
	for k = 1, 4 do
		Build.VerticalCylinder(position + Vector3.new(0, k * 6, 0), 6.15, 0.5, { Name = "SiloRing", Color = metal:Lerp(Color3.new(0, 0, 0), 0.15), Material = Enum.Material.Metal, CanCollide = false }, parent)
	end
	Build.Part({ Name = "SiloDome", Shape = Enum.PartType.Ball, Size = Vector3.new(12.2, 12.2, 12.2), Position = position + Vector3.new(0, 28, 0), Color = RED, Material = Enum.Material.Metal }, parent)
	Build.Part({ Name = "SiloLadder", Size = Vector3.new(1.6, 28, 0.3), CFrame = CFrame.new(position + Vector3.new(0, 14, -6.2)), Color = Color3.fromRGB(70, 72, 80), Material = Enum.Material.DiamondPlate, CanCollide = false }, parent)
end

local function buildWindmill(parent: Instance, position: Vector3, facing: Vector3)
	local cf = CFrame.lookAt(position, Vector3.new(facing.X, position.Y, facing.Z))
	-- Tour en pierre (tronc de cône par étages) et galerie en bois
	for i = 0, 5 do
		local w = 12 - i * 1.2
		Build.Part({ Name = "WindmillTower", Size = Vector3.new(w, 5, w), CFrame = cf * CFrame.new(0, 2.5 + i * 5, 0), Color = Color3.fromRGB(236, 230, 218), Material = Enum.Material.Plaster }, parent)
	end
	Build.Part({ Name = "WindmillBand", Size = Vector3.new(12.4, 0.8, 12.4), CFrame = cf * CFrame.new(0, 5, 0), Color = Color3.fromRGB(150, 150, 160), Material = Enum.Material.Cobblestone }, parent)
	Build.Part({ Name = "Gallery", Size = Vector3.new(11, 0.6, 11), CFrame = cf * CFrame.new(0, 20.3, 0), Color = Color3.fromRGB(140, 98, 62), Material = Enum.Material.WoodPlanks, CanCollide = false }, parent)
	Props.Door(parent, cf * CFrame.new(0, 0, -6.05), 3.4, 6, Color3.fromRGB(120, 80, 50), WHITE)
	Props.Window(parent, cf * CFrame.new(0, 14, -5.45), 2.4, 3, WHITE, Color3.fromRGB(60, 120, 180))
	-- Toit (coiffe) en coins
	Props.Roof(parent, cf * CFrame.new(0, 30, 0), { Width = 7.5, Depth = 7.5, Rise = 5, Color = RED, Gable = RED, Overhang = 0.8 })
	-- Ailes : modèle tournant autour d'un axe horizontal (animé par les clients)
	local hub = cf * CFrame.new(0, 29, -5)
	local pivot = hub * CFrame.Angles(math.rad(90), 0, 0) -- l'axe Y du pivot pointe vers -Z
	local spinner = MapBase.NewSpinner(parent, "WindmillBlades", pivot)
	for i = 0, 3 do
		local a = i * math.pi / 2
		local arm = pivot * CFrame.Angles(0, a, 0)
		Build.Part({ Name = "BladeSpar", Size = Vector3.new(17, 0.5, 0.6), CFrame = arm * CFrame.new(8.5, 0, 0), Color = Color3.fromRGB(110, 76, 50), CanCollide = false, CanQuery = false }, spinner)
		Build.Part({ Name = "BladeSail", Size = Vector3.new(12, 0.2, 3.2), CFrame = arm * CFrame.new(10, 0.1, 1.8), Color = WHITE, Material = Enum.Material.Fabric, CanCollide = false, CanQuery = false }, spinner)
		for k = 0, 3 do
			Build.Part({ Name = "BladeLath", Size = Vector3.new(0.3, 0.3, 3.4), CFrame = arm * CFrame.new(5 + k * 3.6, 0.25, 1.8), Color = Color3.fromRGB(110, 76, 50), CanCollide = false, CanQuery = false }, spinner)
		end
	end
	Build.Part({ Name = "BladeHub", Shape = Enum.PartType.Ball, Size = Vector3.new(2.2, 2.2, 2.2), CFrame = pivot, Color = RED, CanCollide = false, CanQuery = false }, spinner)
	MapBase.StartSpinner(spinner, 0.8)
end

local function buildWaterTower(parent: Instance, position: Vector3)
	local wood = Color3.fromRGB(130, 90, 60)
	for _, x in { -4, 4 } do
		for _, z in { -4, 4 } do
			Build.Part({ Name = "TowerLeg", Size = Vector3.new(1.2, 20, 1.2), CFrame = CFrame.new(position + Vector3.new(x, 10, z)) * CFrame.Angles(math.rad(-z * 0.8), 0, math.rad(x * 0.8)), Color = wood, Material = Enum.Material.Wood }, parent)
		end
	end
	for _, y in { 6, 13 } do
		for _, rot in { 0, 90 } do
			Build.Part({ Name = "TowerBrace", Size = Vector3.new(0.5, 0.5, 11), CFrame = CFrame.new(position + Vector3.new(0, y, 0)) * CFrame.Angles(0, math.rad(rot), math.rad(35)), Color = wood, Material = Enum.Material.Wood, CanCollide = false }, parent)
		end
	end
	Build.Part({ Name = "TowerDeck", Size = Vector3.new(12, 0.8, 12), Position = position + Vector3.new(0, 20, 0), Color = wood, Material = Enum.Material.WoodPlanks }, parent)
	Build.VerticalCylinder(position + Vector3.new(0, 25.5, 0), 5.2, 10, { Name = "Tank", Color = Color3.fromRGB(176, 124, 80), Material = Enum.Material.WoodPlanks }, parent)
	for _, y in { 21.5, 25.5, 29.5 } do
		Build.VerticalCylinder(position + Vector3.new(0, y, 0), 5.35, 0.35, { Name = "TankHoop", Color = Color3.fromRGB(60, 62, 70), Material = Enum.Material.Metal, CanCollide = false }, parent)
	end
	Build.VerticalCylinder(position + Vector3.new(0, 31, 0), 6, 1, { Name = "TankRoof", Color = RED }, parent)
	Build.VerticalCylinder(position + Vector3.new(0, 32, 0), 3.5, 1.2, { Name = "TankRoofTop", Color = RED }, parent)
end

local function buildTractor(parent: Instance, position: Vector3, yaw: number)
	local cf = CFrame.new(position) * CFrame.Angles(0, yaw, 0)
	local green = Color3.fromRGB(52, 156, 72)
	local yellow = Color3.fromRGB(250, 205, 50)
	Build.Part({ Name = "TractorBody", Size = Vector3.new(4.4, 3.4, 8), CFrame = cf * CFrame.new(0, 3.4, -1), Color = green }, parent)
	Build.Wedge({ Name = "TractorHood", Size = Vector3.new(4.4, 1.2, 4), CFrame = cf * CFrame.new(0, 5.7, -3) , Color = green }, parent)
	Build.Part({ Name = "TractorGrill", Size = Vector3.new(3.6, 2.6, 0.3), CFrame = cf * CFrame.new(0, 3.4, -5.1), Color = Color3.fromRGB(50, 52, 60) }, parent)
	Build.Part({ Name = "TractorCab", Size = Vector3.new(5, 0.6, 5), CFrame = cf * CFrame.new(0, 9.2, 2.6), Color = yellow }, parent)
	for _, x in { -2.2, 2.2 } do
		for _, z in { 0.4, 4.8 } do
			Build.Part({ Name = "CabPost", Size = Vector3.new(0.35, 4.2, 0.35), CFrame = cf * CFrame.new(x, 7, z), Color = Color3.fromRGB(50, 52, 60) }, parent)
		end
	end
	Build.Part({ Name = "Seat", Size = Vector3.new(2, 1.6, 1.6), CFrame = cf * CFrame.new(0, 5.8, 3.2), Color = Color3.fromRGB(50, 52, 60) }, parent)
	Build.Part({ Name = "Exhaust", Size = Vector3.new(0.5, 3.5, 0.5), CFrame = cf * CFrame.new(1.4, 7, -3.4), Color = Color3.fromRGB(60, 60, 66), Material = Enum.Material.Metal }, parent)
	for _, wheel in { { -2.9, 3, 2.6 }, { 2.9, 3, 2.6 }, { -2.6, 1.7, -3.6 }, { 2.6, 1.7, -3.6 } } do
		local wcf = cf * CFrame.new(wheel[1], wheel[2], wheel[3])
		Build.Part({ Name = "Tyre", Shape = Enum.PartType.Cylinder, Size = Vector3.new(1.6, wheel[2] * 2, wheel[2] * 2), CFrame = wcf, Color = Color3.fromRGB(38, 38, 44) }, parent)
		Build.Part({ Name = "Rim", Shape = Enum.PartType.Cylinder, Size = Vector3.new(1.7, wheel[2] * 1.1, wheel[2] * 1.1), CFrame = wcf, Color = yellow, CanCollide = false }, parent)
	end
end

-- Verger : rangées de pommiers (troncs bloquants = slalom) et herbes hautes
local function buildOrchard(parent: Instance, center: Vector3, facing: number)
	local model = Instance.new("Model")
	model.Name = "Orchard"
	local cf = CFrame.new(center) * CFrame.Angles(0, facing, 0)
	local leaf = { Color3.fromRGB(92, 176, 66), Color3.fromRGB(74, 156, 58), Color3.fromRGB(110, 190, 74) }
	local random = MapBase.Random()
	for row = -1, 1 do
		for col = -1, 2 do
			local p = (cf * CFrame.new((col - 0.5) * 14, 0, row * 14)).Position
			local tree = Props.RoundTree(model, p, random:NextNumber(0.75, 0.9), leaf)
			-- Pommes rouges dans la couronne
			for k = 1, 6 do
				local a = k / 6 * math.pi * 2 + random:NextNumber(0, 0.5)
				local apple = p + Vector3.new(math.cos(a) * 4.2, random:NextNumber(8.5, 11.5), math.sin(a) * 4.2)
				Build.Part({ Name = "Apple", Shape = Enum.PartType.Ball, Size = Vector3.new(1, 1, 1), Position = apple, Color = Color3.fromRGB(226, 40, 46), Accent = true, CanCollide = false, CanQuery = false, CastShadow = false }, tree)
			end
		end
	end
	-- Panier, caisses de pommes et échelle
	Props.Cart(model, cf * CFrame.new(0, 0, -25) * CFrame.Angles(0, math.rad(80), 0), Color3.fromRGB(220, 50, 50))
	for _, x in { -8, -4.6 } do
		Props.Crate(model, cf * CFrame.new(x, 0, 24) * CFrame.Angles(0, x * 0.05, 0), 2.6)
		for k = 0, 3 do
			Build.Part({ Name = "Apple", Shape = Enum.PartType.Ball, Size = Vector3.new(0.9, 0.9, 0.9), CFrame = cf * CFrame.new(x - 0.6 + (k % 2) * 1.2, 2.9, 24 - 0.6 + math.floor(k / 2) * 1.2), Color = Color3.fromRGB(226, 40, 46), Accent = true, CanCollide = false, CanQuery = false }, model)
		end
	end
	Props.Sign(model, cf * CFrame.new(10, 0, -24) * CFrame.Angles(0, math.pi, 0), "APPLE ORCHARD", Color3.fromRGB(150, 60, 50))
	model.Parent = parent
	Ground.PaintDisc(center, 30, center.Y, Enum.Material.LeafyGrass)
end

-- Potager : sillons de terre (on peut sauter par-dessus), citrouilles, épouvantail
local function buildPumpkinPatch(parent: Instance, center: Vector3, facing: number)
	local model = Instance.new("Model")
	model.Name = "PumpkinPatch"
	local cf = CFrame.new(center) * CFrame.Angles(0, facing, 0)
	local random = MapBase.Random()
	Ground.Paint(cf, 40, 34, center.Y, Enum.Material.Mud)
	for i = -3, 3 do
		local x = i * 5
		Build.Part({ Name = "Furrow", Size = Vector3.new(2.6, 1, 30), CFrame = cf * CFrame.new(x, 0.3, 0), Color = Color3.fromRGB(118, 82, 52), Material = Enum.Material.Ground }, model)
		for j = -2, 2 do
			local z = j * 6 + random:NextNumber(-1, 1)
			local pos = (cf * CFrame.new(x, 0.8, z)).Position
			if (i + j) % 2 == 0 then
				local size = random:NextNumber(2, 3)
				Build.Part({ Name = "Pumpkin", Shape = Enum.PartType.Ball, Size = Vector3.new(size, size * 0.78, size), Position = pos + Vector3.new(0, size * 0.36, 0), Color = Color3.fromRGB(246, 132, 30), Accent = true, CanCollide = false }, model)
				Build.Part({ Name = "PumpkinStem", Size = Vector3.new(0.35, 0.7, 0.35), Position = pos + Vector3.new(0, size * 0.78 + 0.2, 0), Color = Color3.fromRGB(80, 120, 44), CanCollide = false, CanQuery = false }, model)
			else
				Build.Part({ Name = "Cabbage", Shape = Enum.PartType.Ball, Size = Vector3.new(1.8, 1.4, 1.8), Position = pos + Vector3.new(0, 0.5, 0), Color = Color3.fromRGB(130, 196, 90), CanCollide = false, CanQuery = false }, model)
			end
		end
	end
	-- Épouvantail (repère du lieu)
	local s = cf * CFrame.new(0, 0, -19)
	Build.Part({ Name = "ScarecrowPole", Size = Vector3.new(0.6, 9, 0.6), CFrame = s * CFrame.new(0, 4.5, 0), Color = Props.Colors.WoodDark, Material = Enum.Material.Wood }, model)
	Build.Part({ Name = "ScarecrowArms", Size = Vector3.new(8, 0.5, 0.5), CFrame = s * CFrame.new(0, 6.6, 0), Color = Props.Colors.WoodDark, Material = Enum.Material.Wood }, model)
	Build.Part({ Name = "ScarecrowShirt", Size = Vector3.new(3, 3, 1.2), CFrame = s * CFrame.new(0, 5.8, 0), Color = Color3.fromRGB(70, 120, 200), Material = Enum.Material.Fabric }, model)
	Build.Part({ Name = "ScarecrowSleeves", Size = Vector3.new(7, 1.1, 1), CFrame = s * CFrame.new(0, 6.6, 0), Color = Color3.fromRGB(196, 60, 52), Material = Enum.Material.Fabric }, model)
	Build.Part({ Name = "ScarecrowHead", Shape = Enum.PartType.Ball, Size = Vector3.new(2.4, 2.4, 2.4), CFrame = s * CFrame.new(0, 8.4, 0), Color = Color3.fromRGB(236, 206, 140), Material = Enum.Material.Fabric }, model)
	Build.VerticalCylinder((s * CFrame.new(0, 9.4, 0)).Position, 2.4, 0.3, { Name = "HatBrim", Color = Color3.fromRGB(196, 160, 80), Material = Enum.Material.Fabric }, model)
	Build.VerticalCylinder((s * CFrame.new(0, 10.2, 0)).Position, 1.2, 1.6, { Name = "HatTop", Color = Color3.fromRGB(196, 160, 80), Material = Enum.Material.Fabric }, model)
	for _, x in { -3.6, 3.6 } do
		Build.Part({ Name = "Straw", Size = Vector3.new(0.6, 0.9, 0.6), CFrame = s * CFrame.new(x, 6.2, 0), Color = HAY, CanCollide = false }, model)
	end
	-- Corbeau perché
	Build.Part({ Name = "Crow", Size = Vector3.new(0.7, 0.8, 1.3), CFrame = s * CFrame.new(3, 7.3, 0), Color = Color3.fromRGB(30, 30, 36), CanCollide = false }, model)
	-- Bordure : petite palissade blanche avec une entrée de chaque côté
	local corners = { cf * CFrame.new(-21, 0, -18), cf * CFrame.new(21, 0, -18), cf * CFrame.new(21, 0, 18), cf * CFrame.new(-21, 0, 18) }
	for k = 1, 4 do
		local a, b = corners[k].Position, corners[k % 4 + 1].Position
		local mid = (a + b) / 2
		local half = (b - a).Unit * 4
		Props.PicketFence(model, a, mid - half)
		Props.PicketFence(model, mid + half, b)
	end
	model.Parent = parent
end

-- Poulailler surélevé avec rampe
local function buildCoop(parent: Instance, position: Vector3, yaw: number)
	local cf = CFrame.new(position) * CFrame.Angles(0, yaw, 0)
	local model = Instance.new("Model")
	model.Name = "Coop"
	for _, x in { -5.5, 5.5 } do
		for _, z in { -3.5, 3.5 } do
			Build.Part({ Name = "CoopLeg", Size = Vector3.new(0.8, 3, 0.8), CFrame = cf * CFrame.new(x, 1.5, z), Color = Props.Colors.WoodDark, Material = Enum.Material.Wood }, model)
		end
	end
	Build.Part({ Name = "Coop", Size = Vector3.new(13, 6, 9), CFrame = cf * CFrame.new(0, 6, 0), Color = Color3.fromRGB(250, 238, 214), Material = Enum.Material.WoodPlanks }, model)
	Props.Roof(model, cf * CFrame.new(0, 9, 0), { Width = 13, Depth = 9, Rise = 3.6, Color = RED, Gable = Color3.fromRGB(250, 238, 214), Overhang = 1 })
	Build.Part({ Name = "CoopRamp", Size = Vector3.new(2.6, 0.4, 7), CFrame = cf * CFrame.new(0, 1.6, -7.2) * CFrame.Angles(math.rad(-24), 0, 0), Color = Props.Colors.Wood, Material = Enum.Material.WoodPlanks }, model)
	Build.Part({ Name = "CoopDoor", Size = Vector3.new(2.4, 2.8, 0.2), CFrame = cf * CFrame.new(0, 4.6, -4.55), Color = Color3.fromRGB(40, 30, 25), CanCollide = false }, model)
	Props.Window(model, cf * CFrame.new(-4, 6.4, -4.6), 2, 2, WHITE, nil)
	Props.Window(model, cf * CFrame.new(4, 6.4, -4.6), 2, 2, WHITE, nil)
	model.Parent = parent
end

-- Mare aux canards (eau en Part, peu profonde : on peut la traverser)
local function buildDuckPond(parent: Instance, center: Vector3)
	local model = Instance.new("Model")
	model.Name = "DuckPond"
	Ground.PaintDisc(center, 17, center.Y, Enum.Material.Sand)
	Build.VerticalCylinder(center + Vector3.new(0, 0.06, 0), 13, 0.12, { Name = "PondWater", Color = Color3.fromRGB(70, 170, 210), Material = Enum.Material.Glass, Transparency = 0.15, Reflectance = 0.2, Accent = true, CanCollide = false }, model)
	local random = MapBase.Random()
	for i = 0, 9 do
		local a = i / 10 * math.pi * 2 + random:NextNumber(-0.2, 0.2)
		local p = center + Vector3.new(math.cos(a), 0, math.sin(a)) * random:NextNumber(13.5, 15.5)
		if i % 3 == 0 then
			Props.Rock(model, p, random:NextNumber(1.8, 3), nil, false)
		else
			Props.GrassTuft(model, p, Color3.fromRGB(96, 170, 70))
		end
	end
	-- Canards
	for i, spot in { Vector3.new(-4, 0, 2), Vector3.new(3, 0, -3), Vector3.new(5, 0, 4) } do
		local p = center + spot
		local yaw = CFrame.Angles(0, i * 1.9, 0)
		local duck = CFrame.new(p + Vector3.new(0, 0.6, 0)) * yaw
		Build.Part({ Name = "DuckBody", Shape = Enum.PartType.Ball, Size = Vector3.new(1.6, 1, 2.2), CFrame = duck, Color = WHITE, CanCollide = false, CanQuery = false }, model)
		Build.Part({ Name = "DuckHead", Shape = Enum.PartType.Ball, Size = Vector3.new(0.9, 0.9, 0.9), CFrame = duck * CFrame.new(0, 0.7, -0.8), Color = WHITE, CanCollide = false, CanQuery = false }, model)
		Build.Part({ Name = "DuckBeak", Size = Vector3.new(0.4, 0.2, 0.5), CFrame = duck * CFrame.new(0, 0.65, -1.35), Color = Color3.fromRGB(250, 160, 40), Accent = true, CanCollide = false, CanQuery = false }, model)
	end
	-- Petit ponton
	Build.Part({ Name = "Jetty", Size = Vector3.new(3.6, 0.5, 9), CFrame = CFrame.new(center + Vector3.new(0, 0.5, 11)), Color = Props.Colors.Wood, Material = Enum.Material.WoodPlanks }, model)
	for _, x in { -1.6, 1.6 } do
		for _, z in { 7.5, 14.5 } do
			Build.Part({ Name = "JettyPost", Size = Vector3.new(0.6, 2, 0.6), Position = center + Vector3.new(x, 0.6, z), Color = Props.Colors.WoodDark, Material = Enum.Material.Wood }, model)
		end
	end
	model.Parent = parent
end

-- Ferme d'habitation avec jardin (coin de la map)
local function buildFarmhouse(parent: Instance, position: Vector3, facing: Vector3)
	local cf = CFrame.lookAt(position, Vector3.new(facing.X, position.Y, facing.Z))
	Props.House(parent, cf, { Width = 22, Depth = 16, Floors = 2, Height = 16, Wall = Color3.fromRGB(250, 236, 206), Roof = RED, Shutters = Color3.fromRGB(60, 130, 190), Door = Color3.fromRGB(60, 130, 190) })
	-- Porche
	Build.Part({ Name = "Porch", Size = Vector3.new(14, 0.8, 5), CFrame = cf * CFrame.new(0, 1, -10.5), Color = Props.Colors.Wood, Material = Enum.Material.WoodPlanks }, parent)
	for _, x in { -6.5, 6.5 } do
		Build.Part({ Name = "PorchPost", Size = Vector3.new(0.6, 8, 0.6), CFrame = cf * CFrame.new(x, 5, -12.6), Color = WHITE }, parent)
	end
	Build.Wedge({ Name = "PorchRoof", Size = Vector3.new(15, 1.6, 5.6), CFrame = cf * CFrame.new(0, 9.6, -10.6), Color = RED }, parent)
	Props.Bench(parent, cf * CFrame.new(-3.5, 1.4, -9.4) * CFrame.Angles(0, math.pi, 0))
	-- Jardin à palissade blanche
	Props.PicketFence(parent, (cf * CFrame.new(-16, 0, -16)).Position, (cf * CFrame.new(-4, 0, -16)).Position)
	Props.PicketFence(parent, (cf * CFrame.new(4, 0, -16)).Position, (cf * CFrame.new(16, 0, -16)).Position)
	Props.FlowerBed(parent, cf * CFrame.new(-10, 0, -14), 8, 2.4)
	Props.FlowerBed(parent, cf * CFrame.new(10, 0, -14), 8, 2.4)
	Ground.Path({ (cf * CFrame.new(0, 0, -11)).Position, (cf * CFrame.new(0, 0, -30)).Position }, 5, position.Y, Enum.Material.Pavement)
	Props.Tree(parent, (cf * CFrame.new(16, 0, 6)).Position, 1.1, { "Round" })
	Props.Well(parent, (cf * CFrame.new(-18, 0, -6)).Position)
end

local function buildArm(parent: Instance): Model
	local spinner = MapBase.NewSpinner(parent, "SpinningArm", CFrame.new(origin))
	local length = cfg.ArmLength
	local width = cfg.ArmWidth
	-- Poutre rayée (segments alternés)
	local segment = 6
	local count = math.floor((length - ARM_INNER_RADIUS) / segment)
	for i = 0, count - 1 do
		local x0 = ARM_INNER_RADIUS + i * segment
		Build.Part({
			Name = "ArmSegment",
			Size = Vector3.new(segment, ARM_HEIGHT, width),
			CFrame = CFrame.new(origin + Vector3.new(x0 + segment / 2, 0.3 + ARM_HEIGHT / 2, 0)),
			Color = i % 2 == 0 and Color3.fromRGB(225, 50, 45) or Color3.fromRGB(245, 240, 230),
			Material = Enum.Material.SmoothPlastic,
			Accent = true,
			CanCollide = false,
			CanQuery = false,
		}, spinner)
	end
	-- Pare-choc au bout du bras
	Build.VerticalCylinder(origin + Vector3.new(length, 2.2, 0), 2.6, 4.4, {
		Name = "ArmBumper",
		Color = Color3.fromRGB(255, 200, 40),
		Accent = true,
		CanCollide = false,
		CanQuery = false,
	}, spinner)
	-- Roue au départ du bras + moyeu central
	Build.VerticalCylinder(origin + Vector3.new(ARM_INNER_RADIUS, 1.8, 0), 1.8, 3.6, {
		Name = "ArmWheel",
		Color = Color3.fromRGB(60, 60, 70),
		CanCollide = false,
		CanQuery = false,
	}, spinner)
	Build.Part({
		Name = "ArmHubBeam",
		Size = Vector3.new(ARM_INNER_RADIUS, 1, 1.2),
		CFrame = CFrame.new(origin + Vector3.new(ARM_INNER_RADIUS / 2, 9, 0)),
		Color = Color3.fromRGB(60, 60, 70),
		CanCollide = false,
		CanQuery = false,
	}, spinner)
	Build.Part({
		Name = "ArmHubDrop",
		Size = Vector3.new(1, 6, 1),
		CFrame = CFrame.new(origin + Vector3.new(ARM_INNER_RADIUS, 6, 0)),
		Color = Color3.fromRGB(60, 60, 70),
		CanCollide = false,
		CanQuery = false,
	}, spinner)
	Build.VerticalCylinder(origin + Vector3.new(0, 9, 0), 1.6, 2, {
		Name = "ArmHubCap",
		Color = Color3.fromRGB(225, 50, 45),
		CanCollide = false,
		CanQuery = false,
	}, spinner)
	Mechanics.SetSpin(spinner, 0, 0)
	return spinner
end

local function buildNest(parent: Instance)
	-- Aire de battage : terre battue balayée par le bras (zone dangereuse lisible)
	Ground.PaintDisc(origin, cfg.ArmLength + 4, origin.Y, Enum.Material.Ground)
	-- Bordure de pavés autour de l'aire (rappel visuel du danger)
	local count = 48
	for i = 0, count - 1 do
		local a = i / count * math.pi * 2
		local r = cfg.ArmLength + 4.5
		local p = origin + Vector3.new(math.cos(a) * r, 0.15, math.sin(a) * r)
		Build.Part({
			Name = "RingStone",
			Size = Vector3.new(1.6, 0.3, (2 * math.pi * r) / count - 0.5),
			CFrame = CFrame.lookAt(p, p + Vector3.new(-math.sin(a), 0, math.cos(a))),
			Color = i % 2 == 0 and Color3.fromRGB(236, 82, 60) or Color3.fromRGB(246, 238, 220),
			Accent = true,
			CanCollide = false,
			CanQuery = false,
		}, parent)
	end
	-- Poteau fixe au centre (le bras tourne autour) et nid de paille
	Build.VerticalCylinder(origin + Vector3.new(0, 4.5, 0), 1, 9, { Name = "CenterPole", Color = Color3.fromRGB(120, 85, 55), Material = Enum.Material.Wood }, parent)
	Build.VerticalCylinder(origin + Vector3.new(0, 0.5, 0), 6.5, 1, { Name = "Nest", Color = Color3.fromRGB(176, 140, 92), Material = Enum.Material.Fabric }, parent)
	Build.VerticalCylinder(origin + Vector3.new(0, 1.05, 0), 5.2, 0.2, { Name = "NestInner", Color = Color3.fromRGB(150, 112, 70), Material = Enum.Material.Fabric, CanCollide = false }, parent)
	-- Rail circulaire du bras
	for i = 0, 23 do
		local a = i / 24 * math.pi * 2
		local p = origin + Vector3.new(math.cos(a) * ARM_INNER_RADIUS, 0.15, math.sin(a) * ARM_INNER_RADIUS)
		Build.Part({
			Name = "Rail",
			Size = Vector3.new(0.8, 0.3, 2.3),
			CFrame = CFrame.lookAt(p, p + Vector3.new(-math.sin(a), 0, math.cos(a))),
			Color = Color3.fromRGB(70, 70, 80),
			Material = Enum.Material.Metal,
			CanCollide = false,
		}, parent)
	end
	-- Traces de roues dans la terre
	for i = 0, 5 do
		local a = i / 6 * math.pi * 2 + 0.3
		local p = origin + Vector3.new(math.cos(a) * 36, 0.04, math.sin(a) * 36)
		Build.Part({ Name = "Furrow", Size = Vector3.new(16, 0.06, 2.2), CFrame = CFrame.new(p) * CFrame.Angles(0, -a, 0), Color = Color3.fromRGB(150, 110, 72), CanCollide = false, CanQuery = false }, parent)
	end
end

-- Obstacles du cercle intérieur (entre l'aire de battage et les camps) :
-- murets de foin, caisses, abreuvoirs. Ils créent des feintes sans fermer les lignes :
-- posés entre les couloirs des camps (90°, 210°, 330°), jamais dessus.
local function buildRingCover(parent: Instance)
	local random = MapBase.Random()
	for i = 0, 5 do
		local deg = i * 60
		local p = MapBase.Polar(origin, deg, 84)
		local a = math.rad(deg)
		local tangent = math.atan2(-math.cos(a), math.sin(a))
		if i % 2 == 0 then
			-- Mur de bottes de foin (2 + 1 au-dessus)
			local cf = CFrame.new(p) * CFrame.Angles(0, -a + math.pi / 2, 0)
			Props.HayBale(parent, (cf * CFrame.new(-2.6, 0, 0)).Position, -a + math.pi / 2)
			Props.HayBale(parent, (cf * CFrame.new(2.6, 0, 0)).Position, -a + math.pi / 2)
			Props.HayBale(parent, (cf * CFrame.new(0, 3, 0)).Position, -a + math.pi / 2)
			Props.HayBale(parent, (cf * CFrame.new(7, 0, 2)).Position, -a + math.pi / 2 + 0.3, true)
		else
			Props.CrateStack(parent, p, tangent + random:NextNumber(-0.3, 0.3))
			Props.Barrel(parent, p + Vector3.new(4, 0, 3))
		end
	end
	-- Abreuvoirs (bas : on saute par-dessus)
	for _, deg in { 0, 120, 240 } do
		local p = MapBase.Polar(origin, deg, 96)
		local a = math.rad(deg)
		local cf = CFrame.new(p) * CFrame.Angles(0, -a, 0)
		Build.Part({ Name = "Trough", Size = Vector3.new(3, 2, 9), CFrame = cf * CFrame.new(0, 1, 0), Color = Props.Colors.Wood, Material = Enum.Material.WoodPlanks }, parent)
		Build.Part({ Name = "TroughWater", Size = Vector3.new(2.2, 0.2, 8.2), CFrame = cf * CFrame.new(0, 1.95, 0), Color = Color3.fromRGB(80, 170, 210), Material = Enum.Material.Glass, Transparency = 0.2, Accent = true, CanCollide = false }, parent)
	end
end

function Map.Build(mapOrigin: Vector3, _context: MapContext)
	origin = mapOrigin
	local f = MapBase.NewFolder("Map_" .. Map.Id)
	local builtBases = MapBase.BuildArena(f, origin, cfg, THEME)
	bases = builtBases
	buildNest(f)
	arm = buildArm(f)
	buildRingCover(f)

	-- Lieux (un par secteur entre deux camps + coins)
	buildBarn(f, MapBase.Polar(origin, 270, 120))
	buildSilo(f, MapBase.Polar(origin, 270, 120) + Vector3.new(28, 0, -6))
	buildTractor(f, MapBase.Polar(origin, 270, 120) + Vector3.new(-30, 0, 4), math.rad(70))
	buildOrchard(f, MapBase.Polar(origin, 30, 122), math.rad(-30))
	buildPumpkinPatch(f, MapBase.Polar(origin, 150, 120), math.rad(30))
	buildCoop(f, MapBase.Polar(origin, 150, 120) + Vector3.new(-8, 0, 30), math.rad(150))
	buildFarmhouse(f, MapBase.Polar(origin, 45, 170), origin)
	buildDuckPond(f, MapBase.Polar(origin, 135, 158))
	buildWindmill(f, MapBase.Polar(origin, 225, 168), origin)
	buildWaterTower(f, MapBase.Polar(origin, 315, 168))

	-- Petites scènes de la vie de la ferme, regroupées en bordure (jamais sur
	-- les lignes de course : bible visuelle, §4)
	Props.SheepPen(f, CFrame.lookAt(MapBase.Polar(origin, 0, 130), origin), 22, 16, 4)
	for k = 0, 2 do
		Props.Beehive(f, MapBase.Polar(origin, 180 + (k - 1) * 6, 136 + (k % 2) * 4))
	end
	Props.LogPile(f, MapBase.Polar(origin, 300, 134), math.rad(-60))
	Props.Cart(f, CFrame.new(MapBase.Polar(origin, 238, 136)) * CFrame.Angles(0, math.rad(-30), 0), HAY)
	Props.HayBale(f, MapBase.Polar(origin, 244, 142), 0.4, true)

	-- Cachettes : hautes herbes, terriers et buissons
	for _, deg in { 22, 150, 262 } do
		MapBase.BuildTallGrass(f, MapBase.Polar(origin, deg, 100), 6.5)
	end
	for _, deg in { 60, 180, 300 } do
		MapBase.BuildBurrow(f, MapBase.Polar(origin, deg, 74))
	end
	for _, deg in { 0, 120, 240 } do
		MapBase.BuildBush(f, MapBase.Polar(origin, deg, 44), 9)
	end

	-- Clôtures basses avec passages (raccourcis à sauter) entre les lieux
	for _, deg in { 120, 240 } do
		local center = MapBase.Polar(origin, deg, 114)
		local a = math.rad(deg)
		local tangent = Vector3.new(-math.sin(a), 0, math.cos(a))
		Props.Fence(f, center - tangent * 13, center - tangent * 3)
		Props.Fence(f, center + tangent * 3, center + tangent * 13)
	end

	-- Lampadaires à l'entrée des camps (de part et d'autre du chemin)
	for _, base in builtBases do
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
-- Œuf d'or
-- ---------------------------------------------------------------------------
local function groundPosition(position: Vector3): Vector3
	local limit = cfg.GroundSize / 2 - 6
	return Vector3.new(
		math.clamp(position.X, origin.X - limit, origin.X + limit),
		origin.Y + EGG_HEIGHT,
		math.clamp(position.Z, origin.Z - limit, origin.Z + limit)
	)
end

local function createEgg(): Part
	local part = Build.Part({
		Name = "GoldenEgg",
		Size = Vector3.new(2.4, 3, 2.4),
		Color = Color3.fromRGB(255, 205, 40),
		Material = Enum.Material.Neon,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
	})
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = part
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 210, 80)
	light.Range = 14
	light.Brightness = 2
	light.Parent = part
	local sparkles = Instance.new("ParticleEmitter")
	sparkles.Name = "Sparkles"
	sparkles.Color = ColorSequence.new(Color3.fromRGB(255, 240, 150))
	sparkles.LightEmission = 1
	sparkles.Size = NumberSequence.new(0.35, 0)
	sparkles.Lifetime = NumberRange.new(0.6, 1.1)
	sparkles.Rate = 12
	sparkles.Speed = NumberRange.new(2, 4)
	sparkles.SpreadAngle = Vector2.new(180, 180)
	sparkles.Parent = part
	part:SetAttribute("Objective", "GoldenEgg")
	return part
end

local function placeEggOnGround(position: Vector3)
	local part = egg
	if not part then
		return
	end
	if eggWeld then
		eggWeld:Destroy()
		eggWeld = nil
	end
	part.Anchored = true
	part.Massless = false
	part.CFrame = CFrame.new(groundPosition(position))
	part.Parent = folder
	CollectionService:AddTag(part, Mechanics.FloatTag)
end

local function setAllObjectives(position: Vector3?)
	local ctx = context
	if not ctx then
		return
	end
	for _, teamId in Teams.Order do
		ctx.SetObjective(teamId, position)
	end
end

local function clearCarrier()
	local ctx = context
	local current = carrier
	carrier = nil
	if ctx and current then
		ctx.SetCarrier(current, false)
		ctx.SetSpeedModifier(current, "EggCarrier", nil)
		ctx.SetActorObjective(current, nil)
	end
end

local function spawnEggAtCenter()
	clearCarrier()
	if not egg then
		egg = createEgg()
	end
	placeEggOnGround(origin)
	eggState = "Center"
	pickupAllowedAt = os.clock() + 0.5
	setAllObjectives(origin + Vector3.new(0, EGG_HEIGHT, 0))
end

local function dropEgg(position: Vector3, reason: string)
	if eggState ~= "Carried" then
		return
	end
	clearCarrier()
	-- L'œuf porté est rangé dans le personnage : s'il n'a plus de parent, il a
	-- disparu avec lui (réapparition du porteur) et on en refait un
	if egg and egg.Parent == nil then
		egg = createEgg()
		eggWeld = nil
	end
	placeEggOnGround(position)
	eggState = "Dropped"
	pickupAllowedAt = os.clock() + cfg.EggDropPickupDelay
	setAllObjectives(groundPosition(position))
	local ctx = context
	if ctx then
		ctx.Announce(reason == "caught" and "The egg was dropped!" or "Egg knocked loose!", Color3.fromRGB(255, 215, 0))
	end
end

local function pickUp(actor: Actor)
	local ctx = context
	local part = egg
	local character = actor.Character
	if not ctx or not part or not character then
		return
	end
	local head = character:FindFirstChild("Head")
	if not head or not head:IsA("BasePart") then
		return
	end
	CollectionService:RemoveTag(part, Mechanics.FloatTag)
	part.Anchored = false
	part.Massless = true
	part.CFrame = head.CFrame * CFrame.new(0, head.Size.Y / 2 + 2, 0)
	part.Parent = character
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = head
	weld.Part1 = part
	weld.Parent = part
	eggWeld = weld

	carrier = actor
	carrierLastPosition = head.Position
	eggState = "Carried"
	ctx.SetCarrier(actor, true)
	ctx.SetSpeedModifier(actor, "EggCarrier", cfg.CarrierSpeedMultiplier)
	local team = actor.Team :: string
	local def = Teams.Get(team)
	if bases then
		ctx.SetActorObjective(actor, bases[team].Center)
	end
	if def then
		ctx.Announce(def.Display .. " team has the egg!", def.Color)
	end
end

local function score(actor: Actor)
	local ctx = context
	if not ctx then
		return
	end
	local team = actor.Team :: string
	local def = Teams.Get(team)
	local position = ctx.GetRoot(actor)
	clearCarrier()
	if egg then
		CollectionService:RemoveTag(egg, Mechanics.FloatTag)
		egg.Parent = nil
	end
	if eggWeld then
		eggWeld:Destroy()
		eggWeld = nil
	end
	eggState = "Waiting"
	setAllObjectives(nil)
	ctx.AddScore(team, 1)
	ctx.RewardObjective(actor, "GoldenEgg")
	local total = ctx.GetScore(team)
	Remotes.Get("Effect"):FireAllClients("Score", { Position = position and position.Position, Team = team })
	if def then
		ctx.Announce(string.format("%s team scored! (%d/%d)", def.Display, total, cfg.PointsToWin), def.Color)
	end
	if total >= cfg.PointsToWin then
		ctx.EndRound(team, "Objective")
		return
	end
	task.delay(cfg.EggRespawnDelay, function()
		if running and eggState == "Waiting" then
			spawnEggAtCenter()
			if context then
				context.Announce("A new golden egg appeared!", Color3.fromRGB(255, 215, 0))
			end
		end
	end)
end

local function updateEgg()
	local ctx = context
	if not ctx or not bases then
		return
	end
	if eggState == "Carried" then
		local current = carrier
		local root = current and ctx.GetRoot(current)
		if not current or not root or not current.Team then
			dropEgg(carrierLastPosition or (egg and egg.Position) or origin, "lost")
			return
		end
		carrierLastPosition = root.Position
		-- Objectifs : les autres équipes chassent le porteur
		for _, teamId in Teams.Order do
			ctx.SetObjective(teamId, teamId == current.Team and bases[teamId].Center or root.Position)
		end
		if MapBase.IsInBase(bases[current.Team], root.Position) then
			score(current)
		end
	elseif (eggState == "Center" or eggState == "Dropped") and egg and os.clock() >= pickupAllowedAt then
		local eggPos = egg.Position
		local best, bestDistance = nil, cfg.EggPickupRange
		for _, actor in ctx.GetActors() do
			local root = ctx.GetRoot(actor)
			-- Un porteur de coéquipier a les mains prises
			if root and actor.Team and actor.Character and actor.Character:GetAttribute("Ragdoll") ~= true and actor.Character:GetAttribute("Carrying") == nil then
				local d = (root.Position - eggPos).Magnitude
				if d <= bestDistance then
					best, bestDistance = actor, d
				end
			end
		end
		if best then
			pickUp(best)
		end
	end
end

-- ---------------------------------------------------------------------------
-- Bras tournant : détection par balayage d'angle
-- ---------------------------------------------------------------------------
local function updateArm()
	local ctx = context
	local spinner = arm
	if not ctx or not spinner then
		return
	end
	local angle = Mechanics.GetAngle(spinner)
	local swept = math.max(0, angle - lastArmAngle)
	lastArmAngle = angle
	if swept <= 0 then
		return
	end
	for _, actor in ctx.GetActors() do
		local root = ctx.GetRoot(actor)
		local character = actor.Character
		if not root or not character or character:GetAttribute("Ragdoll") == true then
			continue
		end
		local position = root.Position
		local rel = Vector3.new(position.X - origin.X, 0, position.Z - origin.Z)
		local r = rel.Magnitude
		if r < ARM_INNER_RADIUS - 1.5 or r > cfg.ArmLength + 2.5 then
			continue
		end
		if position.Y - origin.Y > SAFE_JUMP_HEIGHT then
			continue
		end
		local margin = (cfg.ArmWidth / 2 + 1.5) / math.max(r, 1)
		local d = Mechanics.AngleDelta(Mechanics.AngleOf(origin, position), angle)
		if d <= margin and d >= -(swept + margin) then
			local tangent = Vector3.new(-math.sin(angle), 0, -math.cos(angle))
			local radial = rel.Unit
			local direction = (tangent * 0.75 + radial * 0.65).Unit
			local velocity = direction * cfg.ArmLaunchSpeed + Vector3.new(0, cfg.ArmLaunchUpSpeed, 0)
			if actor == carrier then
				dropEgg(position, "launched")
			end
			ctx.Launch(actor, velocity, cfg.RagdollSeconds)
		end
	end
end

-- ---------------------------------------------------------------------------
-- Mode
-- ---------------------------------------------------------------------------
function Map.StartMode(ctx: MapContext)
	context = ctx
	running = true
	ctx.SetScoreInfo(cfg.PointsToWin, "eggs")
	spawnEggAtCenter()
	if arm then
		MapBase.StartSpinner(arm, math.pi * 2 / cfg.ArmRotationSeconds)
		lastArmAngle = Mechanics.GetAngle(arm)
	end
	eggTick = 0
	connection = RunService.Heartbeat:Connect(function(dt)
		if not running then
			return
		end
		updateArm()
		eggTick += dt
		if eggTick >= 0.1 then
			eggTick = 0
			updateEgg()
		end
	end)
end

function Map.StopMode()
	running = false
	if connection then
		connection:Disconnect()
		connection = nil
	end
	if arm then
		Mechanics.SetSpin(arm, 0)
	end
	clearCarrier()
end

function Map.Cleanup()
	Map.StopMode()
	if egg then
		egg:Destroy()
		egg = nil
	end
	eggWeld = nil
	eggState = "None"
	if folder then
		folder:Destroy()
		folder = nil
	end
	arm = nil
	bases = nil
	context = nil
end

-- ---------------------------------------------------------------------------
-- Crochets optionnels
-- ---------------------------------------------------------------------------
function Map.OnCapture(_hunter: Actor, victim: Actor)
	if victim == carrier then
		local root = context and context.GetRoot(victim)
		dropEgg(root and root.Position or origin, "caught")
	end
end

function Map.OnActorRemoved(actor: Actor)
	if actor == carrier then
		-- Là où était le porteur (et non à son point de réapparition)
		dropEgg(carrierLastPosition or (egg and egg.Position) or origin, "lost")
	end
end

-- Objectif d'un bot quand il ne chasse ni ne fuit
function Map.GetBotGoal(actor: Actor): Vector3?
	local team = actor.Team
	if not bases or not team then
		return nil
	end
	if actor == carrier then
		return bases[team].Center
	end
	if eggState == "Carried" and carrier then
		local root = context and context.GetRoot(carrier)
		if carrier.Team == actor.Team then
			-- Escorte : rester près du porteur, côté base
			return root and root.Position:Lerp(bases[team].Center, 0.3) or nil
		end
		return root and root.Position or nil
	end
	if egg and (eggState == "Center" or eggState == "Dropped") then
		return egg.Position
	end
	return nil
end

-- Vrai si l'acteur porte l'œuf (utilisé par les bots)
function Map.IsCarrier(actor: Actor): boolean
	return actor == carrier
end

-- Pour les tests : état interne de l'œuf
function Map.DebugState()
	return { State = eggState, Carrier = carrier, Egg = egg, Arm = arm }
end

return Map

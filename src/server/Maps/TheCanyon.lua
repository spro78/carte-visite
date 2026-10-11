--[[
	TheCanyon.lua - mode "Raid"
	  - Chaque base contient 5 œufs. On ne peut voler que dans la base de sa proie.
	    Un œuf volé doit être ramené à sa propre base.
	    L'équipe avec le plus d'œufs à la fin du chrono gagne (une équipe qui
	    réunit tous les œufs gagne tout de suite).
	  - Un voleur attrapé perd son œuf, qui retourne dans la base d'où il vient.
	  - Mécanisme : une catapulte tournante au centre. Sauter dedans te lance
	    dans la direction qu'elle vise à ce moment-là.
	Thème : "Red Rock Gulch", ville fantôme du Far West au soleil couchant :
	mesas en strates, saloon traversable, mine percée d'un tunnel, arche de
	grès, éolienne de pompage, cimetière, campement de chariots.
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
local TerrainKit = require(script.Parent.Parent.Util.TerrainKit)

type Actor = Types.Actor
type MapContext = Types.MapContext

local Map = {}
Map.Id = "TheCanyon"
-- Soleil bas et chaud, brume orangée
Map.Lighting = {
	ClockTime = 16.3,
	Brightness = 2.7,
	OutdoorAmbient = Color3.fromRGB(196, 150, 120),
	Atmosphere = { Density = 0.3, Haze = 1.4, Color = Color3.fromRGB(255, 206, 160), Decay = Color3.fromRGB(230, 140, 90) },
	ColorCorrection = { TintColor = Color3.fromRGB(255, 238, 222), Saturation = 0.2, Contrast = 0.08 },
}

local cfg = Config.Maps.TheCanyon
local BUCKET_HEIGHT = 2.5
local ROCK = Color3.fromRGB(176, 98, 60)

local THEME: MapBase.ArenaTheme = {
	Seed = 3307,
	Floor = Enum.Material.Sand,
	Patches = { Enum.Material.Ground },
	PatchCount = 10,
	Path = Enum.Material.Ground,
	PathWidth = 12,
	RingPath = 76,
	CenterRadius = 26,
	Valley = {
		Style = "Canyon",
		Ground = Enum.Material.Sand,
		Hill = Enum.Material.Sandstone,
		Rock = Enum.Material.Sandstone,
		Strata = { Enum.Material.Sandstone, Enum.Material.Sandstone, Enum.Material.Limestone, Enum.Material.Ground },
		Height = 120,
		Gap = 20,
	},
	Perimeter = "Fence",
	PerimeterColor = Color3.fromRGB(150, 112, 80),
	Trees = { "Round" },
	TreeCount = 0,
	Camp = { Wall = Enum.Material.WoodPlanks, Ground = Enum.Material.Ground },
}

local folder: Folder? = nil
local bases: { [string]: MapBase.Base }? = nil
local origin = Vector3.zero
local context: MapContext? = nil
local running = false
local connection: RBXScriptConnection? = nil
local catapult: Model? = nil
local tick = 0

-- Œufs posés dans chaque base (Parts visibles) et vols en cours
local eggsInBase: { [string]: { Part } } = {}
local carrying: { [string]: { From: string, Part: Part } } = {} -- [actorId]
local lastCatapult: { [string]: number } = {}

-- ---------------------------------------------------------------------------
-- Construction
-- ---------------------------------------------------------------------------
local WOOD = Color3.fromRGB(150, 100, 62)
local WOOD_DARK = Color3.fromRGB(104, 68, 44)
local CREAM = Color3.fromRGB(242, 228, 200)
local CACTUS = Color3.fromRGB(78, 150, 84)

local function deco(props: { [string]: any }): { [string]: any }
	props.CanCollide = false
	props.CanQuery = false
	return props
end

-- Saguaro : tronc côtelé et bras recourbés (taille variable)
local function buildCactus(parent: Instance, ground: Vector3, scale: number?)
	local s = scale or 1
	local random = MapBase.Random()
	local h = 9 * s
	Build.VerticalCylinder(ground + Vector3.new(0, h / 2, 0), 1.1 * s, h, { Name = "Cactus", Color = CACTUS }, parent)
	Build.Part(deco({ Name = "CactusTop", Shape = Enum.PartType.Ball, Size = Vector3.new(2.2, 2.2, 2.2) * s, Position = ground + Vector3.new(0, h, 0), Color = CACTUS }), parent)
	local yaw = random:NextNumber(0, math.pi * 2)
	for i, side in { -1, 1 } do
		local armY = h * (0.4 + i * 0.12)
		local cf = CFrame.new(ground + Vector3.new(0, armY, 0)) * CFrame.Angles(0, yaw, 0)
		Build.Part(deco({ Name = "ArmOut", Size = Vector3.new(2.6 * s, 1.5 * s, 1.5 * s), CFrame = cf * CFrame.new(side * 1.6 * s, 0, 0), Color = CACTUS }), parent)
		local up = 3 * s * (i == 1 and 1 or 0.7)
		Build.VerticalCylinder((cf * CFrame.new(side * 2.7 * s, up / 2 + 0.4, 0)).Position, 0.75 * s, up + 0.8, deco({ Name = "ArmUp", Color = CACTUS }), parent)
		Build.Part(deco({ Name = "ArmTip", Shape = Enum.PartType.Ball, Size = Vector3.new(1.5, 1.5, 1.5) * s, Position = (cf * CFrame.new(side * 2.7 * s, up + 0.8, 0)).Position, Color = CACTUS }), parent)
	end
	-- Fleur rose au sommet
	Build.Part(deco({ Name = "CactusFlower", Shape = Enum.PartType.Ball, Size = Vector3.new(0.8, 0.5, 0.8) * s, Position = ground + Vector3.new(0, h + 1.1 * s, 0), Color = Color3.fromRGB(255, 110, 160), Accent = true }), parent)
end

local function buildTumbleweed(parent: Instance, ground: Vector3)
	Build.Part(deco({ Name = "Tumbleweed", Shape = Enum.PartType.Ball, Size = Vector3.new(2.6, 2.4, 2.6), Position = ground + Vector3.new(0, 1.2, 0), Color = Color3.fromRGB(176, 140, 86), Material = Enum.Material.Fabric, Transparency = 0.2 }), parent)
end

-- Façade de western : bâtiment, fausse façade haute avec enseigne, porche en
-- planches. hollow = true : traversable (portes avant et arrière alignées).
local function buildStorefront(parent: Instance, cf: CFrame, w: number, d: number, h: number, color: Color3, sign: string, hollow: boolean?)
	local model = Instance.new("Model")
	model.Name = "Storefront"
	local trim = CREAM
	if hollow then
		local doorW = 7
		Build.Part({ Name = "Floor", Size = Vector3.new(w, 0.6, d), CFrame = cf * CFrame.new(0, 0.3, 0), Color = WOOD_DARK, Material = Enum.Material.WoodPlanks }, model)
		for _, side in { -1, 1 } do
			Build.Part({ Name = "SideWall", Size = Vector3.new(1, h, d), CFrame = cf * CFrame.new(side * (w / 2 - 0.5), h / 2, 0), Color = color, Material = Enum.Material.WoodPlanks }, model)
			-- Murs avant/arrière de part et d'autre de la porte
			for _, face in { -1, 1 } do
				local pierW = (w - doorW) / 2
				Build.Part({ Name = "FaceWall", Size = Vector3.new(pierW, h, 1), CFrame = cf * CFrame.new(side * (doorW / 2 + pierW / 2), h / 2, face * (d / 2 - 0.5)), Color = color, Material = Enum.Material.WoodPlanks }, model)
			end
		end
		for _, face in { -1, 1 } do
			Build.Part({ Name = "Lintel", Size = Vector3.new(doorW, h - 8, 1), CFrame = cf * CFrame.new(0, 8 + (h - 8) / 2, face * (d / 2 - 0.5)), Color = color, Material = Enum.Material.WoodPlanks }, model)
			-- Portes battantes de saloon (à hauteur de buste)
			for _, s in { -1, 1 } do
				Build.Part(deco({ Name = "BatwingDoor", Size = Vector3.new(doorW / 2 - 0.4, 3.4, 0.25), CFrame = cf * CFrame.new(s * (doorW / 4 + 0.6), 4.2, face * (d / 2 - 0.2)) * CFrame.Angles(0, s * face * 0.9, 0) * CFrame.new(s * 0.6, 0, 0), Color = WOOD }), model)
			end
		end
		Build.Part({ Name = "Ceiling", Size = Vector3.new(w, 1, d), CFrame = cf * CFrame.new(0, h + 0.5, 0), Color = WOOD_DARK, Material = Enum.Material.WoodPlanks }, model)
		-- Comptoir et tabourets à l'intérieur (sur le côté)
		Build.Part({ Name = "Bar", Size = Vector3.new(2.4, 3.6, d * 0.6), CFrame = cf * CFrame.new(w / 2 - 3.5, 1.8, 0), Color = WOOD, Material = Enum.Material.WoodPlanks }, model)
		for k = -1, 1 do
			Build.VerticalCylinder((cf * CFrame.new(w / 2 - 6, 1.3, k * 3)).Position, 0.8, 2.6, { Name = "Stool", Color = Color3.fromRGB(170, 60, 50) }, model)
		end
		local lamp = Build.Part(deco({ Name = "Chandelier", Size = Vector3.new(2, 1, 2), CFrame = cf * CFrame.new(0, h - 1.5, 0), Color = Color3.fromRGB(255, 214, 130), Material = Enum.Material.Neon }), model)
		local light = Instance.new("PointLight")
		light.Color = Color3.fromRGB(255, 200, 120)
		light.Range = 18
		light.Brightness = 1.2
		light.Parent = lamp
	else
		Build.Part({ Name = "Body", Size = Vector3.new(w, h, d), CFrame = cf * CFrame.new(0, h / 2, 0), Color = color, Material = Enum.Material.WoodPlanks }, model)
		Props.Door(model, cf * CFrame.new(0, 0.6, -d / 2 - 0.15), 4, 7, WOOD_DARK, trim)
		for _, x in { -w * 0.3, w * 0.3 } do
			Props.Window(model, cf * CFrame.new(x, 5, -d / 2 - 0.15), 3.2, 3.6, trim, nil)
		end
	end
	-- Fausse façade (plus haute) + enseigne ; ouverte au-dessus de la porte si traversable
	local front = cf * CFrame.new(0, 0, -d / 2 - 0.6)
	local frontColor = color:Lerp(Color3.new(1, 1, 1), 0.08)
	if hollow then
		for _, s in { -1, 1 } do
			Build.Part({ Name = "FalseFront", Size = Vector3.new((w + 1 - 7) / 2, h + 6, 0.8), CFrame = front * CFrame.new(s * (7 / 2 + (w + 1 - 7) / 4), (h + 6) / 2, 0), Color = frontColor, Material = Enum.Material.WoodPlanks, CanCollide = false }, model)
		end
		Build.Part(deco({ Name = "FalseFrontTop", Size = Vector3.new(7, h - 2, 0.8), CFrame = front * CFrame.new(0, 8 + (h - 2) / 2, 0), Color = frontColor, Material = Enum.Material.WoodPlanks }), model)
	else
		Build.Part({ Name = "FalseFront", Size = Vector3.new(w + 1, h + 6, 0.8), CFrame = front * CFrame.new(0, (h + 6) / 2, 0), Color = frontColor, Material = Enum.Material.WoodPlanks, CanCollide = false }, model)
	end
	Build.Part(deco({ Name = "FrontCap", Size = Vector3.new(w + 1.6, 0.8, 1.2), CFrame = front * CFrame.new(0, h + 6.2, 0), Color = trim }), model)
	local board = Build.Part(deco({ Name = "SignBoard", Size = Vector3.new(w * 0.8, 3, 0.4), CFrame = front * CFrame.new(0, h + 3, -0.6), Color = Color3.fromRGB(60, 40, 30) }), model)
	Build.SurfaceLabel(board, Enum.NormalId.Front, sign, { TextColor3 = Color3.fromRGB(255, 220, 140), TextStrokeTransparency = 0.6, Font = Enum.Font.Garamond })
	-- Porche : plancher, poteaux, auvent
	Build.Part({ Name = "Boardwalk", Size = Vector3.new(w + 2, 0.8, 5), CFrame = cf * CFrame.new(0, 0.4, -d / 2 - 3.1), Color = WOOD, Material = Enum.Material.WoodPlanks }, model)
	for _, x in { -w / 2, -w / 6, w / 6, w / 2 } do
		if not hollow or math.abs(x) > 4 then
			Build.Part({ Name = "PorchPost", Size = Vector3.new(0.6, 8, 0.6), CFrame = cf * CFrame.new(x, 4.4, -d / 2 - 5.2), Color = WOOD_DARK, Material = Enum.Material.Wood }, model)
		end
	end
	Build.Wedge(deco({ Name = "PorchRoof", Size = Vector3.new(w + 2, 1.4, 5.6), CFrame = cf * CFrame.new(0, 9, -d / 2 - 3.3), Color = WOOD_DARK }), model)
	model.Parent = parent
	return model
end

-- Ville fantôme en U face au centre : saloon traversable au fond (raccourci
-- vers la ruelle arrière), shérif et magasin général sur les côtés.
local function buildTown(parent: Instance, center: Vector3)
	local facing = CFrame.lookAt(center, Vector3.new(origin.X, center.Y, origin.Z))
	TerrainKit.Paint(facing * CFrame.new(0, 0, 4), 70, 40, center.Y, Enum.Material.Ground)
	buildStorefront(parent, facing * CFrame.new(0, 0, 8), 22, 16, 11, Color3.fromRGB(176, 84, 60), "SALOON", true)
	buildStorefront(parent, facing * CFrame.new(-25, 0, 2) * CFrame.Angles(0, math.rad(-25), 0), 16, 12, 9, Color3.fromRGB(110, 134, 160), "SHERIFF", false)
	buildStorefront(parent, facing * CFrame.new(25, 0, 2) * CFrame.Angles(0, math.rad(25), 0), 18, 12, 10, Color3.fromRGB(196, 160, 96), "GENERAL STORE", false)
	-- Abreuvoir, tonneaux, poteau d'attache
	Build.Part({ Name = "HitchRail", Size = Vector3.new(10, 0.5, 0.5), CFrame = facing * CFrame.new(-9, 3.2, -6), Color = WOOD_DARK, Material = Enum.Material.Wood }, parent)
	for _, x in { -13.5, -4.5 } do
		Build.Part({ Name = "HitchPost", Size = Vector3.new(0.6, 3.4, 0.6), CFrame = facing * CFrame.new(x, 1.7, -6), Color = WOOD_DARK, Material = Enum.Material.Wood }, parent)
	end
	Props.Barrel(parent, (facing * CFrame.new(10, 0, -5)).Position, Color3.fromRGB(130, 82, 50))
	Props.Barrel(parent, (facing * CFrame.new(12.6, 0, -4)).Position, Color3.fromRGB(130, 82, 50))
	Props.Lamp(parent, (facing * CFrame.new(-16, 0, -8)).Position, math.pi)
	Props.Lamp(parent, (facing * CFrame.new(16, 0, -8)).Position, math.pi)
end

-- Mine : mesa en strates percée d'un tunnel boisé (raccourci), rails et wagonnet
local function buildMine(parent: Instance, center: Vector3)
	local random = MapBase.Random()
	local a = math.atan2(center.Z - origin.Z, center.X - origin.X)
	local tangent = Vector3.new(-math.sin(a), 0, math.cos(a))
	TerrainKit.Mesa(center, 18, 26, origin.Y, { Enum.Material.Sandstone, Enum.Material.Limestone, Enum.Material.Sandstone, Enum.Material.Ground }, random)
	local tunnel = CFrame.lookAt(center, center + tangent)
	workspace.Terrain:FillBlock(tunnel * CFrame.new(0, 5.5, 0), Vector3.new(10, 11, 48), Enum.Material.Air)
	-- Cadres de bois tout le long
	for k = -4, 4 do
		local frame = tunnel * CFrame.new(0, 0, k * 5)
		for _, s in { -1, 1 } do
			Build.Part({ Name = "MineBeam", Size = Vector3.new(1, 10, 1), CFrame = frame * CFrame.new(s * 4.4, 5, 0), Color = WOOD_DARK, Material = Enum.Material.Wood }, parent)
		end
		Build.Part({ Name = "MineLintel", Size = Vector3.new(10, 1.2, 1.2), CFrame = frame * CFrame.new(0, 10, 0), Color = WOOD, Material = Enum.Material.Wood }, parent)
		if k % 2 == 0 then
			local lantern = Build.Part(deco({ Name = "MineLantern", Size = Vector3.new(0.8, 1.1, 0.8), CFrame = frame * CFrame.new(0, 8.8, 0), Color = Color3.fromRGB(255, 200, 110), Material = Enum.Material.Neon }), parent)
			local light = Instance.new("PointLight")
			light.Color = Color3.fromRGB(255, 190, 110)
			light.Range = 14
			light.Brightness = 1
			light.Parent = lantern
		end
	end
	-- Rails qui sortent des deux côtés
	for _, dir in { -1, 1 } do
		local from = center + tangent * dir * 10
		local to = center + tangent * dir * 40
		local cf = CFrame.lookAt(from, to)
		local length = (to - from).Magnitude
		for _, x in { -1.6, 1.6 } do
			Build.Part(deco({ Name = "Rail", Size = Vector3.new(0.4, 0.4, length), CFrame = cf * CFrame.new(x, 0.45, -length / 2), Color = Color3.fromRGB(120, 120, 130), Material = Enum.Material.Metal }), parent)
		end
		for k = 0, math.floor(length / 3) do
			Build.Part(deco({ Name = "Sleeper", Size = Vector3.new(4.6, 0.3, 1), CFrame = cf * CFrame.new(0, 0.15, -k * 3), Color = WOOD_DARK, Material = Enum.Material.Wood }), parent)
		end
	end
	local cart = CFrame.lookAt(center + tangent * 24, center + tangent * 30)
	Build.Part({ Name = "MineCart", Size = Vector3.new(4, 2.6, 5), CFrame = cart * CFrame.new(0, 2.2, 0), Color = Color3.fromRGB(96, 98, 110), Material = Enum.Material.Metal }, parent)
	Build.Part(deco({ Name = "Gold", Size = Vector3.new(3.4, 1, 4.4), CFrame = cart * CFrame.new(0, 3.6, 0), Color = Color3.fromRGB(255, 204, 60), Material = Enum.Material.Metal, Accent = true }), parent)
	for _, x in { -2.1, 2.1 } do
		for _, z in { -1.6, 1.6 } do
			Build.Part(deco({ Name = "CartWheel", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.4, 1.4, 1.4), CFrame = cart * CFrame.new(x, 0.8, z), Color = Color3.fromRGB(50, 50, 56) }), parent)
		end
	end
	Props.Sign(parent, CFrame.lookAt(center - (center - origin).Unit * 22 + tangent * 12, origin), "GOLD MINE", WOOD)
end

-- Arche naturelle en grès et jardin de cactus
local function buildRockArch(parent: Instance, center: Vector3)
	local a = math.atan2(center.Z - origin.Z, center.X - origin.X)
	local tangent = Vector3.new(-math.sin(a), 0, math.cos(a))
	local t = workspace.Terrain
	for _, s in { -1, 1 } do
		local foot = center + tangent * s * 11
		t:FillBall(foot + Vector3.new(0, 4, 0), 7, Enum.Material.Sandstone)
		t:FillCylinder(CFrame.new(foot + Vector3.new(0, 11, 0)), 14, 4.5, Enum.Material.Sandstone)
		t:FillBall(foot + Vector3.new(0, 17, 0), 5.5, Enum.Material.Limestone)
	end
	t:FillBlock(CFrame.lookAt(center + Vector3.new(0, 21, 0), center + Vector3.new(0, 21, 0) + tangent), Vector3.new(7, 6, 30), Enum.Material.Sandstone)
	t:FillBall(center + Vector3.new(0, 23, 0), 6, Enum.Material.Limestone)
	local random = MapBase.Random()
	for _ = 1, 7 do
		local ang = random:NextNumber(0, math.pi * 2)
		local r = random:NextNumber(14, 24)
		buildCactus(parent, center + Vector3.new(math.cos(ang) * r, 0, math.sin(ang) * r), random:NextNumber(0.6, 1.05))
	end
	-- Crâne de bœuf posé sur un rocher
	local skull = center + Vector3.new(0, 0, 0) - (center - origin).Unit * 8
	Props.Rock(parent, skull, 3.4, Color3.fromRGB(196, 120, 80))
	Build.Part(deco({ Name = "Skull", Size = Vector3.new(1.8, 1.4, 2), Position = skull + Vector3.new(0, 3, 0), Color = Color3.fromRGB(244, 236, 220) }), parent)
	for _, s in { -1, 1 } do
		Build.Part(deco({ Name = "Horn", Size = Vector3.new(2, 0.4, 0.4), CFrame = CFrame.new(skull + Vector3.new(s * 1.6, 3.6, 0)) * CFrame.Angles(0, 0, s * 0.5), Color = Color3.fromRGB(244, 236, 220) }), parent)
	end
end

-- Éolienne de pompage (roue à pales qui tourne) et citerne
local function buildWindPump(parent: Instance, ground: Vector3)
	for _, x in { -2.5, 2.5 } do
		for _, z in { -2.5, 2.5 } do
			Build.Part({ Name = "PumpLeg", Size = Vector3.new(0.6, 30, 0.6), CFrame = CFrame.new(ground + Vector3.new(x * 0.6, 15, z * 0.6)) * CFrame.Angles(math.rad(-z * 1.6), 0, math.rad(x * 1.6)), Color = Color3.fromRGB(150, 150, 160), Material = Enum.Material.Metal }, parent)
		end
	end
	local hub = CFrame.lookAt(ground + Vector3.new(0, 30, 0), origin + Vector3.new(0, 30, 0)) * CFrame.new(0, 0, -1.4)
	local pivot = hub * CFrame.Angles(math.rad(90), 0, 0)
	local spinner = MapBase.NewSpinner(parent, "WindPump", pivot)
	for i = 0, 15 do
		Build.Part(deco({ Name = "Vane", Size = Vector3.new(5, 0.15, 1.2), CFrame = pivot * CFrame.Angles(0, i / 16 * math.pi * 2, 0) * CFrame.new(3.6, 0, 0) * CFrame.Angles(0.35, 0, 0), Color = Color3.fromRGB(230, 232, 236), Material = Enum.Material.Metal }), spinner)
	end
	Build.Part(deco({ Name = "Hub", Shape = Enum.PartType.Ball, Size = Vector3.new(1.4, 1.4, 1.4), CFrame = pivot, Color = Color3.fromRGB(196, 60, 50) }), spinner)
	MapBase.StartSpinner(spinner, 1.4)
	Build.Part(deco({ Name = "Tail", Size = Vector3.new(0.2, 2.6, 5), CFrame = hub * CFrame.new(0, 0, 4), Color = Color3.fromRGB(196, 60, 50) }), parent)
	Build.VerticalCylinder(ground + Vector3.new(7, 2.5, 3), 4, 5, { Name = "Tank", Color = Color3.fromRGB(150, 156, 166), Material = Enum.Material.CorrodedMetal }, parent)
	Build.VerticalCylinder(ground + Vector3.new(7, 5.05, 3), 3.6, 0.1, deco({ Name = "TankWater", Color = Color3.fromRGB(70, 160, 200), Material = Enum.Material.Glass, Transparency = 0.2 }), parent)
end

-- Cimetière de "Boot Hill" : croix de bois, pierres tombales, clôture
local function buildGraveyard(parent: Instance, center: Vector3)
	local random = MapBase.Random()
	local facing = CFrame.lookAt(center, Vector3.new(origin.X, center.Y, origin.Z))
	for row = 0, 1 do
		for col = -2, 2 do
			local cf = facing * CFrame.new(col * 4.5 + random:NextNumber(-0.5, 0.5), 0, row * 6 + 2) * CFrame.Angles(0, 0, random:NextNumber(-0.12, 0.12))
			if (row + col) % 2 == 0 then
				Build.Part({ Name = "CrossPost", Size = Vector3.new(0.5, 4, 0.5), CFrame = cf * CFrame.new(0, 2, 0), Color = WOOD, Material = Enum.Material.Wood }, parent)
				Build.Part(deco({ Name = "CrossBar", Size = Vector3.new(2.4, 0.5, 0.5), CFrame = cf * CFrame.new(0, 3, 0), Color = WOOD }), parent)
			else
				Build.Part({ Name = "Headstone", Size = Vector3.new(2.2, 2.8, 0.7), CFrame = cf * CFrame.new(0, 1.4, 0), Color = Color3.fromRGB(150, 146, 140), Material = Enum.Material.Slate }, parent)
			end
			Build.Part(deco({ Name = "Mound", Size = Vector3.new(2.2, 0.5, 4), CFrame = cf * CFrame.new(0, 0.2, -2.4), Color = Color3.fromRGB(150, 100, 70), Material = Enum.Material.Ground }), parent)
		end
	end
	Props.Sign(parent, facing * CFrame.new(-14, 0, -4), "BOOT HILL", WOOD_DARK)
	Props.PicketFence(parent, (facing * CFrame.new(-13, 0, -2)).Position, (facing * CFrame.new(-3, 0, -2)).Position, Color3.fromRGB(196, 186, 170))
	Props.PicketFence(parent, (facing * CFrame.new(3, 0, -2)).Position, (facing * CFrame.new(13, 0, -2)).Position, Color3.fromRGB(196, 186, 170))
end

-- Château d'eau de la ville (repère haut)
local function buildWaterTower(parent: Instance, ground: Vector3)
	for _, x in { -3.5, 3.5 } do
		for _, z in { -3.5, 3.5 } do
			Build.Part({ Name = "TowerLeg", Size = Vector3.new(1, 18, 1), Position = ground + Vector3.new(x, 9, z), Color = WOOD_DARK, Material = Enum.Material.Wood }, parent)
		end
	end
	for _, rot in { 0, 90 } do
		Build.Part(deco({ Name = "Brace", Size = Vector3.new(0.4, 0.4, 10), CFrame = CFrame.new(ground + Vector3.new(0, 8, 0)) * CFrame.Angles(0, math.rad(rot), math.rad(38)), Color = WOOD_DARK }), parent)
	end
	Build.VerticalCylinder(ground + Vector3.new(0, 22.5, 0), 5, 9, { Name = "Tank", Color = WOOD, Material = Enum.Material.WoodPlanks }, parent)
	for _, y in { 19, 22.5, 26 } do
		Build.VerticalCylinder(ground + Vector3.new(0, y, 0), 5.15, 0.35, deco({ Name = "Hoop", Color = Color3.fromRGB(70, 70, 76), Material = Enum.Material.Metal }), parent)
	end
	Build.VerticalCylinder(ground + Vector3.new(0, 27.6, 0), 5.8, 1, { Name = "TankRoof", Color = Color3.fromRGB(170, 70, 50) }, parent)
	Build.VerticalCylinder(ground + Vector3.new(0, 28.6, 0), 3, 1.2, { Name = "TankRoofTop", Color = Color3.fromRGB(170, 70, 50) }, parent)
	local board = Build.Part(deco({ Name = "TownName", Size = Vector3.new(9, 2.2, 0.3), CFrame = CFrame.lookAt(ground + Vector3.new(0, 22.5, 0), Vector3.new(origin.X, ground.Y + 22.5, origin.Z)) * CFrame.new(0, 0, -5.3), Color = CREAM }), parent)
	Build.SurfaceLabel(board, Enum.NormalId.Front, "RED ROCK", { TextColor3 = Color3.fromRGB(170, 70, 50), TextStrokeTransparency = 1, Font = Enum.Font.GothamBlack })
end

-- Lit de rivière à sec qui serpente (sable clair, galets) et pont de bois
local function buildDryCreek(parent: Instance, points: { Vector3 })
	TerrainKit.Path(points, 14, origin.Y, Enum.Material.Ground)
	TerrainKit.Path(points, 8, origin.Y, Enum.Material.Salt)
	local random = MapBase.Random()
	for i = 1, #points - 1 do
		local a, b = points[i], points[i + 1]
		for _ = 1, 3 do
			local p = a:Lerp(b, random:NextNumber())
			local side = (b - a).Unit
			p += Vector3.new(-side.Z, 0, side.X) * random:NextNumber(-6, 6)
			Build.Part(deco({ Name = "Pebble", Shape = Enum.PartType.Ball, Size = Vector3.new(1, 0.5, 0.8) * random:NextNumber(0.8, 1.6), Position = p + Vector3.new(0, 0.15, 0), Color = Color3.fromRGB(180, 160, 140), Material = Enum.Material.Slate }), parent)
		end
	end
	-- Pont au milieu
	local mid = math.max(1, #points // 2)
	local a, b = points[mid], points[mid + 1]
	local center = (a + b) / 2
	local along = (b - a).Unit
	local cf = CFrame.lookAt(center, center + Vector3.new(-along.Z, 0, along.X))
	for k = -5, 5 do
		Build.Part(deco({ Name = "BridgePlank", Size = Vector3.new(6, 0.4, 1.4), CFrame = cf * CFrame.new(0, 0.5 + (1 - (k / 5) ^ 2) * 0.8, k * 1.5), Color = k % 2 == 0 and WOOD or WOOD_DARK, Material = Enum.Material.WoodPlanks }), parent)
	end
	for _, x in { -3.2, 3.2 } do
		for _, z in { -7.5, 0, 7.5 } do
			Build.Part({ Name = "BridgePost", Size = Vector3.new(0.5, 3, 0.5), CFrame = cf * CFrame.new(x, 1.8, z), Color = WOOD_DARK, Material = Enum.Material.Wood }, parent)
		end
		Build.Part(deco({ Name = "BridgeRail", Size = Vector3.new(0.3, 0.3, 15.5), CFrame = cf * CFrame.new(x, 3.1, 0), Color = WOOD }), parent)
	end
end

-- Corral rond (clôture avec entrée), abreuvoir, foin et selle sur la barrière
local function buildCorral(parent: Instance, center: Vector3)
	local toCenter = (origin - center).Unit
	local entry = math.atan2(toCenter.Z, toCenter.X)
	local r = 14
	local n = 14
	for i = 0, n - 1 do
		local a1, a2 = i / n * math.pi * 2, (i + 1) / n * math.pi * 2
		local mid = (a1 + a2) / 2
		if math.abs(Mechanics.AngleDelta(mid, entry)) > 0.3 then
			Props.Fence(parent, center + Vector3.new(math.cos(a1) * r, 0, math.sin(a1) * r), center + Vector3.new(math.cos(a2) * r, 0, math.sin(a2) * r), Color3.fromRGB(150, 112, 80))
		end
	end
	TerrainKit.PaintDisc(center, r, origin.Y, Enum.Material.Ground)
	Build.Part({ Name = "Trough", Size = Vector3.new(2.4, 1.8, 7), CFrame = CFrame.new(center + Vector3.new(-6, 0.9, 2)), Color = WOOD, Material = Enum.Material.WoodPlanks }, parent)
	Build.Part(deco({ Name = "TroughWater", Size = Vector3.new(1.8, 0.2, 6.4), CFrame = CFrame.new(center + Vector3.new(-6, 1.75, 2)), Color = Color3.fromRGB(80, 160, 200), Material = Enum.Material.Glass, Transparency = 0.2, Accent = true }), parent)
	Props.HayBale(parent, center + Vector3.new(5, 0, 4), 0.3, true)
	Props.HayBale(parent, center + Vector3.new(6, 0, -2), -0.4)
	Build.Part(deco({ Name = "Saddle", Size = Vector3.new(1.6, 1, 2.2), CFrame = CFrame.new(center - toCenter * r + Vector3.new(0, 3.2, 0)), Color = Color3.fromRGB(120, 60, 40), Material = Enum.Material.Fabric }), parent)
end

-- Campement de chariots bâchés autour d'un feu de camp
-- Campement de chariots bâchés autour d'un feu de camp
local function buildWagon(parent: Instance, cf: CFrame)
	Build.Part({ Name = "WagonBed", Size = Vector3.new(6, 2, 10), CFrame = cf * CFrame.new(0, 3, 0), Color = WOOD, Material = Enum.Material.WoodPlanks }, parent)
	for _, z in { -3.6, 0, 3.6 } do
		Build.Part(deco({ Name = "Hoop", Size = Vector3.new(0.3, 4.6, 0.3), CFrame = cf * CFrame.new(-3, 5.6, z) * CFrame.Angles(0, 0, -0.25), Color = WOOD_DARK }), parent)
		Build.Part(deco({ Name = "Hoop", Size = Vector3.new(0.3, 4.6, 0.3), CFrame = cf * CFrame.new(3, 5.6, z) * CFrame.Angles(0, 0, 0.25), Color = WOOD_DARK }), parent)
	end
	Build.Part({ Name = "Canvas", Shape = Enum.PartType.Cylinder, Size = Vector3.new(9.6, 7, 7), CFrame = cf * CFrame.new(0, 5.4, 0) * CFrame.Angles(0, math.rad(90), 0), Color = CREAM, Material = Enum.Material.Fabric }, parent)
	for _, x in { -3.3, 3.3 } do
		for _, z in { -3.5, 3.5 } do
			Build.Part(deco({ Name = "WagonWheel", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.5, 3.6, 3.6), CFrame = cf * CFrame.new(x, 1.8, z), Color = WOOD_DARK }), parent)
			Build.Part(deco({ Name = "WheelHub", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.7, 0.9, 0.9), CFrame = cf * CFrame.new(x * 1.05, 1.8, z), Color = Color3.fromRGB(70, 70, 76), Material = Enum.Material.Metal }), parent)
		end
	end
end

local function buildCamp(parent: Instance, center: Vector3)
	for i = 0, 2 do
		local a = i / 3 * math.pi * 2 + 0.4
		local p = center + Vector3.new(math.cos(a), 0, math.sin(a)) * 13
		buildWagon(parent, CFrame.lookAt(p, center) * CFrame.Angles(0, math.rad(90), 0))
	end
	-- Feu de camp
	for i = 0, 7 do
		local a = i / 8 * math.pi * 2
		Props.Rock(parent, center + Vector3.new(math.cos(a) * 2.6, 0, math.sin(a) * 2.6), 1.1, Color3.fromRGB(140, 130, 124), false)
	end
	for i = 0, 2 do
		Build.Part(deco({ Name = "Firewood", Size = Vector3.new(0.6, 0.6, 3.6), CFrame = CFrame.new(center + Vector3.new(0, 0.5, 0)) * CFrame.Angles(0, i * 1.05, 0.25), Color = WOOD_DARK }), parent)
	end
	local flame = Build.Part(deco({ Name = "Flame", Shape = Enum.PartType.Ball, Size = Vector3.new(1.8, 2.6, 1.8), Position = center + Vector3.new(0, 1.6, 0), Color = Color3.fromRGB(255, 150, 50), Material = Enum.Material.Neon, CastShadow = false }), parent)
	local fire = Instance.new("Fire")
	fire.Size = 4
	fire.Heat = 6
	fire.Parent = flame
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 160, 80)
	light.Range = 22
	light.Brightness = 1.4
	light.Parent = flame
	for i = 0, 2 do
		local a = i / 3 * math.pi * 2 + 1.4
		Build.Part({ Name = "LogSeat", Shape = Enum.PartType.Cylinder, Size = Vector3.new(4, 1.3, 1.3), CFrame = CFrame.new(center + Vector3.new(math.cos(a) * 6, 0.65, math.sin(a) * 6)) * CFrame.Angles(0, -a + math.pi / 2, 0), Color = WOOD, Material = Enum.Material.Wood }, parent)
	end
end

local function eggSlot(teamId: string, index: number): CFrame
	assert(bases)
	local base = bases[teamId]
	local total = cfg.EggsPerBase * 3
	local cols = 5
	local row = (index - 1) // cols
	local col = (index - 1) % cols
	local localPos = Vector3.new((col - (cols - 1) / 2) * 3, 2.2, 6 + row * 3)
	local _ = total
	return base.CFrame * CFrame.new(localPos)
end

local function newEgg(teamId: string): Part
	local def = Teams.Get(teamId)
	local part = Build.Part({
		Name = "RaidEgg",
		Accent = true,
		Size = Vector3.new(1.8, 2.3, 1.8),
		Color = def and def.Color:Lerp(Color3.new(1, 1, 1), 0.45) or Color3.new(1, 1, 1),
		Material = Enum.Material.SmoothPlastic,
		CanCollide = false,
		CanQuery = false,
	})
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = part
	part:SetAttribute("Objective", "RaidEgg")
	return part
end

-- Range les œufs d'une base sur leurs emplacements
local function layoutBase(teamId: string)
	local list = eggsInBase[teamId]
	for index, part in list do
		part.Anchored = true
		part.CFrame = eggSlot(teamId, index)
		part.Parent = folder
	end
end

local function buildNest(parent: Instance, teamId: string)
	assert(bases)
	local base = bases[teamId]
	Build.Part({
		Name = teamId .. "_EggNest",
		Size = Vector3.new(17, 0.8, 11),
		CFrame = base.CFrame * CFrame.new(0, 1.3, 9),
		Color = Color3.fromRGB(200, 165, 100),
		Material = Enum.Material.Fabric,
	}, parent)
end

local function buildCatapult(parent: Instance): Model
	-- Socle fixe
	Build.VerticalCylinder(origin + Vector3.new(0, 1.5, 0), 6, 3, { Name = "CatapultBase", Color = Color3.fromRGB(120, 80, 50), Material = Enum.Material.WoodPlanks }, parent)
	Build.VerticalCylinder(origin + Vector3.new(0, 0.05, 0), cfg.CatapultArmLength + 5, 0.1, {
		Name = "CatapultRing",
		Color = Color3.fromRGB(190, 120, 70),
		Material = Enum.Material.Sand,
		CanCollide = false,
		CanQuery = false,
	}, parent)
	local spinner = MapBase.NewSpinner(parent, "Catapult", CFrame.new(origin))
	local length = cfg.CatapultArmLength
	Build.Part({
		Name = "CatapultArm",
		Size = Vector3.new(length, 1.2, 1.6),
		CFrame = CFrame.new(origin + Vector3.new(length / 2, 3.6, 0)),
		Color = Color3.fromRGB(150, 100, 60),
		Material = Enum.Material.Wood,
		CanCollide = false,
		CanQuery = false,
	}, spinner)
	-- Godet (traversable : la détection se fait côté serveur)
	Build.VerticalCylinder(origin + Vector3.new(length, BUCKET_HEIGHT, 0), 3, 0.6, {
		Name = "BucketFloor",
		Color = Color3.fromRGB(110, 70, 45),
		Material = Enum.Material.WoodPlanks,
		CanCollide = false,
		CanQuery = false,
	}, spinner)
	for i = 0, 7 do
		local a = i / 8 * math.pi * 2
		Build.Part({
			Name = "BucketWall",
			Size = Vector3.new(0.4, 2, 2.4),
			CFrame = CFrame.new(origin + Vector3.new(length + math.cos(a) * 3, BUCKET_HEIGHT + 1, math.sin(a) * 3)) * CFrame.Angles(0, -a, 0),
			Color = Color3.fromRGB(150, 100, 60),
			Material = Enum.Material.Wood,
			CanCollide = false,
			CanQuery = false,
		}, spinner)
	end
	-- Flèche de visée lumineuse au-delà du godet
	for i = 1, 3 do
		Build.Part({
			Name = "AimArrow",
			Size = Vector3.new(2, 0.2, 2),
			CFrame = CFrame.new(origin + Vector3.new(length + 3 + i * 3, 0.25, 0)) * CFrame.Angles(0, math.rad(45), 0),
			Color = Color3.fromRGB(255, 220, 90),
			Material = Enum.Material.Neon,
			CanCollide = false,
			CanQuery = false,
		}, spinner)
	end
	Build.VerticalCylinder(origin + Vector3.new(0, 4.5, 0), 2, 3, { Name = "CatapultHub", Color = Color3.fromRGB(80, 55, 35), CanCollide = false, CanQuery = false }, spinner)
	Mechanics.SetSpin(spinner, 0, 0)
	return spinner
end

function Map.Build(mapOrigin: Vector3, _context: MapContext)
	origin = mapOrigin
	local f = MapBase.NewFolder("Map_" .. Map.Id)
	folder = f
	bases = MapBase.BuildArena(f, origin, cfg, THEME)
	catapult = buildCatapult(f)

	-- Œufs : 5 par base
	for _, teamId in Teams.Order do
		buildNest(f, teamId)
		eggsInBase[teamId] = {}
		for _ = 1, cfg.EggsPerBase do
			table.insert(eggsInBase[teamId], newEgg(teamId))
		end
		layoutBase(teamId)
	end

	-- Lieux (un par secteur entre deux camps + coins)
	buildTown(f, MapBase.Polar(origin, 270, 122))
	buildWaterTower(f, MapBase.Polar(origin, 270, 122) + Vector3.new(-30, 0, -14))
	-- Gorge qui encadre la ville : deux parois rocheuses en strates
	local strata = { Enum.Material.Sandstone, Enum.Material.Limestone, Enum.Material.Sandstone, Enum.Material.Ground }
	for _, deg in { 249, 291 } do
		TerrainKit.RockRidge(MapBase.Polar(origin, deg, 100), MapBase.Polar(origin, deg, 136), 9, 16, origin.Y, strata, MapBase.Random())
	end
	-- Rivière à sec entre le camp des renards et l'arche
	buildDryCreek(f, {
		MapBase.Polar(origin, 112, 150),
		MapBase.Polar(origin, 120, 128),
		MapBase.Polar(origin, 112, 108),
		MapBase.Polar(origin, 124, 88),
		MapBase.Polar(origin, 118, 70),
	})
	buildMine(f, MapBase.Polar(origin, 30, 128))
	buildRockArch(f, MapBase.Polar(origin, 150, 122))
	buildWindPump(f, MapBase.Polar(origin, 315, 172))
	buildGraveyard(f, MapBase.Polar(origin, 225, 168))
	buildCamp(f, MapBase.Polar(origin, 45, 166))
	buildCamp(f, MapBase.Polar(origin, 135, 168))
	buildCorral(f, MapBase.Polar(origin, 0, 126))
	-- Amas rocheux pour casser les grands espaces (sans fermer les lignes)
	for _, spec in { { 200, 128 }, { 340, 132 }, { 60, 136 }, { 180, 104 } } do
		local p = MapBase.Polar(origin, spec[1], spec[2])
		Props.Rock(f, p, 6, ROCK)
		Props.Rock(f, p + Vector3.new(5, 0, 3), 3.5, ROCK)
		buildCactus(f, p + Vector3.new(-4, 0, 5), 0.7)
	end

	-- Obstacles du cercle intérieur : rochers, cactus, tonneaux, caisses
	local random = MapBase.Random()
	for i = 0, 11 do
		local deg = i * 30 + 15
		local r = (i % 2 == 0) and 64 or 86
		local p = MapBase.Polar(origin, deg, r)
		if i % 3 == 0 then
			buildCactus(f, p, random:NextNumber(0.8, 1.1))
		elseif i % 3 == 1 then
			Props.Rock(f, p, random:NextNumber(5, 8), ROCK)
		else
			Props.CrateStack(f, p, math.rad(deg))
			Props.Barrel(f, p + Vector3.new(4, 0, -3), Color3.fromRGB(130, 82, 50))
		end
	end

	-- Cachettes : herbes sèches, terriers, buissons de sauge
	for _, deg in { 0, 120, 240 } do
		MapBase.BuildTallGrass(f, MapBase.Polar(origin, deg, 104), 6.5, Color3.fromRGB(206, 172, 96))
	end
	for _, deg in { 65, 185, 305 } do
		MapBase.BuildBurrow(f, MapBase.Polar(origin, deg, 70), Color3.fromRGB(176, 104, 64))
	end
	for _, deg in { 20, 140, 260 } do
		MapBase.BuildBush(f, MapBase.Polar(origin, deg, 48), 8, Color3.fromRGB(140, 150, 84))
	end

	-- Lanternes et tonneaux à l'entrée des camps, cactus et virevoltants épars
	for _, base in bases :: { [string]: MapBase.Base } do
		local toCenter = (origin - base.Center).Unit
		local side = Vector3.new(-toCenter.Z, 0, toCenter.X)
		local p = base.Center + toCenter * (base.Radius + 12)
		Props.Lamp(f, p + side * 9, math.atan2(toCenter.X, toCenter.Z))
		Props.Lamp(f, p - side * 9, math.atan2(toCenter.X, toCenter.Z))
	end
	for _ = 1, 18 do
		local p = MapBase.Polar(origin, random:NextNumber(0, 360), random:NextNumber(96, 146))
		if random:NextNumber() < 0.5 then
			buildCactus(f, p, random:NextNumber(0.5, 0.8))
		else
			buildTumbleweed(f, p)
		end
	end
	-- Cactus géants hors de la zone de jeu
	for _ = 1, 30 do
		local a = random:NextNumber(0, 360)
		local p = MapBase.Polar(origin, a, random:NextNumber(185, 260))
		buildCactus(f, TerrainKit.Ground(p) - Vector3.new(0, 0.5, 0), random:NextNumber(1, 1.6))
	end

	f.Parent = workspace
end

function Map.GetSpawns(teamId: string): { CFrame }
	assert(bases, "Map non construite")
	return bases[teamId].Spawns
end

-- ---------------------------------------------------------------------------
-- Logique du Raid
-- ---------------------------------------------------------------------------
local function publishScores()
	local ctx = context
	if not ctx then
		return
	end
	for _, teamId in Teams.Order do
		ctx.SetScore(teamId, #eggsInBase[teamId])
	end
end

local function attachToHead(actor: Actor, part: Part): boolean
	local character = actor.Character
	local head = character and character:FindFirstChild("Head")
	if not character or not head or not head:IsA("BasePart") then
		return false
	end
	part.Anchored = false
	part.Massless = true
	part.CFrame = head.CFrame * CFrame.new(0, head.Size.Y / 2 + 1.6, 0)
	part.Parent = character
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = head
	weld.Part1 = part
	weld.Parent = part
	return true
end

local function releaseCarry(actor: Actor, returnHome: boolean)
	local entry = carrying[actor.Id]
	if not entry then
		return
	end
	carrying[actor.Id] = nil
	local ctx = context
	if ctx then
		ctx.SetCarrier(actor, false)
		ctx.SetSpeedModifier(actor, "RaidEgg", nil)
		ctx.SetActorObjective(actor, nil)
	end
	local weld = entry.Part:FindFirstChildOfClass("WeldConstraint")
	if weld then
		weld:Destroy()
	end
	if returnHome then
		table.insert(eggsInBase[entry.From], entry.Part)
		layoutBase(entry.From)
		publishScores()
	end
end

local function steal(actor: Actor, fromTeam: string)
	local list = eggsInBase[fromTeam]
	local part = table.remove(list)
	if not part then
		return
	end
	if not attachToHead(actor, part) then
		table.insert(list, part)
		return
	end
	carrying[actor.Id] = { From = fromTeam, Part = part }
	local ctx = context
	if ctx and bases then
		if cfg.CarrierVisible then
			ctx.SetCarrier(actor, true)
		end
		ctx.SetSpeedModifier(actor, "RaidEgg", cfg.CarrierSpeedMultiplier)
		ctx.SetActorObjective(actor, bases[actor.Team :: string].Center)
		local thief = Teams.Get(actor.Team)
		local victim = Teams.Get(fromTeam)
		if thief and victim then
			ctx.Announce(string.format("%s stole an egg from the %s!", thief.Display, victim.Plural), thief.Color)
		end
	end
	publishScores()
end

local function deposit(actor: Actor)
	local entry = carrying[actor.Id]
	local team = actor.Team
	if not entry or not team then
		return
	end
	releaseCarry(actor, false)
	table.insert(eggsInBase[team], entry.Part)
	layoutBase(team)
	publishScores()
	local ctx = context
	if ctx then
		ctx.RewardObjective(actor, "RaidEgg")
		local def = Teams.Get(team)
		local root = ctx.GetRoot(actor)
		Remotes.Get("Effect"):FireAllClients("Score", { Position = root and root.Position, Team = team })
		if def then
			ctx.Announce(string.format("%s team now has %d eggs!", def.Display, #eggsInBase[team]), def.Color)
		end
		-- Tous les œufs réunis : victoire immédiate
		if #eggsInBase[team] >= cfg.EggsPerBase * #Teams.Order then
			ctx.EndRound(team, "Objective")
		end
	end
end

local function updateRaid()
	local ctx = context
	if not ctx or not bases then
		return
	end
	for _, actor in ctx.GetActors() do
		local team = actor.Team
		local root = ctx.GetRoot(actor)
		if not team or not root or (actor.Character and actor.Character:GetAttribute("Ragdoll") == true) then
			continue
		end
		local entry = carrying[actor.Id]
		if entry then
			if MapBase.IsInBase(bases[team], root.Position) then
				deposit(actor)
			end
		else
			local preyTeam = Teams.GetPrey(team)
			if preyTeam and #eggsInBase[preyTeam] > 0 and MapBase.IsInBase(bases[preyTeam], root.Position) then
				steal(actor, preyTeam)
			end
		end
	end
	-- Objectifs : chaque équipe vise la base de sa proie
	for _, teamId in Teams.Order do
		local preyTeam = Teams.GetPrey(teamId)
		ctx.SetObjective(teamId, preyTeam and #eggsInBase[preyTeam] > 0 and bases[preyTeam].Center or nil)
	end
end

-- Catapulte : un acteur dans le godet est lancé dans la direction visée
local function updateCatapult()
	local ctx = context
	local spinner = catapult
	if not ctx or not spinner then
		return
	end
	local angle = Mechanics.GetAngle(spinner)
	local aim = Mechanics.Direction(angle)
	local bucket = origin + aim * cfg.CatapultArmLength
	local now = os.clock()
	for _, actor in ctx.GetActors() do
		local root = ctx.GetRoot(actor)
		if not root or (actor.Character and actor.Character:GetAttribute("Ragdoll") == true) then
			continue
		end
		if lastCatapult[actor.Id] and now - lastCatapult[actor.Id] < cfg.CatapultCooldown then
			continue
		end
		local p = root.Position
		local horizontal = Vector3.new(p.X - bucket.X, 0, p.Z - bucket.Z).Magnitude
		local height = p.Y - origin.Y
		if horizontal <= 3.4 and height >= BUCKET_HEIGHT + 1.2 and height <= BUCKET_HEIGHT + 9 then
			lastCatapult[actor.Id] = now
			local limit = cfg.GroundSize / 2 - 12
			local target = bucket + aim * cfg.CatapultRange
			target = Vector3.new(
				math.clamp(target.X, origin.X - limit, origin.X + limit),
				origin.Y + 3,
				math.clamp(target.Z, origin.Z - limit, origin.Z + limit)
			)
			local gravity = workspace.Gravity
			local t = cfg.CatapultFlightSeconds
			local delta = target - p
			local velocity = Vector3.new(delta.X / t, (delta.Y + 0.5 * gravity * t * t) / t, delta.Z / t)
			ctx.Launch(actor, velocity, 0.8)
		end
	end
end

function Map.StartMode(ctx: MapContext)
	context = ctx
	running = true
	ctx.SetScoreInfo(nil, "eggs")
	publishScores()
	if catapult then
		MapBase.StartSpinner(catapult, math.pi * 2 / cfg.CatapultRotationSeconds)
	end
	tick = 0
	connection = RunService.Heartbeat:Connect(function(dt)
		if not running then
			return
		end
		updateCatapult()
		tick += dt
		if tick >= 0.1 then
			tick = 0
			updateRaid()
		end
	end)
end

function Map.StopMode()
	running = false
	if connection then
		connection:Disconnect()
		connection = nil
	end
	if catapult then
		Mechanics.SetSpin(catapult, 0)
	end
	local ctx = context
	for actorId in carrying do
		if ctx then
			for _, actor in ctx.GetActors() do
				if actor.Id == actorId then
					ctx.SetCarrier(actor, false)
					ctx.SetSpeedModifier(actor, "RaidEgg", nil)
				end
			end
		end
	end
end

function Map.Cleanup()
	Map.StopMode()
	for _, entry in carrying do
		entry.Part:Destroy()
	end
	table.clear(carrying)
	for _, list in eggsInBase do
		for _, part in list do
			part:Destroy()
		end
	end
	table.clear(eggsInBase)
	table.clear(lastCatapult)
	if folder then
		folder:Destroy()
		folder = nil
	end
	catapult = nil
	bases = nil
	context = nil
end

-- Crochets
function Map.OnCapture(_hunter: Actor, victim: Actor)
	if carrying[victim.Id] then
		local entry = carrying[victim.Id]
		releaseCarry(victim, true)
		local ctx = context
		local def = Teams.Get(entry.From)
		if ctx and def then
			ctx.Announce("The egg went back to the " .. def.Plural .. "!", def.Color)
		end
	end
end

function Map.OnActorRemoved(actor: Actor)
	if carrying[actor.Id] then
		releaseCarry(actor, true)
	end
end

function Map.ResolveTimeUp(): string?
	local best, bestCount, tie = nil, -1, false
	for _, teamId in Teams.Order do
		local n = #(eggsInBase[teamId] or {})
		if n > bestCount then
			best, bestCount, tie = teamId, n, false
		elseif n == bestCount then
			tie = true
		end
	end
	if tie then
		return nil
	end
	return best
end

function Map.IsCarrier(actor: Actor): boolean
	return carrying[actor.Id] ~= nil
end

function Map.GetBotGoal(actor: Actor): Vector3?
	local team = actor.Team
	if not bases or not team then
		return nil
	end
	if carrying[actor.Id] then
		return bases[team].Center
	end
	local preyTeam = Teams.GetPrey(team)
	if preyTeam and #eggsInBase[preyTeam] > 0 then
		return bases[preyTeam].Center
	end
	-- Plus rien à voler : défendre sa base
	return bases[team].Center
end

function Map.DebugState()
	local counts = {}
	for teamId, list in eggsInBase do
		counts[teamId] = #list
	end
	return { Eggs = counts, Carrying = carrying, Catapult = catapult }
end

return Map

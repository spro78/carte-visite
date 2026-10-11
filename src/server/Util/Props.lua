--[[
	Props.lua
	Bibliothèque de décors 3D construits en Parts (aucun asset externe) :
	arbres (feuillus, ronds, sapins), buissons, rochers, maisons à toit en
	pente, granges, clôtures, haies, murets, lampadaires, bancs, caisses,
	tonneaux, massifs de fleurs, guirlandes de fanions, puits, charrettes...

	Toutes les fonctions prennent un parent et un CFrame (ou une position au
	sol). Les décors bloquants gardent leur collision ; le feuillage et les
	petits détails n'en ont pas.
]]

local Build = require(script.Parent.Build)

local Props = {}

local random = Random.new()

function Props.Seed(seed: number)
	random = Random.new(seed)
end

function Props.Random(): Random
	return random
end

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

local function vary(color: Color3, amount: number): Color3
	local k = random:NextNumber(-amount, amount)
	if k >= 0 then
		return color:Lerp(Color3.new(1, 1, 1), k)
	end
	return color:Lerp(Color3.new(0, 0, 0), -k)
end

local function deco(props: { [string]: any }): { [string]: any }
	props.CanCollide = false
	props.CanQuery = false
	props.CanTouch = false
	return props
end

Props.Colors = {
	Trunk = rgb(118, 82, 56),
	TrunkDark = rgb(92, 62, 42),
	Leaf = { rgb(96, 186, 72), rgb(74, 164, 62), rgb(124, 200, 78) },
	Autumn = { rgb(255, 140, 40), rgb(238, 82, 44), rgb(255, 192, 48), rgb(250, 116, 52) },
	Pine = { rgb(46, 132, 82), rgb(38, 116, 72), rgb(58, 146, 90) },
	Rock = rgb(150, 154, 164),
	Wood = rgb(160, 112, 70),
	WoodDark = rgb(112, 76, 48),
	White = rgb(246, 244, 238),
	Flower = { rgb(255, 82, 96), rgb(255, 214, 64), rgb(255, 255, 255), rgb(186, 112, 255), rgb(255, 150, 196), rgb(90, 170, 255) },
}

-- ---------------------------------------------------------------------------
-- Végétation
-- ---------------------------------------------------------------------------

-- Feuillu "cubique" (façon Huss Valley) : tronc avec deux branches, couronne
-- de cubes de tailles variées légèrement tournés.
function Props.BlockTree(parent: Instance, ground: Vector3, scale: number?, palette: { Color3 }?)
	local s = scale or 1
	local colors = palette or Props.Colors.Autumn
	local model = Instance.new("Model")
	model.Name = "Tree"
	local yaw = random:NextNumber(0, math.pi * 2)
	local base = CFrame.new(ground) * CFrame.Angles(0, yaw, 0)
	local trunkH = 9 * s
	Build.Part({ Name = "Trunk", Size = Vector3.new(2.2, trunkH, 2.2) * Vector3.new(s, 1, s), CFrame = base * CFrame.new(0, trunkH / 2, 0), Color = Props.Colors.Trunk, Material = Enum.Material.Wood }, model)
	Build.Part({ Name = "Root", Size = Vector3.new(3.4 * s, 1.2 * s, 3.4 * s), CFrame = base * CFrame.new(0, 0.6 * s, 0) * CFrame.Angles(0, 0.78, 0), Color = Props.Colors.TrunkDark, Material = Enum.Material.Wood }, model)
	for _, side in { -1, 1 } do
		Build.Part(deco({ Name = "Branch", Size = Vector3.new(1.1, 4.5, 1.1) * s, CFrame = base * CFrame.new(side * 1.6 * s, trunkH * 0.82, 0) * CFrame.Angles(0, 0, math.rad(-side * 40)), Color = Props.Colors.Trunk, Material = Enum.Material.Wood }), model)
	end
	local crown = trunkH + 2.5 * s
	local cubes = {
		{ 0, 0, 0, 8.5 }, { 3.6, -1.6, 1.4, 6.2 }, { -3.4, -1.2, -1.2, 6.4 }, { 0.8, 3.4, -0.6, 5.8 },
		{ -1.2, -2.2, 3.2, 5.2 }, { 1.6, -2, -3.4, 5 }, { -2.6, 2.4, 1.8, 4.2 }, { 2.8, 2, 2.6, 3.8 },
	}
	for i, c in cubes do
		local size = c[4] * s * random:NextNumber(0.88, 1.1)
		Build.Part({
			Name = "Leaves",
			Size = Vector3.new(size, size, size),
			CFrame = base * CFrame.new(c[1] * s, crown + c[2] * s, c[3] * s) * CFrame.Angles(random:NextNumber(-0.4, 0.4), random:NextNumber(0, 1.5), random:NextNumber(-0.4, 0.4)),
			Color = vary(colors[(i - 1) % #colors + 1], 0.06),
			Material = Enum.Material.SmoothPlastic,
			CanCollide = i == 1,
		}, model)
	end
	model.Parent = parent
	return model
end

-- Arbre rond : couronne de boules de feuillage
function Props.RoundTree(parent: Instance, ground: Vector3, scale: number?, palette: { Color3 }?)
	local s = scale or 1
	local colors = palette or Props.Colors.Leaf
	local model = Instance.new("Model")
	model.Name = "Tree"
	local yaw = random:NextNumber(0, math.pi * 2)
	local base = CFrame.new(ground) * CFrame.Angles(0, yaw, 0)
	local trunkH = 8 * s
	Build.VerticalCylinder((base * CFrame.new(0, trunkH / 2, 0)).Position, 1.1 * s, trunkH, { Name = "Trunk", Color = Props.Colors.Trunk, Material = Enum.Material.Wood }, model)
	local crown = trunkH + 3 * s
	local balls = { { 0, 0, 0, 10 }, { 3.4, -1.4, 1.2, 7 }, { -3.2, -1, -1.4, 7.4 }, { 0.6, 3, -0.8, 7 }, { -1, -1.6, 3.2, 6.4 }, { 1.4, -1.8, -3.2, 6 } }
	for i, b in balls do
		local size = b[4] * s * random:NextNumber(0.9, 1.1)
		Build.Part({
			Name = "Leaves",
			Shape = Enum.PartType.Ball,
			Size = Vector3.new(size, size, size),
			CFrame = base * CFrame.new(b[1] * s, crown + b[2] * s, b[3] * s),
			Color = vary(colors[(i - 1) % #colors + 1], 0.05),
			Material = Enum.Material.SmoothPlastic,
			CanCollide = i == 1,
		}, model)
	end
	model.Parent = parent
	return model
end

-- Sapin : étages de feuillage carrés tournés de 45° (silhouette conique)
function Props.PineTree(parent: Instance, ground: Vector3, scale: number?, palette: { Color3 }?)
	local s = scale or 1
	local colors = palette or Props.Colors.Pine
	local model = Instance.new("Model")
	model.Name = "Tree"
	local yaw = random:NextNumber(0, math.pi / 2)
	local base = CFrame.new(ground) * CFrame.Angles(0, yaw, 0)
	Build.Part({ Name = "Trunk", Size = Vector3.new(1.6 * s, 6 * s, 1.6 * s), CFrame = base * CFrame.new(0, 3 * s, 0), Color = Props.Colors.TrunkDark, Material = Enum.Material.Wood }, model)
	local tiers = 4
	for i = 0, tiers - 1 do
		local w = (11 - i * 2.4) * s
		local h = 4.2 * s
		local y = (5 + i * 3.4) * s
		Build.Part({
			Name = "Needles",
			Size = Vector3.new(w, h, w),
			CFrame = base * CFrame.new(0, y + h / 2, 0) * CFrame.Angles(0, (i % 2) * math.rad(45), 0),
			Color = vary(colors[i % #colors + 1], 0.04),
			Material = Enum.Material.SmoothPlastic,
			CanCollide = i == 0,
		}, model)
		-- Pente : un coin sur chaque côté pour adoucir le profil
		for k = 0, 3 do
			Build.Wedge(deco({
				Name = "NeedleSlope",
				Size = Vector3.new(w, h * 0.7, w * 0.22),
				CFrame = base * CFrame.Angles(0, (i % 2) * math.rad(45) + k * math.pi / 2, 0) * CFrame.new(0, y + h + h * 0.35, -w * 0.39),
				Color = vary(colors[i % #colors + 1], 0.04),
				Material = Enum.Material.SmoothPlastic,
			}), model)
		end
	end
	Build.Part(deco({ Name = "Tip", Size = Vector3.new(2, 3, 2) * s, CFrame = base * CFrame.new(0, (5 + tiers * 3.4 + 1.6) * s, 0) * CFrame.Angles(0, math.rad(45), 0), Color = colors[1], Material = Enum.Material.SmoothPlastic }), model)
	model.Parent = parent
	return model
end

-- Arbre au hasard parmi les styles demandés
function Props.Tree(parent: Instance, ground: Vector3, scale: number?, kinds: { string }?)
	local list = kinds or { "Block", "Round", "Pine" }
	local kind = list[random:NextInteger(1, #list)]
	if kind == "Round" then
		return Props.RoundTree(parent, ground, scale)
	elseif kind == "Pine" then
		return Props.PineTree(parent, ground, scale)
	elseif kind == "Green" then
		return Props.BlockTree(parent, ground, scale, Props.Colors.Leaf)
	end
	return Props.BlockTree(parent, ground, scale)
end

-- Buisson : grappe de boules (décoratif, traversable)
function Props.Bush(parent: Instance, ground: Vector3, size: number, color: Color3?, withFlowers: boolean?)
	local model = Instance.new("Model")
	model.Name = "Bush"
	local base = color or Props.Colors.Leaf[2]
	local specs = { { 0, 0.42, 0, 1 }, { 0.36, 0.3, 0.14, 0.72 }, { -0.34, 0.3, -0.12, 0.74 }, { 0.06, 0.32, 0.36, 0.66 }, { -0.1, 0.3, -0.38, 0.62 } }
	for i, b in specs do
		local d = size * b[4]
		Build.Part(deco({
			Name = "Leaves",
			Shape = Enum.PartType.Ball,
			Size = Vector3.new(d, d * 0.9, d),
			CFrame = CFrame.new(ground + Vector3.new(b[1] * size, b[2] * size, b[3] * size)),
			Color = vary(base, 0.07) :: Color3,
			Material = Enum.Material.SmoothPlastic,
		}), model)
		if withFlowers and i > 1 then
			local c = Props.Colors.Flower[random:NextInteger(1, #Props.Colors.Flower)]
			Build.Part(deco({ Name = "Blossom", Shape = Enum.PartType.Ball, Size = Vector3.new(0.9, 0.9, 0.9), CFrame = CFrame.new(ground + Vector3.new(b[1] * size * 1.5, b[2] * size + d * 0.42, b[3] * size * 1.5)), Color = c, Accent = true }), model)
		end
	end
	model.Parent = parent
	return model
end

-- Haie taillée le long d'un segment
function Props.Hedge(parent: Instance, from: Vector3, to: Vector3, height: number?, color: Color3?)
	local h = height or 4
	local delta = to - from
	local mid = (from + to) / 2
	local cf = CFrame.lookAt(mid, mid + delta)
	local c = color or Props.Colors.Leaf[2]
	Build.Part({ Name = "Hedge", Size = Vector3.new(3, h, delta.Magnitude), CFrame = cf * CFrame.new(0, h / 2, 0), Color = c, Material = Enum.Material.SmoothPlastic }, parent)
	Build.Part(deco({ Name = "HedgeTop", Size = Vector3.new(3.4, 0.8, delta.Magnitude + 0.4), CFrame = cf * CFrame.new(0, h - 0.2, 0), Color = c:Lerp(Color3.new(1, 1, 1), 0.08), Material = Enum.Material.SmoothPlastic }), parent)
end

-- Massif de fleurs (tiges + corolles)
function Props.Flowers(parent: Instance, center: Vector3, count: number?, radius: number?)
	local r = radius or 4
	for _ = 1, count or 8 do
		local a = random:NextNumber(0, math.pi * 2)
		local d = math.sqrt(random:NextNumber()) * r
		local p = center + Vector3.new(math.cos(a) * d, 0, math.sin(a) * d)
		local h = random:NextNumber(0.9, 1.6)
		Build.Part(deco({ Name = "Stem", Size = Vector3.new(0.2, h, 0.2), Position = p + Vector3.new(0, h / 2, 0), Color = rgb(70, 150, 56), CastShadow = false }), parent)
		Build.Part(deco({ Name = "Flower", Shape = Enum.PartType.Ball, Size = Vector3.new(0.9, 0.7, 0.9), Position = p + Vector3.new(0, h + 0.2, 0), Color = Props.Colors.Flower[random:NextInteger(1, #Props.Colors.Flower)], CastShadow = false, Accent = true }), parent)
	end
end

-- Jardinière en bois remplie de fleurs
function Props.FlowerBed(parent: Instance, cf: CFrame, length: number, width: number?)
	local w = width or 3
	Build.Part({ Name = "Planter", Size = Vector3.new(length, 1.4, w), CFrame = cf * CFrame.new(0, 0.7, 0), Color = Props.Colors.Wood, Material = Enum.Material.WoodPlanks }, parent)
	Build.Part(deco({ Name = "Soil", Size = Vector3.new(length - 0.6, 0.2, w - 0.6), CFrame = cf * CFrame.new(0, 1.42, 0), Color = rgb(96, 70, 48), Material = Enum.Material.Ground }), parent)
	local n = math.floor(length / 1.2)
	for i = 1, n do
		local x = -length / 2 + (i - 0.5) * (length / n)
		local p = (cf * CFrame.new(x + random:NextNumber(-0.2, 0.2), 1.5, random:NextNumber(-w * 0.25, w * 0.25))).Position
		Build.Part(deco({ Name = "Leaf", Shape = Enum.PartType.Ball, Size = Vector3.new(1.2, 0.8, 1.2), Position = p + Vector3.new(0, 0.3, 0), Color = Props.Colors.Leaf[2] }), parent)
		Build.Part(deco({ Name = "Flower", Shape = Enum.PartType.Ball, Size = Vector3.new(0.8, 0.8, 0.8), Position = p + Vector3.new(0, 0.9, 0), Color = Props.Colors.Flower[random:NextInteger(1, #Props.Colors.Flower)], Accent = true, CastShadow = false }), parent)
	end
end

-- Touffe d'herbe haute (décor)
function Props.GrassTuft(parent: Instance, ground: Vector3, color: Color3?)
	local c = color or rgb(110, 190, 70)
	for i = 0, 3 do
		local a = i * 1.7 + random:NextNumber(0, 0.5)
		local h = random:NextNumber(1.4, 2.4)
		Build.Wedge(deco({
			Name = "Blade",
			Size = Vector3.new(0.4, h, 0.6),
			CFrame = CFrame.new(ground + Vector3.new(math.cos(a) * 0.4, h / 2, math.sin(a) * 0.4)) * CFrame.Angles(0, a, random:NextNumber(-0.25, 0.25)),
			Color = vary(c, 0.08),
			CastShadow = false,
		}), parent)
	end
end

-- ---------------------------------------------------------------------------
-- Roches
-- ---------------------------------------------------------------------------

-- Rocher "taillé" : 2 à 4 blocs tournés et imbriqués (silhouette low-poly)
function Props.Rock(parent: Instance, ground: Vector3, size: number, color: Color3?, collide: boolean?)
	local model = Instance.new("Model")
	model.Name = "Rock"
	local c = color or Props.Colors.Rock
	local n = random:NextInteger(2, 4)
	for i = 1, n do
		local k = i == 1 and 1 or random:NextNumber(0.45, 0.7)
		local sz = Vector3.new(size * k * random:NextNumber(0.9, 1.3), size * k * random:NextNumber(0.6, 0.9), size * k * random:NextNumber(0.8, 1.1))
		local offset = i == 1 and Vector3.zero or Vector3.new(random:NextNumber(-0.5, 0.5) * size, 0, random:NextNumber(-0.5, 0.5) * size)
		Build.Part({
			Name = "Stone",
			Size = sz,
			CFrame = CFrame.new(ground + offset + Vector3.new(0, sz.Y * 0.38, 0)) * CFrame.Angles(random:NextNumber(-0.3, 0.3), random:NextNumber(0, math.pi), random:NextNumber(-0.3, 0.3)),
			Color = vary(c, 0.06),
			Material = Enum.Material.Slate,
			CanCollide = collide ~= false and i == 1,
		}, model)
	end
	model.Parent = parent
	return model
end

-- ---------------------------------------------------------------------------
-- Bâtiments
-- ---------------------------------------------------------------------------

-- Toit à deux pans (faîtage selon l'axe X du CFrame). cf = centre du haut des murs.
-- Pignons pleins (coins) + deux pans de toit qui débordent.
export type RoofOptions = {
	Width: number, -- le long du faîtage (X)
	Depth: number, -- perpendiculaire au faîtage (Z)
	Rise: number, -- hauteur du faîtage
	Color: Color3,
	Gable: Color3?,
	Overhang: number?,
	Thickness: number?,
	Material: Enum.Material?,
}
function Props.Roof(parent: Instance, cf: CFrame, o: RoofOptions)
	local overhang = o.Overhang or 1.5
	local thickness = o.Thickness or 0.8
	local halfD = o.Depth / 2
	-- Pignons : deux coins dos à dos, face verticale au faîtage
	for _, side in { -1, 1 } do
		local rot = side < 0 and CFrame.new() or CFrame.Angles(0, math.pi, 0)
		Build.Wedge({
			Name = "Gable",
			Size = Vector3.new(o.Width - 0.2, o.Rise, halfD),
			CFrame = cf * rot * CFrame.new(0, o.Rise / 2, -halfD / 2),
			Color = o.Gable or o.Color,
			Material = Enum.Material.SmoothPlastic,
		}, parent)
	end
	-- Pans
	local slope = math.atan2(o.Rise, halfD)
	local length = math.sqrt(o.Rise * o.Rise + halfD * halfD) + overhang
	for _, side in { -1, 1 } do
		local panel = cf
			* CFrame.new(0, o.Rise / 2, side * halfD / 2)
			* CFrame.Angles(side * slope, 0, 0)
			* CFrame.new(0, thickness / 2 + 0.05, side * overhang / 2)
		Build.Part({
			Name = "RoofPanel",
			Size = Vector3.new(o.Width + overhang * 2, thickness, length),
			CFrame = panel,
			Color = o.Color,
			Material = o.Material or Enum.Material.SmoothPlastic,
		}, parent)
		-- Bandeau clair au bas du pan
		Build.Part(deco({
			Name = "RoofTrim",
			Size = Vector3.new(o.Width + overhang * 2 + 0.2, thickness + 0.3, 0.6),
			CFrame = panel * CFrame.new(0, 0, side * (length / 2 - 0.3)),
			Color = o.Color:Lerp(Color3.new(0, 0, 0), 0.18),
		}), parent)
	end
	-- Faîtage
	Build.Part(deco({
		Name = "RoofRidge",
		Size = Vector3.new(o.Width + overhang * 2 + 0.4, thickness * 1.4, thickness * 1.6),
		CFrame = cf * CFrame.new(0, o.Rise + thickness * 0.7, 0),
		Color = o.Color:Lerp(Color3.new(0, 0, 0), 0.2),
	}), parent)
end

-- Fenêtre avec encadrement, vitre et croisillons, sur un mur (cf = centre de
-- la fenêtre, -Z local = vers l'extérieur).
function Props.Window(parent: Instance, cf: CFrame, width: number, height: number, frame: Color3?, shutters: Color3?)
	local f = frame or Props.Colors.White
	Build.Part(deco({ Name = "WindowGlass", Size = Vector3.new(width, height, 0.2), CFrame = cf, Color = rgb(150, 205, 240), Material = Enum.Material.Glass, Transparency = 0.15, Reflectance = 0.15 }), parent)
	local t = 0.45
	Build.Part(deco({ Name = "WindowFrame", Size = Vector3.new(width + t * 2, t, 0.5), CFrame = cf * CFrame.new(0, height / 2 + t / 2, -0.1), Color = f }), parent)
	Build.Part(deco({ Name = "WindowSill", Size = Vector3.new(width + t * 3, t, 0.9), CFrame = cf * CFrame.new(0, -height / 2 - t / 2, -0.3), Color = f }), parent)
	for _, sx in { -1, 1 } do
		Build.Part(deco({ Name = "WindowFrame", Size = Vector3.new(t, height, 0.5), CFrame = cf * CFrame.new(sx * (width / 2 + t / 2), 0, -0.1), Color = f }), parent)
	end
	Build.Part(deco({ Name = "WindowBar", Size = Vector3.new(0.22, height, 0.3), CFrame = cf * CFrame.new(0, 0, -0.1), Color = f }), parent)
	Build.Part(deco({ Name = "WindowBar", Size = Vector3.new(width, 0.22, 0.3), CFrame = cf * CFrame.new(0, 0, -0.1), Color = f }), parent)
	if shutters then
		for _, sx in { -1, 1 } do
			Build.Part(deco({ Name = "Shutter", Size = Vector3.new(width * 0.5, height + 0.4, 0.25), CFrame = cf * CFrame.new(sx * (width * 0.75 + t + 0.1), 0, -0.05), Color = shutters }), parent)
		end
	end
end

-- Porte avec encadrement et poignée (cf = bas-centre de la porte, -Z = dehors)
function Props.Door(parent: Instance, cf: CFrame, width: number, height: number, color: Color3, frame: Color3?)
	local f = frame or Props.Colors.White
	Build.Part(deco({ Name = "Door", Size = Vector3.new(width, height, 0.3), CFrame = cf * CFrame.new(0, height / 2, 0), Color = color, Material = Enum.Material.WoodPlanks }), parent)
	Build.Part(deco({ Name = "DoorFrame", Size = Vector3.new(width + 1, 0.6, 0.6), CFrame = cf * CFrame.new(0, height + 0.3, -0.1), Color = f }), parent)
	for _, sx in { -1, 1 } do
		Build.Part(deco({ Name = "DoorFrame", Size = Vector3.new(0.5, height, 0.6), CFrame = cf * CFrame.new(sx * (width / 2 + 0.25), height / 2, -0.1), Color = f }), parent)
	end
	Build.Part(deco({ Name = "Knob", Shape = Enum.PartType.Ball, Size = Vector3.new(0.5, 0.5, 0.5), CFrame = cf * CFrame.new(width * 0.32, height * 0.48, -0.3), Color = rgb(250, 205, 70), Material = Enum.Material.Metal }), parent)
end

-- Maison : soubassement, murs, fenêtres à volets, porte, toit à deux pans,
-- cheminée, marche et jardinières. cf = centre au sol, -Z = façade.
export type HouseOptions = {
	Width: number?,
	Depth: number?,
	Height: number?,
	Wall: Color3?,
	Roof: Color3?,
	Trim: Color3?,
	Door: Color3?,
	Shutters: Color3?,
	Chimney: boolean?,
	Floors: number?,
	Material: Enum.Material?,
}
function Props.House(parent: Instance, cf: CFrame, o: HouseOptions?): Model
	local opt: HouseOptions = o or {}
	local w = opt.Width or 20
	local d = opt.Depth or 16
	local floors = opt.Floors or 1
	local h = opt.Height or (floors * 9)
	local wall = opt.Wall or rgb(110, 210, 184)
	local roof = opt.Roof or rgb(44, 126, 76)
	local trim = opt.Trim or Props.Colors.White
	local model = Instance.new("Model")
	model.Name = "House"
	-- Soubassement en pierre
	Build.Part({ Name = "Foundation", Size = Vector3.new(w + 1, 1.2, d + 1), CFrame = cf * CFrame.new(0, 0.6, 0), Color = rgb(150, 150, 160), Material = Enum.Material.Cobblestone }, model)
	-- Murs
	Build.Part({ Name = "Walls", Size = Vector3.new(w, h, d), CFrame = cf * CFrame.new(0, 1.2 + h / 2, 0), Color = wall, Material = opt.Material or Enum.Material.SmoothPlastic }, model)
	-- Chaînages d'angle
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			Build.Part(deco({ Name = "Corner", Size = Vector3.new(1, h, 1), CFrame = cf * CFrame.new(sx * w / 2, 1.2 + h / 2, sz * d / 2), Color = trim }), model)
		end
	end
	-- Corniche
	Build.Part(deco({ Name = "Cornice", Size = Vector3.new(w + 1.2, 0.8, d + 1.2), CFrame = cf * CFrame.new(0, 1.2 + h - 0.1, 0), Color = trim }), model)
	-- Façade : porte + fenêtres
	local doorW, doorH = 4, 7
	local front = cf * CFrame.new(0, 1.2, -d / 2 - 0.15)
	Props.Door(model, front * CFrame.new(0, 0, 0), doorW, doorH, opt.Door or rgb(150, 92, 60), trim)
	-- Petit auvent au-dessus de la porte
	Build.Wedge(deco({ Name = "Awning", Size = Vector3.new(doorW + 3, 1.4, 2.4), CFrame = front * CFrame.new(0, doorH + 1.6, -1.2) * CFrame.Angles(0, 0, 0), Color = roof }), model)
	-- Marche
	Build.Part({ Name = "Step", Size = Vector3.new(doorW + 2, 0.8, 2.2), CFrame = cf * CFrame.new(0, 0.4, -d / 2 - 1.4), Color = rgb(170, 170, 178), Material = Enum.Material.Concrete }, model)
	local winW, winH = 3.6, 3.6
	for floor = 1, floors do
		local y = 1.2 + (floor - 1) * 9 + 4.8
		for _, sx in { -1, 1 } do
			local x = sx * w * 0.3
			if floor > 1 or math.abs(x) > doorW then
				Props.Window(model, cf * CFrame.new(x, y, -d / 2 - 0.15), winW, winH, trim, opt.Shutters)
				if floor == 1 then
					Props.FlowerBed(model, cf * CFrame.new(x, 0.9, -d / 2 - 1.1), winW + 1.4, 1.4)
				end
			end
			-- Arrière
			Props.Window(model, cf * CFrame.Angles(0, math.pi, 0) * CFrame.new(x, y, -d / 2 - 0.15), winW, winH, trim, opt.Shutters)
		end
		if floor > 1 then
			Props.Window(model, cf * CFrame.new(0, y, -d / 2 - 0.15), winW, winH, trim, opt.Shutters)
		end
		-- Pignons latéraux : une fenêtre de chaque côté
		for _, side in { -1, 1 } do
			Props.Window(model, cf * CFrame.Angles(0, side * math.pi / 2, 0) * CFrame.new(0, y, -w / 2 - 0.15), winW * 0.8, winH * 0.8, trim, nil)
		end
	end
	-- Toit
	Props.Roof(model, cf * CFrame.new(0, 1.2 + h, 0), { Width = w, Depth = d, Rise = d * 0.42, Color = roof, Gable = wall, Overhang = 1.6 })
	if opt.Chimney ~= false then
		Build.Part({ Name = "Chimney", Size = Vector3.new(2.4, 7, 2.4), CFrame = cf * CFrame.new(w * 0.3, 1.2 + h + d * 0.3, d * 0.18), Color = rgb(176, 96, 76), Material = Enum.Material.Brick }, model)
		Build.Part(deco({ Name = "ChimneyCap", Size = Vector3.new(3, 0.6, 3), CFrame = cf * CFrame.new(w * 0.3, 1.2 + h + d * 0.3 + 3.7, d * 0.18), Color = rgb(90, 90, 98) }), model)
	end
	model.Parent = parent
	return model
end

-- Grange : murs en planches, toit à deux pans, grande porte croisée, lucarne
function Props.Barn(parent: Instance, cf: CFrame, width: number?, depth: number?, color: Color3?): Model
	local w = width or 28
	local d = depth or 22
	local h = 14
	local red = color or rgb(196, 58, 48)
	local white = Props.Colors.White
	local model = Instance.new("Model")
	model.Name = "Barn"
	Build.Part({ Name = "Foundation", Size = Vector3.new(w + 1, 1, d + 1), CFrame = cf * CFrame.new(0, 0.5, 0), Color = rgb(150, 150, 160), Material = Enum.Material.Cobblestone }, model)
	Build.Part({ Name = "BarnWalls", Size = Vector3.new(w, h, d), CFrame = cf * CFrame.new(0, 1 + h / 2, 0), Color = red, Material = Enum.Material.WoodPlanks }, model)
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			Build.Part(deco({ Name = "Corner", Size = Vector3.new(1.2, h, 1.2), CFrame = cf * CFrame.new(sx * w / 2, 1 + h / 2, sz * d / 2), Color = white }), model)
		end
	end
	-- Pignon de façade (le faîtage suit Z ici : on tourne le toit)
	local roofCf = cf * CFrame.new(0, 1 + h, 0) * CFrame.Angles(0, math.pi / 2, 0)
	Props.Roof(model, roofCf, { Width = d, Depth = w, Rise = w * 0.38, Color = rgb(96, 64, 52), Gable = red, Overhang = 1.8 })
	-- Grande porte à croisillon blanc
	local doorCf = cf * CFrame.new(0, 1, -d / 2 - 0.2)
	Build.Part(deco({ Name = "BarnDoor", Size = Vector3.new(11, 11, 0.4), CFrame = doorCf * CFrame.new(0, 5.5, 0), Color = red:Lerp(Color3.new(0, 0, 0), 0.12), Material = Enum.Material.WoodPlanks }), model)
	Build.Part(deco({ Name = "DoorTrim", Size = Vector3.new(12, 0.8, 0.6), CFrame = doorCf * CFrame.new(0, 11.2, -0.1), Color = white }), model)
	for _, sx in { -1, 1 } do
		Build.Part(deco({ Name = "DoorTrim", Size = Vector3.new(0.8, 11, 0.6), CFrame = doorCf * CFrame.new(sx * 5.8, 5.5, -0.1), Color = white }), model)
		Build.Part(deco({ Name = "DoorCross", Size = Vector3.new(0.7, 14.5, 0.5), CFrame = doorCf * CFrame.new(0, 5.5, -0.3) * CFrame.Angles(0, 0, math.rad(sx * 45)), Color = white }), model)
	end
	Build.Part(deco({ Name = "DoorTrim", Size = Vector3.new(11, 0.7, 0.6), CFrame = doorCf * CFrame.new(0, 5.5, -0.15), Color = white }), model)
	-- Lucarne du grenier
	Props.Window(model, cf * CFrame.new(0, 1 + h + w * 0.14, -d / 2 - 0.15), 4, 4, white, nil)
	-- Fenêtres latérales
	for _, side in { -1, 1 } do
		for _, z in { -d * 0.25, d * 0.25 } do
			Props.Window(model, cf * CFrame.Angles(0, side * math.pi / 2, 0) * CFrame.new(z, 1 + h * 0.55, -w / 2 - 0.15), 3.6, 3.6, white, nil)
		end
	end
	model.Parent = parent
	return model
end

-- Tente / auvent de marché à rayures (cf = centre au sol)
function Props.Stall(parent: Instance, cf: CFrame, width: number, depth: number, colorA: Color3, colorB: Color3?)
	local model = Instance.new("Model")
	model.Name = "Stall"
	local b = colorB or Props.Colors.White
	local postH = 7
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			Build.Part({ Name = "Post", Size = Vector3.new(0.6, postH, 0.6), CFrame = cf * CFrame.new(sx * (width / 2 - 0.4), postH / 2, sz * (depth / 2 - 0.4)), Color = Props.Colors.WoodDark, Material = Enum.Material.Wood }, model)
		end
	end
	Build.Part({ Name = "Counter", Size = Vector3.new(width - 1, 3, 2), CFrame = cf * CFrame.new(0, 1.5, -depth / 2 + 1.4), Color = Props.Colors.Wood, Material = Enum.Material.WoodPlanks }, model)
	local stripes = math.max(3, math.floor(width / 2))
	local sw = width / stripes
	for i = 0, stripes - 1 do
		Build.Wedge(deco({
			Name = "Canopy",
			Size = Vector3.new(sw, 2.2, depth + 1),
			CFrame = cf * CFrame.new(-width / 2 + sw * (i + 0.5), postH + 1.1, 0) * CFrame.Angles(0, 0, 0),
			Color = i % 2 == 0 and colorA or b,
		}), model)
		-- Lambrequin festonné
		Build.Part(deco({ Name = "Valance", Size = Vector3.new(sw, 1, 0.2), CFrame = cf * CFrame.new(-width / 2 + sw * (i + 0.5), postH - 0.4, -depth / 2 - 0.5), Color = i % 2 == 0 and colorA or b }), model)
	end
	model.Parent = parent
	return model
end

-- ---------------------------------------------------------------------------
-- Clôtures, murs, mobilier
-- ---------------------------------------------------------------------------

-- Clôture en bois (poteaux + deux lisses)
function Props.Fence(parent: Instance, from: Vector3, to: Vector3, color: Color3?)
	local wood = color or Props.Colors.Wood
	local delta = to - from
	local length = delta.Magnitude
	if length < 0.5 then
		return
	end
	local mid = (from + to) / 2
	local cf = CFrame.lookAt(mid, mid + delta)
	for _, h in { 1.3, 2.7 } do
		Build.Part({ Name = "FenceRail", Size = Vector3.new(0.35, 0.55, length), CFrame = cf + Vector3.new(0, h, 0), Color = wood, Material = Enum.Material.Wood }, parent)
	end
	local posts = math.max(2, math.floor(length / 7) + 1)
	for i = 0, posts - 1 do
		local p = from + delta * (i / (posts - 1))
		Build.Part({ Name = "FencePost", Size = Vector3.new(0.8, 3.6, 0.8), CFrame = CFrame.lookAt(p + Vector3.new(0, 1.8, 0), p + Vector3.new(0, 1.8, 0) + delta), Color = wood:Lerp(Color3.new(0, 0, 0), 0.15), Material = Enum.Material.Wood }, parent)
		Build.Part(deco({ Name = "PostCap", Size = Vector3.new(1, 0.4, 1), CFrame = CFrame.lookAt(p + Vector3.new(0, 3.75, 0), p + Vector3.new(0, 3.75, 0) + delta), Color = wood:Lerp(Color3.new(1, 1, 1), 0.1) }), parent)
	end
end

-- Palissade blanche (piquets pointus)
function Props.PicketFence(parent: Instance, from: Vector3, to: Vector3, color: Color3?)
	local c = color or Props.Colors.White
	local delta = to - from
	local length = delta.Magnitude
	if length < 0.5 then
		return
	end
	local mid = (from + to) / 2
	local cf = CFrame.lookAt(mid, mid + delta)
	Build.Part({ Name = "FenceRail", Size = Vector3.new(0.3, 0.4, length), CFrame = cf + Vector3.new(0, 1.9, 0), Color = c }, parent)
	Build.Part(deco({ Name = "FenceRail", Size = Vector3.new(0.3, 0.4, length), CFrame = cf + Vector3.new(0, 0.8, 0), Color = c }), parent)
	local n = math.floor(length / 1.4)
	for i = 0, n do
		local p = from + delta * (i / math.max(1, n))
		local pcf = CFrame.lookAt(p, p + delta)
		Build.Part(deco({ Name = "Picket", Size = Vector3.new(0.25, 2.6, 0.8), CFrame = pcf * CFrame.new(0.2, 1.3, 0), Color = c }), parent)
		Build.Part(deco({ Name = "PicketTip", Size = Vector3.new(0.25, 0.56, 0.56), CFrame = pcf * CFrame.new(0.2, 2.6, 0) * CFrame.Angles(math.rad(45), 0, 0), Color = c }), parent)
	end
end

-- Muret de pierres (gros moellons)
function Props.StoneWall(parent: Instance, from: Vector3, to: Vector3, height: number?, color: Color3?)
	local h = height or 3
	local c = color or rgb(160, 162, 170)
	local delta = to - from
	local length = delta.Magnitude
	local dir = delta.Unit
	local n = math.max(1, math.floor(length / 3))
	local step = length / n
	for row = 0, math.floor(h / 1.5) - 1 do
		local shift = (row % 2) * step / 2
		for i = 0, n - 1 do
			local along = math.min(length - step / 2, i * step + step / 2 + shift)
			local p = from + dir * along + Vector3.new(0, row * 1.5 + 0.75, 0)
			Build.Part({
				Name = "Stone",
				Size = Vector3.new(2.2, 1.5, step + 0.1),
				CFrame = CFrame.lookAt(p, p + dir) * CFrame.Angles(0, random:NextNumber(-0.04, 0.04), 0),
				Color = vary(c, 0.06),
				Material = Enum.Material.Slate,
			}, parent)
		end
	end
	local mid = (from + to) / 2
	Build.Part(deco({ Name = "WallCap", Size = Vector3.new(2.6, 0.5, length + 0.4), CFrame = CFrame.lookAt(mid + Vector3.new(0, math.floor(h / 1.5) * 1.5 + 0.25, 0), mid + Vector3.new(0, math.floor(h / 1.5) * 1.5 + 0.25, 0) + dir), Color = vary(c, 0.03):Lerp(Color3.new(1, 1, 1), 0.12) :: Color3, Material = Enum.Material.Slate }), parent)
end

-- Lampadaire classique (lanterne chaude)
function Props.Lamp(parent: Instance, ground: Vector3, yaw: number?)
	local cf = CFrame.new(ground) * CFrame.Angles(0, yaw or 0, 0)
	local metal = rgb(48, 54, 66)
	Build.Part({ Name = "LampBase", Size = Vector3.new(1.6, 1, 1.6), CFrame = cf * CFrame.new(0, 0.5, 0), Color = metal, Material = Enum.Material.Metal }, parent)
	Build.Part({ Name = "LampPost", Size = Vector3.new(0.7, 11, 0.7), CFrame = cf * CFrame.new(0, 6, 0), Color = metal, Material = Enum.Material.Metal }, parent)
	Build.Part(deco({ Name = "LampArm", Size = Vector3.new(0.4, 0.4, 2.6), CFrame = cf * CFrame.new(0, 11.2, -1.1), Color = metal, Material = Enum.Material.Metal }), parent)
	Build.Part(deco({ Name = "LampHood", Size = Vector3.new(1.9, 0.5, 1.9), CFrame = cf * CFrame.new(0, 10.9, -2.3), Color = metal, Material = Enum.Material.Metal }), parent)
	local lantern = Build.Part(deco({ Name = "Lantern", Size = Vector3.new(1.3, 1.6, 1.3), CFrame = cf * CFrame.new(0, 9.85, -2.3), Color = rgb(255, 214, 130), Material = Enum.Material.Neon }), parent)
	local light = Instance.new("PointLight")
	light.Color = rgb(255, 205, 130)
	light.Range = 16
	light.Brightness = 1
	light.Shadows = false
	light.Parent = lantern
end

-- Banc de parc (cf = centre au sol, -Z = devant)
function Props.Bench(parent: Instance, cf: CFrame)
	local wood = Props.Colors.Wood
	local metal = rgb(48, 54, 66)
	for _, sx in { -2.2, 2.2 } do
		Build.Part({ Name = "BenchLeg", Size = Vector3.new(0.4, 1.8, 1.8), CFrame = cf * CFrame.new(sx, 0.9, 0), Color = metal, Material = Enum.Material.Metal }, parent)
	end
	for i = 0, 2 do
		Build.Part({ Name = "BenchSlat", Size = Vector3.new(5.6, 0.25, 0.55), CFrame = cf * CFrame.new(0, 1.9, -0.65 + i * 0.65), Color = wood, Material = Enum.Material.WoodPlanks }, parent)
	end
	for i = 0, 1 do
		Build.Part(deco({ Name = "BenchBack", Size = Vector3.new(5.6, 0.5, 0.2), CFrame = cf * CFrame.new(0, 2.6 + i * 0.75, 0.95) * CFrame.Angles(math.rad(-12), 0, 0), Color = wood, Material = Enum.Material.WoodPlanks }), parent)
	end
end

-- Caisse en bois avec renforts
function Props.Crate(parent: Instance, cf: CFrame, size: number?)
	local s = size or 3
	local wood = rgb(186, 136, 82)
	local edge = rgb(130, 90, 56)
	Build.Part({ Name = "Crate", Size = Vector3.new(s, s, s), CFrame = cf * CFrame.new(0, s / 2, 0), Color = wood, Material = Enum.Material.WoodPlanks }, parent)
	for _, sy in { -1, 1 } do
		for _, sz in { -1, 1 } do
			Build.Part(deco({ Name = "CrateEdge", Size = Vector3.new(s + 0.1, s * 0.12, s * 0.12), CFrame = cf * CFrame.new(0, s / 2 + sy * s * 0.47, sz * s * 0.47), Color = edge, Material = Enum.Material.Wood }), parent)
			Build.Part(deco({ Name = "CrateEdge", Size = Vector3.new(s * 0.12, s + 0.1, s * 0.12), CFrame = cf * CFrame.new(sy * s * 0.47, s / 2, sz * s * 0.47), Color = edge, Material = Enum.Material.Wood }), parent)
		end
	end
	for _, sz in { -1, 1 } do
		Build.Part(deco({ Name = "CrateBrace", Size = Vector3.new(s * 1.25, s * 0.12, 0.1), CFrame = cf * CFrame.new(0, s / 2, sz * (s / 2 + 0.02)) * CFrame.Angles(0, 0, math.rad(45)), Color = edge, Material = Enum.Material.Wood }), parent)
	end
end

-- Pile de caisses (obstacle pour feinter)
function Props.CrateStack(parent: Instance, ground: Vector3, yaw: number?)
	local cf = CFrame.new(ground) * CFrame.Angles(0, yaw or 0, 0)
	Props.Crate(parent, cf * CFrame.new(-1.6, 0, 0) * CFrame.Angles(0, 0.08, 0), 3.2)
	Props.Crate(parent, cf * CFrame.new(1.7, 0, 0.3) * CFrame.Angles(0, -0.12, 0), 3.2)
	Props.Crate(parent, cf * CFrame.new(0.1, 3.2, 0.1) * CFrame.Angles(0, 0.3, 0), 2.8)
end

-- Tonneau cerclé
function Props.Barrel(parent: Instance, ground: Vector3, color: Color3?)
	local c = color or rgb(150, 98, 58)
	Build.VerticalCylinder(ground + Vector3.new(0, 2, 0), 1.5, 4, { Name = "Barrel", Color = c, Material = Enum.Material.WoodPlanks }, parent)
	for _, y in { 0.7, 3.3 } do
		Build.VerticalCylinder(ground + Vector3.new(0, y, 0), 1.6, 0.35, deco({ Name = "Hoop", Color = rgb(70, 72, 80), Material = Enum.Material.Metal }), parent)
	end
end

-- Botte de foin ronde ou carrée
function Props.HayBale(parent: Instance, ground: Vector3, yaw: number?, round: boolean?)
	local hay = rgb(244, 204, 74)
	if round then
		Build.Part({ Name = "HayRoll", Shape = Enum.PartType.Cylinder, Size = Vector3.new(4, 4.6, 4.6), CFrame = CFrame.new(ground + Vector3.new(0, 2.3, 0)) * CFrame.Angles(0, yaw or 0, 0), Color = hay, Material = Enum.Material.Fabric }, parent)
		return
	end
	local cf = CFrame.new(ground) * CFrame.Angles(0, yaw or 0, 0)
	Build.Part({ Name = "HayBale", Size = Vector3.new(5, 3, 3.2), CFrame = cf * CFrame.new(0, 1.5, 0), Color = hay, Material = Enum.Material.Fabric }, parent)
	for _, x in { -1.4, 1.4 } do
		Build.Part(deco({ Name = "Twine", Size = Vector3.new(0.25, 3.1, 3.3), CFrame = cf * CFrame.new(x, 1.5, 0), Color = rgb(196, 150, 60) }), parent)
	end
end

-- Guirlande de fanions entre deux points (chaînette affaissée)
function Props.Bunting(parent: Instance, from: Vector3, to: Vector3, colors: { Color3 }, sag: number?)
	local delta = to - from
	local length = delta.Magnitude
	local n = math.max(2, math.floor(length / 2.2))
	local dip = sag or math.min(4, length * 0.08)
	local prev = from
	for i = 1, n do
		local t = i / n
		local p = from + delta * t - Vector3.new(0, math.sin(t * math.pi) * dip, 0)
		local mid = (prev + p) / 2
		Build.Part(deco({ Name = "String", Size = Vector3.new(0.08, 0.08, (p - prev).Magnitude), CFrame = CFrame.lookAt(mid, p), Color = rgb(240, 240, 240), CastShadow = false }), parent)
		local flagPos = mid - Vector3.new(0, 0.75, 0)
		Build.Wedge(deco({
			Name = "Pennant",
			Size = Vector3.new(0.1, 1.5, 1.3),
			CFrame = CFrame.lookAt(flagPos, flagPos + delta) * CFrame.Angles(math.pi, 0, 0),
			Color = colors[(i - 1) % #colors + 1],
			Accent = true,
			CastShadow = false,
		}), parent)
		prev = p
	end
end

-- Puits en pierre avec toit
function Props.Well(parent: Instance, ground: Vector3)
	Build.VerticalCylinder(ground + Vector3.new(0, 1.6, 0), 3.2, 3.2, { Name = "WellWall", Color = rgb(160, 160, 168), Material = Enum.Material.Cobblestone }, parent)
	Build.VerticalCylinder(ground + Vector3.new(0, 3.15, 0), 2.5, 0.2, deco({ Name = "WellWater", Color = rgb(40, 120, 170), Material = Enum.Material.Glass, Transparency = 0.2 }), parent)
	for _, x in { -2.8, 2.8 } do
		Build.Part({ Name = "WellPost", Size = Vector3.new(0.6, 6, 0.6), Position = ground + Vector3.new(x, 6, 0), Color = Props.Colors.WoodDark, Material = Enum.Material.Wood }, parent)
	end
	Props.Roof(parent, CFrame.new(ground + Vector3.new(0, 8.6, 0)), { Width = 6.6, Depth = 5, Rise = 2.2, Color = rgb(186, 66, 52), Gable = Props.Colors.Wood, Overhang = 0.8, Thickness = 0.5 })
	Build.Part(deco({ Name = "Crank", Shape = Enum.PartType.Cylinder, Size = Vector3.new(5.6, 0.7, 0.7), Position = ground + Vector3.new(0, 7, 0), Color = Props.Colors.Wood, Material = Enum.Material.Wood }), parent)
end

-- Charrette en bois (cf = centre au sol)
function Props.Cart(parent: Instance, cf: CFrame, cargo: Color3?)
	Build.Part({ Name = "CartBed", Size = Vector3.new(5, 0.6, 8), CFrame = cf * CFrame.new(0, 2.6, 0), Color = Props.Colors.Wood, Material = Enum.Material.WoodPlanks }, parent)
	for _, sx in { -1, 1 } do
		Build.Part({ Name = "CartSide", Size = Vector3.new(0.4, 1.6, 8), CFrame = cf * CFrame.new(sx * 2.3, 3.6, 0), Color = Props.Colors.WoodDark, Material = Enum.Material.WoodPlanks }, parent)
		Build.Part(deco({ Name = "Wheel", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.5, 4, 4), CFrame = cf * CFrame.new(sx * 2.8, 2, 0.8), Color = Props.Colors.WoodDark, Material = Enum.Material.Wood }), parent)
		Build.Part(deco({ Name = "Hub", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.7, 1, 1), CFrame = cf * CFrame.new(sx * 2.9, 2, 0.8), Color = rgb(70, 72, 80), Material = Enum.Material.Metal }), parent)
		Build.Part(deco({ Name = "Shaft", Size = Vector3.new(0.4, 0.4, 6), CFrame = cf * CFrame.new(sx * 1.6, 2.4, -6.6) * CFrame.Angles(math.rad(-12), 0, 0), Color = Props.Colors.Wood, Material = Enum.Material.Wood }), parent)
	end
	Build.Part({ Name = "CartBack", Size = Vector3.new(5, 1.6, 0.4), CFrame = cf * CFrame.new(0, 3.6, 3.8), Color = Props.Colors.WoodDark, Material = Enum.Material.WoodPlanks }, parent)
	if cargo then
		Build.Part(deco({ Name = "Cargo", Size = Vector3.new(4, 1.4, 6.6), CFrame = cf * CFrame.new(0, 3.6, 0), Color = cargo, Material = Enum.Material.Fabric }), parent)
	end
end

-- Panneau en bois sur poteau (texte en anglais, deux faces)
function Props.Sign(parent: Instance, cf: CFrame, text: string, color: Color3?)
	Build.Part({ Name = "SignPost", Size = Vector3.new(0.6, 6, 0.6), CFrame = cf * CFrame.new(0, 3, 0), Color = Props.Colors.WoodDark, Material = Enum.Material.Wood }, parent)
	local board = Build.Part(deco({ Name = "SignBoard", Size = Vector3.new(6, 2.4, 0.4), CFrame = cf * CFrame.new(0, 5, -0.4), Color = color or Props.Colors.Wood, Material = Enum.Material.WoodPlanks }), parent)
	for _, face in { Enum.NormalId.Front, Enum.NormalId.Back } do
		Build.SurfaceLabel(board, face, text, { TextColor3 = rgb(255, 250, 235), TextStrokeTransparency = 0.4, Font = Enum.Font.GothamBlack })
	end
	return board
end

-- Parasol / arbre de fête : poteau + disque coloré
function Props.Umbrella(parent: Instance, ground: Vector3, color: Color3)
	Build.Part({ Name = "UmbrellaPole", Size = Vector3.new(0.4, 7, 0.4), Position = ground + Vector3.new(0, 3.5, 0), Color = Props.Colors.White }, parent)
	for i = 0, 7 do
		local a = i / 8 * math.pi * 2
		Build.Wedge(deco({
			Name = "UmbrellaPanel",
			Size = Vector3.new(2.6, 1.2, 3.2),
			CFrame = CFrame.new(ground + Vector3.new(0, 7.2, 0)) * CFrame.Angles(0, a, 0) * CFrame.new(0, 0, -1.6),
			Color = i % 2 == 0 and color or Props.Colors.White,
			Accent = true,
		}), parent)
	end
end

return Props

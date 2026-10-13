--[[
	LobbyBuilder.lua
	Lobby carré et fermé, construit entièrement par le code, dans l'ambiance de
	la référence (reference/HUSS_VALLEY_NOTES.md, section A) : style Roblox
	classique lumineux, sol vert à tenons, place de pierre, arbres en cubes,
	blocs jaunes, murs de classement gris, roue de récompense, cadeau géant,
	portail violet, plateformes rondes de vote. Éléments et textes originaux.

	Disposition (vue du dessus, Nord = -Z) :
	              [ ÉCRAN GÉANT ]
	              (  PORTAIL  )                         Nord
	        (pad 1)    (pad 2)    (pad 3)   <- vote
	 [MURS DE                                 [CADEAU
	  CLASSEMENT]        ( SPAWN )             GÉANT = SHOP]   Ouest / Est
	 (ROUE DU JOUR)                          [blocs jaunes : dash]
	              [ PANNEAU DES RÈGLES ]                Sud
	 Murets de pierre tout autour, maisons et arbres derrière.
]]

local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Teams = require(Shared.Teams)
local Lang = require(Shared.Lang)
local MapInfo = require(Shared.MapInfo)
local ModeInfo = require(Shared.ModeInfo)
local Style = require(Shared.Style)
local Mechanics = require(Shared.Mechanics)
local Build = require(script.Parent.Parent.Util.Build)
local Props = require(script.Parent.Parent.Util.Props)
local TerrainKit = require(script.Parent.Parent.Util.TerrainKit)
local Ground = require(script.Parent.Parent.Util.Ground)

local LobbyBuilder = {}

local P = Style.Palette
local folder: Folder? = nil
local spawnCFrame = CFrame.new(Config.World.LobbyOrigin + Vector3.new(0, 3, 0))

type BoardLabels = { Status: TextLabel?, Time: TextLabel?, Map: TextLabel? }
local boardLabels: BoardLabels = {}
type VotePlate = { Part: Part, Name: TextLabel, Mode: TextLabel, Votes: TextLabel, Ring: Part, MapId: string? }
local votePlates: { VotePlate } = {}
local plateCallback: ((Player, number) -> ())? = nil
local shopCallback: ((Player) -> ())? = nil
local spinCallback: ((Player) -> ())? = nil
local lastTouch: { [Player]: number } = {}
type Leaderboard = { Rows: { { Frame: Frame, Name: TextLabel, Value: TextLabel } }, Message: TextLabel }
local leaderboards: { [string]: Leaderboard } = {}
local wheel: Model? = nil
local wheelSegments = 8

-- ---------------------------------------------------------------------------
-- Éléments génériques
-- ---------------------------------------------------------------------------
local function text(parent: Instance, props: { [string]: any }): TextLabel
	-- NoStroke est une option de ce helper, pas une propriété Roblox
	local clean = table.clone(props)
	clean.NoStroke = nil
	local label = Build.TextLabel(parent, clean)
	label.Font = Enum.Font.GothamBlack
	if not props.NoStroke then
		label.TextStrokeTransparency = 0.2
		label.TextStrokeColor3 = Color3.fromRGB(20, 20, 30)
	end
	return label
end

local function prompt(part: BasePart, action: string, object: string, callback: (Player) -> ())
	local p = Instance.new("ProximityPrompt")
	p.ActionText = Lang.T(action)
	p.ObjectText = Lang.T(object)
	p.KeyboardKeyCode = Enum.KeyCode.E
	p.GamepadKeyCode = Enum.KeyCode.ButtonY
	p.MaxActivationDistance = 14
	p.RequiresLineOfSight = false
	p.Parent = part
	p.Triggered:Connect(callback)
	return p
end

local function yellowBlocks(parent: Instance, position: Vector3, layout: { Vector3 })
	for _, offset in layout do
		Build.Part({ Name = "YellowBlock", Size = Vector3.new(4, 4, 4), Position = position + offset * 4 + Vector3.new(0, 2, 0), Color = P.BlockYellow, Studs = true }, parent)
	end
end

-- ---------------------------------------------------------------------------
-- Sol, enceinte, village autour
-- ---------------------------------------------------------------------------
-- Sol en pièces, comme les maps (reference/BIBLE_VISUELLE.md) : pelouse à
-- tenons en bandes, place en dalles claires, allées, terrasses de blocs au loin
local function buildGround(parent: Folder, origin: Vector3)
	local size = Config.Lobby.Size
	local random = Random.new(31)
	TerrainKit.Clear(origin + Vector3.new(0, 60, 0), Vector3.new(size + 400, 200, size + 400))
	Ground.Begin(parent, origin.Y, {
		Cobblestone = Color3.fromRGB(186, 190, 204), -- dalles de la place
		Pavement = Color3.fromRGB(226, 218, 202), -- allées
	})
	Ground.Board(origin, size, Color3.fromRGB(92, 184, 80), Color3.fromRGB(80, 168, 70), 20)
	Ground.Terraces(origin, size, { Side = Color3.fromRGB(112, 130, 166), Top = Color3.fromRGB(92, 176, 78), Gap = 54, Heights = { 12, 26, 46 } }, random)
	-- Place au nord (vote + portail), rond du spawn, allées vers chaque attraction
	Ground.Paint(CFrame.new(origin + Vector3.new(0, 0, -38)), 92, 56, origin.Y, Enum.Material.Cobblestone)
	Ground.PaintDisc(origin, 22, origin.Y, Enum.Material.Cobblestone)
	Ground.Path({ origin, origin + Vector3.new(0, 0, 60) }, 12, origin.Y, Enum.Material.Pavement)
	Ground.Path({ origin, origin + Vector3.new(-48, 0, 34) }, 9, origin.Y, Enum.Material.Pavement)
	Ground.Path({ origin, origin + Vector3.new(44, 0, -6) }, 9, origin.Y, Enum.Material.Pavement)
	Ground.Path({ origin, origin + Vector3.new(-46, 0, -8) }, 9, origin.Y, Enum.Material.Pavement)
	Ground.Path({ origin + Vector3.new(14, 0, 18), origin + Vector3.new(36, 0, 40) }, 8, origin.Y, Enum.Material.Pavement)
	-- Ligne blanche de la place
	Build.Part({ Name = "PlazaLine", Size = Vector3.new(84, 0.06, 0.8), Position = origin + Vector3.new(0, 0.6, -13), Color = P.White, CanCollide = false, Accent = true }, parent)
end

local function buildEnclosure(parent: Folder, origin: Vector3)
	local cfg = Config.Lobby
	local half = cfg.Size / 2
	-- Murets de pierre coiffés de haies, avec barrière invisible plus haute
	local corners = {
		origin + Vector3.new(-half, 0, -half), origin + Vector3.new(half, 0, -half),
		origin + Vector3.new(half, 0, half), origin + Vector3.new(-half, 0, half),
	}
	for i = 1, 4 do
		local a, b = corners[i], corners[i % 4 + 1]
		Props.StoneWall(parent, a, b, 3, Color3.fromRGB(176, 172, 166))
		local dir = (b - a).Unit
		local mid = (a + b) / 2
		Build.Part({ Name = "WallBarrier" .. i, Size = Vector3.new(4, 40, (b - a).Magnitude + 4), CFrame = CFrame.lookAt(mid + Vector3.new(0, 20, 0), mid + Vector3.new(0, 20, 0) + dir), Transparency = 1, CanQuery = false }, parent)
		-- Haie basse le long de l'intérieur, interrompue tous les 30 studs
		local length = (b - a).Magnitude
		local inward = Vector3.new(-dir.Z, 0, dir.X)
		if (origin - mid):Dot(inward) < 0 then
			inward = -inward
		end
		for k = 0, math.floor(length / 30) - 1 do
			local s = a + dir * (k * 30 + 6) + inward * 3.5
			Props.Hedge(parent, s, s + dir * 18, 3.2)
		end
		-- Lampadaires aux coins et au milieu des côtés
		Props.Lamp(parent, mid + inward * 6, math.atan2(inward.X, inward.Z) + math.pi)
	end
	-- Arbres dans les coins, à l'intérieur
	for _, corner in { Vector3.new(-1, 0, -1), Vector3.new(1, 0, -1), Vector3.new(-1, 0, 1), Vector3.new(1, 0, 1) } do
		Props.BlockTree(parent, origin + corner * (half - 11), 1.05)
	end
	Props.BlockTree(parent, origin + Vector3.new(-half + 12, 0, 22), 0.85)
	Props.RoundTree(parent, origin + Vector3.new(half - 10, 0, 30), 0.95)
	-- Village au-delà des murets : maisons turquoise à toit vert (clin d'œil à la référence)
	local walls = { Color3.fromRGB(110, 210, 184), Color3.fromRGB(250, 236, 206), Color3.fromRGB(150, 200, 240), Color3.fromRGB(246, 196, 170) }
	local roofs = { Color3.fromRGB(44, 126, 76), Color3.fromRGB(196, 66, 56), Color3.fromRGB(60, 90, 160), Color3.fromRGB(44, 126, 76) }
	local random = Random.new(12)
	local spots = {}
	for i = -2, 2 do
		table.insert(spots, { origin + Vector3.new(i * 30, 0, -half - 26), origin })
		table.insert(spots, { origin + Vector3.new(i * 30 + 8, 0, half + 26), origin })
	end
	for i = -1, 1 do
		table.insert(spots, { origin + Vector3.new(half + 26, 0, i * 36), origin })
		table.insert(spots, { origin + Vector3.new(-half - 26, 0, i * 36 + 10), origin })
	end
	for i, spot in spots do
		local cf = CFrame.lookAt(spot[1], Vector3.new(spot[2].X, spot[1].Y, spot[2].Z))
		Props.House(parent, cf, {
			Width = random:NextNumber(18, 24),
			Depth = 14,
			Floors = (i % 3 == 0) and 2 or 1,
			Wall = walls[(i % #walls) + 1],
			Roof = roofs[(i % #roofs) + 1],
			Shutters = Color3.fromRGB(70, 110, 160),
		})
	end
	-- Arbres en cubes sur les terrasses, derrière le village
	for _, spot in Ground.TerraceSpots(46, random) do
		Props.Tree(parent, spot - Vector3.new(0, 0.2, 0), random:NextNumber(1, 1.4), { "Block", "Block", "Green" })
	end
end

-- Statue stylisée d'un animal sur un socle (mascottes autour du spawn)
local function buildStatue(parent: Folder, ground: Vector3, facing: Vector3, teamId: string)
	local def = Teams.Get(teamId)
	assert(def)
	local cf = CFrame.lookAt(ground, Vector3.new(facing.X, ground.Y, facing.Z))
	local white = Color3.fromRGB(250, 248, 242)
	local dark = Color3.fromRGB(40, 32, 30)
	Build.VerticalCylinder((cf * CFrame.new(0, 1, 0)).Position, 3.2, 2, { Name = "Plinth", Color = Color3.fromRGB(200, 196, 190), Material = Enum.Material.Marble }, parent)
	Build.VerticalCylinder((cf * CFrame.new(0, 2.15, 0)).Position, 3.4, 0.3, { Name = "PlinthRing", Color = def.Color, Accent = true }, parent)
	local plate = Build.Part({ Name = "Plate", Size = Vector3.new(4, 0.9, 0.2), CFrame = cf * CFrame.new(0, 1.1, -3.25), Color = def.DarkColor, Accent = true, CanCollide = false }, parent)
	Build.SurfaceLabel(plate, Enum.NormalId.Front, def.Display, { TextColor3 = Color3.new(1, 1, 1), TextStrokeTransparency = 1, Font = Enum.Font.GothamBlack })
	local base = cf * CFrame.new(0, 2.3, 0)
	local function p(props: { [string]: any })
		props.Accent = true
		return Build.Part(props, parent)
	end
	if teamId == "FOX" then
		p({ Name = "Body", Shape = Enum.PartType.Ball, Size = Vector3.new(2.6, 2.6, 3.8), CFrame = base * CFrame.new(0, 1.8, 0.4), Color = def.Color })
		p({ Name = "Chest", Shape = Enum.PartType.Ball, Size = Vector3.new(1.8, 2, 1.4), CFrame = base * CFrame.new(0, 2, -1.2), Color = white })
		p({ Name = "Head", Shape = Enum.PartType.Ball, Size = Vector3.new(2.4, 2.2, 2.2), CFrame = base * CFrame.new(0, 3.9, -1.4), Color = def.Color })
		p({ Name = "Snout", Size = Vector3.new(1, 0.8, 1.4), CFrame = base * CFrame.new(0, 3.6, -2.6), Color = white })
		p({ Name = "Nose", Shape = Enum.PartType.Ball, Size = Vector3.new(0.45, 0.45, 0.45), CFrame = base * CFrame.new(0, 3.75, -3.3), Color = dark })
		for _, s in { -1, 1 } do
			p({ Name = "Ear", Size = Vector3.new(0.7, 1.5, 0.35), CFrame = base * CFrame.new(s * 0.75, 5.2, -1.4) * CFrame.Angles(0, 0, -s * 0.25), Color = def.Color })
			p({ Name = "EarTip", Size = Vector3.new(0.5, 0.6, 0.4), CFrame = base * CFrame.new(s * 0.88, 5.8, -1.4) * CFrame.Angles(0, 0, -s * 0.25), Color = dark })
			p({ Name = "Eye", Shape = Enum.PartType.Ball, Size = Vector3.new(0.4, 0.5, 0.3), CFrame = base * CFrame.new(s * 0.55, 4.2, -2.4), Color = dark })
			p({ Name = "Leg", Size = Vector3.new(0.6, 1.4, 0.6), CFrame = base * CFrame.new(s * 0.7, 0.7, -0.8), Color = dark })
		end
		p({ Name = "Tail", Shape = Enum.PartType.Ball, Size = Vector3.new(1.6, 1.6, 3.6), CFrame = base * CFrame.new(0.4, 2.2, 2.8) * CFrame.Angles(math.rad(-30), 0.3, 0), Color = def.Color })
		p({ Name = "TailTip", Shape = Enum.PartType.Ball, Size = Vector3.new(1.3, 1.3, 1.4), CFrame = base * CFrame.new(0.7, 3.3, 4.2), Color = white })
	elseif teamId == "CHICKEN" then
		p({ Name = "Body", Shape = Enum.PartType.Ball, Size = Vector3.new(3, 3, 3.4), CFrame = base * CFrame.new(0, 2, 0.2), Color = def.Color })
		p({ Name = "Head", Shape = Enum.PartType.Ball, Size = Vector3.new(1.9, 1.9, 1.9), CFrame = base * CFrame.new(0, 4, -1), Color = def.Color })
		p({ Name = "Beak", Size = Vector3.new(0.7, 0.5, 0.9), CFrame = base * CFrame.new(0, 3.9, -2.1), Color = Color3.fromRGB(255, 160, 30) })
		p({ Name = "Wattle", Shape = Enum.PartType.Ball, Size = Vector3.new(0.5, 0.8, 0.5), CFrame = base * CFrame.new(0, 3.3, -1.8), Color = Color3.fromRGB(230, 40, 40) })
		for k = -1, 1 do
			p({ Name = "Comb", Shape = Enum.PartType.Ball, Size = Vector3.new(0.5, 0.9, 0.7), CFrame = base * CFrame.new(0, 5 + (k == 0 and 0.2 or 0), -1 + k * 0.45), Color = Color3.fromRGB(230, 40, 40) })
		end
		for _, s in { -1, 1 } do
			p({ Name = "Eye", Shape = Enum.PartType.Ball, Size = Vector3.new(0.35, 0.45, 0.3), CFrame = base * CFrame.new(s * 0.55, 4.3, -1.7), Color = dark })
			p({ Name = "Wing", Shape = Enum.PartType.Ball, Size = Vector3.new(0.6, 1.8, 2.4), CFrame = base * CFrame.new(s * 1.55, 2.2, 0.3), Color = def.DarkColor })
			p({ Name = "Leg", Size = Vector3.new(0.3, 1, 0.3), CFrame = base * CFrame.new(s * 0.6, 0.5, 0), Color = Color3.fromRGB(255, 160, 30) })
		end
		for i, a in { -25, 0, 25 } do
			p({ Name = "TailFeather" .. i, Size = Vector3.new(0.4, 2, 0.8), CFrame = base * CFrame.new(0, 3, 1.8) * CFrame.Angles(math.rad(-35), 0, math.rad(a)) * CFrame.new(0, 0.6, 0), Color = i == 2 and white or def.DarkColor })
		end
	else
		-- Vipère lovée (anneaux de perles), capuche déployée
		for k = 0, 2 do
			local r = 2.2 - k * 0.55
			local n = 12 - k * 2
			for i = 0, n - 1 do
				local a = i / n * math.pi * 2
				p({ Name = "Coil", Shape = Enum.PartType.Ball, Size = Vector3.new(1.3, 1.1, 1.3) * (1 - k * 0.12), CFrame = base * CFrame.new(math.cos(a) * r, 0.55 + k * 0.85, math.sin(a) * r), Color = (i + k) % 3 == 0 and def.DarkColor or def.Color })
			end
		end
		p({ Name = "Neck", Size = Vector3.new(1, 3.4, 1), CFrame = base * CFrame.new(0, 4, -0.4) * CFrame.Angles(math.rad(-8), 0, 0), Color = def.Color })
		p({ Name = "Hood", Shape = Enum.PartType.Ball, Size = Vector3.new(3.4, 3, 0.8), CFrame = base * CFrame.new(0, 5.4, -0.2), Color = def.Color })
		p({ Name = "HoodMark", Shape = Enum.PartType.Ball, Size = Vector3.new(1.6, 1.4, 0.82), CFrame = base * CFrame.new(0, 5.4, -0.25), Color = def.DarkColor })
		p({ Name = "Head", Shape = Enum.PartType.Ball, Size = Vector3.new(1.6, 1.1, 2), CFrame = base * CFrame.new(0, 6.2, -1.1), Color = def.Color })
		p({ Name = "Tongue", Size = Vector3.new(0.15, 0.08, 0.9), CFrame = base * CFrame.new(0, 6, -2.3), Color = Color3.fromRGB(230, 50, 70) })
		for _, s in { -1, 1 } do
			p({ Name = "Eye", Shape = Enum.PartType.Ball, Size = Vector3.new(0.35, 0.35, 0.35), CFrame = base * CFrame.new(s * 0.45, 6.4, -1.8), Color = Color3.fromRGB(255, 220, 60), Material = Enum.Material.Neon })
		end
	end
end

-- ---------------------------------------------------------------------------
-- Spawn
-- ---------------------------------------------------------------------------
local function buildSpawn(parent: Folder, origin: Vector3)
	Build.VerticalCylinder(origin + Vector3.new(0, 0.15, 0), 10, 0.3, { Name = "SpawnRing", Color = P.White, Accent = true }, parent)
	Build.VerticalCylinder(origin + Vector3.new(0, 0.2, 0), 9, 0.3, { Name = "SpawnPad", Color = Color3.fromRGB(236, 226, 206), Material = Enum.Material.Pavement }, parent)
	Build.VerticalCylinder(origin + Vector3.new(0, 0.24, 0), 4, 0.3, { Name = "SpawnStar", Color = P.Gold, Accent = true }, parent)
	-- Anneau des trois équipes : on lit le triangle dès l'arrivée
	for index, teamId in Teams.Order do
		local def = Teams.Get(teamId)
		assert(def)
		for k = 0, 9 do
			local a = math.rad((index - 1) * 120 + k * 11 + 5)
			local pos = origin + Vector3.new(math.cos(a) * 12, 0.12, math.sin(a) * 12)
			Build.Part({ Name = "TeamRing", Size = Vector3.new(2.6, 0.16, 1.6), CFrame = CFrame.lookAt(pos, origin + Vector3.new(0, 0.12, 0)), Color = def.Color, Accent = true, CanCollide = false }, parent)
		end
	end
	-- Statues des trois animaux sur l'anneau, tournées vers le spawn
	for index, teamId in Teams.Order do
		local a = math.rad((index - 1) * 120 + 60)
		buildStatue(parent, origin + Vector3.new(math.cos(a) * 18, 0, math.sin(a) * 18), origin, teamId)
	end
	-- Guirlandes de fanions entre les lampadaires de la place
	local colors = { Teams.Defs.FOX.Color, Teams.Defs.CHICKEN.Color, Teams.Defs.SNAKE.Color, Color3.new(1, 1, 1) }
	for _, x in { -40, 40 } do
		Props.Lamp(parent, origin + Vector3.new(x, 0, -12), x < 0 and math.rad(90) or math.rad(-90))
	end
	Props.Bunting(parent, origin + Vector3.new(-40, 11, -12), origin + Vector3.new(-22, 18, -58), colors, 2)
	Props.Bunting(parent, origin + Vector3.new(40, 11, -12), origin + Vector3.new(22, 18, -58), colors, 2)
	-- Bancs et massifs fleuris autour du spawn
	for _, a in { 0, 120, 240 } do
		local r = math.rad(a)
		local pos = origin + Vector3.new(math.cos(r) * 25, 0, math.sin(r) * 25)
		Props.FlowerBed(parent, CFrame.lookAt(pos, origin), 7, 2.4)
	end
	Props.Bench(parent, CFrame.lookAt(origin + Vector3.new(-14, 0, 26), origin + Vector3.new(-14, 0, 0)))
	Props.Bench(parent, CFrame.lookAt(origin + Vector3.new(14, 0, 26), origin + Vector3.new(14, 0, 0)))

	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "LobbySpawn"
	spawn.Anchored = true
	spawn.Neutral = true
	spawn.Size = Vector3.new(10, 1, 10)
	spawn.Position = origin + Vector3.new(0, 0.5, 0)
	spawn.Transparency = 1
	spawn.CanCollide = false
	spawn.Duration = 0
	spawn.Parent = parent
	spawnCFrame = CFrame.new(origin + Vector3.new(0, 1 + Config.World.RespawnHeight, 0))
end

-- ---------------------------------------------------------------------------
-- Nord : portail, écran géant, plateformes de vote
-- ---------------------------------------------------------------------------
local function buildPortal(parent: Folder, origin: Vector3)
	local center = origin + Vector3.new(0, 11, -54)
	local radius = 9
	for i = 0, 23 do
		local a = i / 24 * math.pi * 2
		Build.Part({
			Name = "PortalRing",
			Size = Vector3.new(2.6, 2.6, 3.2),
			CFrame = CFrame.new(center + Vector3.new(math.cos(a) * radius, math.sin(a) * radius, 0)) * CFrame.Angles(0, 0, a),
			Color = P.PortalDark,
			Accent = true,
		}, parent)
	end
	local disc = Build.Part({ Name = "PortalGlow", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.4, radius * 2 - 2, radius * 2 - 2), CFrame = CFrame.new(center) * CFrame.Angles(0, math.rad(90), 0), Color = P.PortalGlow, Material = Enum.Material.Neon, Transparency = 0.45, CanCollide = false }, parent)
	local particles = Instance.new("ParticleEmitter")
	particles.Color = ColorSequence.new(P.PortalGlow)
	particles.LightEmission = 0.8
	particles.Size = NumberSequence.new(0.8, 0)
	particles.Speed = NumberRange.new(2, 5)
	particles.Lifetime = NumberRange.new(1, 2)
	particles.Rate = 18
	particles.Parent = disc
	Build.Part({ Name = "PortalBase", Size = Vector3.new(24, 2, 8), Position = center - Vector3.new(0, radius + 1, 0), Color = P.PortalDark, Studs = true, Accent = true }, parent)

	-- Écran géant au-dessus du portail : chrono + map
	local board = Build.Part({ Name = "GiantBoard", Size = Vector3.new(46, 15, 1.5), Position = origin + Vector3.new(0, 31, -58), Color = P.Screen, Accent = true }, parent)
	Build.Part({ Name = "GiantBoardFrame", Size = Vector3.new(48, 17, 1.2), Position = board.Position - Vector3.new(0, 0, 0.8), Color = P.WheelBlue, Accent = true }, parent)
	for _, side in { -1, 1 } do
		Build.Part({ Name = "BoardPost", Size = Vector3.new(2, 24, 2), Position = origin + Vector3.new(side * 22, 12, -59), Color = P.StoneDark, Studs = true }, parent)
	end
	local gui = Build.SurfaceGui(board, Enum.NormalId.Back)
	text(gui, { Name = "Title", Size = UDim2.fromScale(1, 0.2), Position = UDim2.fromScale(0, 0.04), Text = Lang.T("HUNT OR HIDE"), TextColor3 = P.Gold })
	boardLabels.Status = text(gui, { Name = "Status", Size = UDim2.fromScale(1, 0.17), Position = UDim2.fromScale(0, 0.27), Text = Lang.T("Waiting for players..."), TextColor3 = P.ScreenText })
	boardLabels.Time = text(gui, { Name = "Time", Size = UDim2.fromScale(1, 0.32), Position = UDim2.fromScale(0, 0.45), Text = "--:--", TextColor3 = Color3.new(1, 1, 1) })
	boardLabels.Map = text(gui, { Name = "Map", Size = UDim2.fromScale(1, 0.15), Position = UDim2.fromScale(0, 0.8), Text = "", TextColor3 = Color3.fromRGB(150, 210, 255) })
end

local function buildVotePads(parent: Folder, origin: Vector3)
	for index = 1, Config.Round.VoteCandidates do
		local x = (index - (Config.Round.VoteCandidates + 1) / 2) * 26
		local center = origin + Vector3.new(x, 0, -30)
		local ring = Build.VerticalCylinder(center + Vector3.new(0, 0.55, 0), 7, 0.5, { Name = "VoteRing", Color = P.PadBlue, Accent = true }, parent)
		local plate = Build.VerticalCylinder(center + Vector3.new(0, 0.7, 0), 6, 0.5, { Name = "VotePlate" .. index, Color = P.PadBlue:Lerp(Color3.new(1, 1, 1), 0.25), Accent = true }, parent)
		plate:SetAttribute("VoteIndex", index)
		-- Écran sur poteau derrière la plateforme (comme les écrans d'équipe de la référence)
		Build.Part({ Name = "VotePost", Size = Vector3.new(1.2, 9, 1.2), Position = center + Vector3.new(0, 4.5, -8), Color = P.StoneDark, Studs = true }, parent)
		local screen = Build.Part({ Name = "VoteScreen" .. index, Size = Vector3.new(14, 6, 0.8), Position = center + Vector3.new(0, 11, -8), Color = P.Screen, Accent = true }, parent)
		Build.Part({ Name = "VoteScreenFrame", Size = Vector3.new(14.8, 6.8, 0.6), Position = center + Vector3.new(0, 11, -8.4), Color = P.WheelBlue, Accent = true }, parent)
		local gui = Build.SurfaceGui(screen, Enum.NormalId.Back)
		local nameLabel = text(gui, { Size = UDim2.fromScale(0.94, 0.42), Position = UDim2.fromScale(0.03, 0.05), Text = "?", TextColor3 = P.ScreenText })
		local modeLabel = text(gui, { Size = UDim2.fromScale(0.94, 0.26), Position = UDim2.fromScale(0.03, 0.47), Text = "", TextColor3 = P.Gold })
		local votesLabel = text(gui, { Size = UDim2.fromScale(0.94, 0.24), Position = UDim2.fromScale(0.03, 0.74), Text = "", TextColor3 = Color3.fromRGB(170, 200, 255) })
		plate.Touched:Connect(function(hit)
			local player = Build.GetPlayerFromHit(hit)
			if not player then
				return
			end
			local now = os.clock()
			if lastTouch[player] and now - lastTouch[player] < 0.5 then
				return
			end
			lastTouch[player] = now
			if plateCallback then
				plateCallback(player, index)
			end
		end)
		votePlates[index] = { Part = plate, Name = nameLabel, Mode = modeLabel, Votes = votesLabel, Ring = ring, MapId = nil }
	end
end

-- ---------------------------------------------------------------------------
-- Ouest : murs de classement et roue de récompense
-- ---------------------------------------------------------------------------
local MEDALS = { Color3.fromRGB(255, 200, 40), Color3.fromRGB(200, 210, 225), Color3.fromRGB(214, 140, 80) }

local function buildLeaderboards(parent: Folder, origin: Vector3)
	local walls = {
		{ Key = "Wins", Title = Lang.T("TOP WINS"), Accent = P.Gold, Pos = Vector3.new(-58, 0, -22), Yaw = 70 },
		{ Key = "Captures", Title = Lang.T("TOP CATCHES"), Accent = Color3.fromRGB(70, 200, 160), Pos = Vector3.new(-60, 0, 6), Yaw = 85 },
	}
	for _, info in walls do
		local cf = CFrame.new(origin + info.Pos + Vector3.new(0, 11.5, 0)) * CFrame.Angles(0, math.rad(info.Yaw), 0)
		-- Cadre de pierre, écran sombre encastré, socle
		Build.Part({ Name = "LeaderboardFrame", Size = Vector3.new(27, 23, 2.4), CFrame = cf, Color = Color3.fromRGB(176, 172, 166), Material = Enum.Material.Slate }, parent)
		Build.Part({ Name = "LeaderboardCap", Size = Vector3.new(28.4, 1.4, 3.2), CFrame = cf * CFrame.new(0, 12.1, 0), Color = info.Accent, Accent = true }, parent)
		Build.Part({ Name = "LeaderboardBase", Size = Vector3.new(29, 2, 4.4), CFrame = cf * CFrame.new(0, -11.5, 0), Color = Color3.fromRGB(150, 146, 140), Material = Enum.Material.Slate }, parent)
		local screen = Build.Part({ Name = "Leaderboard" .. info.Key, Size = Vector3.new(24, 20, 0.4), CFrame = cf * CFrame.new(0, 0, 1.3), Color = P.Screen, Accent = true }, parent)
		-- Face Back : celle qui regarde le centre du lobby
		local gui = Build.SurfaceGui(screen, Enum.NormalId.Back)
		local header = Instance.new("Frame")
		header.Size = UDim2.fromScale(1, 0.17)
		header.BackgroundColor3 = info.Accent
		header.BorderSizePixel = 0
		header.Parent = gui
		text(header, { Size = UDim2.fromScale(0.9, 0.62), Position = UDim2.fromScale(0.05, 0.08), Text = info.Title, TextColor3 = Color3.fromRGB(20, 22, 36), NoStroke = true })
		text(header, { Size = UDim2.fromScale(0.9, 0.24), Position = UDim2.fromScale(0.05, 0.7), Text = Lang.T("ALL TIME"), TextColor3 = Color3.fromRGB(40, 44, 64), NoStroke = true })
		local rows = {}
		for rank = 1, Config.Lobby.LeaderboardSize do
			local row = Instance.new("Frame")
			row.Name = "Row" .. rank
			row.Position = UDim2.fromScale(0.04, 0.2 + (rank - 1) * 0.078)
			row.Size = UDim2.fromScale(0.92, 0.07)
			row.BackgroundColor3 = Color3.new(1, 1, 1)
			row.BackgroundTransparency = rank % 2 == 1 and 0.9 or 0.96
			row.BorderSizePixel = 0
			row.Visible = false
			row.Parent = gui
			local badge = Instance.new("Frame")
			badge.Size = UDim2.fromScale(0.1, 0.9)
			badge.Position = UDim2.fromScale(0.01, 0.05)
			badge.BackgroundColor3 = MEDALS[rank] or Color3.fromRGB(70, 80, 110)
			badge.BorderSizePixel = 0
			badge.Parent = row
			local corner = Instance.new("UICorner")
			corner.CornerRadius = UDim.new(0.5, 0)
			corner.Parent = badge
			text(badge, { Size = UDim2.fromScale(0.8, 0.8), Position = UDim2.fromScale(0.1, 0.1), Text = tostring(rank), TextColor3 = rank <= 3 and Color3.fromRGB(20, 22, 36) or Color3.new(1, 1, 1), NoStroke = rank <= 3 })
			local name = text(row, { Name = "PlayerName", Size = UDim2.fromScale(0.6, 0.8), Position = UDim2.fromScale(0.14, 0.1), Text = "", TextColor3 = Color3.new(1, 1, 1), TextXAlignment = Enum.TextXAlignment.Left })
			local value = text(row, { Name = "Value", Size = UDim2.fromScale(0.24, 0.8), Position = UDim2.fromScale(0.74, 0.1), Text = "", TextColor3 = info.Accent, TextXAlignment = Enum.TextXAlignment.Right })
			rows[rank] = { Frame = row, Name = name, Value = value }
		end
		local message = text(gui, { Name = "Message", Size = UDim2.fromScale(0.84, 0.16), Position = UDim2.fromScale(0.08, 0.48), Text = Lang.T("Loading..."), TextColor3 = Color3.fromRGB(200, 210, 230) })
		leaderboards[info.Key] = { Rows = rows, Message = message }
	end
end

local function buildWheel(parent: Folder, origin: Vector3)
	local base = origin + Vector3.new(-48, 0, 42)
	local facing = CFrame.lookAt(base, origin + Vector3.new(0, 0, 0))
	local axisCf = facing * CFrame.new(0, 14, 0)
	-- Pied
	Build.Part({ Name = "WheelStand", Size = Vector3.new(4, 14, 3), CFrame = facing * CFrame.new(0, 7, 1), Color = P.WheelBlue, Accent = true }, parent)
	Build.Part({ Name = "WheelFoot", Size = Vector3.new(14, 1.5, 8), CFrame = facing * CFrame.new(0, 0.75, 1), Color = P.WheelBlue, Accent = true }, parent)
	-- Roue : modèle tournant autour de son axe (animé par MechanicsController)
	local model = Instance.new("Model")
	model.Name = "RewardWheel"
	-- Le pivot "tourne" autour de son axe Y : on oriente l'axe Y vers le centre
	local pivot = axisCf * CFrame.Angles(math.rad(90), 0, 0)
	local anchor = Build.Part({ Name = "Pivot", Size = Vector3.new(0.2, 0.2, 0.2), CFrame = pivot, Transparency = 1, CanCollide = false, CanQuery = false }, model)
	model.PrimaryPart = anchor
	local radius = 10
	local rewards = Config.DailySpin.Rewards
	wheelSegments = #rewards
	for i, reward in rewards do
		local a = (i - 0.5) / #rewards * math.pi * 2
		local seg = Build.Part({
			Name = "Segment" .. i,
			Size = Vector3.new(radius * 0.95, 0.6, 2 * math.pi * radius / #rewards * 0.98),
			CFrame = pivot * CFrame.Angles(0, a, 0) * CFrame.new(radius / 2, 0, 0),
			Color = i % 2 == 0 and P.White or P.WheelBlue,
			Accent = true,
			CanCollide = false,
		}, model)
		local gui = Build.SurfaceGui(seg, Enum.NormalId.Bottom)
		text(gui, { Size = UDim2.fromScale(0.95, 0.9), Position = UDim2.fromScale(0.025, 0.05), Text = Lang.T(reward.Label), TextColor3 = i % 2 == 0 and P.WheelBlue or P.White, Rotation = 90 })
	end
	Build.Part({ Name = "WheelHub", Shape = Enum.PartType.Cylinder, Size = Vector3.new(1.2, 4, 4), CFrame = pivot * CFrame.Angles(0, 0, math.rad(90)), Color = P.White, Accent = true, CanCollide = false }, model)
	model:SetAttribute("SpinBase", pivot)
	Mechanics.SetSpin(model, 0, 0)
	CollectionService:AddTag(model, Mechanics.SpinnerTag)
	model.Parent = parent
	wheel = model
	-- Flèche en haut de la roue
	Build.Part({ Name = "WheelPointer", Size = Vector3.new(1.4, 2.4, 1.4), CFrame = axisCf * CFrame.new(0, radius + 1, -1.2) * CFrame.Angles(0, 0, math.rad(45)), Color = P.GiftRed, Accent = true }, parent)
	-- Panneau et bouton d'interaction
	local sign = Build.Part({ Name = "WheelSign", Size = Vector3.new(12, 3, 0.6), CFrame = axisCf * CFrame.new(0, radius + 4, 0), Color = P.Screen, Accent = true }, parent)
	text(Build.SurfaceGui(sign, Enum.NormalId.Front), { Size = UDim2.fromScale(1, 0.9), Position = UDim2.fromScale(0, 0.05), Text = Lang.T("DAILY SPIN"), TextColor3 = P.Gold })
	local button = Build.Part({ Name = "WheelButton", Size = Vector3.new(4, 3, 3), CFrame = facing * CFrame.new(0, 1.5, -5), Color = P.GiftRed, Studs = true, Accent = true }, parent)
	prompt(button, "Spin", "Daily Spin", function(player)
		if spinCallback then
			spinCallback(player)
		end
	end)
end

-- ---------------------------------------------------------------------------
-- Est : cadeau géant = boutique
-- ---------------------------------------------------------------------------
local function buildGiftShop(parent: Folder, origin: Vector3)
	local center = origin + Vector3.new(52, 0, -6)
	local size = 16
	local box = Build.Part({ Name = "GiftBox", Size = Vector3.new(size, size * 0.8, size), CFrame = CFrame.new(center + Vector3.new(0, size * 0.4, 0)) * CFrame.Angles(0, math.rad(20), 0), Color = P.GiftRed, Studs = true, Accent = true }, parent)
	Build.Part({ Name = "GiftLid", Size = Vector3.new(size + 1.5, 2.4, size + 1.5), CFrame = box.CFrame * CFrame.new(0, size * 0.4 + 1.2, 0), Color = P.GiftRed:Lerp(Color3.new(1, 1, 1), 0.08), Studs = true, Accent = true }, parent)
	for _, axis in { 0, 90 } do
		Build.Part({ Name = "Ribbon", Size = Vector3.new(2.6, size * 0.8 + 2.6, size + 1.7), CFrame = box.CFrame * CFrame.Angles(0, math.rad(axis), 0) * CFrame.new(0, 1.2, 0), Color = P.Gold, Accent = true }, parent)
	end
	for _, side in { -1, 1 } do
		Build.Part({ Name = "Bow", Size = Vector3.new(4, 3, 2), CFrame = box.CFrame * CFrame.new(side * 2.4, size * 0.4 + 3.6, 0) * CFrame.Angles(0, 0, math.rad(side * 30)), Color = P.Gold, Accent = true }, parent)
	end
	-- Comptoir devant le cadeau
	local counter = Build.Part({ Name = "ShopCounter", Size = Vector3.new(4, 3.5, 12), CFrame = box.CFrame * CFrame.new(-size / 2 - 4, -size * 0.4 + 1.75, 0), Color = P.Wood, Material = Enum.Material.WoodPlanks }, parent)
	prompt(counter, "Open Shop", "Shop", function(player)
		if shopCallback then
			shopCallback(player)
		end
	end)
	local sign = Build.Part({ Name = "ShopSign", Size = Vector3.new(0.6, 4, 14), CFrame = box.CFrame * CFrame.new(-size / 2 - 0.4, size * 0.4 + 6, 0), Color = P.Screen, Accent = true }, parent)
	text(Build.SurfaceGui(sign, Enum.NormalId.Left), { Size = UDim2.fromScale(1, 0.9), Position = UDim2.fromScale(0, 0.05), Text = Lang.T("SHOP"), TextColor3 = P.Gold })
end

-- ---------------------------------------------------------------------------
-- Sud : règles + parcours de dash
-- ---------------------------------------------------------------------------
local function buildRules(parent: Folder, origin: Vector3)
	local center = origin + Vector3.new(0, 0, 62)
	local board = Build.Part({ Name = "RulesBoard", Size = Vector3.new(34, 18, 1.5), Position = center + Vector3.new(0, 14, 0), Color = P.Screen, Accent = true }, parent)
	Build.Part({ Name = "RulesFrame", Size = Vector3.new(36, 20, 1.2), Position = center + Vector3.new(0, 14, 0.8), Color = P.WheelBlue, Accent = true }, parent)
	for _, side in { -1, 1 } do
		Build.Part({ Name = "RulesPost", Size = Vector3.new(2, 14, 2), Position = center + Vector3.new(side * 16, 7, 1), Color = P.StoneDark, Studs = true }, parent)
	end
	local gui = Build.SurfaceGui(board, Enum.NormalId.Front)
	text(gui, { Name = "Title", Size = UDim2.fromScale(1, 0.13), Position = UDim2.fromScale(0, 0.03), Text = Lang.T("WHO CATCHES WHO?"), TextColor3 = P.Gold })
	local function animal(teamId: string, position: UDim2)
		local def = Teams.Get(teamId)
		assert(def)
		local frame = Instance.new("Frame")
		frame.AnchorPoint = Vector2.new(0.5, 0.5)
		frame.Size = UDim2.fromScale(0.28, 0.14)
		frame.Position = position
		frame.BackgroundColor3 = def.Color
		frame.Parent = gui
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0.25, 0)
		corner.Parent = frame
		text(frame, { Size = UDim2.fromScale(0.9, 0.76), Position = UDim2.fromScale(0.05, 0.12), Text = def.Display, TextColor3 = Color3.new(1, 1, 1) })
	end
	local function arrow(position: UDim2, rotation: number)
		text(gui, { AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromScale(0.12, 0.12), Position = position, Text = "➜", Rotation = rotation, TextColor3 = Color3.new(1, 1, 1) })
	end
	animal("FOX", UDim2.fromScale(0.5, 0.3))
	animal("CHICKEN", UDim2.fromScale(0.78, 0.68))
	animal("SNAKE", UDim2.fromScale(0.22, 0.68))
	arrow(UDim2.fromScale(0.68, 0.47), 55)
	arrow(UDim2.fromScale(0.5, 0.72), 180)
	arrow(UDim2.fromScale(0.32, 0.47), -55)
	text(gui, { Name = "Rule", Size = UDim2.fromScale(1, 0.1), Position = UDim2.fromScale(0, 0.87), Text = Teams.Rule, TextColor3 = Color3.new(1, 1, 1) })
end

local function buildPractice(parent: Folder, origin: Vector3)
	-- Slalom de blocs jaunes pour s'entraîner au dash
	for i = 0, 5 do
		local x = 30 + (i % 2) * 8
		local z = 22 + i * 8
		yellowBlocks(parent, origin + Vector3.new(x, 0, z), { Vector3.new(0, 0, 0) })
	end
	yellowBlocks(parent, origin + Vector3.new(54, 0, 50), { Vector3.new(0, 0, 0), Vector3.new(1, 0, 0), Vector3.new(0, 0, 1), Vector3.new(0.5, 1, 0.5) })
	yellowBlocks(parent, origin + Vector3.new(-30, 0, -8), { Vector3.new(0, 0, 0), Vector3.new(0, 0, 1) })
	local label = Build.Part({ Name = "PracticeSign", Size = Vector3.new(14, 3, 0.6), Position = origin + Vector3.new(34, 6, 16), Color = P.Screen, Accent = true }, parent)
	text(Build.SurfaceGui(label, Enum.NormalId.Front), { Size = UDim2.fromScale(1, 0.9), Position = UDim2.fromScale(0, 0.05), Text = Lang.T("DASH PRACTICE"), TextColor3 = P.Gold })
end

-- ---------------------------------------------------------------------------
-- API publique
-- ---------------------------------------------------------------------------
function LobbyBuilder.Build()
	if folder then
		folder:Destroy()
	end
	local newFolder = Instance.new("Folder")
	newFolder.Name = "Lobby"
	local origin = Config.World.LobbyOrigin
	buildGround(newFolder, origin)
	buildEnclosure(newFolder, origin)
	buildSpawn(newFolder, origin)
	buildPortal(newFolder, origin)
	buildVotePads(newFolder, origin)
	buildLeaderboards(newFolder, origin)
	buildWheel(newFolder, origin)
	buildGiftShop(newFolder, origin)
	buildRules(newFolder, origin)
	buildPractice(newFolder, origin)
	newFolder.Parent = workspace
	folder = newFolder
	Players.PlayerRemoving:Connect(function(player)
		lastTouch[player] = nil
	end)
end

function LobbyBuilder.GetSpawnCFrame(): CFrame
	local angle = math.random() * math.pi * 2
	local radius = math.random() * 5
	return spawnCFrame + Vector3.new(math.cos(angle) * radius, 0, math.sin(angle) * radius)
end

function LobbyBuilder.SetBoard(statusText: string, timeText: string, mapText: string)
	if boardLabels.Status then
		boardLabels.Status.Text = statusText
	end
	if boardLabels.Time then
		boardLabels.Time.Text = timeText
	end
	if boardLabels.Map then
		boardLabels.Map.Text = mapText
	end
end

function LobbyBuilder.OnVotePlateTouched(callback: (Player, number) -> ())
	plateCallback = callback
end

function LobbyBuilder.OnShopOpened(callback: (Player) -> ())
	shopCallback = callback
end

function LobbyBuilder.OnSpinRequested(callback: (Player) -> ())
	spinCallback = callback
end

-- Fait tourner la roue et l'arrête sur le segment "index" (animation côté clients)
function LobbyBuilder.SpinWheel(index: number, seconds: number)
	local model = wheel
	if not model then
		return
	end
	local segment = math.pi * 2 / wheelSegments
	-- Angle final : le segment visé se retrouve sous la flèche (en haut)
	local current = Mechanics.GetAngle(model)
	local target = -((index - 0.5) * segment) + math.pi / 2
	local turns = math.pi * 2 * 4
	local delta = ((target - current) % (math.pi * 2)) + turns
	Mechanics.SetSpin(model, delta / seconds, current)
	task.delay(seconds, function()
		if wheel == model then
			Mechanics.SetSpin(model, 0, current + delta)
		end
	end)
end

function LobbyBuilder.SetVoteCandidates(candidates: { string })
	for index, plate in votePlates do
		local option = candidates[index]
		local mapId, modeId = ModeInfo.Split(option)
		local mapDef, modeDef = MapInfo.Get(mapId), ModeInfo.Get(modeId)
		plate.MapId = option
		if mapDef and modeDef then
			plate.Part.Color = modeDef.Color
			plate.Name.Text = modeDef.DisplayName
			plate.Mode.Text = mapDef.DisplayName
			plate.Votes.Text = string.format("%d %s", 0, Lang.Plural(0, "vote", "votes"))
		else
			plate.Part.Color = P.PadBlue
			plate.Name.Text = "-"
			plate.Mode.Text = ""
			plate.Votes.Text = ""
		end
	end
end

function LobbyBuilder.SetVoteCounts(counts: { [string]: number })
	for _, plate in votePlates do
		local option = plate.MapId
		if option then
			local n = counts[option] or 0
			plate.Votes.Text = string.format("%d %s", n, Lang.Plural(n, "vote", "votes"))
		end
	end
end

function LobbyBuilder.GetVotePlateMapId(index: number): string?
	local plate = votePlates[index]
	return plate and plate.MapId or nil
end

-- Message à la place de la liste (classements indisponibles...)
function LobbyBuilder.SetLeaderboardMessage(key: string, message: string)
	local board = leaderboards[key]
	if not board then
		return
	end
	for _, row in board.Rows do
		row.Frame.Visible = false
	end
	board.Message.Text = message
	board.Message.Visible = true
end

-- Liste classée : { { nom, valeur }, ... }
function LobbyBuilder.SetLeaderboard(key: string, entries: { { any } })
	local board = leaderboards[key]
	if not board then
		return
	end
	if #entries == 0 then
		LobbyBuilder.SetLeaderboardMessage(key, Lang.T("Play a round to\nappear here!"))
		return
	end
	board.Message.Visible = false
	for rank, row in board.Rows do
		local entry = entries[rank]
		row.Frame.Visible = entry ~= nil
		if entry then
			row.Name.Text = tostring(entry[1])
			row.Value.Text = tostring(entry[2])
		end
	end
end

return LobbyBuilder

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
local MapInfo = require(Shared.MapInfo)
local Style = require(Shared.Style)
local Mechanics = require(Shared.Mechanics)
local Build = require(script.Parent.Parent.Util.Build)

local LobbyBuilder = {}

local P = Style.Palette
local folder: Folder? = nil
local spawnCFrame = CFrame.new(Config.World.LobbyOrigin + Vector3.new(0, 3, 0))
local random = Random.new(7)

type BoardLabels = { Status: TextLabel?, Time: TextLabel?, Map: TextLabel? }
local boardLabels: BoardLabels = {}
type VotePlate = { Part: Part, Name: TextLabel, Mode: TextLabel, Votes: TextLabel, Ring: Part, MapId: string? }
local votePlates: { VotePlate } = {}
local plateCallback: ((Player, number) -> ())? = nil
local shopCallback: ((Player) -> ())? = nil
local spinCallback: ((Player) -> ())? = nil
local lastTouch: { [Player]: number } = {}
local leaderboardLabels: { [string]: TextLabel } = {}
local wheel: Model? = nil
local wheelSegments = 8

-- ---------------------------------------------------------------------------
-- Éléments génériques
-- ---------------------------------------------------------------------------
local function text(parent: Instance, props: { [string]: any }): TextLabel
	local label = Build.TextLabel(parent, props)
	label.Font = Enum.Font.GothamBlack
	if not props.NoStroke then
		label.TextStrokeTransparency = 0.2
		label.TextStrokeColor3 = Color3.fromRGB(20, 20, 30)
	end
	return label
end

local function prompt(part: BasePart, action: string, object: string, callback: (Player) -> ())
	local p = Instance.new("ProximityPrompt")
	p.ActionText = action
	p.ObjectText = object
	p.KeyboardKeyCode = Enum.KeyCode.E
	p.GamepadKeyCode = Enum.KeyCode.ButtonY
	p.MaxActivationDistance = 14
	p.RequiresLineOfSight = false
	p.Parent = part
	p.Triggered:Connect(callback)
	return p
end

local function cubeTree(parent: Instance, position: Vector3, scale: number)
	Build.Part({ Name = "Trunk", Size = Vector3.new(2.4, 12, 2.4) * scale, CFrame = CFrame.new(position + Vector3.new(0, 6 * scale, 0)) * CFrame.Angles(0, random:NextNumber(0, 1.5), 0), Color = P.Trunk, Material = Enum.Material.Wood }, parent)
	local colors = { P.LeafOrange, P.LeafRed, P.LeafYellow, P.LeafOrange }
	local cubes = { { Vector3.new(0, 14, 0), 9 }, { Vector3.new(4, 12, 2), 7 }, { Vector3.new(-3.5, 12.5, -2), 7 }, { Vector3.new(1, 18, -1), 6.5 }, { Vector3.new(-2, 11, 4), 6 } }
	for i, spec in cubes do
		local size = spec[2] * scale
		Build.Part({
			Name = "Leaves",
			Size = Vector3.new(size, size, size),
			CFrame = CFrame.new(position + spec[1] * scale) * CFrame.Angles(random:NextNumber(-0.5, 0.5), random:NextNumber(0, 1.5), random:NextNumber(-0.5, 0.5)),
			Color = colors[(i - 1) % #colors + 1],
			Studs = true,
		}, parent)
	end
end

local function yellowBlocks(parent: Instance, position: Vector3, layout: { Vector3 })
	for _, offset in layout do
		Build.Part({ Name = "YellowBlock", Size = Vector3.new(4, 4, 4), Position = position + offset * 4 + Vector3.new(0, 2, 0), Color = P.BlockYellow, Studs = true }, parent)
	end
end

local function house(parent: Instance, position: Vector3, yaw: number, width: number)
	local cf = CFrame.new(position) * CFrame.Angles(0, yaw, 0)
	Build.Part({ Name = "HouseWall", Size = Vector3.new(width, 14, 18), CFrame = cf * CFrame.new(0, 7, 0), Color = P.HouseWall }, parent)
	for _, side in { -1, 1 } do
		Build.Part({ Name = "HouseRoof", Size = Vector3.new(width + 2, 1.2, 11), CFrame = cf * CFrame.new(0, 17, side * 4.6) * CFrame.Angles(math.rad(side * 30), 0, 0), Color = P.HouseRoof, Studs = true }, parent)
	end
	Build.Part({ Name = "HouseGable", Size = Vector3.new(width, 4, 9), CFrame = cf * CFrame.new(0, 15.5, 0), Color = P.HouseWall }, parent)
	Build.Part({ Name = "Garage", Size = Vector3.new(width * 0.4, 8, 0.4), CFrame = cf * CFrame.new(-width * 0.2, 4, -9.1), Color = P.Garage }, parent)
	Build.Part({ Name = "Window", Size = Vector3.new(4, 4, 0.3), CFrame = cf * CFrame.new(width * 0.25, 8, -9.1), Color = Color3.fromRGB(90, 160, 240), Material = Enum.Material.Glass, Accent = true }, parent)
end

-- ---------------------------------------------------------------------------
-- Sol, enceinte, décor
-- ---------------------------------------------------------------------------
local function buildGround(parent: Folder, origin: Vector3)
	local size = Config.Lobby.Size
	Build.Part({ Name = "Floor", Size = Vector3.new(size, 2, size), Position = origin + Vector3.new(0, -1, 0), Color = P.Grass, Studs = true }, parent)
	-- Place de pierre au nord (vote + portail) avec une ligne blanche
	Build.Part({ Name = "Plaza", Size = Vector3.new(84, 0.4, 52), Position = origin + Vector3.new(0, 0.2, -38), Color = P.Stone, Studs = true }, parent)
	Build.Part({ Name = "PlazaLine", Size = Vector3.new(84, 0.06, 0.8), Position = origin + Vector3.new(0, 0.43, -13), Color = P.White, CanCollide = false, Accent = true }, parent)
	-- Allée de pierre vers le sud
	Build.Part({ Name = "Path", Size = Vector3.new(14, 0.3, 60), Position = origin + Vector3.new(0, 0.15, 30), Color = P.StoneDark, Studs = true }, parent)
end

local function buildEnclosure(parent: Folder, origin: Vector3)
	local cfg = Config.Lobby
	local half = cfg.Size / 2
	local h = 7
	-- Murets de pierre (le lobby est fermé mais le ciel reste visible)
	local sides = {
		{ Vector3.new(0, 0, -half), Vector3.new(cfg.Size + 4, h, 4) },
		{ Vector3.new(0, 0, half), Vector3.new(cfg.Size + 4, h, 4) },
		{ Vector3.new(-half, 0, 0), Vector3.new(4, h, cfg.Size + 4) },
		{ Vector3.new(half, 0, 0), Vector3.new(4, h, cfg.Size + 4) },
	}
	for index, spec in sides do
		Build.Part({ Name = "Wall" .. index, Size = spec[2], Position = origin + spec[1] + Vector3.new(0, h / 2, 0), Color = P.StoneDark, Studs = true }, parent)
		Build.Part({ Name = "WallCap" .. index, Size = spec[2] + Vector3.new(1, -h + 1.2, 1), Position = origin + spec[1] + Vector3.new(0, h + 0.6, 0), Color = P.GrassDark, Studs = true }, parent)
		-- Barrière invisible plus haute pour ne pas sortir en sautant
		Build.Part({ Name = "WallBarrier" .. index, Size = spec[2] + Vector3.new(0, 30, 0), Position = origin + spec[1] + Vector3.new(0, h + 15, 0), Transparency = 1, CanQuery = false }, parent)
	end
	-- Arbres dans les coins, à l'intérieur
	for _, corner in { Vector3.new(-1, 0, -1), Vector3.new(1, 0, -1), Vector3.new(-1, 0, 1), Vector3.new(1, 0, 1) } do
		cubeTree(parent, origin + corner * (half - 10), 1)
	end
	cubeTree(parent, origin + Vector3.new(-half + 12, 0, 0), 0.85)
	cubeTree(parent, origin + Vector3.new(half - 10, 0, 28), 0.9)
	-- Maisons et grands arbres au-delà des murets (décor de fond)
	for i = -2, 2 do
		house(parent, origin + Vector3.new(i * 32, 0, -half - 22), 0, 22)
	end
	for i = -1, 1 do
		house(parent, origin + Vector3.new(half + 24, 0, i * 40), math.rad(-90), 24)
		cubeTree(parent, origin + Vector3.new(-half - 18, 0, i * 45), 1.4)
	end
	for i = -2, 2 do
		cubeTree(parent, origin + Vector3.new(i * 30, 0, half + 18), 1.3)
	end
	-- Ground extérieur
	Build.Part({ Name = "OuterGround", Size = Vector3.new(cfg.Size + 120, 1.8, cfg.Size + 120), Position = origin + Vector3.new(0, -1.1, 0), Color = P.GrassDark, Studs = true, CanQuery = false }, parent)
end

-- ---------------------------------------------------------------------------
-- Spawn
-- ---------------------------------------------------------------------------
local function buildSpawn(parent: Folder, origin: Vector3)
	Build.VerticalCylinder(origin + Vector3.new(0, 0.15, 0), 10, 0.3, { Name = "SpawnRing", Color = P.White, Accent = true }, parent)
	Build.VerticalCylinder(origin + Vector3.new(0, 0.2, 0), 9, 0.3, { Name = "SpawnPad", Color = P.Grass, Studs = true }, parent)
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
	text(gui, { Name = "Title", Size = UDim2.fromScale(1, 0.2), Position = UDim2.fromScale(0, 0.04), Text = "HUNT OR HIDE", TextColor3 = P.Gold })
	boardLabels.Status = text(gui, { Name = "Status", Size = UDim2.fromScale(1, 0.17), Position = UDim2.fromScale(0, 0.27), Text = "Waiting for players...", TextColor3 = P.ScreenText })
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
local function buildLeaderboards(parent: Folder, origin: Vector3)
	local walls = { { Key = "Wins", Title = "TOP WINS", Pos = Vector3.new(-58, 0, -22), Yaw = 70 }, { Key = "Captures", Title = "TOP CATCHES", Pos = Vector3.new(-60, 0, 6), Yaw = 85 } }
	for _, info in walls do
		local cf = CFrame.new(origin + info.Pos + Vector3.new(0, 11, 0)) * CFrame.Angles(0, math.rad(info.Yaw), 0)
		local wall = Build.Part({ Name = "Leaderboard" .. info.Key, Size = Vector3.new(26, 22, 2), CFrame = cf, Color = P.BoardGray, Studs = true }, parent)
		Build.Part({ Name = "LeaderboardBase", Size = Vector3.new(28, 2, 4), CFrame = cf * CFrame.new(0, -11, 0), Color = P.StoneDark, Studs = true }, parent)
		-- Face Back : celle qui regarde le centre du lobby
		local gui = Build.SurfaceGui(wall, Enum.NormalId.Back)
		text(gui, { Name = "Title", Size = UDim2.fromScale(1, 0.12), Position = UDim2.fromScale(0, 0.03), Text = info.Title, TextColor3 = Color3.new(1, 1, 1) })
		text(gui, { Name = "Sub", Size = UDim2.fromScale(1, 0.05), Position = UDim2.fromScale(0, 0.15), Text = "ALL TIME", TextColor3 = Color3.fromRGB(225, 230, 240) })
		local entries = text(gui, {
			Name = "Entries",
			Size = UDim2.fromScale(0.88, 0.76),
			Position = UDim2.fromScale(0.06, 0.22),
			Text = "Loading...",
			TextColor3 = Color3.new(1, 1, 1),
			TextXAlignment = Enum.TextXAlignment.Left,
			TextYAlignment = Enum.TextYAlignment.Top,
		})
		leaderboardLabels[info.Key] = entries
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
		text(gui, { Size = UDim2.fromScale(0.95, 0.9), Position = UDim2.fromScale(0.025, 0.05), Text = reward.Label, TextColor3 = i % 2 == 0 and P.WheelBlue or P.White, Rotation = 90 })
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
	text(Build.SurfaceGui(sign, Enum.NormalId.Front), { Size = UDim2.fromScale(1, 0.9), Position = UDim2.fromScale(0, 0.05), Text = "DAILY SPIN", TextColor3 = P.Gold })
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
	text(Build.SurfaceGui(sign, Enum.NormalId.Left), { Size = UDim2.fromScale(1, 0.9), Position = UDim2.fromScale(0, 0.05), Text = "SHOP", TextColor3 = P.Gold })
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
	text(gui, { Name = "Title", Size = UDim2.fromScale(1, 0.13), Position = UDim2.fromScale(0, 0.03), Text = "WHO CATCHES WHO?", TextColor3 = P.Gold })
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
	text(Build.SurfaceGui(label, Enum.NormalId.Front), { Size = UDim2.fromScale(1, 0.9), Position = UDim2.fromScale(0, 0.05), Text = "DASH PRACTICE", TextColor3 = P.Gold })
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
		local mapId = candidates[index]
		local def = MapInfo.Get(mapId)
		plate.MapId = mapId
		if def then
			plate.Part.Color = def.Color
			plate.Name.Text = def.DisplayName
			plate.Mode.Text = def.ModeName
			plate.Votes.Text = "0 votes"
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
		local mapId = plate.MapId
		if mapId then
			local n = counts[mapId] or 0
			plate.Votes.Text = string.format("%d vote%s", n, n == 1 and "" or "s")
		end
	end
end

function LobbyBuilder.GetVotePlateMapId(index: number): string?
	local plate = votePlates[index]
	return plate and plate.MapId or nil
end

function LobbyBuilder.SetLeaderboard(key: string, entries: { { any } })
	local label = leaderboardLabels[key]
	if not label then
		return
	end
	if #entries == 0 then
		label.Text = "No data yet"
		return
	end
	local lines = {}
	for rank, entry in entries do
		table.insert(lines, string.format("#%d  %s   %s", rank, tostring(entry[1]), tostring(entry[2])))
	end
	label.Text = table.concat(lines, "\n")
end

return LobbyBuilder

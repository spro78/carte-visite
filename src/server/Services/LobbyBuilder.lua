--[[
	LobbyBuilder.lua
	Lobby carré et fermé, construit entièrement par le code, dans une ambiance
	de hangar industriel (direction artistique : Shared/Style).

	Disposition (vue du dessus, Nord = -Z) :
	            [ ÉCRAN GÉANT : chrono + map ]                 Nord
	        [ QUAI 1 ]   [ QUAI 2 ]   [ QUAI 3 ]   <- plaques de vote
	 [CLASSEMENTS]                          [BOUTIQUE]
	 (victoires,         ( SPAWN )          (conteneur,       Ouest / Est
	  captures)        anneau d'équipes      comptoir)
	 [piste de dash]
	        [ ÉCRAN DES RÈGLES : FOX > CHICKEN > SNAKE ]
	        [====== TAPIS ROULANT ======>]                       Sud
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Teams = require(Shared.Teams)
local MapInfo = require(Shared.MapInfo)
local Style = require(Shared.Style)
local Build = require(script.Parent.Parent.Util.Build)

local LobbyBuilder = {}

local P = Style.Palette
local folder: Folder? = nil
local spawnCFrame = CFrame.new(Config.World.LobbyOrigin + Vector3.new(0, 3, 0))

type BoardLabels = { Status: TextLabel?, Time: TextLabel?, Map: TextLabel? }
local boardLabels: BoardLabels = {}
type VotePlate = { Part: Part, Name: TextLabel, Mode: TextLabel, Votes: TextLabel, Strip: Part, MapId: string? }
local votePlates: { VotePlate } = {}
local plateCallback: ((Player, number) -> ())? = nil
local shopCallback: ((Player) -> ())? = nil
local lastTouch: { [Player]: number } = {}
local leaderboardLabels: { [string]: TextLabel } = {}

-- ---------------------------------------------------------------------------
-- Éléments génériques
-- ---------------------------------------------------------------------------
local function screen(parent: Instance, name: string, size: Vector3, cframe: CFrame, face: Enum.NormalId): (Part, SurfaceGui)
	-- Cadre en acier + dalle d'écran
	Build.Part({
		Name = name .. "Frame",
		Size = size + Vector3.new(1.6, 1.6, -0.4),
		CFrame = cframe * CFrame.new(0, 0, face == Enum.NormalId.Back and -0.4 or 0.4),
		Color = P.Steel,
		Material = Enum.Material.Metal,
	}, parent)
	local panel = Build.Part({
		Name = name,
		Size = size,
		CFrame = cframe,
		Color = P.Screen,
		Material = Enum.Material.SmoothPlastic,
		Accent = true,
	}, parent)
	local gui = Build.SurfaceGui(panel, face)
	return panel, gui
end

local function hazardStripe(parent: Instance, from: Vector3, to: Vector3, height: number, thickness: number)
	local delta = to - from
	local length = delta.Magnitude
	local count = math.max(1, math.floor(length / 3))
	local step = delta / count
	for i = 0, count - 1 do
		local center = from + step * (i + 0.5)
		Build.Part({
			Name = "Hazard",
			Size = Vector3.new(thickness, height, length / count),
			CFrame = CFrame.lookAt(center, center + delta),
			Color = i % 2 == 0 and P.Hazard or P.HazardDark,
			Accent = true,
		}, parent)
	end
end

local function floorLine(parent: Instance, from: Vector3, to: Vector3, width: number, color: Color3)
	local delta = to - from
	local mid = (from + to) / 2
	Build.Part({
		Name = "FloorLine",
		Size = Vector3.new(width, 0.06, delta.Magnitude),
		CFrame = CFrame.lookAt(mid, mid + delta),
		Color = color,
		CanCollide = false,
		CanQuery = false,
		Accent = true,
	}, parent)
end

local function floorText(parent: Instance, position: Vector3, yaw: number, size: Vector2, text: string, color: Color3)
	local part = Build.Part({
		Name = "FloorText",
		Size = Vector3.new(size.X, 0.05, size.Y),
		CFrame = CFrame.new(position) * CFrame.Angles(0, yaw, 0),
		Transparency = 1,
		CanCollide = false,
		CanQuery = false,
	}, parent)
	Build.SurfaceLabel(part, Enum.NormalId.Top, text, { TextColor3 = color, TextTransparency = 0.1 })
end

local function crate(parent: Instance, position: Vector3, size: number, yaw: number, metal: boolean?)
	Build.Part({
		Name = "Crate",
		Size = Vector3.new(size, size, size),
		CFrame = CFrame.new(position + Vector3.new(0, size / 2, 0)) * CFrame.Angles(0, yaw, 0),
		Color = metal and P.SteelLight or P.Wood,
		Material = metal and Enum.Material.DiamondPlate or Enum.Material.WoodPlanks,
	}, parent)
end

local function barrel(parent: Instance, position: Vector3, color: Color3)
	Build.VerticalCylinder(position + Vector3.new(0, 2, 0), 1.4, 4, { Name = "Barrel", Color = color, Material = Enum.Material.CorrodedMetal }, parent)
end

-- ---------------------------------------------------------------------------
-- Sol, murs, toit
-- ---------------------------------------------------------------------------
local function buildShell(parent: Folder, origin: Vector3)
	local cfg = Config.Lobby
	local size = cfg.Size
	local half = size / 2
	local height = cfg.WallHeight

	Build.Part({ Name = "Floor", Size = Vector3.new(size, 2, size), Position = origin + Vector3.new(0, -1, 0), Color = P.Concrete, Material = Enum.Material.Concrete }, parent)
	-- Joints de dalles
	for i = -4, 4 do
		local x = i * 15
		floorLine(parent, origin + Vector3.new(x, 0.03, -half), origin + Vector3.new(x, 0.03, half), 0.25, Style.Environment(P.ConcreteDark))
		floorLine(parent, origin + Vector3.new(-half, 0.03, x), origin + Vector3.new(half, 0.03, x), 0.25, Style.Environment(P.ConcreteDark))
	end
	-- Ligne de sécurité jaune le long des murs
	local inset = half - 7
	local corners = {
		origin + Vector3.new(-inset, 0.05, -inset),
		origin + Vector3.new(inset, 0.05, -inset),
		origin + Vector3.new(inset, 0.05, inset),
		origin + Vector3.new(-inset, 0.05, inset),
	}
	for i = 1, 4 do
		floorLine(parent, corners[i], corners[i % 4 + 1], 0.7, P.Hazard)
	end

	-- Murs : soubassement béton, bardage métallique en lames, piliers, bandeau
	local walls = {
		{ normal = Vector3.new(0, 0, 1), center = Vector3.new(0, 0, -half), along = Vector3.new(1, 0, 0) },
		{ normal = Vector3.new(0, 0, -1), center = Vector3.new(0, 0, half), along = Vector3.new(1, 0, 0) },
		{ normal = Vector3.new(1, 0, 0), center = Vector3.new(-half, 0, 0), along = Vector3.new(0, 0, 1) },
		{ normal = Vector3.new(-1, 0, 0), center = Vector3.new(half, 0, 0), along = Vector3.new(0, 0, 1) },
	}
	for index, wall in walls do
		local base = origin + wall.center
		local cf = CFrame.lookAt(base, base + wall.normal)
		Build.Part({ Name = "WallCore" .. index, Size = Vector3.new(size + 4, height, 2), CFrame = cf * CFrame.new(0, height / 2, 1), Color = P.ConcreteDark, Material = Enum.Material.Concrete }, parent)
		Build.Part({ Name = "WallBase", Size = Vector3.new(size, 3.5, 0.6), CFrame = cf * CFrame.new(0, 1.75, -0.2), Color = P.ConcreteDark, Material = Enum.Material.Concrete }, parent)
		local strips = math.floor(size / 5)
		for i = 0, strips - 1 do
			local x = -half + 2.5 + i * 5
			Build.Part({
				Name = "Cladding",
				Size = Vector3.new(4.6, height - 6, 0.4),
				CFrame = cf * CFrame.new(x, 3.5 + (height - 6) / 2, 0),
				Color = i % 2 == 0 and P.Panel or P.PanelAlt,
				Material = Enum.Material.Metal,
			}, parent)
		end
		for i = -3, 3 do
			Build.Part({ Name = "Column", Size = Vector3.new(2.2, height + 2, 1.6), CFrame = cf * CFrame.new(i * 24, (height + 2) / 2, -0.6), Color = P.Steel, Material = Enum.Material.Metal }, parent)
		end
		local a = base + wall.along * -half + wall.normal * 0.5 + Vector3.new(0, height - 1.2, 0)
		local b = base + wall.along * half + wall.normal * 0.5 + Vector3.new(0, height - 1.2, 0)
		hazardStripe(parent, a, b, 1.6, 0.5)
	end

	-- Charpente : poutres et lampes suspendues
	for _, z in { -45, -15, 15, 45 } do
		local i = z // 30
		Build.Part({ Name = "Truss", Size = Vector3.new(size, 1.6, 1.6), Position = origin + Vector3.new(0, height + 1, z), Color = P.Steel, Material = Enum.Material.Metal }, parent)
		Build.Part({ Name = "TrussLow", Size = Vector3.new(size, 0.6, 0.6), Position = origin + Vector3.new(0, height - 2, z), Color = P.Steel, Material = Enum.Material.Metal }, parent)
		for j = -2, 2 do
			local x = j * 30 + 15 * (i % 2)
			local top = origin + Vector3.new(x, height, z)
			Build.Part({ Name = "LampCord", Size = Vector3.new(0.15, 4, 0.15), Position = top + Vector3.new(0, -2, 0), Color = P.HazardDark }, parent)
			Build.Part({ Name = "LampShade", Size = Vector3.new(3.4, 1, 3.4), Position = top + Vector3.new(0, -4.2, 0), Color = P.Steel, Material = Enum.Material.Metal }, parent)
			local bulb = Build.Part({
				Name = "LampBulb",
				Shape = Enum.PartType.Ball,
				Size = Vector3.new(1.6, 1.6, 1.6),
				Position = top + Vector3.new(0, -4.9, 0),
				Color = P.LampWarm,
				Material = Enum.Material.Neon,
				CanCollide = false,
			}, parent)
			local light = Instance.new("PointLight")
			light.Color = P.LampWarm
			light.Range = 40
			light.Brightness = 1.6
			light.Shadows = false
			light.Parent = bulb
		end
	end
end

-- ---------------------------------------------------------------------------
-- Spawn central
-- ---------------------------------------------------------------------------
local function buildSpawn(parent: Folder, origin: Vector3)
	Build.VerticalCylinder(origin + Vector3.new(0, 0.2, 0), 11, 0.4, { Name = "SpawnRing", Color = P.Hazard, Accent = true }, parent)
	Build.VerticalCylinder(origin + Vector3.new(0, 0.3, 0), 9.6, 0.4, { Name = "SpawnPad", Color = P.ConcreteLight, Material = Enum.Material.Concrete }, parent)
	-- Anneau des trois équipes (lecture du triangle dès l'arrivée)
	for index, teamId in Teams.Order do
		local def = Teams.Get(teamId)
		assert(def)
		for k = 0, 9 do
			local a = math.rad((index - 1) * 120 + k * 11 + 5)
			local p = origin + Vector3.new(math.cos(a) * 13, 0.12, math.sin(a) * 13)
			Build.Part({
				Name = "TeamRing",
				Size = Vector3.new(2.6, 0.12, 1.6),
				CFrame = CFrame.lookAt(p, origin + Vector3.new(0, 0.12, 0)),
				Color = def.Color,
				Accent = true,
				CanCollide = false,
			}, parent)
		end
	end
	floorText(parent, origin + Vector3.new(0, 0.55, 0), 0, Vector2.new(14, 4), "HUNT OR HIDE", P.HazardDark)

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
-- Nord : écran géant et quais de vote
-- ---------------------------------------------------------------------------
local function buildBoard(parent: Folder, origin: Vector3)
	local half = Config.Lobby.Size / 2
	local _, gui = screen(parent, "GiantBoard", Vector3.new(56, 18, 1), CFrame.new(origin + Vector3.new(0, 25, -half + 2)), Enum.NormalId.Back)
	Build.TextLabel(gui, { Name = "Title", Size = UDim2.fromScale(1, 0.2), Position = UDim2.fromScale(0, 0.04), Text = "HUNT OR HIDE", TextColor3 = P.Hazard })
	boardLabels.Status = Build.TextLabel(gui, { Name = "Status", Size = UDim2.fromScale(1, 0.18), Position = UDim2.fromScale(0, 0.27), Text = "Waiting for players...", TextColor3 = P.ScreenText })
	boardLabels.Time = Build.TextLabel(gui, { Name = "Time", Size = UDim2.fromScale(1, 0.32), Position = UDim2.fromScale(0, 0.45), Text = "--:--", TextColor3 = Color3.new(1, 1, 1) })
	boardLabels.Map = Build.TextLabel(gui, { Name = "Map", Size = UDim2.fromScale(1, 0.15), Position = UDim2.fromScale(0, 0.8), Text = "", TextColor3 = Color3.fromRGB(160, 190, 230) })
end

local function buildVoteBays(parent: Folder, origin: Vector3)
	local cfg = Config.Lobby
	local half = cfg.Size / 2
	local size = cfg.VotePlateSize
	local gap = size + 10
	for index = 1, Config.Round.VoteCandidates do
		local x = (index - (Config.Round.VoteCandidates + 1) / 2) * gap
		local bayBack = origin + Vector3.new(x, 0, -half + 2.5)
		-- Encadrement de quai (poteaux + linteau) et porte roulante entrouverte
		for _, side in { -1, 1 } do
			Build.Part({ Name = "BayPost", Size = Vector3.new(1.4, 10, 1.4), Position = bayBack + Vector3.new(side * (size / 2 + 1), 5, 1), Color = P.Hazard, Accent = true }, parent)
		end
		Build.Part({ Name = "BayLintel", Size = Vector3.new(size + 3.4, 1.4, 1.4), Position = bayBack + Vector3.new(0, 10.6, 1), Color = P.Steel, Material = Enum.Material.Metal }, parent)
		for k = 0, 5 do
			Build.Part({ Name = "RollerDoor", Size = Vector3.new(size + 1, 0.9, 0.3), Position = bayBack + Vector3.new(0, 9.8 - k * 0.95, 0.5), Color = P.SteelLight, Material = Enum.Material.Metal }, parent)
		end
		local strip = Build.Part({ Name = "BayLight", Size = Vector3.new(size + 1, 0.4, 0.4), Position = bayBack + Vector3.new(0, 11.6, 1.6), Color = Color3.new(1, 1, 1), Material = Enum.Material.Neon }, parent)

		-- Plaque de vote au sol devant le quai
		local platePos = origin + Vector3.new(x, 0.25, -half + 13)
		local plate = Build.Part({
			Name = "VotePlate" .. index,
			Size = Vector3.new(size, 0.5, size),
			Position = platePos,
			Color = P.ConcreteLight,
			Accent = true,
		}, parent)
		plate:SetAttribute("VoteIndex", index)
		Build.SurfaceLabel(plate, Enum.NormalId.Top, "STAND HERE TO VOTE", { TextColor3 = P.HazardDark, TextTransparency = 0.2 })
		hazardStripe(parent, platePos + Vector3.new(-size / 2 - 0.4, 0, size / 2 + 0.4), platePos + Vector3.new(size / 2 + 0.4, 0, size / 2 + 0.4), 0.6, 0.6)

		-- Petit écran au-dessus du quai : nom, mode, votes
		local _, gui = screen(parent, "VoteScreen" .. index, Vector3.new(size + 2, 4.4, 0.6), CFrame.new(bayBack + Vector3.new(0, 13.2, 1.2)), Enum.NormalId.Back)
		local nameLabel = Build.TextLabel(gui, { Size = UDim2.fromScale(0.94, 0.42), Position = UDim2.fromScale(0.03, 0.04), Text = "?", TextColor3 = P.ScreenText })
		local modeLabel = Build.TextLabel(gui, { Size = UDim2.fromScale(0.94, 0.26), Position = UDim2.fromScale(0.03, 0.46), Text = "", TextColor3 = P.Hazard })
		local votesLabel = Build.TextLabel(gui, { Size = UDim2.fromScale(0.94, 0.24), Position = UDim2.fromScale(0.03, 0.73), Text = "", TextColor3 = Color3.fromRGB(170, 180, 195) })

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
		votePlates[index] = { Part = plate, Name = nameLabel, Mode = modeLabel, Votes = votesLabel, Strip = strip, MapId = nil }
	end
	floorText(parent, origin + Vector3.new(0, 0.06, -half + 24), 0, Vector2.new(30, 3), "▲  VOTE FOR THE NEXT MAP  ▲", P.Hazard)
end

-- ---------------------------------------------------------------------------
-- Est : boutique dans un conteneur
-- ---------------------------------------------------------------------------
local function buildShop(parent: Folder, origin: Vector3)
	local half = Config.Lobby.Size / 2
	local center = origin + Vector3.new(half - 12, 0, -4)
	local length, depth, height = 26, 12, 11
	local blue = P.ContainerBlue
	-- Conteneur ouvert côté ouest (vers le spawn)
	Build.Part({ Name = "ContainerBack", Size = Vector3.new(0.6, height, length), Position = center + Vector3.new(depth / 2, height / 2, 0), Color = blue, Material = Enum.Material.Metal }, parent)
	Build.Part({ Name = "ContainerRoof", Size = Vector3.new(depth + 0.6, 0.6, length + 0.6), Position = center + Vector3.new(0, height, 0), Color = blue, Material = Enum.Material.Metal }, parent)
	for _, side in { -1, 1 } do
		Build.Part({ Name = "ContainerEnd", Size = Vector3.new(depth, height, 0.6), Position = center + Vector3.new(0, height / 2, side * length / 2), Color = blue, Material = Enum.Material.Metal }, parent)
		-- Porte battante ouverte
		Build.Part({ Name = "ContainerDoor", Size = Vector3.new(0.4, height - 0.6, length / 4), CFrame = CFrame.new(center + Vector3.new(-depth / 2 - length / 8, height / 2, side * (length / 2 + 0.3))) * CFrame.Angles(0, math.rad(side * 80), 0), Color = blue, Material = Enum.Material.Metal }, parent)
	end
	for i = 0, 12 do
		Build.Part({ Name = "ContainerRib", Size = Vector3.new(0.3, height - 1, 0.5), Position = center + Vector3.new(depth / 2 - 0.4, height / 2, -length / 2 + 1 + i * 2), Color = Style.Palette.Steel, Material = Enum.Material.Metal }, parent)
	end
	-- Comptoir avec invite d'interaction
	local counter = Build.Part({ Name = "ShopCounter", Size = Vector3.new(3, 3.6, length - 6), Position = center + Vector3.new(-depth / 2 + 3, 1.8, 0), Color = P.Wood, Material = Enum.Material.WoodPlanks }, parent)
	Build.Part({ Name = "ShopCounterTop", Size = Vector3.new(3.6, 0.4, length - 5), Position = center + Vector3.new(-depth / 2 + 3, 3.8, 0), Color = P.Steel, Material = Enum.Material.Metal }, parent)
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "ShopPrompt"
	prompt.ActionText = "Open Shop"
	prompt.ObjectText = "Shop"
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.GamepadKeyCode = Enum.KeyCode.ButtonY
	prompt.MaxActivationDistance = 12
	prompt.RequiresLineOfSight = false
	prompt.Parent = counter
	prompt.Triggered:Connect(function(player)
		if shopCallback then
			shopCallback(player)
		end
	end)
	-- Étagères de produits (couleurs de gameplay)
	for i = 0, 4 do
		Build.Part({ Name = "Shelf", Size = Vector3.new(1.5, 0.3, length - 6), Position = center + Vector3.new(depth / 2 - 1.5, 2 + i * 1.8, 0), Color = P.Steel, Material = Enum.Material.Metal }, parent)
		for j = 0, 5 do
			Build.Part({ Name = "Goods", Size = Vector3.new(1, 1, 1.4), Position = center + Vector3.new(depth / 2 - 1.5, 2.8 + i * 1.8, -8 + j * 3.2), Color = ({ P.Hazard, Teams.Defs.FOX.Color, Teams.Defs.CHICKEN.Color, Teams.Defs.SNAKE.Color })[(i + j) % 4 + 1], Accent = true }, parent)
		end
	end
	-- Enseigne lumineuse
	local _, gui = screen(parent, "ShopSign", Vector3.new(0.6, 4, 16), CFrame.new(center + Vector3.new(-depth / 2 - 0.3, height + 2.6, 0)), Enum.NormalId.Left)
	Build.TextLabel(gui, { Size = UDim2.fromScale(0.9, 0.8), Position = UDim2.fromScale(0.05, 0.1), Text = "SHOP", TextColor3 = P.Hazard })
	floorText(parent, center + Vector3.new(-depth / 2 - 6, 0.06, 0), math.rad(90), Vector2.new(16, 3), "PRESS E AT THE COUNTER", P.Hazard)
end

-- ---------------------------------------------------------------------------
-- Ouest : classements
-- ---------------------------------------------------------------------------
local function buildLeaderboards(parent: Folder, origin: Vector3)
	local half = Config.Lobby.Size / 2
	local boards = { { Key = "Wins", Title = "TOP WINS", Z = -16 }, { Key = "Captures", Title = "TOP CATCHES", Z = 16 } }
	for _, info in boards do
		local _, gui = screen(parent, "Leaderboard" .. info.Key, Vector3.new(1, 22, 22), CFrame.new(origin + Vector3.new(-half + 2.5, 13, info.Z)), Enum.NormalId.Right)
		Build.TextLabel(gui, { Name = "Title", Size = UDim2.fromScale(1, 0.12), Position = UDim2.fromScale(0, 0.02), Text = info.Title, TextColor3 = P.Hazard })
		leaderboardLabels[info.Key] = Build.TextLabel(gui, {
			Name = "Entries",
			Size = UDim2.fromScale(0.88, 0.82),
			Position = UDim2.fromScale(0.06, 0.16),
			Text = "Loading...",
			TextColor3 = P.ScreenText,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextYAlignment = Enum.TextYAlignment.Top,
		})
	end
end

-- Piste d'entraînement au dash (plots en slalom)
local function buildPracticeLane(parent: Folder, origin: Vector3)
	local half = Config.Lobby.Size / 2
	for i = 0, 6 do
		local z = -36 + i * 12
		local x = -half + 26 + (i % 2) * 7
		Build.VerticalCylinder(origin + Vector3.new(x, 1.5, z), 0.8, 3, { Name = "Bollard", Color = P.Hazard, Accent = true }, parent)
		Build.VerticalCylinder(origin + Vector3.new(x, 2.4, z), 0.85, 0.5, { Name = "BollardBand", Color = P.HazardDark, Accent = true }, parent)
	end
	floorText(parent, origin + Vector3.new(-half + 29, 0.06, 48), 0, Vector2.new(16, 3), "DASH PRACTICE  (Q / E)", P.Hazard)
end

-- ---------------------------------------------------------------------------
-- Sud : écran des règles et tapis roulant
-- ---------------------------------------------------------------------------
local function buildRules(parent: Folder, origin: Vector3)
	local half = Config.Lobby.Size / 2
	local _, gui = screen(parent, "RulesBoard", Vector3.new(40, 20, 1), CFrame.new(origin + Vector3.new(0, 16, half - 2)), Enum.NormalId.Front)
	Build.TextLabel(gui, { Name = "Title", Size = UDim2.fromScale(1, 0.13), Position = UDim2.fromScale(0, 0.03), Text = "WHO CATCHES WHO?", TextColor3 = P.Hazard })

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
		corner.CornerRadius = UDim.new(0.2, 0)
		corner.Parent = frame
		Build.TextLabel(frame, { Size = UDim2.fromScale(0.9, 0.76), Position = UDim2.fromScale(0.05, 0.12), Text = def.Display, TextColor3 = Color3.fromRGB(20, 20, 26) })
	end
	local function arrow(position: UDim2, rotation: number)
		Build.TextLabel(gui, { AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromScale(0.12, 0.12), Position = position, Text = "➜", Rotation = rotation, TextColor3 = P.ScreenText })
	end
	animal("FOX", UDim2.fromScale(0.5, 0.3))
	animal("CHICKEN", UDim2.fromScale(0.78, 0.68))
	animal("SNAKE", UDim2.fromScale(0.22, 0.68))
	arrow(UDim2.fromScale(0.68, 0.47), 55)
	arrow(UDim2.fromScale(0.5, 0.72), 180)
	arrow(UDim2.fromScale(0.32, 0.47), -55)
	Build.TextLabel(gui, { Name = "Rule", Size = UDim2.fromScale(1, 0.1), Position = UDim2.fromScale(0, 0.87), Text = Teams.Rule, TextColor3 = P.ScreenText })
end

local function buildConveyor(parent: Folder, origin: Vector3)
	local half = Config.Lobby.Size / 2
	local length, width = 90, 7
	local center = origin + Vector3.new(0, 0, half - 12)
	local speed = 14
	local belt = Build.Part({
		Name = "ConveyorBelt",
		Size = Vector3.new(length, 1, width),
		Position = center + Vector3.new(0, 0.5, 0),
		Color = Color3.fromRGB(40, 42, 48),
		Material = Enum.Material.Rubber,
	}, parent)
	-- Vitesse d'entraînement : un objet posé dessus est emporté (effet tapis roulant)
	belt.AssemblyLinearVelocity = Vector3.new(speed, 0, 0)
	for i = 0, 14 do
		Build.Part({
			Name = "Chevron",
			Size = Vector3.new(0.6, 0.05, width - 1.5),
			CFrame = CFrame.new(center + Vector3.new(-length / 2 + 3 + i * 6, 1.03, 0)),
			Color = P.Hazard,
			Accent = true,
			CanCollide = false,
			CanQuery = false,
		}, parent)
	end
	for _, side in { -1, 1 } do
		Build.Part({ Name = "ConveyorRail", Size = Vector3.new(length, 1.6, 0.6), Position = center + Vector3.new(0, 0.8, side * (width / 2 + 0.3)), Color = P.Steel, Material = Enum.Material.Metal }, parent)
		Build.Part({ Name = "ConveyorRoller", Shape = Enum.PartType.Cylinder, Size = Vector3.new(width + 1, 1.8, 1.8), CFrame = CFrame.new(center + Vector3.new(side * (length / 2 + 0.9), 0.9, 0)) * CFrame.Angles(0, math.rad(90), 0), Color = P.Hazard, Accent = true }, parent)
	end
end

local function buildProps(parent: Folder, origin: Vector3)
	local half = Config.Lobby.Size / 2
	-- Piles de caisses et fûts dans les coins
	local spots = {
		{ Vector3.new(-half + 10, 0, -half + 10), 0.2 },
		{ Vector3.new(half - 10, 0, half - 10), 0.6 },
		{ Vector3.new(-half + 10, 0, half - 22), 0.4 },
		{ Vector3.new(half - 14, 0, -half + 10), 0.1 },
	}
	for i, spot in spots do
		local p = origin + spot[1]
		crate(parent, p, 5, spot[2], i % 2 == 0)
		crate(parent, p + Vector3.new(5.5, 0, 0.5), 5, spot[2] + 0.3, i % 2 == 1)
		crate(parent, p + Vector3.new(2.5, 5, 0.2), 4.5, spot[2] - 0.2)
		barrel(parent, p + Vector3.new(-3, 0, 6), P.Rust)
		barrel(parent, p + Vector3.new(0.5, 0, 7), P.ContainerOrange)
	end
	-- Palettes près des quais
	for _, x in { -40, 40 } do
		Build.Part({ Name = "Pallet", Size = Vector3.new(6, 0.8, 6), Position = origin + Vector3.new(x, 0.4, -half + 18), Color = P.Wood, Material = Enum.Material.WoodPlanks }, parent)
		crate(parent, origin + Vector3.new(x, 0.8, -half + 18), 4, 0.1, true)
	end
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

	buildShell(newFolder, origin)
	buildSpawn(newFolder, origin)
	buildBoard(newFolder, origin)
	buildVoteBays(newFolder, origin)
	buildShop(newFolder, origin)
	buildLeaderboards(newFolder, origin)
	buildPracticeLane(newFolder, origin)
	buildRules(newFolder, origin)
	buildConveyor(newFolder, origin)
	buildProps(newFolder, origin)

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

-- Appelé quand un joueur interagit avec le comptoir de la boutique
function LobbyBuilder.OnShopOpened(callback: (Player) -> ())
	shopCallback = callback
end

-- Affecte les maps candidates aux quais (liste de mapId, nil = quai vide).
function LobbyBuilder.SetVoteCandidates(candidates: { string })
	for index, plate in votePlates do
		local mapId = candidates[index]
		local def = MapInfo.Get(mapId)
		plate.MapId = mapId
		if def then
			plate.Part.Color = def.Color
			plate.Strip.Color = def.Color
			plate.Name.Text = def.DisplayName
			plate.Mode.Text = def.ModeName
			plate.Votes.Text = "0 votes"
		else
			plate.Part.Color = P.ConcreteLight
			plate.Strip.Color = Color3.new(1, 1, 1)
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

-- Met à jour un classement : entries = { {Name, Value}, ... }
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
		table.insert(lines, string.format("%d. %s  -  %s", rank, tostring(entry[1]), tostring(entry[2])))
	end
	label.Text = table.concat(lines, "\n")
end

return LobbyBuilder

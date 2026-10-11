--[[
	LobbyBuilder.lua
	Construit le lobby entièrement par le code : sol, murs, spawn central,
	panneau géant (chrono + map), trois plaques de vote, boutique (emplacement),
	classements (emplacements), panneau du triangle FOX > CHICKEN > SNAKE > FOX.

	Disposition (vue du dessus, Nord = -Z) :
	        [ PANNEAU GÉANT ]            Nord
	        [ 3 plaques de vote ]
	 [Classements]   (spawn)   [Boutique]   Ouest / Est
	        [ Panneau des règles ]       Sud
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Teams = require(Shared.Teams)
local MapInfo = require(Shared.MapInfo)
local Build = require(script.Parent.Parent.Util.Build)

local LobbyBuilder = {}

local folder: Folder? = nil
local spawnCFrame = CFrame.new(Config.World.LobbyOrigin + Vector3.new(0, 3, 0))

local boardLabels: { Title: TextLabel?, Time: TextLabel?, Map: TextLabel? } = {}
local votePlates: { { Part: Part, Name: TextLabel, Mode: TextLabel, Votes: TextLabel, MapId: string? } } = {}
local plateCallback: ((Player, number) -> ())? = nil
local lastTouch: { [Player]: number } = {}

local WHITE = Color3.new(1, 1, 1)

-- ---------------------------------------------------------------------------
-- Éléments
-- ---------------------------------------------------------------------------

local function buildFloorAndWalls(parent: Folder, origin: Vector3)
	local cfg = Config.Lobby
	local half = cfg.Size / 2

	Build.Part({
		Name = "Floor",
		Size = Vector3.new(cfg.Size, 2, cfg.Size),
		Position = origin + Vector3.new(0, -1, 0),
		Color = cfg.FloorColor,
		Material = Enum.Material.Grass,
	}, parent)

	-- Allées en croix vers les quatre côtés
	for _, axis in { Vector3.new(1, 0, 0), Vector3.new(0, 0, 1) } do
		Build.Part({
			Name = "Path",
			Size = Vector3.new(cfg.Size * math.abs(axis.X) + 10 * math.abs(axis.Z), 0.2, cfg.Size * math.abs(axis.Z) + 10 * math.abs(axis.X)),
			Position = origin + Vector3.new(0, 0.1, 0),
			Color = cfg.PathColor,
			Material = Enum.Material.Cobblestone,
		}, parent)
	end

	-- Quatre murs + corniche colorée
	local walls = {
		{ Vector3.new(0, 0, -half), Vector3.new(cfg.Size + cfg.WallThickness, cfg.WallHeight, cfg.WallThickness) },
		{ Vector3.new(0, 0, half), Vector3.new(cfg.Size + cfg.WallThickness, cfg.WallHeight, cfg.WallThickness) },
		{ Vector3.new(-half, 0, 0), Vector3.new(cfg.WallThickness, cfg.WallHeight, cfg.Size + cfg.WallThickness) },
		{ Vector3.new(half, 0, 0), Vector3.new(cfg.WallThickness, cfg.WallHeight, cfg.Size + cfg.WallThickness) },
	}
	for index, wall in walls do
		local offset, size = wall[1], wall[2]
		Build.Part({
			Name = "Wall" .. index,
			Size = size,
			Position = origin + offset + Vector3.new(0, cfg.WallHeight / 2, 0),
			Color = cfg.WallColor,
			Material = Enum.Material.Brick,
		}, parent)
		Build.Part({
			Name = "WallTrim" .. index,
			Size = Vector3.new(size.X + 1, 1.5, size.Z + 1),
			Position = origin + offset + Vector3.new(0, cfg.WallHeight + 0.75, 0),
			Color = cfg.WallTrimColor,
		}, parent)
	end

	-- Lampadaires aux quatre coins
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			local base = origin + Vector3.new(sx * (half - 10), 0, sz * (half - 10))
			Build.VerticalCylinder(base + Vector3.new(0, 6, 0), 0.5, 12, { Name = "LampPost", Color = Color3.fromRGB(60, 60, 70) }, parent)
			local lamp = Build.Part({
				Name = "Lamp",
				Shape = Enum.PartType.Ball,
				Size = Vector3.new(3, 3, 3),
				Position = base + Vector3.new(0, 13, 0),
				Color = cfg.AccentColor,
				Material = Enum.Material.Neon,
			}, parent)
			local light = Instance.new("PointLight")
			light.Range = 30
			light.Brightness = 1.5
			light.Color = cfg.AccentColor
			light.Parent = lamp
		end
	end

	-- Quelques arbres décoratifs (tronc + feuillage)
	local treeSpots = {
		Vector3.new(-half + 22, 0, -half + 30),
		Vector3.new(half - 22, 0, -half + 30),
		Vector3.new(-half + 22, 0, half - 30),
		Vector3.new(half - 22, 0, half - 30),
	}
	for _, spot in treeSpots do
		Build.VerticalCylinder(origin + spot + Vector3.new(0, 4, 0), 1.2, 8, { Name = "Trunk", Color = Color3.fromRGB(110, 75, 45), Material = Enum.Material.Wood }, parent)
		Build.Part({
			Name = "Leaves",
			Shape = Enum.PartType.Ball,
			Size = Vector3.new(12, 12, 12),
			Position = origin + spot + Vector3.new(0, 12, 0),
			Color = Color3.fromRGB(70, 150, 70),
			Material = Enum.Material.Grass,
		}, parent)
	end
end

local function buildSpawn(parent: Folder, origin: Vector3)
	local cfg = Config.Lobby
	Build.VerticalCylinder(origin + Vector3.new(0, 0.3, 0), 9, 0.6, { Name = "SpawnPad", Color = cfg.AccentColor }, parent)
	Build.VerticalCylinder(origin + Vector3.new(0, 0.5, 0), 6, 0.4, { Name = "SpawnPadInner", Color = cfg.PanelColor }, parent)

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

local function buildGiantBoard(parent: Folder, origin: Vector3)
	local cfg = Config.Lobby
	local half = cfg.Size / 2
	local board = Build.Part({
		Name = "GiantBoard",
		Size = Vector3.new(50, 18, 2),
		Position = origin + Vector3.new(0, 15, -half + cfg.WallThickness + 1),
		Color = cfg.PanelColor,
	}, parent)
	-- Cadre
	Build.Part({
		Name = "GiantBoardFrame",
		Size = Vector3.new(52, 20, 1.5),
		Position = board.Position + Vector3.new(0, 0, -0.5),
		Color = cfg.AccentColor,
	}, parent)

	-- Le panneau est sur le mur nord (-Z) : la face visible depuis le centre est Back (+Z)
	local gui = Build.SurfaceGui(board, Enum.NormalId.Back)
	Build.TextLabel(gui, {
		Name = "GameTitle",
		Size = UDim2.fromScale(1, 0.25),
		Position = UDim2.fromScale(0, 0.02),
		Text = "HUNT OR HIDE",
		TextColor3 = cfg.AccentColor,
	})
	boardLabels.Title = Build.TextLabel(gui, {
		Name = "Status",
		Size = UDim2.fromScale(1, 0.22),
		Position = UDim2.fromScale(0, 0.28),
		Text = "Waiting for players...",
	})
	boardLabels.Time = Build.TextLabel(gui, {
		Name = "Time",
		Size = UDim2.fromScale(1, 0.3),
		Position = UDim2.fromScale(0, 0.48),
		Text = "--:--",
	})
	boardLabels.Map = Build.TextLabel(gui, {
		Name = "Map",
		Size = UDim2.fromScale(1, 0.18),
		Position = UDim2.fromScale(0, 0.8),
		Text = "",
		TextColor3 = Color3.fromRGB(200, 220, 255),
	})
end

local function buildVotePlates(parent: Folder, origin: Vector3)
	local cfg = Config.Lobby
	local half = cfg.Size / 2
	local size = cfg.VotePlateSize
	local gap = size + 6
	for index = 1, Config.Round.VoteCandidates do
		local x = (index - (Config.Round.VoteCandidates + 1) / 2) * gap
		local position = origin + Vector3.new(x, 0.5, -half + 24)
		local plate = Build.Part({
			Name = "VotePlate" .. index,
			Size = Vector3.new(size, 1, size),
			Position = position,
			Color = Color3.fromRGB(200, 200, 200),
		}, parent)
		plate:SetAttribute("VoteIndex", index)
		Build.SurfaceLabel(plate, Enum.NormalId.Top, "VOTE", { TextTransparency = 0.3 })

		-- Panneau vertical derrière la plaque (côté nord), lisible depuis le centre :
		-- nom de la map, mode, nombre de votes.
		local sign = Build.Part({
			Name = "VoteSign" .. index,
			Size = Vector3.new(size, 7, 0.5),
			Position = position + Vector3.new(0, 4, -size / 2 - 0.5),
			Color = cfg.PanelColor,
		}, parent)
		local gui = Build.SurfaceGui(sign, Enum.NormalId.Back)
		local nameLabel = Build.TextLabel(gui, {
			Size = UDim2.fromScale(0.94, 0.38),
			Position = UDim2.fromScale(0.03, 0.04),
			Text = "?",
		})
		local modeLabel = Build.TextLabel(gui, {
			Size = UDim2.fromScale(0.94, 0.24),
			Position = UDim2.fromScale(0.03, 0.44),
			Text = "",
			TextColor3 = cfg.AccentColor,
		})
		local votesLabel = Build.TextLabel(gui, {
			Size = UDim2.fromScale(0.94, 0.24),
			Position = UDim2.fromScale(0.03, 0.72),
			Text = "",
		})

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

		votePlates[index] = { Part = plate, Name = nameLabel, Mode = modeLabel, Votes = votesLabel, MapId = nil }
	end
end

local function buildShop(parent: Folder, origin: Vector3)
	local cfg = Config.Lobby
	local half = cfg.Size / 2
	local center = origin + Vector3.new(half - 14, 0, 0)
	Build.Part({
		Name = "ShopCounter",
		Size = Vector3.new(4, 4, 24),
		Position = center + Vector3.new(0, 2, 0),
		Color = Color3.fromRGB(150, 100, 60),
		Material = Enum.Material.Wood,
	}, parent)
	Build.Part({
		Name = "ShopRoof",
		Size = Vector3.new(10, 1, 28),
		Position = center + Vector3.new(2, 10, 0),
		Color = cfg.WallTrimColor,
	}, parent)
	for _, z in { -13, 13 } do
		Build.VerticalCylinder(center + Vector3.new(6, 5, z), 0.5, 10, { Name = "ShopPole", Color = WHITE }, parent)
	end
	local sign = Build.Part({
		Name = "ShopSign",
		Size = Vector3.new(1, 5, 20),
		Position = center + Vector3.new(6, 13.5, 0),
		Color = cfg.PanelColor,
	}, parent)
	Build.SurfaceLabel(sign, Enum.NormalId.Left, "SHOP", { TextColor3 = cfg.AccentColor })
	local info = Build.Part({
		Name = "ShopInfo",
		Size = Vector3.new(1, 3, 20),
		Position = center + Vector3.new(6, 7.5, 0),
		Color = cfg.PanelColor,
	}, parent)
	Build.SurfaceLabel(info, Enum.NormalId.Left, "Abilities - Consumables - Looks\nOpening soon!")
end

local function buildLeaderboards(parent: Folder, origin: Vector3)
	local cfg = Config.Lobby
	local half = cfg.Size / 2
	local titles = { "TOP WINS", "TOP CATCHES" }
	for index, title in titles do
		local z = (index - 1.5) * 26
		local board = Build.Part({
			Name = "Leaderboard" .. index,
			Size = Vector3.new(1, 16, 20),
			Position = origin + Vector3.new(-half + cfg.WallThickness + 1, 10, z),
			Color = cfg.PanelColor,
		}, parent)
		board:SetAttribute("LeaderboardKind", title)
		local gui = Build.SurfaceGui(board, Enum.NormalId.Right)
		Build.TextLabel(gui, {
			Name = "Title",
			Size = UDim2.fromScale(1, 0.18),
			Text = title,
			TextColor3 = cfg.AccentColor,
		})
		Build.TextLabel(gui, {
			Name = "Entries",
			Size = UDim2.fromScale(0.9, 0.75),
			Position = UDim2.fromScale(0.05, 0.22),
			Text = "Coming soon",
			TextXAlignment = Enum.TextXAlignment.Left,
			TextYAlignment = Enum.TextYAlignment.Top,
		})
	end
end

-- Panneau des règles : triangle FOX > CHICKEN > SNAKE > FOX
local function buildRulesPanel(parent: Folder, origin: Vector3)
	local cfg = Config.Lobby
	local half = cfg.Size / 2
	local board = Build.Part({
		Name = "RulesBoard",
		Size = Vector3.new(36, 20, 2),
		Position = origin + Vector3.new(0, 14, half - cfg.WallThickness - 1),
		Color = cfg.PanelColor,
	}, parent)
	Build.Part({
		Name = "RulesBoardFrame",
		Size = Vector3.new(38, 22, 1.5),
		Position = board.Position + Vector3.new(0, 0, 0.5),
		Color = cfg.AccentColor,
	}, parent)

	-- Le panneau est sur le mur sud (+Z) : la face visible depuis le centre est Front (-Z)
	local gui = Build.SurfaceGui(board, Enum.NormalId.Front)
	Build.TextLabel(gui, {
		Name = "Title",
		Size = UDim2.fromScale(1, 0.14),
		Text = "WHO CATCHES WHO?",
		TextColor3 = cfg.AccentColor,
	})

	local function animal(teamId: string, position: UDim2)
		local def = Teams.Get(teamId)
		assert(def)
		local frame = Instance.new("Frame")
		frame.AnchorPoint = Vector2.new(0.5, 0.5)
		frame.Size = UDim2.fromScale(0.3, 0.14)
		frame.Position = position
		frame.BackgroundColor3 = def.Color
		frame.Parent = gui
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0.3, 0)
		corner.Parent = frame
		Build.TextLabel(frame, {
			Size = UDim2.fromScale(0.9, 0.8),
			Position = UDim2.fromScale(0.05, 0.1),
			Text = def.Display,
			TextColor3 = Color3.fromRGB(25, 25, 35),
		})
	end

	local function arrow(position: UDim2, rotation: number)
		Build.TextLabel(gui, {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Size = UDim2.fromScale(0.12, 0.12),
			Position = position,
			Text = "➜",
			Rotation = rotation,
		})
	end

	-- Triangle : FOX en haut, CHICKEN en bas à droite, SNAKE en bas à gauche
	animal("FOX", UDim2.fromScale(0.5, 0.3))
	animal("CHICKEN", UDim2.fromScale(0.78, 0.68))
	animal("SNAKE", UDim2.fromScale(0.22, 0.68))
	arrow(UDim2.fromScale(0.68, 0.47), 55) -- FOX -> CHICKEN
	arrow(UDim2.fromScale(0.5, 0.72), 180) -- CHICKEN -> SNAKE
	arrow(UDim2.fromScale(0.32, 0.47), -55) -- SNAKE -> FOX

	Build.TextLabel(gui, {
		Name = "Rule",
		Size = UDim2.fromScale(1, 0.12),
		Position = UDim2.fromScale(0, 0.86),
		Text = Teams.Rule,
	})
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

	buildFloorAndWalls(newFolder, origin)
	buildSpawn(newFolder, origin)
	buildGiantBoard(newFolder, origin)
	buildVotePlates(newFolder, origin)
	buildShop(newFolder, origin)
	buildLeaderboards(newFolder, origin)
	buildRulesPanel(newFolder, origin)

	newFolder.Parent = workspace
	folder = newFolder

	Players.PlayerRemoving:Connect(function(player)
		lastTouch[player] = nil
	end)
end

function LobbyBuilder.GetSpawnCFrame(): CFrame
	-- Légère dispersion pour éviter d'empiler les joueurs
	local angle = math.random() * math.pi * 2
	local radius = math.random() * 4
	return spawnCFrame + Vector3.new(math.cos(angle) * radius, 0, math.sin(angle) * radius)
end

function LobbyBuilder.SetBoard(statusText: string, timeText: string, mapText: string)
	if boardLabels.Title then
		boardLabels.Title.Text = statusText
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

-- Affecte les maps candidates aux plaques (liste de mapId, nil = plaque vide).
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
			plate.Part.Color = Color3.fromRGB(200, 200, 200)
			plate.Name.Text = "-"
			plate.Mode.Text = ""
			plate.Votes.Text = ""
		end
	end
end

function LobbyBuilder.SetVoteCounts(counts: { [string]: number })
	for _, plate in votePlates do
		if plate.MapId then
			local n = counts[plate.MapId] or 0
			plate.Votes.Text = string.format("%d vote%s", n, n == 1 and "" or "s")
		end
	end
end

function LobbyBuilder.GetVotePlateMapId(index: number): string?
	local plate = votePlates[index]
	return plate and plate.MapId or nil
end

return LobbyBuilder

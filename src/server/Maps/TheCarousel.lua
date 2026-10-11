--[[
	TheCarousel.lua - mode "King of the Wheel"
	  - Une grande plateforme tourne au centre. Chaque seconde, l'équipe qui a
	    le plus de membres dessus gagne 1 point. Première à 100 gagne.
	  - Mécanisme : la plateforme accélère par paliers, puis éjecte tout le monde
	    et repart lentement.
	Thème : fête foraine (chapiteaux, ballons, stands).
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

type Actor = Types.Actor
type MapContext = Types.MapContext

local Map = {}
Map.Id = "TheCarousel"
Map.Lighting = {
	ClockTime = 16.5,
	Brightness = 2.2,
	OutdoorAmbient = Color3.fromRGB(170, 150, 170),
}

local cfg = Config.Maps.TheCarousel
local STRIPES = {
	Color3.fromRGB(235, 70, 90), Color3.fromRGB(250, 245, 235), Color3.fromRGB(90, 160, 235),
	Color3.fromRGB(250, 245, 235), Color3.fromRGB(250, 200, 60), Color3.fromRGB(250, 245, 235),
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
local function buildTent(parent: Instance, position: Vector3, radius: number, color: Color3)
	Build.VerticalCylinder(position + Vector3.new(0, 5, 0), radius, 10, { Name = "TentWall", Color = Color3.fromRGB(250, 245, 235), Material = Enum.Material.Fabric }, parent)
	for i = 0, 7 do
		local a = i / 8 * math.pi * 2
		local p = position + Vector3.new(math.cos(a) * radius * 0.5, 13, math.sin(a) * radius * 0.5)
		Build.Part({
			Name = "TentRoof",
			Size = Vector3.new(radius * 0.85, 0.6, radius * 1.15),
			CFrame = CFrame.lookAt(p, position + Vector3.new(0, 13, 0)) * CFrame.Angles(math.rad(-28), 0, 0),
			Color = i % 2 == 0 and color or Color3.fromRGB(250, 245, 235),
			Material = Enum.Material.Fabric,
		}, parent)
	end
	Build.Part({ Name = "TentFlag", Size = Vector3.new(0.3, 4, 0.3), Position = position + Vector3.new(0, 19, 0), Color = Color3.fromRGB(80, 60, 50) }, parent)
	Build.Part({ Name = "TentFlagCloth", Size = Vector3.new(0.1, 1.5, 2.5), Position = position + Vector3.new(0, 20.2, 1.2), Color = color }, parent)
end

local function buildBalloons(parent: Instance, position: Vector3)
	for i = 1, 5 do
		local a = i * 1.3
		local p = position + Vector3.new(math.cos(a) * 1.5, 9 + i * 0.6, math.sin(a) * 1.5)
		Build.Part({
			Name = "Balloon",
			Shape = Enum.PartType.Ball,
			Size = Vector3.new(2.2, 2.2, 2.2),
			Position = p,
			Color = STRIPES[(i % #STRIPES) + 1],
			Material = Enum.Material.SmoothPlastic,
			CanCollide = false,
		}, parent)
		Build.Part({ Name = "String", Size = Vector3.new(0.08, 8, 0.08), Position = (p + position) / 2, Color = Color3.new(1, 1, 1), CanCollide = false }, parent)
	end
	Build.Part({ Name = "Stand", Size = Vector3.new(4, 3, 3), Position = position + Vector3.new(0, 1.5, 0), Color = Color3.fromRGB(235, 70, 90), Material = Enum.Material.WoodPlanks }, parent)
end

local function buildWheel(parent: Instance): Model
	local spinner = MapBase.NewSpinner(parent, "Carousel", CFrame.new(origin))
	spinner:SetAttribute("SpinCollide", true)
	local radius = cfg.PlatformRadius
	local top = cfg.PlatformHeight
	-- Socle fixe (bordure)
	Build.VerticalCylinder(origin + Vector3.new(0, top / 2 - 0.3, 0), radius + 2, top - 0.6, {
		Name = "WheelSkirt",
		Color = Color3.fromRGB(120, 70, 140),
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
	for i = 0, 11 do
		local a = i / 12 * math.pi * 2
		local p = origin + Vector3.new(math.cos(a) * radius * 0.5, top + 17.5, -math.sin(a) * radius * 0.5)
		Build.Part({
			Name = "Canopy",
			Size = Vector3.new(radius * 1.05, 0.5, radius * 0.3),
			CFrame = CFrame.lookAt(p, origin + Vector3.new(0, top + 17.5, 0)) * CFrame.Angles(math.rad(-15), math.rad(90), 0),
			Color = STRIPES[(i % #STRIPES) + 1],
			Material = Enum.Material.Fabric,
			CanCollide = false,
			CanQuery = false,
		}, spinner)
	end
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
	MapBase.BuildGround(f, origin, cfg.GroundSize, Color3.fromRGB(125, 185, 95), Enum.Material.Grass)
	MapBase.BuildBoundary(f, origin, cfg.GroundSize, 80)
	MapBase.BuildPerimeterFence(f, origin, cfg.GroundSize, Color3.fromRGB(240, 240, 240))
	bases = MapBase.BuildBases(f, origin, cfg.BaseRadius, cfg.BasePadSize)
	-- Allées de terre vers la roue
	for _, teamId in Teams.Order do
		local basePos = MapBase.BasePosition(origin, teamId, cfg.BaseRadius)
		local mid = (basePos + origin) / 2
		Build.Part({
			Name = "Path",
			Size = Vector3.new(10, 0.1, (basePos - origin).Magnitude - cfg.PlatformRadius),
			CFrame = CFrame.lookAt(mid + Vector3.new(0, 0.05, 0), origin + Vector3.new(0, 0.05, 0)),
			Color = Color3.fromRGB(215, 190, 140),
			Material = Enum.Material.Sand,
			CanCollide = false,
		}, f)
	end
	wheel = buildWheel(f)

	local half = cfg.GroundSize / 2
	buildTent(f, origin + Vector3.new(-half + 32, 0, half - 32), 12, Color3.fromRGB(235, 70, 90))
	buildTent(f, origin + Vector3.new(half - 32, 0, half - 32), 10, Color3.fromRGB(90, 160, 235))
	buildTent(f, origin + Vector3.new(half - 30, 0, -half + 30), 11, Color3.fromRGB(250, 200, 60))
	buildTent(f, origin + Vector3.new(-half + 30, 0, -half + 30), 9, Color3.fromRGB(150, 90, 220))
	for _, deg in { 0, 120, 240 } do
		local a = math.rad(deg)
		buildBalloons(f, origin + Vector3.new(math.cos(a), 0, math.sin(a)) * 62)
	end

	-- Cachettes
	for _, deg in { 30, 150, 270 } do
		local a = math.rad(deg)
		MapBase.BuildTallGrass(f, origin + Vector3.new(math.cos(a), 0, math.sin(a)) * 88, 7)
	end
	for _, deg in { 60, 180, 300 } do
		local a = math.rad(deg)
		MapBase.BuildBush(f, origin + Vector3.new(math.cos(a), 0, math.sin(a)) * 55, 9, Color3.fromRGB(70, 140, 75))
		MapBase.BuildBurrow(f, origin + Vector3.new(math.cos(a + 0.35), 0, math.sin(a + 0.35)) * 100)
	end
	-- Caisses et tonneaux pour feinter
	for i = 0, 8 do
		local a = math.rad(i * 40 + 10)
		local p = origin + Vector3.new(math.cos(a), 0, math.sin(a)) * 75
		if i % 2 == 0 then
			Build.Part({ Name = "Crate", Size = Vector3.new(5, 5, 5), CFrame = CFrame.new(p + Vector3.new(0, 2.5, 0)) * CFrame.Angles(0, a, 0), Color = Color3.fromRGB(175, 125, 75), Material = Enum.Material.WoodPlanks }, f)
		else
			Build.VerticalCylinder(p + Vector3.new(0, 2.5, 0), 2, 5, { Name = "Barrel", Color = Color3.fromRGB(140, 90, 55), Material = Enum.Material.Wood }, f)
		end
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

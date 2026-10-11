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
local pickupAllowedAt = 0
local eggTick = 0

-- ---------------------------------------------------------------------------
-- Construction
-- ---------------------------------------------------------------------------
local function buildBarn(parent: Instance, position: Vector3, yaw: number)
	local cf = CFrame.new(position) * CFrame.Angles(0, yaw, 0)
	local red = Color3.fromRGB(190, 55, 45)
	Build.Part({ Name = "Barn", Size = Vector3.new(30, 16, 24), CFrame = cf * CFrame.new(0, 8, 0), Color = red, Material = Enum.Material.WoodPlanks }, parent)
	for _, side in { -1, 1 } do
		Build.Part({
			Name = "BarnRoof",
			Size = Vector3.new(31, 1.2, 15),
			CFrame = cf * CFrame.new(0, 20, side * 6) * CFrame.Angles(math.rad(side * 35), 0, 0),
			Color = Color3.fromRGB(90, 60, 50),
			Material = Enum.Material.WoodPlanks,
		}, parent)
	end
	Build.Part({ Name = "BarnGable", Size = Vector3.new(30.2, 7, 12), CFrame = cf * CFrame.new(0, 18.5, 0), Color = red, Material = Enum.Material.WoodPlanks }, parent)
	Build.Part({ Name = "BarnDoor", Size = Vector3.new(10, 11, 0.4), CFrame = cf * CFrame.new(0, 5.5, -12.1), Color = Color3.fromRGB(240, 235, 225), Material = Enum.Material.WoodPlanks }, parent)
	Build.Part({ Name = "BarnDoorX", Size = Vector3.new(0.8, 14, 0.5), CFrame = cf * CFrame.new(0, 5.5, -12.3) * CFrame.Angles(0, 0, math.rad(40)), Color = red, Material = Enum.Material.Wood }, parent)
	Build.Part({ Name = "BarnDoorX", Size = Vector3.new(0.8, 14, 0.5), CFrame = cf * CFrame.new(0, 5.5, -12.3) * CFrame.Angles(0, 0, math.rad(-40)), Color = red, Material = Enum.Material.Wood }, parent)
end

local function buildSilo(parent: Instance, position: Vector3)
	Build.VerticalCylinder(position + Vector3.new(0, 13, 0), 6, 26, { Name = "Silo", Color = Color3.fromRGB(200, 205, 210), Material = Enum.Material.Metal }, parent)
	Build.Part({ Name = "SiloTop", Shape = Enum.PartType.Ball, Size = Vector3.new(12, 12, 12), Position = position + Vector3.new(0, 26, 0), Color = Color3.fromRGB(190, 55, 45), Material = Enum.Material.Metal }, parent)
end

local function buildCrops(parent: Instance, center: Vector3, rows: number, length: number, yaw: number)
	local cf = CFrame.new(center) * CFrame.Angles(0, yaw, 0)
	for i = 1, rows do
		local x = (i - (rows + 1) / 2) * 4
		Build.Part({ Name = "CropRow", Size = Vector3.new(2.4, 0.8, length), CFrame = cf * CFrame.new(x, 0.4, 0), Color = Color3.fromRGB(110, 75, 45), Material = Enum.Material.Ground }, parent)
		for j = 1, math.floor(length / 5) do
			Build.Part({
				Name = "Crop",
				Shape = Enum.PartType.Ball,
				Size = Vector3.new(1.6, 1.6, 1.6),
				CFrame = cf * CFrame.new(x, 1.2, -length / 2 + j * 5 - 2.5),
				Color = (i + j) % 3 == 0 and Color3.fromRGB(240, 140, 40) or Color3.fromRGB(90, 170, 60),
				CanCollide = false,
			}, parent)
		end
	end
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
			CanCollide = false,
			CanQuery = false,
		}, spinner)
	end
	-- Pare-choc au bout du bras
	Build.VerticalCylinder(origin + Vector3.new(length, 2.2, 0), 2.6, 4.4, {
		Name = "ArmBumper",
		Color = Color3.fromRGB(255, 200, 40),
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
	-- Poteau fixe au centre (le bras tourne autour)
	Build.VerticalCylinder(origin + Vector3.new(0, 4.5, 0), 1, 9, { Name = "CenterPole", Color = Color3.fromRGB(120, 85, 55), Material = Enum.Material.Wood }, parent)
	Build.VerticalCylinder(origin + Vector3.new(0, 0.6, 0), 6.5, 1.2, { Name = "Nest", Color = Color3.fromRGB(215, 175, 90), Material = Enum.Material.Fabric }, parent)
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
	-- Cercle de terre balayé par le bras (zone dangereuse lisible)
	Build.VerticalCylinder(origin + Vector3.new(0, 0.05, 0), cfg.ArmLength + 2, 0.1, {
		Name = "DangerZone",
		Color = Color3.fromRGB(190, 160, 100),
		Material = Enum.Material.Ground,
		CanCollide = false,
		CanQuery = false,
	}, parent)
end

function Map.Build(mapOrigin: Vector3, _context: MapContext)
	origin = mapOrigin
	local f = MapBase.NewFolder("Map_" .. Map.Id)
	MapBase.BuildGround(f, origin, cfg.GroundSize, Color3.fromRGB(110, 178, 72), Enum.Material.Grass)
	MapBase.BuildBoundary(f, origin, cfg.GroundSize, 80)
	MapBase.BuildPerimeterFence(f, origin, cfg.GroundSize)
	bases = MapBase.BuildBases(f, origin, cfg.BaseRadius, cfg.BasePadSize)
	buildNest(f)
	arm = buildArm(f)

	local half = cfg.GroundSize / 2
	-- Décors dans les coins (hors des chemins entre bases)
	buildBarn(f, origin + Vector3.new(-half + 30, 0, half - 28), math.rad(45))
	buildSilo(f, origin + Vector3.new(half - 22, 0, half - 22))
	buildCrops(f, origin + Vector3.new(half - 40, 0, -half + 40), 5, 34, math.rad(45))
	buildCrops(f, origin + Vector3.new(-half + 40, 0, -half + 40), 5, 34, math.rad(-45))
	for _, corner in { Vector3.new(-1, 0, -1), Vector3.new(1, 0, -1), Vector3.new(1, 0, 1), Vector3.new(-1, 0, 1) } do
		MapBase.BuildTree(f, origin + corner * (half - 10), 1.1)
	end

	-- Cachettes : hautes herbes entre les bases, terriers et buissons
	for _, deg in { 30, 150, 270 } do
		local a = math.rad(deg)
		MapBase.BuildTallGrass(f, origin + Vector3.new(math.cos(a), 0, math.sin(a)) * 92, 7)
	end
	for _, deg in { 60, 180, 300 } do
		local a = math.rad(deg)
		MapBase.BuildBurrow(f, origin + Vector3.new(math.cos(a), 0, math.sin(a)) * 72)
	end
	for _, deg in { 0, 120, 240 } do
		local a = math.rad(deg)
		MapBase.BuildBush(f, origin + Vector3.new(math.cos(a), 0, math.sin(a)) * 44, 9)
	end

	-- Obstacles pour feinter : bottes de foin et bouts de clôture
	for i = 0, 5 do
		local a = math.rad(i * 60 + 15)
		local p = origin + Vector3.new(math.cos(a), 0, math.sin(a)) * 78
		MapBase.BuildHayBale(f, p, a)
		MapBase.BuildHayBale(f, p + Vector3.new(math.cos(a + 1.57), 0, math.sin(a + 1.57)) * 5.5, a)
	end
	for _, deg in { 0, 120, 240 } do
		local a = math.rad(deg)
		local center = origin + Vector3.new(math.cos(a), 0, math.sin(a)) * 110
		local tangent = Vector3.new(-math.sin(a), 0, math.cos(a))
		MapBase.BuildFence(f, center - tangent * 12, center + tangent * 12)
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
			dropEgg(egg and egg.Position or origin, "lost")
			return
		end
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
			if root and actor.Team and actor.Character and actor.Character:GetAttribute("Ragdoll") ~= true then
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
		local root = context and context.GetRoot(actor)
		dropEgg(root and root.Position or (egg and egg.Position) or origin, "lost")
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

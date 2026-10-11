--[[
	TheSwamp.lua - mode "The Pack"
	  - Conversion pure : aucune autre règle. Dernière équipe debout
	    (sinon, à la fin du chrono, l'équipe la plus nombreuse gagne).
	  - Mécanismes :
	      * un tourniquet central attrape les joueurs (ils restent bloqués un
	        court instant) puis les relâche vers un des trois camps au hasard ;
	      * des geysers propulsent en l'air à intervalles réguliers (ils
	        bouillonnent avant d'éclater).
	Thème : marais (eau trouble, nénuphars, roseaux, arbres morts, brume).
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

type Actor = Types.Actor
type MapContext = Types.MapContext

local Map = {}
Map.Id = "TheSwamp"
Map.Lighting = {
	ClockTime = 18.2,
	Brightness = 1.7,
	OutdoorAmbient = Color3.fromRGB(120, 150, 130),
	FogColor = Color3.fromRGB(150, 175, 150),
	FogStart = 60,
	FogEnd = 420,
}

local cfg = Config.Maps.TheSwamp
local MUD = Color3.fromRGB(78, 98, 70)
local WATER = Color3.fromRGB(60, 110, 100)
local ARM_COUNT = 4
local ARM_HEIGHT = 3
local SAFE_JUMP_HEIGHT = 6.5

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
local function buildDeadTree(parent: Instance, position: Vector3, height: number)
	local bark = Color3.fromRGB(80, 65, 55)
	Build.VerticalCylinder(position + Vector3.new(0, height / 2, 0), 1.1, height, { Name = "DeadTrunk", Color = bark, Material = Enum.Material.Wood }, parent)
	for i = 1, 3 do
		local a = i * 2.1
		local p = position + Vector3.new(math.cos(a) * 2.2, height * (0.55 + i * 0.1), math.sin(a) * 2.2)
		Build.Part({
			Name = "DeadBranch",
			Size = Vector3.new(0.6, 0.6, 5),
			CFrame = CFrame.lookAt(p, p + Vector3.new(math.cos(a), 0.9, math.sin(a))),
			Color = bark,
			Material = Enum.Material.Wood,
		}, parent)
	end
	-- Mousse pendante
	Build.Part({
		Name = "Moss",
		Size = Vector3.new(0.3, 3, 2),
		Position = position + Vector3.new(1.5, height * 0.7 - 1.5, 0),
		Color = Color3.fromRGB(120, 150, 90),
		Material = Enum.Material.Grass,
		CanCollide = false,
	}, parent)
end

local function buildPond(parent: Instance, position: Vector3, radius: number)
	Build.VerticalCylinder(position + Vector3.new(0, 0.08, 0), radius, 0.16, {
		Name = "Pond",
		Color = WATER,
		Material = Enum.Material.Glass,
		Transparency = 0.15,
		CanCollide = false,
		CanQuery = false,
	}, parent)
	for i = 1, 4 do
		local a = i * 1.7
		local r = radius * 0.6
		Build.VerticalCylinder(position + Vector3.new(math.cos(a) * r, 0.2, math.sin(a) * r), 1.4, 0.1, {
			Name = "LilyPad",
			Color = Color3.fromRGB(90, 160, 80),
			CanCollide = false,
			CanQuery = false,
		}, parent)
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

local function buildWillow(parent: Instance, position: Vector3, scale: number)
	local trunk = Color3.fromRGB(85, 70, 55)
	Build.Part({ Name = "WillowTrunk", Size = Vector3.new(2.6, 12, 2.6) * scale, Position = position + Vector3.new(0, 6 * scale, 0), Color = trunk, Material = Enum.Material.Wood }, parent)
	local leaf = Color3.fromRGB(90, 150, 70)
	Build.Part({ Name = "WillowTop", Size = Vector3.new(14, 6, 14) * scale, Position = position + Vector3.new(0, 14 * scale, 0), Color = leaf, Studs = true }, parent)
	Build.Part({ Name = "WillowTop", Size = Vector3.new(9, 4, 9) * scale, CFrame = CFrame.new(position + Vector3.new(0, 18 * scale, 0)) * CFrame.Angles(0, 0.5, 0), Color = leaf:Lerp(Color3.new(1, 1, 1), 0.1), Studs = true }, parent)
	-- Rideaux de feuillage qui pendent
	for i = 0, 9 do
		local a = i / 10 * math.pi * 2
		local p = position + Vector3.new(math.cos(a) * 6.2 * scale, 8.5 * scale, math.sin(a) * 6.2 * scale)
		Build.Part({ Name = "WillowDrape", Size = Vector3.new(1.4, 7 * scale, 0.4), CFrame = CFrame.new(p) * CFrame.Angles(0, -a, 0), Color = leaf:Lerp(Color3.new(0, 0, 0), 0.12), CanCollide = false, CanQuery = false }, parent)
	end
end

local function buildMushrooms(parent: Instance, center: Vector3)
	for i = 0, 4 do
		local a = i * 1.3
		local p = center + Vector3.new(math.cos(a) * (1 + i * 0.6), 0, math.sin(a) * (1 + i * 0.6))
		local h = 1.2 + (i % 3) * 0.6
		Build.Part({ Name = "MushStem", Size = Vector3.new(0.6, h, 0.6), Position = p + Vector3.new(0, h / 2, 0), Color = Color3.fromRGB(245, 240, 225), CanCollide = false }, parent)
		Build.Part({ Name = "MushCap", Size = Vector3.new(1.8, 0.7, 1.8), Position = p + Vector3.new(0, h + 0.2, 0), Color = Color3.fromRGB(225, 50, 50), Studs = true, CanCollide = false, Accent = true }, parent)
	end
end

local function buildBoardwalk(parent: Instance, from: Vector3, to: Vector3)
	local delta = Vector3.new(to.X - from.X, 0, to.Z - from.Z)
	local length = delta.Magnitude
	local cf = CFrame.lookAt(from, from + delta)
	for k = 0, math.floor(length / 2.2) do
		Build.Part({ Name = "Plank", Size = Vector3.new(6, 0.4, 2), CFrame = cf * CFrame.new(0, 0.3, -k * 2.2) * CFrame.Angles(0, (k % 3 - 1) * 0.03, 0), Color = Color3.fromRGB(135, 100, 70):Lerp(Color3.fromRGB(110, 80, 55), (k % 2) * 0.5), Material = Enum.Material.WoodPlanks, CanCollide = false }, parent)
	end
	for k = 0, math.floor(length / 8) do
		for _, x in { -3.2, 3.2 } do
			Build.Part({ Name = "Post", Size = Vector3.new(0.6, 2.4, 0.6), CFrame = cf * CFrame.new(x, 1, -k * 8), Color = Color3.fromRGB(100, 75, 55), Material = Enum.Material.Wood }, parent)
		end
	end
end

local function buildFireflies(parent: Instance, position: Vector3)
	local host = Build.Part({ Name = "Fireflies", Size = Vector3.new(14, 4, 14), Position = position + Vector3.new(0, 4, 0), Transparency = 1, CanCollide = false, CanQuery = false }, parent)
	local fx = Instance.new("ParticleEmitter")
	fx.Color = ColorSequence.new(Color3.fromRGB(230, 255, 140))
	fx.LightEmission = 1
	fx.Size = NumberSequence.new(0.25)
	fx.Lifetime = NumberRange.new(3, 5)
	fx.Rate = 6
	fx.Speed = NumberRange.new(0.5, 1.5)
	fx.SpreadAngle = Vector2.new(180, 180)
	fx.Parent = host
end

function Map.Build(mapOrigin: Vector3, _context: MapContext)
	origin = mapOrigin
	table.clear(geysers)
	local f = MapBase.NewFolder("Map_" .. Map.Id)
	MapBase.BuildGround(f, origin, cfg.GroundSize, Color3.fromRGB(82, 130, 75))
	MapBase.BuildBoundary(f, origin, cfg.GroundSize, 80)
	MapBase.BuildPerimeterFence(f, origin, cfg.GroundSize, Color3.fromRGB(95, 80, 65))
	bases = MapBase.BuildBases(f, origin, cfg.BaseRadius, cfg.BasePadSize)
	turnstile = buildTurnstile(f)
	-- Cercle de boue autour du tourniquet
	Build.VerticalCylinder(origin + Vector3.new(0, 0.05, 0), cfg.TurnstileRadius + 3, 0.1, { Name = "TurnstileZone", Color = Color3.fromRGB(100, 85, 60), Material = Enum.Material.Mud, CanCollide = false, CanQuery = false }, f)

	-- Geysers sur deux anneaux
	for i = 0, cfg.GeyserCount - 1 do
		local a = math.rad(i * (360 / cfg.GeyserCount) + 30)
		local r = (i % 2 == 0) and 48 or 70
		buildGeyser(f, origin + Vector3.new(math.cos(a), 0, math.sin(a)) * r)
	end

	-- Mares, arbres morts
	local half = cfg.GroundSize / 2
	for i = 0, 5 do
		local a = math.rad(i * 60)
		buildPond(f, origin + Vector3.new(math.cos(a), 0, math.sin(a)) * 118, 9 + (i % 2) * 4)
	end
	for _, corner in { Vector3.new(-1, 0, -1), Vector3.new(1, 0, -1), Vector3.new(1, 0, 1), Vector3.new(-1, 0, 1) } do
		buildDeadTree(f, origin + corner * (half - 18), 18)
		buildDeadTree(f, origin + corner * (half - 40) + Vector3.new(10, 0, -6), 13)
	end

	-- Cachettes : roseaux (hautes herbes sombres), buissons, terriers
	for _, deg in { 30, 150, 270 } do
		local a = math.rad(deg)
		MapBase.BuildTallGrass(f, origin + Vector3.new(math.cos(a), 0, math.sin(a)) * 90, 8, Color3.fromRGB(80, 120, 60))
		MapBase.BuildTallGrass(f, origin + Vector3.new(math.cos(a + 0.4), 0, math.sin(a + 0.4)) * 58, 5, Color3.fromRGB(80, 120, 60))
	end
	for _, deg in { 90, 210, 330 } do
		local a = math.rad(deg + 35)
		MapBase.BuildBurrow(f, origin + Vector3.new(math.cos(a), 0, math.sin(a)) * 80, Color3.fromRGB(90, 70, 50))
	end
	for _, deg in { 0, 120, 240 } do
		local a = math.rad(deg)
		MapBase.BuildBush(f, origin + Vector3.new(math.cos(a), 0, math.sin(a)) * 98, 9, Color3.fromRGB(70, 110, 60))
	end
	-- Troncs couchés
	for i = 0, 5 do
		local a = math.rad(i * 60 + 45)
		local p = origin + Vector3.new(math.cos(a), 0, math.sin(a)) * 36
		Build.Part({
			Name = "Log",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(10, 2.6, 2.6),
			CFrame = CFrame.new(p + Vector3.new(0, 1.3, 0)) * CFrame.Angles(0, a + math.pi / 2, 0),
			Color = Color3.fromRGB(100, 75, 55),
			Material = Enum.Material.Wood,
		}, f)
	end

	-- Environnement : collines sombres, passerelles, saules, champignons, lucioles
	MapBase.BuildSurroundings(f, origin, cfg.GroundSize, {
		Ground = Color3.fromRGB(70, 110, 70),
		Hill = Color3.fromRGB(65, 115, 70),
		HillTop = Color3.fromRGB(85, 135, 80),
		Trees = true,
		TreeColor = Color3.fromRGB(100, 150, 70),
	})
	MapBase.BuildGrassPatches(f, origin, cfg.GroundSize, Color3.fromRGB(70, 115, 65), 12)
	local builtBases = bases :: { [string]: MapBase.Base }
	for _, base in builtBases do
		local toCenter = (origin - base.Center).Unit
		local start = base.Center + toCenter * (base.Radius + 2)
		buildBoardwalk(f, start, origin + toCenter * -(cfg.TurnstileRadius + 8))
		local side = Vector3.new(-toCenter.Z, 0, toCenter.X)
		MapBase.BuildLamp(f, start + toCenter * 12 + side * 5)
		buildMushrooms(f, base.Center + side * (base.Radius + 8))
	end
	for i = 0, 2 do
		local a = math.rad(i * 120 + 60)
		buildWillow(f, origin + Vector3.new(math.cos(a), 0, math.sin(a)) * 128, 1)
		buildFireflies(f, origin + Vector3.new(math.cos(a + 0.4), 0, math.sin(a + 0.4)) * 80)
	end
	for i = 0, 5 do
		local a = math.rad(i * 60 + 20)
		buildMushrooms(f, origin + Vector3.new(math.cos(a), 0, math.sin(a)) * 105)
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

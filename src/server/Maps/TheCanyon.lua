--[[
	TheCanyon.lua - mode "Raid"
	  - Chaque base contient 5 œufs. On ne peut voler que dans la base de sa proie.
	    Un œuf volé doit être ramené à sa propre base.
	    L'équipe avec le plus d'œufs à la fin du chrono gagne (une équipe qui
	    réunit tous les œufs gagne tout de suite).
	  - Un voleur attrapé perd son œuf, qui retourne dans la base d'où il vient.
	  - Mécanisme : une catapulte tournante au centre. Sauter dedans te lance
	    dans la direction qu'elle vise à ce moment-là.
	Thème : canyon rouge (mesas, rochers, cactus, herbes sèches).
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
Map.Id = "TheCanyon"
Map.Lighting = {
	ClockTime = 17.3,
	Brightness = 2.4,
	OutdoorAmbient = Color3.fromRGB(190, 140, 110),
	FogColor = Color3.fromRGB(230, 170, 120),
	FogEnd = 900,
}

local cfg = Config.Maps.TheCanyon
local BUCKET_HEIGHT = 2.5
local SAND = Color3.fromRGB(214, 150, 95)
local ROCK = Color3.fromRGB(176, 98, 60)

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
local function buildMesa(parent: Instance, position: Vector3, radius: number, height: number)
	for i = 0, 2 do
		local r = radius * (1 - i * 0.18)
		Build.VerticalCylinder(position + Vector3.new(0, height * (i + 0.5) / 3, 0), r, height / 3, {
			Name = "Mesa",
			Color = ROCK:Lerp(Color3.fromRGB(230, 160, 110), i * 0.15),
			Material = Enum.Material.Sandstone,
		}, parent)
	end
end

local function buildCactus(parent: Instance, position: Vector3)
	local green = Color3.fromRGB(80, 140, 70)
	Build.VerticalCylinder(position + Vector3.new(0, 3.5, 0), 1, 7, { Name = "Cactus", Color = green, Material = Enum.Material.Grass }, parent)
	Build.Part({ Name = "CactusArm", Size = Vector3.new(3, 1.4, 1.4), Position = position + Vector3.new(1.5, 3.5, 0), Color = green, Material = Enum.Material.Grass }, parent)
	Build.VerticalCylinder(position + Vector3.new(2.6, 4.6, 0), 0.7, 2.6, { Name = "CactusArm", Color = green, Material = Enum.Material.Grass }, parent)
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
	MapBase.BuildGround(f, origin, cfg.GroundSize, SAND, Enum.Material.Sandstone)
	MapBase.BuildBoundary(f, origin, cfg.GroundSize, 80)
	bases = MapBase.BuildBases(f, origin, cfg.BaseRadius, cfg.BasePadSize)
	catapult = buildCatapult(f)

	-- Falaises tout autour (décor de bord)
	local half = cfg.GroundSize / 2
	for i = 0, 15 do
		local t = i / 16
		local edge = i // 4
		local along = (t * 4 - edge) * cfg.GroundSize - half
		local p
		if edge == 0 then
			p = Vector3.new(along, 0, -half)
		elseif edge == 1 then
			p = Vector3.new(half, 0, along)
		elseif edge == 2 then
			p = Vector3.new(-along, 0, half)
		else
			p = Vector3.new(-half, 0, -along)
		end
		buildMesa(f, origin + p, 14 + (i % 3) * 3, 22 + (i % 4) * 6)
	end

	-- Œufs : 5 par base
	for _, teamId in Teams.Order do
		buildNest(f, teamId)
		eggsInBase[teamId] = {}
		for _ = 1, cfg.EggsPerBase do
			table.insert(eggsInBase[teamId], newEgg(teamId))
		end
		layoutBase(teamId)
	end

	-- Cachettes : herbes sèches, terriers, buissons secs
	for _, deg in { 30, 150, 270 } do
		local a = math.rad(deg)
		MapBase.BuildTallGrass(f, origin + Vector3.new(math.cos(a), 0, math.sin(a)) * 95, 7, Color3.fromRGB(200, 170, 90))
	end
	for _, deg in { 65, 185, 305 } do
		local a = math.rad(deg)
		MapBase.BuildBurrow(f, origin + Vector3.new(math.cos(a), 0, math.sin(a)) * 70, Color3.fromRGB(150, 90, 55))
	end
	for _, deg in { 0, 120, 240 } do
		local a = math.rad(deg)
		MapBase.BuildBush(f, origin + Vector3.new(math.cos(a), 0, math.sin(a)) * 50, 8, Color3.fromRGB(130, 140, 70))
	end

	-- Rochers et cactus pour feinter
	for i = 0, 11 do
		local a = math.rad(i * 30 + 15)
		local r = (i % 2 == 0) and 62 or 82
		local p = origin + Vector3.new(math.cos(a), 0, math.sin(a)) * r
		if i % 3 == 0 then
			buildCactus(f, p)
		else
			MapBase.BuildRock(f, p, Vector3.new(7 + i % 3 * 2, 6 + i % 2 * 3, 6), ROCK)
		end
	end
	-- Arches rocheuses entre les bases
	for _, deg in { 30, 150, 270 } do
		local a = math.rad(deg)
		local center = origin + Vector3.new(math.cos(a), 0, math.sin(a)) * 125
		local tangent = Vector3.new(-math.sin(a), 0, math.cos(a))
		for _, side in { -1, 1 } do
			Build.Part({ Name = "ArchLeg", Size = Vector3.new(4, 14, 4), Position = center + tangent * side * 7 + Vector3.new(0, 7, 0), Color = ROCK, Material = Enum.Material.Sandstone }, f)
		end
		Build.Part({ Name = "ArchTop", Size = Vector3.new(4, 4, 18), CFrame = CFrame.lookAt(center + Vector3.new(0, 15, 0), center + Vector3.new(0, 15, 0) + tangent), Color = ROCK, Material = Enum.Material.Sandstone }, f)
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

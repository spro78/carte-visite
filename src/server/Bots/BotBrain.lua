--[[
	BotBrain.lua
	Intelligence d'un bot, volontairement imparfaite pour qu'un débutant gagne :
	  1. FUIR le prédateur le plus proche s'il est à moins de FleeDistance studs
	     (parfois vers une cachette, vers la zone sûre de son camp s'il est
	     proche, avec un dash de panique) ;
	  2. PORTER un coéquipier à terre jusqu'au camp (s'il en porte un), ou aller
	     le RAMASSER s'il est assez près (pas toujours : RescueChance) ;
	  3. sinon POURSUIVRE la proie la plus proche (anticipation + erreur de visée,
	     dash et capacité de temps en temps), hors de sa zone sûre ;
	  4. sinon aller vers l'OBJECTIF de la map (Map.GetBotGoal), ou flâner.
	Un bot à terre ne fait rien : il attend qu'on le porte.
	Chaque changement de décision est retardé d'un temps de réaction, et une
	part des décisions sont des "erreurs" (hésitation, mauvaise direction).
	Le déplacement utilise PathfindingService pour les cibles lointaines.
]]

local PathfindingService = game:GetService("PathfindingService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Teams = require(Shared.Teams)
local Movement = require(Shared.Movement)
local Types = require(Shared.Types)
local ActorService = require(script.Parent.Parent.Services.ActorService)
local RoundState = require(script.Parent.Parent.Services.RoundState)
local AbilityService = require(script.Parent.Parent.Services.AbilityService)
local HideService = require(script.Parent.Parent.Services.HideService)
local RescueService = require(script.Parent.Parent.Services.RescueService)
local SafeZoneService = require(script.Parent.Parent.Services.SafeZoneService)
local BotAnimator = require(script.Parent.BotAnimator)

type Actor = Types.Actor

local BotBrain = {}
BotBrain.__index = BotBrain

local cfg = Config.Bots
local random = Random.new()

export type Brain = {
	Actor: Actor,
	Animator: any,
	Mode: string, -- "Idle" | "Chase" | "Flee" | "Objective" | "Wander" | "Hide" | "Pause" | "Rescue"
	Target: Actor?,
	Goal: Vector3?,
	FleeDirection: Vector3?,
	AimOffset: Vector3,
	PendingMode: string?,
	PendingAt: number,
	PendingData: any,
	NextThink: number,
	Waypoints: { PathWaypoint }?,
	WaypointIndex: number,
	PathGoal: Vector3?,
	PathBusy: boolean,
	LastPathAt: number,
	Speed: number,
	LastProgressPos: Vector3?,
	LastProgressAt: number,
	SidestepUntil: number,
	SidestepDir: Vector3?,
	AnimAccumulator: number,
	RescueChoice: { [any]: boolean }, -- décision prise pour chaque mise à terre
	NextCarryTry: number,
}

function BotBrain.new(actor: Actor): Brain
	local self = setmetatable({
		Actor = actor,
		Animator = nil,
		Mode = "Idle",
		Target = nil,
		Goal = nil,
		FleeDirection = nil,
		AimOffset = Vector3.zero,
		PendingMode = nil,
		PendingAt = 0,
		PendingData = nil,
		NextThink = os.clock() + random:NextNumber(0, cfg.ThinkInterval),
		Waypoints = nil,
		WaypointIndex = 1,
		PathGoal = nil,
		PathBusy = false,
		LastPathAt = 0,
		Speed = 0,
		LastProgressPos = nil,
		LastProgressAt = os.clock(),
		SidestepUntil = 0,
		SidestepDir = nil,
		AnimAccumulator = 0,
		RescueChoice = setmetatable({}, { __mode = "k" }),
		NextCarryTry = 0,
	}, BotBrain)
	local humanoid = ActorService.GetHumanoid(actor)
	if humanoid then
		self.Animator = BotAnimator.new(humanoid)
	end
	return (self :: any) :: Brain
end

function BotBrain.Destroy(self: Brain)
	if self.Animator then
		self.Animator:Destroy()
		self.Animator = nil
	end
end

-- ---------------------------------------------------------------------------
-- Outils
-- ---------------------------------------------------------------------------
local function flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

local function mapHalfSize(): number
	local mapId = RoundState.MapId
	local mapCfg = mapId and Config.Maps[mapId]
	return mapCfg and (mapCfg.GroundSize / 2 - 8) or 140
end

local function clampToMap(position: Vector3): Vector3
	local origin = Config.World.MapOrigin
	local half = mapHalfSize()
	return Vector3.new(
		math.clamp(position.X, origin.X - half, origin.X + half),
		position.Y,
		math.clamp(position.Z, origin.Z - half, origin.Z + half)
	)
end

local function isVisibleTo(other: Actor, distance: number): boolean
	local character = other.Character
	if not character then
		return false
	end
	if character:GetAttribute("Carrier") == true then
		return true
	end
	if character:GetAttribute("Hidden") == true and distance > Config.Hiding.RevealDistance then
		return false
	end
	return true
end

local function isProtected(other: Actor): boolean
	local character = other.Character
	if character and character:GetAttribute("SafeZone") == true then
		return true -- à l'abri dans la zone sûre de son camp
	end
	local untilTime = character and character:GetAttribute("ProtectedUntil")
	return type(untilTime) == "number" and untilTime > os.clock()
end

-- Centre du camp de l'équipe (zone sûre)
local function homeOf(actor: Actor): Vector3?
	local base = SafeZoneService.GetBase(actor.Team)
	return base and base.Center or nil
end

-- Coéquipier à terre (non porté) que ce bot accepte d'aller chercher
local function findRescueTarget(self: Brain, position: Vector3): Actor?
	local team = self.Actor.Team
	local best, bestDistance = nil, cfg.RescueRange
	for _, entry in RescueService.GetDowned() do
		local victim = entry.Actor
		if entry.Carrier == nil and victim.Team == team and victim ~= self.Actor then
			local p = ActorService.GetPosition(victim)
			if p then
				local distance = flat(p - position).Magnitude
				if distance < bestDistance then
					-- Décision tirée une fois par mise à terre (pas d'hésitation)
					local willing = self.RescueChoice[entry]
					if willing == nil then
						willing = random:NextNumber() < cfg.RescueChance
						self.RescueChoice[entry] = willing
					end
					if willing then
						best, bestDistance = victim, distance
					end
				end
			end
		end
	end
	return best
end

-- ---------------------------------------------------------------------------
-- Décision
-- ---------------------------------------------------------------------------
type Perception = {
	Predator: Actor?,
	PredatorDistance: number,
	Prey: Actor?,
	PreyDistance: number,
	NearestEnemyDistance: number,
}

local function perceive(self: Brain, position: Vector3): Perception
	local actor = self.Actor
	local team = actor.Team
	local result: Perception = {
		Predator = nil,
		PredatorDistance = math.huge,
		Prey = nil,
		PreyDistance = math.huge,
		NearestEnemyDistance = math.huge,
	}
	if not team then
		return result
	end
	local preyTeam = Teams.GetPrey(team)
	local predatorTeam = Teams.GetPredator(team)
	for _, other in RoundState.GetActiveParticipants() do
		if other == actor then
			continue
		end
		local otherPos = ActorService.GetPosition(other)
		if not otherPos then
			continue
		end
		local distance = flat(otherPos - position).Magnitude
		if not isVisibleTo(other, distance) then
			continue
		end
		if other.Team ~= team and distance < result.NearestEnemyDistance then
			result.NearestEnemyDistance = distance
		end
		if other.Team == predatorTeam and distance < result.PredatorDistance then
			result.Predator, result.PredatorDistance = other, distance
		elseif other.Team == preyTeam and distance < result.PreyDistance and not isProtected(other) then
			result.Prey, result.PreyDistance = other, distance
		end
	end
	return result
end

local function isCarrier(actor: Actor): boolean
	local map = RoundState.Map
	return map ~= nil and map.IsCarrier ~= nil and map.IsCarrier(actor) == true
end

local function chooseHidingSpot(position: Vector3, fleeDir: Vector3): Vector3?
	local best, bestScore = nil, math.huge
	for _, spot in HideService.GetSpots() do
		local delta = flat(spot - position)
		local distance = delta.Magnitude
		if distance < 45 and distance > 2 and delta.Unit:Dot(fleeDir) > 0.2 and distance < bestScore then
			best, bestScore = spot, distance
		end
	end
	return best
end

local function setMode(self: Brain, mode: string, data: any)
	self.Mode = mode
	if mode == "Rescue" then
		self.Target = data
	elseif mode == "Chase" then
		self.Target = data
		self.AimOffset = Vector3.new(random:NextNumber(-1, 1), 0, random:NextNumber(-1, 1)) * cfg.AimError
	elseif mode == "Flee" then
		self.Target = data.Predator
		self.FleeDirection = data.Direction
		self.Goal = data.HideSpot
	elseif mode == "Objective" or mode == "Wander" or mode == "Hide" then
		self.Goal = data
	elseif mode == "Pause" then
		self.Goal = nil
	end
end

-- Programme une décision ; si elle diffère de l'actuelle, elle n'est appliquée
-- qu'après un temps de réaction.
local function decide(self: Brain, mode: string, data: any)
	if mode == self.Mode then
		setMode(self, mode, data)
		self.PendingMode = nil
		return
	end
	if self.PendingMode == mode then
		self.PendingData = data
		return
	end
	self.PendingMode = mode
	self.PendingData = data
	self.PendingAt = os.clock() + random:NextNumber(cfg.ReactionTimeMin, cfg.ReactionTimeMax)
end

local function wanderPoint(position: Vector3): Vector3
	local origin = Config.World.MapOrigin
	local toward = flat(origin - position)
	local base = position + (toward.Magnitude > 1 and toward.Unit * 15 or Vector3.zero)
	local offset = Vector3.new(random:NextNumber(-1, 1), 0, random:NextNumber(-1, 1)) * cfg.WanderRadius
	return clampToMap(base + offset)
end

local function useAbilities(self: Brain, perception: Perception)
	local actor = self.Actor
	local team = actor.Team
	if not team or random:NextNumber() > cfg.AbilityChance then
		return
	end
	if team == "FOX" and self.Mode == "Chase" and perception.PreyDistance < 30 then
		AbilityService.TryAbility(actor, true)
	elseif team == "CHICKEN" and self.Mode == "Flee" and perception.PredatorDistance < 10 then
		AbilityService.TryAbility(actor, true)
	elseif team == "SNAKE" and perception.NearestEnemyDistance < Config.Abilities.SNAKE.Range then
		AbilityService.TryAbility(actor, true)
	end
end

local function useDash(self: Brain, position: Vector3, perception: Perception)
	local actor = self.Actor
	local root = ActorService.GetRoot(actor)
	if not root or random:NextNumber() > cfg.DashChance then
		return
	end
	if self.Mode == "Chase" and self.Target and perception.PreyDistance > 5 and perception.PreyDistance < 14 then
		local targetPos = ActorService.GetPosition(self.Target)
		if targetPos then
			local lateral = root.CFrame.RightVector:Dot(flat(targetPos - position))
			if math.abs(lateral) > 3 then
				AbilityService.TryDash(actor, lateral > 0 and 1 or -1, true)
			end
		end
	elseif self.Mode == "Flee" and perception.PredatorDistance < 9 then
		AbilityService.TryDash(actor, random:NextNumber() < 0.5 and -1 or 1, true)
	end
end

function BotBrain.Think(self: Brain)
	local actor = self.Actor
	local position = ActorService.GetPosition(actor)
	if not position or not actor.Team then
		return
	end
	if not RoundState.IsActive() or RescueService.IsDown(actor) then
		setMode(self, "Idle", nil)
		self.PendingMode = nil
		return
	end
	local perception = perceive(self, position)
	local carryingTeammate = RescueService.GetCarried(actor) ~= nil
	local carrying = isCarrier(actor) or carryingTeammate
	local fleeDistance = cfg.FleeDistance * (carrying and 0.6 or 1)
	local home = homeOf(actor)
	local rescueTarget = (not carrying) and findRescueTarget(self, position) or nil

	-- Erreur volontaire : hésitation ou fausse piste (pas pendant un sauvetage)
	local focused = carryingTeammate or self.Mode == "Rescue"
	if random:NextNumber() < cfg.MistakeChance and not focused then
		if random:NextNumber() < 0.5 then
			decide(self, "Pause", nil)
		else
			decide(self, "Wander", wanderPoint(position))
		end
	elseif perception.Predator and perception.PredatorDistance < fleeDistance then
		local predatorPos = ActorService.GetPosition(perception.Predator) or position
		local away = flat(position - predatorPos)
		away = away.Magnitude > 0.1 and away.Unit or Vector3.new(1, 0, 0)
		-- Un porteur fuit en direction de sa base ; près de son camp, on se
		-- réfugie dans la zone sûre
		local map = RoundState.Map
		if carryingTeammate and home then
			away = (away + flat(home - position).Unit * 1.2).Unit
		elseif carrying and map and map.GetBotGoal then
			local goal = map.GetBotGoal(actor)
			if goal then
				away = (away + flat(goal - position).Unit * 1.2).Unit
			end
		elseif home and flat(home - position).Magnitude < cfg.SafeZoneRefugeDistance then
			away = (away + flat(home - position).Unit * 0.9).Unit
		end
		local hideSpot = nil
		if not carrying and random:NextNumber() < cfg.HideChance then
			hideSpot = chooseHidingSpot(position, away)
		end
		decide(self, "Flee", { Predator = perception.Predator, Direction = away, HideSpot = hideSpot })
	elseif carryingTeammate and home then
		-- Ramener le coéquipier porté dans la zone sûre du camp
		decide(self, "Objective", home)
	elseif rescueTarget then
		decide(self, "Rescue", rescueTarget)
	elseif perception.Prey and perception.PreyDistance < cfg.ChaseDistance and not carrying then
		decide(self, "Chase", perception.Prey)
	else
		local map = RoundState.Map
		local goal = map and map.GetBotGoal and map.GetBotGoal(actor)
		if goal then
			decide(self, "Objective", clampToMap(goal))
		elseif self.Mode ~= "Wander" or not self.Goal or flat(self.Goal - position).Magnitude < 4 then
			decide(self, "Wander", wanderPoint(position))
		end
	end

	useDash(self, position, perception)
	useAbilities(self, perception)
end

-- ---------------------------------------------------------------------------
-- Déplacement
-- ---------------------------------------------------------------------------
local function requestPath(self: Brain, from: Vector3, goal: Vector3)
	if self.PathBusy then
		return
	end
	self.PathBusy = true
	self.LastPathAt = os.clock()
	self.PathGoal = goal
	task.spawn(function()
		local path = PathfindingService:CreatePath({
			AgentRadius = 2,
			AgentHeight = 5,
			AgentCanJump = true,
			WaypointSpacing = 6,
		})
		local ok = pcall(function()
			path:ComputeAsync(from, goal)
		end)
		self.PathBusy = false
		if ok and path.Status == Enum.PathStatus.Success then
			local waypoints = path:GetWaypoints()
			self.Waypoints = waypoints
			self.WaypointIndex = math.min(2, #waypoints)
		else
			self.Waypoints = nil
		end
	end)
end

-- Direction vers une cible lointaine, en suivant un chemin si possible
local function pathDirection(self: Brain, position: Vector3, goal: Vector3): (Vector3?, boolean)
	local now = os.clock()
	local needNew = self.PathGoal == nil or flat(goal - self.PathGoal).Magnitude > 8 or now - self.LastPathAt > cfg.PathRecomputeInterval
	if needNew then
		requestPath(self, position, goal)
	end
	local waypoints = self.Waypoints
	local jump = false
	if waypoints and #waypoints > 0 then
		while self.WaypointIndex <= #waypoints do
			local wp = waypoints[self.WaypointIndex]
			if flat(wp.Position - position).Magnitude < 3.5 then
				self.WaypointIndex += 1
			else
				jump = wp.Action == Enum.PathWaypointAction.Jump
				local delta = flat(wp.Position - position)
				return delta.Magnitude > 0.1 and delta.Unit or nil, jump
			end
		end
	end
	local delta = flat(goal - position)
	return delta.Magnitude > 0.1 and delta.Unit or nil, false
end

function BotBrain.Step(self: Brain, dt: number)
	local actor = self.Actor
	local character = actor.Character
	local humanoid = ActorService.GetHumanoid(actor)
	local root = ActorService.GetRoot(actor)
	if not character or not humanoid or not root or humanoid.Health <= 0 then
		return
	end
	local now = os.clock()
	-- À terre (ou porté) : immobile, en attendant un coéquipier
	if character:GetAttribute("Downed") == true then
		self.Speed = 0
		self.Mode = "Idle"
		self.PendingMode = nil
		humanoid:Move(Vector3.zero, false)
		return
	end

	-- Décision en attente (temps de réaction)
	if self.PendingMode and now >= self.PendingAt then
		setMode(self, self.PendingMode, self.PendingData)
		self.PendingMode = nil
	end
	if now >= self.NextThink then
		self.NextThink = now + cfg.ThinkInterval
		BotBrain.Think(self)
	end

	local frozen = character:GetAttribute("Frozen") == true
	local ragdoll = Movement.IsRagdolled(character)
	local position = root.Position
	local direction: Vector3? = nil
	local wantJump = false

	if not frozen and not ragdoll then
		if self.Mode == "Chase" and self.Target then
			local targetPos = ActorService.GetPosition(self.Target)
			local targetRoot = ActorService.GetRoot(self.Target)
			if targetPos and targetRoot and self.Target.Team == Teams.GetPrey(actor.Team or "") then
				local aim = targetPos + flat(targetRoot.AssemblyLinearVelocity) * cfg.LeadSeconds
				local distance = flat(targetPos - position).Magnitude
				-- L'erreur de visée diminue en s'approchant
				aim += self.AimOffset * math.clamp(distance / 30, 0, 1)
				if distance < cfg.DirectChaseDistance then
					local delta = flat(aim - position)
					direction = delta.Magnitude > 0.1 and delta.Unit or nil
				else
					direction, wantJump = pathDirection(self, position, clampToMap(aim))
				end
			else
				self.Mode = "Idle"
			end
		elseif self.Mode == "Rescue" and self.Target then
			local targetPos = ActorService.GetPosition(self.Target)
			if targetPos and RescueService.IsDown(self.Target) and RescueService.GetCarried(actor) == nil then
				local distance = flat(targetPos - position).Magnitude
				if distance <= Config.Rescue.PickupRange - 1 then
					if now >= self.NextCarryTry then
						self.NextCarryTry = now + 0.3
						RescueService.TryCarry(actor)
					end
				elseif distance < cfg.DirectChaseDistance then
					direction = flat(targetPos - position).Unit
				else
					direction, wantJump = pathDirection(self, position, targetPos)
				end
			else
				self.Mode = "Idle"
			end
		elseif self.Mode == "Flee" then
			if self.Goal then
				local delta = flat(self.Goal - position)
				if delta.Magnitude > 2 then
					direction = delta.Unit
				end
			elseif self.FleeDirection then
				-- Rester dans la map : on glisse le long des bords
				local ahead = position + self.FleeDirection * 12
				local clamped = clampToMap(ahead)
				local delta = flat(clamped - position)
				if delta.Magnitude < 4 then
					delta = flat(Vector3.new(-self.FleeDirection.Z, 0, self.FleeDirection.X))
				end
				direction = delta.Magnitude > 0.1 and delta.Unit or nil
			end
		elseif (self.Mode == "Objective" or self.Mode == "Wander" or self.Mode == "Hide") and self.Goal then
			if flat(self.Goal - position).Magnitude > 2.5 then
				direction, wantJump = pathDirection(self, position, self.Goal)
			end
		end
	end

	-- Petit écart pour se décoincer
	if now < self.SidestepUntil and self.SidestepDir then
		direction = self.SidestepDir
	end

	-- Vitesse avec inertie simple
	local maxSpeed = frozen and 0 or Movement.GetMaxSpeed(character) * cfg.SpeedMultiplier
	local targetSpeed = direction and maxSpeed or 0
	local accel = targetSpeed > self.Speed and Config.Movement.Acceleration or Config.Movement.Deceleration
	if self.Speed < targetSpeed then
		self.Speed = math.min(targetSpeed, self.Speed + accel * dt)
	else
		self.Speed = math.max(targetSpeed, self.Speed - accel * dt)
	end
	if not ragdoll then
		humanoid.WalkSpeed = self.Speed
		if direction then
			humanoid:Move(direction, false)
		elseif self.Speed < 0.5 then
			humanoid:Move(Vector3.zero, false)
		end
		if wantJump then
			humanoid.Jump = true
		end
	end
	Movement.GlideStep(character)

	-- Détection de blocage
	if direction and self.Speed > 5 and not ragdoll then
		if not self.LastProgressPos or flat(position - self.LastProgressPos).Magnitude > 2 then
			self.LastProgressPos = position
			self.LastProgressAt = now
		elseif now - self.LastProgressAt > cfg.StuckSeconds then
			humanoid.Jump = true
			self.Waypoints = nil
			self.SidestepDir = Vector3.new(-direction.Z, 0, direction.X) * (random:NextNumber() < 0.5 and -1 or 1)
			self.SidestepUntil = now + 0.7
			self.LastProgressAt = now
		end
	else
		self.LastProgressPos = position
		self.LastProgressAt = now
	end

	-- Animations (10 fois par seconde)
	self.AnimAccumulator += dt
	if self.Animator and self.AnimAccumulator > 0.1 then
		self.AnimAccumulator = 0
		self.Animator:Update(humanoid, flat(root.AssemblyLinearVelocity).Magnitude)
	end
end

return BotBrain

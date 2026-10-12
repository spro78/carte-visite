--[[
	EggRun.lua - mode EGG RUN
	Des œufs peints apparaissent dans les nids de la carte (un par nid au plus,
	Config.Modes.EggRun.ActiveEggs en même temps). On ramasse un œuf en le
	touchant et on le rapporte dans la zone sûre de son camp : +1 œuf.
	  - le porteur est ralenti, visible de tous, ne peut ni attraper ni porter
	    un coéquipier (mains prises) ;
	  - un porteur attrapé (mis à terre) lâche l'œuf là où il est ; un œuf
	    tombé se ramasse après un court délai, puis retourne à un nid s'il
	    reste seul trop longtemps ;
	  - première équipe à EggsToWin œufs : victoire ; au chrono, l'équipe qui
	    a le plus d'œufs (égalité : règle de base, l'équipe la plus nombreuse).
	Les nids sont fournis par la carte (layout.Nests), à égale distance des
	camps dans l'ensemble (un nid entre chaque paire de camps).
]]

local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Teams = require(Shared.Teams)
local Types = require(Shared.Types)
local Remotes = require(Shared.Remotes)
local Mechanics = require(Shared.Mechanics)
local Kit = require(script.Parent.Parent.Util.Kit)
local SafeZoneService = require(script.Parent.Parent.Services.SafeZoneService)

type Actor = Types.Actor
type MapContext = Types.MapContext

type Egg = {
	Model: Model,
	Pivot: BasePart,
	State: string, -- "Nest" | "Carried" | "Dropped"
	Nest: number?,
	Carrier: Actor?,
	Weld: WeldConstraint?,
	PickupAt: number,
	DroppedAt: number,
	LastPosition: Vector3,
}

local EggRun = {}

local cfg = Config.Modes.EggRun
local EGG_FLOAT = 1.4 -- hauteur de l'œuf au-dessus du nid

local context: MapContext? = nil
local layout: any = nil
local eggs: { Egg } = {}
local nestBusy: { [number]: boolean } = {}
local pending = 0 -- œufs en attente de réapparition
local connection: RBXScriptConnection? = nil
local running = false
local tick = 0
local objectiveTick = 0

local function carrierOf(actor: Actor): Egg?
	for _, egg in eggs do
		if egg.Carrier == actor then
			return egg
		end
	end
	return nil
end

local function newEgg(position: Vector3): Egg
	local model = Kit.Place(layout.Folder, "Egg", CFrame.new(position), { Collide = false, Movable = true, Name = "PaintedEgg" })
	local pivot = model.PrimaryPart :: BasePart
	pivot:SetAttribute("Objective", "Egg")
	-- Halo : un œuf se voit de loin (sans couleur d'équipe)
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 240, 220)
	light.Range = 12
	light.Brightness = 1.4
	light.Parent = pivot
	local sparkles = Instance.new("ParticleEmitter")
	sparkles.Name = "Sparkles"
	sparkles.Color = ColorSequence.new(Color3.fromRGB(255, 250, 235))
	sparkles.LightEmission = 1
	sparkles.Size = NumberSequence.new(0.3, 0)
	sparkles.Lifetime = NumberRange.new(0.6, 1.1)
	sparkles.Rate = 10
	sparkles.Speed = NumberRange.new(2, 4)
	sparkles.SpreadAngle = Vector2.new(180, 180)
	sparkles.Parent = pivot
	return {
		Model = model,
		Pivot = pivot,
		State = "Nest",
		Nest = nil,
		Carrier = nil,
		Weld = nil,
		PickupAt = os.clock() + 0.5,
		DroppedAt = 0,
		LastPosition = position,
	}
end

local function rest(egg: Egg, position: Vector3)
	if egg.Weld then
		egg.Weld:Destroy()
		egg.Weld = nil
	end
	local pivot = egg.Pivot
	pivot.Anchored = true
	pivot.CFrame = CFrame.new(position)
	if egg.Model.Parent ~= layout.Folder then
		egg.Model.Parent = layout.Folder
	end
	CollectionService:AddTag(pivot, Mechanics.FloatTag)
	pivot:SetAttribute("FloatServerPos", position)
	egg.LastPosition = position
end

local function freeNests(): { number }
	local list = {}
	for index in layout.Nests do
		if not nestBusy[index] then
			table.insert(list, index)
		end
	end
	return list
end

local function spawnInNest(index: number)
	local position = layout.Nests[index] + Vector3.new(0, EGG_FLOAT, 0)
	local egg = newEgg(position)
	egg.Nest = index
	nestBusy[index] = true
	rest(egg, position)
	table.insert(eggs, egg)
end

local function spawnRandom(): boolean
	local free = freeNests()
	if #free == 0 then
		return false
	end
	spawnInNest(free[math.random(#free)])
	return true
end

local function releaseCarrier(egg: Egg)
	local actor = egg.Carrier
	egg.Carrier = nil
	local ctx = context
	if ctx and actor then
		ctx.SetCarrier(actor, false)
		ctx.SetSpeedModifier(actor, "EggCarrier", nil)
		ctx.SetActorObjective(actor, nil)
	end
end

local function groundPoint(position: Vector3): Vector3
	local half = (layout.HalfSize or 150) - 6
	local o = layout.Origin
	return Vector3.new(math.clamp(position.X, o.X - half, o.X + half), o.Y + EGG_FLOAT, math.clamp(position.Z, o.Z - half, o.Z + half))
end

local function drop(egg: Egg, position: Vector3, reason: string)
	if egg.State ~= "Carried" then
		return
	end
	releaseCarrier(egg)
	-- L'œuf porté est rangé dans le personnage : s'il a disparu avec lui
	-- (réapparition du porteur), on en refait un
	if egg.Model.Parent == nil or egg.Pivot.Parent == nil then
		local fresh = newEgg(position)
		egg.Model = fresh.Model
		egg.Pivot = fresh.Pivot
	end
	egg.State = "Dropped"
	egg.DroppedAt = os.clock()
	egg.PickupAt = os.clock() + cfg.DropPickupDelay
	rest(egg, groundPoint(position))
	local ctx = context
	if ctx then
		ctx.Announce(reason == "caught" and "An egg was dropped!" or "An egg fell!", Color3.fromRGB(240, 236, 255))
	end
end

local function pickUp(egg: Egg, actor: Actor)
	local ctx = context
	local character = actor.Character
	local head = character and character:FindFirstChild("Head")
	if not ctx or not head or not head:IsA("BasePart") or not actor.Team then
		return
	end
	if egg.Nest then
		nestBusy[egg.Nest] = nil
		egg.Nest = nil
		pending += 1
		-- Le nid vide reçoit un nouvel œuf plus tard (ActiveEggs en jeu au plus)
		task.delay(cfg.RespawnDelay, function()
			if running then
				pending -= 1
				if #eggs < cfg.ActiveEggs then
					spawnRandom()
				end
			end
		end)
	end
	local pivot = egg.Pivot
	CollectionService:RemoveTag(pivot, Mechanics.FloatTag)
	pivot.Anchored = false
	pivot.Massless = true
	pivot.CFrame = head.CFrame * CFrame.new(0, head.Size.Y / 2 + 1.8, 0)
	egg.Model.Parent = character
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = head
	weld.Part1 = pivot
	weld.Parent = pivot
	egg.Weld = weld
	egg.State = "Carried"
	egg.Carrier = actor
	egg.LastPosition = head.Position
	ctx.SetCarrier(actor, true)
	ctx.SetSpeedModifier(actor, "EggCarrier", cfg.CarrierSpeedMultiplier)
	local base = layout.Bases and layout.Bases[actor.Team]
	if base then
		ctx.SetActorObjective(actor, base.Center)
	end
	local def = Teams.Get(actor.Team)
	if def then
		ctx.AnnounceTo(actor, "You have an egg! Run it to your camp!", def.Color)
	end
end

local function score(egg: Egg, actor: Actor)
	local ctx = context
	local team = actor.Team
	if not ctx or not team then
		return
	end
	local root = ctx.GetRoot(actor)
	releaseCarrier(egg)
	egg.Model:Destroy()
	table.remove(eggs, table.find(eggs, egg) :: number)
	ctx.AddScore(team, 1)
	ctx.RewardObjective(actor, "Egg")
	local total = ctx.GetScore(team)
	Remotes.Get("Effect"):FireAllClients("Score", { Position = root and root.Position, Team = team })
	local def = Teams.Get(team)
	if def then
		ctx.Announce(string.format("%s scored an egg! (%d/%d)", def.Plural, total, cfg.EggsToWin), def.Color)
	end
	if total >= cfg.EggsToWin then
		ctx.EndRound(team, "Objective")
		return
	end
	-- Remplacer l'œuf marqué (toujours ActiveEggs œufs en jeu)
	pending += 1
	task.delay(cfg.RespawnDelay, function()
		if running then
			pending -= 1
			if #eggs < cfg.ActiveEggs then
				spawnRandom()
			end
		end
	end)
end

local function eligible(actor: Actor): boolean
	local character = actor.Character
	if not character or not actor.Team then
		return false
	end
	-- Mains prises : déjà un œuf, ou un coéquipier sur l'épaule
	return character:GetAttribute("Ragdoll") ~= true and character:GetAttribute("Carrying") == nil and carrierOf(actor) == nil
end

local function update()
	local ctx = context
	if not ctx then
		return
	end
	local now = os.clock()
	for _, egg in table.clone(eggs) do
		if egg.State == "Carried" then
			local actor = egg.Carrier
			local root = actor and ctx.GetRoot(actor)
			local character = actor and actor.Character
			if not actor or not root or not actor.Team or not character or character:GetAttribute("Downed") == true then
				drop(egg, egg.LastPosition, "lost")
				continue
			end
			egg.LastPosition = root.Position
			if SafeZoneService.Contains(actor.Team, root.Position) then
				score(egg, actor)
			end
		elseif now >= egg.PickupAt then
			if egg.State == "Dropped" and now - egg.DroppedAt > cfg.DropReturnSeconds then
				-- Un œuf oublié retourne dans un nid libre
				local free = freeNests()
				if #free > 0 then
					local index = free[math.random(#free)]
					egg.State = "Nest"
					egg.Nest = index
					nestBusy[index] = true
					rest(egg, layout.Nests[index] + Vector3.new(0, EGG_FLOAT, 0))
					continue
				end
			end
			local position = egg.Pivot.Position
			local best, bestDistance = nil, cfg.PickupRange
			for _, actor in ctx.GetActors() do
				local root = ctx.GetRoot(actor)
				if root and eligible(actor) then
					local d = (root.Position - position).Magnitude
					if d <= bestDistance then
						best, bestDistance = actor, d
					end
				end
			end
			if best then
				pickUp(egg, best)
			end
		end
	end
end

-- Flèche d'objectif de chaque joueur : son camp s'il porte un œuf, sinon
-- l'œuf libre le plus proche (ou le porteur adverse le plus proche)
local function updateObjectives()
	local ctx = context
	if not ctx then
		return
	end
	for _, actor in ctx.GetActors() do
		local root = ctx.GetRoot(actor)
		if not root or carrierOf(actor) or (actor.Character and actor.Character:GetAttribute("Carrying") ~= nil) then
			continue
		end
		local best, bestDistance = nil, math.huge
		for _, egg in eggs do
			local p = egg.State == "Carried" and egg.Carrier and egg.Carrier.Team ~= actor.Team and egg.LastPosition or (egg.State ~= "Carried" and egg.Pivot.Position or nil)
			if p then
				local d = (p - root.Position).Magnitude
				if d < bestDistance then
					best, bestDistance = p, d
				end
			end
		end
		ctx.SetActorObjective(actor, best)
	end
end

function EggRun.Start(ctx: MapContext, mapLayout: any)
	context = ctx
	layout = mapLayout
	running = true
	table.clear(eggs)
	table.clear(nestBusy)
	pending = 0
	ctx.SetScoreInfo(cfg.EggsToWin, "eggs")
	for _ = 1, math.min(cfg.ActiveEggs, #layout.Nests) do
		spawnRandom()
	end
	tick = 0
	objectiveTick = 0
	connection = RunService.Heartbeat:Connect(function(dt)
		if not running then
			return
		end
		tick += dt
		objectiveTick += dt
		if tick >= 0.1 then
			tick = 0
			update()
		end
		if objectiveTick >= 0.5 then
			objectiveTick = 0
			updateObjectives()
		end
	end)
end

function EggRun.Stop()
	running = false
	if connection then
		connection:Disconnect()
		connection = nil
	end
	for _, egg in eggs do
		releaseCarrier(egg)
		egg.Model:Destroy()
	end
	table.clear(eggs)
	table.clear(nestBusy)
	local ctx = context
	if ctx then
		for _, actor in ctx.GetActors() do
			ctx.SetActorObjective(actor, nil)
		end
	end
end

function EggRun.OnCapture(_hunter: Actor, victim: Actor)
	local egg = carrierOf(victim)
	if egg then
		local root = context and context.GetRoot(victim)
		drop(egg, root and root.Position or egg.LastPosition, "caught")
	end
end

function EggRun.OnActorRemoved(actor: Actor)
	local egg = carrierOf(actor)
	if egg then
		drop(egg, egg.LastPosition, "lost")
	end
end

function EggRun.ResolveTimeUp(): string?
	local ctx = context
	if not ctx then
		return nil
	end
	local best, bestScore, tie = nil, 0, false
	for _, teamId in Teams.Order do
		local value = ctx.GetScore(teamId)
		if value > bestScore then
			best, bestScore, tie = teamId, value, false
		elseif value == bestScore and value > 0 then
			tie = true
		end
	end
	return (not tie) and best or nil
end

function EggRun.GetBotGoal(actor: Actor): Vector3?
	local team = actor.Team
	if not team or not layout then
		return nil
	end
	if carrierOf(actor) then
		local base = layout.Bases and layout.Bases[team]
		return base and base.Center or nil
	end
	local ctx = context
	local root = ctx and ctx.GetRoot(actor)
	if not root then
		return nil
	end
	local best, bestDistance = nil, math.huge
	for _, egg in eggs do
		local p: Vector3? = nil
		if egg.State ~= "Carried" then
			p = egg.Pivot.Position
		elseif egg.Carrier and egg.Carrier.Team ~= team and Teams.CanCatch(team, egg.Carrier.Team :: string) then
			p = egg.LastPosition -- chasser un porteur qui est une proie
		end
		if p then
			local d = (p - root.Position).Magnitude
			if d < bestDistance then
				best, bestDistance = p, d
			end
		end
	end
	return best
end

function EggRun.IsCarrier(actor: Actor): boolean
	return carrierOf(actor) ~= nil
end

function EggRun.DebugState()
	local list = {}
	for _, egg in eggs do
		table.insert(list, { State = egg.State, Nest = egg.Nest, Carrier = egg.Carrier, Position = egg.Pivot.Position, Model = egg.Model })
	end
	return { Mode = "EggRun", Eggs = list, Pending = pending }
end

return EggRun

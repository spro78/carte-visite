--[[
	Carousel.lua - mode CAROUSEL (les chevaux volants)
	Le manège du centre a trois bras ; au bout de chacun, un cheval volant fait
	le tour de la vallée au-dessus de la piste (Config.Modes.Carousel). Sous
	chaque cheval, un anneau au sol suit sa course.
	  - chaque seconde, chaque anneau donne 1 point à l'équipe qui y a le plus
	    de joueurs debout (égalité ou anneau vide : personne) ;
	  - l'anneau prend la couleur de l'équipe qui le tient ;
	  - le manège change de sens régulièrement : on ne s'installe pas ;
	  - première équipe à PointsToWin : victoire ; au chrono, le plus de points.
	Pourquoi trois zones mobiles plutôt qu'une plateforme au centre : tout le
	serveur participe (trois points d'action qui passent devant chaque camp),
	personne n'attend au centre et la poursuite continue partout. La piste ne
	traverse aucune zone sûre : on n'y est jamais protégé.
]]

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Teams = require(Shared.Teams)
local Lang = require(Shared.Lang)
local Types = require(Shared.Types)
local Mechanics = require(Shared.Mechanics)
local Kit = require(script.Parent.Parent.Util.Kit)

type Actor = Types.Actor
type MapContext = Types.MapContext

local Carousel = {}

local cfg = Config.Modes.Carousel
local NEUTRAL = Color3.fromRGB(252, 248, 236)
local CONTESTED = Color3.fromRGB(196, 200, 214)

local context: MapContext? = nil
local layout: any = nil
local running = false
local connection: RBXScriptConnection? = nil
local scoreClock = 0
local objectiveClock = 0
local reverseClock = 0
local direction = 1
local holders: { [number]: string | false } = {} -- index de l'anneau -> équipe qui le tient
local inZone: { [string]: number } = {} -- id d'acteur -> index de l'anneau
local fills: { BasePart } = {}

local function speed(): number
	return direction * math.pi * 2 / cfg.TurnSeconds
end

-- Position au sol de l'anneau i (dans t secondes)
function Carousel.ZonePosition(index: number, ahead: number?): Vector3?
	if not layout or not layout.Spinner then
		return nil
	end
	local zone = layout.Zones[index]
	local offset = zone and zone:GetAttribute("RideAngle") or 0
	local now = workspace:GetServerTimeNow() + (ahead or 0)
	local angle = Mechanics.GetAngle(layout.Spinner, now) + offset
	return layout.Origin + Mechanics.Direction(angle) * layout.TrackRadius
end

-- Disque translucide sous l'anneau (aux couleurs de l'équipe qui le tient)
local function makeFill(index: number)
	local zone = layout.Zones[index]
	local base = layout.Spinner and layout.Spinner:GetAttribute("SpinBase")
	if not zone or typeof(base) ~= "CFrame" then
		return
	end
	-- Position dans le repère de l'angle 0 (celui du serveur, qui ne fait pas
	-- tourner le manège) : chaque client la replace dans son repère courant
	local rideAngle = zone:GetAttribute("RideAngle") or 0
	local ground = (base * CFrame.Angles(0, rideAngle, 0) * CFrame.new(layout.TrackRadius, 0, 0)).Position
	local fill = Instance.new("Part")
	fill.Name = "ZoneFill"
	fill.Shape = Enum.PartType.Cylinder
	fill.Size = Vector3.new(0.12, cfg.ZoneRadius * 2 - 1.6, cfg.ZoneRadius * 2 - 1.6)
	fill.CFrame = CFrame.new(ground + Vector3.new(0, 0.24, 0)) * CFrame.Angles(0, 0, math.pi / 2)
	fill.Anchored = true
	fill.CanCollide = false
	fill.CanQuery = false
	fill.CanTouch = false
	fill.CastShadow = false
	fill.Material = Enum.Material.SmoothPlastic
	fill.Color = NEUTRAL
	fill.Transparency = 0.72
	fill.Parent = zone
	fills[index] = fill
end

local function setHolder(index: number, team: string | false, contested: boolean)
	if holders[index] == team and not contested then
		return
	end
	holders[index] = team
	local zone = layout.Zones[index]
	local def = team and Teams.Get(team)
	local color = def and def.Color or (contested and CONTESTED or NEUTRAL)
	if zone then
		Kit.SetRoleColor(zone, "Zone", color)
		zone:SetAttribute("HeldBy", team or nil)
	end
	local fill = fills[index]
	if fill then
		fill.Color = color
		fill.Transparency = def and 0.55 or 0.72
	end
end

local function award()
	local ctx = context
	if not ctx then
		return
	end
	table.clear(inZone)
	local centers = {}
	for index in layout.Zones do
		centers[index] = Carousel.ZonePosition(index)
	end
	local counts: { [number]: { [string]: number } } = {}
	for _, actor in ctx.GetActors() do
		local root = ctx.GetRoot(actor)
		local team = actor.Team
		if not root or not team then
			continue
		end
		for index, center in centers do
			local flatDelta = Vector3.new(root.Position.X - center.X, 0, root.Position.Z - center.Z)
			if flatDelta.Magnitude <= cfg.ZoneRadius and math.abs(root.Position.Y - center.Y - 3) < 8 then
				counts[index] = counts[index] or {}
				counts[index][team] = (counts[index][team] or 0) + 1
				inZone[actor.Id] = index
				break
			end
		end
	end
	for index in layout.Zones do
		local best, bestCount, tie = nil, 0, false
		for _, teamId in Teams.Order do
			local n = counts[index] and counts[index][teamId] or 0
			if n > bestCount then
				best, bestCount, tie = teamId, n, false
			elseif n == bestCount and n > 0 then
				tie = true
			end
		end
		if best and not tie then
			setHolder(index, best, false)
			ctx.AddScore(best, 1)
			local total = ctx.GetScore(best)
			if total >= cfg.PointsToWin then
				ctx.EndRound(best, "Objective")
				return
			end
			if total % 30 == 0 then
				local def = Teams.Get(best)
				if def then
					ctx.Announce(Lang.F("%s: %d points!", def.Plural, total), def.Color)
				end
			end
		else
			setHolder(index, false, tie)
		end
	end
end

-- Flèche d'objectif : l'anneau le plus proche (un peu en avance sur sa course)
local function updateObjectives()
	local ctx = context
	if not ctx then
		return
	end
	for _, actor in ctx.GetActors() do
		local root = ctx.GetRoot(actor)
		if root and not (actor.Character and actor.Character:GetAttribute("Carrying") ~= nil) then
			local best, bestDistance = nil, math.huge
			for index in layout.Zones do
				local p = Carousel.ZonePosition(index, 1)
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
end

function Carousel.Start(ctx: MapContext, mapLayout: any)
	context = ctx
	layout = mapLayout
	running = true
	direction = 1
	scoreClock, objectiveClock, reverseClock = 0, 0, 0
	table.clear(holders)
	table.clear(inZone)
	table.clear(fills)
	ctx.SetScoreInfo(cfg.PointsToWin, "points")
	if layout.Spinner then
		Mechanics.SetSpin(layout.Spinner, speed())
	end
	for index in layout.Zones do
		makeFill(index)
		setHolder(index, false, false)
	end
	connection = RunService.Heartbeat:Connect(function(dt)
		if not running then
			return
		end
		scoreClock += dt
		objectiveClock += dt
		reverseClock += dt
		if scoreClock >= cfg.ScoreInterval then
			scoreClock -= cfg.ScoreInterval
			award()
		end
		if objectiveClock >= 0.5 then
			objectiveClock = 0
			updateObjectives()
		end
		if cfg.ReverseEverySeconds > 0 and reverseClock >= cfg.ReverseEverySeconds then
			reverseClock = 0
			direction = -direction
			if layout.Spinner then
				Mechanics.SetSpin(layout.Spinner, speed())
			end
			ctx.Announce(Lang.T("The carousel turns the other way!"), Color3.fromRGB(255, 226, 160))
		end
	end)
end

function Carousel.Stop()
	running = false
	if connection then
		connection:Disconnect()
		connection = nil
	end
	if layout then
		for index in layout.Zones do
			setHolder(index, false, false)
		end
	end
	for _, fill in fills do
		fill:Destroy()
	end
	table.clear(fills)
	local ctx = context
	if ctx then
		for _, actor in ctx.GetActors() do
			ctx.SetActorObjective(actor, nil)
		end
	end
end

function Carousel.ResolveTimeUp(): string?
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

-- Les bots visent l'anneau le plus proche, là où il sera dans 2 secondes
function Carousel.GetBotGoal(actor: Actor): Vector3?
	local ctx = context
	local root = ctx and ctx.GetRoot(actor)
	if not root or not layout then
		return nil
	end
	local best, bestDistance = nil, math.huge
	for index in layout.Zones do
		local p = Carousel.ZonePosition(index, 2)
		if p then
			local d = (p - root.Position).Magnitude
			if d < bestDistance then
				best, bestDistance = p, d
			end
		end
	end
	return best
end

function Carousel.InZone(actor: Actor): number?
	return inZone[actor.Id]
end

function Carousel.DebugState()
	return { Mode = "Carousel", Holders = holders, InZone = inZone, Direction = direction }
end

return Carousel

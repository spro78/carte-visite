--[[
	CaptureService.lua
	Captures et conversions. Le serveur décide de tout :
	  - une boucle serveur détecte les contacts chasseur/proie (joueurs et bots),
	  - un client peut signaler un contact (CaptureAttempt) pour plus de réactivité :
	    l'intention est revalidée ici (distance, équipes, protections, recharge).
	Une capture convertit la proie : elle rejoint l'équipe du chasseur et change
	d'animal sur place, avec quelques secondes d'invincibilité.
]]

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Remotes = require(Shared.Remotes)
local Teams = require(Shared.Teams)
local Types = require(Shared.Types)
local ActorService = require(script.Parent.ActorService)
local TeamService = require(script.Parent.TeamService)
local AbilityService = require(script.Parent.AbilityService)
local RoundState = require(script.Parent.RoundState)
local RateLimiter = require(script.Parent.RateLimiter)
local Signal = require(script.Parent.Parent.Util.Signal)

type Actor = Types.Actor

local CaptureService = {}

CaptureService.Captured = Signal.new() -- (hunter: Actor, victim: Actor)

-- Fonctions appelées avant une capture ; si l'une retourne false, la capture
-- est annulée (bouclier, etc.).
local guards: { (hunter: Actor, victim: Actor) -> boolean } = {}
local lastCapture: { [string]: number } = {}

-- ---------------------------------------------------------------------------
-- Protection (invincibilité temporaire, ForceField visible)
-- ---------------------------------------------------------------------------
function CaptureService.Protect(character: Model, seconds: number)
	local untilTime = os.clock() + seconds
	local current = character:GetAttribute("ProtectedUntil")
	if type(current) == "number" and current > untilTime then
		return
	end
	character:SetAttribute("ProtectedUntil", untilTime)
	local field = character:FindFirstChildOfClass("ForceField")
	if not field then
		field = Instance.new("ForceField")
		field.Visible = true
		field.Parent = character
	end
	task.delay(seconds, function()
		local latest = character:GetAttribute("ProtectedUntil")
		if type(latest) == "number" and latest <= os.clock() + 0.01 then
			local existing = character:FindFirstChildOfClass("ForceField")
			if existing then
				existing:Destroy()
			end
		end
	end)
end

function CaptureService.IsProtected(character: Model): boolean
	local untilTime = character:GetAttribute("ProtectedUntil")
	return type(untilTime) == "number" and untilTime > os.clock()
end

function CaptureService.ClearProtection(character: Model)
	character:SetAttribute("ProtectedUntil", nil)
	local existing = character:FindFirstChildOfClass("ForceField")
	if existing then
		existing:Destroy()
	end
end

function CaptureService.AddGuard(guard: (hunter: Actor, victim: Actor) -> boolean)
	table.insert(guards, guard)
end

-- ---------------------------------------------------------------------------
-- Règles
-- ---------------------------------------------------------------------------
local function horizontalDistance(a: Vector3, b: Vector3): number
	return Vector3.new(a.X - b.X, 0, a.Z - b.Z).Magnitude
end

-- Vérifie toutes les règles d'une capture. extraRange : tolérance réseau.
function CaptureService.CanCapture(hunter: Actor, victim: Actor, extraRange: number?): boolean
	if not RoundState.IsActive() then
		return false
	end
	if hunter == victim or not RoundState.IsParticipant(hunter) or not RoundState.IsParticipant(victim) then
		return false
	end
	if not Teams.CanCatch(hunter.Team, victim.Team) then
		return false
	end
	if not ActorService.IsAlive(hunter) or not ActorService.IsAlive(victim) then
		return false
	end
	local hunterChar = hunter.Character :: Model
	local victimChar = victim.Character :: Model
	if CaptureService.IsProtected(victimChar) then
		return false
	end
	-- Un chasseur fraîchement converti (protégé) ne peut pas attraper tout de suite
	if CaptureService.IsProtected(hunterChar) then
		return false
	end
	if hunterChar:GetAttribute("Frozen") == true then
		return false
	end
	local last = lastCapture[hunter.Id]
	if last and os.clock() - last < Config.Capture.CooldownSeconds then
		return false
	end
	local a = ActorService.GetPosition(hunter)
	local b = ActorService.GetPosition(victim)
	if not a or not b then
		return false
	end
	if math.abs(a.Y - b.Y) > Config.Capture.MaxVerticalGap then
		return false
	end
	local range = AbilityService.GetCaptureRange(hunter) + (extraRange or 0)
	return horizontalDistance(a, b) <= range
end

-- Effectue la capture (les règles doivent avoir été vérifiées).
local function capture(hunter: Actor, victim: Actor)
	for _, guard in guards do
		if guard(hunter, victim) == false then
			lastCapture[hunter.Id] = os.clock()
			return
		end
	end
	lastCapture[hunter.Id] = os.clock()
	local newTeam = hunter.Team :: string
	local def = Teams.Get(newTeam)
	assert(def)

	TeamService.SetTeam(victim, newTeam)
	victim.LastCaughtAt = os.clock()
	hunter.RoundCaptures += 1
	AbilityService.ClearModifiers(victim)
	AbilityService.ResetCooldowns(victim)
	if victim.Character then
		CaptureService.Protect(victim.Character, Config.Capture.InvincibilitySeconds)
		victim.Character:SetAttribute("Carrier", nil)
	end

	local announce = Remotes.Get("Announce")
	ActorService.FireClient(victim, announce, "You were caught! You are now a " .. def.Display .. "!", def.Color)
	ActorService.FireClient(hunter, announce, "Caught " .. victim.Name .. "!", Teams.PreyOutlineColor)
	local position = ActorService.GetPosition(victim)
	Remotes.Get("Effect"):FireAllClients("Capture", {
		Position = position,
		Team = newTeam,
		HunterId = hunter.Id,
		VictimId = victim.Id,
	})
	CaptureService.Captured:Fire(hunter, victim)
end

function CaptureService.TryCapture(hunter: Actor, victim: Actor, extraRange: number?): boolean
	if CaptureService.CanCapture(hunter, victim, extraRange) then
		capture(hunter, victim)
		return true
	end
	return false
end

-- ---------------------------------------------------------------------------
-- Boucle de détection serveur
-- ---------------------------------------------------------------------------
local accumulator = 0

local function scan()
	local actors = RoundState.GetActiveParticipants()
	if #actors < 2 then
		return
	end
	-- Regroupe par équipe pour ne comparer que chasseur/proie
	local byTeam: { [string]: { Actor } } = {}
	for _, actor in actors do
		local team = actor.Team :: string
		byTeam[team] = byTeam[team] or {}
		table.insert(byTeam[team], actor)
	end
	local converted: { [string]: boolean } = {}
	for _, hunter in actors do
		if converted[hunter.Id] then
			continue
		end
		local prey = Teams.GetPrey(hunter.Team :: string)
		for _, victim in (prey and byTeam[prey]) or {} do
			if not converted[victim.Id] and victim.Team == prey and CaptureService.CanCapture(hunter, victim) then
				capture(hunter, victim)
				converted[victim.Id] = true
				break
			end
		end
	end
end

function CaptureService.Init()
	RunService.Heartbeat:Connect(function(dt)
		if not RoundState.IsActive() then
			accumulator = 0
			return
		end
		accumulator += dt
		if accumulator < Config.Capture.CheckInterval then
			return
		end
		accumulator = 0
		scan()
	end)

	-- Intention d'un client : "je touche cette cible"
	Remotes.Get("CaptureAttempt").OnServerEvent:Connect(function(player: Player, target: any)
		if not RateLimiter.Allow(player, "Capture", 15) then
			return
		end
		if typeof(target) ~= "Instance" or not target:IsA("Model") then
			return
		end
		local hunter = ActorService.FromPlayer(player)
		local victim = ActorService.FromCharacter(target)
		if hunter and victim then
			CaptureService.TryCapture(hunter, victim, Config.Capture.ClientTolerance)
		end
	end)

	ActorService.ActorRemoving:Connect(function(actor: Actor)
		lastCapture[actor.Id] = nil
	end)
end

function CaptureService.ResetRound()
	table.clear(lastCapture)
end

return CaptureService

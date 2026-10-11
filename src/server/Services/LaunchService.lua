--[[
	LaunchService.lua
	Éjections (bras tournant, catapulte, geysers, plateforme...).
	Le serveur décide de l'éjection ; la physique est appliquée par le
	propriétaire du personnage : le client pour un joueur, le serveur pour un bot.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Remotes = require(Shared.Remotes)
local Movement = require(Shared.Movement)
local Types = require(Shared.Types)
local ActorService = require(script.Parent.ActorService)

type Actor = Types.Actor

local LaunchService = {}

local lastLaunch: { [string]: number } = {}

-- Retourne true si l'éjection a été appliquée.
function LaunchService.Launch(actor: Actor, velocity: Vector3, ragdollSeconds: number?, ignoreCooldown: boolean?): boolean
	local character = actor.Character
	if not character or not ActorService.IsAlive(actor) then
		return false
	end
	local now = os.clock()
	if not ignoreCooldown and lastLaunch[actor.Id] and now - lastLaunch[actor.Id] < Config.Launch.Cooldown then
		return false
	end
	lastLaunch[actor.Id] = now
	local ragdoll = ragdollSeconds or Config.Launch.DefaultRagdollSeconds
	if actor.Player then
		Remotes.Get("Launch"):FireClient(actor.Player, velocity, ragdoll)
	else
		Movement.Launch(character, velocity, ragdoll)
	end
	local root = ActorService.GetRoot(actor)
	if root then
		Remotes.Get("Effect"):FireAllClients("Launch", { Position = root.Position })
	end
	return true
end

-- Vitesse initiale pour atteindre "target" depuis "from" en "flightTime" secondes.
function LaunchService.BallisticVelocity(from: Vector3, target: Vector3, flightTime: number): Vector3
	local gravity = workspace.Gravity
	local delta = target - from
	local horizontal = Vector3.new(delta.X, 0, delta.Z) / flightTime
	local vertical = (delta.Y + 0.5 * gravity * flightTime * flightTime) / flightTime
	return Vector3.new(horizontal.X, vertical, horizontal.Z)
end

function LaunchService.Forget(actor: Actor)
	lastLaunch[actor.Id] = nil
end

return LaunchService

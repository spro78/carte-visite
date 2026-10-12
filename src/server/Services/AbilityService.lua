--[[
	AbilityService.lua
	Valide et exécute les intentions de mouvement spécial et de capacité :
	  - Dash latéral (joueurs : prédit par le client, validé ici ; bots : exécuté ici)
	  - Capacité d'animal : FOX sprint, CHICKEN saut plané, SNAKE morsure
	Gère aussi les modificateurs de vitesse (sprint, morsure, porteur, boost...),
	publiés dans l'attribut "SpeedMult" du personnage.
	Les temps de recharge sont publiés en temps serveur dans les attributs
	"DashReadyAt" et "AbilityReadyAt" (lus par l'interface).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Remotes = require(Shared.Remotes)
local Movement = require(Shared.Movement)
local Teams = require(Shared.Teams)
local Types = require(Shared.Types)
local ActorService = require(script.Parent.ActorService)
local RoundState = require(script.Parent.RoundState)
local RateLimiter = require(script.Parent.RateLimiter)
local SafeZoneService = require(script.Parent.SafeZoneService)

type Actor = Types.Actor

local AbilityService = {}

-- Tolérance (secondes) sur les temps de recharge prédits par le client
local CLIENT_COOLDOWN_TOLERANCE = 0.3

type Modifier = { Multiplier: number, Token: number }
local modifiers: { [string]: { [string]: Modifier } } = {}
local tokenCounter = 0
local violations: { [string]: number } = {}

local function serverNow(): number
	return workspace:GetServerTimeNow()
end

-- ---------------------------------------------------------------------------
-- Statistiques de base : IDENTIQUES pour tous les joueurs. Aucun achat ne
-- modifie la vitesse, le dash ou la portée de capture (seule l'adresse compte).
-- ---------------------------------------------------------------------------
function AbilityService.GetBaseSpeedMultiplier(_actor: Actor): number
	return 1
end

function AbilityService.GetDashCooldown(_actor: Actor): number
	return Config.Movement.DashCooldown
end

function AbilityService.GetCaptureRange(_actor: Actor): number
	return Config.Capture.Range
end

-- ---------------------------------------------------------------------------
-- Modificateurs de vitesse
-- ---------------------------------------------------------------------------
local function recompute(actor: Actor)
	local mult = AbilityService.GetBaseSpeedMultiplier(actor)
	local list = modifiers[actor.Id]
	if list then
		for _, modifier in list do
			mult *= modifier.Multiplier
		end
	end
	ActorService.SetCharacterAttribute(actor, "SpeedMult", mult)
end

-- Ajoute (ou remplace) un modificateur. duration nil = jusqu'à suppression.
function AbilityService.SetSpeedModifier(actor: Actor, key: string, multiplier: number?, duration: number?)
	local list = modifiers[actor.Id]
	if not list then
		list = {}
		modifiers[actor.Id] = list
	end
	if multiplier == nil then
		list[key] = nil
		recompute(actor)
		return
	end
	tokenCounter += 1
	local token = tokenCounter
	list[key] = { Multiplier = multiplier, Token = token }
	recompute(actor)
	if duration then
		task.delay(duration, function()
			local current = modifiers[actor.Id]
			if current and current[key] and current[key].Token == token then
				current[key] = nil
				recompute(actor)
			end
		end)
	end
end

function AbilityService.ClearModifiers(actor: Actor)
	modifiers[actor.Id] = nil
	recompute(actor)
end

-- Publie sur le personnage les valeurs dérivées des améliorations.
function AbilityService.RefreshCharacter(actor: Actor)
	ActorService.SetCharacterAttribute(actor, "DashCooldown", AbilityService.GetDashCooldown(actor))
	ActorService.SetCharacterAttribute(actor, "CaptureRange", AbilityService.GetCaptureRange(actor))
	recompute(actor)
end

-- ---------------------------------------------------------------------------
-- Dash
-- ---------------------------------------------------------------------------
local function canMove(actor: Actor): boolean
	local character = actor.Character
	if not character or not ActorService.IsAlive(actor) then
		return false
	end
	if character:GetAttribute("Frozen") == true or character:GetAttribute("Downed") == true or Movement.IsRagdolled(character) then
		return false
	end
	return true
end

-- Retourne true si le dash est accepté. execute = appliquer la physique ici (bots).
function AbilityService.TryDash(actor: Actor, side: number, execute: boolean): boolean
	if not canMove(actor) then
		return false
	end
	local character = actor.Character :: Model
	local readyAt = character:GetAttribute("DashReadyAt")
	local tolerance = execute and 0 or CLIENT_COOLDOWN_TOLERANCE
	if type(readyAt) == "number" and serverNow() < readyAt - tolerance then
		violations[actor.Id] = (violations[actor.Id] or 0) + 1
		return false
	end
	character:SetAttribute("DashReadyAt", serverNow() + AbilityService.GetDashCooldown(actor))
	if execute then
		Movement.Dash(character, side)
	end
	Remotes.Get("Effect"):FireAllClients("Dash", { ActorId = actor.Id })
	return true
end

-- ---------------------------------------------------------------------------
-- Capacités d'animal
-- ---------------------------------------------------------------------------
-- Ennemi le plus proche que l'on peut viser : ni à terre (exclus des
-- participants actifs) ni à l'abri dans la zone sûre de son camp
local function closestEnemy(actor: Actor, range: number): Actor?
	local origin = ActorService.GetPosition(actor)
	if not origin then
		return nil
	end
	local best, bestDistance = nil, range
	for _, other in RoundState.GetActiveParticipants() do
		if other ~= actor and other.Team ~= actor.Team and not SafeZoneService.IsSafe(other) then
			local position = ActorService.GetPosition(other)
			if position then
				local distance = (position - origin).Magnitude
				if distance <= bestDistance then
					best, bestDistance = other, distance
				end
			end
		end
	end
	return best
end

local abilityHandlers: { [string]: (Actor, boolean) -> boolean } = {
	FOX = function(actor)
		local cfg = Config.Abilities.FOX
		AbilityService.SetSpeedModifier(actor, "Sprint", cfg.SpeedMultiplier, cfg.Duration)
		ActorService.SetCharacterAttribute(actor, "SprintUntil", serverNow() + cfg.Duration)
		return true
	end,
	CHICKEN = function(actor, execute)
		-- Les joueurs appliquent la physique eux-mêmes (prédiction) ; le serveur
		-- l'applique pour les bots.
		if execute and actor.Character then
			Movement.GlideJump(actor.Character)
		end
		return true
	end,
	SNAKE = function(actor)
		local cfg = Config.Abilities.SNAKE
		local target = closestEnemy(actor, cfg.Range)
		if not target or not target.Character then
			return true -- capacité consommée même dans le vide (pas de spam)
		end
		local protectedUntil = target.Character:GetAttribute("ProtectedUntil")
		if type(protectedUntil) == "number" and protectedUntil > os.clock() then
			return true
		end
		AbilityService.SetSpeedModifier(target, "Bite", cfg.SlowMultiplier, cfg.SlowDuration)
		ActorService.SetCharacterAttribute(target, "SlowedUntil", serverNow() + cfg.SlowDuration)
		ActorService.FireClient(target, Remotes.Get("Announce"), "Bitten! You are slowed!", Teams.Defs.SNAKE.Color)
		Remotes.Get("Effect"):FireAllClients("Bite", { From = actor.Id, To = target.Id })
		return true
	end,
}

function AbilityService.TryAbility(actor: Actor, execute: boolean): boolean
	if not RoundState.IsActive() or not RoundState.IsParticipant(actor) then
		return false
	end
	if not canMove(actor) or not actor.Team then
		return false
	end
	local character = actor.Character :: Model
	local readyAt = character:GetAttribute("AbilityReadyAt")
	local tolerance = execute and 0 or CLIENT_COOLDOWN_TOLERANCE
	if type(readyAt) == "number" and serverNow() < readyAt - tolerance then
		violations[actor.Id] = (violations[actor.Id] or 0) + 1
		return false
	end
	local handler = abilityHandlers[actor.Team]
	local cfg = Config.Abilities[actor.Team]
	if not handler or not cfg then
		return false
	end
	if not handler(actor, execute) then
		return false
	end
	character:SetAttribute("AbilityReadyAt", serverNow() + cfg.Cooldown)
	Remotes.Get("Effect"):FireAllClients("Ability", { ActorId = actor.Id, Team = actor.Team })
	return true
end

-- Réinitialise les temps de recharge (nouvelle manche, conversion)
function AbilityService.ResetCooldowns(actor: Actor)
	ActorService.SetCharacterAttribute(actor, "AbilityReadyAt", nil)
	ActorService.SetCharacterAttribute(actor, "DashReadyAt", nil)
end

function AbilityService.GetViolations(actor: Actor): number
	return violations[actor.Id] or 0
end

-- ---------------------------------------------------------------------------
-- Init : intentions des joueurs
-- ---------------------------------------------------------------------------
function AbilityService.Init()
	Remotes.Get("RequestDash").OnServerEvent:Connect(function(player: Player, side: any)
		if not RateLimiter.Allow(player, "Dash", 6) then
			return
		end
		if side ~= -1 and side ~= 1 then
			return
		end
		local actor = ActorService.FromPlayer(player)
		if actor then
			AbilityService.TryDash(actor, side, false)
		end
	end)

	Remotes.Get("RequestAbility").OnServerEvent:Connect(function(player: Player)
		if not RateLimiter.Allow(player, "Ability", 6) then
			return
		end
		local actor = ActorService.FromPlayer(player)
		if actor then
			AbilityService.TryAbility(actor, false)
		end
	end)

	ActorService.CharacterAdded:Connect(function(actor: Actor)
		AbilityService.RefreshCharacter(actor)
	end)
	ActorService.ActorRemoving:Connect(function(actor: Actor)
		modifiers[actor.Id] = nil
		violations[actor.Id] = nil
	end)
end

return AbilityService

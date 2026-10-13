--[[
	RescueService.lua
	Mise à terre, portage et réanimation : il n'y a ni prison ni cachot.
	Règle retenue (documentée dans README.md, section « Règles du jeu ») :
	  1. Un joueur attrapé est À TERRE (CaptureService appelle Down) : couché là
	     où il a été attrapé, il ne bouge plus, ne peut plus être attrapé et ne
	     compte plus pour les objectifs. Il reste dans son équipe.
	  2. Un coéquipier debout, à moins de Config.Rescue.PickupRange studs, peut le
	     PORTER (touche C, bouton Y de la manette, bouton CARRY en tactile ;
	     remote RequestCarry). Le porteur est ralenti, ne peut pas attraper et
	     peut lâcher (même commande). Le chrono est suspendu pendant le portage.
	  3. Dès que le porteur entre dans la zone sûre de leur camp, le joueur porté
	     se RELÈVE sur la plateforme, dans son équipe, protégé quelques secondes.
	  4. Sans secours à temps (Config.Rescue.BleedOutSeconds), ou si plus aucun
	     coéquipier n'est debout, il rejoint l'équipe qui l'a attrapé et se relève
	     sur place, protégé : c'est la conversion d'origine, appliquée une seule
	     fois, à la fin. Personne ne reste bloqué.
	  5. Un porteur attrapé lâche son coéquipier (au sol, avec au moins
	     Config.Rescue.DropGraceSeconds de chrono). Réapparaître (reset) pendant
	     qu'on est à terre vaut abandon : conversion immédiate.
	Physique : un joueur à terre a sa HumanoidRootPart ancrée (couché sur le
	dos) ; porté, elle est soudée (Weld) sur l'épaule du porteur, qui devient
	propriétaire réseau de l'ensemble. Tout est rétabli quand il se relève.
	Attributs répliqués (lus par l'interface) :
	  joueur à terre : Downed, DownedUntil (temps serveur), DownedBy, CarriedBy
	  porteur        : Carrying (pseudo du joueur porté), ObjectiveTarget (sa base)
]]

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Remotes = require(Shared.Remotes)
local Teams = require(Shared.Teams)
local Lang = require(Shared.Lang)
local Types = require(Shared.Types)
local ActorService = require(script.Parent.ActorService)
local TeamService = require(script.Parent.TeamService)
local AbilityService = require(script.Parent.AbilityService)
local CaptureService = require(script.Parent.CaptureService)
local RoundState = require(script.Parent.RoundState)
local RateLimiter = require(script.Parent.RateLimiter)
local SafeZoneService = require(script.Parent.SafeZoneService)
local Signal = require(script.Parent.Parent.Util.Signal)

type Actor = Types.Actor

type SavedPart = { CanCollide: boolean, Massless: boolean }
export type Entry = {
	Actor: Actor,
	Character: Model,
	CatcherTeam: string,
	CatcherName: string,
	Deadline: number?, -- os.clock() de la conversion ; nil pendant le portage
	Remaining: number, -- temps restant, figé pendant le portage
	Carrier: Actor?,
	Weld: Weld?,
	Saved: { [BasePart]: SavedPart },
}

local RescueService = {}

RescueService.Downed = Signal.new() -- (victim: Actor, hunter: Actor)
RescueService.Revived = Signal.new() -- (victim: Actor, rescuer: Actor?)
RescueService.Converted = Signal.new() -- (victim: Actor, newTeam: string, reason: string)

local downed: { [string]: Entry } = {} -- id du joueur à terre -> état
local carriedBy: { [string]: Entry } = {} -- id du porteur -> état du joueur porté
local accumulator = 0

-- Sur l'épaule droite du porteur : à plat ventre, tête dans son dos, jambes
-- devant lui (colonnes : droite, haut, arrière du joueur porté)
local CARRY_OFFSET = CFrame.fromMatrix(Vector3.new(1.6, 1.75, 0), Vector3.new(-1, 0, 0), Vector3.new(0, 0, 1), Vector3.new(0, 1, 0))
local LYING_HEIGHT = 0.9 -- hauteur de la racine au-dessus du sol, couché
local STANDING_HEIGHT = 3 -- hauteur de la racine au-dessus du sol, debout

-- ---------------------------------------------------------------------------
-- Outils
-- ---------------------------------------------------------------------------
local function serverNow(): number
	return workspace:GetServerTimeNow()
end

local function getRoot(character: Model): BasePart?
	local root = character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return root
	end
	return nil
end

local function getHumanoid(character: Model): Humanoid?
	return character:FindFirstChildOfClass("Humanoid")
end

local function yawOf(cframe: CFrame): number
	local look = cframe.LookVector
	if math.abs(look.X) + math.abs(look.Z) < 1e-3 then
		look = cframe.UpVector
	end
	return math.atan2(-look.X, -look.Z)
end

-- Déplace le personnage pour que sa racine arrive exactement sur target
local function moveRootTo(character: Model, root: BasePart, target: CFrame)
	character:PivotTo(target * root.CFrame:Inverse() * character:GetPivot())
end

-- Propriétaire réseau : le joueur lui-même, sinon le serveur (bots)
local function setOwner(root: BasePart, player: Player?)
	pcall(function()
		root:SetNetworkOwner(player)
	end)
end

-- Sol sous une position (personnages et pièces traversables ignorés)
local function groundBelow(position: Vector3): Vector3
	local ignore = {}
	for _, actor in ActorService.GetAll() do
		if actor.Character then
			table.insert(ignore, actor.Character)
		end
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = ignore
	params.RespectCanCollide = true
	local result = workspace:Raycast(position + Vector3.new(0, 2, 0), Vector3.new(0, -80, 0), params)
	if result then
		return result.Position
	end
	return Vector3.new(position.X, Config.World.MapOrigin.Y, position.Z)
end

local function standingCFrame(position: Vector3, yaw: number): CFrame
	local floor = groundBelow(position)
	return CFrame.new(floor + Vector3.new(0, STANDING_HEIGHT, 0)) * CFrame.Angles(0, yaw, 0)
end

-- Le corps à terre ne gêne personne et ne pèse rien sur l'épaule du porteur
local function saveParts(entry: Entry)
	for _, descendant in entry.Character:GetDescendants() do
		if descendant:IsA("BasePart") and entry.Saved[descendant] == nil then
			entry.Saved[descendant] = { CanCollide = descendant.CanCollide, Massless = descendant.Massless }
			descendant.CanCollide = false
			descendant.Massless = true
		end
	end
end

local function restoreParts(entry: Entry)
	for part, saved in entry.Saved do
		if part.Parent then
			part.CanCollide = saved.CanCollide
			part.Massless = saved.Massless
		end
	end
	table.clear(entry.Saved)
end

local function publishTimer(entry: Entry)
	local deadline = entry.Deadline
	entry.Character:SetAttribute("DownedUntil", deadline and (serverNow() + math.max(0, deadline - os.clock())) or nil)
end

local function announceTo(actor: Actor, text: string, color: Color3?)
	ActorService.FireClient(actor, Remotes.Get("Announce"), text, color)
end

-- Couche le personnage sur le dos à la position donnée (racine ancrée)
local function layDown(entry: Entry, position: Vector3, yaw: number?)
	local character = entry.Character
	local root = getRoot(character)
	if not root then
		return
	end
	if entry.Weld then
		entry.Weld:Destroy()
		entry.Weld = nil
	end
	local facing = yaw or yawOf(root.CFrame)
	local floor = groundBelow(position)
	root.Anchored = true
	root.AssemblyLinearVelocity = Vector3.zero
	root.AssemblyAngularVelocity = Vector3.zero
	local humanoid = getHumanoid(character)
	if humanoid then
		humanoid.PlatformStand = true
	end
	moveRootTo(character, root, CFrame.new(floor + Vector3.new(0, LYING_HEIGHT, 0)) * CFrame.Angles(0, facing, 0) * CFrame.Angles(math.rad(90), 0, 0))
end

-- Le porteur n'en est plus un (soudure, ralentissement, flèche, attributs)
local function releaseCarrier(entry: Entry)
	local carrier = entry.Carrier
	if entry.Weld then
		entry.Weld:Destroy()
		entry.Weld = nil
	end
	entry.Character:SetAttribute("CarriedBy", nil)
	if not carrier then
		return
	end
	entry.Carrier = nil
	if carriedBy[carrier.Id] == entry then
		carriedBy[carrier.Id] = nil
	end
	AbilityService.SetSpeedModifier(carrier, "Carry", nil)
	ActorService.SetCharacterAttribute(carrier, "Carrying", nil)
	ActorService.SetCharacterAttribute(carrier, "ObjectiveTarget", nil)
end

-- Relève le personnage (fin de l'état à terre), debout en target
local function standUp(entry: Entry, target: CFrame?)
	local actor = entry.Actor
	if downed[actor.Id] == entry then
		downed[actor.Id] = nil
	end
	releaseCarrier(entry)
	local character = entry.Character
	restoreParts(entry)
	character:SetAttribute("Downed", nil)
	character:SetAttribute("DownedUntil", nil)
	character:SetAttribute("DownedBy", nil)
	if character.Parent == nil then
		return
	end
	local root = getRoot(character)
	if root then
		root.Anchored = false
		moveRootTo(character, root, target or standingCFrame(root.Position, yawOf(root.CFrame)))
		root.AssemblyLinearVelocity = Vector3.zero
		root.AssemblyAngularVelocity = Vector3.zero
		setOwner(root, actor.Player)
	end
	local humanoid = getHumanoid(character)
	if humanoid then
		humanoid.PlatformStand = false
		humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
	end
	actor.LastCaughtAt = os.clock() -- la course recommence (distinction « plus longue survie »)
end

-- Point d'apparition du camp le plus proche d'une position
local function nearestSpawn(teamId: string, position: Vector3): CFrame?
	local map = RoundState.Map
	local spawns = map and map.GetSpawns and map.GetSpawns(teamId)
	if not spawns or #spawns == 0 then
		return nil
	end
	local best, bestDistance = nil, math.huge
	for _, cframe in spawns do
		local d = (cframe.Position - position).Magnitude
		if d < bestDistance then
			best, bestDistance = cframe, d
		end
	end
	return best
end

-- Un coéquipier de cette équipe est-il encore debout pour porter ?
local function hasRescuer(teamId: string, except: Actor): boolean
	for _, actor in RoundState.GetParticipants() do
		if actor ~= except and actor.Team == teamId and downed[actor.Id] == nil and ActorService.IsAlive(actor) then
			return true
		end
	end
	return false
end

-- ---------------------------------------------------------------------------
-- API
-- ---------------------------------------------------------------------------
function RescueService.IsDown(actor: Actor): boolean
	return downed[actor.Id] ~= nil
end

-- Joueur porté par cet acteur (nil s'il ne porte personne)
function RescueService.GetCarried(carrier: Actor): Actor?
	local entry = carriedBy[carrier.Id]
	return entry and entry.Actor or nil
end

-- Liste des joueurs à terre (pour les bots et les tests)
function RescueService.GetDowned(): { Entry }
	local list = {}
	for _, entry in downed do
		table.insert(list, entry)
	end
	return list
end

-- Met l'acteur à terre (appelé par CaptureService à chaque capture)
function RescueService.Down(victim: Actor, hunter: Actor)
	local character = victim.Character
	local root = character and getRoot(character)
	if not character or not root or downed[victim.Id] then
		return
	end
	-- Un porteur attrapé lâche d'abord son coéquipier
	if carriedBy[victim.Id] then
		RescueService.Drop(victim)
	end
	local entry: Entry = {
		Actor = victim,
		Character = character,
		CatcherTeam = hunter.Team :: string,
		CatcherName = hunter.Name,
		Deadline = os.clock() + Config.Rescue.BleedOutSeconds,
		Remaining = Config.Rescue.BleedOutSeconds,
		Carrier = nil,
		Weld = nil,
		Saved = {},
	}
	downed[victim.Id] = entry
	local theirs = Teams.Get(hunter.Team)
	announceTo(hunter, Lang.F("You caught %s!", victim.Name), theirs and theirs.Color)
	RescueService.Downed:Fire(victim, hunter)
	-- Plus aucun coéquipier debout : personne ne pourra le porter, la règle
	-- d'origine s'applique tout de suite (il ne reste pas couché pour rien)
	if not hasRescuer(victim.Team :: string, victim) then
		RescueService.Convert(entry, "NoRescuer")
		return
	end
	saveParts(entry)
	layDown(entry, root.Position)
	character:SetAttribute("Downed", true)
	character:SetAttribute("DownedBy", hunter.Name)
	character:SetAttribute("SafeZone", nil)
	publishTimer(entry)
	local mine = Teams.Get(victim.Team)
	announceTo(victim, Lang.F("%s caught you! A teammate can carry you home.", hunter.Name), mine and mine.Color)
end

-- Vrai si l'acteur peut ramasser un coéquipier maintenant
function RescueService.CanCarry(carrier: Actor): boolean
	if not RoundState.IsActive() or not RoundState.IsParticipant(carrier) or not carrier.Team then
		return false
	end
	if downed[carrier.Id] or carriedBy[carrier.Id] or not ActorService.IsAlive(carrier) then
		return false
	end
	local character = carrier.Character :: Model
	-- Mains prises (œuf), gelé ou éjecté : pas de ramassage
	return character:GetAttribute("Carrier") ~= true and character:GetAttribute("Frozen") ~= true and character:GetAttribute("Ragdoll") ~= true
end

-- Coéquipier à terre (non porté) le plus proche, à portée de ramassage
function RescueService.FindTarget(carrier: Actor): Entry?
	local position = ActorService.GetPosition(carrier)
	if not position or not carrier.Team then
		return nil
	end
	local best, bestDistance = nil, Config.Rescue.PickupRange
	for _, entry in downed do
		if entry.Carrier == nil and entry.Actor ~= carrier and entry.Actor.Team == carrier.Team then
			local root = getRoot(entry.Character)
			if root then
				local distance = (root.Position - position).Magnitude
				if distance <= bestDistance then
					best, bestDistance = entry, distance
				end
			end
		end
	end
	return best
end

-- Ramasse le coéquipier à terre le plus proche. Retourne true si c'est fait.
function RescueService.TryCarry(carrier: Actor): boolean
	if not RescueService.CanCarry(carrier) then
		return false
	end
	local entry = RescueService.FindTarget(carrier)
	local carrierRoot = ActorService.GetRoot(carrier)
	if not entry or not carrierRoot then
		return false
	end
	local character = entry.Character
	local root = getRoot(character)
	if not root then
		return false
	end
	-- Chrono suspendu pendant le portage
	entry.Remaining = math.max(0, (entry.Deadline or os.clock()) - os.clock())
	entry.Deadline = nil
	entry.Carrier = carrier
	carriedBy[carrier.Id] = entry
	saveParts(entry)
	local humanoid = getHumanoid(character)
	if humanoid then
		humanoid.PlatformStand = true
	end
	-- Sur l'épaule : soudure à la racine du porteur
	moveRootTo(character, root, carrierRoot.CFrame * CARRY_OFFSET)
	root.Anchored = false
	local weld = Instance.new("Weld")
	weld.Name = "HoH_CarryWeld"
	weld.Part0 = carrierRoot
	weld.Part1 = root
	weld.C0 = CARRY_OFFSET
	weld.Parent = root
	entry.Weld = weld
	setOwner(root, carrier.Player)
	publishTimer(entry)
	character:SetAttribute("CarriedBy", carrier.Name)
	ActorService.SetCharacterAttribute(carrier, "Carrying", entry.Actor.Name)
	ActorService.SetCharacterAttribute(carrier, "Hidden", nil)
	local base = SafeZoneService.GetBase(carrier.Team)
	if base then
		ActorService.SetCharacterAttribute(carrier, "ObjectiveTarget", base.Center)
	end
	AbilityService.SetSpeedModifier(carrier, "Carry", Config.Rescue.CarrySpeedMultiplier)
	Remotes.Get("Effect"):FireAllClients("Carry", { Position = carrierRoot.Position, CarrierId = carrier.Id, VictimId = entry.Actor.Id })
	local def = Teams.Get(carrier.Team)
	announceTo(entry.Actor, Lang.F("%s is carrying you home!", carrier.Name), def and def.Color)
	return true
end

-- Le porteur lâche son coéquipier : il retombe à terre à côté, chrono relancé
function RescueService.Drop(carrier: Actor)
	local entry = carriedBy[carrier.Id]
	if not entry then
		return
	end
	local carrierRoot = ActorService.GetRoot(carrier)
	local root = getRoot(entry.Character)
	releaseCarrier(entry)
	local position = (carrierRoot and (carrierRoot.Position + carrierRoot.CFrame.RightVector * 2.5)) or (root and root.Position)
	if position then
		layDown(entry, position, carrierRoot and yawOf(carrierRoot.CFrame) or nil)
	end
	entry.Remaining = math.max(entry.Remaining, Config.Rescue.DropGraceSeconds)
	entry.Deadline = os.clock() + entry.Remaining
	publishTimer(entry)
end

-- Réanimation : le joueur porté se relève sur la plateforme de son camp
function RescueService.Revive(entry: Entry)
	local victim = entry.Actor
	local rescuer = entry.Carrier
	local root = getRoot(entry.Character)
	local from = (rescuer and ActorService.GetPosition(rescuer)) or (root and root.Position) or Config.World.MapOrigin
	local spawn = victim.Team and nearestSpawn(victim.Team, from) or nil
	standUp(entry, spawn)
	local character = victim.Character
	if character then
		CaptureService.Protect(character, Config.Rescue.ReviveProtectionSeconds)
	end
	AbilityService.ResetCooldowns(victim)
	local def = Teams.Get(victim.Team)
	local color = def and def.Color
	if rescuer then
		announceTo(victim, Lang.F("%s saved you! Back in the game!", rescuer.Name), color)
		announceTo(rescuer, Lang.F("You saved %s!", victim.Name), color)
	else
		announceTo(victim, Lang.T("You're safe at your base. Back in the game!"), color)
	end
	local position = ActorService.GetPosition(victim)
	Remotes.Get("Effect"):FireAllClients("Revive", {
		Position = position,
		Team = victim.Team,
		VictimId = victim.Id,
		VictimName = victim.Name,
		RescuerId = rescuer and rescuer.Id or nil,
		RescuerName = rescuer and rescuer.Name or nil,
	})
	RescueService.Revived:Fire(victim, rescuer)
end

-- Pas de secours : le joueur rejoint l'équipe qui l'a attrapé, sur place
local REASONS = {
	BleedOut = Lang.T("Nobody carried you home in time."),
	NoRescuer = Lang.T("No teammate left to carry you."),
	Reset = Lang.T("You left the ground."),
}
function RescueService.Convert(entry: Entry, reason: string)
	local victim = entry.Actor
	local oldTeam = victim.Team
	local newTeam = entry.CatcherTeam
	local root = getRoot(entry.Character)
	local carrierRoot = entry.Carrier and ActorService.GetRoot(entry.Carrier)
	local target: CFrame? = nil
	if carrierRoot then
		target = standingCFrame(carrierRoot.Position + carrierRoot.CFrame.RightVector * 3, yawOf(carrierRoot.CFrame))
	elseif root then
		target = standingCFrame(root.Position, yawOf(root.CFrame))
	end
	standUp(entry, target)
	if Teams.IsValid(newTeam) and victim.Team ~= newTeam then
		TeamService.SetTeam(victim, newTeam)
	end
	AbilityService.ClearModifiers(victim)
	AbilityService.ResetCooldowns(victim)
	local character = victim.Character
	if character then
		character:SetAttribute("Carrier", nil)
		CaptureService.Protect(character, Config.Capture.InvincibilitySeconds)
	end
	local def = Teams.Get(newTeam)
	if def then
		local prey = Teams.Get(def.Prey)
		local hint = prey and (" " .. Lang.F("Now catch %s!", prey.Plural)) or ""
		announceTo(victim, (REASONS[reason] or "") .. " " .. Lang.F("You're %s now.", def.WithArticle) .. hint, def.Color)
	end
	Remotes.Get("Effect"):FireAllClients("Convert", {
		Position = ActorService.GetPosition(victim),
		Team = newTeam,
		OldTeam = oldTeam,
		VictimId = victim.Id,
		VictimName = victim.Name,
		Reason = reason,
	})
	RescueService.Converted:Fire(victim, newTeam, reason)
end

-- Fin de manche : tout le monde se relève sur place, sans changer d'équipe
function RescueService.EndRound()
	for _, entry in table.clone(downed) do
		local root = getRoot(entry.Character)
		standUp(entry, root and standingCFrame(root.Position, yawOf(root.CFrame)) or nil)
	end
	table.clear(downed)
	table.clear(carriedBy)
end

function RescueService.Reset()
	RescueService.EndRound()
end

-- ---------------------------------------------------------------------------
-- Boucle serveur : réanimation, fin du chrono, équipe sans sauveteur
-- ---------------------------------------------------------------------------
local function step()
	local now = os.clock()
	for _, entry in table.clone(downed) do
		local victim = entry.Actor
		if downed[victim.Id] ~= entry or entry.Character.Parent == nil or victim.Character ~= entry.Character then
			continue -- réapparition ou départ : géré par les signaux d'ActorService
		end
		local carrier = entry.Carrier
		if carrier then
			local position = ActorService.GetPosition(carrier)
			if ActorService.Get(carrier.Id) == nil or not position or carrier.Team ~= victim.Team or downed[carrier.Id] then
				RescueService.Drop(carrier)
			elseif SafeZoneService.Contains(victim.Team, position) then
				RescueService.Revive(entry)
			end
		else
			local root = getRoot(entry.Character)
			if root and SafeZoneService.Contains(victim.Team, root.Position) then
				-- Déjà dans la zone sûre de son camp (lâché à l'entrée) : il se relève
				RescueService.Revive(entry)
			elseif entry.Deadline and now >= entry.Deadline then
				RescueService.Convert(entry, "BleedOut")
			elseif not hasRescuer(victim.Team :: string, victim) then
				RescueService.Convert(entry, "NoRescuer")
			end
		end
	end
end

function RescueService.Init()
	CaptureService.SetDownHandler(function(hunter: Actor, victim: Actor)
		RescueService.Down(victim, hunter)
	end)

	RunService.Heartbeat:Connect(function(dt)
		if not RoundState.IsActive() then
			accumulator = 0
			return
		end
		accumulator += dt
		if accumulator < 0.1 then
			return
		end
		accumulator = 0
		step()
	end)

	-- Intention du joueur : porter le coéquipier le plus proche, ou le lâcher
	Remotes.Get("RequestCarry").OnServerEvent:Connect(function(player: Player)
		if not RateLimiter.Allow(player, "Carry", 4) then
			return
		end
		local actor = ActorService.FromPlayer(player)
		if not actor then
			return
		end
		if carriedBy[actor.Id] then
			RescueService.Drop(actor)
		else
			RescueService.TryCarry(actor)
		end
	end)

	-- Réapparition pendant qu'on est à terre (reset) : abandon, conversion.
	-- Un porteur qui réapparaît lâche son coéquipier.
	ActorService.CharacterAdded:Connect(function(actor: Actor, character: Model)
		local carried = carriedBy[actor.Id]
		if carried and carried.Character ~= character then
			local root = getRoot(carried.Character)
			releaseCarrier(carried)
			if root then
				layDown(carried, root.Position)
			end
			carried.Remaining = math.max(carried.Remaining, Config.Rescue.DropGraceSeconds)
			carried.Deadline = os.clock() + carried.Remaining
			publishTimer(carried)
		end
		local entry = downed[actor.Id]
		if entry and entry.Character ~= character then
			downed[actor.Id] = nil
			releaseCarrier(entry)
			if RoundState.IsInRound() and Teams.IsValid(entry.CatcherTeam) and actor.Team ~= entry.CatcherTeam then
				TeamService.SetTeam(actor, entry.CatcherTeam)
				local def = Teams.Get(entry.CatcherTeam) :: Teams.TeamDef
				announceTo(actor, REASONS.Reset .. " " .. Lang.F("You're %s now.", def.WithArticle), def.Color)
				RescueService.Converted:Fire(actor, entry.CatcherTeam, "Reset")
			end
		end
	end)

	ActorService.ActorRemoving:Connect(function(actor: Actor)
		if carriedBy[actor.Id] then
			RescueService.Drop(actor)
		end
		local entry = downed[actor.Id]
		if entry then
			downed[actor.Id] = nil
			releaseCarrier(entry)
		end
	end)
end

-- Pour les tests : un pas de la boucle serveur
RescueService.Step = step

return RescueService

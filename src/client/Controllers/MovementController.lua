--[[
	MovementController.lua
	Sensation de déplacement :
	  - vitesse à inertie (accélération et décélération progressives, virages amortis),
	  - dash latéral (gauche/droite) avec temps de recharge,
	  - arrêt instantané (feinte),
	  - capacité de l'animal (sprint, saut plané, morsure),
	  - éjections décidées par le serveur (ragdoll court).
	Technique : on remplace la fonction de déplacement du module de contrôle de
	Roblox (PlayerModule) ; le joystick tactile, le clavier et la manette restent
	ceux de Roblox, on ne fait que lisser la vitesse.
	Le client PRÉDIT dash et capacité pour la réactivité ; le serveur valide.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ContextActionService = game:GetService("ContextActionService")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Movement = require(Shared.Movement)
local Remotes = require(Shared.Remotes)
local Teams = require(Shared.Teams)

local MovementController = {}

local player = Players.LocalPlayer

local character: Model? = nil
local humanoid: Humanoid? = nil
local root: BasePart? = nil

local velocity = Vector3.zero -- vitesse horizontale "voulue" (inertie)
local lastMoveTime = os.clock()
local dashHoldVelocity: Vector3? = nil
local localDashReadyAt = 0
local localAbilityReadyAt = 0
local localStopReadyAt = 0
local lastJumpAbility = 0
local captureDebounce: { [Model]: number } = {}
local captureAccumulator = 0

local RequestDash = Remotes.Get("RequestDash")
local RequestAbility = Remotes.Get("RequestAbility")
local CaptureAttempt = Remotes.Get("CaptureAttempt")

local function serverNow(): number
	return workspace:GetServerTimeNow()
end

local function myTeam(): string?
	local team = character and character:GetAttribute("Team")
	if type(team) == "string" then
		return team
	end
	return nil
end

local function moveToward(current: Vector3, target: Vector3, maxDelta: number): Vector3
	local delta = target - current
	local distance = delta.Magnitude
	if distance <= maxDelta or distance < 1e-4 then
		return target
	end
	return current + delta / distance * maxDelta
end

local function flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

-- Convertit le vecteur du joystick (espace caméra) en direction dans le monde
local function toWorld(moveVector: Vector3, cameraRelative: boolean): Vector3
	if not cameraRelative then
		return flat(moveVector)
	end
	local camera = workspace.CurrentCamera
	if not camera then
		return flat(moveVector)
	end
	local look = flat(camera.CFrame.LookVector)
	if look.Magnitude < 0.01 then
		look = flat(camera.CFrame.UpVector)
	end
	look = look.Unit
	local right = Vector3.new(-look.Z, 0, look.X)
	local dir = right * moveVector.X - look * moveVector.Z
	if dir.Magnitude > 1 then
		dir = dir.Unit
	end
	return dir
end

local function isDisabled(): boolean
	if not character or not humanoid or humanoid.Health <= 0 then
		return true
	end
	-- À terre ou porté : on attend un coéquipier
	if character:GetAttribute("Downed") == true then
		return true
	end
	return Movement.IsRagdolled(character)
end

-- ---------------------------------------------------------------------------
-- Déplacement à inertie (appelé à chaque image par le module de contrôle)
-- ---------------------------------------------------------------------------
local function inertialMove(_player: Player, moveVector: Vector3, cameraRelative: boolean)
	local now = os.clock()
	local dt = math.clamp(now - lastMoveTime, 0, 0.1)
	lastMoveTime = now
	local hum = humanoid
	local char = character
	if not hum or not char then
		return
	end
	if isDisabled() then
		velocity = Vector3.zero
		hum:Move(Vector3.zero, false)
		return
	end
	if dashHoldVelocity then
		if Movement.IsDashing(char) then
			return
		end
		velocity = dashHoldVelocity
		dashHoldVelocity = nil
	end

	local maxSpeed = Movement.GetMaxSpeed(char)
	local direction = toWorld(moveVector, cameraRelative)
	local target = direction * maxSpeed
	local cfg = Config.Movement
	local accel: number
	if target.Magnitude > 0.01 then
		accel = (velocity:Dot(target) < 0) and cfg.TurnAcceleration or cfg.Acceleration
		-- Virage serré : on autorise un peu plus d'accélération latérale
		if velocity.Magnitude > 1 and velocity.Unit:Dot(target.Unit) < 0.7 then
			accel = math.max(accel, cfg.TurnAcceleration * 0.8)
		end
	else
		accel = cfg.Deceleration
	end
	if hum.FloorMaterial == Enum.Material.Air then
		accel *= cfg.AirControl
	end
	velocity = moveToward(velocity, target, accel * dt)
	-- Un ralentissement (morsure, porteur) s'applique tout de suite
	if velocity.Magnitude > maxSpeed then
		velocity = velocity.Unit * maxSpeed
	end
	if velocity.Magnitude < 0.05 then
		velocity = Vector3.zero
	end
	hum.WalkSpeed = velocity.Magnitude
	if velocity.Magnitude > 0 then
		hum:Move(velocity.Unit, false)
	else
		hum:Move(Vector3.zero, false)
	end
end

-- ---------------------------------------------------------------------------
-- Actions
-- ---------------------------------------------------------------------------
function MovementController.Dash(side: number)
	local char = character
	if not char or isDisabled() or char:GetAttribute("Frozen") == true then
		return
	end
	local serverReady = char:GetAttribute("DashReadyAt")
	local now = serverNow()
	if now < localDashReadyAt or (type(serverReady) == "number" and now < serverReady - 0.05) then
		return
	end
	local keep = Movement.Dash(char, side)
	if not keep then
		return
	end
	-- Après le dash : on garde un peu d'élan dans la direction courante
	local forward = velocity.Magnitude > 1 and velocity.Unit * velocity.Magnitude or Vector3.zero
	dashHoldVelocity = forward + keep * 0.35
	localDashReadyAt = now + Movement.GetDashCooldown(char)
	RequestDash:FireServer(side)
end

function MovementController.Stop()
	local char = character
	if not char or isDisabled() then
		return
	end
	local now = os.clock()
	if now < localStopReadyAt then
		return
	end
	localStopReadyAt = now + Config.Movement.StopCooldown
	velocity = Vector3.zero
	dashHoldVelocity = nil
	Movement.Stop(char)
end

function MovementController.Ability()
	local char = character
	local team = myTeam()
	if not char or not team or isDisabled() or char:GetAttribute("Frozen") == true then
		return
	end
	local cfg = Config.Abilities[team]
	if not cfg then
		return
	end
	local now = serverNow()
	local serverReady = char:GetAttribute("AbilityReadyAt")
	if now < localAbilityReadyAt or (type(serverReady) == "number" and now < serverReady - 0.05) then
		return
	end
	localAbilityReadyAt = now + cfg.Cooldown
	if team == "CHICKEN" then
		Movement.GlideJump(char) -- prédiction locale, le serveur valide
	end
	RequestAbility:FireServer()
end

-- Infos pour la barre d'actions
function MovementController.GetCooldowns()
	local char = character
	local now = serverNow()
	local team = myTeam()
	local info = {}
	-- Les boutons d'action ne s'affichent qu'en manche (avec une équipe) : au
	-- lobby, l'écran tactile reste au vote et à la boutique. À terre, aucune action.
	local inRound = char ~= nil and team ~= nil and char:GetAttribute("Downed") ~= true
	local function cd(localReady: number, attr: string, total: number)
		local serverReady = char and char:GetAttribute(attr)
		local ready = localReady
		if type(serverReady) == "number" then
			ready = math.max(ready, serverReady)
		end
		return { Remaining = ready - now, Total = total, Available = inRound }
	end
	local dashTotal = char and Movement.GetDashCooldown(char) or Config.Movement.DashCooldown
	info.DashLeft = cd(localDashReadyAt, "DashReadyAt", dashTotal)
	info.DashRight = info.DashLeft
	info.Stop = { Remaining = localStopReadyAt - os.clock(), Total = Config.Movement.StopCooldown, Available = inRound }
	local abilityCfg = team and Config.Abilities[team]
	if abilityCfg then
		info.Ability = cd(localAbilityReadyAt, "AbilityReadyAt", abilityCfg.Cooldown)
	else
		info.Ability = { Remaining = 0, Total = 1, Available = false }
	end
	return info
end

-- ---------------------------------------------------------------------------
-- Intentions de capture : on signale au serveur un contact avec une proie
-- ---------------------------------------------------------------------------
local function checkCaptures(dt: number)
	captureAccumulator += dt
	if captureAccumulator < 0.1 then
		return
	end
	captureAccumulator = 0
	local team = myTeam()
	local myRoot = root
	if not team or not myRoot or isDisabled() then
		return
	end
	-- Mains prises : un porteur de coéquipier n'attrape personne
	if character and character:GetAttribute("Carrying") ~= nil then
		return
	end
	local prey = Teams.GetPrey(team)
	local range = character and character:GetAttribute("CaptureRange")
	if type(range) ~= "number" then
		range = Config.Capture.Range
	end
	local now = os.clock()
	for _, model in CollectionService:GetTagged("HoH_Actor") do
		-- (une proie à terre ou à l'abri dans sa zone sûre ne peut pas être attrapée)
		if model ~= character and model:IsA("Model") and model:GetAttribute("Team") == prey and model:GetAttribute("Downed") ~= true and model:GetAttribute("SafeZone") ~= true then
			local otherRoot = model:FindFirstChild("HumanoidRootPart")
			if otherRoot and otherRoot:IsA("BasePart") then
				local delta = otherRoot.Position - myRoot.Position
				if Vector3.new(delta.X, 0, delta.Z).Magnitude <= range + 0.5 and math.abs(delta.Y) <= Config.Capture.MaxVerticalGap then
					if not captureDebounce[model] or now - captureDebounce[model] > 0.3 then
						captureDebounce[model] = now
						CaptureAttempt:FireServer(model)
					end
				end
			end
		end
	end
end

-- ---------------------------------------------------------------------------
-- Personnage
-- ---------------------------------------------------------------------------
local function onCharacterAdded(newCharacter: Model)
	character = newCharacter
	humanoid = newCharacter:WaitForChild("Humanoid", 10) :: Humanoid?
	root = newCharacter:WaitForChild("HumanoidRootPart", 10) :: BasePart?
	velocity = Vector3.zero
	dashHoldVelocity = nil
	localDashReadyAt = 0
	localAbilityReadyAt = 0
	if humanoid then
		humanoid.WalkSpeed = 0
		humanoid.UseJumpPower = true
		humanoid.JumpPower = Config.Movement.JumpPower
	end
	newCharacter:GetAttributeChangedSignal("Frozen"):Connect(function()
		local frozen = newCharacter:GetAttribute("Frozen") == true
		if humanoid then
			humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, not frozen)
		end
		if frozen then
			velocity = Vector3.zero
		end
	end)
	-- Changement d'équipe : on remet les temps de recharge locaux à zéro
	newCharacter:GetAttributeChangedSignal("Team"):Connect(function()
		localAbilityReadyAt = 0
	end)
end

local function bindActions()
	local function bind(name: string, keys: { Enum.KeyCode }, callback: () -> ())
		ContextActionService:BindAction(name, function(_, inputState)
			if inputState == Enum.UserInputState.Begin then
				callback()
			end
			return Enum.ContextActionResult.Sink
		end, false, table.unpack(keys))
	end
	bind("HoH_DashLeft", Config.Controls.DashLeft, function()
		MovementController.Dash(-1)
	end)
	bind("HoH_DashRight", Config.Controls.DashRight, function()
		MovementController.Dash(1)
	end)
	bind("HoH_Stop", Config.Controls.Stop, MovementController.Stop)
	bind("HoH_Ability", Config.Controls.Ability, MovementController.Ability)

	-- Poule : appuyer sur Saut en l'air déclenche le saut plané
	UserInputService.JumpRequest:Connect(function()
		local hum = humanoid
		if not hum or myTeam() ~= "CHICKEN" then
			return
		end
		local now = os.clock()
		if now - lastJumpAbility < 0.3 then
			return
		end
		if hum.FloorMaterial == Enum.Material.Air and hum:GetState() == Enum.HumanoidStateType.Freefall then
			lastJumpAbility = now
			MovementController.Ability()
		end
	end)
end

local function hookControls()
	local playerScripts = player:WaitForChild("PlayerScripts")
	local moduleScript = playerScripts:WaitForChild("PlayerModule", 20)
	if not moduleScript then
		warn("[Movement] PlayerModule introuvable : déplacement standard conservé")
		return
	end
	local ok, playerModule = pcall(require, moduleScript)
	if not ok or type(playerModule) ~= "table" then
		warn("[Movement] Impossible de charger PlayerModule : déplacement standard conservé")
		return
	end
	local controls = (playerModule :: any):GetControls()
	if type(controls) ~= "table" then
		return
	end
	controls.moveFunction = inertialMove
end

function MovementController.Init()
	player.CharacterAdded:Connect(onCharacterAdded)
	if player.Character then
		task.spawn(onCharacterAdded, player.Character)
	end

	Remotes.Get("Launch").OnClientEvent:Connect(function(launchVelocity: Vector3, ragdoll: number)
		if character and typeof(launchVelocity) == "Vector3" then
			velocity = Vector3.zero
			dashHoldVelocity = nil
			Movement.Launch(character, launchVelocity, ragdoll)
		end
	end)

	RunService.Heartbeat:Connect(function(dt)
		if character then
			Movement.GlideStep(character)
		end
		checkCaptures(dt)
		-- Nettoyage du cache anti-rebond
		for model in captureDebounce do
			if model.Parent == nil then
				captureDebounce[model] = nil
			end
		end
	end)

	bindActions()
	task.spawn(hookControls)
end

return MovementController

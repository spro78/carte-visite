--[[
	Movement.lua
	Actions physiques communes, appliquées :
	  - par le CLIENT sur son propre personnage (il possède sa physique),
	  - par le SERVEUR sur les bots.
	Le serveur reste maître des règles (temps de recharge, éjections) :
	ces fonctions ne font qu'exécuter une action déjà validée ou prédite.
]]

local Config = require(script.Parent.Config)

local Movement = {}

local ATTACHMENT_NAME = "HoH_MoveAttachment"
local DASH_NAME = "HoH_Dash"

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

local function getAttachment(root: BasePart): Attachment
	local existing = root:FindFirstChild(ATTACHMENT_NAME)
	if existing and existing:IsA("Attachment") then
		return existing
	end
	local attachment = Instance.new("Attachment")
	attachment.Name = ATTACHMENT_NAME
	attachment.Parent = root
	return attachment
end

-- Impose une vitesse horizontale pendant "duration" secondes (l'axe vertical reste libre).
function Movement.ApplyHorizontalVelocity(character: Model, velocity: Vector3, duration: number, name: string?): LinearVelocity?
	local root = getRoot(character)
	if not root then
		return nil
	end
	local constraint = Instance.new("LinearVelocity")
	constraint.Name = name or DASH_NAME
	constraint.Attachment0 = getAttachment(root)
	constraint.RelativeTo = Enum.ActuatorRelativeTo.World
	constraint.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector
	constraint.ForceLimitMode = Enum.ForceLimitMode.PerAxis
	constraint.MaxAxesForce = Vector3.new(1e6, 0, 1e6)
	constraint.VectorVelocity = Vector3.new(velocity.X, 0, velocity.Z)
	constraint.Parent = root
	task.delay(duration, function()
		if constraint.Parent then
			constraint:Destroy()
		end
	end)
	return constraint
end

-- Direction latérale (gauche = -1, droite = 1) selon l'orientation du personnage.
function Movement.GetLateralDirection(character: Model, side: number): Vector3?
	local root = getRoot(character)
	if not root then
		return nil
	end
	local right = root.CFrame.RightVector
	local flat = Vector3.new(right.X, 0, right.Z)
	if flat.Magnitude < 0.01 then
		return nil
	end
	return flat.Unit * (side < 0 and -1 or 1)
end

-- Dash latéral. Retourne la vitesse horizontale à conserver après le dash.
function Movement.Dash(character: Model, side: number): Vector3?
	local direction = Movement.GetLateralDirection(character, side)
	if not direction then
		return nil
	end
	local cfg = Config.Movement
	local speed = cfg.DashDistance / cfg.DashDuration
	Movement.ApplyHorizontalVelocity(character, direction * speed, cfg.DashDuration, DASH_NAME)
	return direction * cfg.MaxSpeed * cfg.DashEndSpeedFactor
end

function Movement.IsDashing(character: Model): boolean
	local root = getRoot(character)
	return root ~= nil and root:FindFirstChild(DASH_NAME) ~= nil
end

-- Arrêt instantané : annule l'élan horizontal (feinte).
function Movement.Stop(character: Model)
	local root = getRoot(character)
	if not root then
		return
	end
	local dash = root:FindFirstChild(DASH_NAME)
	if dash then
		dash:Destroy()
	end
	local velocity = root.AssemblyLinearVelocity
	root.AssemblyLinearVelocity = Vector3.new(0, math.min(velocity.Y, 0), 0)
	local humanoid = getHumanoid(character)
	if humanoid then
		humanoid:Move(Vector3.zero, false)
	end
end

-- Éjection : vitesse imposée + ragdoll court (PlatformStand).
function Movement.Launch(character: Model, velocity: Vector3, ragdollSeconds: number?)
	local root = getRoot(character)
	local humanoid = getHumanoid(character)
	if not root or not humanoid or humanoid.Health <= 0 then
		return
	end
	local duration = ragdollSeconds or Config.Launch.DefaultRagdollSeconds
	local previous = character:GetAttribute("RagdollToken")
	local token = (type(previous) == "number" and previous or 0) + 1
	character:SetAttribute("RagdollToken", token)
	character:SetAttribute("Ragdoll", true)
	local dash = root:FindFirstChild(DASH_NAME)
	if dash then
		dash:Destroy()
	end
	humanoid.PlatformStand = true
	root.AssemblyLinearVelocity = velocity
	-- Petite rotation pour l'effet "culbute"
	root.AssemblyAngularVelocity = Vector3.new(math.random() * 8 - 4, math.random() * 6 - 3, math.random() * 8 - 4)
	task.delay(duration, function()
		if character:GetAttribute("RagdollToken") ~= token then
			return
		end
		character:SetAttribute("Ragdoll", false)
		if humanoid.Parent and humanoid.Health > 0 then
			humanoid.PlatformStand = false
			root.AssemblyAngularVelocity = Vector3.zero
			humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
		end
	end)
end

function Movement.IsRagdolled(character: Model): boolean
	return character:GetAttribute("Ragdoll") == true
end

-- Saut plané de la poule : impulsion verticale puis chute ralentie.
function Movement.GlideJump(character: Model)
	local root = getRoot(character)
	local humanoid = getHumanoid(character)
	if not root or not humanoid then
		return
	end
	local cfg = Config.Abilities.CHICKEN
	local velocity = root.AssemblyLinearVelocity
	root.AssemblyLinearVelocity = Vector3.new(velocity.X, cfg.DoubleJumpPower, velocity.Z)
	humanoid:ChangeState(Enum.HumanoidStateType.Freefall)
	character:SetAttribute("GlideUntil", workspace:GetServerTimeNow() + cfg.GlideMaxDuration)
end

-- À appeler à chaque image pendant le vol plané. Retourne false quand il est fini.
function Movement.GlideStep(character: Model): boolean
	local glideUntil = character:GetAttribute("GlideUntil")
	if type(glideUntil) ~= "number" or workspace:GetServerTimeNow() > glideUntil then
		return false
	end
	local root = getRoot(character)
	local humanoid = getHumanoid(character)
	if not root or not humanoid then
		return false
	end
	local state = humanoid:GetState()
	if state == Enum.HumanoidStateType.Landed or state == Enum.HumanoidStateType.Running then
		if root.AssemblyLinearVelocity.Y <= 0.5 then
			character:SetAttribute("GlideUntil", nil)
			return false
		end
	end
	local cfg = Config.Abilities.CHICKEN
	local velocity = root.AssemblyLinearVelocity
	if velocity.Y < -cfg.GlideFallSpeed then
		local forward = root.CFrame.LookVector
		local boost = Vector3.new(forward.X, 0, forward.Z) * cfg.GlideForwardBoost
		root.AssemblyLinearVelocity = Vector3.new(velocity.X + boost.X * 0.05, -cfg.GlideFallSpeed, velocity.Z + boost.Z * 0.05)
	end
	return true
end

-- Vitesse maximale effective d'un personnage (attribut SpeedMult posé par le serveur).
function Movement.GetMaxSpeed(character: Model): number
	local mult = character:GetAttribute("SpeedMult")
	if type(mult) ~= "number" then
		mult = 1
	end
	if character:GetAttribute("Frozen") == true then
		return 0
	end
	return Config.Movement.MaxSpeed * mult
end

-- Temps de recharge du dash pour ce personnage (amélioration achetée comprise).
function Movement.GetDashCooldown(character: Model): number
	local cd = character:GetAttribute("DashCooldown")
	if type(cd) == "number" then
		return cd
	end
	return Config.Movement.DashCooldown
end

return Movement

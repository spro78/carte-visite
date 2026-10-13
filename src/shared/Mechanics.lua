--[[
	Mechanics.lua
	Mécanismes tournants synchronisés sans réplication image par image :
	le serveur publie (angle de référence, vitesse, instant de référence) dans
	des attributs du modèle ; chaque client calcule l'angle courant et anime le
	modèle localement (fluide), le serveur calcule les collisions avec le même
	angle. Fonctionne pour les bras, plateformes, catapultes, tourniquets...

	Attributs d'un modèle tagué "HoH_Spinner" :
	  SpinBase   (CFrame) : pivot du modèle à l'angle 0 (axe de rotation = axe Y du pivot)
	  SpinAngle0 (number) : angle (radians) à l'instant SpinT0
	  SpinSpeed  (number) : vitesse angulaire (radians/seconde)
	  SpinT0     (number) : instant de référence (workspace:GetServerTimeNow())
]]

local Mechanics = {}

Mechanics.SpinnerTag = "HoH_Spinner"
Mechanics.FloatTag = "HoH_Float" -- objets ancrés qui flottent et tournent doucement (œufs)

local function now(): number
	return workspace:GetServerTimeNow()
end

function Mechanics.GetAngle(model: Instance, at: number?): number
	local angle0 = model:GetAttribute("SpinAngle0")
	local speed = model:GetAttribute("SpinSpeed")
	local t0 = model:GetAttribute("SpinT0")
	if type(angle0) ~= "number" or type(speed) ~= "number" or type(t0) ~= "number" then
		return 0
	end
	return angle0 + speed * ((at or now()) - t0)
end

-- Côté serveur : (re)définit la rotation en conservant la continuité de l'angle.
function Mechanics.SetSpin(model: Instance, speed: number, angle: number?)
	local current = angle or Mechanics.GetAngle(model)
	model:SetAttribute("SpinAngle0", current % (math.pi * 2))
	model:SetAttribute("SpinSpeed", speed)
	model:SetAttribute("SpinT0", now())
end

-- CFrame du modèle pour un angle donné
function Mechanics.GetCFrame(model: Instance, angle: number): CFrame?
	local base = model:GetAttribute("SpinBase")
	if typeof(base) ~= "CFrame" then
		return nil
	end
	return base * CFrame.Angles(0, angle, 0)
end

-- Différence d'angle ramenée dans [-pi, pi]
function Mechanics.AngleDelta(a: number, b: number): number
	local d = (a - b) % (math.pi * 2)
	if d > math.pi then
		d -= math.pi * 2
	end
	return d
end

-- Angle (autour de l'axe Y) d'une position par rapport à un centre, dans la même
-- convention que CFrame.Angles(0, angle, 0) appliqué à la direction +X.
function Mechanics.AngleOf(center: Vector3, position: Vector3): number
	local dx = position.X - center.X
	local dz = position.Z - center.Z
	return math.atan2(-dz, dx)
end

-- Direction horizontale (unitaire) correspondant à un angle
function Mechanics.Direction(angle: number): Vector3
	return Vector3.new(math.cos(angle), 0, -math.sin(angle))
end

return Mechanics

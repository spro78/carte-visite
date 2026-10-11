--[[
	MechanicsController.lua
	Anime localement (fluide, sans réplication image par image) :
	  - les mécanismes tournants tagués "HoH_Spinner" à partir de l'angle publié
	    par le serveur (Shared/Mechanics),
	  - les objets ancrés tagués "HoH_Float" (œufs) : flottement et rotation.
	Les mécanismes sur lesquels on peut monter (attribut SpinCollide) reçoivent
	aussi une vitesse angulaire locale pour entraîner le personnage.
]]

local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Mechanics = require(Shared.Mechanics)

local MechanicsController = {}

local floatBase: { [BasePart]: CFrame } = {}

local function updateSpinners()
	for _, model in CollectionService:GetTagged(Mechanics.SpinnerTag) do
		if model:IsA("Model") and model.Parent then
			local angle = Mechanics.GetAngle(model)
			local cframe = Mechanics.GetCFrame(model, angle)
			if cframe then
				model:PivotTo(cframe)
				if model:GetAttribute("SpinCollide") == true then
					local speed = model:GetAttribute("SpinSpeed")
					local omega = Vector3.new(0, type(speed) == "number" and speed or 0, 0)
					for _, part in model:GetDescendants() do
						if part:IsA("BasePart") and part.CanCollide then
							part.AssemblyAngularVelocity = omega
						end
					end
				end
			end
		end
	end
end

local function updateFloats()
	local t = os.clock()
	for _, part in CollectionService:GetTagged(Mechanics.FloatTag) do
		if part:IsA("BasePart") and part.Anchored and part.Parent then
			local base = floatBase[part]
			-- Si le serveur a déplacé l'objet, on reprend sa nouvelle position
			if not base or (part:GetAttribute("FloatServerPos") ~= nil and part:GetAttribute("FloatServerPos") ~= base.Position) then
				base = part.CFrame
				floatBase[part] = base
			end
			part.CFrame = base * CFrame.new(0, math.sin(t * 2.2) * 0.35, 0) * CFrame.Angles(0, t * 1.5, 0)
		end
	end
end

function MechanicsController.Init()
	CollectionService:GetInstanceRemovedSignal(Mechanics.FloatTag):Connect(function(part)
		if part:IsA("BasePart") then
			floatBase[part] = nil
		end
	end)
	CollectionService:GetInstanceAddedSignal(Mechanics.FloatTag):Connect(function(part)
		if part:IsA("BasePart") then
			floatBase[part] = nil
		end
	end)
	RunService.RenderStepped:Connect(function()
		updateSpinners()
		updateFloats()
	end)
end

return MechanicsController

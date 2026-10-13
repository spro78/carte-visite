--[[
	HideService.lua
	Cachettes : un acteur dont le centre est dans une zone taguée "HoH_HidingSpot"
	(hautes herbes, buissons, terriers) reçoit l'attribut "Hidden" sur son
	personnage. Les clients masquent alors son nom et son contour (sauf de près).
	Un porteur d'objectif ne peut pas se cacher.
]]

local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local ActorService = require(script.Parent.ActorService)
local RoundState = require(script.Parent.RoundState)

local HideService = {}

local TAG = "HoH_HidingSpot"
local accumulator = 0

local function isInside(zone: BasePart, position: Vector3): boolean
	local localPos = zone.CFrame:PointToObjectSpace(position)
	local half = zone.Size / 2
	return math.abs(localPos.X) <= half.X and math.abs(localPos.Y) <= half.Y and math.abs(localPos.Z) <= half.Z
end

function HideService.IsHidden(position: Vector3): boolean
	for _, zone in CollectionService:GetTagged(TAG) do
		if zone:IsA("BasePart") and isInside(zone, position) then
			return true
		end
	end
	return false
end

-- Liste des positions de cachettes (utilisée par les bots)
function HideService.GetSpots(): { Vector3 }
	local list = {}
	for _, zone in CollectionService:GetTagged(TAG) do
		if zone:IsA("BasePart") then
			table.insert(list, zone.Position)
		end
	end
	return list
end

local function update()
	local zones = CollectionService:GetTagged(TAG)
	for _, actor in ActorService.GetAll() do
		local character = actor.Character
		if not character then
			continue
		end
		local hidden = false
		if #zones > 0 and RoundState.IsInRound() and character:GetAttribute("Carrier") ~= true then
			local position = ActorService.GetPosition(actor)
			if position then
				for _, zone in zones do
					if zone:IsA("BasePart") and isInside(zone, position) then
						hidden = true
						break
					end
				end
			end
		end
		if (character:GetAttribute("Hidden") == true) ~= hidden then
			character:SetAttribute("Hidden", hidden or nil)
		end
	end
end

function HideService.Init()
	RunService.Heartbeat:Connect(function(dt)
		accumulator += dt
		if accumulator >= Config.Hiding.CheckInterval then
			accumulator = 0
			update()
		end
	end)
end

return HideService

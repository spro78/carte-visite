--[[
	TheSwamp.lua
	Phase 1 : squelette (sol, trois bases en triangle, zone centrale, limites).
	Phase 5 : mode de jeu et mécanisme central.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local MapBase = require(script.Parent.MapBase)
local Build = require(script.Parent.Parent.Util.Build)

local Map = {}
Map.Id = "TheSwamp"

local folder: Folder? = nil
local bases = nil
local running = false

function Map.Build(origin: Vector3, context)
	local cfg = Config.Maps[Map.Id]
	folder = MapBase.NewFolder("Map_" .. Map.Id)
	MapBase.BuildGround(folder, origin, cfg.GroundSize, Color3.fromRGB(70, 110, 85), Enum.Material.Mud)
	MapBase.BuildBoundary(folder, origin, cfg.GroundSize, 60)
	bases = MapBase.BuildBases(folder, origin, cfg.BaseRadius, cfg.BasePadSize)
	MapBase.BuildCentralPad(folder, origin, 22, Color3.fromRGB(50, 80, 70))

	-- Mares décoratives
	for i = 1, 5 do
		local a = (i / 5) * math.pi * 2
		Build.VerticalCylinder(origin + Vector3.new(math.cos(a) * 90, 0.15, math.sin(a) * 90), 10, 0.3, {
			Name = "Pond",
			Color = Color3.fromRGB(60, 120, 110),
			Material = Enum.Material.Glass,
			Transparency = 0.3,
			CanCollide = false,
		}, folder)
	end
	folder.Parent = workspace
end

function Map.GetSpawns(teamId: string): { CFrame }
	assert(bases, "Map non construite")
	return bases[teamId].Spawns
end

function Map.StartMode(context)
	running = true
	-- Phase 5 : logique du mode
end

function Map.StopMode()
	running = false
end

function Map.Cleanup()
	running = false
	if folder then
		folder:Destroy()
		folder = nil
	end
	bases = nil
end

return Map

--[[
	TheCarousel.lua
	Phase 1 : squelette (sol, trois bases en triangle, zone centrale, limites).
	Phase 5 : mode de jeu et mécanisme central.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local MapBase = require(script.Parent.MapBase)
local Build = require(script.Parent.Parent.Util.Build)

local Map = {}
Map.Id = "TheCarousel"

local folder: Folder? = nil
local bases = nil
local running = false

function Map.Build(origin: Vector3, context)
	local cfg = Config.Maps[Map.Id]
	folder = MapBase.NewFolder("Map_" .. Map.Id)
	MapBase.BuildGround(folder, origin, cfg.GroundSize, Color3.fromRGB(200, 170, 210), Enum.Material.SmoothPlastic)
	MapBase.BuildBoundary(folder, origin, cfg.GroundSize, 60)
	bases = MapBase.BuildBases(folder, origin, cfg.BaseRadius, cfg.BasePadSize)
	MapBase.BuildCentralPad(folder, origin, 22, Color3.fromRGB(230, 120, 190))

	-- Repère de la future plateforme tournante
	Build.VerticalCylinder(origin + Vector3.new(0, 1.5, 0), cfg.PlatformRadius, 2, {
		Name = "WheelPlaceholder",
		Color = Color3.fromRGB(240, 170, 210),
	}, folder)
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

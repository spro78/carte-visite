--[[
	TheFarm.lua
	Phase 1 : squelette (sol, trois bases en triangle, zone centrale, limites).
	Phase 3 : mode de jeu et mécanisme central.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local MapBase = require(script.Parent.MapBase)
local Build = require(script.Parent.Parent.Util.Build)

local Map = {}
Map.Id = "TheFarm"

local folder: Folder? = nil
local bases = nil
local _running = false

function Map.Build(origin: Vector3, context)
	local cfg = Config.Maps[Map.Id]
	local f = MapBase.NewFolder("Map_" .. Map.Id)
	MapBase.BuildGround(f, origin, cfg.GroundSize, Color3.fromRGB(110, 175, 70), Enum.Material.Grass)
	MapBase.BuildBoundary(f, origin, cfg.GroundSize, 60)
	bases = MapBase.BuildBases(f, origin, cfg.BaseRadius, cfg.BasePadSize)
	MapBase.BuildCentralPad(f, origin, 22, Color3.fromRGB(190, 160, 100))

	-- Quelques buissons décoratifs entre les bases (cachettes en phase 3)
	for i = 1, 9 do
		local a = (i / 9) * math.pi * 2
		MapBase.BuildBush(f, origin + Vector3.new(math.cos(a) * 80, 0, math.sin(a) * 80), 9)
	end
	-- Repère visuel du futur nid de l'œuf d'or
	Build.Part({
		Name = "NestMarker",
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(4, 4, 4),
		Position = origin + Vector3.new(0, 2.5, 0),
		Color = Color3.fromRGB(255, 215, 0),
		Material = Enum.Material.Neon,
		CanCollide = false,
	}, f)
	f.Parent = workspace
	folder = f
end

function Map.GetSpawns(teamId: string): { CFrame }
	assert(bases, "Map non construite")
	return bases[teamId].Spawns
end

function Map.StartMode(context)
	_running = true
	-- Phase 3 : logique du mode
end

function Map.StopMode()
	_running = false
end

function Map.Cleanup()
	_running = false
	if folder then
		folder:Destroy()
		folder = nil
	end
	bases = nil
end

return Map

--[[
	TheCanyon.lua
	Phase 1 : squelette (sol, trois bases en triangle, zone centrale, limites).
	Phase 5 : mode de jeu et mécanisme central.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local MapBase = require(script.Parent.MapBase)
local Build = require(script.Parent.Parent.Util.Build)

local Map = {}
Map.Id = "TheCanyon"

local folder: Folder? = nil
local bases = nil
local _running = false

function Map.Build(origin: Vector3, context)
	local cfg = Config.Maps[Map.Id]
	local f = MapBase.NewFolder("Map_" .. Map.Id)
	MapBase.BuildGround(f, origin, cfg.GroundSize, Color3.fromRGB(205, 150, 95), Enum.Material.Sandstone)
	MapBase.BuildBoundary(f, origin, cfg.GroundSize, 60)
	bases = MapBase.BuildBases(f, origin, cfg.BaseRadius, cfg.BasePadSize)
	MapBase.BuildCentralPad(f, origin, 22, Color3.fromRGB(160, 110, 70))

	-- Rochers décoratifs
	for i = 1, 6 do
		local a = (i / 6) * math.pi * 2 + 0.3
		Build.Part({
			Name = "Rock",
			Size = Vector3.new(14, 10, 12),
			CFrame = CFrame.new(origin + Vector3.new(math.cos(a) * 70, 5, math.sin(a) * 70)) * CFrame.Angles(0, a, 0),
			Color = Color3.fromRGB(150, 105, 70),
			Material = Enum.Material.Slate,
		}, f)
	end
	f.Parent = workspace
	folder = f
end

function Map.GetSpawns(teamId: string): { CFrame }
	assert(bases, "Map non construite")
	return bases[teamId].Spawns
end

function Map.StartMode(context)
	_running = true
	-- Phase 5 : logique du mode
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

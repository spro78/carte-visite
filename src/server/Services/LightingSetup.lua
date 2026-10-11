--[[
	LightingSetup.lua
	Applique l'éclairage de la direction artistique (Shared/Style) au démarrage :
	propriétés de Lighting, Atmosphere, ColorCorrection, Bloom, nuages.
	Les maps peuvent ensuite surcharger certaines propriétés (Map.Lighting),
	restaurées en fin de manche par RoundService.
]]

local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Style = require(Shared.Style)

local LightingSetup = {}

local function ensure(className: string, name: string): Instance
	local existing = Lighting:FindFirstChild(name)
	if existing and existing.ClassName == className then
		return existing
	end
	local inst = Instance.new(className)
	inst.Name = name
	inst.Parent = Lighting
	return inst
end

local function apply(target: Instance, props: { [string]: any })
	for key, value in props do
		local ok, err = pcall(function()
			(target :: any)[key] = value
		end)
		if not ok then
			warn("[LightingSetup] " .. key .. " : " .. tostring(err))
		end
	end
end

function LightingSetup.Apply()
	apply(Lighting, Style.Lighting)
	apply(ensure("Atmosphere", "HoH_Atmosphere"), Style.Atmosphere)
	apply(ensure("ColorCorrectionEffect", "HoH_ColorCorrection"), Style.ColorCorrection)
	apply(ensure("BloomEffect", "HoH_Bloom"), Style.Bloom)
	-- Nuages dynamiques (ciel bleu à nuages)
	local terrain = workspace:FindFirstChildOfClass("Terrain")
	if terrain then
		local clouds = terrain:FindFirstChildOfClass("Clouds")
		if not clouds then
			clouds = Instance.new("Clouds")
			clouds.Parent = terrain
		end
		apply(clouds, Style.Clouds)
	end
end

return LightingSetup

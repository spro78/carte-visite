--[[
	MapRegistry.lua
	Charge automatiquement tous les modules de src/server/Maps, vérifie qu'ils
	respectent le format commun et qu'ils ont une entrée dans MapInfo.
	Les fichiers commençant par "_" (modèle) et "MapBase" sont ignorés.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local MapInfo = require(Shared.MapInfo)
local Config = require(Shared.Config)

local MapRegistry = {}

local REQUIRED_FUNCTIONS = { "Build", "GetSpawns", "StartMode", "StopMode", "Cleanup" }
local IGNORED = { MapBase = true }

local maps: { [string]: any } = {}
local orderedIds: { string } = {}

function MapRegistry.Init(mapsFolder: Instance)
	maps = {}
	orderedIds = {}
	for _, child in mapsFolder:GetChildren() do
		if not child:IsA("ModuleScript") then
			continue
		end
		if IGNORED[child.Name] or string.sub(child.Name, 1, 1) == "_" then
			continue
		end
		local ok, module = pcall(require, child)
		if not ok then
			warn(string.format("[MapRegistry] Impossible de charger %s : %s", child.Name, tostring(module)))
			continue
		end
		if type(module) ~= "table" or type(module.Id) ~= "string" then
			warn(string.format("[MapRegistry] %s n'expose pas un Id valide", child.Name))
			continue
		end
		if not MapInfo.IsValid(module.Id) then
			warn(string.format("[MapRegistry] %s : Id '%s' absent de Shared/MapInfo", child.Name, module.Id))
			continue
		end
		local valid = true
		for _, fnName in REQUIRED_FUNCTIONS do
			if type(module[fnName]) ~= "function" then
				warn(string.format("[MapRegistry] %s : fonction manquante %s()", child.Name, fnName))
				valid = false
			end
		end
		if not valid then
			continue
		end
		maps[module.Id] = module
		table.insert(orderedIds, module.Id)
	end
	table.sort(orderedIds)
	if Config.Debug.VerboseLogs then
		print(string.format("[MapRegistry] %d map(s) chargée(s) : %s", #orderedIds, table.concat(orderedIds, ", ")))
	end
	assert(#orderedIds > 0, "[MapRegistry] Aucune map valide trouvée")
end

function MapRegistry.Get(id: string)
	return maps[id]
end

function MapRegistry.GetIds(): { string }
	return table.clone(orderedIds)
end

-- Tire n maps distinctes au hasard (moins si pas assez de maps).
function MapRegistry.PickRandom(n: number): { string }
	local pool = table.clone(orderedIds)
	local picked = {}
	while #picked < n and #pool > 0 do
		local index = math.random(#pool)
		table.insert(picked, pool[index])
		table.remove(pool, index)
	end
	return picked
end

-- ---------------------------------------------------------------------------
-- Rotation : les maps jouées récemment passent après les autres
-- ---------------------------------------------------------------------------
local lastPlayed: { [string]: number } = {}
local roundCounter = 0

function MapRegistry.MarkPlayed(id: string)
	roundCounter += 1
	lastPlayed[id] = roundCounter
end

-- Ancienneté : plus c'est grand, plus la map attend son tour (jamais jouée = très grand)
function MapRegistry.Staleness(id: string): number
	local last = lastPlayed[id]
	return last and (roundCounter - last) or math.huge
end

-- Candidats au vote : en priorité les maps qui n'ont pas été jouées depuis
-- longtemps (hasard entre maps d'ancienneté égale). La dernière map jouée
-- n'est proposée que s'il n'y a pas assez d'autres maps.
function MapRegistry.PickRotation(n: number): { string }
	local pool = table.clone(orderedIds)
	local keys = {}
	for _, id in pool do
		keys[id] = MapRegistry.Staleness(id) + math.random() * 0.5
	end
	table.sort(pool, function(a, b)
		return keys[a] > keys[b]
	end)
	local picked = {}
	for i = 1, math.min(n, #pool) do
		picked[i] = pool[i]
	end
	return picked
end

return MapRegistry

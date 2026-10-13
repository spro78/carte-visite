--[[
	MapRegistry.lua
	Charge automatiquement tous les modules de src/server/Maps, vérifie qu'ils
	respectent le format commun et qu'ils ont une entrée dans MapInfo.
	Les fichiers commençant par "_" (modèle) et "MapBase" sont ignorés.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local MapInfo = require(Shared.MapInfo)
local ModeInfo = require(Shared.ModeInfo)
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
-- Rotation : les options (mode + carte) jouées récemment passent après les autres
-- ---------------------------------------------------------------------------
local lastPlayed: { [string]: number } = {} -- carte -> manche
local lastMode: { [string]: number } = {} -- mode -> manche
local roundCounter = 0

-- Option "Carte/Mode" ou carte seule (ancien format)
function MapRegistry.MarkPlayed(option: string)
	roundCounter += 1
	local mapId, modeId = ModeInfo.Split(option)
	lastPlayed[mapId or option] = roundCounter
	if modeId then
		lastMode[modeId] = roundCounter
	end
end

-- Ancienneté : plus c'est grand, plus la carte attend son tour (jamais jouée = très grand)
function MapRegistry.Staleness(id: string): number
	local last = lastPlayed[id]
	return last and (roundCounter - last) or math.huge
end

function MapRegistry.ModeStaleness(modeId: string): number
	local last = lastMode[modeId]
	return last and (roundCounter - last) or math.huge
end

-- Modes jouables d'une carte (au moins son mode historique)
function MapRegistry.GetModes(mapId: string): { string }
	local def = MapInfo.Get(mapId)
	return def and def.Modes or {}
end

-- Cartes de la rotation (Config.Round.MapPool), parmi celles qui sont chargées
function MapRegistry.GetPool(): { string }
	local pool = {}
	for _, id in Config.Round.MapPool or orderedIds do
		if maps[id] then
			table.insert(pool, id)
		end
	end
	if #pool == 0 then
		pool = table.clone(orderedIds)
	end
	return pool
end

-- Options du vote : n couples (mode, carte), des modes différents d'abord.
-- Les modes joués il y a le plus longtemps passent en premier (rotation
-- équitable), puis les cartes qui attendent leur tour ; le hasard départage.
function MapRegistry.PickOptions(n: number): { string }
	local options = {}
	for _, mapId in MapRegistry.GetPool() do
		for _, modeId in MapRegistry.GetModes(mapId) do
			if ModeInfo.Get(modeId) then
				table.insert(options, {
					Id = ModeInfo.Option(mapId, modeId),
					Mode = modeId,
					Key = math.min(MapRegistry.ModeStaleness(modeId), 1e6) * 1000 + math.min(MapRegistry.Staleness(mapId), 999) + math.random() * 0.5,
				})
			end
		end
	end
	table.sort(options, function(a, b)
		return a.Key > b.Key
	end)
	local picked, usedModes = {}, {}
	for _, option in options do
		if #picked < n and not usedModes[option.Mode] then
			usedModes[option.Mode] = true
			table.insert(picked, option.Id)
		end
	end
	for _, option in options do
		if #picked < n and not table.find(picked, option.Id) then
			table.insert(picked, option.Id)
		end
	end
	return picked
end

-- Ancien vote par carte (compatibilité des outils)
function MapRegistry.PickRotation(n: number): { string }
	local pool = MapRegistry.GetPool()
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

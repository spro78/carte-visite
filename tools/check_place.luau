--[[
	check_place.luau : contrôle d'une place construite par Rojo (fichier .rbxl),
	sans Studio. Lit le fichier avec la bibliothèque Roblox de Lune et vérifie :
	  - les deux points d'entrée (Script serveur, LocalScript client) ;
	  - les modules attendus (services, cartes, modes, kit 3D) ;
	  - les données du kit : un module de meshes par asset du manifeste ;
	  - qu'aucun script n'est désactivé et que la place démarre vide
	    (pas de Baseplate : la carte et le lobby sont construits par le code).
	Usage : lune run tools/check_place.luau <place.rbxl>
	Ce contrôle prouve que le fichier est complet et lisible. Il ne remplace
	pas un test dans Roblox Studio.
]]

local fs = require("@lune/fs")
local process = require("@lune/process")
local roblox = require("@lune/roblox")

local path = process.args[1]
assert(path, "usage : lune run tools/check_place.luau <place.rbxl>")

local game = roblox.deserializePlace(fs.readFile(path))
local failures = 0

local function check(ok: boolean, label: string)
	print((ok and "  OK     " or "  ÉCHEC  ") .. label)
	if not ok then
		failures += 1
	end
end

local function find(root: any, names: { string }): any
	local node = root
	for _, name in names do
		node = node and node:FindFirstChild(name)
	end
	return node
end

local counts: { [string]: number } = {}
local disabled = {}
local biggest, biggestName = 0, ""
local totalSource = 0
for _, inst in game:GetDescendants() do
	counts[inst.ClassName] = (counts[inst.ClassName] or 0) + 1
	if inst:IsA("LuaSourceContainer") then
		local source = inst.Source
		totalSource += #source
		if #source > biggest then
			biggest, biggestName = #source, inst:GetFullName()
		end
		if inst:IsA("Script") and inst.Disabled then
			table.insert(disabled, inst:GetFullName())
		end
	end
end

print(string.format("Place : %s (%d octets)", path, #fs.readFile(path)))
print(string.format(
	"  %d Script, %d LocalScript, %d ModuleScript, %d Folder ; %d Ko de code",
	counts.Script or 0,
	counts.LocalScript or 0,
	counts.ModuleScript or 0,
	counts.Folder or 0,
	totalSource // 1024
))

local server = find(game, { "ServerScriptService", "Server" })
local client = find(game, { "StarterPlayer", "StarterPlayerScripts", "Client" })
local shared = find(game, { "ReplicatedStorage", "Shared" })
local main = server and server:FindFirstChild("Main")
local clientMain = client and client:FindFirstChild("Main")
check(main ~= nil and main.ClassName == "Script", "ServerScriptService.Server.Main est un Script")
check(clientMain ~= nil and clientMain.ClassName == "LocalScript", "StarterPlayerScripts.Client.Main est un LocalScript")
check(#disabled == 0, "aucun script désactivé" .. (#disabled > 0 and (" : " .. table.concat(disabled, ", ")) or ""))

local expected = {
	{ "ServerScriptService", "Server", "Services", "RoundService" },
	{ "ServerScriptService", "Server", "Services", "CaptureService" },
	{ "ServerScriptService", "Server", "Services", "RescueService" },
	{ "ServerScriptService", "Server", "Services", "SafeZoneService" },
	{ "ServerScriptService", "Server", "Services", "VoteService" },
	{ "ServerScriptService", "Server", "Maps", "TheCarousel" },
	{ "ServerScriptService", "Server", "Maps", "MapBase" },
	{ "ServerScriptService", "Server", "Modes", "Chase" },
	{ "ServerScriptService", "Server", "Modes", "EggRun" },
	{ "ServerScriptService", "Server", "Modes", "Carousel" },
	{ "ServerScriptService", "Server", "Util", "Kit" },
	{ "StarterPlayer", "StarterPlayerScripts", "Client", "Controllers", "KitController" },
	{ "StarterPlayer", "StarterPlayerScripts", "Client", "UI", "HUD" },
	{ "ReplicatedStorage", "Shared", "Config" },
	{ "ReplicatedStorage", "Shared", "Kit", "Manifest" },
	{ "ReplicatedStorage", "Shared", "Kit", "KitMesh" },
	{ "ReplicatedStorage", "Shared", "Kit", "Palettes" },
	{ "ReplicatedStorage", "Shared", "Kit", "Layouts" },
}
local missing = {}
for _, names in expected do
	local node = find(game, names)
	if not node or node.ClassName ~= "ModuleScript" then
		table.insert(missing, table.concat(names, "."))
	end
end
check(#missing == 0, string.format("%d modules clés présents", #expected - #missing) .. (#missing > 0 and (" ; manquants : " .. table.concat(missing, ", ")) or ""))

-- Kit 3D : un module de meshes par asset du manifeste
local manifest = find(game, { "ReplicatedStorage", "Shared", "Kit", "Manifest" })
local meshes = find(game, { "ReplicatedStorage", "Shared", "Kit", "Meshes" })
local assets = {}
if manifest then
	for name in string.gmatch(manifest.Source, '\n\t(%w+) = {\n\t\tCategory') do
		table.insert(assets, name)
	end
end
local noData = {}
for _, name in assets do
	local module = meshes and meshes:FindFirstChild(name)
	if not module or module.ClassName ~= "ModuleScript" or #module.Source < 100 then
		table.insert(noData, name)
	end
end
check(#assets > 0 and #noData == 0, string.format("kit 3D : %d assets au manifeste, données de meshes pour chacun", #assets) .. (#noData > 0 and (" ; sans données : " .. table.concat(noData, ", ")) or ""))
print(string.format("  plus gros script : %s (%d Ko)", biggestName, biggest // 1024))

-- Place vide : tout est construit par le code au démarrage
local workspace = game:GetService("Workspace")
local stray = {}
for _, child in workspace:GetChildren() do
	if child.ClassName ~= "Camera" and child.ClassName ~= "Terrain" then
		table.insert(stray, child.Name)
	end
end
check(#stray == 0, "Workspace vide au départ (pas de Baseplate ni de SpawnLocation)" .. (#stray > 0 and (" : " .. table.concat(stray, ", ")) or ""))
local lighting = game:GetService("Lighting")
check(tostring(lighting.Technology) == "Enum.Technology.Future", "éclairage Future")

if failures > 0 then
	print(string.format("%d contrôle(s) en échec", failures))
	process.exit(1)
end
print("Place complète et lisible (contrôle hors Studio).")

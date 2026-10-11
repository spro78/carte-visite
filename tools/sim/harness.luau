--!nocheck
--[[
	harness.luau : utilitaires communs aux scénarios de test.
]]

local process = require("@lune/process")
local World = require("./world")
local Engine = World.Engine

local H = {}
H.World = World
H.Engine = Engine
H.Roblox = Engine.Roblox
H.failures = {}
H.passes = 0
H.server = {}

function H.check(condition, message)
	if condition then
		H.passes += 1
		print("  \27[32mOK\27[0m   " .. message)
	else
		table.insert(H.failures, message)
		print("  \27[31mFAIL\27[0m " .. message)
	end
	return condition
end

function H.section(name)
	print("\n== " .. name)
end

-- Démarre le serveur ; configure(Config) permet d'ajuster Config avant le lancement
function H.boot(configure)
	Engine.Quiet = true
	World.LoadSourcemap(process.args[1] or "sourcemap.json")
	if configure then
		Engine.Run("server", function()
			configure(World.Require(World.game.ReplicatedStorage.Shared.Config))
		end)
	end
	Engine.Run("server", function()
		World.StartServer()
	end)
	Engine.Advance(0.5)
	Engine.Run("server", function()
		local services = World.game.ServerScriptService.Server.Services
		for _, name in { "RoundState", "ActorService", "RoundService", "TeamService", "CaptureService", "AbilityService" } do
			H.server[name] = World.Require(services[name])
		end
		H.server.Config = World.Require(World.game.ReplicatedStorage.Shared.Config)
		H.server.Teams = World.Require(World.game.ReplicatedStorage.Shared.Teams)
		H.server.Mechanics = World.Require(World.game.ReplicatedStorage.Shared.Mechanics)
	end)
	return H.server
end

function H.require(path)
	local result
	Engine.Run("server", function()
		result = World.Require(path)
	end)
	return result
end

function H.onServer(fn)
	local result
	Engine.Run("server", function()
		result = fn()
	end)
	return result
end

function H.advanceUntil(predicate, maxSeconds, step)
	local t = 0
	step = step or 0.25
	while t < maxSeconds do
		if predicate() then
			return true
		end
		Engine.Advance(step)
		t += step
	end
	return predicate()
end

function H.phase()
	return H.server.RoundState.Phase
end

-- Téléporte un acteur (côté serveur)
function H.teleport(actor, position)
	H.onServer(function()
		local CFrame = Engine.Roblox.CFrame
		actor.Character:PivotTo(CFrame.new(position))
		actor.Character.HumanoidRootPart.AssemblyLinearVelocity = Engine.Roblox.Vector3.zero
	end)
end

function H.finish()
	print(string.format("\n%d vérifications OK, %d échec(s), %d erreur(s) d'exécution, %d avertissement(s)", H.passes, #H.failures, #Engine.Errors, #World.Warnings))
	for _, w in World.Warnings do
		print("  warn: " .. w)
	end
	for _, e in Engine.Errors do
		print(e)
	end
	process.exit((#H.failures > 0 or #Engine.Errors > 0) and 1 or 0)
end

return H

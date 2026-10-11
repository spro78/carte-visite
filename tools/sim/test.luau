--!nocheck
-- Test de fumée : démarre le serveur, ajoute un joueur client, simule du temps.
local process = require("@lune/process")
local World = require("./world")
local Engine = World.Engine

World.LoadSourcemap(process.args[1] or "sourcemap.json")
Engine.Run("server", function()
	World.StartServer()
end)
Engine.Advance(1)
local p1 = World.AddPlayer("Malcom", { client = true })
Engine.Advance(60)
print("Phase:", #Engine.Errors, "errors")
for k, v in Engine.RemoteCalls do
	print(k, v)
end
process.exit(#Engine.Errors > 0 and 1 or 0)

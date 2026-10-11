--!nocheck
-- Scénario ÉCONOMIE : pièces, boutique, consommables, sauvegarde, échecs DataStore.
local H = require("./harness")
local World, Engine = H.World, H.Engine
local Vector3 = H.Roblox.Vector3
local server = H.boot(function(Config)
	Config.Debug.ForceMap = "TheSwamp"
	Config.Debug.DisableBots = true
	Config.Debug.FastRounds = true
end)
local check, section = H.check, H.section
local DataService = H.require(World.game.ServerScriptService.Server.Data.DataService)
local cfg = server.Config

section("Chargement du profil")
local alice = World.AddPlayer("Alice", { client = true, UserId = 501 })
local bob = World.AddPlayer("Bob", { UserId = 502 })
local carl = World.AddPlayer("Carl", { UserId = 503 })
Engine.Advance(2)
local profile = DataService.Get(alice)
check(profile ~= nil and profile.Coins == cfg.Economy.StartingCoins, "nouveau profil avec " .. cfg.Economy.StartingCoins .. " pièces")
check(DataService.IsSaved(alice), "profil sauvegardable (verrou de session pris)")
local stored = World.DataStores["D:" .. cfg.Data.StoreName].data["Player_501"]
check(stored and stored.Lock and stored.Lock.JobId ~= nil, "verrou de session écrit dans le DataStore")
check((Engine.RemoteCalls["DataUpdate:FireClient"] or 0) > 0, "profil envoyé au client")

section("Boutique")
local purchase = function(player, cat, id)
	Engine.Run(player, function()
		local Remotes = World.Require(World.game.ReplicatedStorage.Shared.Remotes)
		Remotes.Get("ShopPurchase"):FireServer(cat, id)
	end)
	Engine.Advance(0.6)
end
DataService.AddCoins(alice, 1000)
local before = profile.Coins
purchase(alice, "Upgrades", "DashCooldown")
check(profile.Upgrades.DashCooldown == 1, "amélioration achetée (niveau 1)")
check(profile.Coins == before - cfg.Shop.Upgrades.DashCooldown.Prices[1], "prix débité")
check(math.abs((alice.Character:GetAttribute("DashCooldown") or 0) - cfg.Movement.DashCooldown * 0.9) < 0.01, "recharge du dash réduite de 10 %")
purchase(alice, "Consumables", "Shield")
purchase(alice, "Consumables", "Trap")
check(profile.Consumables.Shield == 1 and profile.Consumables.Trap == 1, "consommables achetés")
local coins = profile.Coins
purchase(alice, "Upgrades", "NotAnUpgrade")
purchase(alice, 42, {})
purchase(alice, "Consumables", "Shield")
check(profile.Coins == coins - cfg.Shop.Consumables.Shield.Price, "intentions invalides ignorées, achat valide accepté")
profile.Coins = 10
purchase(alice, "Looks", "Crown")
check(not profile.OwnedLooks.Crown, "achat refusé sans assez de pièces")
profile.Coins = 1000
purchase(alice, "Looks", "Crown")
Engine.Run(alice, function()
	World.Require(World.game.ReplicatedStorage.Shared.Remotes).Get("ShopEquip"):FireServer("Looks", "Crown")
end)
Engine.Advance(0.3)
check(profile.EquippedLook == "Crown" and alice.Character:FindFirstChild("HoH_Cosmetics") ~= nil, "chapeau acheté et équipé (ajouté par-dessus l'avatar)")

section("Pièces pendant une manche")
check(H.advanceUntil(function()
	return H.phase() == "Round"
end, 60), "manche lancée")
local A = server.ActorService.FromPlayer(alice)
local B = server.ActorService.FromPlayer(bob)
local C = server.ActorService.FromPlayer(carl)
local O = cfg.World.MapOrigin
H.teleport(A, O + Vector3.new(-100, 3, -100))
H.teleport(B, O + Vector3.new(100, 3, -100))
H.teleport(C, O + Vector3.new(0, 3, 110))
Engine.Advance(3)
-- Bouclier : la première capture de Alice est bloquée
local use = function(id)
	Engine.Run(alice, function()
		World.Require(World.game.ReplicatedStorage.Shared.Remotes).Get("UseConsumable"):FireServer(id)
	end)
	Engine.Advance(0.2)
end
use("Shield")
check(alice.Character:GetAttribute("Shield") == true, "bouclier activé")
local predator = (server.Teams.CanCatch(B.Team, A.Team) and B) or C
local aliceTeam = A.Team
H.teleport(predator, alice.Character.HumanoidRootPart.Position + Vector3.new(2, 0, 0))
Engine.Advance(0.4)
check(A.Team == aliceTeam, "le bouclier bloque la capture")
check(alice.Character:GetAttribute("Shield") == nil, "bouclier consommé")
Engine.Advance(1.5)
H.teleport(predator, O + Vector3.new(60, 3, 60))
-- Piège
H.teleport(A, O + Vector3.new(-60, 3, 0))
Engine.Advance(0.2)
use("Trap")
-- Alice s'éloigne, puis un ennemi marche sur le piège
H.teleport(A, O + Vector3.new(-90, 3, -40))
Engine.Advance(0.2)
local enemy = (B.Team ~= A.Team and B) or C
H.teleport(enemy, O + Vector3.new(-60, 3, 1))
Engine.Advance(0.2)
check(enemy.Character:GetAttribute("Frozen") == true, "le piège gèle un ennemi")
Engine.Advance(cfg.Shop.Consumables.Trap.StunSeconds + 0.2)
check(enemy.Character:GetAttribute("Frozen") == nil, "dégel après " .. cfg.Shop.Consumables.Trap.StunSeconds .. " s")
-- Capture par Alice : pièces
H.teleport(enemy, O + Vector3.new(60, 3, 60))
local prey = (server.Teams.CanCatch(A.Team, B.Team) and B) or (server.Teams.CanCatch(A.Team, C.Team) and C)
check(prey ~= nil, "Alice a une proie")
if prey then
	local c0 = profile.Coins
	Engine.Advance(2.5)
	H.teleport(prey, alice.Character.HumanoidRootPart.Position + Vector3.new(2, 0, 0))
	Engine.Advance(0.4)
	check(profile.Coins == c0 + cfg.Economy.CoinsPerCapture, "+" .. cfg.Economy.CoinsPerCapture .. " pièces pour une capture")
	check(profile.Stats.Captures == 1, "statistique Captures = 1")
end
local rewardsBefore = Engine.RemoteCalls["RoundReward:FireClient"] or 0
check(H.advanceUntil(function()
	return H.phase() == "Results"
end, 120, 1), "fin de manche")
Engine.Advance(0.5)
check((Engine.RemoteCalls["RoundReward:FireClient"] or 0) >= rewardsBefore + 3, "récapitulatif des pièces envoyé à chaque joueur")
check(profile.Stats.RoundsPlayed == 1, "RoundsPlayed = 1")

section("Sauvegarde, départ et retour")
local coinsAtLeave = profile.Coins
World.RemovePlayer(alice)
Engine.Advance(2)
stored = World.DataStores["D:" .. cfg.Data.StoreName].data["Player_501"]
check(stored.Coins == coinsAtLeave, "pièces sauvegardées au départ (" .. coinsAtLeave .. ")")
check(stored.Lock == nil, "verrou libéré au départ")
check(stored.EquippedLook == "Crown", "apparence sauvegardée")
local wins = World.DataStores["O:" .. cfg.Data.LeaderboardCaptures]
check(wins and wins.data["501"] ~= nil, "classement global mis à jour")
local alice2 = World.AddPlayer("Alice", { UserId = 501 })
Engine.Advance(2)
check(DataService.Get(alice2).Coins == coinsAtLeave, "profil rechargé au retour")

section("Panne du DataStore")
World.DataStoreFailRate = 1
local dave = World.AddPlayer("Dave", { UserId = 504 })
Engine.Advance(30)
check(DataService.Get(dave) ~= nil and not DataService.IsSaved(dave), "panne : profil en session seulement")
local before2 = World.DataStores["D:" .. cfg.Data.StoreName].data["Player_504"]
World.DataStoreFailRate = 0
DataService.AddCoins(dave, 500)
World.RemovePlayer(dave)
Engine.Advance(2)
check(World.DataStores["D:" .. cfg.Data.StoreName].data["Player_504"] == before2, "rien n'est écrit pour un profil non chargé")

section("Fermeture du serveur")
DataService.AddCoins(bob, 77)
local bobCoins = DataService.Get(bob).Coins
World.Shutdown()
check(World.DataStores["D:" .. cfg.Data.StoreName].data["Player_502"].Coins == bobCoins, "BindToClose sauvegarde tout le monde")
H.finish()

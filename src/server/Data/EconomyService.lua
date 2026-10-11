--[[
	EconomyService.lua
	Pièces et statistiques, décidées uniquement par le serveur :
	  - capture : CoinsPerCapture au chasseur ;
	  - objectif (œuf ramené, œuf volé...) : CoinsPerObjective ;
	  - fin de manche : participation + survie (par minute sans être attrapé)
	    + victoire ;
	  - Game Pass VIP (si son identifiant est renseigné) : pièces multipliées.
	Branché sur RoundService via RoundService.SetRewardHandler(EconomyService).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Remotes = require(Shared.Remotes)
local Types = require(Shared.Types)
local DataService = require(script.Parent.DataService)

type Actor = Types.Actor

local EconomyService = {}

-- Pièces gagnées pendant la manche en cours (pour le récapitulatif)
type Ledger = { Captures: number, Objectives: number }
local ledger: { [Player]: Ledger } = {}
local multiplierProvider: ((Player) -> number)? = nil

local function multiplier(player: Player): number
	if multiplierProvider then
		return multiplierProvider(player)
	end
	return 1
end

local function getLedger(player: Player): Ledger
	local entry = ledger[player]
	if not entry then
		entry = { Captures = 0, Objectives = 0 }
		ledger[player] = entry
	end
	return entry
end

-- Fournisseur de multiplicateur (Game Pass VIP)
function EconomyService.SetMultiplierProvider(provider: (Player) -> number)
	multiplierProvider = provider
end

function EconomyService.OnCapture(hunter: Actor, victim: Actor)
	if hunter.Player then
		local coins = Config.Economy.CoinsPerCapture * multiplier(hunter.Player)
		DataService.AddCoins(hunter.Player, coins, true)
		DataService.AddStat(hunter.Player, "Captures", 1)
		getLedger(hunter.Player).Captures += coins
		Remotes.Get("Effect"):FireClient(hunter.Player, "Coins", { Amount = coins })
	end
	if victim.Player then
		DataService.AddStat(victim.Player, "TimesCaught", 1)
	end
end

function EconomyService.OnObjective(actor: Actor, _reason: string)
	if actor.Player then
		local coins = Config.Economy.CoinsPerObjective * multiplier(actor.Player)
		DataService.AddCoins(actor.Player, coins, true)
		DataService.AddStat(actor.Player, "Objectives", 1)
		getLedger(actor.Player).Objectives += coins
		Remotes.Get("Effect"):FireClient(actor.Player, "Coins", { Amount = coins })
	end
end

-- Fin de manche : participation, survie, victoire + récapitulatif
function EconomyService.OnRoundEnd(participants: { Actor }, winner: string?, duration: number)
	local cfg = Config.Economy
	for _, actor in participants do
		local player = actor.Player
		if not player then
			continue
		end
		local mult = multiplier(player)
		local entry = getLedger(player)
		local lines = {}
		local total = 0
		local function add(label: string, amount: number)
			amount = math.floor(amount * mult)
			if amount > 0 then
				table.insert(lines, { label, amount })
				total += amount
			end
		end
		if entry.Captures > 0 then
			table.insert(lines, { "Catches", entry.Captures })
		end
		if entry.Objectives > 0 then
			table.insert(lines, { "Objectives", entry.Objectives })
		end
		add("Played", cfg.CoinsForParticipation)
		local survived = math.min(duration, os.clock() - actor.LastCaughtAt)
		add("Survival", math.floor(survived / 60) * cfg.CoinsPerSurvivalMinute)
		local won = winner ~= nil and actor.Team == winner
		if won then
			add("Victory", cfg.CoinsForWin)
		end
		DataService.AddCoins(player, total, true)
		DataService.AddStat(player, "RoundsPlayed", 1)
		if won then
			DataService.AddStat(player, "Wins", 1)
		end
		local grand = total + entry.Captures + entry.Objectives
		local profile = DataService.Get(player)
		local xpBefore = profile and profile.XP or 0
		local levelBefore, levelAfter, unlocks = DataService.AddXP(player, grand + cfg.XPPerRound)
		Remotes.Get("RoundReward"):FireClient(player, {
			Total = grand,
			Lines = lines,
			Won = won,
			Multiplier = mult,
			XPGained = grand + cfg.XPPerRound,
			XPBefore = xpBefore,
			LevelBefore = levelBefore,
			Level = levelAfter,
			XP = profile and profile.XP or 0,
			XPNeeded = DataService.XPForLevel(levelAfter),
			Unlocks = unlocks,
		})
	end
	table.clear(ledger)
end

return EconomyService

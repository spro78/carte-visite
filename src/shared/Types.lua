--[[
	Types.lua
	Types Luau partagés. Ce module n'exporte que des types (table vide au runtime).
]]

local Types = {}

export type Phase = "Waiting" | "Intermission" | "Countdown" | "Round" | "Results"

-- État envoyé à tous les clients par le serveur (RemoteEvent StateUpdate)
export type GameState = {
	Phase: string,
	TimeLeft: number, -- secondes restantes dans la phase courante
	MapId: string?, -- map en cours (ou gagnante du vote)
	Candidates: { string }, -- maps proposées au vote
	Votes: { [string]: number }, -- votes par mapId
	TeamCounts: { [string]: number }, -- membres par équipe (joueurs + bots)
	Scores: { [string]: number }, -- score du mode par équipe
	ScoreGoal: number?, -- score à atteindre (si le mode en a un)
	ScoreLabel: string?, -- libellé du score ("Eggs", "Points"...)
	Winner: string?, -- équipe gagnante ("DRAW" possible) pendant Results
	WinReason: string?, -- "Objective" | "LastStanding" | "TimeUp" | "Draw"
	BestHunter: string?, -- pseudo du meilleur chasseur
	BestHunterCaptures: number?,
}

-- Un acteur = un participant (vrai joueur ou bot)
export type Actor = {
	Id: string,
	Name: string,
	Player: Player?,
	IsBot: boolean,
	Character: Model?,
	Team: string?,
	RoundCaptures: number,
	RoundObjectives: number,
	LastCaughtAt: number,
	Data: any?, -- profil sauvegardé (joueurs seulement)
}

-- Contexte fourni par RoundService à chaque module de map
export type MapContext = {
	Origin: Vector3,
	GetActors: () -> { Actor }, -- participants de la manche
	GetTeam: (Actor) -> string?,
	GetRoot: (Actor) -> BasePart?,
	AddScore: (string, number) -> (),
	SetScore: (string, number) -> (),
	GetScore: (string) -> number,
	SetScoreInfo: (goal: number?, label: string?) -> (),
	Announce: (string, Color3?) -> (),
	AnnounceTo: (Actor, string, Color3?) -> (),
	RewardObjective: (Actor, string) -> (), -- pièces + stats pour un objectif
	Launch: (Actor, Vector3, number?) -> (), -- éjection (ragdoll)
	SetSpeedModifier: (Actor, string, number?) -> (), -- nil = retirer
	SetObjective: (string, Vector3?) -> (), -- cible de la flèche pour une équipe
	SetActorObjective: (Actor, Vector3?) -> (), -- cible de la flèche pour un acteur
	SetCarrier: (Actor, boolean) -> (), -- porteur : visible de tous, ne peut pas se cacher
	EndRound: (string?, string) -> (),
	IsRoundActive: () -> boolean,
}

-- Format commun de toutes les maps (voir src/server/Maps/_Template.lua)
export type MapModule = {
	Id: string,
	Build: (origin: Vector3, context: MapContext) -> (),
	GetSpawns: (team: string) -> { CFrame },
	StartMode: (context: MapContext) -> (),
	StopMode: () -> (),
	Cleanup: () -> (),
	-- Optionnels
	OnCapture: ((hunter: Actor, victim: Actor) -> ())?,
	OnActorRemoved: ((actor: Actor) -> ())?,
	ResolveTimeUp: (() -> string?)?, -- vainqueur à la fin du chrono (sinon : équipe la plus nombreuse)
	GetBotGoal: ((actor: Actor) -> Vector3?)?, -- où un bot doit aller quand il ne chasse/fuit pas
	IsCarrier: ((actor: Actor) -> boolean)?, -- l'acteur porte-t-il un objectif ?
	Lighting: { [string]: any }?, -- propriétés de Lighting appliquées pendant la manche
}

return Types

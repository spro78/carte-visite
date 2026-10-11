--[[
	Types.lua
	Types Luau partagés. Ce module n'exporte que des types (table vide au runtime).
]]

local Types = {}

export type TeamId = "FOX" | "CHICKEN" | "SNAKE"

export type Phase = "Waiting" | "Intermission" | "Countdown" | "Round" | "Results"

-- État envoyé à tous les clients par le serveur (RemoteEvent StateUpdate)
export type GameState = {
	Phase: Phase,
	TimeLeft: number, -- secondes restantes dans la phase courante
	MapId: string?, -- map en cours (ou gagnante du vote)
	Candidates: { string }, -- maps proposées au vote
	Votes: { [string]: number }, -- votes par mapId
	TeamCounts: { [string]: number }, -- joueurs par équipe
	Scores: { [string]: number }, -- score du mode par équipe
	Winner: string?, -- équipe gagnante ("DRAW" possible) pendant Results
	WinReason: string?, -- "Objective" | "LastStanding" | "TimeUp" | "Draw"
	BestHunter: string?, -- pseudo du meilleur chasseur
	BestHunterCaptures: number?,
}

-- Contexte fourni par RoundService à chaque module de map
export type MapContext = {
	Origin: Vector3,
	GetParticipants: () -> { Player },
	GetTeam: (Player) -> TeamId?,
	AddScore: (TeamId, number) -> (),
	GetScore: (TeamId) -> number,
	Announce: (string, Color3?) -> (),
	EndRound: (TeamId?, string) -> (),
	IsRoundActive: () -> boolean,
}

-- Format commun de toutes les maps (voir src/server/Maps/_Template.lua)
export type MapModule = {
	Id: string,
	Build: (origin: Vector3, context: MapContext) -> (),
	GetSpawns: (team: TeamId) -> { CFrame },
	StartMode: (context: MapContext) -> (),
	StopMode: () -> (),
	Cleanup: () -> (),
}

return Types

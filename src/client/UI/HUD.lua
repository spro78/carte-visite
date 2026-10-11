--[[
	HUD.lua
	Interface construite entièrement par le code (style cartoon, tailles en
	échelle pour rester lisible sur mobile).
	Phase 1 : bandeau de rôle, chrono, panneau des équipes, annonces centrales,
	panneau de vote, écran de résultats, message spectateur.
	Phase 2 : boutons tactiles dash / capacité.
]]

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Teams = require(Shared.Teams)
local MapInfo = require(Shared.MapInfo)
local Types = require(Shared.Types)

local HUD = {}

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local FONT = Enum.Font.FredokaOne
local WHITE = Color3.new(1, 1, 1)
local DARK = Color3.fromRGB(30, 32, 45)
local PANEL = Color3.fromRGB(45, 50, 70)
local ACCENT = Color3.fromRGB(255, 200, 60)

local PHASE_LABELS = {
	Waiting = "WAITING FOR PLAYERS",
	Intermission = "NEXT ROUND IN",
	Countdown = "GET READY",
	Round = "TIME LEFT",
	Results = "RESULTS",
}

local voteCallback: ((string) -> ())? = nil
local myVote: string? = nil
local lastCandidatesKey = ""

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------
local function new(className: string, props: { [string]: any }, parent: Instance?): Instance
	local inst = Instance.new(className)
	for key, value in props do
		(inst :: any)[key] = value
	end
	if parent then
		inst.Parent = parent
	end
	return inst
end

local function corner(parent: Instance, radius: number?)
	new("UICorner", { CornerRadius = UDim.new(0, radius or 12) }, parent)
end

local function stroke(parent: Instance, thickness: number?, color: Color3?)
	new("UIStroke", {
		Thickness = thickness or 2.5,
		Color = color or DARK,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	}, parent)
end

local function label(parent: Instance, props: { [string]: any }): TextLabel
	local merged = {
		BackgroundTransparency = 1,
		Font = FONT,
		TextScaled = true,
		TextColor3 = WHITE,
		Text = "",
	}
	for key, value in props do
		merged[key] = value
	end
	return new("TextLabel", merged, parent) :: TextLabel
end

local function formatTime(seconds: number): string
	seconds = math.max(0, math.floor(seconds + 0.5))
	return string.format("%d:%02d", seconds // 60, seconds % 60)
end

-- ---------------------------------------------------------------------------
-- Construction
-- ---------------------------------------------------------------------------
local screen = new("ScreenGui", {
	Name = "HuntOrHideHUD",
	ResetOnSpawn = false,
	IgnoreGuiInset = true,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	DisplayOrder = 10,
}, playerGui) :: ScreenGui

-- Bandeau de rôle (haut, centré)
local banner = new("Frame", {
	Name = "RoleBanner",
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0.015, 0),
	Size = UDim2.new(0.62, 0, 0.065, 0),
	BackgroundColor3 = DARK,
}, screen) :: Frame
corner(banner, 16)
stroke(banner, 3, WHITE)
local bannerText = label(banner, {
	Size = UDim2.fromScale(0.94, 0.75),
	Position = UDim2.fromScale(0.03, 0.125),
	Text = Teams.Rule,
})
new("UITextSizeConstraint", { MaxTextSize = 36 }, bannerText)

-- Chrono + libellé de phase (sous le bandeau)
local timerFrame = new("Frame", {
	Name = "Timer",
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0.09, 0),
	Size = UDim2.new(0.2, 0, 0.095, 0),
	BackgroundColor3 = PANEL,
}, screen) :: Frame
corner(timerFrame, 14)
stroke(timerFrame, 2.5, DARK)
local phaseText = label(timerFrame, {
	Size = UDim2.fromScale(0.9, 0.3),
	Position = UDim2.fromScale(0.05, 0.05),
	Text = PHASE_LABELS.Waiting,
	TextColor3 = ACCENT,
})
local timerText = label(timerFrame, {
	Size = UDim2.fromScale(0.9, 0.6),
	Position = UDim2.fromScale(0.05, 0.35),
	Text = "--:--",
})
local mapText = label(screen, {
	Name = "MapName",
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0.19, 0),
	Size = UDim2.new(0.4, 0, 0.03, 0),
	Text = "",
	TextStrokeTransparency = 0.4,
})

-- Panneau des équipes (haut gauche) : nom, nombre de joueurs, score
local teamPanel = new("Frame", {
	Name = "TeamPanel",
	Position = UDim2.new(0.012, 0, 0.015, 0),
	Size = UDim2.new(0.2, 0, 0.17, 0),
	BackgroundColor3 = PANEL,
}, screen) :: Frame
corner(teamPanel, 14)
stroke(teamPanel, 2.5, DARK)
new("UIListLayout", {
	FillDirection = Enum.FillDirection.Vertical,
	Padding = UDim.new(0.03, 0),
	HorizontalAlignment = Enum.HorizontalAlignment.Center,
	VerticalAlignment = Enum.VerticalAlignment.Center,
	SortOrder = Enum.SortOrder.LayoutOrder,
}, teamPanel)

local teamRows: { [string]: { Count: TextLabel, Score: TextLabel, Row: Frame } } = {}
for index, teamId in Teams.Order do
	local def = Teams.Get(teamId)
	assert(def)
	local row = new("Frame", {
		Name = teamId,
		Size = UDim2.fromScale(0.92, 0.28),
		BackgroundColor3 = def.Color,
		LayoutOrder = index,
	}, teamPanel) :: Frame
	corner(row, 10)
	label(row, {
		Size = UDim2.fromScale(0.5, 0.8),
		Position = UDim2.fromScale(0.04, 0.1),
		Text = def.Display,
		TextColor3 = DARK,
		TextXAlignment = Enum.TextXAlignment.Left,
	})
	local count = label(row, {
		Size = UDim2.fromScale(0.2, 0.8),
		Position = UDim2.fromScale(0.54, 0.1),
		Text = "0",
		TextColor3 = DARK,
	})
	local score = label(row, {
		Size = UDim2.fromScale(0.22, 0.8),
		Position = UDim2.fromScale(0.75, 0.1),
		Text = "",
		TextColor3 = WHITE,
		TextStrokeTransparency = 0.3,
	})
	teamRows[teamId] = { Count = count, Score = score, Row = row }
end

-- Annonce centrale
local announceLabel = label(screen, {
	Name = "Announce",
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.new(0.5, 0, 0.32, 0),
	Size = UDim2.new(0.8, 0, 0.09, 0),
	Text = "",
	TextStrokeTransparency = 0,
	TextStrokeColor3 = DARK,
	Visible = false,
})
new("UITextSizeConstraint", { MaxTextSize = 64 }, announceLabel)

-- Message spectateur
local spectatorLabel = label(screen, {
	Name = "Spectator",
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 0.93, 0),
	Size = UDim2.new(0.7, 0, 0.05, 0),
	Text = "A round is in progress. You'll join the next one!",
	TextStrokeTransparency = 0.3,
	Visible = false,
})

-- Panneau de vote (bas de l'écran, pendant l'intermission)
local votePanel = new("Frame", {
	Name = "VotePanel",
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 0.97, 0),
	Size = UDim2.new(0.82, 0, 0.24, 0),
	BackgroundTransparency = 1,
	Visible = false,
}, screen) :: Frame
label(votePanel, {
	Size = UDim2.fromScale(1, 0.2),
	Text = "VOTE FOR THE NEXT MAP",
	TextStrokeTransparency = 0.3,
})
local voteButtonsFrame = new("Frame", {
	Position = UDim2.fromScale(0, 0.22),
	Size = UDim2.fromScale(1, 0.78),
	BackgroundTransparency = 1,
}, votePanel)
new("UIListLayout", {
	FillDirection = Enum.FillDirection.Horizontal,
	Padding = UDim.new(0.02, 0),
	HorizontalAlignment = Enum.HorizontalAlignment.Center,
	VerticalAlignment = Enum.VerticalAlignment.Center,
	SortOrder = Enum.SortOrder.LayoutOrder,
}, voteButtonsFrame)

local voteButtons: { { Button: TextButton, Name: TextLabel, Mode: TextLabel, Votes: TextLabel, MapId: string?, Stroke: UIStroke } } = {}
for index = 1, 3 do
	local button = new("TextButton", {
		Name = "Vote" .. index,
		Size = UDim2.fromScale(0.3, 1),
		BackgroundColor3 = PANEL,
		Text = "",
		AutoButtonColor = true,
		LayoutOrder = index,
	}, voteButtonsFrame) :: TextButton
	corner(button, 14)
	local buttonStroke = new("UIStroke", { Thickness = 3, Color = DARK }, button) :: UIStroke
	local nameLabel = label(button, {
		Size = UDim2.fromScale(0.9, 0.38),
		Position = UDim2.fromScale(0.05, 0.05),
		Text = "?",
		TextColor3 = DARK,
	})
	local modeLabel = label(button, {
		Size = UDim2.fromScale(0.9, 0.25),
		Position = UDim2.fromScale(0.05, 0.42),
		Text = "",
		TextColor3 = DARK,
	})
	local votesLabel = label(button, {
		Size = UDim2.fromScale(0.9, 0.25),
		Position = UDim2.fromScale(0.05, 0.7),
		Text = "",
		TextColor3 = WHITE,
		TextStrokeTransparency = 0.2,
	})
	local entry = { Button = button, Name = nameLabel, Mode = modeLabel, Votes = votesLabel, MapId = nil, Stroke = buttonStroke }
	button.Activated:Connect(function()
		if entry.MapId and voteCallback then
			myVote = entry.MapId
			voteCallback(entry.MapId)
			HUD.RefreshVoteHighlight()
		end
	end)
	voteButtons[index] = entry
end

-- Écran de résultats
local resultsFrame = new("Frame", {
	Name = "Results",
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.new(0.5, 0, 0.5, 0),
	Size = UDim2.new(0.5, 0, 0.32, 0),
	BackgroundColor3 = PANEL,
	Visible = false,
}, screen) :: Frame
corner(resultsFrame, 20)
stroke(resultsFrame, 4, ACCENT)
local resultsTitle = label(resultsFrame, {
	Size = UDim2.fromScale(0.9, 0.35),
	Position = UDim2.fromScale(0.05, 0.05),
	Text = "",
})
local resultsReason = label(resultsFrame, {
	Size = UDim2.fromScale(0.9, 0.18),
	Position = UDim2.fromScale(0.05, 0.42),
	Text = "",
	TextColor3 = Color3.fromRGB(210, 220, 240),
})
local resultsHunter = label(resultsFrame, {
	Size = UDim2.fromScale(0.9, 0.18),
	Position = UDim2.fromScale(0.05, 0.62),
	Text = "",
	TextColor3 = ACCENT,
})
local resultsCoins = label(resultsFrame, {
	Size = UDim2.fromScale(0.9, 0.15),
	Position = UDim2.fromScale(0.05, 0.82),
	Text = "",
	TextColor3 = Color3.fromRGB(255, 230, 120),
})

-- ---------------------------------------------------------------------------
-- API
-- ---------------------------------------------------------------------------
function HUD.OnVote(callback: (string) -> ())
	voteCallback = callback
end

function HUD.RefreshVoteHighlight()
	for _, entry in voteButtons do
		if entry.MapId and entry.MapId == myVote then
			entry.Stroke.Color = ACCENT
			entry.Stroke.Thickness = 5
		else
			entry.Stroke.Color = DARK
			entry.Stroke.Thickness = 3
		end
	end
end

-- Met à jour le bandeau de rôle selon l'équipe du joueur local
function HUD.SetRole(teamId: string?)
	local def = Teams.Get(teamId)
	if def then
		banner.BackgroundColor3 = def.Color
		bannerText.TextColor3 = DARK
		bannerText.Text = Teams.RoleBanner(def.Id)
	else
		banner.BackgroundColor3 = DARK
		bannerText.TextColor3 = WHITE
		bannerText.Text = Teams.Rule
	end
end

local announceToken = 0
function HUD.Announce(text: string, color: Color3?)
	announceToken += 1
	local token = announceToken
	announceLabel.Text = text
	announceLabel.TextColor3 = color or WHITE
	announceLabel.TextTransparency = 0
	announceLabel.TextStrokeTransparency = 0
	announceLabel.Visible = true
	announceLabel.Size = UDim2.new(0.7, 0, 0.08, 0)
	TweenService:Create(announceLabel, TweenInfo.new(0.2, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Size = UDim2.new(0.8, 0, 0.09, 0),
	}):Play()
	task.delay(2.2, function()
		if token ~= announceToken then
			return
		end
		local tween = TweenService:Create(announceLabel, TweenInfo.new(0.4), {
			TextTransparency = 1,
			TextStrokeTransparency = 1,
		})
		tween:Play()
		tween.Completed:Connect(function()
			if token == announceToken then
				announceLabel.Visible = false
			end
		end)
	end)
end

local function updateVotePanel(state: Types.GameState)
	local key = table.concat(state.Candidates, "|")
	if key ~= lastCandidatesKey then
		lastCandidatesKey = key
		myVote = nil
	end
	for index, entry in voteButtons do
		local mapId = state.Candidates[index]
		local def = MapInfo.Get(mapId)
		entry.MapId = mapId
		if def then
			entry.Button.Visible = true
			entry.Button.BackgroundColor3 = def.Color
			entry.Name.Text = def.DisplayName
			entry.Mode.Text = def.ModeName
			local n = state.Votes[mapId] or 0
			entry.Votes.Text = string.format("%d vote%s", n, n == 1 and "" or "s")
		else
			entry.Button.Visible = false
		end
	end
	HUD.RefreshVoteHighlight()
end

local function updateResults(state: Types.GameState)
	local winnerDef = Teams.Get(state.Winner)
	if winnerDef then
		resultsTitle.Text = winnerDef.Plural .. " WIN!"
		resultsTitle.TextColor3 = winnerDef.Color
	else
		resultsTitle.Text = "DRAW!"
		resultsTitle.TextColor3 = WHITE
	end
	local reasons = {
		Objective = "Objective completed",
		LastStanding = "Last team standing",
		TimeUp = "Biggest team when time ran out",
		Draw = "No winner this time",
	}
	resultsReason.Text = reasons[state.WinReason or ""] or ""
	if state.BestHunter then
		resultsHunter.Text = string.format("Best hunter: %s (%d catches)", state.BestHunter, state.BestHunterCaptures or 0)
	else
		resultsHunter.Text = "Best hunter: -"
	end
	resultsCoins.Text = "" -- Phase 6 : pièces gagnées
end

function HUD.UpdateState(state: Types.GameState)
	local phase = state.Phase
	phaseText.Text = PHASE_LABELS[phase] or phase
	timerText.Text = (phase == "Waiting") and "--:--" or formatTime(state.TimeLeft)

	local mapDef = MapInfo.Get(state.MapId)
	mapText.Text = mapDef and (mapDef.DisplayName .. "  -  " .. mapDef.ModeName) or ""

	local inRound = phase == "Countdown" or phase == "Round" or phase == "Results"
	for teamId, row in teamRows do
		row.Count.Text = tostring(state.TeamCounts[teamId] or 0)
		row.Score.Text = inRound and tostring(state.Scores[teamId] or 0) or ""
	end
	teamPanel.Visible = inRound

	votePanel.Visible = phase == "Intermission"
	if votePanel.Visible then
		updateVotePanel(state)
	end

	local myTeam = player:GetAttribute("Team")
	spectatorLabel.Visible = (phase == "Countdown" or phase == "Round") and myTeam == nil

	resultsFrame.Visible = phase == "Results"
	if resultsFrame.Visible then
		updateResults(state)
	end
end

return HUD

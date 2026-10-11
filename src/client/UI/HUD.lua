--[[
	HUD.lua
	Interface principale construite par le code :
	  - bandeau de rôle ("You are a FOX - Catch CHICKENS - Avoid SNAKES")
	  - chrono + libellé de phase + objectif de score
	  - panneau des équipes (membres et score par équipe)
	  - annonces courtes au centre
	  - panneau de vote (intermission), écran de résultats, message spectateur
	  - compteur de pièces
	Tailles en échelle + contraintes : lisible sur téléphone comme sur PC.
]]

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Teams = require(Shared.Teams)
local MapInfo = require(Shared.MapInfo)
local Types = require(Shared.Types)
local Theme = require(script.Parent.Theme)

local HUD = {}

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local New, Label = Theme.New, Theme.Label

local PHASE_LABELS = {
	Waiting = "WAITING FOR PLAYERS",
	Intermission = "NEXT ROUND IN",
	Countdown = "GET READY",
	Round = "TIME LEFT",
	Results = "RESULTS",
}

local REASONS = {
	Objective = "Objective completed!",
	LastStanding = "Last team standing!",
	TimeUp = "Time's up!",
	Draw = "No winner this time",
}

local voteCallback: ((string) -> ())? = nil
local myVote: string? = nil
local lastCandidatesKey = ""
local lastReward: { [string]: any }? = nil

-- ---------------------------------------------------------------------------
-- Construction
-- ---------------------------------------------------------------------------
local screen: ScreenGui = New("ScreenGui", {
	Name = "HuntOrHideHUD",
	ResetOnSpawn = false,
	IgnoreGuiInset = false, -- on reste sous la barre de menu de Roblox
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	DisplayOrder = 10,
}, playerGui)
HUD.Screen = screen

-- Bandeau de rôle (haut, centré)
local banner: Frame = New("Frame", {
	Name = "RoleBanner",
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 6),
	Size = UDim2.new(0.52, 0, 0.07, 0),
	BackgroundColor3 = Theme.Dark,
	BackgroundTransparency = 0.15,
}, screen)
Theme.CornerScale(banner, 0.5)
local bannerStroke = Theme.Stroke(banner, 3, Theme.White)
New("UISizeConstraint", { MaxSize = Vector2.new(760, 56), MinSize = Vector2.new(0, 24) }, banner)
local bannerText = Label(banner, {
	Name = "Text",
	Size = UDim2.fromScale(0.94, 0.78),
	Position = UDim2.fromScale(0.03, 0.11),
	Text = Teams.Rule,
})

-- Chrono (sous le bandeau)
local timerFrame: Frame = New("Frame", {
	Name = "Timer",
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0.085, 6),
	Size = UDim2.new(0.15, 0, 0.1, 0),
	BackgroundColor3 = Theme.Panel,
	BackgroundTransparency = 0.2,
}, screen)
Theme.Corner(timerFrame, 14)
Theme.Stroke(timerFrame, 2.5)
New("UISizeConstraint", { MaxSize = Vector2.new(230, 76), MinSize = Vector2.new(110, 40) }, timerFrame)
local phaseText = Label(timerFrame, {
	Name = "Phase",
	Size = UDim2.fromScale(0.9, 0.3),
	Position = UDim2.fromScale(0.05, 0.06),
	Text = PHASE_LABELS.Waiting,
	TextColor3 = Theme.Accent,
})
local timerText = Label(timerFrame, {
	Name = "Time",
	Font = Theme.FontBlack,
	Size = UDim2.fromScale(0.9, 0.58),
	Position = UDim2.fromScale(0.05, 0.36),
	Text = "--:--",
})
local subText = Label(screen, {
	Name = "SubText",
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0.19, 8),
	Size = UDim2.new(0.4, 0, 0.032, 0),
	Text = "",
	TextStrokeTransparency = 0.35,
})
Theme.MaxText(subText, 22)

-- Panneau des équipes (haut gauche)
local teamPanel: Frame = New("Frame", {
	Name = "TeamPanel",
	Position = UDim2.new(0, 8, 0, 6),
	Size = UDim2.new(0.2, 0, 0.2, 0),
	BackgroundColor3 = Theme.Panel,
	BackgroundTransparency = 0.1,
	Visible = false,
}, screen)
Theme.Corner(teamPanel, 14)
Theme.Stroke(teamPanel, 2.5)
New("UISizeConstraint", { MaxSize = Vector2.new(280, 130), MinSize = Vector2.new(150, 70) }, teamPanel)
New("UIListLayout", {
	FillDirection = Enum.FillDirection.Vertical,
	Padding = UDim.new(0.04, 0),
	HorizontalAlignment = Enum.HorizontalAlignment.Center,
	VerticalAlignment = Enum.VerticalAlignment.Center,
	SortOrder = Enum.SortOrder.LayoutOrder,
}, teamPanel)

local teamRows: { [string]: { Row: Frame, Count: TextLabel, Score: TextLabel, Stroke: UIStroke } } = {}
for index, teamId in Teams.Order do
	local def = Teams.Get(teamId)
	assert(def)
	local row: Frame = New("Frame", {
		Name = teamId,
		Size = UDim2.fromScale(0.92, 0.27),
		BackgroundColor3 = def.Color,
		LayoutOrder = index,
	}, teamPanel)
	Theme.Corner(row, 9)
	local rowStroke = Theme.Stroke(row, 0, Theme.White)
	Label(row, {
		Size = UDim2.fromScale(0.52, 0.8),
		Position = UDim2.fromScale(0.04, 0.1),
		Text = def.Display,
		TextColor3 = Theme.Dark,
		TextXAlignment = Enum.TextXAlignment.Left,
	})
	local count = Label(row, {
		Name = "Count",
		Size = UDim2.fromScale(0.18, 0.8),
		Position = UDim2.fromScale(0.56, 0.1),
		Text = "0",
		TextColor3 = Theme.Dark,
	})
	local score = Label(row, {
		Name = "Score",
		Size = UDim2.fromScale(0.22, 0.8),
		Position = UDim2.fromScale(0.76, 0.1),
		Text = "",
		TextColor3 = Theme.White,
		TextStrokeTransparency = 0.25,
	})
	teamRows[teamId] = { Row = row, Count = count, Score = score, Stroke = rowStroke }
end

-- Pièces (sous le panneau des équipes)
local coinsFrame: Frame = New("Frame", {
	Name = "Coins",
	Position = UDim2.new(0, 8, 0.22, 10),
	Size = UDim2.new(0.13, 0, 0.065, 0),
	BackgroundColor3 = Theme.Dark,
	BackgroundTransparency = 0.15,
}, screen)
Theme.CornerScale(coinsFrame, 0.5)
Theme.Stroke(coinsFrame, 2, Theme.Coin)
New("UISizeConstraint", { MaxSize = Vector2.new(170, 44), MinSize = Vector2.new(90, 26) }, coinsFrame)
local coinIcon: Frame = New("Frame", {
	Name = "Icon",
	AnchorPoint = Vector2.new(0, 0.5),
	Position = UDim2.fromScale(0.06, 0.5),
	Size = UDim2.fromScale(0.62, 0.62),
	BackgroundColor3 = Theme.Coin,
}, coinsFrame)
New("UIAspectRatioConstraint", { AspectRatio = 1 }, coinIcon)
Theme.CornerScale(coinIcon, 0.5)
Theme.Stroke(coinIcon, 2, Color3.fromRGB(190, 140, 20))
local coinsText = Label(coinsFrame, {
	Name = "Amount",
	Size = UDim2.fromScale(0.62, 0.78),
	Position = UDim2.fromScale(0.33, 0.11),
	Text = "0",
	TextColor3 = Theme.Coin,
	TextXAlignment = Enum.TextXAlignment.Left,
})

-- Annonce centrale
local announceLabel = Label(screen, {
	Name = "Announce",
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.new(0.5, 0, 0.33, 0),
	Size = UDim2.new(0.8, 0, 0.09, 0),
	Text = "",
	TextStrokeTransparency = 0,
	TextStrokeColor3 = Theme.Dark,
	Visible = false,
	ZIndex = 5,
})
Theme.MaxText(announceLabel, 60)

-- Notification courte (achats, erreurs)
local toast: TextLabel = Label(screen, {
	Name = "Toast",
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 0.74, 0),
	Size = UDim2.new(0.5, 0, 0.05, 0),
	BackgroundColor3 = Theme.Dark,
	BackgroundTransparency = 0.2,
	Text = "",
	Visible = false,
	ZIndex = 30,
})
Theme.Corner(toast, 10)
Theme.MaxText(toast, 24)
New("UIPadding", { PaddingTop = UDim.new(0.15, 0), PaddingBottom = UDim.new(0.15, 0) }, toast)

-- Message spectateur
local spectatorLabel = Label(screen, {
	Name = "Spectator",
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 0.97, 0),
	Size = UDim2.new(0.7, 0, 0.05, 0),
	Text = "A round is in progress. You'll join the next one!",
	TextStrokeTransparency = 0.3,
	Visible = false,
})
Theme.MaxText(spectatorLabel, 28)

-- Panneau de vote (bas, pendant l'intermission)
local votePanel: Frame = New("Frame", {
	Name = "VotePanel",
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 1, -8),
	Size = UDim2.new(0.7, 0, 0.24, 0),
	BackgroundTransparency = 1,
	Visible = false,
}, screen)
New("UISizeConstraint", { MaxSize = Vector2.new(820, 190) }, votePanel)
Label(votePanel, {
	Size = UDim2.fromScale(1, 0.22),
	Text = "VOTE FOR THE NEXT MAP",
	TextStrokeTransparency = 0.3,
})
local voteButtonsFrame: Frame = New("Frame", {
	Position = UDim2.fromScale(0, 0.25),
	Size = UDim2.fromScale(1, 0.75),
	BackgroundTransparency = 1,
}, votePanel)
New("UIListLayout", {
	FillDirection = Enum.FillDirection.Horizontal,
	Padding = UDim.new(0.02, 0),
	HorizontalAlignment = Enum.HorizontalAlignment.Center,
	VerticalAlignment = Enum.VerticalAlignment.Center,
	SortOrder = Enum.SortOrder.LayoutOrder,
}, voteButtonsFrame)

type VoteButton = { Button: TextButton, Name: TextLabel, Mode: TextLabel, Votes: TextLabel, MapId: string?, Stroke: UIStroke }
local voteButtons: { VoteButton } = {}

function HUD.RefreshVoteHighlight()
	for _, entry in voteButtons do
		if entry.MapId and entry.MapId == myVote then
			entry.Stroke.Color = Theme.White
			entry.Stroke.Thickness = 5
		else
			entry.Stroke.Color = Theme.Dark
			entry.Stroke.Thickness = 3
		end
	end
end

for index = 1, 3 do
	local button: TextButton = New("TextButton", {
		Name = "Vote" .. index,
		Size = UDim2.fromScale(0.31, 1),
		BackgroundColor3 = Theme.Panel,
		Text = "",
		AutoButtonColor = true,
		LayoutOrder = index,
	}, voteButtonsFrame)
	Theme.Corner(button, 14)
	local buttonStroke = Theme.Stroke(button, 3)
	local nameLabel = Label(button, {
		Size = UDim2.fromScale(0.9, 0.36),
		Position = UDim2.fromScale(0.05, 0.06),
		Text = "?",
		TextColor3 = Theme.Dark,
	})
	local modeLabel = Label(button, {
		Size = UDim2.fromScale(0.9, 0.24),
		Position = UDim2.fromScale(0.05, 0.43),
		Text = "",
		TextColor3 = Theme.Dark,
	})
	local votesLabel = Label(button, {
		Size = UDim2.fromScale(0.9, 0.24),
		Position = UDim2.fromScale(0.05, 0.7),
		Text = "",
		TextStrokeTransparency = 0.2,
	})
	local entry: VoteButton = { Button = button, Name = nameLabel, Mode = modeLabel, Votes = votesLabel, MapId = nil, Stroke = buttonStroke }
	button.Activated:Connect(function()
		local mapId = entry.MapId
		if mapId and voteCallback then
			myVote = mapId
			voteCallback(mapId)
			HUD.RefreshVoteHighlight()
		end
	end)
	voteButtons[index] = entry
end

-- Écran de résultats
local resultsFrame: Frame = New("Frame", {
	Name = "Results",
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.new(0.5, 0, 0.55, 0),
	Size = UDim2.new(0.5, 0, 0.46, 0),
	BackgroundColor3 = Theme.Panel,
	BackgroundTransparency = 0.08,
	Visible = false,
	ZIndex = 3,
}, screen)
Theme.Corner(resultsFrame, 20)
local resultsStroke = Theme.Stroke(resultsFrame, 4, Theme.Accent)
New("UISizeConstraint", { MaxSize = Vector2.new(620, 330), MinSize = Vector2.new(300, 170) }, resultsFrame)
local resultsTitle = Label(resultsFrame, {
	Font = Theme.FontBlack,
	Size = UDim2.fromScale(0.9, 0.26),
	Position = UDim2.fromScale(0.05, 0.04),
	Text = "",
	ZIndex = 3,
})
local resultsReason = Label(resultsFrame, {
	Size = UDim2.fromScale(0.9, 0.12),
	Position = UDim2.fromScale(0.05, 0.31),
	Text = "",
	TextColor3 = Color3.fromRGB(210, 220, 240),
	ZIndex = 3,
})
local resultsHunter = Label(resultsFrame, {
	Size = UDim2.fromScale(0.9, 0.13),
	Position = UDim2.fromScale(0.05, 0.46),
	Text = "",
	TextColor3 = Theme.Accent,
	ZIndex = 3,
})
local resultsCoins = Label(resultsFrame, {
	Size = UDim2.fromScale(0.9, 0.15),
	Position = UDim2.fromScale(0.05, 0.62),
	Text = "",
	TextColor3 = Theme.Coin,
	ZIndex = 3,
})
local resultsDetail = Label(resultsFrame, {
	Size = UDim2.fromScale(0.9, 0.12),
	Position = UDim2.fromScale(0.05, 0.8),
	Text = "",
	TextColor3 = Color3.fromRGB(200, 205, 225),
	ZIndex = 3,
})

-- ---------------------------------------------------------------------------
-- API
-- ---------------------------------------------------------------------------
function HUD.OnVote(callback: (string) -> ())
	voteCallback = callback
end

-- Met à jour le bandeau de rôle selon l'équipe du joueur local
function HUD.SetRole(teamId: string?)
	local def = Teams.Get(teamId)
	if def then
		banner.BackgroundColor3 = def.Color
		bannerText.TextColor3 = Theme.Dark
		bannerStroke.Color = def.DarkColor
		bannerText.Text = Teams.RoleBanner(def.Id)
	else
		banner.BackgroundColor3 = Theme.Dark
		bannerText.TextColor3 = Theme.White
		bannerStroke.Color = Theme.White
		bannerText.Text = Teams.Rule
	end
	for id, row in teamRows do
		row.Stroke.Thickness = (id == teamId) and 3 or 0
	end
end

function HUD.SetCoins(amount: number)
	coinsText.Text = tostring(math.floor(amount))
end

local announceToken = 0
function HUD.Announce(text: string, color: Color3?)
	announceToken += 1
	local token = announceToken
	announceLabel.Text = text
	announceLabel.TextColor3 = color or Theme.White
	announceLabel.TextTransparency = 0
	announceLabel.TextStrokeTransparency = 0
	announceLabel.Visible = true
	announceLabel.Size = UDim2.new(0.6, 0, 0.07, 0)
	TweenService:Create(announceLabel, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
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

local toastToken = 0
function HUD.Notify(text: string, color: Color3?)
	toastToken += 1
	local token = toastToken
	toast.Text = text
	toast.TextColor3 = color or Theme.White
	toast.Visible = true
	task.delay(2.5, function()
		if token == toastToken then
			toast.Visible = false
		end
	end)
end

-- Récompense de fin de manche (pièces gagnées)
function HUD.SetRoundReward(reward: { [string]: any }?)
	lastReward = reward
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
		if def and mapId then
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
	local myTeam = player:GetAttribute("Team")
	if winnerDef then
		resultsTitle.Text = winnerDef.Plural .. " WIN!"
		resultsTitle.TextColor3 = winnerDef.Color
		resultsStroke.Color = winnerDef.Color
	else
		resultsTitle.Text = "DRAW!"
		resultsTitle.TextColor3 = Theme.White
		resultsStroke.Color = Theme.Accent
	end
	local reason = REASONS[state.WinReason or ""] or ""
	if winnerDef and myTeam then
		reason = (myTeam == winnerDef.Id and "Your team won! " or "Your team lost. ") .. reason
	end
	resultsReason.Text = reason
	if state.BestHunter then
		resultsHunter.Text = string.format("Best hunter: %s (%d catch%s)", state.BestHunter, state.BestHunterCaptures or 0, (state.BestHunterCaptures or 0) == 1 and "" or "es")
	else
		resultsHunter.Text = "Best hunter: nobody caught anyone!"
	end
	local reward = lastReward
	if reward and type(reward.Total) == "number" then
		resultsCoins.Text = string.format("+%d coins", reward.Total)
		local parts = {}
		for _, item in reward.Lines or {} do
			table.insert(parts, string.format("%s +%d", item[1], item[2]))
		end
		resultsDetail.Text = table.concat(parts, "   ")
	else
		resultsCoins.Text = ""
		resultsDetail.Text = ""
	end
end

function HUD.UpdateState(state: Types.GameState)
	local phase = state.Phase
	phaseText.Text = PHASE_LABELS[phase] or phase
	timerText.Text = (phase == "Waiting") and "--:--" or Theme.FormatTime(state.TimeLeft)

	local mapDef = MapInfo.Get(state.MapId)
	local inRound = phase == "Countdown" or phase == "Round" or phase == "Results"
	if mapDef and inRound then
		local goal = state.ScoreGoal and string.format("  -  First to %d %s", state.ScoreGoal, state.ScoreLabel or "points") or ""
		subText.Text = mapDef.DisplayName .. "  -  " .. mapDef.ModeName .. goal
	else
		subText.Text = ""
	end

	for teamId, row in teamRows do
		row.Count.Text = "x" .. tostring(state.TeamCounts[teamId] or 0)
		local score = state.Scores[teamId]
		row.Score.Text = (inRound and state.ScoreLabel ~= nil) and tostring(score or 0) or ""
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
	elseif phase == "Intermission" or phase == "Waiting" then
		lastReward = nil
	end
end

return HUD

--[[
	HUD.lua
	Interface principale, construite par le code, selon le kit du jeu
	(reference/BIBLE_VISUELLE.md, §9). Disposition propre au jeu :
	  - haut centre : capsule chrono (phase + temps), ruban de rôle aux couleurs
	    de l'équipe ("FOX · catch CHICKENS · avoid SNAKES"), ligne d'objectif ;
	  - sous le ruban : pastille d'état (à terre + chrono, porté, en train de
	    porter, consigne de secours, protégé dans la zone sûre), puis annonces
	    courtes (petite pastille) : le centre de l'écran reste libre ;
	  - haut droite : menus (SHOP / SPIN / HELP), tableau des trois équipes en
	    manche (les menus passent à sa gauche), fil des captures dessous ;
	  - bas gauche : pièces et niveau ; bas centre : dock des médaillons d'action
	    (ActionBar) ou panneau de vote pendant l'intermission ;
	  - fin de manche : bandeau du vainqueur, colonnes des trois équipes, trois
	    cartes de distinction et puce de niveau.
]]

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Teams = require(Shared.Teams)
local MapInfo = require(Shared.MapInfo)
local ModeInfo = require(Shared.ModeInfo)
local Types = require(Shared.Types)
local Theme = require(script.Parent.Theme)

local HUD = {}

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local New, Label, Title = Theme.New, Theme.Label, Theme.Title

local PHASE_LABELS = {
	Waiting = "LOBBY",
	Intermission = "LOBBY",
	Countdown = "READY",
	Round = "ROUND",
	Results = "END",
}
local REASONS = {
	Objective = "Objective completed",
	LastStanding = "Last team standing",
	TimeUp = "Time's up",
	Draw = "No winner this time",
}
-- Cartes de distinction de fin de manche (clé du podium serveur -> titre)
local AWARDS = {
	{ Key = "MVP", Title = "ROUND STAR" },
	{ Key = "Survival", Title = "LONGEST RUN" },
	{ Key = "Catches", Title = "TOP CATCHER" },
}
local PLAYING = { Countdown = true, Round = true }

local voteCallback: ((string) -> ())? = nil
local compact = false -- petit écran (téléphone)
local touchMode = false -- commandes tactiles affichées (voir ActionBar)
local myVote: string? = nil
local lastCandidatesKey = ""
local lastReward: { [string]: any }? = nil
local lastState: Types.GameState? = nil
local profile: { [string]: any } = {}

-- Panneau du kit : encre vert-de-gris, bord crème
local function panel(parent: Instance?, props: { [string]: any }, stroke: number?): Frame
	local frame: Frame = New("Frame", props, parent)
	if props.BackgroundColor3 == nil then
		frame.BackgroundColor3 = Theme.Panel
	end
	if props.BackgroundTransparency == nil then
		frame.BackgroundTransparency = 0.1
	end
	Theme.Stroke(frame, stroke or 2, Theme.Cream, 0.1)
	return frame
end

-- ---------------------------------------------------------------------------
-- Écran
-- ---------------------------------------------------------------------------
local screen: ScreenGui = New("ScreenGui", {
	Name = "HuntOrHideHUD",
	ResetOnSpawn = false,
	IgnoreGuiInset = true,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	DisplayOrder = 10,
}, playerGui)
HUD.Screen = screen

-- ---------------------------------------------------------------------------
-- Menus en haut à droite (à gauche du tableau des équipes pendant la manche)
-- ---------------------------------------------------------------------------
local pillRow: Frame = New("Frame", {
	Name = "Pills",
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, -12, 0, 14),
	Size = UDim2.new(0, 328, 0, 40),
	BackgroundTransparency = 1,
}, screen)
New("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Right, Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }, pillRow)
HUD.Pills = {}
for index, name in { "SHOP", "SPIN", "HELP" } do
	local pill = Theme.Pill(pillRow, name, { Name = name, Size = UDim2.new(0, 104, 1, 0), LayoutOrder = index })
	HUD.Pills[name] = pill
end
local spinBadge = Theme.Badge(HUD.Pills.SPIN)

-- ---------------------------------------------------------------------------
-- Haut centre : capsule chrono, ruban de rôle, ligne d'objectif
-- ---------------------------------------------------------------------------
local topCenter: Frame = New("Frame", {
	Name = "TopCenter",
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 10),
	Size = UDim2.new(0.56, 0, 0, 112),
	BackgroundTransparency = 1,
}, screen)
local clock: Frame = panel(topCenter, {
	Name = "Clock",
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 0),
	Size = UDim2.new(0, 176, 0, 46),
}, 3)
Theme.CornerScale(clock, 0.5)
local phaseLabel = Title(clock, { Name = "Phase", Position = UDim2.new(0.06, 0, 0.22, 0), Size = UDim2.new(0.36, 0, 0.56, 0), Text = "LOBBY", TextColor3 = Theme.Mint })
local timerLabel = Title(clock, { Name = "Timer", Position = UDim2.new(0.42, 0, 0.1, 0), Size = UDim2.new(0.52, 0, 0.8, 0), Text = "", TextColor3 = Theme.White })
local mainLabel = Title(topCenter, {
	Name = "Main",
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 52),
	Size = UDim2.new(1, 0, 0, 34),
	Text = Teams.Rule,
	RichText = true,
	BackgroundColor3 = Theme.Panel,
	BackgroundTransparency = 0.1,
})
Theme.CornerScale(mainLabel, 0.5)
local ribbonStroke = Theme.Stroke(mainLabel, 3, Theme.Mint)
New("UIPadding", { PaddingTop = UDim.new(0, 5), PaddingBottom = UDim.new(0, 5), PaddingLeft = UDim.new(0, 16), PaddingRight = UDim.new(0, 16) }, mainLabel)
Theme.MaxText(mainLabel, 22)
local subLabel = Title(topCenter, { Name = "Sub", Position = UDim2.new(0, 0, 0, 90), Size = UDim2.new(1, 0, 0, 20), Text = "", TextColor3 = Theme.Cream })

-- ---------------------------------------------------------------------------
-- Haut droite : tableau des équipes
-- ---------------------------------------------------------------------------
local teamPanel: Frame = panel(screen, {
	Name = "Teams",
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, -12, 0, 14),
	Size = UDim2.new(0, 230, 0, 112),
	Visible = false,
}, 2)
Theme.Corner(teamPanel, 14)
New("UIListLayout", { Padding = UDim.new(0, 4), HorizontalAlignment = Enum.HorizontalAlignment.Center, VerticalAlignment = Enum.VerticalAlignment.Center, SortOrder = Enum.SortOrder.LayoutOrder }, teamPanel)
local teamRows: { [string]: { Row: Frame, Count: TextLabel, Score: TextLabel, Stroke: UIStroke } } = {}
for index, teamId in Teams.Order do
	local def = Teams.Get(teamId)
	assert(def)
	local row: Frame = New("Frame", { Name = teamId, Size = UDim2.new(0.92, 0, 0, 30), BackgroundColor3 = Theme.PanelLight, LayoutOrder = index }, teamPanel)
	Theme.CornerScale(row, 0.5)
	local stroke = Theme.Stroke(row, 0, Theme.Cream)
	local chip: Frame = New("Frame", { Name = "Chip", Size = UDim2.fromScale(0.5, 1), BackgroundColor3 = def.Color }, row)
	Theme.CornerScale(chip, 0.5)
	Label(chip, { Size = UDim2.fromScale(0.84, 0.66), Position = UDim2.fromScale(0.08, 0.17), Text = def.Display, TextColor3 = Theme.TextOn(def.Color), FontFace = Theme.FaceHeavy })
	local count = Title(row, { Size = UDim2.fromScale(0.2, 0.66), Position = UDim2.fromScale(0.54, 0.17), Text = "x0" })
	local score = Title(row, { Size = UDim2.fromScale(0.22, 0.66), Position = UDim2.fromScale(0.76, 0.17), Text = "", TextColor3 = Theme.Mint })
	teamRows[teamId] = { Row = row, Count = count, Score = score, Stroke = stroke }
end

-- ---------------------------------------------------------------------------
-- Bas gauche : pièces et niveau
-- ---------------------------------------------------------------------------
local function currencyPanel(name: string, order: number, iconColor: Color3): (Frame, TextLabel, TextLabel, Frame)
	local frame: Frame = panel(nil, {
		Name = name,
		Size = UDim2.new(0, 230, 0, 52),
		LayoutOrder = order,
	}, 2)
	Theme.CornerScale(frame, 0.5)
	local icon: Frame = New("Frame", { AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 10, 0.5, 0), Size = UDim2.new(0, 30, 0, 30), BackgroundColor3 = iconColor }, frame)
	Theme.CornerScale(icon, 0.5)
	Theme.Stroke(icon, 2, Theme.Cream)
	local value = Title(frame, { Name = "Value", Position = UDim2.new(0, 48, 0, 4), Size = UDim2.new(1, -60, 0, 28), Text = "0", TextXAlignment = Enum.TextXAlignment.Left })
	local caption = Label(frame, { Name = "Caption", Position = UDim2.new(0, 48, 0, 31), Size = UDim2.new(1, -60, 0, 14), Text = "", TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = Theme.Muted })
	return frame, value, caption, icon
end
local bottomLeft: Frame = New("Frame", {
	Name = "Currency",
	AnchorPoint = Vector2.new(0, 1),
	Position = UDim2.new(0, 12, 1, -12),
	Size = UDim2.new(0, 230, 0, 112),
	BackgroundTransparency = 1,
}, screen)
New("UIListLayout", { Padding = UDim.new(0, 8), VerticalAlignment = Enum.VerticalAlignment.Bottom, SortOrder = Enum.SortOrder.LayoutOrder }, bottomLeft)
local coinsPanel, coinsValue, coinsCaption = currencyPanel("Coins", 1, Theme.Coin)
coinsPanel.Parent = bottomLeft
coinsCaption.Text = "COINS"
local levelPanel, levelValue, levelCaption = currencyPanel("Level", 2, Theme.Mint)
levelPanel.Parent = bottomLeft
local levelBar: Frame = New("Frame", { Position = UDim2.new(0, 48, 1, -9), Size = UDim2.new(1, -66, 0, 4), BackgroundColor3 = Theme.PanelLight, BorderSizePixel = 0 }, levelPanel)
local levelFill: Frame = New("Frame", { Size = UDim2.fromScale(0, 1), BackgroundColor3 = Theme.Mint, BorderSizePixel = 0 }, levelBar)
levelCaption.Position = UDim2.new(0, 48, 0, 29)

-- ---------------------------------------------------------------------------
-- Bas centre : dock des médaillons d'action (ActionBar) + vote
-- ---------------------------------------------------------------------------
local bottomCenter: Frame = New("Frame", {
	Name = "BottomCenter",
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 1, -14),
	Size = UDim2.new(0, 360, 0, 104),
	BackgroundTransparency = 1,
}, screen)
New("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 14), HorizontalAlignment = Enum.HorizontalAlignment.Center, VerticalAlignment = Enum.VerticalAlignment.Bottom, SortOrder = Enum.SortOrder.LayoutOrder }, bottomCenter)
HUD.BottomRow = bottomCenter

-- Panneau de vote (intermission) : trois cartes « mode + carte » avec la règle
-- en trois lignes, le nombre de voix et le nom de ceux qui ont choisi chaque
-- carte ; dessous, la liste de tous les joueurs présents (votants ou non)
local votePanel: Frame = New("Frame", {
	Name = "VotePanel",
	AnchorPoint = Vector2.new(0, 1),
	Position = UDim2.new(0, 310, 1, -66),
	Size = UDim2.new(0, 700, 0, 214),
	BackgroundTransparency = 1,
	Visible = false,
}, screen)
local voteTitle = Title(votePanel, { Name = "VoteTitle", Size = UDim2.new(1, 0, 0, 24), Text = "VOTE FOR THE NEXT MODE" })
local voteButtonsFrame: Frame = New("Frame", { Name = "Cards", Position = UDim2.new(0, 0, 0, 28), Size = UDim2.new(1, 0, 1, -56), BackgroundTransparency = 1 }, votePanel)
New("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 10), HorizontalAlignment = Enum.HorizontalAlignment.Center, SortOrder = Enum.SortOrder.LayoutOrder }, voteButtonsFrame)
-- Tous les joueurs : ceux qui ont voté (et pour quoi), ceux qu'on attend
local rosterLabel = Label(votePanel, { Name = "Roster", AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 0, 1, 0), Size = UDim2.new(1, 0, 0, 22), Text = "", RichText = true, TextColor3 = Theme.Cream, BackgroundTransparency = 0.15, BackgroundColor3 = Theme.Panel })
Theme.Corner(rosterLabel, 10)
Theme.MaxText(rosterLabel, 15)

type VoteButton = { Button: TextButton, Name: TextLabel, Map: TextLabel, Rules: TextLabel, Votes: TextLabel, Stripe: Frame, MapId: string?, Stroke: UIStroke }
local voteButtons: { VoteButton } = {}

function HUD.RefreshVoteHighlight()
	for _, entry in voteButtons do
		local selected = entry.MapId ~= nil and entry.MapId == myVote
		entry.Stroke.Color = selected and Theme.Mint or Theme.Cream
		entry.Stroke.Thickness = selected and 4 or 2
	end
end

for index = 1, 3 do
	local button: TextButton = New("TextButton", {
		Name = "Vote" .. index,
		Size = UDim2.new(0.31, 0, 1, 0),
		BackgroundColor3 = Theme.Panel,
		BackgroundTransparency = 0.06,
		Text = "",
		AutoButtonColor = true,
		LayoutOrder = index,
	}, voteButtonsFrame)
	Theme.Corner(button, 16)
	local stroke = Theme.Stroke(button, 2, Theme.Cream)
	local stripe: Frame = New("Frame", { Size = UDim2.new(1, 0, 0, 8), BackgroundColor3 = Theme.Mint, BorderSizePixel = 0 }, button)
	Theme.Corner(stripe, 6)
	local nameLabel = Title(button, { Name = "ModeName", Size = UDim2.new(0.92, 0, 0.2, 0), Position = UDim2.fromScale(0.04, 0.08), Text = "?" })
	local mapLabel = Label(button, { Name = "MapName", Size = UDim2.new(0.92, 0, 0.11, 0), Position = UDim2.fromScale(0.04, 0.28), Text = "", TextColor3 = Theme.Mint, FontFace = Theme.FaceHeavy })
	local rulesLabel = Label(button, { Name = "Rules", Size = UDim2.new(0.92, 0, 0.36, 0), Position = UDim2.fromScale(0.04, 0.41), Text = "", TextColor3 = Theme.Cream, TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top, TextXAlignment = Enum.TextXAlignment.Left })
	Theme.MaxText(rulesLabel, 14)
	local votesLabel = Label(button, { Name = "Votes", Size = UDim2.new(0.92, 0, 0.17, 0), Position = UDim2.fromScale(0.04, 0.8), Text = "", RichText = true, TextColor3 = Theme.Muted, TextXAlignment = Enum.TextXAlignment.Left })
	Theme.MaxText(votesLabel, 14)
	local entry: VoteButton = { Button = button, Name = nameLabel, Map = mapLabel, Rules = rulesLabel, Votes = votesLabel, Stripe = stripe, MapId = nil, Stroke = stroke }
	button.Activated:Connect(function()
		local option = entry.MapId
		if option and voteCallback then
			myVote = option
			voteCallback(option)
			HUD.RefreshVoteHighlight()
		end
	end)
	voteButtons[index] = entry
end

-- ---------------------------------------------------------------------------
-- Pastille d'état (RescueController) : une ligne sous le bloc du haut, bord à la
-- couleur de l'état, petite jauge pour le chrono à terre
-- ---------------------------------------------------------------------------
local statusPill: Frame = New("Frame", {
	Name = "Status",
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 128),
	Size = UDim2.new(0, 460, 0, 34),
	BackgroundColor3 = Theme.Panel,
	BackgroundTransparency = 0.12,
	Visible = false,
	ZIndex = 6,
}, screen)
Theme.CornerScale(statusPill, 0.5)
local statusStroke = Theme.Stroke(statusPill, 3, Theme.Mint)
local statusLabel = Title(statusPill, {
	Name = "Text",
	Position = UDim2.new(0, 14, 0, 4),
	Size = UDim2.new(1, -28, 1, -10),
	Text = "",
	ZIndex = 6,
})
Theme.MaxText(statusLabel, 20)
local statusBar: Frame = New("Frame", {
	Name = "Timer",
	AnchorPoint = Vector2.new(0, 1),
	Position = UDim2.new(0, 18, 1, -3),
	Size = UDim2.new(1, -36, 0, 3),
	BackgroundColor3 = Theme.Dark,
	BorderSizePixel = 0,
	Visible = false,
	ZIndex = 6,
}, statusPill)
local statusFill: Frame = New("Frame", { Name = "Fill", Size = UDim2.fromScale(1, 1), BackgroundColor3 = Theme.Bad, BorderSizePixel = 0, ZIndex = 7 }, statusBar)
local statusText: string? = nil

-- ---------------------------------------------------------------------------
-- Annonces, notifications, spectateur, aide
-- ---------------------------------------------------------------------------
-- Annonce de la map (oeuf volé, points...) : petite pastille sous le ruban de
-- rôle, jamais au milieu de l'écran, où se joue la poursuite
local announcePill: Frame = New("Frame", {
	Name = "Announce",
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 128),
	Size = UDim2.new(0, 440, 0, 30),
	BackgroundColor3 = Theme.Panel,
	BackgroundTransparency = 0.3,
	Visible = false,
	ZIndex = 5,
}, screen)
Theme.CornerScale(announcePill, 0.5)
local announceLabel = Title(announcePill, {
	Name = "Text",
	Position = UDim2.new(0, 14, 0, 4),
	Size = UDim2.new(1, -28, 1, -8),
	Text = "",
	ZIndex = 5,
})
Theme.MaxText(announceLabel, 22)

local toast: TextLabel = Label(screen, {
	Name = "Toast",
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 1, -170),
	Size = UDim2.new(0, 420, 0, 34),
	BackgroundColor3 = Theme.Panel,
	BackgroundTransparency = 0.1,
	Text = "",
	Visible = false,
	ZIndex = 30,
})
Theme.CornerScale(toast, 0.5)
Theme.Stroke(toast, 2, Theme.Cream, 0.1)
New("UIPadding", { PaddingTop = UDim.new(0, 6), PaddingBottom = UDim.new(0, 6) }, toast)

local spectatorLabel = Title(screen, {
	Name = "Spectator",
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 1, -170),
	Size = UDim2.new(0.6, 0, 0, 26),
	Text = "A round is in progress. You'll join the next one!",
	Visible = false,
})

-- Composition des équipes, pendant le décompte (on est figé dans son camp) :
-- tous les joueurs de la manche, bots compris, colonne par équipe
local lineup: Frame = New("Frame", {
	Name = "Lineup",
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0.36, 0),
	Size = UDim2.new(0, 600, 0, 150),
	BackgroundTransparency = 1,
	Visible = false,
}, screen)
New("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 10), HorizontalAlignment = Enum.HorizontalAlignment.Center, SortOrder = Enum.SortOrder.LayoutOrder }, lineup)
type LineupColumn = { Frame: Frame, Title: TextLabel, Names: TextLabel, Stroke: UIStroke }
local lineupColumns: { [string]: LineupColumn } = {}
for index, teamId in Teams.Order do
	local def = Teams.Get(teamId) :: Teams.TeamDef
	local column: Frame = panel(lineup, { Name = teamId, Size = UDim2.new(0.31, 0, 1, 0), LayoutOrder = index, BackgroundTransparency = 0.12 })
	Theme.Corner(column, 14)
	local stroke = Theme.Stroke(column, 2, def.Color)
	local title = Title(column, { Name = "TeamName", Size = UDim2.new(0.92, 0, 0, 24), Position = UDim2.new(0.04, 0, 0, 6), Text = def.Plural, TextColor3 = def.Color })
	local names = Label(column, { Name = "Names", Size = UDim2.new(0.92, 0, 1, -38), Position = UDim2.new(0.04, 0, 0, 32), Text = "", RichText = true, TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top, TextColor3 = Theme.Cream })
	Theme.MaxText(names, 15)
	lineupColumns[teamId] = { Frame = column, Title = title, Names = names, Stroke = stroke }
end

local function updateLineup()
	local members: { [string]: { string } } = {}
	for _, teamId in Teams.Order do
		members[teamId] = {}
	end
	local myCharacter = player.Character
	for _, model in CollectionService:GetTagged("HoH_Actor") do
		local team = model:GetAttribute("Team")
		if type(team) == "string" and members[team] then
			local name = model:GetAttribute("DisplayName")
			name = type(name) == "string" and name or model.Name
			if model == myCharacter then
				name = "<b>" .. name .. " (you)</b>"
			end
			table.insert(members[team], name)
		end
	end
	for teamId, column in lineupColumns do
		local list = members[teamId]
		table.sort(list)
		local shown = {}
		local limit = compact and 4 or 7
		for i = 1, math.min(#list, limit) do
			shown[i] = list[i]
		end
		local text = table.concat(shown, "\n")
		if #list > limit then
			text ..= string.format("\n+%d more", #list - limit)
		end
		column.Names.Text = text
		column.Title.Text = string.format("%s · %d", (Teams.Get(teamId) :: Teams.TeamDef).Plural, #list)
	end
end

local helpPanel: Frame = panel(screen, {
	Name = "Help",
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.new(0, 520, 0, 300),
	BackgroundTransparency = 0.04,
	Visible = false,
	ZIndex = 40,
}, 4)
Theme.Corner(helpPanel, 22)
Title(helpPanel, { Size = UDim2.new(1, 0, 0, 40), Position = UDim2.new(0, 0, 0, 14), Text = "HOW TO PLAY", TextColor3 = Theme.Mint, ZIndex = 40 })
-- Règles : la partie "commandes" suit l'appareil (clavier ou tactile)
local HELP_RULES = "Catch your prey. Run from your hunter.\nFOX catches CHICKEN, CHICKEN catches SNAKE, SNAKE catches FOX.\nOutlines show teams: FOX orange, CHICKEN yellow, SNAKE green.\nCaught? You're down. A teammate can carry you to your base to revive you.\nNo rescue in " .. Config.Rescue.BleedOutSeconds .. "s? You join the team that caught you.\nNobody can catch you in your base's SAFE ZONE.\n\n"
local HELP_KEYS = "Q / E : dash sideways    F : stop dead    R : your animal's ability\nC : carry a downed teammate home    Hide in tall grass and bushes!"
local HELP_TOUCH = "DASH buttons : dodge sideways    STOP : stop dead    Big button : ability\nCARRY : pick up a downed teammate    Hide in tall grass!"
local helpText = Label(helpPanel, {
	Name = "Rules",
	Size = UDim2.new(1, -44, 1, -76),
	Position = UDim2.new(0, 22, 0, 60),
	TextScaled = true,
	TextWrapped = true,
	TextYAlignment = Enum.TextYAlignment.Top,
	TextXAlignment = Enum.TextXAlignment.Left,
	ZIndex = 40,
	Text = HELP_RULES .. HELP_KEYS,
})
New("UIScale", { Name = "Scale" }, helpPanel)
local helpClose: TextButton = New("TextButton", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -12, 0, 12), Size = UDim2.new(0, 38, 0, 38), BackgroundColor3 = Theme.Bad, Text = "X", FontFace = Theme.FaceHeavy, TextScaled = true, TextColor3 = Theme.White, ZIndex = 41 }, helpPanel)
Theme.CornerScale(helpClose, 0.5)
Theme.Stroke(helpClose, 2, Theme.Cream)
helpClose.Activated:Connect(function()
	helpPanel.Visible = false
end)
HUD.Pills.HELP.Activated:Connect(function()
	helpPanel.Visible = not helpPanel.Visible
end)

-- ---------------------------------------------------------------------------
-- Fin de manche : bandeau du vainqueur, équipes, distinctions, niveau
-- ---------------------------------------------------------------------------
local results: Frame = panel(screen, {
	Name = "Results",
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.52),
	Size = UDim2.new(0, 760, 0, 520),
	BackgroundTransparency = 0.04,
	Visible = false,
	ZIndex = 20,
}, 4)
Theme.Corner(results, 26)
New("UISizeConstraint", { MaxSize = Vector2.new(760, 520), MinSize = Vector2.new(360, 250) }, results)
New("UIScale", { Name = "Scale", Scale = 1 }, results)
local banner: Frame = New("Frame", { Name = "Banner", Position = UDim2.new(0, 16, 0, 16), Size = UDim2.new(1, -32, 0, 82), BackgroundColor3 = Theme.PanelLight, ZIndex = 20 }, results)
Theme.Corner(banner, 18)
local resultsTitle = Title(banner, { Name = "Title", Size = UDim2.new(1, -120, 0, 46), Position = UDim2.new(0, 60, 0, 6), Text = "", ZIndex = 21 })
local resultsReason = Title(banner, { Name = "Reason", Size = UDim2.new(1, -60, 0, 22), Position = UDim2.new(0, 30, 0, 54), Text = "", TextColor3 = Theme.Cream, ZIndex = 21 })
local resultsClose: TextButton = New("TextButton", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -24, 0, 24), Size = UDim2.new(0, 44, 0, 44), BackgroundColor3 = Theme.Bad, Text = "X", TextColor3 = Theme.White, FontFace = Theme.FaceTitle, TextScaled = true, ZIndex = 22 }, results)
Theme.CornerScale(resultsClose, 0.5)
Theme.Stroke(resultsClose, 2, Theme.Cream)
local resultsHidden = false
resultsClose.Activated:Connect(function()
	resultsHidden = true
	results.Visible = false
end)
-- Colonnes des équipes (effectif final et score du mode)
local teamStrip: Frame = New("Frame", { Name = "TeamStrip", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 110), Size = UDim2.new(0, 660, 0, 56), BackgroundTransparency = 1, ZIndex = 20 }, results)
New("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 12), HorizontalAlignment = Enum.HorizontalAlignment.Center, SortOrder = Enum.SortOrder.LayoutOrder }, teamStrip)
local teamChips: { [string]: { Frame: Frame, Text: TextLabel, Stroke: UIStroke } } = {}
for index, teamId in Teams.Order do
	local def = Teams.Get(teamId)
	assert(def)
	local chip: Frame = New("Frame", { Name = teamId, Size = UDim2.new(0, 204, 1, 0), BackgroundColor3 = def.Color, LayoutOrder = index, ZIndex = 21 }, teamStrip)
	Theme.CornerScale(chip, 0.5)
	local stroke = Theme.Stroke(chip, 0, Theme.Cream)
	local text = Label(chip, { Size = UDim2.new(0.86, 0, 0.62, 0), Position = UDim2.fromScale(0.07, 0.19), Text = def.Plural, TextColor3 = Theme.TextOn(def.Color), FontFace = Theme.FaceHeavy, ZIndex = 22 })
	teamChips[teamId] = { Frame = chip, Text = text, Stroke = stroke }
end
-- Trois cartes de distinction côte à côte (pas de podium)
local awardsRow: Frame = New("Frame", { Name = "Awards", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 180), Size = UDim2.new(0, 700, 0, 196), BackgroundTransparency = 1, ZIndex = 20 }, results)
New("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 14), HorizontalAlignment = Enum.HorizontalAlignment.Center, SortOrder = Enum.SortOrder.LayoutOrder }, awardsRow)
type AwardCard = { Frame: Frame, Portrait: Frame, Initial: TextLabel, Name: TextLabel, Value: TextLabel }
local awardCards: { [string]: AwardCard } = {}
for index, award in AWARDS do
	local card: Frame = New("Frame", { Name = award.Key, Size = UDim2.new(0, 222, 1, 0), BackgroundColor3 = Theme.PanelLight, LayoutOrder = index, ZIndex = 21 }, awardsRow)
	Theme.Corner(card, 18)
	Theme.Stroke(card, 2, Theme.Cream, 0.2)
	Title(card, { Size = UDim2.new(0.9, 0, 0, 24), Position = UDim2.new(0.05, 0, 0, 10), Text = award.Title, TextColor3 = Theme.Mint, ZIndex = 22 })
	local portrait: Frame = New("Frame", { Name = "Portrait", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 42), Size = UDim2.new(0, 84, 0, 84), BackgroundColor3 = Theme.Panel, ZIndex = 22 }, card)
	Theme.CornerScale(portrait, 0.5)
	Theme.Stroke(portrait, 3, Theme.Cream)
	local initial = Title(portrait, { Size = UDim2.fromScale(0.6, 0.6), Position = UDim2.fromScale(0.2, 0.2), Text = "?", ZIndex = 23 })
	local nameLabel = Title(card, { Size = UDim2.new(0.9, 0, 0, 24), Position = UDim2.new(0.05, 0, 0, 132), Text = "-", ZIndex = 22 })
	local valueLabel = Title(card, { Size = UDim2.new(0.9, 0, 0, 26), Position = UDim2.new(0.05, 0, 0, 160), Text = "", TextColor3 = Theme.Cream, ZIndex = 22 })
	awardCards[award.Key] = { Frame = card, Portrait = portrait, Initial = initial, Name = nameLabel, Value = valueLabel }
end
local readyLabel = Title(results, { Size = UDim2.new(1, -60, 0, 26), Position = UDim2.new(0, 30, 0, 388), Text = "Next round soon", TextColor3 = Theme.Cream, ZIndex = 20 })
local coinsLine = Title(results, { Size = UDim2.new(1, -60, 0, 20), Position = UDim2.new(0, 30, 0, 420), Text = "", TextColor3 = Theme.Coin, ZIndex = 20 })
-- Puce de niveau : pastille "LV n", jauge menthe, XP dans la jauge
local xpRow: Frame = New("Frame", { Name = "LevelChip", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -22), Size = UDim2.new(0, 440, 0, 40), BackgroundTransparency = 1, ZIndex = 20 }, results)
local xpBadge: Frame = New("Frame", { Size = UDim2.new(0, 72, 1, 0), BackgroundColor3 = Theme.Mint, ZIndex = 21 }, xpRow)
Theme.CornerScale(xpBadge, 0.5)
local xpLevelLeft = Label(xpBadge, { Size = UDim2.fromScale(0.8, 0.6), Position = UDim2.fromScale(0.1, 0.2), Text = "LV 1", TextColor3 = Theme.Dark, FontFace = Theme.FaceHeavy, ZIndex = 22 })
local xpBar: Frame = New("Frame", { Position = UDim2.new(0, 84, 0.18, 0), Size = UDim2.new(1, -84, 0.64, 0), BackgroundColor3 = Theme.Dark, ZIndex = 21 }, xpRow)
Theme.CornerScale(xpBar, 0.5)
Theme.Stroke(xpBar, 2, Theme.Cream, 0.2)
local xpFill: Frame = New("Frame", { Size = UDim2.fromScale(0, 1), BackgroundColor3 = Theme.Mint, ZIndex = 22 }, xpBar)
Theme.CornerScale(xpFill, 0.5)
local xpText = Title(xpBar, { Size = UDim2.fromScale(1, 0.84), Position = UDim2.fromScale(0, 0.08), Text = "", ZIndex = 23 })

local function renderAwards()
	local state = lastState
	for _, award in AWARDS do
		local card = awardCards[award.Key]
		local list = state and state.Podium and state.Podium[award.Key] or {}
		local entry = list[1]
		for _, child in card.Portrait:GetChildren() do
			if child:IsA("ImageLabel") then
				child:Destroy()
			end
		end
		if entry then
			card.Name.Text = entry.Name
			card.Value.Text = entry.Value
			card.Initial.Text = string.upper(string.sub(entry.Name, 1, 1))
			card.Initial.Visible = true
			if entry.UserId and entry.UserId > 0 then
				card.Initial.Visible = false
				local image = New("ImageLabel", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Image = string.format("rbxthumb://type=AvatarHeadShot&id=%d&w=150&h=150", entry.UserId), ZIndex = 23 }, card.Portrait)
				Theme.CornerScale(image, 0.5)
			end
		else
			card.Name.Text = "-"
			card.Value.Text = ""
			card.Initial.Text = "?"
			card.Initial.Visible = true
		end
	end
end

-- ---------------------------------------------------------------------------
-- API
-- ---------------------------------------------------------------------------
function HUD.OnVote(callback: (string) -> ())
	voteCallback = callback
end

local currentRole: string? = nil
function HUD.SetRole(teamId: string?)
	currentRole = Teams.Get(teamId) and teamId or nil
	for id, row in teamRows do
		row.Stroke.Thickness = (id == currentRole) and 3 or 0
	end
	if lastState then
		HUD.UpdateState(lastState)
	end
end

-- Ruban de rôle : chaque équipe à sa couleur, la même que son contour dans le
-- monde (on sait d'un coup d'œil quelle couleur attraper et laquelle fuir)
local function roleText(teamId: string): string
	local def = Teams.Get(teamId)
	if not def then
		return Teams.Rule
	end
	local prey = Teams.Defs[def.Prey]
	local predator = Teams.Defs[def.Predator]
	local function tint(color: Color3): string
		return Theme.Hex(color:Lerp(Color3.new(1, 1, 1), 0.2))
	end
	return string.format('<font color="%s">%s</font>  ·  catch <font color="%s">%s</font>  ·  avoid <font color="%s">%s</font>', tint(def.Color), def.Display, tint(prey.Color), prey.Plural, tint(predator.Color), predator.Plural)
end

-- Pastille d'état (RescueController) : text nil = masquée ; progress = jauge 0..1
local rescale: () -> ()
function HUD.SetStatus(text: string?, color: Color3?, progress: number?)
	local playing = lastState ~= nil and PLAYING[lastState.Phase] == true
	local shown = text ~= nil and text ~= "" and playing
	statusText = text
	statusLabel.Text = text or ""
	statusStroke.Color = color or Theme.Mint
	statusBar.Visible = progress ~= nil
	statusFill.Size = UDim2.fromScale(math.clamp(progress or 0, 0, 1), 1)
	if statusPill.Visible ~= shown then
		statusPill.Visible = shown
		rescale()
	end
end

function HUD.SetCoins(amount: number)
	coinsValue.Text = Theme.FormatNumber(amount)
end

-- Profil (niveau, VIP, roue)
local helpShownOnce = false
function HUD.SetProfile(data: { [string]: any })
	profile = data
	-- Nouveau joueur : les règles s'affichent une fois, au lobby seulement
	local inLobby = lastState == nil or lastState.Phase == "Waiting" or lastState.Phase == "Intermission"
	if not helpShownOnce and inLobby and type(data.Stats) == "table" and (data.Stats.RoundsPlayed or 0) == 0 then
		helpPanel.Visible = true
	end
	helpShownOnce = true
	HUD.SetCoins(data.Coins or 0)
	coinsCaption.Text = player:GetAttribute("VIP") and "COINS  [2X]" or "COINS"
	local level = data.Level or 1
	levelValue.Text = "LEVEL " .. level
	local needed = data.XPNeeded or 100
	levelCaption.Text = string.format("%d / %d XP", data.XP or 0, needed)
	levelFill.Size = UDim2.fromScale(math.clamp((data.XP or 0) / needed, 0, 1), 1)
	local available = type(data.NextSpinAt) == "number" and type(data.ServerTime) == "number" and data.ServerTime >= data.NextSpinAt
	spinBadge.Visible = available == true
end

local announceToken = 0
function HUD.Announce(text: string, color: Color3?)
	announceToken += 1
	local token = announceToken
	announceLabel.Text = text
	announceLabel.TextColor3 = color or Theme.White
	announceLabel.TextTransparency = 0
	announceLabel.TextStrokeTransparency = 0
	announcePill.BackgroundTransparency = 0.3
	announcePill.Visible = true
	-- Petit rebond d'apparition, sans grossir au-delà de la pastille
	local scale = announcePill:FindFirstChildOfClass("UIScale") or New("UIScale", {}, announcePill)
	scale.Scale = 0.85
	TweenService:Create(scale, TweenInfo.new(0.2, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	task.delay(1.8, function()
		if token ~= announceToken then
			return
		end
		local fade = TweenInfo.new(0.35)
		TweenService:Create(announcePill, fade, { BackgroundTransparency = 1 }):Play()
		local tween = TweenService:Create(announceLabel, fade, { TextTransparency = 1, TextStrokeTransparency = 1 })
		tween:Play()
		tween.Completed:Connect(function()
			if token == announceToken then
				announcePill.Visible = false
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

function HUD.SetRoundReward(reward: { [string]: any }?)
	lastReward = reward
end

-- Liste de noms courte : "Ana, Bo, Cy +2"
local function nameList(names: { string }, limit: number): string
	local shown = {}
	for i = 1, math.min(#names, limit) do
		shown[i] = names[i]
	end
	local text = table.concat(shown, ", ")
	if #names > limit then
		text ..= string.format(" +%d", #names - limit)
	end
	return text
end

local function updateVotePanel(state: Types.GameState)
	local key = table.concat(state.Candidates, "|")
	if key ~= lastCandidatesKey then
		lastCandidatesKey = key
		myVote = nil
	end
	-- Qui a voté pour quoi (liste envoyée par le serveur)
	local voters: { [string]: { string } } = {}
	local waiting: { string } = {}
	local roster = state.Roster or {}
	for _, entry in roster do
		if entry.Vote then
			voters[entry.Vote] = voters[entry.Vote] or {}
			table.insert(voters[entry.Vote], entry.Name)
		else
			table.insert(waiting, entry.Name)
		end
		if entry.UserId == player.UserId and entry.Vote then
			myVote = entry.Vote
		end
	end
	for index, entry in voteButtons do
		local option = state.Candidates[index]
		local mapId, modeId = ModeInfo.Split(option)
		local mapDef, modeDef = MapInfo.Get(mapId), ModeInfo.Get(modeId)
		entry.MapId = option
		if option and mapDef and modeDef then
			entry.Button.Visible = true
			entry.Stripe.BackgroundColor3 = modeDef.Color
			entry.Name.Text = modeDef.DisplayName
			entry.Map.Text = "on " .. mapDef.DisplayName
			entry.Rules.Text = compact and modeDef.Rules[1] or table.concat(modeDef.Rules, "\n")
			local n = state.Votes[option] or 0
			local names = voters[option] or {}
			entry.Votes.Text = string.format("<b>%d vote%s</b>%s", n, n == 1 and "" or "s", #names > 0 and (" · " .. nameList(names, compact and 2 or 3)) or "")
		else
			entry.Button.Visible = false
		end
	end
	local count = #roster
	if count == 0 then
		rosterLabel.Text = ""
	elseif #waiting == 0 then
		rosterLabel.Text = string.format("<b>%d player%s</b> · everyone voted · ties: the mode played least recently", count, count == 1 and "" or "s")
	else
		rosterLabel.Text = string.format("<b>%d player%s</b> · waiting for: %s", count, count == 1 and "" or "s", nameList(waiting, compact and 3 or 6))
	end
	HUD.RefreshVoteHighlight()
end

local function updateResults(state: Types.GameState)
	local winnerDef = Teams.Get(state.Winner)
	if winnerDef then
		resultsTitle.Text = winnerDef.Plural .. " WIN!"
		resultsTitle.TextColor3 = winnerDef.Color
		banner.BackgroundColor3 = winnerDef.DarkColor
	else
		resultsTitle.Text = "DRAW!"
		resultsTitle.TextColor3 = Theme.White
		banner.BackgroundColor3 = Theme.PanelLight
	end
	-- Raison détaillée : écrite par le serveur, là où la règle est appliquée
	local reason = state.WinDetail or REASONS[state.WinReason or ""] or ""
	local myTeam = player:GetAttribute("Team")
	if winnerDef and myTeam then
		reason = (myTeam == winnerDef.Id and "Your team won! " or "Your team lost. ") .. reason
	end
	resultsReason.Text = reason
	-- Colonnes des équipes : effectif final (et score du mode)
	for teamId, chip in teamChips do
		local def = Teams.Get(teamId)
		local count = state.TeamCounts[teamId] or 0
		local score = state.ScoreLabel ~= nil and (" · " .. tostring(state.Scores[teamId] or 0)) or ""
		chip.Text.Text = string.format("%s x%d%s", def and def.Plural or teamId, count, score)
		chip.Stroke.Thickness = (winnerDef and winnerDef.Id == teamId) and 4 or 0
	end
	renderAwards()
	local reward = lastReward
	if reward and type(reward.Total) == "number" then
		local parts = {}
		for _, item in reward.Lines or {} do
			table.insert(parts, string.format("%s +%d", item[1], item[2]))
		end
		coinsLine.Text = string.format("+%d coins   (%s)", reward.Total, table.concat(parts, ", "))
		local needed = reward.XPNeeded or 100
		xpLevelLeft.Text = "LV " .. (reward.Level or 1)
		xpText.Text = string.format("%d/%d XP", reward.XP or 0, needed)
		xpFill.Size = UDim2.fromScale(math.clamp((reward.XP or 0) / needed, 0, 1), 1)
		local leveledUp = reward.LevelBefore and reward.Level and reward.Level > reward.LevelBefore
		local unlocks = type(reward.Unlocks) == "table" and reward.Unlocks or {}
		if leveledUp then
			local extra = #unlocks > 0 and ("  ·  " .. unlocks[#unlocks]) or ""
			readyLabel.Text = "LEVEL UP! Level " .. reward.Level .. extra
		else
			-- Ta manche en chiffres
			local survival = tonumber(reward.Survival) or 0
			readyLabel.Text = string.format("You: %d catch%s  ·  %ds longest survival%s", reward.Catches or 0, (reward.Catches or 0) == 1 and "" or "es", survival,
				(reward.Objectives or 0) > 0 and string.format("  ·  %d objective%s", reward.Objectives, reward.Objectives == 1 and "" or "s") or "")
		end
	else
		coinsLine.Text = ""
		local level = profile.Level or 1
		xpLevelLeft.Text = "LV " .. level
		xpText.Text = string.format("%d/%d XP", profile.XP or 0, profile.XPNeeded or 100)
		xpFill.Size = UDim2.fromScale(math.clamp((profile.XP or 0) / (profile.XPNeeded or 100), 0, 1), 1)
		readyLabel.Text = "Next round soon"
	end
end

function HUD.UpdateState(state: Types.GameState)
	local previousPhase = lastState and lastState.Phase
	lastState = state
	local phase = state.Phase
	-- Les règles se ferment quand la manche démarre (et ne couvrent jamais les résultats)
	if phase ~= previousPhase and (phase == "Countdown" or phase == "Results") then
		helpPanel.Visible = false
	end
	local inRound = phase == "Countdown" or phase == "Round" or phase == "Results"
	local myTeam = player:GetAttribute("Team")
	phaseLabel.Text = PHASE_LABELS[phase] or phase

	-- Ruban : rôle pendant la manche, sinon statut
	local roleDef = Teams.Get(currentRole)
	if (phase == "Countdown" or phase == "Round") and currentRole and roleDef then
		mainLabel.Text = roleText(currentRole)
		ribbonStroke.Color = roleDef.Color
	else
		ribbonStroke.Color = Theme.Mint
		if phase == "Intermission" then
			mainLabel.Text = "Vote for the next mode!"
		elseif phase == "Waiting" then
			mainLabel.Text = "Waiting for players..."
		elseif phase == "Results" then
			mainLabel.Text = "Back to the lobby soon"
		else
			mainLabel.Text = Teams.Rule
		end
	end

	local mapDef = MapInfo.Get(state.MapId)
	local modeDef = ModeInfo.Get(state.ModeId)
	local modeName = modeDef and modeDef.DisplayName or (mapDef and mapDef.ModeName) or ""
	if phase == "Intermission" then
		subLabel.Text = "Walk onto a plate or tap a card · one vote each"
	elseif phase == "Countdown" then
		-- Comment gagner dans ce mode, lisible pendant le décompte
		local tagline = modeDef and modeDef.Tagline or (mapDef and mapDef.Tagline) or ""
		subLabel.Text = modeName .. ": " .. tagline
	elseif phase == "Round" and mapDef then
		local goal = state.ScoreGoal and string.format(" · first to %d %s", state.ScoreGoal, state.ScoreLabel or "points") or " · last team standing"
		subLabel.Text = modeName .. " · " .. mapDef.DisplayName .. goal
	else
		subLabel.Text = ""
	end
	local showTimer = phase ~= "Waiting"
	timerLabel.Text = showTimer and Theme.FormatTime(state.TimeLeft) or ""
	timerLabel.Visible = showTimer
	phaseLabel.Position = UDim2.new(showTimer and 0.06 or 0.1, 0, 0.22, 0)
	phaseLabel.Size = UDim2.new(showTimer and 0.36 or 0.8, 0, 0.56, 0)

	for teamId, row in teamRows do
		row.Count.Text = "x" .. tostring(state.TeamCounts[teamId] or 0)
		row.Score.Text = (inRound and state.ScoreLabel ~= nil) and tostring(state.Scores[teamId] or 0) or ""
	end
	teamPanel.Visible = inRound

	votePanel.Visible = phase == "Intermission"
	if votePanel.Visible then
		updateVotePanel(state)
	end
	lineup.Visible = phase == "Countdown"
	if lineup.Visible then
		updateLineup()
	end
	-- Dock d'action : seulement en jeu, jamais sous les résultats.
	-- En tactile, les médaillons sont autour du bouton de saut (ActionBar).
	bottomCenter.Visible = not votePanel.Visible and phase ~= "Results" and not touchMode
	spectatorLabel.Visible = (phase == "Countdown" or phase == "Round") and myTeam == nil

	-- Les annonces appartiennent à la manche (jamais par-dessus les résultats)
	if phase ~= "Round" then
		announcePill.Visible = false
	end
	-- La pastille d'état aussi (à terre, portage, zone sûre)
	statusPill.Visible = PLAYING[phase] == true and myTeam ~= nil and statusText ~= nil and statusText ~= ""
	-- Menus : à gauche du tableau des équipes quand il est affiché ; en tactile
	-- pendant la manche, ils s'effacent (le pouce reste sur le jeu)
	local playing = (phase == "Countdown" or phase == "Round") and myTeam ~= nil
	pillRow.Visible = not (touchMode and playing)
	if phase == "Results" then
		results.Visible = not resultsHidden
		-- Le haut centre ne passe pas derrière la fenêtre de résultats ; sur
		-- téléphone, les panneaux de pièces, de niveau et d'équipes s'effacent aussi
		topCenter.Visible = not results.Visible
		bottomLeft.Visible = not (compact and results.Visible)
		teamPanel.Visible = not (compact and results.Visible)
		updateResults(state)
	else
		results.Visible = false
		topCenter.Visible = true
		-- En tactile, le coin bas-gauche appartient au joystick pendant la manche
		bottomLeft.Visible = not (touchMode and playing)
		resultsHidden = false
		if phase == "Intermission" or phase == "Waiting" then
			lastReward = nil
		end
	end
	rescale()
end

-- Appelé par ActionBar quand on passe du clavier au tactile (ou l'inverse)
function HUD.SetTouchMode(on: boolean)
	if touchMode == on then
		return
	end
	touchMode = on
	helpText.Text = HELP_RULES .. (on and HELP_TOUCH or HELP_KEYS)
	if lastState then
		HUD.UpdateState(lastState)
	end
end

-- Disposition selon la taille de l'écran (téléphone = plus petit côté < 500 px)
rescale = function()
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	local size = camera.ViewportSize
	local small = math.min(size.X, size.Y) < 500
	-- Portrait (si l'orientation libre est activée) : les blocs s'empilent
	local portrait = size.Y > size.X
	compact = small
	-- Résultats : tiennent dans l'écran
	local scale = math.clamp(math.min(size.X / 820, (size.Y - (small and 72 or 0)) / 560), 0.45, 1)
	local s = results:FindFirstChild("Scale")
	if s and s:IsA("UIScale") then
		s.Scale = scale
	end
	results.Position = small and UDim2.new(0.5, 0, 0.5, 24) or UDim2.fromScale(0.5, 0.52)
	local helpScale = helpPanel:FindFirstChild("Scale")
	if helpScale and helpScale:IsA("UIScale") then
		helpScale.Scale = math.clamp(math.min(size.X / 600, size.Y / 400), 0.55, 1)
	end
	-- Haut centre : capsule chrono, ruban, ligne d'objectif (jamais sous le
	-- tableau des équipes ni le fil des captures, voir KillFeed.Rescale)
	local teamWidth = small and 160 or 230
	local sideWidth = small and (170 + 8 + 8) or (250 + 14 + 8)
	local centerWidth = portrait and (size.X - 24) or math.min((small and 0.44 or 0.56) * size.X, size.X - 2 * sideWidth, 600)
	topCenter.Size = UDim2.new(0, centerWidth, 0, small and 82 or 112)
	topCenter.Position = UDim2.new(0.5, 0, 0, small and 6 or 10)
	clock.Size = UDim2.new(0, small and 132 or 176, 0, small and 34 or 46)
	mainLabel.Position = UDim2.new(0.5, 0, 0, small and 38 or 52)
	mainLabel.Size = UDim2.new(1, 0, 0, small and 26 or 34)
	local ribbonMax = mainLabel:FindFirstChildOfClass("UITextSizeConstraint")
	if ribbonMax then
		ribbonMax.MaxTextSize = small and 15 or 22
	end
	subLabel.Position = UDim2.new(0, 0, 0, small and 66 or 90)
	subLabel.Size = UDim2.new(1, 0, 0, small and 15 or 20)
	-- Pastille d'état puis annonce : sous la ligne d'objectif (en portrait, sous
	-- les équipes), à la largeur du bloc du haut (jamais sous les panneaux latéraux)
	local stackY = portrait and 186 or (small and 90 or 128)
	local statusHeight = small and 26 or 34
	statusPill.Position = UDim2.new(0.5, 0, 0, stackY)
	statusPill.Size = UDim2.new(0, math.min(portrait and (size.X - 24) or centerWidth, 520), 0, statusHeight)
	local statusMax = statusLabel:FindFirstChildOfClass("UITextSizeConstraint")
	if statusMax then
		statusMax.MaxTextSize = small and 15 or 20
	end
	local announceY = statusPill.Visible and (stackY + statusHeight + (small and 4 or 6)) or (portrait and 186 or (small and 88 or 128))
	announcePill.Position = UDim2.new(0.5, 0, 0, announceY)
	announcePill.Size = UDim2.new(0, math.min(small and 300 or 440, portrait and (size.X - 24) or 0.42 * size.X), 0, small and 22 or 30)
	local announceMax = announceLabel:FindFirstChildOfClass("UITextSizeConstraint")
	if announceMax then
		announceMax.MaxTextSize = small and 15 or 22
	end
	-- Menus en haut à droite, à gauche du tableau des équipes s'il est visible
	local pillWidth = small and 72 or 104
	for _, pill in HUD.Pills do
		pill.Size = UDim2.new(0, pillWidth, 1, 0)
	end
	local pillList = pillRow:FindFirstChildOfClass("UIListLayout")
	if pillList then
		pillList.Padding = UDim.new(0, small and 6 or 8)
	end
	pillRow.Size = UDim2.new(0, 3 * pillWidth + 2 * (small and 6 or 8), 0, small and 30 or 40)
	local rightInset = (teamPanel.Visible and not portrait) and (12 + teamWidth + 8) or 12
	pillRow.Position = UDim2.new(1, -rightInset, 0, portrait and 94 or (small and 8 or 14))
	-- Panneaux du bas
	bottomLeft.Size = UDim2.new(0, small and 150 or 230, 0, small and 78 or 112)
	coinsPanel.Size = UDim2.new(0, small and 150 or 230, 0, small and 35 or 52)
	levelPanel.Size = coinsPanel.Size
	teamPanel.Size = UDim2.new(0, teamWidth, 0, small and 78 or 112)
	-- En portrait, le tableau des équipes passe sous le bloc du haut, à gauche
	teamPanel.AnchorPoint = portrait and Vector2.new(0, 0) or Vector2.new(1, 0)
	teamPanel.Position = portrait and UDim2.new(0, 12, 0, 94) or UDim2.new(1, -12, 0, 14)
	for _, row in teamRows do
		row.Row.Size = UDim2.new(0.92, 0, 0, small and 21 or 30)
	end
	bottomCenter.Position = UDim2.new(0.5, 0, 1, small and -8 or -14)
	-- Composition des équipes : au milieu, sous la pastille d'état
	lineup.Size = UDim2.new(0, math.min(600, size.X - 24), 0, small and 104 or 150)
	lineup.Position = UDim2.new(0.5, 0, 0, portrait and 240 or (small and 124 or 176))
	-- Vote : à droite des pièces quand l'écran est trop étroit pour le centrer ;
	-- en portrait, sur toute la largeur au-dessus des pièces
	local currencyRight = 12 + (small and 150 or 230) + 8
	local voteWidth = math.min(720, size.X - currencyRight - 12)
	local voteLeft = math.max(currencyRight, (size.X - voteWidth) / 2)
	local voteHeight = small and 156 or 214
	if portrait then
		votePanel.Position = UDim2.new(0, 12, 1, -(12 + (small and 78 or 112) + 10))
		votePanel.Size = UDim2.new(0, size.X - 24, 0, 214)
	else
		votePanel.Position = UDim2.new(0, voteLeft, 1, small and -10 or -14)
		votePanel.Size = UDim2.new(0, voteWidth, 0, voteHeight)
	end
	voteTitle.Size = UDim2.new(1, 0, 0, small and 18 or 24)
	voteButtonsFrame.Position = UDim2.new(0, 0, 0, small and 20 or 28)
	voteButtonsFrame.Size = UDim2.new(1, 0, 1, -(small and 20 or 28) - (small and 22 or 28))
	rosterLabel.Size = UDim2.new(1, 0, 0, small and 18 or 22)
end
HUD.Rescale = rescale
rescale()
if workspace.CurrentCamera then
	workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(rescale)
end

return HUD

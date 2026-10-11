--[[
	HUD.lua
	Interface principale, construite par le code, d'après la disposition de la
	référence (reference/HUSS_VALLEY_NOTES.md, section A) :
	  - en haut à gauche : pastilles SHOP / SPIN / HELP (à côté des boutons Roblox) ;
	  - en haut au centre : petit libellé de phase, grand message (bandeau de rôle :
	    "You are a FOX - Catch CHICKENS - Avoid SNAKES"), sous-ligne avec le chrono ;
	  - en haut à droite : équipes (membres et score) pendant la manche ;
	  - sous le bloc du haut : annonces courtes (petite pastille, le centre reste libre) ;
	  - en bas à gauche : pièces et niveau ;
	  - en bas au centre : cartes (capacité, objets) et barre de dash (ActionBar,
	    Inventory) ; panneau de vote pendant l'intermission ;
	  - fin de manche : podium (meilleur joueur / survie / captures) + expérience.
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
local New, Label, Title = Theme.New, Theme.Label, Theme.Title

local PHASE_LABELS = {
	Waiting = "LOBBY",
	Intermission = "LOBBY",
	Countdown = "GET READY",
	Round = "ROUND",
	Results = "RESULTS",
}
local REASONS = {
	Objective = "Objective completed",
	LastStanding = "Last team standing",
	TimeUp = "Time's up",
	Draw = "No winner this time",
}
local PODIUM_TABS = { { Key = "MVP", Label = "Best player" }, { Key = "Survival", Label = "Survival" }, { Key = "Catches", Label = "Catches" } }

local voteCallback: ((string) -> ())? = nil
local compact = false -- petit écran (téléphone en paysage)
local touchMode = false -- commandes tactiles affichées (voir ActionBar)
local myVote: string? = nil
local lastCandidatesKey = ""
local lastReward: { [string]: any }? = nil
local lastState: Types.GameState? = nil
local podiumTab = "MVP"
local profile: { [string]: any } = {}

-- ---------------------------------------------------------------------------
-- Écran
-- ---------------------------------------------------------------------------
local screen: ScreenGui = New("ScreenGui", {
	Name = "HuntOrHideHUD",
	ResetOnSpawn = false,
	IgnoreGuiInset = true, -- on place nos pastilles dans la rangée de la barre Roblox
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	DisplayOrder = 10,
}, playerGui)
HUD.Screen = screen

-- ---------------------------------------------------------------------------
-- Pastilles en haut à gauche
-- ---------------------------------------------------------------------------
local pillRow: Frame = New("Frame", {
	Name = "Pills",
	Position = UDim2.new(0, 228, 0, 14),
	Size = UDim2.new(0, 360, 0, 42),
	BackgroundTransparency = 1,
}, screen)
New("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }, pillRow)
HUD.Pills = {}
for index, name in { "SHOP", "SPIN", "HELP" } do
	local pill = Theme.Pill(pillRow, name, { Name = name, Size = UDim2.new(0, 104, 1, 0), LayoutOrder = index })
	HUD.Pills[name] = pill
end
local spinBadge = Theme.Badge(HUD.Pills.SPIN)

-- ---------------------------------------------------------------------------
-- Haut centre : libellé de phase, message principal, sous-ligne
-- ---------------------------------------------------------------------------
local topCenter: Frame = New("Frame", {
	Name = "TopCenter",
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 58),
	Size = UDim2.new(0.56, 0, 0, 108),
	BackgroundTransparency = 1,
}, screen)
local phaseLabel = Title(topCenter, { Name = "Phase", Size = UDim2.new(1, 0, 0, 18), Text = "LOBBY", FontFace = Theme.FaceHeavy })
local mainLabel = Title(topCenter, { Name = "Main", Position = UDim2.new(0, 0, 0, 22), Size = UDim2.new(1, 0, 0, 40), Text = Teams.Rule, RichText = true })
Theme.MaxText(mainLabel, 34)
local subLabel = Title(topCenter, { Name = "Sub", Position = UDim2.new(0, 0, 0, 66), Size = UDim2.new(1, 0, 0, 20), Text = "", FontFace = Theme.FaceBold })
local timerLabel = Title(topCenter, { Name = "Timer", Position = UDim2.new(0, 0, 0, 86), Size = UDim2.new(1, 0, 0, 22), Text = "", FontFace = Theme.FaceHeavy, TextColor3 = Theme.Gold })

-- ---------------------------------------------------------------------------
-- Haut droite : équipes
-- ---------------------------------------------------------------------------
local teamPanel: Frame = New("Frame", {
	Name = "Teams",
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, -12, 0, 14),
	Size = UDim2.new(0, 230, 0, 112),
	BackgroundColor3 = Theme.Panel,
	BackgroundTransparency = 0.15,
	Visible = false,
}, screen)
Theme.Corner(teamPanel, 10)
Theme.Stroke(teamPanel, 2, Theme.White, 0.35)
New("UIListLayout", { Padding = UDim.new(0, 4), HorizontalAlignment = Enum.HorizontalAlignment.Center, VerticalAlignment = Enum.VerticalAlignment.Center, SortOrder = Enum.SortOrder.LayoutOrder }, teamPanel)
local teamRows: { [string]: { Row: Frame, Count: TextLabel, Score: TextLabel, Stroke: UIStroke } } = {}
for index, teamId in Teams.Order do
	local def = Teams.Get(teamId)
	assert(def)
	local row: Frame = New("Frame", { Name = teamId, Size = UDim2.new(0.92, 0, 0, 30), BackgroundColor3 = def.Color, LayoutOrder = index }, teamPanel)
	Theme.Corner(row, 7)
	local stroke = Theme.Stroke(row, 0, Theme.White)
	Title(row, { Size = UDim2.fromScale(0.5, 0.7), Position = UDim2.fromScale(0.05, 0.15), Text = def.Display, TextXAlignment = Enum.TextXAlignment.Left, FontFace = Theme.FaceHeavy })
	local count = Title(row, { Size = UDim2.fromScale(0.2, 0.7), Position = UDim2.fromScale(0.55, 0.15), Text = "x0", FontFace = Theme.FaceHeavy })
	local score = Title(row, { Size = UDim2.fromScale(0.22, 0.7), Position = UDim2.fromScale(0.76, 0.15), Text = "", FontFace = Theme.FaceHeavy, TextColor3 = Theme.Gold })
	teamRows[teamId] = { Row = row, Count = count, Score = score, Stroke = stroke }
end

-- ---------------------------------------------------------------------------
-- Bas gauche : pièces et niveau
-- ---------------------------------------------------------------------------
local function currencyPanel(name: string, order: number, iconColor: Color3): (Frame, TextLabel, TextLabel, Frame)
	local frame: Frame = New("Frame", {
		Name = name,
		Size = UDim2.new(0, 230, 0, 52),
		BackgroundColor3 = Theme.Dark,
		BackgroundTransparency = 0.25,
		LayoutOrder = order,
	}, nil)
	Theme.Corner(frame, 8)
	Theme.Stroke(frame, 2, Theme.Outline)
	local icon: Frame = New("Frame", { AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 10, 0.5, 0), Size = UDim2.new(0, 28, 0, 28), BackgroundColor3 = iconColor }, frame)
	Theme.CornerScale(icon, 0.5)
	Theme.Stroke(icon, 2, iconColor:Lerp(Color3.new(0, 0, 0), 0.35))
	local value = Title(frame, { Name = "Value", Position = UDim2.new(0, 46, 0, 4), Size = UDim2.new(1, -54, 0, 28), Text = "0", TextXAlignment = Enum.TextXAlignment.Left, FontFace = Theme.FaceHeavy })
	local caption = Label(frame, { Name = "Caption", Position = UDim2.new(0, 46, 0, 32), Size = UDim2.new(1, -54, 0, 14), Text = "", TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = Theme.Muted })
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
local levelPanel, levelValue, levelCaption = currencyPanel("Level", 2, Theme.Good)
levelPanel.Parent = bottomLeft
local levelBar: Frame = New("Frame", { Position = UDim2.new(0, 46, 1, -8), Size = UDim2.new(1, -58, 0, 4), BackgroundColor3 = Theme.PanelLight, BorderSizePixel = 0 }, levelPanel)
local levelFill: Frame = New("Frame", { Size = UDim2.fromScale(0, 1), BackgroundColor3 = Theme.Good, BorderSizePixel = 0 }, levelBar)
levelCaption.Position = UDim2.new(0, 46, 0, 30)

-- ---------------------------------------------------------------------------
-- Bas centre : rangée de cartes (capacité, objets) + vote
-- ---------------------------------------------------------------------------
local bottomCenter: Frame = New("Frame", {
	Name = "BottomCenter",
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 1, -64),
	Size = UDim2.new(0, 640, 0, 82),
	BackgroundTransparency = 1,
}, screen)
New("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 8), HorizontalAlignment = Enum.HorizontalAlignment.Center, VerticalAlignment = Enum.VerticalAlignment.Bottom, SortOrder = Enum.SortOrder.LayoutOrder }, bottomCenter)
HUD.BottomRow = bottomCenter

-- Panneau de vote (intermission)
local votePanel: Frame = New("Frame", {
	Name = "VotePanel",
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 1, -66),
	Size = UDim2.new(0, 660, 0, 150),
	BackgroundTransparency = 1,
	Visible = false,
}, screen)
New("UISizeConstraint", { MaxSize = Vector2.new(660, 150) }, votePanel)
Title(votePanel, { Size = UDim2.new(1, 0, 0, 26), Text = "VOTE FOR THE NEXT MAP" })
local voteButtonsFrame: Frame = New("Frame", { Position = UDim2.new(0, 0, 0, 32), Size = UDim2.new(1, 0, 1, -32), BackgroundTransparency = 1 }, votePanel)
New("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 10), HorizontalAlignment = Enum.HorizontalAlignment.Center, SortOrder = Enum.SortOrder.LayoutOrder }, voteButtonsFrame)

type VoteButton = { Button: TextButton, Name: TextLabel, Mode: TextLabel, Votes: TextLabel, Stripe: Frame, MapId: string?, Stroke: UIStroke }
local voteButtons: { VoteButton } = {}

function HUD.RefreshVoteHighlight()
	for _, entry in voteButtons do
		local selected = entry.MapId ~= nil and entry.MapId == myVote
		entry.Stroke.Color = selected and Theme.Gold or Theme.Outline
		entry.Stroke.Thickness = selected and 4 or 3
	end
end

for index = 1, 3 do
	local button: TextButton = New("TextButton", {
		Name = "Vote" .. index,
		Size = UDim2.new(0.31, 0, 1, 0),
		BackgroundColor3 = Theme.Panel,
		BackgroundTransparency = 0.08,
		Text = "",
		AutoButtonColor = true,
		LayoutOrder = index,
	}, voteButtonsFrame)
	Theme.Corner(button, 10)
	local stroke = Theme.Stroke(button, 3, Theme.Outline)
	local stripe: Frame = New("Frame", { Size = UDim2.new(1, 0, 0, 8), BackgroundColor3 = Theme.Gold, BorderSizePixel = 0 }, button)
	Theme.Corner(stripe, 6)
	local nameLabel = Title(button, { Size = UDim2.new(0.9, 0, 0.34, 0), Position = UDim2.fromScale(0.05, 0.12), Text = "?" })
	local modeLabel = Label(button, { Size = UDim2.new(0.9, 0, 0.2, 0), Position = UDim2.fromScale(0.05, 0.5), Text = "", TextColor3 = Theme.Gold, FontFace = Theme.FaceHeavy })
	local votesLabel = Label(button, { Size = UDim2.new(0.9, 0, 0.18, 0), Position = UDim2.fromScale(0.05, 0.74), Text = "", TextColor3 = Theme.Muted })
	local entry: VoteButton = { Button = button, Name = nameLabel, Mode = modeLabel, Votes = votesLabel, Stripe = stripe, MapId = nil, Stroke = stroke }
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

-- ---------------------------------------------------------------------------
-- Annonces, notifications, spectateur, aide
-- ---------------------------------------------------------------------------
-- Annonce de la map (oeuf volé, points...) : petite pastille sous le bloc du
-- haut, jamais au milieu de l'écran, où se joue la poursuite
local announcePill: Frame = New("Frame", {
	Name = "Announce",
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 174),
	Size = UDim2.new(0, 440, 0, 30),
	BackgroundColor3 = Theme.Dark,
	BackgroundTransparency = 0.35,
	Visible = false,
	ZIndex = 5,
}, screen)
Theme.CornerScale(announcePill, 0.5)
local announceLabel = Title(announcePill, {
	Name = "Text",
	Position = UDim2.new(0, 14, 0, 4),
	Size = UDim2.new(1, -28, 1, -8),
	Text = "",
	FontFace = Theme.FaceHeavy,
	ZIndex = 5,
})
Theme.MaxText(announceLabel, 22)

local toast: TextLabel = Label(screen, {
	Name = "Toast",
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 1, -170),
	Size = UDim2.new(0, 420, 0, 34),
	BackgroundColor3 = Theme.Dark,
	BackgroundTransparency = 0.15,
	Text = "",
	Visible = false,
	ZIndex = 30,
})
Theme.Corner(toast, 8)
New("UIPadding", { PaddingTop = UDim.new(0, 6), PaddingBottom = UDim.new(0, 6) }, toast)

local spectatorLabel = Title(screen, {
	Name = "Spectator",
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 1, -170),
	Size = UDim2.new(0.6, 0, 0, 26),
	Text = "A round is in progress. You'll join the next one!",
	Visible = false,
})

local helpPanel: Frame = New("Frame", {
	Name = "Help",
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.new(0, 520, 0, 330),
	BackgroundColor3 = Theme.Panel,
	BackgroundTransparency = 0.05,
	Visible = false,
	ZIndex = 40,
}, screen)
Theme.Corner(helpPanel, 14)
Theme.Stroke(helpPanel, 4, Theme.Outline)
Title(helpPanel, { Size = UDim2.new(1, 0, 0, 40), Position = UDim2.new(0, 0, 0, 12), Text = "HOW TO PLAY", ZIndex = 40 })
-- Règles : la partie "commandes" suit l'appareil (clavier ou tactile)
local HELP_RULES = "Catch your prey. Run from your hunter.\n\nFOX catches CHICKEN, CHICKEN catches SNAKE, SNAKE catches FOX.\nGreen outline = your prey. Red outline = your hunter.\nCaught? You join the team that caught you and keep playing.\n\n"
local HELP_KEYS = "Q / E : dash sideways to dodge    F : stop dead to fake out\nR : your animal's ability    Hide in tall grass and bushes!"
local HELP_TOUCH = "DASH buttons : dodge sideways    STOP : stop dead to fake out\nBig round button : your animal's ability    Hide in tall grass!"
local helpText = Label(helpPanel, {
	Name = "Rules",
	Size = UDim2.new(1, -40, 1, -70),
	Position = UDim2.new(0, 20, 0, 58),
	TextScaled = true,
	TextWrapped = true,
	TextYAlignment = Enum.TextYAlignment.Top,
	TextXAlignment = Enum.TextXAlignment.Left,
	ZIndex = 40,
	Text = HELP_RULES .. HELP_KEYS,
})
New("UIScale", { Name = "Scale" }, helpPanel)
local helpClose: TextButton = New("TextButton", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -10, 0, 10), Size = UDim2.new(0, 36, 0, 36), BackgroundColor3 = Theme.Bad, Text = "X", FontFace = Theme.FaceHeavy, TextScaled = true, TextColor3 = Theme.White, ZIndex = 41 }, helpPanel)
Theme.Corner(helpClose, 8)
helpClose.Activated:Connect(function()
	helpPanel.Visible = false
end)
HUD.Pills.HELP.Activated:Connect(function()
	helpPanel.Visible = not helpPanel.Visible
end)

-- ---------------------------------------------------------------------------
-- Résultats : podium + expérience
-- ---------------------------------------------------------------------------
local results: Frame = New("Frame", {
	Name = "Results",
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.52),
	Size = UDim2.new(0, 760, 0, 520),
	BackgroundColor3 = Theme.Panel,
	BackgroundTransparency = 0.05,
	Visible = false,
	ZIndex = 20,
}, screen)
Theme.Corner(results, 18)
Theme.Stroke(results, 5, Theme.Outline)
New("UISizeConstraint", { MaxSize = Vector2.new(760, 520), MinSize = Vector2.new(360, 250) }, results)
New("UIScale", { Name = "Scale", Scale = 1 }, results)
local resultsTitle = Title(results, { Size = UDim2.new(1, -140, 0, 44), Position = UDim2.new(0, 70, 0, 26), Text = "", ZIndex = 20 })
local resultsReason = Title(results, { Size = UDim2.new(1, -120, 0, 24), Position = UDim2.new(0, 60, 0, 74), Text = "", TextColor3 = Theme.Good, ZIndex = 20 })
local resultsClose: TextButton = New("TextButton", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -16, 0, 16), Size = UDim2.new(0, 48, 0, 48), BackgroundTransparency = 1, Text = "X", TextColor3 = Theme.Bad, FontFace = Theme.FaceTitle, TextScaled = true, TextStrokeTransparency = 0, ZIndex = 21 }, results)
local resultsHidden = false
resultsClose.Activated:Connect(function()
	resultsHidden = true
	results.Visible = false
end)
local tabRow: Frame = New("Frame", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 106), Size = UDim2.new(0, 420, 0, 34), BackgroundTransparency = 1, ZIndex = 20 }, results)
New("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 6), HorizontalAlignment = Enum.HorizontalAlignment.Center, SortOrder = Enum.SortOrder.LayoutOrder }, tabRow)
local tabButtons: { [string]: TextButton } = {}
local podiumFrame: Frame = New("Frame", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 150), Size = UDim2.new(0, 700, 0, 230), BackgroundTransparency = 1, ZIndex = 20 }, results)
local readyLabel = Title(results, { Size = UDim2.new(1, -40, 0, 32), Position = UDim2.new(0, 20, 0, 392), Text = "Ready for the next match", TextColor3 = Theme.Gold, ZIndex = 20 })
local coinsLine = Title(results, { Size = UDim2.new(1, -40, 0, 20), Position = UDim2.new(0, 20, 0, 428), Text = "", FontFace = Theme.FaceBold, TextColor3 = Theme.Coin, ZIndex = 20 })
local xpRow: Frame = New("Frame", { Position = UDim2.new(0, 20, 1, -58), Size = UDim2.new(1, -40, 0, 30), BackgroundTransparency = 1, ZIndex = 20 }, results)
local xpLevelLeft = Title(xpRow, { Size = UDim2.new(0, 110, 1, 0), Text = "Level 1", FontFace = Theme.FaceHeavy, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 20 })
local xpLevelRight = Title(xpRow, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 0), Size = UDim2.new(0, 110, 1, 0), Text = "Level 2", FontFace = Theme.FaceHeavy, TextXAlignment = Enum.TextXAlignment.Right, ZIndex = 20 })
local xpBar: Frame = New("Frame", { Position = UDim2.new(0, 120, 0.15, 0), Size = UDim2.new(1, -240, 0.7, 0), BackgroundColor3 = Theme.Dark, ZIndex = 20 }, xpRow)
Theme.CornerScale(xpBar, 0.5)
Theme.Stroke(xpBar, 2, Theme.Outline)
local xpFill: Frame = New("Frame", { Size = UDim2.fromScale(0, 1), BackgroundColor3 = Theme.Gold, ZIndex = 21 }, xpBar)
Theme.CornerScale(xpFill, 0.5)
local xpText = Title(xpBar, { Size = UDim2.fromScale(1, 0.9), Position = UDim2.fromScale(0, 0.05), Text = "", FontFace = Theme.FaceHeavy, ZIndex = 22 })

local PODIUM_STYLE = {
	{ Slot = 2, Color = Color3.fromRGB(40, 150, 150), Scale = 0.9 },
	{ Slot = 1, Color = Color3.fromRGB(230, 170, 30), Scale = 1 },
	{ Slot = 3, Color = Color3.fromRGB(90, 96, 110), Scale = 0.9 },
}

local function renderPodium()
	for _, child in podiumFrame:GetChildren() do
		child:Destroy()
	end
	for _, tab in PODIUM_TABS do
		local button = tabButtons[tab.Key]
		if button then
			local selected = tab.Key == podiumTab
			button.BackgroundColor3 = selected and Theme.Good or Theme.PanelLight
		end
	end
	local state = lastState
	local list = state and state.Podium and state.Podium[podiumTab] or {}
	local width = 210
	for index, style in PODIUM_STYLE do
		local entry = list[style.Slot]
		local x = (index - 2) * (width + 16)
		local h = 220 * style.Scale
		local card: Frame = New("Frame", {
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, x, 1, 0),
			Size = UDim2.new(0, width * style.Scale, 0, h),
			BackgroundColor3 = style.Color,
			ZIndex = 21,
		}, podiumFrame)
		Theme.Corner(card, 12)
		Theme.Stroke(card, style.Slot == 1 and 4 or 3, style.Slot == 1 and Theme.Gold or Theme.Outline)
		Title(card, { Size = UDim2.new(1, 0, 0, 34), Position = UDim2.new(0, 0, 0, 6), Text = "#" .. style.Slot, ZIndex = 22 })
		if entry then
			local portrait: Frame = New("Frame", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 40), Size = UDim2.new(0, h * 0.45, 0, h * 0.45), BackgroundColor3 = style.Color:Lerp(Color3.new(1, 1, 1), 0.25), ZIndex = 22 }, card)
			Theme.Corner(portrait, 10)
			if entry.UserId and entry.UserId > 0 then
				New("ImageLabel", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Image = string.format("rbxthumb://type=AvatarHeadShot&id=%d&w=150&h=150", entry.UserId), ZIndex = 23 }, portrait)
			else
				Title(portrait, { Size = UDim2.fromScale(0.8, 0.8), Position = UDim2.fromScale(0.1, 0.1), Text = string.upper(string.sub(entry.Name, 1, 1)), ZIndex = 23 })
			end
			Title(card, { Size = UDim2.new(0.92, 0, 0, 26), Position = UDim2.new(0.04, 0, 1, -66), Text = entry.Name, FontFace = Theme.FaceHeavy, ZIndex = 22 })
			Title(card, { Size = UDim2.new(0.92, 0, 0, 30), Position = UDim2.new(0.04, 0, 1, -38), Text = entry.Value, TextColor3 = Theme.Gold, ZIndex = 22 })
		end
	end
end

for index, tab in PODIUM_TABS do
	local button: TextButton = New("TextButton", { Size = UDim2.new(0, 134, 1, 0), BackgroundColor3 = Theme.PanelLight, Text = tab.Label, TextColor3 = Theme.White, FontFace = Theme.FaceHeavy, TextScaled = true, LayoutOrder = index, ZIndex = 21 }, tabRow)
	Theme.Corner(button, 6)
	Theme.Stroke(button, 2, Theme.Outline)
	New("UIPadding", { PaddingTop = UDim.new(0, 6), PaddingBottom = UDim.new(0, 6) }, button)
	button.Activated:Connect(function()
		podiumTab = tab.Key
		renderPodium()
	end)
	tabButtons[tab.Key] = button
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

-- Bandeau de rôle en texte riche : animal en couleur, proie en vert, prédateur en rouge
local function roleText(teamId: string): string
	local def = Teams.Get(teamId)
	if not def then
		return Teams.Rule
	end
	local prey = Teams.Defs[def.Prey]
	local predator = Teams.Defs[def.Predator]
	return string.format(
		'You are a <font color="%s">%s</font> - Catch <font color="%s">%s</font> - Avoid <font color="%s">%s</font>',
		Theme.Hex(def.Color), def.Display, Theme.Hex(Teams.PreyOutlineColor), prey.Plural, Theme.Hex(Teams.PredatorOutlineColor), predator.Plural
	)
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
	announcePill.BackgroundTransparency = 0.35
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
			entry.Stripe.BackgroundColor3 = def.Color
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
		resultsTitle.TextColor3 = Theme.White
	end
	-- Raison détaillée : écrite par le serveur, là où la règle est appliquée
	local reason = state.WinDetail or REASONS[state.WinReason or ""] or ""
	local myTeam = player:GetAttribute("Team")
	if winnerDef and myTeam then
		reason = (myTeam == winnerDef.Id and "Your team won! " or "Your team lost. ") .. reason
	end
	resultsReason.Text = reason
	renderPodium()
	local reward = lastReward
	if reward and type(reward.Total) == "number" then
		local parts = {}
		for _, item in reward.Lines or {} do
			table.insert(parts, string.format("%s +%d", item[1], item[2]))
		end
		coinsLine.Text = string.format("+%d coins   (%s)", reward.Total, table.concat(parts, ", "))
		local needed = reward.XPNeeded or 100
		xpLevelLeft.Text = "Level " .. (reward.Level or 1)
		xpLevelRight.Text = "Level " .. ((reward.Level or 1) + 1)
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
		xpLevelLeft.Text = "Level " .. level
		xpLevelRight.Text = "Level " .. (level + 1)
		xpText.Text = string.format("%d/%d XP", profile.XP or 0, profile.XPNeeded or 100)
		xpFill.Size = UDim2.fromScale(math.clamp((profile.XP or 0) / (profile.XPNeeded or 100), 0, 1), 1)
		readyLabel.Text = "Ready for the next match"
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

	-- Message principal : bandeau de rôle pendant la manche, sinon statut
	if (phase == "Countdown" or phase == "Round") and currentRole then
		mainLabel.Text = roleText(currentRole)
	elseif phase == "Intermission" then
		mainLabel.Text = "Vote for the next map!"
	elseif phase == "Waiting" then
		mainLabel.Text = "Waiting for players..."
	elseif phase == "Results" then
		mainLabel.Text = "Back to the lobby soon"
	else
		mainLabel.Text = Teams.Rule
	end

	local mapDef = MapInfo.Get(state.MapId)
	if phase == "Intermission" then
		subLabel.Text = "Next match soon"
	elseif phase == "Countdown" then
		-- Comment gagner sur cette map, lisible pendant le décompte
		subLabel.Text = mapDef and (mapDef.ModeName .. ": " .. mapDef.Tagline) or ""
	elseif phase == "Round" and mapDef then
		local goal = state.ScoreGoal and string.format(" · First to %d %s", state.ScoreGoal, state.ScoreLabel or "points") or ""
		subLabel.Text = mapDef.DisplayName .. " · " .. mapDef.ModeName .. goal
	elseif phase == "Results" then
		subLabel.Text = ""
	else
		subLabel.Text = ""
	end
	timerLabel.Text = (phase == "Waiting") and "" or Theme.FormatTime(state.TimeLeft)

	for teamId, row in teamRows do
		row.Count.Text = "x" .. tostring(state.TeamCounts[teamId] or 0)
		row.Score.Text = (inRound and state.ScoreLabel ~= nil) and tostring(state.Scores[teamId] or 0) or ""
	end
	teamPanel.Visible = inRound

	votePanel.Visible = phase == "Intermission"
	if votePanel.Visible then
		updateVotePanel(state)
	end
	-- Barre d'action (capacité, dash) : seulement en jeu, jamais sous les résultats.
	-- En tactile, les boutons ronds affichent déjà capacité et recharges.
	bottomCenter.Visible = not votePanel.Visible and phase ~= "Results" and not touchMode
	local dashBar = screen:FindFirstChild("DashBar")
	if dashBar and dashBar:IsA("GuiObject") then
		dashBar.Visible = phase ~= "Results" and phase ~= "Intermission" and not touchMode
	end
	spectatorLabel.Visible = (phase == "Countdown" or phase == "Round") and myTeam == nil

	-- Les annonces appartiennent à la manche (jamais par-dessus les résultats)
	if phase ~= "Round" then
		announcePill.Visible = false
	end
	if phase == "Results" then
		results.Visible = not resultsHidden
		-- Le titre du haut ne passe pas derrière la fenêtre de résultats ; sur
		-- téléphone, les panneaux de pièces, de niveau et d'équipes s'effacent aussi
		topCenter.Visible = not results.Visible
		bottomLeft.Visible = not (compact and results.Visible)
		teamPanel.Visible = not (compact and results.Visible)
		updateResults(state)
	else
		results.Visible = false
		topCenter.Visible = true
		-- En tactile, le coin bas-gauche appartient au joystick pendant la manche
		bottomLeft.Visible = not (touchMode and (phase == "Countdown" or phase == "Round") and myTeam ~= nil)
		resultsHidden = false
		if phase == "Intermission" or phase == "Waiting" then
			lastReward = nil
		end
	end
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

-- Échelle de l'écran de résultats sur petit écran
local function rescale()
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	local size = camera.ViewportSize
	local small = size.Y < 500
	compact = small
	-- Résultats : tiennent entre les pastilles du haut et le bas de l'écran
	local scale = math.clamp(math.min(size.X / 820, (size.Y - (small and 72 or 0)) / 560), 0.45, 1)
	local s = results:FindFirstChild("Scale")
	if s and s:IsA("UIScale") then
		s.Scale = scale
	end
	results.Position = small and UDim2.new(0.5, 0, 0.5, 30) or UDim2.fromScale(0.5, 0.52)
	-- Pastilles plus basses et plus étroites sur téléphone : le bloc du haut respire
	pillRow.Position = UDim2.new(0, 228, 0, small and 8 or 14)
	pillRow.Size = UDim2.new(0, 360, 0, small and 32 or 42)
	local pillList = pillRow:FindFirstChildOfClass("UIListLayout")
	if pillList then
		pillList.Padding = UDim.new(0, small and 6 or 8)
	end
	for _, pill in HUD.Pills do
		pill.Size = UDim2.new(0, small and 84 or 104, 1, 0)
	end
	-- Haut centre sur téléphone : pas de libellé de phase, lignes bien séparées
	phaseLabel.Visible = not small
	mainLabel.Position = UDim2.new(0, 0, 0, small and 0 or 22)
	mainLabel.Size = UDim2.new(1, 0, 0, small and 24 or 40)
	subLabel.Position = UDim2.new(0, 0, 0, small and 28 or 66)
	subLabel.Size = UDim2.new(1, 0, 0, small and 16 or 20)
	timerLabel.Position = UDim2.new(0, 0, 0, small and 48 or 88)
	timerLabel.Size = UDim2.new(1, 0, 0, small and 20 or 22)
	local helpScale = helpPanel:FindFirstChild("Scale")
	if helpScale and helpScale:IsA("UIScale") then
		helpScale.Scale = math.clamp(math.min(size.X / 600, size.Y / 420), 0.55, 1)
	end
	bottomLeft.Size = UDim2.new(0, small and 150 or 230, 0, small and 78 or 112)
	coinsPanel.Size = UDim2.new(0, small and 150 or 230, 0, small and 35 or 52)
	levelPanel.Size = coinsPanel.Size
	-- Bloc central : jamais sous le panneau des équipes ni sous le fil des captures
	-- (largeur 170 px sur téléphone, 250 px sinon, voir KillFeed.Rescale)
	local sideWidth = small and (170 + 8 + 8) or (250 + 14 + 8)
	local centerWidth = math.min((small and 0.44 or 0.56) * size.X, size.X - 2 * sideWidth)
	topCenter.Size = UDim2.new(0, centerWidth, 0, small and 68 or 110)
	topCenter.Position = UDim2.new(0.5, 0, 0, small and 44 or 58)
	teamPanel.Size = UDim2.new(0, small and 160 or 230, 0, small and 78 or 112)
	for _, row in teamRows do
		row.Row.Size = UDim2.new(0.92, 0, 0, small and 21 or 30)
	end
	-- Annonce : juste sous le bloc du haut (qui finit à 112 px sur téléphone, 168 px sinon)
	announcePill.Position = UDim2.new(0.5, 0, 0, small and 116 or 174)
	announcePill.Size = UDim2.new(0, math.min(small and 300 or 440, 0.42 * size.X), 0, small and 22 or 30)
	local announceMax = announceLabel:FindFirstChildOfClass("UITextSizeConstraint")
	if announceMax then
		announceMax.MaxTextSize = small and 15 or 22
	end
	-- Vote : à droite des pièces quand l'écran est trop étroit pour le centrer
	local currencyRight = 12 + (small and 150 or 230) + 8
	local voteWidth = math.min(660, size.X - currencyRight - 12)
	local voteLeft = math.max(currencyRight, (size.X - voteWidth) / 2)
	votePanel.AnchorPoint = Vector2.new(0, 1)
	votePanel.Position = UDim2.new(0, voteLeft, 1, small and -10 or -66)
	votePanel.Size = UDim2.new(0, voteWidth, 0, small and 130 or 150)
	bottomCenter.Position = UDim2.new(0.5, 0, 1, small and -50 or -64)
	local dash = screen:FindFirstChild("DashBar")
	if dash and dash:IsA("Frame") then
		dash.Size = small and UDim2.new(0.4, 0, 0, 36) or UDim2.new(0, 460, 0, 44)
		local hint = dash:FindFirstChild("Hint")
		if hint and hint:IsA("GuiObject") then
			hint.Visible = not small
		end
	end
end
HUD.Rescale = rescale
rescale()
if workspace.CurrentCamera then
	workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(rescale)
end

return HUD

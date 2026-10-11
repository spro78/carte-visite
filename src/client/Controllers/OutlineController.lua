--[[
	OutlineController.lua
	Lisibilité immédiate, sans tutoriel (Highlight côté client) :
	  - ma proie est entourée en VERT,
	  - mon prédateur est entouré en ROUGE,
	  - mes coéquipiers n'ont pas de contour,
	  - un porteur d'objectif est entouré en OR pour tout le monde,
	  - une étiquette d'une ligne flotte au-dessus de chaque autre acteur : puce
	    d'équipe (ou PREY / HUNTER) puis pseudo ; l'avatar Roblox reste intact.
	Un acteur caché (attribut "Hidden") perd son contour et son nom, sauf s'il
	est tout proche. Roblox limite le nombre de Highlights affichés (31) :
	on garde les plus proches.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Teams = require(Shared.Teams)

local Theme = require(script.Parent.Parent:WaitForChild("UI"):WaitForChild("Theme"))

local OutlineController = {}

local player = Players.LocalPlayer
local TAG = "HoH_Actor"
local HIGHLIGHT_NAME = "HoH_Outline"
local BADGE_NAME = "HoH_TeamBadge"
local RELATION_WORD = { Prey = "PREY", Predator = "HUNTER" }
local MAX_HIGHLIGHTS = 28
local UPDATE_INTERVAL = 0.2

local tracked: { [Model]: boolean } = {}
local accumulator = 0

local function getHighlight(model: Model): Highlight
	local existing = model:FindFirstChild(HIGHLIGHT_NAME)
	if existing and existing:IsA("Highlight") then
		return existing
	end
	local highlight = Instance.new("Highlight")
	highlight.Name = HIGHLIGHT_NAME
	highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	highlight.FillTransparency = 0.82
	highlight.OutlineTransparency = 0
	highlight.Enabled = false
	highlight.Adornee = model
	highlight.Parent = model
	return highlight
end

-- Étiquette locale au-dessus de la tête (remplace le nom Roblox), sur une ligne
-- (bible visuelle, §7) : puce aux couleurs de l'équipe à gauche (animal, ou
-- PREY / HUNTER pour qui me concerne, bord vert ou rouge), pseudo à droite.
type Tag = { Gui: BillboardGui, Team: TextLabel, Name: TextLabel, Stroke: UIStroke }
local tags: { [Model]: Tag } = {}

local function getTag(model: Model): Tag?
	local existing = tags[model]
	if existing and existing.Gui.Parent then
		return existing
	end
	local head = model:FindFirstChild("Head")
	if not head or not head:IsA("BasePart") then
		return nil
	end
	local gui = Instance.new("BillboardGui")
	gui.Name = BADGE_NAME
	gui.Adornee = head
	-- Taille en studs : l'étiquette rapetisse avec la distance (pas de mur de
	-- pseudos qui se chevauchent au loin), plafonnée de près.
	gui.Size = UDim2.new(8, 0, 1.3, 0)
	gui.StudsOffset = Vector3.new(0, 2.8, 0)
	gui.MaxDistance = Config.Appearance.BadgeMaxDistance
	gui.LightInfluence = 0
	gui.AlwaysOnTop = false
	gui.Enabled = false
	local row = Theme.New("Frame", { Name = "Row", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1 }, gui)
	Theme.New("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Center, VerticalAlignment = Enum.VerticalAlignment.Center, Padding = UDim.new(0.02, 0), SortOrder = Enum.SortOrder.LayoutOrder }, row)
	local team = Theme.Label(row, { Name = "Team", Size = UDim2.fromScale(0.34, 0.84), Text = "", BackgroundTransparency = 0, BackgroundColor3 = Theme.Panel, FontFace = Theme.FaceHeavy, LayoutOrder = 1 })
	Theme.CornerScale(team, 0.5)
	local stroke = Theme.Stroke(team, 0, Theme.White)
	local name = Theme.Title(row, { Name = "PlayerName", Size = UDim2.fromScale(0.62, 1), Text = "", TextXAlignment = Enum.TextXAlignment.Left, LayoutOrder = 2 })
	Theme.MaxText(team, 15)
	Theme.MaxText(name, 26)
	gui.Parent = head
	local tag = { Gui = gui, Team = team, Name = name, Stroke = stroke }
	tags[model] = tag
	return tag
end

local function updateTag(model: Model, team: any, relation: string?, visible: boolean)
	local tag = getTag(model)
	if not tag then
		return
	end
	if not visible then
		tag.Gui.Enabled = false
		return
	end
	tag.Gui.Enabled = true
	local def = Teams.Get(team)
	if def and Config.Appearance.ShowTeamBadge then
		tag.Team.Visible = true
		tag.Team.Text = RELATION_WORD[relation or ""] or def.Display
		tag.Team.BackgroundColor3 = def.Color
		tag.Team.TextColor3 = Theme.TextOn(def.Color)
		tag.Stroke.Thickness = (relation == "Prey" or relation == "Predator") and 3 or 0
		tag.Stroke.Color = relation == "Prey" and Teams.PreyOutlineColor or Teams.PredatorOutlineColor
	else
		tag.Team.Visible = false
	end
	local displayName = model:GetAttribute("DisplayName")
	tag.Name.Text = type(displayName) == "string" and displayName or model.Name
end

local function setNameVisible(model: Model, visible: boolean)
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.DisplayDistanceType = visible and Enum.HumanoidDisplayDistanceType.Viewer or Enum.HumanoidDisplayDistanceType.None
	end
end

local function myPosition(): Vector3?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return root.Position
	end
	return nil
end

local function update()
	local myTeam = player:GetAttribute("Team")
	if type(myTeam) ~= "string" then
		myTeam = nil
	end
	local origin = myPosition()
	local candidates = {}
	for model in tracked do
		if model.Parent == nil then
			tracked[model] = nil
			tags[model] = nil
			continue
		end
		local highlight = getHighlight(model)
		if model == player.Character then
			highlight.Enabled = false
			local ownTag = tags[model]
			if ownTag then
				ownTag.Gui.Enabled = false
			end
			continue
		end
		local team = model:GetAttribute("Team")
		local root = model:FindFirstChild("HumanoidRootPart")
		local distance = math.huge
		if origin and root and root:IsA("BasePart") then
			distance = (root.Position - origin).Magnitude
		end
		local relation = Teams.Relation(myTeam, team)
		local carrier = model:GetAttribute("Carrier") == true
		local hidden = model:GetAttribute("Hidden") == true and not carrier
		local revealed = distance <= Config.Hiding.RevealDistance or relation == "Ally"

		local color: Color3? = nil
		if carrier then
			color = Teams.CarrierOutlineColor
		elseif hidden and not revealed then
			color = nil
		elseif relation == "Prey" then
			color = Teams.PreyOutlineColor
		elseif relation == "Predator" then
			color = Teams.PredatorOutlineColor
		end
		-- Le nom Roblox est remplacé par notre étiquette
		setNameVisible(model, false)
		updateTag(model, team, relation, not hidden or revealed)
		if color then
			table.insert(candidates, { Highlight = highlight, Color = color, Distance = distance, Carrier = carrier })
		else
			highlight.Enabled = false
		end
	end
	-- Les porteurs d'abord, puis les plus proches
	table.sort(candidates, function(a, b)
		if a.Carrier ~= b.Carrier then
			return a.Carrier
		end
		return a.Distance < b.Distance
	end)
	for index, entry in candidates do
		local highlight = entry.Highlight
		if index <= MAX_HIGHLIGHTS then
			highlight.OutlineColor = entry.Color
			highlight.FillColor = entry.Color
			highlight.Enabled = true
		else
			highlight.Enabled = false
		end
	end
end

local function track(model: Instance)
	if model:IsA("Model") then
		tracked[model] = true
	end
end

function OutlineController.Init()
	for _, model in CollectionService:GetTagged(TAG) do
		track(model)
	end
	CollectionService:GetInstanceAddedSignal(TAG):Connect(track)
	CollectionService:GetInstanceRemovedSignal(TAG):Connect(function(model)
		if model:IsA("Model") then
			tracked[model] = nil
			local highlight = model:FindFirstChild(HIGHLIGHT_NAME)
			if highlight then
				highlight:Destroy()
			end
		end
	end)
	player:GetAttributeChangedSignal("Team"):Connect(update)
	RunService.Heartbeat:Connect(function(dt)
		accumulator += dt
		if accumulator >= UPDATE_INTERVAL then
			accumulator = 0
			update()
		end
	end)
end

-- Pour les tests : force une mise à jour immédiate
OutlineController.Update = update

return OutlineController

--[[
	OutlineController.lua
	Lisibilité immédiate, sans tutoriel (Highlight côté client) :
	  - ma proie est entourée en VERT,
	  - mon prédateur est entouré en ROUGE,
	  - mes coéquipiers n'ont pas de contour,
	  - un porteur d'objectif est entouré en OR pour tout le monde,
	  - un petit badge "FOX / CHICKEN / SNAKE" flotte au-dessus de chaque autre
	    acteur (l'avatar Roblox reste intact).
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
local RELATION_SUFFIX = { Prey = " · PREY", Predator = " · HUNTER" }
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

-- Étiquette locale au-dessus de la tête (remplace le nom Roblox) :
--   ligne 1 : équipe en couleur (+ "PREY" / "HUNTER")
--   ligne 2 : pseudo en gros blanc contouré
--   ligne 3 : "Level 6 · 12 wins"
type Tag = { Gui: BillboardGui, Team: TextLabel, Name: TextLabel, Info: TextLabel }
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
	gui.Size = UDim2.new(7, 0, 2.2, 0)
	gui.StudsOffset = Vector3.new(0, 3.2, 0)
	gui.MaxDistance = Config.Appearance.BadgeMaxDistance
	gui.LightInfluence = 0
	gui.AlwaysOnTop = false
	gui.Enabled = false
	local team = Theme.Title(gui, { Name = "Team", Size = UDim2.fromScale(1, 0.26), Text = "", FontFace = Theme.FaceTitle })
	local name = Theme.Title(gui, { Name = "PlayerName", Position = UDim2.fromScale(0, 0.27), Size = UDim2.fromScale(1, 0.44), Text = "", FontFace = Theme.FaceHeavy })
	local info = Theme.Label(gui, { Name = "Info", Position = UDim2.fromScale(0, 0.73), Size = UDim2.fromScale(1, 0.22), Text = "", TextColor3 = Color3.fromRGB(215, 220, 230), TextStrokeTransparency = 0.4 })
	Theme.MaxText(team, 16)
	Theme.MaxText(name, 28)
	Theme.MaxText(info, 14)
	gui.Parent = head
	local tag = { Gui = gui, Team = team, Name = name, Info = info }
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
		tag.Team.Text = def.Display .. (relation and RELATION_SUFFIX[relation] or "")
		tag.Team.TextColor3 = relation == "Prey" and Teams.PreyOutlineColor or relation == "Predator" and Teams.PredatorOutlineColor or def.Color
	else
		tag.Team.Text = ""
	end
	local displayName = model:GetAttribute("DisplayName")
	tag.Name.Text = type(displayName) == "string" and displayName or model.Name
	local level = model:GetAttribute("Level")
	local wins = model:GetAttribute("Wins")
	if type(level) == "number" then
		tag.Info.Text = string.format("Level %d · %d win%s", level, type(wins) == "number" and wins or 0, wins == 1 and "" or "s")
	else
		tag.Info.Text = ""
	end
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

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
local RELATION_SUFFIX = { Prey = "  ▼ PREY", Predator = "  ▲ HUNTER" }
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

-- Badge d'équipe local (BillboardGui) au-dessus de la tête
local function getBadge(model: Model): (BillboardGui?, TextLabel?)
	local head = model:FindFirstChild("Head")
	if not head or not head:IsA("BasePart") then
		return nil, nil
	end
	local existing = head:FindFirstChild(BADGE_NAME)
	if existing and existing:IsA("BillboardGui") then
		local label = existing:FindFirstChild("Label")
		return existing, label and label:IsA("TextLabel") and label or nil
	end
	local gui = Instance.new("BillboardGui")
	gui.Name = BADGE_NAME
	gui.Adornee = head
	gui.Size = UDim2.fromOffset(110, 22)
	gui.StudsOffset = Vector3.new(0, 3.6, 0)
	gui.MaxDistance = Config.Appearance.BadgeMaxDistance
	gui.LightInfluence = 0
	gui.AlwaysOnTop = false
	gui.Enabled = false
	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundColor3 = Theme.Dark
	label.BackgroundTransparency = 0.2
	label.Font = Theme.FontBold
	label.TextScaled = true
	label.TextColor3 = Theme.White
	label.Parent = gui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = label
	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0.12, 0)
	padding.PaddingBottom = UDim.new(0.12, 0)
	padding.Parent = label
	gui.Parent = head
	return gui, label
end

local function updateBadge(model: Model, team: any, relation: string?, visible: boolean)
	if not Config.Appearance.ShowTeamBadge then
		return
	end
	local def = Teams.Get(team)
	local gui, label = getBadge(model)
	if not gui or not label then
		return
	end
	if not def or not visible then
		gui.Enabled = false
		return
	end
	gui.Enabled = true
	label.Text = def.Display .. (relation and RELATION_SUFFIX[relation] or "")
	label.BackgroundColor3 = def.DarkColor
	label.TextColor3 = def.Color:Lerp(Color3.new(1, 1, 1), 0.35)
	if relation == "Prey" then
		label.TextColor3 = Teams.PreyOutlineColor
	elseif relation == "Predator" then
		label.TextColor3 = Teams.PredatorOutlineColor
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
			continue
		end
		local highlight = getHighlight(model)
		if model == player.Character then
			highlight.Enabled = false
			local ownBadge = getBadge(model)
			if ownBadge then
				ownBadge.Enabled = false
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
		setNameVisible(model, not hidden or revealed)
		updateBadge(model, team, relation, not hidden or revealed)
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

--[[
	OutlineController.lua
	Lisibilité immédiate, sans tutoriel (Highlight côté client) :
	  - ma proie est entourée en VERT,
	  - mon prédateur est entouré en ROUGE,
	  - mes coéquipiers n'ont pas de contour,
	  - un porteur d'objectif est entouré en OR pour tout le monde.
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

local OutlineController = {}

local player = Players.LocalPlayer
local TAG = "HoH_Actor"
local HIGHLIGHT_NAME = "HoH_Outline"
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

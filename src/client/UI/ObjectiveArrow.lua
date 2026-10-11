--[[
	ObjectiveArrow.lua
	Flèche discrète vers l'objectif de la map :
	  - cible = attribut "ObjectiveTarget" de mon personnage (ex : ma base quand je
	    porte l'œuf), sinon l'objectif de mon équipe (ReplicatedStorage.HoH_Objectives) ;
	  - cible hors écran : flèche sur le bord de l'écran ;
	  - cible à l'écran : petit losange au-dessus de la cible avec la distance.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Theme = require(script.Parent.Theme)

local ObjectiveArrow = {}

local player = Players.LocalPlayer
local New, Label = Theme.New, Theme.Label

local holder: Frame
local arrow: TextLabel
local marker: Frame
local markerText: TextLabel
local objectives: Instance? = nil

local function getTarget(): Vector3?
	local character = player.Character
	if character then
		local own = character:GetAttribute("ObjectiveTarget")
		if typeof(own) == "Vector3" then
			return own
		end
	end
	local team = player:GetAttribute("Team")
	if type(team) ~= "string" then
		return nil
	end
	objectives = objectives or ReplicatedStorage:FindFirstChild("HoH_Objectives")
	if objectives then
		local value = objectives:GetAttribute(team)
		if typeof(value) == "Vector3" then
			return value
		end
	end
	return nil
end

local function update()
	local target = getTarget()
	local camera = workspace.CurrentCamera
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not target or not camera or not root or not root:IsA("BasePart") then
		arrow.Visible = false
		marker.Visible = false
		return
	end
	local distance = (target - root.Position).Magnitude
	local viewport = camera.ViewportSize
	local point, onScreen = camera:WorldToViewportPoint(target + Vector3.new(0, 4, 0))
	local inset = 40
	if onScreen and point.Z > 0 and point.X > inset and point.X < viewport.X - inset and point.Y > inset and point.Y < viewport.Y - inset then
		arrow.Visible = false
		marker.Visible = distance > 12
		marker.Position = UDim2.fromOffset(point.X, point.Y - 36)
		markerText.Text = string.format("%dm", math.floor(distance))
		return
	end
	marker.Visible = false
	arrow.Visible = true
	-- Direction de la cible dans le plan de l'écran
	local relative = camera.CFrame:PointToObjectSpace(target)
	local dir = Vector2.new(relative.X, -relative.Y)
	if relative.Z > 0 then
		dir = Vector2.new(relative.X, math.abs(relative.Y) + 1)
	end
	if dir.Magnitude < 0.001 then
		dir = Vector2.new(0, 1)
	end
	dir = dir.Unit
	local center = viewport / 2
	local radius = Vector2.new(viewport.X / 2 - 60, viewport.Y / 2 - 70)
	local pos = center + Vector2.new(dir.X * radius.X, dir.Y * radius.Y)
	arrow.Position = UDim2.fromOffset(pos.X, pos.Y)
	arrow.Rotation = math.deg(math.atan2(dir.Y, dir.X)) + 90
end

function ObjectiveArrow.Init(screen: ScreenGui)
	holder = New("Frame", {
		Name = "Objective",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
	}, screen)
	arrow = Label(holder, {
		Name = "Arrow",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.fromOffset(44, 44),
		Text = "▲",
		TextColor3 = Theme.Accent,
		TextStrokeTransparency = 0.2,
		TextTransparency = 0.15,
		Visible = false,
	})
	marker = New("Frame", {
		Name = "Marker",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.fromOffset(70, 40),
		BackgroundTransparency = 1,
		Visible = false,
	}, holder)
	Label(marker, {
		Size = UDim2.fromScale(1, 0.55),
		Text = "◆",
		TextColor3 = Theme.Accent,
		TextStrokeTransparency = 0.3,
	})
	markerText = Label(marker, {
		Position = UDim2.fromScale(0, 0.55),
		Size = UDim2.fromScale(1, 0.45),
		Text = "",
		TextStrokeTransparency = 0.3,
	})
	RunService.RenderStepped:Connect(update)
end

return ObjectiveArrow

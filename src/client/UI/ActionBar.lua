--[[
	ActionBar.lua
	Boutons d'action avec affichage du temps de recharge :
	  - écran tactile : gros boutons autour du bouton de saut (dash gauche/droite,
	    stop, capacité) ;
	  - clavier/manette : indicateurs compacts en bas au centre avec la touche.
	Le contrôleur de mouvement fournit l'état via ActionBar.Init(handlers, provider).
]]

local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Teams = require(Shared.Teams)
local Theme = require(script.Parent.Theme)

local ActionBar = {}

export type CooldownInfo = { Remaining: number, Total: number, Available: boolean }
export type Provider = () -> { [string]: CooldownInfo }
export type Handlers = { [string]: () -> () }

local New, Label = Theme.New, Theme.Label

local ACTIONS = { "DashLeft", "DashRight", "Stop", "Ability" }
local TOUCH_LABELS = { DashLeft = "◀ DASH", DashRight = "DASH ▶", Stop = "STOP", Ability = "ABILITY" }
local ABILITY_SHORT = { FOX = "SPRINT", CHICKEN = "GLIDE", SNAKE = "BITE" }

type Slot = { Root: GuiObject, Fill: Frame, Text: TextLabel, Key: TextLabel?, Main: TextLabel, Stroke: UIStroke }

local touchSlots: { [string]: Slot } = {}
local keySlots: { [string]: Slot } = {}
local touchContainer: Frame
local keyContainer: Frame
local usingTouch = false

local function keyName(action: string): string
	local keys = Config.Controls[action]
	if not keys then
		return ""
	end
	local gamepad = UserInputService.GamepadEnabled and not UserInputService.KeyboardEnabled
	for _, key in keys do
		local isGamepad = string.find(key.Name, "Button") ~= nil
		if isGamepad == gamepad then
			return (string.gsub(key.Name, "Button", ""))
		end
	end
	return keys[1].Name
end

local function makeSlot(parent: Instance, action: string, isTouch: boolean, handler: () -> ()): Slot
	local root: GuiObject
	if isTouch then
		root = New("TextButton", {
			Name = action,
			Text = "",
			AutoButtonColor = true,
			BackgroundColor3 = Theme.Panel,
			BackgroundTransparency = 0.15,
			AnchorPoint = Vector2.new(0.5, 0.5),
		}, parent)
		Theme.CornerScale(root, 0.5)
		;(root :: TextButton).Activated:Connect(handler)
	else
		root = New("Frame", {
			Name = action,
			BackgroundColor3 = Theme.Panel,
			BackgroundTransparency = 0.1,
			Size = UDim2.fromScale(0.23, 1),
		}, parent)
		Theme.Corner(root, 10)
	end
	New("UIAspectRatioConstraint", { AspectRatio = 1 }, root)
	local stroke = Theme.Stroke(root, 3, Theme.Dark)
	local fill: Frame = New("Frame", {
		Name = "Cooldown",
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.45,
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.fromScale(1, 0),
		ZIndex = 2,
	}, root)
	Theme.CornerScale(fill, isTouch and 0.5 or 0.15)
	local main = Label(root, {
		Name = "Main",
		Size = UDim2.fromScale(0.86, isTouch and 0.4 or 0.36),
		Position = UDim2.fromScale(0.07, isTouch and 0.3 or 0.12),
		Text = isTouch and TOUCH_LABELS[action] or TOUCH_LABELS[action],
		ZIndex = 3,
		TextStrokeTransparency = 0.4,
	})
	local text = Label(root, {
		Name = "Seconds",
		Size = UDim2.fromScale(0.6, 0.36),
		Position = UDim2.fromScale(0.2, isTouch and 0.32 or 0.3),
		Text = "",
		ZIndex = 4,
		TextStrokeTransparency = 0,
		Visible = false,
	})
	local key: TextLabel? = nil
	if not isTouch then
		key = Label(root, {
			Name = "Key",
			Size = UDim2.fromScale(0.86, 0.32),
			Position = UDim2.fromScale(0.07, 0.6),
			Text = keyName(action),
			TextColor3 = Theme.Accent,
			ZIndex = 3,
		})
	end
	return { Root = root, Fill = fill, Text = text, Key = key, Main = main, Stroke = stroke }
end

local function placeTouch()
	-- Coordonnées relatives au conteneur (carré en bas à droite, le bouton de saut
	-- de Roblox occupe le coin inférieur droit).
	local layout = {
		Ability = { 0.76, 0.3, 0.32 },
		Stop = { 0.44, 0.38, 0.2 },
		DashLeft = { 0.18, 0.78, 0.24 },
		DashRight = { 0.46, 0.8, 0.24 },
	}
	for action, slot in touchSlots do
		local spec = layout[action]
		slot.Root.Position = UDim2.fromScale(spec[1], spec[2])
		slot.Root.Size = UDim2.fromScale(spec[3], spec[3])
	end
end

local function refreshMode()
	usingTouch = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
	local last = UserInputService:GetLastInputType()
	if last == Enum.UserInputType.Touch then
		usingTouch = true
	elseif last == Enum.UserInputType.Keyboard or last == Enum.UserInputType.MouseButton1 or string.find(last.Name, "Gamepad") then
		usingTouch = false
	end
	touchContainer.Visible = usingTouch
	keyContainer.Visible = not usingTouch
	for action, slot in keySlots do
		if slot.Key then
			slot.Key.Text = keyName(action)
		end
	end
end

local function setSlot(slot: Slot, info: CooldownInfo?)
	if not info or not info.Available then
		slot.Root.Visible = false
		return
	end
	slot.Root.Visible = true
	local remaining = math.max(0, info.Remaining)
	if remaining > 0.05 and info.Total > 0 then
		slot.Fill.Size = UDim2.fromScale(1, math.clamp(remaining / info.Total, 0, 1))
		slot.Text.Visible = true
		slot.Text.Text = remaining >= 1 and tostring(math.ceil(remaining)) or string.format("%.1f", remaining)
		slot.Main.TextTransparency = 0.6
		slot.Stroke.Color = Theme.Dark
	else
		slot.Fill.Size = UDim2.fromScale(1, 0)
		slot.Text.Visible = false
		slot.Main.TextTransparency = 0
		slot.Stroke.Color = Theme.White
	end
end

-- Met à jour le bouton de capacité selon l'animal
function ActionBar.SetTeam(teamId: string?)
	local def = Teams.Get(teamId)
	for _, slots in { touchSlots, keySlots } do
		local slot = slots.Ability
		if slot then
			if def then
				slot.Root.BackgroundColor3 = def.Color
				slot.Main.Text = ABILITY_SHORT[def.Id] or "ABILITY"
				slot.Main.TextColor3 = Theme.Dark
				slot.Main.TextStrokeTransparency = 1
			else
				slot.Root.BackgroundColor3 = Theme.Panel
				slot.Main.Text = "ABILITY"
				slot.Main.TextColor3 = Theme.White
			end
		end
	end
end

function ActionBar.Init(screen: ScreenGui, handlers: Handlers, provider: Provider)
	touchContainer = New("Frame", {
		Name = "TouchActions",
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -6, 1, -6),
		Size = UDim2.fromScale(0.62, 0.62),
		BackgroundTransparency = 1,
		Visible = false,
	}, screen)
	New("UIAspectRatioConstraint", { AspectRatio = 1, DominantAxis = Enum.DominantAxis.Height }, touchContainer)
	New("UISizeConstraint", { MaxSize = Vector2.new(360, 360) }, touchContainer)

	keyContainer = New("Frame", {
		Name = "KeyActions",
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -12, 1, -12),
		Size = UDim2.fromScale(0.3, 0.1),
		BackgroundTransparency = 1,
		Visible = false,
	}, screen)
	New("UISizeConstraint", { MaxSize = Vector2.new(330, 76), MinSize = Vector2.new(200, 50) }, keyContainer)
	New("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		Padding = UDim.new(0.025, 0),
		HorizontalAlignment = Enum.HorizontalAlignment.Right,
		VerticalAlignment = Enum.VerticalAlignment.Bottom,
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, keyContainer)

	for index, action in ACTIONS do
		local handler = handlers[action] or function() end
		touchSlots[action] = makeSlot(touchContainer, action, true, handler)
		local keySlot = makeSlot(keyContainer, action, false, handler)
		keySlot.Root.LayoutOrder = index
		keySlots[action] = keySlot
	end
	placeTouch()
	refreshMode()
	UserInputService.LastInputTypeChanged:Connect(refreshMode)

	Players.LocalPlayer:GetAttributeChangedSignal("Team"):Connect(function()
		ActionBar.SetTeam(Players.LocalPlayer:GetAttribute("Team"))
	end)
	ActionBar.SetTeam(Players.LocalPlayer:GetAttribute("Team"))

	RunService.RenderStepped:Connect(function()
		local info = provider()
		local slots = usingTouch and touchSlots or keySlots
		for _, action in ACTIONS do
			setSlot(slots[action], info[action])
		end
	end)
end

return ActionBar

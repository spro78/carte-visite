--[[
	ActionBar.lua
	Bas de l'écran, d'après la référence :
	  - carte "ABILITY" (capacité de l'animal) avec barre de recharge ;
	  - sous les cartes : "Q / E · DASH" et une longue barre de recharge du dash
	    ("Dash ready" / "Move, then dash left or right") ;
	  - sur écran tactile : gros boutons ronds autour du bouton de saut
	    (dash gauche/droite, stop, capacité) avec affichage de la recharge.
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

local New, Label, Title = Theme.New, Theme.Label, Theme.Title

local TOUCH = { "DashLeft", "DashRight", "Stop", "Ability" }
local TOUCH_LABELS = { DashLeft = "◀ DASH", DashRight = "DASH ▶", Stop = "STOP", Ability = "ABILITY" }

type TouchSlot = { Root: TextButton, Fill: Frame, Seconds: TextLabel, Main: TextLabel }
local touchSlots: { [string]: TouchSlot } = {}
local touchContainer: Frame
local abilityCard: Frame
local abilityName: TextLabel
local abilityStatus: TextLabel
local abilityFill: Frame
local abilityIcon: Frame
local abilityKey: TextLabel
local dashArea: Frame
local dashFill: Frame
local dashLeft: TextLabel
local dashTitle: TextLabel
local usingTouch = false

local function keyText(action: string): string
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

local function makeTouch(parent: Instance, action: string, handler: () -> ()): TouchSlot
	local root: TextButton = New("TextButton", {
		Name = action,
		Text = "",
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = Theme.Panel,
		BackgroundTransparency = 0.15,
		AutoButtonColor = true,
	}, parent)
	Theme.CornerScale(root, 0.5)
	Theme.Stroke(root, 3, Theme.Outline)
	New("UIAspectRatioConstraint", { AspectRatio = 1 }, root)
	local fill: Frame = New("Frame", { AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.fromScale(1, 0), BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0.45, ZIndex = 2 }, root)
	Theme.CornerScale(fill, 0.5)
	local main = Title(root, { Size = UDim2.fromScale(0.84, 0.36), Position = UDim2.fromScale(0.08, 0.32), Text = TOUCH_LABELS[action], FontFace = Theme.FaceHeavy, ZIndex = 3 })
	local seconds = Title(root, { Size = UDim2.fromScale(0.6, 0.36), Position = UDim2.fromScale(0.2, 0.32), Text = "", Visible = false, ZIndex = 4 })
	root.Activated:Connect(handler)
	return { Root = root, Fill = fill, Seconds = seconds, Main = main }
end

local function placeTouch()
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
	dashTitle.Text = usingTouch and "DASH" or (keyText("DashLeft") .. " / " .. keyText("DashRight") .. " · DASH")
	abilityKey.Text = usingTouch and "" or keyText("Ability")
end

function ActionBar.SetTeam(teamId: string?)
	local def = Teams.Get(teamId)
	local touch = touchSlots.Ability
	if def then
		local cfg = Config.Abilities[def.Id]
		abilityCard.Visible = true
		abilityName.Text = cfg and cfg.Name or "Ability"
		abilityIcon.BackgroundColor3 = def.Color
		if touch then
			touch.Root.BackgroundColor3 = def.Color
			touch.Main.Text = string.upper(cfg and cfg.Name or "ABILITY")
		end
	else
		abilityCard.Visible = false
		if touch then
			touch.Root.BackgroundColor3 = Theme.Panel
			touch.Main.Text = "ABILITY"
		end
	end
end

local function setTouch(slot: TouchSlot, info: CooldownInfo?)
	if not info or not info.Available then
		slot.Root.Visible = false
		return
	end
	slot.Root.Visible = true
	local remaining = math.max(0, info.Remaining)
	if remaining > 0.05 and info.Total > 0 then
		slot.Fill.Size = UDim2.fromScale(1, math.clamp(remaining / info.Total, 0, 1))
		slot.Seconds.Visible = true
		slot.Seconds.Text = remaining >= 1 and tostring(math.ceil(remaining)) or string.format("%.1f", remaining)
		slot.Main.TextTransparency = 0.7
	else
		slot.Fill.Size = UDim2.fromScale(1, 0)
		slot.Seconds.Visible = false
		slot.Main.TextTransparency = 0
	end
end

function ActionBar.Init(screen: ScreenGui, bottomRow: Frame, handlers: Handlers, provider: Provider)
	-- Carte "ABILITY" (première carte de la rangée du bas)
	abilityCard = New("Frame", {
		Name = "AbilityCard",
		Size = UDim2.new(0, 190, 0, 70),
		BackgroundColor3 = Theme.Panel,
		BackgroundTransparency = 0.1,
		LayoutOrder = 0,
		Visible = false,
	}, bottomRow)
	Theme.Corner(abilityCard, 8)
	Theme.Stroke(abilityCard, 2, Theme.Outline)
	abilityIcon = New("Frame", { AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 8, 0.5, -3), Size = UDim2.new(0, 46, 0, 46), BackgroundColor3 = Theme.Gold }, abilityCard)
	Theme.CornerScale(abilityIcon, 0.5)
	Theme.Stroke(abilityIcon, 2, Theme.Outline)
	abilityKey = Title(abilityIcon, { Size = UDim2.fromScale(0.6, 0.6), Position = UDim2.fromScale(0.2, 0.2), Text = "R", FontFace = Theme.FaceHeavy })
	Label(abilityCard, { Position = UDim2.new(0, 62, 0, 6), Size = UDim2.new(1, -70, 0, 12), Text = "ABILITY", TextColor3 = Theme.Muted, TextXAlignment = Enum.TextXAlignment.Left })
	abilityName = Label(abilityCard, { Position = UDim2.new(0, 62, 0, 20), Size = UDim2.new(1, -70, 0, 22), Text = "", FontFace = Theme.FaceHeavy, TextXAlignment = Enum.TextXAlignment.Left })
	abilityStatus = Label(abilityCard, { Position = UDim2.new(0, 62, 0, 44), Size = UDim2.new(1, -70, 0, 12), Text = "READY", TextColor3 = Theme.Good, TextXAlignment = Enum.TextXAlignment.Left })
	local abilityBar: Frame = New("Frame", { AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 8, 1, -4), Size = UDim2.new(1, -16, 0, 3), BackgroundColor3 = Theme.PanelLight, BorderSizePixel = 0 }, abilityCard)
	abilityFill = New("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Theme.Gold, BorderSizePixel = 0 }, abilityBar)

	-- Barre de dash sous les cartes
	dashArea = New("Frame", {
		Name = "DashBar",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -14),
		Size = UDim2.new(0, 640, 0, 44),
		BackgroundTransparency = 1,
	}, screen)
	New("UISizeConstraint", { MaxSize = Vector2.new(640, 44) }, dashArea)
	dashTitle = Title(dashArea, { Size = UDim2.new(1, 0, 0, 18), Text = "Q / E · DASH", FontFace = Theme.FaceHeavy })
	dashLeft = Title(dashArea, { Position = UDim2.new(0, 0, 0, 20), Size = UDim2.new(0.45, 0, 0, 13), Text = "Dash ready", FontFace = Theme.FaceBold, TextXAlignment = Enum.TextXAlignment.Left })
	Title(dashArea, { Name = "Hint", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 20), Size = UDim2.new(0.55, 0, 0, 13), Text = "Move, then dash left or right", FontFace = Theme.FaceBold, TextXAlignment = Enum.TextXAlignment.Right })
	local bar: Frame = New("Frame", { Position = UDim2.new(0, 0, 1, -7), Size = UDim2.new(1, 0, 0, 6), BackgroundColor3 = Theme.Dark, BackgroundTransparency = 0.3 }, dashArea)
	Theme.CornerScale(bar, 0.5)
	Theme.Stroke(bar, 1, Theme.White, 0.5)
	dashFill = New("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Theme.White }, bar)
	Theme.CornerScale(dashFill, 0.5)

	-- Boutons tactiles
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
	for _, action in TOUCH do
		touchSlots[action] = makeTouch(touchContainer, action, handlers[action] or function() end)
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
		for _, action in TOUCH do
			setTouch(touchSlots[action], info[action])
		end
		-- Carte de capacité
		local ability = info.Ability
		if ability and ability.Available then
			local remaining = math.max(0, ability.Remaining)
			if remaining > 0.05 then
				abilityStatus.Text = string.format("%.1fs", remaining)
				abilityStatus.TextColor3 = Theme.Muted
				abilityFill.Size = UDim2.fromScale(1 - math.clamp(remaining / ability.Total, 0, 1), 1)
			else
				abilityStatus.Text = "READY"
				abilityStatus.TextColor3 = Theme.Good
				abilityFill.Size = UDim2.fromScale(1, 1)
			end
		end
		-- Barre de dash
		local dash = info.DashLeft
		if dash and dash.Available then
			local remaining = math.max(0, dash.Remaining)
			dashFill.Size = UDim2.fromScale(1 - math.clamp(remaining / dash.Total, 0, 1), 1)
			dashLeft.Text = remaining > 0.05 and string.format("Recharging... %.1fs", remaining) or "Dash ready"
		end
	end)
end

return ActionBar

--[[
	ActionBar.lua
	Médaillons d'action (kit du jeu, reference/BIBLE_VISUELLE.md §8) :
	  - au clavier ou à la manette : un dock en bas au centre avec les médaillons
	    ronds (DASH, capacité de l'animal, STOP), recharge en remplissage sombre et
	    puce de touche (Q E, R, F) ;
	  - sur écran tactile : les mêmes médaillons, tappables, autour du bouton de saut
	    de Roblox (sans jamais le couvrir) ; le dock du bas s'efface.
	  - CARRY (touche C) n'apparaît que près d'un coéquipier à terre, et devient
	    DROP quand on le porte (RescueController).
	Les boutons ne s'affichent qu'en manche (décompte compris), jamais à terre.
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

export type CooldownInfo = { Remaining: number, Total: number, Available: boolean, Label: string? }
export type Provider = () -> { [string]: CooldownInfo }
export type Handlers = { [string]: () -> () }

local New, Title = Theme.New, Theme.Title

local TOUCH = { "DashLeft", "DashRight", "Stop", "Ability", "Carry" }
local TOUCH_LABELS = { DashLeft = "◀ DASH", DashRight = "DASH ▶", Stop = "STOP", Ability = "ABILITY", Carry = "CARRY" }
-- Dock clavier : un médaillon par action (le dash couvre les deux côtés)
local DOCK = {
	{ Action = "DashLeft", Label = "DASH", Size = 64 },
	{ Action = "Ability", Label = "ABILITY", Size = 80 },
	{ Action = "Stop", Label = "STOP", Size = 54 },
	{ Action = "Carry", Label = "CARRY", Size = 64 },
}

type Medallion = { Root: GuiObject, Circle: GuiObject, Fill: Frame, Seconds: TextLabel, Main: TextLabel, Key: TextLabel? }
local touchSlots: { [string]: Medallion } = {}
local dockSlots: { [string]: Medallion } = {}
local touchContainer: Frame
local usingTouch = false
local modeCallback: ((boolean) -> ())? = nil
local roundActive = false -- décompte ou manche en cours (pas de boutons au lobby ni sur les résultats)

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

-- Médaillon rond : panneau encre à bord crème, remplissage de recharge, texte
local function decorate(circle: GuiObject, label: string): (Frame, TextLabel, TextLabel)
	circle.BackgroundColor3 = Theme.Panel
	circle.BackgroundTransparency = 0.1
	Theme.CornerScale(circle, 0.5)
	Theme.Stroke(circle, 3, Theme.Cream, 0.05)
	New("UIAspectRatioConstraint", { AspectRatio = 1 }, circle)
	local fill: Frame = New("Frame", { Name = "Fill", AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.fromScale(1, 0), BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0.45, ZIndex = 2 }, circle)
	Theme.CornerScale(fill, 0.5)
	local main = Title(circle, { Name = "Main", Size = UDim2.fromScale(0.82, 0.32), Position = UDim2.fromScale(0.09, 0.34), Text = label, ZIndex = 3 })
	local seconds = Title(circle, { Name = "Seconds", Size = UDim2.fromScale(0.6, 0.4), Position = UDim2.fromScale(0.2, 0.3), Text = "", Visible = false, ZIndex = 4 })
	return fill, main, seconds
end

local function makeTouch(parent: Instance, action: string, handler: () -> ()): Medallion
	local root: TextButton = New("TextButton", {
		Name = action,
		Text = "",
		AnchorPoint = Vector2.new(0.5, 0.5),
		AutoButtonColor = true,
	}, parent)
	local fill, main, seconds = decorate(root, TOUCH_LABELS[action])
	root.Activated:Connect(handler)
	return { Root = root, Circle = root, Fill = fill, Seconds = seconds, Main = main, Key = nil }
end

local function makeDock(parent: Instance, spec: { Action: string, Label: string, Size: number }, order: number): Medallion
	local root: Frame = New("Frame", {
		Name = spec.Action == "DashLeft" and "Dash" or spec.Action,
		Size = UDim2.new(0, spec.Size + 8, 0, spec.Size + 8),
		BackgroundTransparency = 1,
		LayoutOrder = order,
	}, parent)
	local circle: Frame = New("Frame", { Name = "Medallion", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, 0), Size = UDim2.new(0, spec.Size, 0, spec.Size) }, root)
	local fill, main, seconds = decorate(circle, spec.Label)
	-- Puce de touche en haut à gauche du médaillon
	local badge: Frame = New("Frame", { Name = "KeyBadge", Position = UDim2.new(0, 0, 0, 0), Size = UDim2.new(0, 26, 0, 22), BackgroundColor3 = Theme.Cream, ZIndex = 5 }, root)
	Theme.CornerScale(badge, 0.5)
	Theme.Stroke(badge, 2, Theme.Outline)
	local key = Theme.Label(badge, { Name = "Key", Size = UDim2.fromScale(0.86, 0.72), Position = UDim2.fromScale(0.07, 0.14), Text = "", TextColor3 = Theme.Dark, FontFace = Theme.FaceHeavy, ZIndex = 6 })
	return { Root = root, Circle = circle, Fill = fill, Seconds = seconds, Main = main, Key = key }
end

-- Bouton de saut de Roblox (module TouchJump du PlayerModule) : 70 px si le
-- plus petit côté de l'écran fait 500 px ou moins, 120 px sinon. Renvoie son
-- centre, en distance depuis le coin bas-droit, et sa taille.
function ActionBar.JumpButtonGeometry(viewport: Vector2): (number, number, number)
	local small = math.min(viewport.X, viewport.Y) <= 500
	local size = small and 70 or 120
	local right = size * 1.5 - 10
	local top = small and (size + 20) or (size * 1.75)
	return right - size / 2, top - size / 2, size
end

-- Nos boutons entourent le saut sans jamais le recouvrir : dashs sur la même
-- ligne à sa gauche, capacité au-dessus, stop au-dessus du dash droit, porter
-- au-dessus du dash gauche.
local function placeTouch()
	local camera = workspace.CurrentCamera
	local viewport = camera and camera.ViewportSize or Vector2.new(1280, 720)
	local jx, jy, j = ActionBar.JumpButtonGeometry(viewport)
	local gap = j * 0.15
	local dash, ability, stop = j * 0.86, j * 0.94, j * 0.72
	local dashRightX = jx + j / 2 + gap + dash / 2
	local upperY = jy + j / 2 + gap + ability / 2
	local layout = {
		DashRight = { dashRightX, jy, dash },
		DashLeft = { dashRightX + dash + gap, jy, dash },
		Ability = { jx, upperY, ability },
		Stop = { dashRightX, upperY, stop },
		Carry = { dashRightX + dash + gap, upperY, ability },
	}
	for action, slot in touchSlots do
		local spec = layout[action]
		slot.Root.Position = UDim2.fromOffset(-spec[1], -spec[2])
		slot.Root.Size = UDim2.fromOffset(spec[3], spec[3])
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
	local dash = dockSlots.DashLeft
	if dash and dash.Key then
		dash.Key.Text = keyText("DashLeft") .. " " .. keyText("DashRight")
	end
	for _, action in { "Ability", "Stop", "Carry" } do
		local slot = dockSlots[action]
		if slot and slot.Key then
			slot.Key.Text = keyText(action)
		end
	end
	if modeCallback then
		modeCallback(usingTouch)
	end
end

function ActionBar.IsTouch(): boolean
	return usingTouch
end

function ActionBar.SetPhase(phase: string)
	roundActive = phase == "Countdown" or phase == "Round"
end

-- Médaillon de capacité aux couleurs de l'équipe, nom de la capacité dedans
function ActionBar.SetTeam(teamId: string?)
	local def = Teams.Get(teamId)
	local cfg = def and Config.Abilities[def.Id]
	local text = string.upper(cfg and cfg.Name or "ABILITY")
	for _, slots in { touchSlots, dockSlots } do
		local slot = slots.Ability
		if slot then
			slot.Circle.BackgroundColor3 = def and def.DarkColor or Theme.Panel
			slot.Main.Text = text
		end
	end
end

local function setSlot(slot: Medallion, info: CooldownInfo?)
	if not info or not info.Available or not roundActive then
		slot.Root.Visible = false
		return
	end
	slot.Root.Visible = true
	if info.Label then
		slot.Main.Text = info.Label
	end
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

-- onModeChanged(usingTouch) : prévient le HUD quand on passe du clavier au tactile
function ActionBar.Init(screen: ScreenGui, bottomRow: Frame, handlers: Handlers, provider: Provider, onModeChanged: ((boolean) -> ())?)
	modeCallback = onModeChanged
	-- Dock clavier (dans la rangée du bas du HUD)
	for order, spec in DOCK do
		dockSlots[spec.Action] = makeDock(bottomRow, spec, order)
	end

	-- Boutons tactiles : cadre de taille nulle ancré dans le coin bas-droit, pour
	-- ne jamais couvrir (ni bloquer) le bouton de saut ou le joystick de Roblox
	touchContainer = New("Frame", {
		Name = "TouchActions",
		Position = UDim2.fromScale(1, 1),
		Size = UDim2.fromOffset(0, 0),
		BackgroundTransparency = 1,
		Visible = false,
	}, screen)
	for _, action in TOUCH do
		touchSlots[action] = makeTouch(touchContainer, action, handlers[action] or function() end)
	end
	placeTouch()
	refreshMode()
	UserInputService.LastInputTypeChanged:Connect(refreshMode)
	local camera = workspace.CurrentCamera
	if camera then
		camera:GetPropertyChangedSignal("ViewportSize"):Connect(placeTouch)
	end

	Players.LocalPlayer:GetAttributeChangedSignal("Team"):Connect(function()
		ActionBar.SetTeam(Players.LocalPlayer:GetAttribute("Team"))
	end)
	ActionBar.SetTeam(Players.LocalPlayer:GetAttribute("Team"))

	RunService.RenderStepped:Connect(function()
		local info = provider()
		for _, action in TOUCH do
			setSlot(touchSlots[action], info[action])
		end
		for _, spec in DOCK do
			setSlot(dockSlots[spec.Action], info[spec.Action])
		end
	end)
end

return ActionBar

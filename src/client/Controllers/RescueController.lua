--[[
	RescueController.lua
	Côté client de la mise à terre et du portage (règle : RescueService) :
	  - repère le coéquipier à terre le plus proche ; à portée, l'action CARRY
	    apparaît (touche C, bouton Y de la manette, médaillon tactile) ; quand on
	    porte quelqu'un, la même action devient DROP ;
	  - marqueur "HELP" au-dessus de chaque coéquipier à terre, visible de loin
	    et à travers le décor, avec le temps restant et la distance ;
	  - pastille d'état du HUD, par priorité : à terre (chrono), porté, en train
	    de porter, coéquipier à portée (consigne), protégé dans la zone sûre,
	    coéquipier à terre ailleurs (consigne de secours).
	Le client n'envoie qu'une intention (RequestCarry) : le serveur choisit la
	cible et vérifie tout.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ContextActionService = game:GetService("ContextActionService")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Remotes = require(Shared.Remotes)
local Teams = require(Shared.Teams)
local Lang = require(Shared.Lang)

local UI = script.Parent.Parent:WaitForChild("UI")
local Theme = require(UI:WaitForChild("Theme"))
local ActionBar = require(UI:WaitForChild("ActionBar"))

local RescueController = {}

local player = Players.LocalPlayer
local TAG = "HoH_Actor"
local MARKER_NAME = "HoH_Help"
local UPDATE_INTERVAL = 0.15

local hud: any = nil
local RequestCarry: RemoteEvent
local accumulator = 0
local nearest: Model? = nil -- coéquipier à terre à portée de ramassage
local markers: { [Model]: { Gui: BillboardGui, Text: TextLabel, Stroke: UIStroke } } = {}

local function serverNow(): number
	return workspace:GetServerTimeNow()
end

local function rootOf(model: Model?): BasePart?
	local root = model and model:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return root
	end
	return nil
end

local function displayName(model: Model): string
	local name = model:GetAttribute("DisplayName")
	return type(name) == "string" and name or model.Name
end

local function secondsLeft(model: Model): number?
	local untilTime = model:GetAttribute("DownedUntil")
	if type(untilTime) == "number" then
		return math.max(0, untilTime - serverNow())
	end
	return nil
end

-- Touche du clavier ou bouton de manette, pour la consigne
local function carryKey(): string
	local gamepad = UserInputService.GamepadEnabled and not UserInputService.KeyboardEnabled
	for _, key in Config.Controls.Carry do
		local isGamepad = string.find(key.Name, "Button") ~= nil
		if isGamepad == gamepad then
			return (string.gsub(key.Name, "Button", ""))
		end
	end
	return Config.Controls.Carry[1].Name
end

local function carryHint(name: string): string
	if ActionBar.IsTouch() then
		return Lang.F("Tap CARRY to save %s", name)
	end
	return Lang.F("Press %s to carry %s", carryKey(), name)
end

-- ---------------------------------------------------------------------------
-- Marqueurs HELP au-dessus des coéquipiers à terre
-- ---------------------------------------------------------------------------
local function getMarker(model: Model)
	local existing = markers[model]
	if existing and existing.Gui.Parent then
		return existing
	end
	-- Accroché à la tête (couchée au sol), décalé vers le haut de l'écran
	local head = model:FindFirstChild("Head")
	local anchor = (head and head:IsA("BasePart")) and head or rootOf(model)
	if not anchor then
		return nil
	end
	local gui = Instance.new("BillboardGui")
	gui.Name = MARKER_NAME
	gui.Adornee = anchor
	gui.Size = UDim2.fromOffset(96, 34)
	gui.StudsOffset = Vector3.new(0, 5, 0) -- au-dessus de l'étiquette du nom (2,8 studs)
	gui.AlwaysOnTop = true
	gui.MaxDistance = 600
	gui.LightInfluence = 0
	local pill = Theme.New("Frame", { Name = "Pill", Size = UDim2.fromScale(1, 1), BackgroundColor3 = Theme.Panel, BackgroundTransparency = 0.1 }, gui)
	Theme.CornerScale(pill, 0.5)
	local stroke = Theme.Stroke(pill, 3, Theme.Bad)
	local text = Theme.Title(pill, { Name = "Text", Size = UDim2.new(1, -12, 1, -8), Position = UDim2.fromOffset(6, 4), Text = Lang.T("HELP!"), RichText = true })
	Theme.MaxText(text, 18)
	gui.Parent = anchor
	local marker = { Gui = gui, Text = text, Stroke = stroke }
	markers[model] = marker
	return marker
end

local function hideMarker(model: Model)
	local marker = markers[model]
	if marker then
		marker.Gui.Enabled = false
	end
end

-- ---------------------------------------------------------------------------
-- État local et consignes
-- ---------------------------------------------------------------------------
local function update()
	local character = player.Character
	local myTeam = player:GetAttribute("Team")
	local myRoot = rootOf(character)
	local def = Teams.Get(myTeam)
	nearest = nil
	if not character or not myRoot or not def then
		for model in markers do
			hideMarker(model)
		end
		if hud then
			hud.SetStatus(nil)
		end
		return
	end
	local me = myRoot.Position
	local downed = character:GetAttribute("Downed") == true
	local carrying = character:GetAttribute("Carrying")
	local canPick = not downed and carrying == nil and character:GetAttribute("Carrier") ~= true

	-- Coéquipiers à terre : marqueurs, plus proche à portée, plus proche tout court
	local closest: Model?, closestDistance = nil, math.huge
	local nearestDistance = Config.Rescue.PickupRange
	for _, model in CollectionService:GetTagged(TAG) do
		if not model:IsA("Model") or model == character then
			continue
		end
		local root = rootOf(model)
		local isMate = model:GetAttribute("Team") == myTeam
		local isDown = model:GetAttribute("Downed") == true
		local carried = model:GetAttribute("CarriedBy") ~= nil
		if not root or not isMate or not isDown or carried then
			hideMarker(model)
			continue
		end
		local distance = (root.Position - me).Magnitude
		local marker = getMarker(model)
		if marker then
			marker.Gui.Enabled = true
			local left = secondsLeft(model)
			marker.Text.Text = Lang.T("HELP!") .. " " .. string.format("%s<font color=\"%s\">· %dm</font>", left and string.format("%ds ", math.ceil(left)) or "", Theme.Hex(Theme.Cream), math.floor(distance))
			marker.Stroke.Color = def.Color
		end
		if distance < closestDistance then
			closest, closestDistance = model, distance
		end
		if canPick and distance <= nearestDistance then
			nearest, nearestDistance = model, distance
		end
	end
	for model in markers do
		if model.Parent == nil then
			markers[model] = nil
		end
	end

	if not hud then
		return
	end
	-- Pastille d'état, par priorité
	if downed then
		local carrier = character:GetAttribute("CarriedBy")
		if type(carrier) == "string" then
			hud.SetStatus(Lang.F("CARRIED HOME by %s · hold on!", carrier), def.Color, nil)
		else
			local left = secondsLeft(character) or 0
			hud.SetStatus(Lang.F("YOU'RE DOWN · %ds · a teammate can carry you home", math.ceil(left)), Theme.Bad, left / Config.Rescue.BleedOutSeconds)
		end
	elseif type(carrying) == "string" then
		hud.SetStatus(Lang.F("CARRYING %s · run to your base!", carrying), def.Color, nil)
	elseif nearest then
		hud.SetStatus(carryHint(displayName(nearest :: Model)), Theme.Mint, nil)
	elseif character:GetAttribute("SafeZone") == true then
		hud.SetStatus(Lang.T("SAFE ZONE · nobody can catch you here"), Theme.Mint, nil)
	elseif closest then
		hud.SetStatus(Lang.F("%s is down · %dm · carry them home", displayName(closest), math.floor(closestDistance)), def.Color, nil)
	else
		hud.SetStatus(nil)
	end
end

-- ---------------------------------------------------------------------------
-- API
-- ---------------------------------------------------------------------------
-- Infos pour la barre d'actions (médaillon CARRY / DROP)
function RescueController.GetActionInfo(): { Remaining: number, Total: number, Available: boolean, Label: string? }
	local character = player.Character
	local carrying = character and character:GetAttribute("Carrying")
	if type(carrying) == "string" then
		return { Remaining = 0, Total = 1, Available = true, Label = Lang.T("DROP") }
	end
	return { Remaining = 0, Total = 1, Available = nearest ~= nil, Label = Lang.T("CARRY") }
end

-- Intention : porter le coéquipier à portée, ou lâcher celui qu'on porte
function RescueController.Carry()
	local character = player.Character
	if not character or character:GetAttribute("Downed") == true then
		return
	end
	if character:GetAttribute("Carrying") == nil and nearest == nil then
		return
	end
	RequestCarry:FireServer()
end

function RescueController.Init(hudModule: any)
	hud = hudModule
	RequestCarry = Remotes.Get("RequestCarry")
	ContextActionService:BindAction("HoH_Carry", function(_, inputState)
		if inputState == Enum.UserInputState.Begin then
			RescueController.Carry()
		end
		return Enum.ContextActionResult.Sink
	end, false, table.unpack(Config.Controls.Carry))
	RunService.Heartbeat:Connect(function(dt)
		accumulator += dt
		if accumulator >= UPDATE_INTERVAL then
			accumulator = 0
			update()
		end
	end)
end

-- Pour les tests : mise à jour immédiate
RescueController.Update = update

return RescueController

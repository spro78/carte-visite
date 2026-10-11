--[[
	Inventory.lua
	Barre d'objets (consommables) pendant la manche : 4 cases avec le stock et
	la touche (1-4) ; cases tactiles sur mobile. Le serveur valide l'usage.
]]

local ContextActionService = game:GetService("ContextActionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Remotes = require(Shared.Remotes)
local Theme = require(script.Parent.Theme)

local Inventory = {}

local New, Label = Theme.New, Theme.Label

local bar: Frame
local slots: { [string]: { Frame: TextButton, Count: TextLabel } } = {}
local counts: { [string]: number } = {}
local SHORT = { Shield = "SHIELD", Decoy = "DECOY", SpeedBoost = "BOOST", Trap = "TRAP" }

local function use(itemId: string)
	if (counts[itemId] or 0) > 0 then
		Remotes.Get("UseConsumable"):FireServer(itemId)
	end
end

local function refresh()
	local any = false
	for itemId, slot in slots do
		local n = counts[itemId] or 0
		slot.Count.Text = "x" .. n
		slot.Frame.BackgroundTransparency = n > 0 and 0.1 or 0.55
		if n > 0 then
			any = true
		end
	end
	bar:SetAttribute("HasItems", any)
end

function Inventory.SetCounts(data: { [string]: number }?)
	counts = data or {}
	refresh()
end

function Inventory.SetVisible(visible: boolean)
	bar.Visible = visible
end

function Inventory.Init(screen: ScreenGui)
	bar = New("Frame", {
		Name = "Inventory",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 10, 1, -10),
		Size = UDim2.fromScale(0.26, 0.085),
		BackgroundTransparency = 1,
		Visible = false,
	}, screen)
	New("UISizeConstraint", { MaxSize = Vector2.new(300, 70), MinSize = Vector2.new(180, 44) }, bar)
	New("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0.03, 0), SortOrder = Enum.SortOrder.LayoutOrder }, bar)
	for index, itemId in Config.Shop.ConsumableOrder do
		local key = Config.Controls.Consumables[index]
		local button: TextButton = New("TextButton", {
			Name = itemId,
			Size = UDim2.fromScale(0.225, 1),
			BackgroundColor3 = Theme.Panel,
			Text = "",
			LayoutOrder = index,
		}, bar)
		Theme.Corner(button, 8)
		Theme.Stroke(button, 2, Theme.White)
		Label(button, { Size = UDim2.fromScale(0.9, 0.36), Position = UDim2.fromScale(0.05, 0.08), Text = SHORT[itemId] or itemId })
		local count = Label(button, { Size = UDim2.fromScale(0.9, 0.3), Position = UDim2.fromScale(0.05, 0.46), Text = "x0", TextColor3 = Theme.Accent })
		local keyText = ({ One = "1", Two = "2", Three = "3", Four = "4" })[key and key.Name or ""] or ""
		Label(button, { Size = UDim2.fromScale(0.3, 0.22), Position = UDim2.fromScale(0.68, 0.76), Text = keyText, TextColor3 = Color3.fromRGB(150, 155, 165) })
		button.Activated:Connect(function()
			use(itemId)
		end)
		slots[itemId] = { Frame = button, Count = count }
		if key then
			ContextActionService:BindAction("HoH_Item_" .. itemId, function(_, state)
				if state == Enum.UserInputState.Begin and bar.Visible then
					use(itemId)
				end
				return Enum.ContextActionResult.Pass
			end, false, key)
		end
	end
	refresh()
end

return Inventory

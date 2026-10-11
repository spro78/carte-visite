--[[
	Inventory.lua
	Cartes d'objets (consommables) dans la rangée du bas, comme les cartes
	"objet équipé" de la référence : nom, stock, touche (1-4). Une carte n'est
	affichée que si le joueur possède l'objet. Touchables sur mobile.
	Le serveur valide chaque utilisation.
]]

local ContextActionService = game:GetService("ContextActionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Remotes = require(Shared.Remotes)
local Theme = require(script.Parent.Theme)

local Inventory = {}

local New, Label, Title = Theme.New, Theme.Label, Theme.Title

local cards: { [string]: { Card: TextButton, Count: TextLabel } } = {}
local counts: { [string]: number } = {}
local visible = false
local ICON_COLORS = {
	Shield = Color3.fromRGB(120, 200, 255),
	Decoy = Color3.fromRGB(200, 160, 255),
	SpeedBoost = Color3.fromRGB(255, 220, 80),
	Trap = Color3.fromRGB(230, 120, 60),
}

local function use(itemId: string)
	if visible and (counts[itemId] or 0) > 0 then
		Remotes.Get("UseConsumable"):FireServer(itemId)
	end
end

local function refresh()
	for itemId, entry in cards do
		local n = counts[itemId] or 0
		entry.Count.Text = "x" .. n
		entry.Card.Visible = visible and n > 0
	end
end

function Inventory.SetCounts(data: { [string]: number }?)
	counts = data or {}
	refresh()
end

function Inventory.SetVisible(value: boolean)
	visible = value
	refresh()
end

function Inventory.Init(bottomRow: Frame)
	for index, itemId in Config.Shop.ConsumableOrder do
		local def = Config.Shop.Consumables[itemId]
		local key = Config.Controls.Consumables[index]
		local keyText = ({ One = "1", Two = "2", Three = "3", Four = "4" })[key and key.Name or ""] or ""
		local card: TextButton = New("TextButton", {
			Name = itemId,
			Size = UDim2.new(0, 150, 0, 70),
			BackgroundColor3 = Theme.Panel,
			BackgroundTransparency = 0.1,
			Text = "",
			LayoutOrder = index,
			Visible = false,
		}, bottomRow)
		Theme.Corner(card, 8)
		Theme.Stroke(card, 2, Theme.Outline)
		local icon: Frame = New("Frame", { AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 8, 0.5, 0), Size = UDim2.new(0, 40, 0, 40), BackgroundColor3 = ICON_COLORS[itemId] or Theme.Gold }, card)
		Theme.CornerScale(icon, 0.5)
		Theme.Stroke(icon, 2, Theme.Outline)
		Title(icon, { Size = UDim2.fromScale(0.6, 0.6), Position = UDim2.fromScale(0.2, 0.2), Text = keyText, FontFace = Theme.FaceHeavy })
		Label(card, { Position = UDim2.new(0, 54, 0, 8), Size = UDim2.new(1, -60, 0, 12), Text = "ITEM", TextColor3 = Theme.Muted, TextXAlignment = Enum.TextXAlignment.Left })
		Label(card, { Position = UDim2.new(0, 54, 0, 22), Size = UDim2.new(1, -60, 0, 20), Text = def.Name, FontFace = Theme.FaceHeavy, TextXAlignment = Enum.TextXAlignment.Left })
		local count = Label(card, { Position = UDim2.new(0, 54, 0, 46), Size = UDim2.new(1, -60, 0, 14), Text = "x0", TextColor3 = Theme.Gold, TextXAlignment = Enum.TextXAlignment.Left })
		card.Activated:Connect(function()
			use(itemId)
		end)
		cards[itemId] = { Card = card, Count = count }
		if key then
			ContextActionService:BindAction("HoH_Item_" .. itemId, function(_, state)
				if state == Enum.UserInputState.Begin then
					use(itemId)
				end
				return Enum.ContextActionResult.Pass
			end, false, key)
		end
	end
	refresh()
end

return Inventory

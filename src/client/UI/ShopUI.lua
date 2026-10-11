--[[
	ShopUI.lua
	Fenêtre de boutique de cosmétiques : onglets Hats / Trails / Catch FX (+ Passes
	si des Game Passes sont configurés). Chaque carte affiche son prix en pièces. Le client n'envoie que des intentions
	d'achat ou d'équipement ; le serveur valide et renvoie le profil à jour.
	S'ouvre au comptoir du lobby (invite "Open Shop") ou avec le bouton SHOP.
]]

local Players = game:GetService("Players")
local MarketplaceService = game:GetService("MarketplaceService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Remotes = require(Shared.Remotes)
local Theme = require(script.Parent.Theme)

local ShopUI = {}

local New, Label = Theme.New, Theme.Label
local player = Players.LocalPlayer

local window: Frame
local content: ScrollingFrame
local coinsLabel: TextLabel
local tabButtons: { [string]: TextButton } = {}
local currentTab = "Hats"
local profile: { [string]: any } = {}
local openButton: GuiButton? = nil

-- Cosmétiques uniquement : aucun achat ne donne d'avantage en poursuite
local TABS = { "Hats", "Trails", "Catch FX" }
local TAB_CATEGORY = { Hats = "Looks", Trails = "Trails", ["Catch FX"] = "CatchEffects" }
local ORDER_KEY = { Looks = "LookOrder", Trails = "TrailOrder", CatchEffects = "CatchEffectOrder" }
local OWNED_KEY = { Looks = "OwnedLooks", Trails = "OwnedTrails", CatchEffects = "OwnedCatchEffects" }
local EQUIPPED_KEY = { Looks = "EquippedLook", Trails = "EquippedTrail", CatchEffects = "EquippedCatchEffect" }
local DESCRIPTIONS = {
	Looks = "A hat on top of your avatar. Cosmetic only.",
	Trails = "A trail behind you when you run. Cosmetic only.",
	CatchEffects = "Plays when you catch someone. Cosmetic only.",
}

local function hasPasses(): boolean
	for _, def in Config.Monetization.GamePasses do
		if def.Id and def.Id > 0 then
			return true
		end
	end
	return false
end

local function card(parent: Instance, order: number, title: string, description: string, status: string, buttonText: string, buttonEnabled: boolean, onClick: () -> ())
	local frame: Frame = New("Frame", {
		Name = title,
		BackgroundColor3 = Theme.PanelLight,
		BackgroundTransparency = 0.1,
		LayoutOrder = order,
	}, parent)
	Theme.Corner(frame, 10)
	Label(frame, { Size = UDim2.fromScale(0.92, 0.22), Position = UDim2.fromScale(0.04, 0.06), Text = title, TextXAlignment = Enum.TextXAlignment.Left, FontFace = Theme.FaceHeavy })
	Label(frame, { Size = UDim2.fromScale(0.92, 0.3), Position = UDim2.fromScale(0.04, 0.3), Text = description, TextColor3 = Color3.fromRGB(190, 196, 208), TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top, TextWrapped = true })
	Label(frame, { Size = UDim2.fromScale(0.45, 0.2), Position = UDim2.fromScale(0.04, 0.74), Text = status, TextColor3 = Theme.Accent, TextXAlignment = Enum.TextXAlignment.Left })
	local button: TextButton = New("TextButton", {
		Size = UDim2.fromScale(0.44, 0.26),
		Position = UDim2.fromScale(0.52, 0.68),
		BackgroundColor3 = buttonEnabled and Theme.Accent or Theme.Panel,
		Text = buttonText,
		TextColor3 = buttonEnabled and Theme.Dark or Color3.fromRGB(140, 145, 155),
		FontFace = Theme.FaceHeavy,
		TextScaled = true,
		AutoButtonColor = buttonEnabled,
	}, frame)
	Theme.Corner(button, 8)
	New("UIPadding", { PaddingTop = UDim.new(0.18, 0), PaddingBottom = UDim.new(0.18, 0) }, button)
	if buttonEnabled then
		button.Activated:Connect(onClick)
	end
end

local function render()
	for _, child in content:GetChildren() do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end
	coinsLabel.Text = tostring(profile.Coins or 0) .. " coins"
	for name, button in tabButtons do
		button.BackgroundColor3 = name == currentTab and Theme.Good or Theme.PanelLight
		button.TextColor3 = name == currentTab and Theme.Dark or Theme.White
	end
	local coins = profile.Coins or 0
	local purchase = Remotes.Get("ShopPurchase")
	local equip = Remotes.Get("ShopEquip")

	local category = TAB_CATEGORY[currentTab]
	if category then
		local defs = (Config.Shop :: any)[category]
		local order = (Config.Shop :: any)[ORDER_KEY[category]]
		local owned = profile[OWNED_KEY[category]] or {}
		local equipped = profile[EQUIPPED_KEY[category]]
		for index, id in order do
			local def = defs[id]
			local isOwned = owned[id] == true
			local isEquipped = equipped == id
			local text = isEquipped and "EQUIPPED" or (isOwned and "EQUIP" or (def.Price .. " coins"))
			local enabled = (isOwned and not isEquipped) or (not isOwned and coins >= def.Price)
			local status = isOwned and "Owned" or (coins >= def.Price and "" or ("Need " .. (def.Price - coins) .. " more"))
			card(content, index, def.Name, DESCRIPTIONS[category], status, text, enabled, function()
				if isOwned then
					equip:FireServer(category, id)
				else
					purchase:FireServer(category, id)
				end
			end)
		end
	elseif currentTab == "Passes" then
		local index = 0
		for key, def in Config.Monetization.GamePasses do
			if def.Id and def.Id > 0 then
				index += 1
				card(content, index, def.Name, def.Description, "", "GET", true, function()
					MarketplaceService:PromptGamePassPurchase(player, def.Id)
				end)
			end
			local _ = key
		end
		for key, def in Config.Monetization.Products do
			if def.Id and def.Id > 0 then
				index += 1
				card(content, index, def.Coins .. " coins", "Coin pack", "", "BUY", true, function()
					MarketplaceService:PromptProductPurchase(player, def.Id)
				end)
			end
			local _ = key
		end
	end
end

function ShopUI.SetProfile(data: { [string]: any })
	profile = data
	if window and window.Visible then
		render()
	end
end

function ShopUI.Open()
	window.Visible = true
	render()
end

function ShopUI.Close()
	window.Visible = false
end

function ShopUI.Toggle()
	if window.Visible then
		ShopUI.Close()
	else
		ShopUI.Open()
	end
end

-- Le bouton SHOP n'est visible que hors manche
function ShopUI.SetButtonVisible(visible: boolean)
	if openButton then
		openButton.Visible = visible
	end
	if not visible then
		ShopUI.Close()
	end
end

function ShopUI.Init(screen: ScreenGui, pill: GuiButton?)
	openButton = pill
	if pill then
		pill.Activated:Connect(ShopUI.Toggle)
	end
	window = New("Frame", {
		Name = "Shop",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.52),
		Size = UDim2.fromScale(0.72, 0.74),
		BackgroundColor3 = Theme.Panel,
		BackgroundTransparency = 0.05,
		Visible = false,
		ZIndex = 20,
	}, screen)
	Theme.Corner(window, 16)
	Theme.Stroke(window, 5, Theme.Outline)
	New("UISizeConstraint", { MaxSize = Vector2.new(900, 600) }, window)
	Theme.Title(window, { Size = UDim2.fromScale(0.4, 0.1), Position = UDim2.fromScale(0.03, 0.025), Text = "SHOP", TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = Theme.Gold })
	coinsLabel = Label(window, { Size = UDim2.fromScale(0.3, 0.07), Position = UDim2.fromScale(0.52, 0.04), Text = "", TextColor3 = Theme.Coin, TextXAlignment = Enum.TextXAlignment.Right })
	local close: TextButton = New("TextButton", {
		Size = UDim2.fromScale(0.08, 0.1),
		Position = UDim2.fromScale(0.9, 0.02),
		BackgroundColor3 = Theme.Bad,
		Text = "X",
		TextScaled = true,
		FontFace = Theme.FaceHeavy,
		TextColor3 = Theme.White,
	}, window)
	Theme.Corner(close, 8)
	New("UIAspectRatioConstraint", { AspectRatio = 1 }, close)
	close.Activated:Connect(ShopUI.Close)

	local tabs: Frame = New("Frame", { Size = UDim2.fromScale(0.94, 0.09), Position = UDim2.fromScale(0.03, 0.14), BackgroundTransparency = 1 }, window)
	New("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0.015, 0), SortOrder = Enum.SortOrder.LayoutOrder }, tabs)
	local tabList = table.clone(TABS)
	if hasPasses() then
		table.insert(tabList, "Passes")
	end
	for index, name in tabList do
		local button: TextButton = New("TextButton", {
			Name = name,
			Size = UDim2.fromScale(1 / #tabList - 0.015, 1),
			BackgroundColor3 = Theme.Panel,
			Text = string.upper(name),
			TextScaled = true,
			FontFace = Theme.FaceHeavy,
			TextColor3 = Theme.White,
			LayoutOrder = index,
		}, tabs)
		Theme.Corner(button, 8)
		New("UIPadding", { PaddingTop = UDim.new(0.22, 0), PaddingBottom = UDim.new(0.22, 0) }, button)
		button.Activated:Connect(function()
			currentTab = name
			render()
		end)
		tabButtons[name] = button
	end

	content = New("ScrollingFrame", {
		Size = UDim2.fromScale(0.94, 0.7),
		Position = UDim2.fromScale(0.03, 0.27),
		BackgroundTransparency = 1,
		ScrollBarThickness = 6,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
	}, window)
	New("UIGridLayout", {
		CellSize = UDim2.new(0.485, 0, 0, 120),
		CellPadding = UDim2.new(0.02, 0, 0, 10),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, content)

	Remotes.Get("OpenShop").OnClientEvent:Connect(ShopUI.Open)
end

return ShopUI

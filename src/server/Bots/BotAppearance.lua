--[[
	BotAppearance.lua
	Apparences variées pour les bots : teinte de peau, gabarit et un accessoire
	simple (casquette, bonnet, lunettes, casque audio...) construit en Parts.
	Les accessoires sont rangés dans un dossier "BotLook" (non teinté par la
	couleur d'équipe, qui ne touche que les membres).
]]

local Players = game:GetService("Players")
local Build = require(script.Parent.Parent.Util.Build)

local BotAppearance = {}

local random = Random.new()

local SKIN = {
	Color3.fromRGB(255, 220, 185), Color3.fromRGB(240, 195, 150), Color3.fromRGB(205, 150, 105),
	Color3.fromRGB(160, 105, 70), Color3.fromRGB(110, 70, 45), Color3.fromRGB(255, 205, 80),
}
local CLOTHES = {
	Color3.fromRGB(40, 90, 200), Color3.fromRGB(200, 40, 60), Color3.fromRGB(30, 30, 35),
	Color3.fromRGB(240, 240, 240), Color3.fromRGB(40, 160, 90), Color3.fromRGB(250, 150, 40),
	Color3.fromRGB(150, 70, 200), Color3.fromRGB(90, 200, 220),
}

local function pick<T>(list: { T }): T
	return list[random:NextInteger(1, #list)]
end

-- Description d'avatar aléatoire
function BotAppearance.CreateDescription(): HumanoidDescription
	local desc = Instance.new("HumanoidDescription")
	local skin = pick(SKIN)
	local shirt = pick(CLOTHES)
	local pants = pick(CLOTHES)
	desc.HeadColor = skin
	desc.LeftArmColor = skin
	desc.RightArmColor = skin
	desc.TorsoColor = shirt
	desc.LeftLegColor = pants
	desc.RightLegColor = pants
	desc.HeightScale = random:NextNumber(0.92, 1.05)
	desc.WidthScale = random:NextNumber(0.85, 1)
	desc.DepthScale = random:NextNumber(0.9, 1)
	desc.HeadScale = random:NextNumber(0.95, 1.1)
	return desc
end

local function attach(character: Model, head: BasePart, folder: Folder, props: { [string]: any }, offset: CFrame)
	local merged = table.clone(props)
	merged.CFrame = head.CFrame * offset
	merged.CastShadow = false
	local part = Build.Part(merged)
	Build.Weld(head, part)
	part.Parent = folder
end

local LOOKS: { (Model, BasePart, Folder) -> () } = {
	-- Casquette
	function(character, head, folder)
		local color = pick(CLOTHES)
		local s = head.Size
		attach(character, head, folder, { Name = "Cap", Size = Vector3.new(s.X * 1.05, s.Y * 0.35, s.Z * 1.05), Color = color }, CFrame.new(0, s.Y * 0.45, 0))
		attach(character, head, folder, { Name = "CapBrim", Size = Vector3.new(s.X * 0.9, 0.15, s.Z * 0.6), Color = color }, CFrame.new(0, s.Y * 0.3, -s.Z * 0.65))
	end,
	-- Bonnet
	function(character, head, folder)
		local s = head.Size
		attach(character, head, folder, { Name = "Beanie", Shape = Enum.PartType.Ball, Size = Vector3.new(s.X * 1.15, s.X * 1.15, s.X * 1.15), Color = pick(CLOTHES), Material = Enum.Material.Fabric }, CFrame.new(0, s.Y * 0.32, 0))
	end,
	-- Lunettes de soleil
	function(character, head, folder)
		local s = head.Size
		attach(character, head, folder, { Name = "Glasses", Size = Vector3.new(s.X * 0.9, s.Y * 0.18, 0.15), Color = Color3.fromRGB(20, 20, 25) }, CFrame.new(0, s.Y * 0.1, -s.Z * 0.52))
	end,
	-- Casque audio
	function(character, head, folder)
		local s = head.Size
		local color = pick(CLOTHES)
		attach(character, head, folder, { Name = "Band", Size = Vector3.new(s.X * 1.1, 0.2, 0.3), Color = color }, CFrame.new(0, s.Y * 0.55, 0))
		for _, side in { -1, 1 } do
			attach(character, head, folder, { Name = "EarCup", Shape = Enum.PartType.Ball, Size = Vector3.new(0.6, 0.6, 0.6), Color = color }, CFrame.new(side * s.X * 0.55, 0, 0))
		end
	end,
	-- Bandana
	function(character, head, folder)
		local s = head.Size
		attach(character, head, folder, { Name = "Bandana", Size = Vector3.new(s.X * 1.04, s.Y * 0.2, s.Z * 1.04), Color = pick(CLOTHES), Material = Enum.Material.Fabric }, CFrame.new(0, s.Y * 0.3, 0))
	end,
	-- Rien
	function() end,
}

-- Ajoute un accessoire aléatoire au personnage
function BotAppearance.AddLook(character: Model)
	local head = character:FindFirstChild("Head")
	if not head or not head:IsA("BasePart") then
		return
	end
	local folder = Instance.new("Folder")
	folder.Name = "BotLook"
	folder.Parent = character
	pick(LOOKS)(character, head, folder)
end

-- Crée un personnage de bot complet (sans le placer dans le monde)
function BotAppearance.CreateCharacter(name: string): Model
	local model = Players:CreateHumanoidModelFromDescription(BotAppearance.CreateDescription(), Enum.HumanoidRigType.R15)
	model.Name = name
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.DisplayName = name
		humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.Viewer
		humanoid.BreakJointsOnDeath = false
	end
	BotAppearance.AddLook(model)
	return model
end

return BotAppearance

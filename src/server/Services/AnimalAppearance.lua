--[[
	AnimalAppearance.lua
	Apparence d'animal construite par-dessus l'avatar avec des Parts soudées :
	  FOX     : oreilles pointues + grosse queue à bout blanc
	  CHICKEN : crête rouge + bec + plumes de queue
	  SNAKE   : capuche (cobra) + longue queue en anneaux
	plus une teinte d'équipe et un bandeau autour du torse.

	REMPLACER PAR DE VRAIS MODÈLES : il suffit de réécrire Apply() et Clear()
	en gardant les mêmes signatures (par exemple en clonant un modèle depuis
	ServerStorage et en le soudant au personnage).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Teams = require(Shared.Teams)
local Build = require(script.Parent.Parent.Util.Build)

local AnimalAppearance = {}

local FOLDER_NAME = "AnimalParts"
local ORIGINAL_COLOR_ATTR = "HoH_OriginalColor"
local WHITE = Color3.fromRGB(250, 250, 245)

local function getPart(character: Model, ...: string): BasePart?
	for _, name in { ... } do
		local part = character:FindFirstChild(name)
		if part and part:IsA("BasePart") then
			return part
		end
	end
	return nil
end

local function getFolder(character: Model): Folder
	local folder = character:FindFirstChild(FOLDER_NAME)
	if folder and folder:IsA("Folder") then
		return folder
	end
	local newFolder = Instance.new("Folder")
	newFolder.Name = FOLDER_NAME
	newFolder.Parent = character
	return newFolder
end

-- Attache une Part décorative soudée à "body" (offset relatif à body).
function AnimalAppearance.Attach(character: Model, body: BasePart, name: string, props: { [string]: any }, offset: CFrame): Part
	local merged = table.clone(props)
	merged.Name = name
	merged.CFrame = body.CFrame * offset
	merged.CastShadow = false
	local part = Build.Part(merged)
	Build.Weld(body, part)
	part.Parent = getFolder(character)
	return part
end

-- ---------------------------------------------------------------------------
-- Pièces par animal
-- ---------------------------------------------------------------------------
local function buildFox(character: Model, color: Color3, dark: Color3)
	local head = getPart(character, "Head")
	local torso = getPart(character, "LowerTorso", "Torso")
	if head then
		local s = head.Size
		for _, side in { -1, 1 } do
			AnimalAppearance.Attach(character, head, "Ear", {
				Size = Vector3.new(0.25, s.Y * 0.75, s.Z * 0.45),
				Color = color,
				Shape = Enum.PartType.Block,
			}, CFrame.new(side * s.X * 0.3, s.Y * 0.62, 0) * CFrame.Angles(0, 0, math.rad(-side * 18)))
			AnimalAppearance.Attach(character, head, "EarInner", {
				Size = Vector3.new(0.2, s.Y * 0.45, s.Z * 0.25),
				Color = dark,
			}, CFrame.new(side * s.X * 0.29, s.Y * 0.57, -0.05) * CFrame.Angles(0, 0, math.rad(-side * 18)))
		end
		AnimalAppearance.Attach(character, head, "Snout", {
			Size = Vector3.new(s.X * 0.4, s.Y * 0.3, s.Z * 0.35),
			Color = WHITE,
		}, CFrame.new(0, -s.Y * 0.18, -s.Z * 0.6))
		AnimalAppearance.Attach(character, head, "Nose", {
			Shape = Enum.PartType.Ball,
			Size = Vector3.new(0.3, 0.3, 0.3),
			Color = Color3.fromRGB(30, 25, 25),
		}, CFrame.new(0, -s.Y * 0.1, -s.Z * 0.78))
	end
	if torso then
		local s = torso.Size
		local base = CFrame.new(0, 0, s.Z * 0.5) * CFrame.Angles(math.rad(35), 0, 0)
		AnimalAppearance.Attach(character, torso, "Tail", {
			Shape = Enum.PartType.Ball,
			Size = Vector3.new(1.1, 1.1, 2.6),
			Color = color,
		}, base * CFrame.new(0, 0, 1.1))
		AnimalAppearance.Attach(character, torso, "TailTip", {
			Shape = Enum.PartType.Ball,
			Size = Vector3.new(0.9, 0.9, 1.1),
			Color = WHITE,
		}, base * CFrame.new(0, 0, 2.3))
	end
end

local function buildChicken(character: Model, color: Color3, dark: Color3)
	local head = getPart(character, "Head")
	local torso = getPart(character, "LowerTorso", "Torso")
	local red = Color3.fromRGB(225, 40, 40)
	if head then
		local s = head.Size
		for i = -1, 1 do
			AnimalAppearance.Attach(character, head, "Comb", {
				Shape = Enum.PartType.Ball,
				Size = Vector3.new(0.35, 0.55, 0.55),
				Color = red,
			}, CFrame.new(0, s.Y * 0.6 + (i == 0 and 0.12 or 0), i * 0.3))
		end
		AnimalAppearance.Attach(character, head, "Beak", {
			Size = Vector3.new(s.X * 0.35, s.Y * 0.2, s.Z * 0.45),
			Color = Color3.fromRGB(255, 170, 30),
		}, CFrame.new(0, -s.Y * 0.08, -s.Z * 0.62))
		AnimalAppearance.Attach(character, head, "Wattle", {
			Shape = Enum.PartType.Ball,
			Size = Vector3.new(0.3, 0.45, 0.3),
			Color = red,
		}, CFrame.new(0, -s.Y * 0.38, -s.Z * 0.5))
	end
	if torso then
		local s = torso.Size
		for i, angle in { -25, 0, 25 } do
			AnimalAppearance.Attach(character, torso, "TailFeather" .. i, {
				Size = Vector3.new(0.3, 1.5, 0.5),
				Color = i == 2 and WHITE or dark,
			}, CFrame.new(0, s.Y * 0.4, s.Z * 0.6) * CFrame.Angles(math.rad(-30), 0, math.rad(angle)) * CFrame.new(0, 0.6, 0))
		end
	end
end

local function buildSnake(character: Model, color: Color3, dark: Color3)
	local head = getPart(character, "Head")
	local torso = getPart(character, "LowerTorso", "Torso")
	if head then
		local s = head.Size
		AnimalAppearance.Attach(character, head, "Hood", {
			Size = Vector3.new(s.X * 1.9, s.Y * 1.5, 0.3),
			Color = color,
		}, CFrame.new(0, s.Y * 0.05, s.Z * 0.55))
		AnimalAppearance.Attach(character, head, "HoodPattern", {
			Size = Vector3.new(s.X * 0.9, s.Y * 0.7, 0.32),
			Color = dark,
		}, CFrame.new(0, s.Y * 0.05, s.Z * 0.56))
		AnimalAppearance.Attach(character, head, "Tongue", {
			Size = Vector3.new(0.12, 0.05, 0.6),
			Color = Color3.fromRGB(230, 50, 70),
		}, CFrame.new(0, -s.Y * 0.3, -s.Z * 0.7))
		for _, side in { -1, 1 } do
			AnimalAppearance.Attach(character, head, "Eye", {
				Shape = Enum.PartType.Ball,
				Size = Vector3.new(0.3, 0.3, 0.3),
				Color = Color3.fromRGB(255, 230, 60),
				Material = Enum.Material.Neon,
			}, CFrame.new(side * s.X * 0.22, s.Y * 0.12, -s.Z * 0.5))
		end
	end
	if torso then
		local s = torso.Size
		local cf = CFrame.new(0, -s.Y * 0.2, s.Z * 0.5)
		for i = 1, 5 do
			local radius = 0.75 - i * 0.1
			cf = cf * CFrame.Angles(math.rad(12), math.rad(i % 2 == 0 and 14 or -14), 0) * CFrame.new(0, 0, 0.75)
			AnimalAppearance.Attach(character, torso, "TailSegment" .. i, {
				Shape = Enum.PartType.Ball,
				Size = Vector3.new(radius * 2, radius * 2, 1.2),
				Color = i % 2 == 0 and dark or color,
			}, cf)
		end
	end
end

local BUILDERS = {
	FOX = buildFox,
	CHICKEN = buildChicken,
	SNAKE = buildSnake,
}

-- ---------------------------------------------------------------------------
-- API
-- ---------------------------------------------------------------------------

-- Applique l'apparence d'une équipe (teamId nil = retour à l'avatar normal).
function AnimalAppearance.Apply(character: Model, teamId: string?)
	AnimalAppearance.Clear(character)
	local def = Teams.Get(teamId)
	if not def then
		return
	end

	-- Teinte des membres (on mémorise la couleur d'origine)
	for _, child in character:GetChildren() do
		if child:IsA("BasePart") and child.Name ~= "HumanoidRootPart" then
			if child:GetAttribute(ORIGINAL_COLOR_ATTR) == nil then
				child:SetAttribute(ORIGINAL_COLOR_ATTR, child.Color)
			end
			child.Color = def.Color
		end
	end

	-- Bandeau de couleur autour du torse : lisible même avec des vêtements
	local torso = getPart(character, "UpperTorso", "Torso")
	if torso then
		local s = torso.Size
		AnimalAppearance.Attach(character, torso, "TeamBand", {
			Size = Vector3.new(s.X + 0.25, 0.45, s.Z + 0.25),
			Color = def.DarkColor,
		}, CFrame.new(0, -s.Y * 0.3, 0))
	end

	local builder = BUILDERS[def.Id]
	if builder then
		builder(character, def.Color, def.DarkColor)
	end
	character:SetAttribute("Animal", def.Id)
end

-- Retire l'apparence et rétablit les couleurs d'origine.
function AnimalAppearance.Clear(character: Model)
	local folder = character:FindFirstChild(FOLDER_NAME)
	if folder then
		folder:Destroy()
	end
	for _, child in character:GetChildren() do
		if child:IsA("BasePart") then
			local original = child:GetAttribute(ORIGINAL_COLOR_ATTR)
			if typeof(original) == "Color3" then
				child.Color = original
			end
		end
	end
	character:SetAttribute("Animal", nil)
end

return AnimalAppearance

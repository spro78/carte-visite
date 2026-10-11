--[[
	AnimalAppearance.lua
	Apparence d'animal par-dessus l'avatar. Phase 1 : teinte d'équipe + bandeau.
	Phase 2 : oreilles/queue (renard), crête/bec (poule), capuche/queue (vipère).
	Conçu pour être remplacé plus tard par de vrais modèles 3D :
	il suffit de réécrire Apply/Clear en conservant la même signature.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Teams = require(Shared.Teams)
local Build = require(script.Parent.Parent.Util.Build)

local AnimalAppearance = {}

local FOLDER_NAME = "AnimalParts"
local ORIGINAL_COLOR_ATTR = "HoH_OriginalColor"

local function getTorso(character: Model): BasePart?
	return (character:FindFirstChild("UpperTorso") or character:FindFirstChild("Torso")) :: BasePart?
end

-- Attache une Part décorative soudée à une partie du corps.
-- offset est relatif à la partie du corps.
function AnimalAppearance.AttachPart(character: Model, bodyPartName: string, name: string, size: Vector3, offset: CFrame, color: Color3, shape: Enum.PartType?): Part?
	local body = character:FindFirstChild(bodyPartName) :: BasePart?
	if not body then
		return nil
	end
	local folder = character:FindFirstChild(FOLDER_NAME)
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = FOLDER_NAME
		folder.Parent = character
	end
	local part = Build.Part({
		Name = name,
		Size = size,
		Color = color,
		Shape = shape or Enum.PartType.Block,
		CFrame = body.CFrame * offset,
	})
	Build.Weld(body, part)
	part.Parent = folder
	return part
end

-- Applique l'apparence d'une équipe (teamId nil = retour à l'avatar normal).
function AnimalAppearance.Apply(character: Model, teamId: string?)
	AnimalAppearance.Clear(character)
	local def = Teams.Get(teamId)
	if not def then
		return
	end

	-- Teinte des membres (sauvegarde la couleur d'origine pour pouvoir la rétablir)
	for _, child in character:GetChildren() do
		if child:IsA("BasePart") and child.Name ~= "HumanoidRootPart" then
			if child:GetAttribute(ORIGINAL_COLOR_ATTR) == nil then
				child:SetAttribute(ORIGINAL_COLOR_ATTR, child.Color)
			end
			child.Color = def.Color
		end
	end

	-- Bandeau de couleur autour du torse : lisible même avec des vêtements
	local torso = getTorso(character)
	if torso then
		local band = torso.Size
		AnimalAppearance.AttachPart(
			character,
			torso.Name,
			"TeamBand",
			Vector3.new(band.X + 0.3, 0.5, band.Z + 0.3),
			CFrame.new(0, band.Y * 0.25, 0),
			def.Color
		)
	end

	character:SetAttribute("Animal", def.Id)
	-- Phase 2 : parties spécifiques (oreilles, crête, capuche...) ici.
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

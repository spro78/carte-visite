--[[
	Cosmetics.lua
	Apparences achetées en boutique, ajoutées PAR-DESSUS l'avatar Roblox
	(l'avatar n'est jamais modifié) : chapeaux construits en Parts soudées et
	traînées (Trail). Rangées dans le dossier "HoH_Cosmetics" du personnage.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Build = require(script.Parent.Parent.Util.Build)

local Cosmetics = {}

local FOLDER = "HoH_Cosmetics"

local function folderOf(character: Model): Folder
	local existing = character:FindFirstChild(FOLDER)
	if existing and existing:IsA("Folder") then
		return existing
	end
	local f = Instance.new("Folder")
	f.Name = FOLDER
	f.Parent = character
	return f
end

local function attach(head: BasePart, parent: Instance, props: { [string]: any }, offset: CFrame)
	local merged = table.clone(props)
	merged.CFrame = head.CFrame * offset
	merged.CastShadow = false
	merged.Accent = true
	local part = Build.Part(merged)
	Build.Weld(head, part)
	part.Parent = parent
end

local HATS: { [string]: (BasePart, Instance) -> () } = {
	Crown = function(head, parent)
		local s = head.Size
		local gold = Color3.fromRGB(255, 200, 50)
		attach(head, parent, { Name = "CrownBand", Size = Vector3.new(s.X * 0.9, 0.5, s.Z * 0.9), Color = gold, Material = Enum.Material.Metal }, CFrame.new(0, s.Y * 0.6, 0))
		for i = 0, 4 do
			local a = i / 5 * math.pi * 2
			attach(head, parent, { Name = "CrownSpike", Size = Vector3.new(0.3, 0.6, 0.3), Color = gold, Material = Enum.Material.Metal }, CFrame.new(math.cos(a) * s.X * 0.38, s.Y * 0.6 + 0.5, math.sin(a) * s.Z * 0.38))
		end
	end,
	TopHat = function(head, parent)
		local s = head.Size
		local black = Color3.fromRGB(25, 25, 30)
		attach(head, parent, { Name = "Brim", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.15, s.X * 1.3, s.X * 1.3), Color = black }, CFrame.new(0, s.Y * 0.55, 0) * CFrame.Angles(0, 0, math.rad(90)))
		attach(head, parent, { Name = "Crown", Shape = Enum.PartType.Cylinder, Size = Vector3.new(1.4, s.X * 0.8, s.X * 0.8), Color = black }, CFrame.new(0, s.Y * 0.55 + 0.75, 0) * CFrame.Angles(0, 0, math.rad(90)))
		attach(head, parent, { Name = "Ribbon", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.3, s.X * 0.82, s.X * 0.82), Color = Color3.fromRGB(200, 40, 50) }, CFrame.new(0, s.Y * 0.55 + 0.25, 0) * CFrame.Angles(0, 0, math.rad(90)))
	end,
	PartyHat = function(head, parent)
		local s = head.Size
		for i = 0, 3 do
			local r = 0.5 - i * 0.11
			attach(head, parent, { Name = "Cone", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.4, r * s.X * 2, r * s.X * 2), Color = i % 2 == 0 and Color3.fromRGB(80, 170, 255) or Color3.fromRGB(255, 220, 70) }, CFrame.new(0, s.Y * 0.6 + i * 0.38, 0) * CFrame.Angles(0, 0, math.rad(90)))
		end
		attach(head, parent, { Name = "Pompom", Shape = Enum.PartType.Ball, Size = Vector3.new(0.4, 0.4, 0.4), Color = Color3.fromRGB(255, 90, 140) }, CFrame.new(0, s.Y * 0.6 + 1.6, 0))
	end,
	Halo = function(head, parent)
		local s = head.Size
		for i = 0, 11 do
			local a = i / 12 * math.pi * 2
			attach(head, parent, { Name = "HaloBit", Size = Vector3.new(0.25, 0.15, 0.45), Color = Color3.fromRGB(255, 240, 150), Material = Enum.Material.Neon }, CFrame.new(math.cos(a) * s.X * 0.45, s.Y * 0.95, math.sin(a) * s.X * 0.45) * CFrame.Angles(0, -a, 0))
		end
	end,
}

local function applyTrail(character: Model, parent: Instance, trailId: string)
	local def = Config.Shop.Trails[trailId]
	local root = character:FindFirstChild("HumanoidRootPart")
	if not def or not def.Colors or not root then
		return
	end
	local top = Instance.new("Attachment")
	top.Name = "HoH_TrailTop"
	top.Position = Vector3.new(0, 0.8, 0.4)
	top.Parent = root
	local bottom = Instance.new("Attachment")
	bottom.Name = "HoH_TrailBottom"
	bottom.Position = Vector3.new(0, -1.2, 0.4)
	bottom.Parent = root
	local keypoints = {}
	for i, color in def.Colors do
		table.insert(keypoints, ColorSequenceKeypoint.new((i - 1) / math.max(1, #def.Colors - 1), color))
	end
	local trail = Instance.new("Trail")
	trail.Name = "HoH_Trail"
	trail.Attachment0 = top
	trail.Attachment1 = bottom
	trail.Color = ColorSequence.new(keypoints)
	trail.Lifetime = 0.5
	trail.LightEmission = 0.6
	trail.Transparency = NumberSequence.new(0.2, 1)
	trail.Parent = parent
	-- Les attachements sont détruits avec le dossier
	local link = Instance.new("ObjectValue")
	link.Name = "TrailAttachments"
	link.Value = top
	link.Parent = parent
	parent.Destroying:Connect(function()
		top:Destroy()
		bottom:Destroy()
	end)
end

-- (Ré)applique les apparences équipées sur le personnage
function Cosmetics.Apply(character: Model, lookId: string?, trailId: string?)
	local existing = character:FindFirstChild(FOLDER)
	if existing then
		existing:Destroy()
	end
	local head = character:FindFirstChild("Head")
	local needed = (lookId and lookId ~= "None" and HATS[lookId]) or (trailId and trailId ~= "None")
	if not needed then
		return
	end
	local parent = folderOf(character)
	if lookId and HATS[lookId] and head and head:IsA("BasePart") then
		HATS[lookId](head, parent)
	end
	if trailId and trailId ~= "None" then
		applyTrail(character, parent, trailId)
	end
end

return Cosmetics

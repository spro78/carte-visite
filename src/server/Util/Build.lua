--[[
	Build.lua
	Petits utilitaires de construction de géométrie par le code.
	Utilisé par le lobby et par les maps.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Style = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Style"))

local Build = {}

Build.Font = Enum.Font.GothamBold

-- Crée une Part ancrée avec les propriétés données.
-- Clés spéciales :
--   Accent = true : garde la couleur telle quelle (gameplay) ; sinon la couleur
--                   passe par le filtre de la direction artistique (Style) ;
--   Studs = true  : dessus à tenons (look Roblox classique).
local function make(className: string, props: { [string]: any }, parent: Instance?): BasePart
	local part = Instance.new(className) :: BasePart
	part.Anchored = true
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Material = Enum.Material.SmoothPlastic
	local accent = props.Accent == true
	for key, value in props do
		if key ~= "Accent" and key ~= "Studs" then
			(part :: any)[key] = value
		end
	end
	if props.Studs == true then
		-- Look Roblox classique : tenons sur le dessus
		part.Material = Enum.Material.Plastic
		part.TopSurface = Enum.SurfaceType.Studs
	end
	if not accent and part.Material ~= Enum.Material.Neon then
		part.Color = Style.Environment(part.Color)
	end
	if parent then
		part.Parent = parent
	end
	return part
end

function Build.Part(props: { [string]: any }, parent: Instance?): Part
	return make("Part", props, parent) :: Part
end

-- Coin (WedgePart) : face verticale à l'arrière (+Z local), pente qui
-- descend vers l'avant (-Z local).
function Build.Wedge(props: { [string]: any }, parent: Instance?): WedgePart
	return make("WedgePart", props, parent) :: WedgePart
end

function Build.CornerWedge(props: { [string]: any }, parent: Instance?): CornerWedgePart
	return make("CornerWedgePart", props, parent) :: CornerWedgePart
end

-- Cylindre debout (axe vertical) : Roblox oriente les cylindres sur l'axe X,
-- on les tourne de 90° pour les avoir à la verticale.
function Build.VerticalCylinder(position: Vector3, radius: number, height: number, props: { [string]: any }, parent: Instance?): Part
	local merged = table.clone(props)
	merged.Shape = Enum.PartType.Cylinder
	merged.Size = Vector3.new(height, radius * 2, radius * 2)
	merged.CFrame = CFrame.new(position) * CFrame.Angles(0, 0, math.rad(90))
	return Build.Part(merged, parent)
end

-- Ajoute un SurfaceGui avec un TextLabel sur une face d'une Part.
-- Retourne le TextLabel pour pouvoir le mettre à jour.
function Build.SurfaceLabel(part: BasePart, face: Enum.NormalId, text: string, props: { [string]: any }?): TextLabel
	local gui = Instance.new("SurfaceGui")
	gui.Face = face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 40
	gui.LightInfluence = 0
	gui.AlwaysOnTop = false
	gui.Parent = part

	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Build.Font
	label.TextScaled = true
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextStrokeTransparency = 0.6
	label.Text = text
	if props then
		for key, value in props do
			(label :: any)[key] = value
		end
	end
	label.Parent = gui
	return label
end

-- SurfaceGui vide (pour des mises en page plus riches). Retourne le SurfaceGui.
function Build.SurfaceGui(part: BasePart, face: Enum.NormalId): SurfaceGui
	local gui = Instance.new("SurfaceGui")
	gui.Face = face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 40
	gui.LightInfluence = 0
	gui.Parent = part
	return gui
end

-- TextLabel générique dans un parent GUI.
function Build.TextLabel(parent: Instance, props: { [string]: any }): TextLabel
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Font = Build.Font
	label.TextScaled = true
	label.TextColor3 = Color3.new(1, 1, 1)
	for key, value in props do
		(label :: any)[key] = value
	end
	label.Parent = parent
	return label
end

-- Soude part1 sur part0 (part1 devient non ancrée et sans collision).
function Build.Weld(part0: BasePart, part1: BasePart): WeldConstraint
	part1.Anchored = false
	part1.CanCollide = false
	part1.CanQuery = false
	part1.CanTouch = false
	part1.Massless = true
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = part0
	weld.Part1 = part1
	weld.Parent = part1
	return weld
end

-- Retourne le joueur associé à une Part touchée (ou nil).
function Build.GetPlayerFromHit(hit: BasePart): Player?
	local Players = game:GetService("Players")
	local model = hit:FindFirstAncestorOfClass("Model")
	if not model then
		return nil
	end
	return Players:GetPlayerFromCharacter(model)
end

return Build

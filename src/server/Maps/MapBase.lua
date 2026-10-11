--[[
	MapBase.lua
	Briques communes à toutes les maps : sol, limites invisibles, trois bases en
	triangle autour d'une zone centrale, cachettes (hautes herbes, buissons,
	terriers), décors (clôtures, bottes de foin, arbres, rochers) et mécanismes
	tournants. Chaque module de map appelle ces fonctions dans Build().
]]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Teams = require(Shared.Teams)
local Config = require(Shared.Config)
local Mechanics = require(Shared.Mechanics)
local Build = require(script.Parent.Parent.Util.Build)

local MapBase = {}

MapBase.HidingTag = "HoH_HidingSpot"

export type Base = {
	Team: string,
	Center: Vector3, -- centre de la base (au niveau du sol)
	CFrame: CFrame, -- orienté vers le centre de la map
	Pad: Part,
	Spawns: { CFrame },
	Radius: number, -- demi-côté de la plateforme
}

-- Angles (degrés) des trois bases autour du centre
MapBase.BaseAngles = { FOX = 90, CHICKEN = 210, SNAKE = 330 }

local random = Random.new()

function MapBase.NewFolder(name: string): Folder
	local folder = Instance.new("Folder")
	folder.Name = name
	return folder
end

-- Sol carré centré sur origin, surface supérieure à origin.Y.
function MapBase.BuildGround(folder: Instance, origin: Vector3, size: number, color: Color3, material: Enum.Material?): Part
	return Build.Part({
		Name = "Ground",
		Size = Vector3.new(size, 4, size),
		Position = origin + Vector3.new(0, -2, 0),
		Color = color,
		Material = material or Enum.Material.Grass,
	}, folder)
end

-- Quatre murs invisibles (et un plafond bas) pour qu'on ne sorte pas de la map.
function MapBase.BuildBoundary(folder: Instance, origin: Vector3, size: number, height: number)
	local half = size / 2
	local specs = {
		{ Vector3.new(0, 0, -half), Vector3.new(size, height, 2) },
		{ Vector3.new(0, 0, half), Vector3.new(size, height, 2) },
		{ Vector3.new(-half, 0, 0), Vector3.new(2, height, size) },
		{ Vector3.new(half, 0, 0), Vector3.new(2, height, size) },
	}
	for index, spec in specs do
		Build.Part({
			Name = "Boundary" .. index,
			Size = spec[2],
			Position = origin + spec[1] + Vector3.new(0, height / 2, 0),
			Transparency = 1,
			CanQuery = false,
		}, folder)
	end
end

-- Position d'une base (angle en degrés autour du centre)
function MapBase.BasePosition(origin: Vector3, teamId: string, radius: number): Vector3
	local angle = math.rad(MapBase.BaseAngles[teamId])
	return origin + Vector3.new(math.cos(angle) * radius, 0, math.sin(angle) * radius)
end

-- Trois bases disposées en triangle. Retourne bases[teamId].
function MapBase.BuildBases(folder: Instance, origin: Vector3, radius: number, padSize: number): { [string]: Base }
	local bases = {}
	for _, teamId in Teams.Order do
		local def = Teams.Get(teamId)
		assert(def)
		local center = MapBase.BasePosition(origin, teamId, radius)
		local facing = CFrame.lookAt(center, Vector3.new(origin.X, center.Y, origin.Z))
		local rotation = facing - facing.Position

		local pad = Build.Part({
			Name = teamId .. "_BasePad",
			Size = Vector3.new(padSize, 1, padSize),
			CFrame = CFrame.new(center + Vector3.new(0, 0.5, 0)) * rotation,
			Color = def.Color,
			Material = Enum.Material.SmoothPlastic,
			Accent = true,
		}, folder)
		pad:SetAttribute("Team", teamId)
		pad:SetAttribute("BasePad", true)
		Build.Part({
			Name = teamId .. "_BaseBorder",
			Size = Vector3.new(padSize + 3, 0.6, padSize + 3),
			CFrame = CFrame.new(center + Vector3.new(0, 0.3, 0)) * rotation,
			Color = def.DarkColor,
			Accent = true,
		}, folder)
		-- Emblème au sol
		local emblem = Build.Part({
			Name = teamId .. "_Emblem",
			Size = Vector3.new(padSize * 0.55, 0.1, padSize * 0.2),
			CFrame = CFrame.new(center + Vector3.new(0, 1.05, 0)) * rotation,
			Color = def.DarkColor,
			Transparency = 1,
			CanCollide = false,
			CanQuery = false,
		}, folder)
		Build.SurfaceLabel(emblem, Enum.NormalId.Top, def.Display, { TextColor3 = def.DarkColor, TextTransparency = 0.15 })

		local halfPad = padSize / 2
		for _, sx in { -1, 1 } do
			for _, sz in { -1, 1 } do
				local localPos = Vector3.new(sx * (halfPad - 1.5), 5, sz * (halfPad - 1.5))
				Build.Part({
					Name = teamId .. "_Pillar",
					Size = Vector3.new(2, 10, 2),
					CFrame = CFrame.new(center) * rotation * CFrame.new(localPos),
					Color = def.Color:Lerp(Color3.new(1, 1, 1), 0.3),
					Accent = true,
				}, folder)
				Build.Part({
					Name = teamId .. "_PillarTop",
					Shape = Enum.PartType.Ball,
					Size = Vector3.new(3, 3, 3),
					CFrame = CFrame.new(center) * rotation * CFrame.new(localPos + Vector3.new(0, 6, 0)),
					Color = def.Color,
					Material = Enum.Material.Neon,
				}, folder)
			end
		end

		-- Pancarte à l'arrière de la base, face au centre
		local sign = Build.Part({
			Name = teamId .. "_Sign",
			Size = Vector3.new(18, 7, 1),
			CFrame = CFrame.new(center) * rotation * CFrame.new(0, 8, halfPad + 2),
			Color = Color3.fromRGB(45, 50, 70),
		}, folder)
		Build.SurfaceLabel(sign, Enum.NormalId.Front, def.Display .. " BASE", { TextColor3 = def.Color })

		-- Points d'apparition : cercle au centre de la base, tournés vers le centre de la map
		local spawns = {}
		local spawnCount = 8
		for i = 1, spawnCount do
			local a = (i / spawnCount) * math.pi * 2
			local offset = Vector3.new(math.cos(a) * padSize * 0.25, 0, math.sin(a) * padSize * 0.25)
			local position = center + offset + Vector3.new(0, 1 + Config.World.RespawnHeight, 0)
			table.insert(spawns, CFrame.lookAt(position, Vector3.new(origin.X, position.Y, origin.Z)))
		end

		bases[teamId] = {
			Team = teamId,
			Center = center,
			CFrame = facing,
			Pad = pad,
			Spawns = spawns,
			Radius = halfPad,
		}
	end
	return bases
end

-- Vrai si la position est sur la plateforme de la base (dans son repère).
function MapBase.IsInBase(base: Base, position: Vector3, margin: number?): boolean
	local localPos = base.CFrame:PointToObjectSpace(position)
	local limit = base.Radius + (margin or 0)
	return math.abs(localPos.X) <= limit and math.abs(localPos.Z) <= limit and localPos.Y < 12
end

-- Zone centrale ronde
function MapBase.BuildCentralPad(folder: Instance, origin: Vector3, radius: number, color: Color3, material: Enum.Material?): Part
	return Build.VerticalCylinder(origin + Vector3.new(0, 0.25, 0), radius, 0.5, {
		Name = "CentralPad",
		Color = color,
		Material = material or Enum.Material.SmoothPlastic,
	}, folder)
end

-- ---------------------------------------------------------------------------
-- Cachettes : une zone invisible taguée + un décor qui masque le joueur
-- ---------------------------------------------------------------------------
local function hidingZone(folder: Instance, cframe: CFrame, size: Vector3, kind: string): Part
	local zone = Build.Part({
		Name = "HidingZone_" .. kind,
		Size = size,
		CFrame = cframe,
		Transparency = 1,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
	}, folder)
	zone:SetAttribute("HidingKind", kind)
	CollectionService:AddTag(zone, MapBase.HidingTag)
	return zone
end

-- Hautes herbes : un massif de brins + une zone de cachette
function MapBase.BuildTallGrass(folder: Instance, position: Vector3, radius: number, color: Color3?)
	local base = color or Color3.fromRGB(95, 165, 70)
	local model = Instance.new("Model")
	model.Name = "TallGrass"
	local blades = math.floor(radius * 3.2)
	for i = 1, blades do
		local a = random:NextNumber(0, math.pi * 2)
		local r = math.sqrt(random:NextNumber()) * radius
		local height = random:NextNumber(5.5, 7.5)
		local p = position + Vector3.new(math.cos(a) * r, height / 2, math.sin(a) * r)
		Build.Part({
			Name = "Blade",
			Size = Vector3.new(random:NextNumber(0.9, 1.5), height, 0.3),
			CFrame = CFrame.new(p) * CFrame.Angles(random:NextNumber(-0.15, 0.15), random:NextNumber(0, math.pi), random:NextNumber(-0.2, 0.2)),
			Color = base:Lerp(Color3.fromRGB(200, 210, 90), random:NextNumber(0, 0.35)),
			Material = Enum.Material.Grass,
			CanCollide = false,
			CanQuery = false,
			CastShadow = false,
		}, model)
	end
	-- Coeur dense pour cacher complètement le joueur
	Build.VerticalCylinder(position + Vector3.new(0, 2.6, 0), radius * 0.65, 5.2, {
		Name = "GrassCore",
		Color = base,
		Material = Enum.Material.Grass,
		CanCollide = false,
		CanQuery = false,
		Transparency = 0.05,
	}, model)
	model.Parent = folder
	hidingZone(folder, CFrame.new(position + Vector3.new(0, 3, 0)), Vector3.new(radius * 2, 6, radius * 2), "Grass")
	return model
end

-- Buisson : boule de feuillage traversable
function MapBase.BuildBush(folder: Instance, position: Vector3, size: number, color: Color3?)
	local model = Instance.new("Model")
	model.Name = "Bush"
	local leafColor = color or Color3.fromRGB(60, 130, 60)
	Build.Part({
		Name = "Leaves",
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(size, size, size),
		Position = position + Vector3.new(0, size * 0.32, 0),
		Color = leafColor,
		Material = Enum.Material.Grass,
		CanCollide = false,
		CanQuery = false,
	}, model)
	for i = 1, 3 do
		local a = i * 2.1
		Build.Part({
			Name = "Leaves",
			Shape = Enum.PartType.Ball,
			Size = Vector3.new(size * 0.6, size * 0.6, size * 0.6),
			Position = position + Vector3.new(math.cos(a) * size * 0.38, size * 0.2, math.sin(a) * size * 0.38),
			Color = leafColor:Lerp(Color3.new(0, 0, 0), 0.12),
			Material = Enum.Material.Grass,
			CanCollide = false,
			CanQuery = false,
		}, model)
	end
	model.Parent = folder
	hidingZone(folder, CFrame.new(position + Vector3.new(0, 2.5, 0)), Vector3.new(size * 0.85, 5, size * 0.85), "Bush")
	return model
end

-- Terrier : un monticule avec une entrée ; se tenir dans le trou cache le joueur
function MapBase.BuildBurrow(folder: Instance, position: Vector3, color: Color3?)
	local model = Instance.new("Model")
	model.Name = "Burrow"
	local dirt = color or Color3.fromRGB(120, 85, 55)
	Build.Part({
		Name = "Mound",
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(14, 14, 14),
		Position = position + Vector3.new(0, -3.5, 0),
		Color = dirt,
		Material = Enum.Material.Ground,
		CanCollide = false,
		CanQuery = false,
	}, model)
	Build.VerticalCylinder(position + Vector3.new(0, 3.55, 0), 3.2, 0.2, {
		Name = "Hole",
		Color = Color3.fromRGB(25, 18, 12),
		CanCollide = false,
		CanQuery = false,
	}, model)
	model.Parent = folder
	hidingZone(folder, CFrame.new(position + Vector3.new(0, 2.5, 0)), Vector3.new(9, 6, 9), "Burrow")
	return model
end

-- ---------------------------------------------------------------------------
-- Décors
-- ---------------------------------------------------------------------------
function MapBase.BuildFence(folder: Instance, from: Vector3, to: Vector3, color: Color3?)
	local wood = color or Color3.fromRGB(165, 115, 70)
	local delta = to - from
	local length = delta.Magnitude
	local mid = (from + to) / 2
	local cf = CFrame.lookAt(mid, mid + delta)
	for _, h in { 1.4, 2.8 } do
		Build.Part({
			Name = "FenceRail",
			Size = Vector3.new(0.4, 0.5, length),
			CFrame = cf + Vector3.new(0, h, 0),
			Color = wood,
			Material = Enum.Material.Wood,
		}, folder)
	end
	local posts = math.max(2, math.floor(length / 8) + 1)
	for i = 0, posts - 1 do
		local p = from + delta * (i / (posts - 1))
		Build.Part({
			Name = "FencePost",
			Size = Vector3.new(0.8, 3.6, 0.8),
			Position = p + Vector3.new(0, 1.8, 0),
			Color = wood:Lerp(Color3.new(0, 0, 0), 0.15),
			Material = Enum.Material.Wood,
		}, folder)
	end
end

function MapBase.BuildHayBale(folder: Instance, position: Vector3, yaw: number?)
	Build.Part({
		Name = "HayBale",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(5, 5, 5),
		CFrame = CFrame.new(position + Vector3.new(0, 2.5, 0)) * CFrame.Angles(0, yaw or 0, 0),
		Color = Color3.fromRGB(230, 195, 95),
		Material = Enum.Material.Fabric,
	}, folder)
end

function MapBase.BuildTree(folder: Instance, position: Vector3, scale: number?, leafColor: Color3?)
	local s = scale or 1
	Build.VerticalCylinder(position + Vector3.new(0, 5 * s, 0), 1.2 * s, 10 * s, {
		Name = "Trunk",
		Color = Color3.fromRGB(110, 75, 45),
		Material = Enum.Material.Wood,
	}, folder)
	Build.Part({
		Name = "Canopy",
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(13, 13, 13) * s,
		Position = position + Vector3.new(0, 13 * s, 0),
		Color = leafColor or Color3.fromRGB(70, 150, 70),
		Material = Enum.Material.Grass,
	}, folder)
end

function MapBase.BuildRock(folder: Instance, position: Vector3, size: Vector3, color: Color3?)
	return Build.Part({
		Name = "Rock",
		Size = size,
		CFrame = CFrame.new(position + Vector3.new(0, size.Y / 2 - 0.5, 0)) * CFrame.Angles(random:NextNumber(-0.15, 0.15), random:NextNumber(0, math.pi), random:NextNumber(-0.15, 0.15)),
		Color = color or Color3.fromRGB(140, 135, 130),
		Material = Enum.Material.Slate,
	}, folder)
end

-- Bordure décorative tout autour (clôture) avec ouvertures nulles : la limite
-- invisible fait le reste.
function MapBase.BuildPerimeterFence(folder: Instance, origin: Vector3, size: number, color: Color3?)
	local half = size / 2 - 2
	local corners = {
		origin + Vector3.new(-half, 0, -half),
		origin + Vector3.new(half, 0, -half),
		origin + Vector3.new(half, 0, half),
		origin + Vector3.new(-half, 0, half),
	}
	for i = 1, 4 do
		MapBase.BuildFence(folder, corners[i], corners[i % 4 + 1], color)
	end
end

-- ---------------------------------------------------------------------------
-- Mécanismes tournants
-- ---------------------------------------------------------------------------

-- Crée un modèle "spinner" dont le pivot est le centre de rotation.
-- Les Parts ajoutées au modèle tournent avec lui (animation côté client).
function MapBase.NewSpinner(folder: Instance, name: string, pivot: CFrame): Model
	local model = Instance.new("Model")
	model.Name = name
	local anchor = Build.Part({
		Name = "Pivot",
		Size = Vector3.new(0.2, 0.2, 0.2),
		CFrame = pivot,
		Transparency = 1,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
	}, model)
	model.PrimaryPart = anchor
	model:SetAttribute("SpinBase", pivot)
	model.Parent = folder
	return model
end

function MapBase.StartSpinner(model: Model, speed: number)
	Mechanics.SetSpin(model, speed, 0)
	CollectionService:AddTag(model, Mechanics.SpinnerTag)
end

return MapBase

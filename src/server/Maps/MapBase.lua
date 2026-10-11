--[[
	MapBase.lua
	Briques communes à toutes les maps : sol, limites invisibles, trois bases
	en triangle autour d'une zone centrale, cachettes de base.
	Chaque module de map appelle ces fonctions dans Build().
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Teams = require(Shared.Teams)
local Config = require(Shared.Config)
local Build = require(script.Parent.Parent.Util.Build)

local MapBase = {}

export type Base = {
	Team: string,
	Center: Vector3, -- centre de la base (au niveau du sol)
	CFrame: CFrame, -- orienté vers le centre de la map
	Pad: Part,
	Spawns: { CFrame },
	Radius: number,
}

-- Angles (degrés) des trois bases autour du centre
MapBase.BaseAngles = { FOX = 90, CHICKEN = 210, SNAKE = 330 }

-- Crée le dossier qui contiendra toute la géométrie de la map.
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

-- Quatre murs invisibles pour qu'on ne tombe pas de la map.
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

-- Trois bases disposées en triangle. Retourne bases[teamId].
function MapBase.BuildBases(folder: Instance, origin: Vector3, radius: number, padSize: number): { [string]: Base }
	local bases = {}
	for _, teamId in Teams.Order do
		local def = Teams.Get(teamId)
		assert(def)
		local angle = math.rad(MapBase.BaseAngles[teamId])
		local center = origin + Vector3.new(math.cos(angle) * radius, 0, math.sin(angle) * radius)
		local facing = CFrame.lookAt(center, Vector3.new(origin.X, center.Y, origin.Z))
		local rotation = facing - facing.Position

		-- Plateforme colorée
		local pad = Build.Part({
			Name = teamId .. "_BasePad",
			Size = Vector3.new(padSize, 1, padSize),
			CFrame = CFrame.new(center + Vector3.new(0, 0.5, 0)) * rotation,
			Color = def.Color,
		}, folder)
		pad:SetAttribute("Team", teamId)
		pad:SetAttribute("BasePad", true)

		-- Bordure plus sombre
		Build.Part({
			Name = teamId .. "_BaseBorder",
			Size = Vector3.new(padSize + 3, 0.6, padSize + 3),
			CFrame = CFrame.new(center + Vector3.new(0, 0.3, 0)) * rotation,
			Color = def.Color:Lerp(Color3.new(0, 0, 0), 0.35),
		}, folder)

		-- Quatre piliers aux coins
		local halfPad = padSize / 2
		for _, sx in { -1, 1 } do
			for _, sz in { -1, 1 } do
				local local_ = Vector3.new(sx * (halfPad - 1.5), 5, sz * (halfPad - 1.5))
				Build.Part({
					Name = teamId .. "_Pillar",
					Size = Vector3.new(2, 10, 2),
					CFrame = CFrame.new(center) * rotation * CFrame.new(local_),
					Color = def.Color:Lerp(Color3.new(1, 1, 1), 0.3),
				}, folder)
				Build.Part({
					Name = teamId .. "_PillarTop",
					Shape = Enum.PartType.Ball,
					Size = Vector3.new(3, 3, 3),
					CFrame = CFrame.new(center) * rotation * CFrame.new(local_ + Vector3.new(0, 6, 0)),
					Color = def.Color,
					Material = Enum.Material.Neon,
				}, folder)
			end
		end

		-- Pancarte à l'arrière de la base, face au centre
		local sign = Build.Part({
			Name = teamId .. "_Sign",
			Size = Vector3.new(16, 7, 1),
			CFrame = CFrame.new(center) * rotation * CFrame.new(0, 7, halfPad + 2),
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

-- Zone centrale ronde (point de départ des mécanismes).
function MapBase.BuildCentralPad(folder: Instance, origin: Vector3, radius: number, color: Color3): Part
	return Build.VerticalCylinder(origin + Vector3.new(0, 0.25, 0), radius, 0.5, {
		Name = "CentralPad",
		Color = color,
	}, folder)
end

-- Vrai si la position est dans la base de l'équipe (distance horizontale).
function MapBase.IsInBase(base: Base, position: Vector3): boolean
	local dx = position.X - base.Center.X
	local dz = position.Z - base.Center.Z
	return math.abs(dx) <= base.Radius and math.abs(dz) <= base.Radius
end

-- Buisson décoratif (la logique de cachette arrive en phase 3).
function MapBase.BuildBush(folder: Instance, position: Vector3, size: number): Part
	local bush = Build.Part({
		Name = "Bush",
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(size, size * 0.8, size),
		Position = position + Vector3.new(0, size * 0.3, 0),
		Color = Color3.fromRGB(60, 130, 60),
		Material = Enum.Material.Grass,
		CanCollide = false,
	}, folder)
	bush:SetAttribute("HidingSpot", true)
	return bush
end

return MapBase

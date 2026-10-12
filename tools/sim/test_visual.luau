--!nocheck
--[[
	test_visual.luau : règles chiffrées de la bible visuelle (reference/BIBLE_VISUELLE.md),
	vérifiées sur chaque map construite par le vrai code :
	  §2  plein jour : ClockTime 12 à 16,5, Brightness >= 2,2, brume <= 0,3
	  §3  sol en pièces : aucun remplissage de Terrain
	  §1  aucune grande surface de la zone de jeu aux couleurs des équipes
	  §5  couloirs de course : 10 studs de large de chaque camp vers le centre,
	      sans obstacle solide de plus de 3 studs (hors mécanismes de jeu)
	  §6  depuis l'entrée de chaque camp, à hauteur d'yeux, on voit la balise
	      des deux autres camps
	  §6  contours lisibles : chaque couleur d'équipe à ΔE >= 45 du plateau et
	      >= 30 des chemins
	  §5  zone sûre de chaque camp : repère au sol, dans la carte, couvre les
	      points d'apparition, sans empiéter sur un autre camp
	Ce que ce test ne peut pas juger : le rendu réel de Roblox (matières, ombres,
	tenons), la lisibilité perçue en mouvement et la performance sur appareil.
]]
local H = require("./harness")
local World, Engine = H.World, H.Engine
local roblox = H.Roblox
local Vector3, CFrame, Enum = roblox.Vector3, roblox.CFrame, roblox.Enum
local check, section = H.check, H.section

local server = H.boot(function(Config)
	Config.Debug.DisableBots = true
end)
local Config = server.Config
local Teams = server.Teams
local Style = H.require(World.game.ReplicatedStorage.Shared.Style)
local O = Config.World.MapOrigin

-- ---------------------------------------------------------------------------
-- Outils
-- ---------------------------------------------------------------------------
local function hsv(c)
	local r, g, b = c.R, c.G, c.B
	local maxc, minc = math.max(r, g, b), math.min(r, g, b)
	local v = maxc
	local s = maxc > 0 and (maxc - minc) / maxc or 0
	local h = 0
	if maxc ~= minc then
		local d = maxc - minc
		if maxc == r then
			h = ((g - b) / d) % 6
		elseif maxc == g then
			h = (b - r) / d + 2
		else
			h = (r - g) / d + 4
		end
		h *= 60
	end
	return h, s, v
end

-- Écart de couleur CIE76 (Lab) entre deux Color3
local function lab(c)
	local function lin(v)
		return v <= 0.04045 and v / 12.92 or ((v + 0.055) / 1.055) ^ 2.4
	end
	local r, g, b = lin(c.R), lin(c.G), lin(c.B)
	local x = (0.4124 * r + 0.3576 * g + 0.1805 * b) / 0.95047
	local y = 0.2126 * r + 0.7152 * g + 0.0722 * b
	local z = (0.0193 * r + 0.1192 * g + 0.9505 * b) / 1.08883
	local function f(t)
		return t > 0.008856 and t ^ (1 / 3) or 7.787 * t + 16 / 116
	end
	return 116 * f(y) - 16, 500 * (f(x) - f(y)), 200 * (f(y) - f(z))
end
local function deltaE(a, b)
	local l1, a1, b1 = lab(a)
	local l2, a2, b2 = lab(b)
	return math.sqrt((l1 - l2) ^ 2 + (a1 - a2) ^ 2 + (b1 - b2) ^ 2)
end
-- Avatars à fort contraste (bible §2, principe P3) : le plateau s'écarte d'au
-- moins 40 (ΔE) des trois couleurs d'équipe et des avatars très clairs ou très sombres
local AVATAR_REFS = {
	{ "white avatar", roblox.Color3.fromRGB(245, 245, 245) },
	{ "dark avatar", roblox.Color3.fromRGB(27, 42, 53) },
}

-- Couleur confondable avec une couleur d'équipe : même teinte (< 22°),
-- saturation et luminosité proches (< 0,25 chacune)
local function confusable(color)
	local h, s, v = hsv(color)
	for _, teamId in Teams.Order do
		local th, ts, tv = hsv(Teams.Get(teamId).Color)
		local dh = math.abs(h - th)
		dh = math.min(dh, 360 - dh)
		if dh < 22 and math.abs(s - ts) < 0.25 and math.abs(v - tv) < 0.25 and s > 0.3 then
			return teamId
		end
	end
	return nil
end

local function insideCamp(part)
	local p = part.Parent
	while p and p ~= World.workspace do
		if string.sub(p.Name, -5) == "_Camp" then
			return true
		end
		p = p.Parent
	end
	return false
end

local function underModel(part, names)
	local p = part.Parent
	while p and p ~= World.workspace do
		if names[p.Name] then
			return true
		end
		p = p.Parent
	end
	return false
end

-- Demi-étendues de la boîte englobante (repère du monde) d'une pièce orientée
local function worldHalfExtents(part)
	local cf, s = part.CFrame, part.Size / 2
	local rx, ry, rz = cf.XVector, cf.YVector, cf.ZVector
	return Vector3.new(
		math.abs(rx.X) * s.X + math.abs(ry.X) * s.Y + math.abs(rz.X) * s.Z,
		math.abs(rx.Y) * s.X + math.abs(ry.Y) * s.Y + math.abs(rz.Y) * s.Z,
		math.abs(rx.Z) * s.X + math.abs(ry.Z) * s.Y + math.abs(rz.Z) * s.Z
	)
end

local function topOf(part)
	return part.Position.Y + worldHalfExtents(part).Y
end

-- Point (x, z) dans l'empreinte au sol d'une pièce : exacte pour une pièce
-- debout (tournée seulement autour de la verticale), boîte englobante sinon
local function footprintContains(part, x, z, margin)
	local cf, size = part.CFrame, part.Size
	if math.abs(cf.YVector.Y) > 0.99 then
		local localPoint = cf:PointToObjectSpace(Vector3.new(x, cf.Position.Y, z))
		return math.abs(localPoint.X) <= size.X / 2 + margin and math.abs(localPoint.Z) <= size.Z / 2 + margin
	end
	local half = worldHalfExtents(part)
	return math.abs(x - cf.Position.X) <= half.X + margin and math.abs(z - cf.Position.Z) <= half.Z + margin
end

-- Segment contre boîte orientée (méthode des dalles dans le repère de la pièce)
local function segmentHitsBox(part, a, b)
	local cf, half = part.CFrame, part.Size / 2
	local la, lb = cf:PointToObjectSpace(a), cf:PointToObjectSpace(b)
	local d = lb - la
	local t0, t1 = 0, 1
	for _, axis in { "X", "Y", "Z" } do
		local o, dir, h = la[axis], d[axis], half[axis]
		if math.abs(dir) < 1e-9 then
			if o < -h or o > h then
				return false
			end
		else
			local ta, tb = (-h - o) / dir, (h - o) / dir
			if ta > tb then
				ta, tb = tb, ta
			end
			t0, t1 = math.max(t0, ta), math.min(t1, tb)
			if t0 > t1 then
				return false
			end
		end
	end
	return true
end

-- Pièces de jeu à ignorer dans les couloirs (mécanismes, zones invisibles)
local MECHANISMS = {
	SpinningArm = true, Carousel = true, Turnstile = true, Catapult = true,
}
-- Fin des couloirs : bord de la zone centrale de chaque map (aire du bras,
-- place du manège, catapulte, tourniquet)
local LANE_END = { TheFarm = 64, TheCarousel = 50, TheCanyon = 30, TheSwamp = 30 }

local maps = { "TheFarm", "TheCarousel", "TheCanyon", "TheSwamp" }
for _, id in maps do
	section("Bible visuelle : " .. id)
	local map, bases
	local opsBefore = 0
	H.onServer(function()
		map = World.Require(World.game.ServerScriptService.Server.Maps[id])
		opsBefore = #World.TerrainOps
		map.Build(O, {
			Origin = O,
			GetParticipants = function() return {} end,
			GetTeam = function() return nil end,
			AddScore = function() end,
			GetScore = function() return 0 end,
			Announce = function() end,
			EndRound = function() end,
			IsRoundActive = function() return true end,
		})
	end)
	Engine.Advance(0.2)
	local cfg = Config.Maps[id]
	local half = cfg.GroundSize / 2
	local folder = World.workspace:FindFirstChild("Map_" .. id)
	check(folder ~= nil, "map construite")

	-- §2 Lumière de jour
	local L = map.Lighting or {}
	local clock = L.ClockTime or Style.Lighting.ClockTime
	local bright = L.Brightness or Style.Lighting.Brightness
	local density = (L.Atmosphere and L.Atmosphere.Density) or Style.Atmosphere.Density
	check(clock >= 12 and clock <= 16.5 and bright >= 2.2 and density <= 0.3, string.format("plein jour (heure %.1f, luminosité %.1f, brume %.2f)", clock, bright, density))

	-- §3 Pas de Terrain
	local fills = 0
	for i = opsBefore + 1, #World.TerrainOps do
		-- (le nettoyage de l'arène remplit d'air : ce n'est pas du relief)
		if World.TerrainOps[i].material ~= "Air" then
			fills += 1
		end
	end
	check(fills == 0, "aucun remplissage de Terrain (" .. fills .. ")")

	-- Pièces de la map
	local parts = {}
	for _, d in folder:GetDescendants() do
		if d:IsA("BasePart") then
			table.insert(parts, d)
		end
	end

	-- §1 Couleurs d'équipe réservées
	local clashes = {}
	for _, part in parts do
		local p = part.Position
		local inPlay = math.abs(p.X - O.X) <= half and math.abs(p.Z - O.Z) <= half
		if inPlay and part.Transparency < 0.5 and part.Material ~= Enum.Material.Neon and not insideCamp(part) then
			local s = part.Size
			local face = math.max(s.X * s.Y, s.Y * s.Z, s.X * s.Z)
			if face >= 64 then
				local team = confusable(part.Color)
				if team then
					table.insert(clashes, string.format("%s (%d,%d,%d ~ %s)", part.Name, part.Color.R * 255, part.Color.G * 255, part.Color.B * 255, team))
				end
			end
		end
	end
	check(#clashes == 0, "aucune grande surface aux couleurs des équipes" .. (#clashes > 0 and (" : " .. table.concat(clashes, ", ")) or ""))

	-- §2 / P3 : contraste des avatars sur le plateau
	local refs = {}
	for _, teamId in Teams.Order do
		table.insert(refs, { teamId, Teams.Get(teamId).Color })
	end
	for _, ref in AVATAR_REFS do
		table.insert(refs, ref)
	end
	local worst, worstName, boardCount = math.huge, "", 0
	local seen = {}
	for _, part in parts do
		if part.Name == "Board" and not seen[part.Color] then
			seen[part.Color] = true
			boardCount += 1
			for _, ref in refs do
				local d = deltaE(part.Color, ref[2])
				if d < worst then
					worst, worstName = d, ref[1]
				end
			end
		end
	end
	check(boardCount > 0 and worst >= 40, string.format("avatars contrastés sur le plateau : écart minimal %.0f (%s), 40 exigé", worst, worstName))

	-- §6 Contours lisibles : la couleur d'équipe (contour lumineux) se détache du
	-- plateau (ΔE >= 45) et des chemins (ΔE >= 30), sur toute la zone de jeu
	local grounds = { Board = {}, Path = {} }
	for _, part in parts do
		local kind = (part.Name == "Board" and "Board") or ((string.sub(part.Name, 1, 5) == "Path_" or part.Name == "PathJoint") and "Path") or nil
		if kind then
			grounds[kind][part.Color] = true
		end
	end
	for _, teamId in Teams.Order do
		local color = Teams.Get(teamId).Color
		local worstBoard, worstPath = math.huge, math.huge
		for c in grounds.Board do
			worstBoard = math.min(worstBoard, deltaE(color, c))
		end
		for c in grounds.Path do
			worstPath = math.min(worstPath, deltaE(color, c))
		end
		check(worstBoard >= 45 and worstPath >= 30, string.format("contour %s lisible : écart %.0f au plateau (45 exigé), %.0f aux chemins (30 exigé)", teamId, worstBoard, worstPath == math.huge and 0 or worstPath))
	end

	-- Zones sûres des trois camps : repère au sol, dans la carte, plateforme
	-- et points d'apparition couverts, pas de chevauchement entre camps
	local MapBase = H.require(World.game.ServerScriptService.Server.Maps.MapBase)
	local active = MapBase.ActiveBases
	for _, teamId in Teams.Order do
		local base = active and active[teamId]
		local zone = base and base.Safe
		local camp = folder:FindFirstChild(teamId .. "_Camp")
		local dashes, label = 0, false
		for _, d in camp and camp:GetDescendants() or {} do
			if d.Name == "SafeZoneDash" then
				dashes += 1
			elseif d.Name == "SafeZoneLabel" then
				label = true
			end
		end
		local ok = zone ~= nil and dashes >= 20 and label
		if ok then
			for _, corner in { { -zone.HalfWidth, -zone.Front }, { zone.HalfWidth, -zone.Front }, { -zone.HalfWidth, zone.Back }, { zone.HalfWidth, zone.Back } } do
				local p = base.CFrame:PointToWorldSpace(Vector3.new(corner[1], 0, corner[2]))
				if math.abs(p.X - O.X) > half or math.abs(p.Z - O.Z) > half then
					ok = false
				end
			end
			for _, spawn in base.Spawns do
				if not MapBase.IsInSafeZone(base, spawn.Position) then
					ok = false
				end
			end
			for _, other in Teams.Order do
				if other ~= teamId and MapBase.IsInSafeZone(base, active[other].Center + Vector3.new(0, 3, 0)) then
					ok = false
				end
			end
		end
		check(ok, string.format("zone sûre %s : %d tirets au sol, mention SAFE ZONE, dans la carte, couvre les apparitions%s", teamId, dashes, zone and string.format(" (±%d, avant %d, arrière %d)", zone.HalfWidth, zone.Front, zone.Back) or ""))
	end

	-- Bases (MapBase) : relues depuis les points d'apparition
	bases = {}
	for _, teamId in Teams.Order do
		local spawns = map.GetSpawns(teamId)
		local sum = Vector3.zero
		for _, s in spawns do
			sum += s.Position
		end
		local center = sum / #spawns
		bases[teamId] = { Center = Vector3.new(center.X, O.Y, center.Z), Radius = cfg.BasePadSize / 2 }
	end

	-- §5 Couloirs de course
	for _, teamId in Teams.Order do
		local base = bases[teamId]
		local toCenter = (O - base.Center)
		toCenter = Vector3.new(toCenter.X, 0, toCenter.Z).Unit
		local side = Vector3.new(-toCenter.Z, 0, toCenter.X)
		local from = base.Center + toCenter * (base.Radius + 4)
		local length = (O - from).Magnitude - LANE_END[id]
		local blockers = {}
		for _, part in parts do
			if part.CanCollide and part.Transparency < 0.9 and topOf(part) > O.Y + 3 and not insideCamp(part) and not underModel(part, MECHANISMS) then
				local hit = false
				for t = 0, length, 2 do
					for lateral = -5, 5, 2.5 do
						local q = from + toCenter * t + side * lateral
						if footprintContains(part, q.X, q.Z, 0) then
							hit = true
							break
						end
					end
					if hit then
						break
					end
				end
				if hit then
					blockers[part.Name] = true
				end
			end
		end
		local names = {}
		for name in blockers do
			table.insert(names, name)
		end
		table.sort(names)
		check(#names == 0, string.format("couloir %s -> centre dégagé sur %d studs", teamId, math.floor(length)) .. (#names > 0 and (" : " .. table.concat(names, ", ")) or ""))
	end

	-- §6 Balises visibles d'un camp à l'autre
	local orbs = {}
	for _, d in folder:GetDescendants() do
		if d.Name == "BeaconOrb" then
			local camp = d.Parent
			orbs[string.sub(camp.Name, 1, -6)] = d
		end
	end
	for _, from in Teams.Order do
		local base = bases[from]
		local toCenter = Vector3.new(O.X - base.Center.X, 0, O.Z - base.Center.Z).Unit
		local eye = base.Center + toCenter * (base.Radius + 6) + Vector3.new(0, 5, 0)
		for _, to in Teams.Order do
			if to ~= from and orbs[to] then
				local target = orbs[to].Position
				local blockers = {}
				for _, part in parts do
					if part.Transparency < 0.5 and part.Parent ~= orbs[to].Parent and part.Name ~= "Boundary1" and part.Name ~= "Boundary2" and part.Name ~= "Boundary3" and part.Name ~= "Boundary4" then
						if segmentHitsBox(part, eye, target) then
							blockers[part.Name] = true
						end
					end
				end
				local names = {}
				for name in blockers do
					table.insert(names, name)
				end
				table.sort(names)
				check(#names == 0, string.format("depuis le camp %s, la balise %s se voit", from, to) .. (#names > 0 and (" (cachée par " .. table.concat(names, ", ") .. ")") or ""))
			end
		end
	end

	H.onServer(function()
		map.Cleanup()
	end)
	Engine.Advance(0.2)
end

H.finish()

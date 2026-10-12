--!nocheck
--[[
	world.luau : DataModel factice construit à partir du sourcemap Rojo,
	services Roblox utilisés par le jeu, joueurs factices, chargement des
	scripts serveur et client.
]]

local Engine = require("./engine")
local roblox = Engine.Roblox
local fs = Engine.Fs
local luau = Engine.Luau
local serde = Engine.Serde

local Instance = Engine.Instance
local Signal = Engine.Signal
local task = Engine.task
local Vector3, CFrame, Color3, Enum = roblox.Vector3, roblox.CFrame, roblox.Color3, roblox.Enum

local World = {}
World.Engine = Engine
World.Warnings = {}

local function props(inst)
	return rawget(inst, "_props")
end

local game = Instance.new("DataModel")
game.Name = "Game"
World.game = game
local services = {}

local function service(className, name)
	local s = Instance.new(className)
	s.Name = name or className
	s.Parent = game
	services[className] = s
	return s
end

local workspace = service("Workspace")
Engine.workspace = workspace
World.workspace = workspace
props(workspace).Gravity = 196.2
props(workspace).FallenPartsDestroyHeight = -500
local camera = Instance.new("Camera")
camera.Name = "Camera"
camera.Parent = workspace
props(workspace).CurrentCamera = camera

-- Terrain : les opérations de remplissage sont enregistrées (pour le rendu)
-- La physique simulée ignore le terrain (sol plat à Engine.GroundY).
local terrain = Instance.new("Terrain")
terrain.Name = "Terrain"
terrain.Parent = workspace
props(terrain).WaterColor = Color3.fromRGB(12, 84, 92)
props(terrain).WaterTransparency = 0.3
props(terrain).WaterWaveSize = 0.15
props(terrain).WaterWaveSpeed = 10
props(terrain).WaterReflectance = 1
props(terrain).Decoration = false
World.TerrainOps = {}
World.TerrainColors = {}
local function terrainOp(op)
	table.insert(World.TerrainOps, op)
end
local function checkMaterial(m)
	assert(typeof(m) == "EnumItem" and m.EnumType == Enum.Material, "Terrain: material must be an Enum.Material")
	return m.Name
end
Engine.AddMethods(terrain, {
	FillBlock = function(_, cf, size, material)
		assert(typeof(cf) == "CFrame" and typeof(size) == "Vector3", "FillBlock(CFrame, Vector3, Material)")
		terrainOp({ op = "Block", cf = { cf:GetComponents() }, size = { size.X, size.Y, size.Z }, material = checkMaterial(material) })
	end,
	FillBall = function(_, center, radius, material)
		assert(typeof(center) == "Vector3" and type(radius) == "number", "FillBall(Vector3, number, Material)")
		terrainOp({ op = "Ball", center = { center.X, center.Y, center.Z }, radius = radius, material = checkMaterial(material) })
	end,
	FillCylinder = function(_, cf, height, radius, material)
		assert(typeof(cf) == "CFrame" and type(height) == "number" and type(radius) == "number", "FillCylinder(CFrame, number, number, Material)")
		terrainOp({ op = "Cylinder", cf = { cf:GetComponents() }, height = height, radius = radius, material = checkMaterial(material) })
	end,
	FillWedge = function(_, cf, size, material)
		assert(typeof(cf) == "CFrame" and typeof(size) == "Vector3", "FillWedge(CFrame, Vector3, Material)")
		terrainOp({ op = "Wedge", cf = { cf:GetComponents() }, size = { size.X, size.Y, size.Z }, material = checkMaterial(material) })
	end,
	FillRegion = function(_, region, resolution, material)
		local cf, size = region.CFrame, region.Size
		terrainOp({ op = "Block", cf = { cf:GetComponents() }, size = { size.X, size.Y, size.Z }, material = checkMaterial(material) })
	end,
	ReplaceMaterial = function() end,
	Clear = function()
		table.clear(World.TerrainOps)
	end,
	SetMaterialColor = function(_, material, color)
		World.TerrainColors[checkMaterial(material)] = color
	end,
	GetMaterialColor = function(_, material)
		return World.TerrainColors[checkMaterial(material)] or Color3.new(0.5, 0.5, 0.5)
	end,
})

-- Projection perspective simple (sténopé) pour la caméra factice
local function project(cam, point)
	local cf = props(cam).CFrame
	local size = props(cam).ViewportSize
	local fov = math.rad(props(cam).FieldOfView or 70)
	local rel = cf:PointToObjectSpace(point)
	local depth = -rel.Z
	local f = (size.Y / 2) / math.tan(fov / 2)
	local x = size.X / 2 + (rel.X / math.max(math.abs(depth), 1e-3)) * f
	local y = size.Y / 2 - (rel.Y / math.max(math.abs(depth), 1e-3)) * f
	local onScreen = depth > 0 and x >= 0 and x <= size.X and y >= 0 and y <= size.Y
	return Vector3.new(x, y, depth), onScreen
end
Engine.AddMethods(camera, {
	WorldToViewportPoint = project,
	WorldToScreenPoint = project,
	ViewportPointToRay = function(cam, x, y)
		local cf = props(cam).CFrame
		return roblox.Ray.new(cf.Position, cf.LookVector)
	end,
	ScreenPointToRay = function(cam, x, y)
		local cf = props(cam).CFrame
		return roblox.Ray.new(cf.Position, cf.LookVector)
	end,
})

local Players = service("Players")
local ReplicatedStorage = service("ReplicatedStorage")
local ServerScriptService = service("ServerScriptService")
service("ServerStorage")
local StarterPlayer = service("StarterPlayer")
local StarterGui = service("StarterGui")
local Lighting = service("Lighting")
local TeamsService = service("Teams")
local SoundService = service("SoundService")
local RunService = service("RunService")
local TweenService = service("TweenService")
local Debris = service("Debris")
local CollectionService = service("CollectionService")
local PathfindingService = service("PathfindingService")
local DataStoreService = service("DataStoreService")
local MarketplaceService = service("MarketplaceService")
local HttpService = service("HttpService")
local UserInputService = service("UserInputService")
local ContextActionService = service("ContextActionService")
local GuiService = service("GuiService")
local PhysicsService = service("PhysicsService")
local TextService = service("TextService")
local BadgeService = service("BadgeService")
local ProximityPromptService = service("ProximityPromptService")
service("Chat")
service("TextChatService")
service("ContentProvider")
service("LocalizationService")
service("SocialService")
service("StarterPack")
service("ReplicatedFirst")

local StarterPlayerScripts = Instance.new("StarterPlayerScripts")
StarterPlayerScripts.Name = "StarterPlayerScripts"
StarterPlayerScripts.Parent = StarterPlayer
local StarterCharacterScripts = Instance.new("StarterCharacterScripts")
StarterCharacterScripts.Name = "StarterCharacterScripts"
StarterCharacterScripts.Parent = StarterPlayer

props(Players).CharacterAutoLoads = true
props(Players).RespawnTime = 5
props(Players).MaxPlayers = 30
props(game).PlaceId = 0
props(game).GameId = 0
props(game).JobId = "sim-job"
props(game).CreatorId = 0
props(StarterPlayer).CharacterWalkSpeed = 16
props(StarterPlayer).CharacterJumpPower = 50
-- Valeurs par défaut de Lighting (comme dans Roblox)
props(Lighting).ClockTime = 14
props(Lighting).Brightness = 2
props(Lighting).FogEnd = 100000
props(Lighting).FogStart = 0
props(Lighting).FogColor = Color3.fromRGB(192, 192, 192)
props(Lighting).Ambient = Color3.fromRGB(70, 70, 70)
props(Lighting).OutdoorAmbient = Color3.fromRGB(128, 128, 128)
props(Lighting).GlobalShadows = true

World.BindToClose = {}

Engine.AddMethods(game, {
	GetService = function(_, name)
		local s = services[name]
		if not s then
			s = service(name)
		end
		return s
	end,
	FindService = function(_, name)
		return services[name]
	end,
	BindToClose = function(_, fn)
		table.insert(World.BindToClose, { fn = fn, ctx = Engine.CurrentCtx() })
	end,
	IsLoaded = function()
		return true
	end,
})

-- ---------------------------------------------------------------------------
-- Workspace
-- ---------------------------------------------------------------------------
Engine.AddMethods(workspace, {
	Raycast = function(_, origin, direction, params)
		return Engine.Raycast(origin, direction, params)
	end,
	GetPartBoundsInRadius = function(_, position, radius, params)
		return Engine.PartsInRadius(position, radius, params)
	end,
	GetPartBoundsInBox = function(_, cf, size, params)
		return Engine.PartsInRadius(cf.Position, size.Magnitude / 2, params)
	end,
	GetPartsInPart = function(_, part, params)
		local p = props(part)
		return Engine.PartsInRadius(p.CFrame.Position, p.Size.Magnitude / 2, params)
	end,
	GetServerTimeNow = function()
		return 1700000000 + Engine.Now()
	end,
	GetRealPhysicsFPS = function()
		return 60
	end,
})

-- ---------------------------------------------------------------------------
-- RunService
-- ---------------------------------------------------------------------------
rawset(RunService, "_get", function(_, key)
	if key == "Heartbeat" or key == "PostSimulation" then
		return Engine.HeartbeatSignal
	elseif key == "Stepped" or key == "PreSimulation" then
		return Engine.SteppedSignal
	elseif key == "RenderStepped" or key == "PreRender" then
		return Engine.RenderSteppedSignal
	end
	return nil
end)
-- Les signaux ci-dessus ne doivent pas être créés par EVENTS : on les retire du cache
for _, name in { "Heartbeat", "Stepped", "RenderStepped", "PreSimulation", "PostSimulation", "PreRender" } do
	rawget(RunService, "_events")[name] = name == "Heartbeat" and Engine.HeartbeatSignal
		or name == "PostSimulation" and Engine.HeartbeatSignal
		or (name == "Stepped" or name == "PreSimulation") and Engine.SteppedSignal
		or Engine.RenderSteppedSignal
end
Engine.AddMethods(RunService, {
	IsServer = function()
		return Engine.CurrentCtx() == "server"
	end,
	IsClient = function()
		return Engine.CurrentCtx() ~= "server"
	end,
	IsStudio = function()
		return true
	end,
	IsRunning = function()
		return true
	end,
	IsEdit = function()
		return false
	end,
	IsRunMode = function()
		return false
	end,
	BindToRenderStep = function(_, name, _priority, fn)
		assert(Engine.CurrentCtx() ~= "server", "BindToRenderStep can only be called from the client")
		Engine.RenderBindings[name] = { ctx = Engine.CurrentCtx(), fn = fn }
	end,
	UnbindFromRenderStep = function(_, name)
		Engine.RenderBindings[name] = nil
	end,
})

-- ---------------------------------------------------------------------------
-- Tween / Debris / Collection
-- ---------------------------------------------------------------------------
Engine.AddMethods(TweenService, {
	Create = function(_, inst, info, goals)
		assert(Engine.IsInstance(inst), "TweenService:Create expects an Instance")
		assert(type(info) == "table" and info._isTweenInfo, "TweenService:Create expects a TweenInfo")
		for k in goals do
			-- Vérifie que la propriété existe (au moins lisible)
			local _ = inst[k]
		end
		local tween = Instance.new("Tween")
		props(tween).PlaybackState = Enum.PlaybackState.Begin
		Engine.AddMethods(tween, {
			Play = function(self)
				props(self).PlaybackState = Enum.PlaybackState.Playing
				task.delay((info.Time or 0) + (info.DelayTime or 0), function()
					if props(self).PlaybackState ~= Enum.PlaybackState.Playing then
						return
					end
					if not rawget(inst, "_destroyed") then
						for k, v in goals do
							inst[k] = v
						end
					end
					if info.RepeatCount and info.RepeatCount < 0 then
						return
					end
					props(self).PlaybackState = Enum.PlaybackState.Completed
					self.Completed:Fire(Enum.PlaybackState.Completed)
				end)
			end,
			Cancel = function(self)
				props(self).PlaybackState = Enum.PlaybackState.Cancelled
			end,
			Pause = function(self)
				props(self).PlaybackState = Enum.PlaybackState.Paused
			end,
		})
		return tween
	end,
	GetValue = function(_, alpha)
		return alpha
	end,
})

Engine.AddMethods(Debris, {
	AddItem = function(_, inst, t)
		task.delay(t or 10, function()
			if not rawget(inst, "_destroyed") then
				inst:Destroy()
			end
		end)
	end,
})

Engine.AddMethods(CollectionService, Engine.Collection)

-- ---------------------------------------------------------------------------
-- AssetService : EditableMesh et MeshPart construits à la volée (kit 3D).
-- La géométrie n'est pas simulée : on compte sommets et triangles et on
-- calcule la boîte englobante (taille du MeshPart, comme Roblox).
-- Le rendu (tools/preview) relit les données du kit par l'attribut KitMesh.
-- ---------------------------------------------------------------------------
local AssetService = service("AssetService")
World.EditableMeshes = 0
World.EditableTriangles = 0
World.EditableMeshDenied = false -- simule une expérience publiée sans l'option
local EditableMeshMT = {}
EditableMeshMT.__index = EditableMeshMT
function EditableMeshMT:AddVertex(p)
	self._n += 1
	local lo, hi = self._min or p, self._max or p
	self._min = Vector3.new(math.min(lo.X, p.X), math.min(lo.Y, p.Y), math.min(lo.Z, p.Z))
	self._max = Vector3.new(math.max(hi.X, p.X), math.max(hi.Y, p.Y), math.max(hi.Z, p.Z))
	return self._n
end
function EditableMeshMT:AddNormal(_n)
	self._normals += 1
	return self._normals
end
function EditableMeshMT:AddTriangle(a, b, c)
	assert(type(a) == "number" and type(b) == "number" and type(c) == "number", "AddTriangle : identifiants de sommets attendus")
	assert(a <= self._n and b <= self._n and c <= self._n, "AddTriangle : sommet inconnu")
	self._tris += 1
	World.EditableTriangles += 1
	return self._tris
end
function EditableMeshMT:SetFaceNormals(face, ids)
	assert(face <= self._tris and #ids == 3, "SetFaceNormals : face ou normales invalides")
end
function EditableMeshMT:Destroy() end
Engine.AddMethods(AssetService, {
	CreateEditableMesh = function(_, _options)
		if World.EditableMeshDenied then
			error("EditableMesh is not allowed in this experience", 2)
		end
		World.EditableMeshes += 1
		return setmetatable({ _n = 0, _normals = 0, _tris = 0 }, EditableMeshMT)
	end,
	CreateMeshPartAsync = function(_, content, _options)
		task.wait()
		local mesh = content and content._object
		assert(mesh and getmetatable(mesh) == EditableMeshMT, "CreateMeshPartAsync : Content.fromObject(EditableMesh) attendu")
		assert(mesh._tris > 0, "CreateMeshPartAsync : mesh vide")
		local part = Instance.new("MeshPart")
		props(part).Size = mesh._max - mesh._min
		rawset(part, "_editable", mesh)
		return part
	end,
})

-- ---------------------------------------------------------------------------
-- Pathfinding (ligne droite découpée)
-- ---------------------------------------------------------------------------
World.PathFailRate = 0
Engine.AddMethods(PathfindingService, {
	CreatePath = function(_, params)
		local path = Instance.new("Path")
		props(path).Status = Enum.PathStatus.NoPath
		local waypoints = {}
		Engine.AddMethods(path, {
			ComputeAsync = function(self, start, goal)
				task.wait(0.02)
				if math.random() < World.PathFailRate then
					props(self).Status = Enum.PathStatus.NoPath
					waypoints = {}
					return
				end
				props(self).Status = Enum.PathStatus.Success
				waypoints = {}
				local delta = goal - start
				local n = math.max(1, math.ceil(delta.Magnitude / 8))
				for i = 1, n do
					table.insert(waypoints, {
						Position = start + delta * (i / n),
						Action = Enum.PathWaypointAction.Walk,
						Label = "",
					})
				end
			end,
			GetWaypoints = function()
				return table.clone(waypoints)
			end,
			CheckOcclusionAsync = function()
				return -1
			end,
		})
		return path
	end,
})

-- ---------------------------------------------------------------------------
-- DataStore en mémoire (avec sérialisation JSON pour détecter les valeurs invalides)
-- ---------------------------------------------------------------------------
World.DataStoreFailRate = 0
World.DataStores = {}
local function jsonRoundTrip(v)
	if v == nil then
		return nil
	end
	return serde.decode("json", serde.encode("json", v))
end
local function maybeFail(what)
	if math.random() < World.DataStoreFailRate then
		error("502: simulated DataStore failure (" .. what .. ")", 0)
	end
end
local function makeStore(name, ordered)
	local key = (ordered and "O:" or "D:") .. name
	if World.DataStores[key] then
		return World.DataStores[key].inst
	end
	local data = {}
	local inst = Instance.new(ordered and "OrderedDataStore" or "DataStore")
	inst.Name = name
	World.DataStores[key] = { inst = inst, data = data }
	Engine.AddMethods(inst, {
		GetAsync = function(_, k)
			task.wait(0.05)
			maybeFail("GetAsync")
			return jsonRoundTrip(data[k])
		end,
		SetAsync = function(_, k, v)
			task.wait(0.05)
			maybeFail("SetAsync")
			if ordered then
				assert(type(v) == "number" and v == math.floor(v), "OrderedDataStore values must be integers")
			end
			data[k] = jsonRoundTrip(v)
		end,
		UpdateAsync = function(_, k, fn)
			task.wait(0.05)
			maybeFail("UpdateAsync")
			local new = fn(jsonRoundTrip(data[k]), nil)
			if new ~= nil then
				if ordered then
					assert(type(new) == "number" and new == math.floor(new), "OrderedDataStore values must be integers")
				end
				data[k] = jsonRoundTrip(new)
			end
			return jsonRoundTrip(data[k])
		end,
		IncrementAsync = function(_, k, delta)
			task.wait(0.05)
			maybeFail("IncrementAsync")
			data[k] = (data[k] or 0) + (delta or 1)
			return data[k]
		end,
		RemoveAsync = function(_, k)
			local old = data[k]
			data[k] = nil
			return old
		end,
		GetSortedAsync = function(_, ascending, pageSize)
			task.wait(0.05)
			maybeFail("GetSortedAsync")
			local list = {}
			for k, v in data do
				table.insert(list, { key = k, value = v })
			end
			table.sort(list, function(a, b)
				if ascending then
					return a.value < b.value
				end
				return a.value > b.value
			end)
			local page = {}
			for i = 1, math.min(pageSize or 50, #list) do
				page[i] = list[i]
			end
			return {
				IsFinished = true,
				GetCurrentPage = function()
					return page
				end,
				AdvanceToNextPageAsync = function() end,
			}
		end,
	})
	return inst
end
Engine.AddMethods(DataStoreService, {
	GetDataStore = function(_, name)
		return makeStore(name, false)
	end,
	GetOrderedDataStore = function(_, name)
		return makeStore(name, true)
	end,
	GetGlobalDataStore = function()
		return makeStore("__global", false)
	end,
	GetRequestBudgetForRequestType = function()
		return 100
	end,
})

-- ---------------------------------------------------------------------------
-- Marketplace, Http, divers
-- ---------------------------------------------------------------------------
Engine.AddMethods(MarketplaceService, {
	UserOwnsGamePassAsync = function()
		return false
	end,
	PlayerOwnsAsset = function()
		return false
	end,
	PromptGamePassPurchase = function() end,
	PromptProductPurchase = function() end,
	GetProductInfo = function(_, id)
		return { Name = "Product " .. tostring(id), PriceInRobux = 0 }
	end,
})

local guidCounter = 0
Engine.AddMethods(HttpService, {
	JSONEncode = function(_, v)
		return serde.encode("json", v)
	end,
	JSONDecode = function(_, s)
		return serde.decode("json", s)
	end,
	GenerateGUID = function(_, braces)
		guidCounter += 1
		local id = string.format("00000000-0000-0000-0000-%012d", guidCounter)
		return braces == false and id or "{" .. id .. "}"
	end,
	UrlEncode = function(_, s)
		return s
	end,
})

Engine.AddMethods(PhysicsService, {
	RegisterCollisionGroup = function() end,
	CollisionGroupSetCollidable = function() end,
	CollisionGroupsAreCollidable = function()
		return true
	end,
	IsCollisionGroupRegistered = function()
		return true
	end,
	UnregisterCollisionGroup = function() end,
})

Engine.AddMethods(TextService, {
	GetTextSize = function(_, text, size)
		return roblox.Vector2.new(#text * size * 0.55, size)
	end,
})

Engine.AddMethods(BadgeService, {
	AwardBadge = function()
		return true
	end,
	UserHasBadgeAsync = function()
		return false
	end,
})

Engine.AddMethods(SoundService, {
	PlayLocalSound = function() end,
})

Engine.AddMethods(Lighting, {
	GetMinutesAfterMidnight = function()
		return (props(Lighting).ClockTime or 14) * 60
	end,
	SetMinutesAfterMidnight = function(_, m)
		props(Lighting).ClockTime = m / 60
	end,
})

Engine.AddMethods(TeamsService, {
	GetTeams = function(self)
		return self:GetChildren()
	end,
})

Engine.AddMethods(GuiService, {
	GetGuiInset = function()
		return roblox.Vector2.new(0, 36), roblox.Vector2.new(0, 0)
	end,
	IsTenFootInterface = function()
		return false
	end,
})

Engine.AddMethods(StarterGui, {
	SetCore = function() end,
	GetCore = function()
		return nil
	end,
	SetCoreGuiEnabled = function() end,
	GetCoreGuiEnabled = function()
		return true
	end,
})

-- ---------------------------------------------------------------------------
-- Entrées client
-- ---------------------------------------------------------------------------
World.Input = { TouchEnabled = false, KeyboardEnabled = true, MouseEnabled = true, GamepadEnabled = false }
rawset(UserInputService, "_get", function(_, key)
	return World.Input[key]
end)
props(UserInputService).MouseBehavior = Enum.MouseBehavior.Default
props(UserInputService).MouseIconEnabled = true
local keysDown = {}
Engine.AddMethods(UserInputService, {
	GetLastInputType = function()
		return World.Input.TouchEnabled and Enum.UserInputType.Touch or Enum.UserInputType.Keyboard
	end,
	IsKeyDown = function(_, key)
		return keysDown[key] == true
	end,
	GetKeysPressed = function()
		return {}
	end,
	GetMouseLocation = function()
		return roblox.Vector2.new(640, 360)
	end,
	GetConnectedGamepads = function()
		return {}
	end,
	GetFocusedTextBox = function()
		return nil
	end,
	IsGamepadButtonDown = function()
		return false
	end,
	GetNavigationGamepads = function()
		return {}
	end,
})

local boundActions = {}
World.BoundActions = boundActions
Engine.AddMethods(ContextActionService, {
	BindAction = function(_, name, fn, createTouchButton, ...)
		boundActions[name] = { fn = fn, ctx = Engine.CurrentCtx(), inputs = { ... }, touch = createTouchButton }
	end,
	BindActionAtPriority = function(_, name, fn, createTouchButton, _priority, ...)
		boundActions[name] = { fn = fn, ctx = Engine.CurrentCtx(), inputs = { ... }, touch = createTouchButton }
	end,
	UnbindAction = function(_, name)
		boundActions[name] = nil
	end,
	SetTitle = function() end,
	SetImage = function() end,
	SetPosition = function() end,
	SetDescription = function() end,
	GetButton = function()
		return nil
	end,
})

-- Simule une touche pour un joueur client
function World.PressKey(player, keyCode, isDown)
	keysDown[keyCode] = isDown
	local input = {
		KeyCode = keyCode,
		UserInputType = Enum.UserInputType.Keyboard,
		UserInputState = isDown and Enum.UserInputState.Begin or Enum.UserInputState.End,
		Position = Vector3.zero,
		Delta = Vector3.zero,
	}
	local sig = isDown and UserInputService.InputBegan or UserInputService.InputEnded
	sig:FireFiltered(player, input, false)
	for name, action in boundActions do
		if action.ctx == player and table.find(action.inputs, keyCode) then
			Engine.SpawnIn(player, action.fn, name, input.UserInputState, input)
		end
	end
end

-- ---------------------------------------------------------------------------
-- Personnages
-- ---------------------------------------------------------------------------
local function newPart(name, size, cf, parent, transparency)
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cf
	p.Transparency = transparency or 0
	p.Parent = parent
	return p
end

-- Apparence factice réaliste : peau, haut, bas, cheveux (pour les rendus).
local SKINS = {
	Color3.fromRGB(255, 220, 185), Color3.fromRGB(234, 184, 146), Color3.fromRGB(204, 142, 105),
	Color3.fromRGB(160, 105, 72), Color3.fromRGB(112, 72, 50), Color3.fromRGB(253, 214, 76),
}
local SHIRTS = {
	Color3.fromRGB(40, 110, 220), Color3.fromRGB(220, 50, 70), Color3.fromRGB(40, 40, 46),
	Color3.fromRGB(245, 245, 245), Color3.fromRGB(46, 170, 96), Color3.fromRGB(250, 160, 40),
	Color3.fromRGB(160, 80, 210), Color3.fromRGB(80, 200, 230), Color3.fromRGB(255, 120, 170),
}
local PANTS = {
	Color3.fromRGB(40, 60, 120), Color3.fromRGB(30, 30, 36), Color3.fromRGB(90, 96, 110),
	Color3.fromRGB(120, 86, 60), Color3.fromRGB(60, 100, 70), Color3.fromRGB(200, 200, 205),
}
local HAIRS = {
	Color3.fromRGB(40, 28, 22), Color3.fromRGB(90, 56, 30), Color3.fromRGB(230, 190, 100),
	Color3.fromRGB(20, 20, 24), Color3.fromRGB(180, 70, 40), Color3.fromRGB(240, 120, 180),
}
local function nameSeed(name)
	local h = 7
	for i = 1, #name do
		h = (h * 31 + string.byte(name, i)) % 2147483647
	end
	return h
end
local function pickFrom(list, seed, salt)
	return list[((seed // salt) % #list) + 1]
end

local function colorRig(model, colors)
	for _, part in model:GetChildren() do
		if part:IsA("BasePart") then
			local n = props(part).Name
			local c
			if n == "Head" or string.find(n, "Hand") or string.find(n, "Arm") then
				c = colors.Skin
			elseif string.find(n, "Torso") then
				c = colors.Shirt
			elseif string.find(n, "Leg") or string.find(n, "Foot") then
				c = colors.Pants
			end
			if string.find(n, "UpperArm") or n == "Left Arm" or n == "Right Arm" then
				-- Manches courtes : haut du bras de la couleur du haut
				c = colors.Sleeves and colors.Shirt or colors.Skin
			end
			if c then
				props(part).Color = c
			end
		end
	end
end
World.ColorRig = colorRig

local function addHair(model, head, color, style)
	local acc = Instance.new("Accessory")
	acc.Name = "Hair"
	local hp = props(head)
	local s = hp.Size
	local handle = newPart("Handle", Vector3.new(s.X * 0.62, s.Y * 0.32, s.Z * 1.08), hp.CFrame * CFrame.new(0, s.Y * 0.52, 0.04), acc)
	props(handle).Color = color
	props(handle).CanCollide = false
	if style == 2 then
		local back = newPart("Handle2", Vector3.new(s.X * 0.62, s.Y * 0.7, s.Z * 0.3), hp.CFrame * CFrame.new(0, s.Y * 0.18, s.Z * 0.42), acc)
		props(back).Color = color
		props(back).CanCollide = false
	end
	acc.Parent = model
end

-- Rig R6 (Head, Torso, bras, jambes) ou R15 simplifié, centré sur at.
local function buildRig(name, at, rigType, colors)
	local model = Instance.new("Model")
	model.Name = name
	local base = CFrame.new(at)
	local root = newPart("HumanoidRootPart", Vector3.new(2, 2, 1), base, model, 1)
	local head
	if rigType == "R15" then
		head = newPart("Head", Vector3.new(1.2, 1.2, 1.2), base * CFrame.new(0, 2.1, 0), model)
		newPart("UpperTorso", Vector3.new(2, 1.6, 1), base * CFrame.new(0, 0.6, 0), model)
		newPart("LowerTorso", Vector3.new(2, 0.4, 1), base * CFrame.new(0, -0.4, 0), model)
		newPart("LeftUpperArm", Vector3.new(1, 1.2, 1), base * CFrame.new(-1.5, 0.6, 0), model)
		newPart("RightUpperArm", Vector3.new(1, 1.2, 1), base * CFrame.new(1.5, 0.6, 0), model)
		newPart("LeftLowerArm", Vector3.new(1, 0.8, 1), base * CFrame.new(-1.5, -0.4, 0), model)
		newPart("RightLowerArm", Vector3.new(1, 0.8, 1), base * CFrame.new(1.5, -0.4, 0), model)
		newPart("LeftUpperLeg", Vector3.new(1, 1.2, 1), base * CFrame.new(-0.5, -1.2, 0), model)
		newPart("RightUpperLeg", Vector3.new(1, 1.2, 1), base * CFrame.new(0.5, -1.2, 0), model)
		newPart("LeftLowerLeg", Vector3.new(1, 1, 1), base * CFrame.new(-0.5, -2.4, 0), model)
		newPart("RightLowerLeg", Vector3.new(1, 1, 1), base * CFrame.new(0.5, -2.4, 0), model)
	else
		head = newPart("Head", Vector3.new(2, 1, 1), base * CFrame.new(0, 1.5, 0), model)
		newPart("Torso", Vector3.new(2, 2, 1), base, model)
		newPart("Left Arm", Vector3.new(1, 2, 1), base * CFrame.new(-1.5, 0, 0), model)
		newPart("Right Arm", Vector3.new(1, 2, 1), base * CFrame.new(1.5, 0, 0), model)
		newPart("Left Leg", Vector3.new(1, 2, 1), base * CFrame.new(-0.5, -2, 0), model)
		newPart("Right Leg", Vector3.new(1, 2, 1), base * CFrame.new(0.5, -2, 0), model)
	end
	if colors then
		colorRig(model, colors)
		if colors.Hair then
			addHair(model, head, colors.Hair, colors.HairStyle)
		end
	end
	local humanoid = Instance.new("Humanoid")
	humanoid.Parent = model
	props(humanoid).RigType = rigType == "R15" and Enum.HumanoidRigType.R15 or Enum.HumanoidRigType.R6
	local animator = Instance.new("Animator")
	animator.Parent = humanoid
	Engine.AddMethods(animator, {
		LoadAnimation = function(_, anim)
			return humanoid:LoadAnimation(anim)
		end,
		GetPlayingAnimationTracks = function()
			return {}
		end,
	})
	props(model).PrimaryPart = root
	return model, humanoid
end

-- Couleurs d'avatar déterministes à partir du nom
function World.AvatarColors(name)
	local seed = nameSeed(name)
	return {
		Skin = pickFrom(SKINS, seed, 1),
		Shirt = pickFrom(SHIRTS, seed, 7),
		Pants = pickFrom(PANTS, seed, 53),
		Hair = pickFrom(HAIRS, seed, 331),
		HairStyle = (seed // 997) % 3,
		Sleeves = (seed // 13) % 2 == 0,
	}
end
World.BuildRig = buildRig

-- AnimationTrack : méthodes Play/Stop
Engine._classHooks.AnimationTrack = function(track)
	Engine.AddMethods(track, {
		Play = function(self, fade, weight, speed)
			props(self).IsPlaying = true
			if speed then
				props(self).Speed = speed
			end
		end,
		Stop = function(self)
			props(self).IsPlaying = false
			self.Stopped:Fire()
		end,
		AdjustSpeed = function(self, s)
			props(self).Speed = s
		end,
		AdjustWeight = function() end,
		GetMarkerReachedSignal = function()
			return Signal.new("Marker")
		end,
	})
end

local function findSpawn()
	for _, d in workspace:GetDescendants() do
		if rawget(d, "_class") == "SpawnLocation" then
			return d
		end
	end
	return nil
end

Engine.AddMethods(Players, {
	GetPlayers = function(self)
		local out = {}
		for _, c in self:GetChildren() do
			if rawget(c, "_class") == "Player" then
				table.insert(out, c)
			end
		end
		return out
	end,
	GetPlayerFromCharacter = function(self, model)
		if model == nil then
			return nil
		end
		for _, p in self:GetPlayers() do
			if props(p).Character == model then
				return p
			end
		end
		return nil
	end,
	GetPlayerByUserId = function(self, id)
		for _, p in self:GetPlayers() do
			if props(p).UserId == id then
				return p
			end
		end
		return nil
	end,
	CreateHumanoidModelFromDescription = function(_, desc, rigType)
		assert(desc and desc:IsA("HumanoidDescription"), "CreateHumanoidModelFromDescription expects a HumanoidDescription")
		local dp = props(desc)
		local colors = {
			Skin = dp.HeadColor or Color3.fromRGB(255, 220, 185),
			Shirt = dp.TorsoColor or Color3.fromRGB(40, 110, 220),
			Pants = dp.LeftLegColor or Color3.fromRGB(40, 60, 120),
		}
		local r15 = rigType == nil or rigType == Enum.HumanoidRigType.R15
		local model, humanoid = buildRig("NPC", Vector3.new(0, 3, 0), r15 and "R15" or "R6", colors)
		-- Bras : couleur de la description
		for _, n in { "Left Arm", "Right Arm", "LeftUpperArm", "RightUpperArm", "LeftLowerArm", "RightLowerArm" } do
			local part = model:FindFirstChild(n)
			if part then
				props(part).Color = dp.LeftArmColor or colors.Skin
			end
		end
		humanoid:ApplyDescription(desc)
		return model
	end,
	GetHumanoidDescriptionFromUserId = function()
		return Instance.new("HumanoidDescription")
	end,
	GetNameFromUserIdAsync = function(_, id)
		task.wait(0.02)
		return "User" .. tostring(id)
	end,
	GetUserThumbnailAsync = function()
		return "rbxasset://textures/ui/GuiImagePlaceholder.png", true
	end,
})
rawset(Players, "_get", function(_, key)
	if key == "LocalPlayer" then
		local ctx = Engine.CurrentCtx()
		if ctx ~= "server" then
			return ctx
		end
		return nil
	end
	return nil
end)

local userIdCounter = 1000
World.ClientPlayers = {}

local function loadCharacter(player)
	local old = props(player).Character
	if old then
		player.CharacterRemoving:Fire(old)
		old:Destroy()
	end
	local spawn = findSpawn()
	local at = spawn and (props(spawn).CFrame.Position + Vector3.new(0, Engine.GroundY + 3 - props(spawn).CFrame.Position.Y, 0)) or Vector3.new(0, Engine.GroundY + 3, 0)
	local model, humanoid = buildRig(props(player).Name, at, "R6", World.AvatarColors(props(player).Name))
	props(player).Character = model
	model.Parent = workspace
	humanoid.Died:Connect(function()
		if props(Players).CharacterAutoLoads then
			task.delay(props(Players).RespawnTime or 5, function()
				if props(player).Parent == Players and props(player).Character == model then
					loadCharacter(player)
				end
			end)
		end
	end)
	player.CharacterAdded:Fire(model)
	player.CharacterAppearanceLoaded:Fire(model)
end

function World.AddPlayer(name, opts)
	opts = opts or {}
	userIdCounter += 1
	local player = Instance.new("Player")
	props(player).Name = name
	props(player).DisplayName = opts.DisplayName or name
	props(player).UserId = opts.UserId or userIdCounter
	props(player).Neutral = true
	props(player).AccountAge = 100
	props(player).MembershipType = Enum.MembershipType.None
	props(player).Character = nil
	local gui = Instance.new("PlayerGui")
	gui.Name = "PlayerGui"
	gui.Parent = player
	local backpack = Instance.new("Backpack")
	backpack.Name = "Backpack"
	backpack.Parent = player
	local scripts = Instance.new("PlayerScripts")
	scripts.Name = "PlayerScripts"
	scripts.Parent = player

	Engine.AddMethods(player, {
		LoadCharacter = function(self)
			assert(Engine.CurrentCtx() == "server", "LoadCharacter can only be called by the server")
			loadCharacter(self)
		end,
		Kick = function(self, msg)
			print("[sim] Kick " .. props(self).Name .. ": " .. tostring(msg))
			World.RemovePlayer(self)
		end,
		Move = function(self, dir, relative)
			local char = props(self).Character
			local h = char and char:FindFirstChildOfClass("Humanoid")
			if h then
				h:Move(dir, relative)
			end
		end,
		GetMouse = function()
			return { Hit = CFrame.new(), Target = nil, X = 0, Y = 0, Icon = "" }
		end,
		IsInGroup = function()
			return false
		end,
		GetRankInGroup = function()
			return 0
		end,
		DistanceFromCharacter = function(self, pos)
			local char = props(self).Character
			local root = char and char:FindFirstChild("HumanoidRootPart")
			return root and (props(root).CFrame.Position - pos).Magnitude or 0
		end,
		GetNetworkPing = function()
			return 0.05
		end,
		GetJoinData = function()
			return {}
		end,
		SetAttribute = Engine.InstanceMT.__index(player, "SetAttribute"),
	})

	-- Module de contrôle factice (PlayerModule) pour les scripts client
	if opts.client then
		local pm = Instance.new("ModuleScript")
		pm.Name = "PlayerModule"
		local controls = {
			moveVector = Vector3.zero,
			enabled = true,
		}
		controls.moveFunction = function(p, dir, relative)
			p:Move(dir, relative)
		end
		function controls:GetMoveVector()
			return self.moveVector
		end
		function controls:Enable(on)
			self.enabled = on ~= false
		end
		function controls:Disable()
			self.enabled = false
		end
		function controls:GetActiveController()
			return self
		end
		local playerModule = {
			GetControls = function()
				return controls
			end,
			GetCameras = function()
				return {}
			end,
		}
		rawset(pm, "_builtin", playerModule)
		pm.Parent = scripts
		World.ClientPlayers[player] = { controls = controls }
		-- Le ControlModule appelle moveFunction à chaque image
		Engine.RenderBindings["__ControlModule_" .. name] = {
			ctx = player,
			fn = function()
				if controls.enabled and props(player).Character then
					controls.moveFunction(player, controls.moveVector, true)
				end
			end,
		}
	end

	player.Parent = Players
	Players.PlayerAdded:Fire(player)

	if opts.client then
		World.StartClient(player)
	end
	if props(Players).CharacterAutoLoads then
		Engine.SpawnIn("server", function()
			task.wait(0.1)
			if props(player).Parent == Players then
				loadCharacter(player)
			end
		end)
	end
	return player
end

function World.SetMoveVector(player, v)
	local c = World.ClientPlayers[player]
	if c then
		c.controls.moveVector = v
	end
end

function World.RemovePlayer(player)
	Players.PlayerRemoving:Fire(player)
	local char = props(player).Character
	if char then
		char:Destroy()
	end
	for name, b in Engine.RenderBindings do
		if b.ctx == player then
			Engine.RenderBindings[name] = nil
		end
	end
	player.Parent = nil
end

-- ---------------------------------------------------------------------------
-- Chargement du projet (sourcemap Rojo) et exécution des scripts
-- ---------------------------------------------------------------------------
local requireCache = {} -- [ctxKey][module] = result
-- Sources préchargées : fs.readFile de Lune est asynchrone et suspendrait
-- nos coroutines au profit du planificateur de Lune.
local sourceCache = {}
local function readSource(path)
	local src = sourceCache[path]
	assert(src, "Source non préchargée : " .. tostring(path))
	return src
end
local loading = {}

local GLOBAL_NAMES = {
	"print", "error", "assert", "pcall", "xpcall", "ipairs", "pairs", "next", "select", "type", "tostring",
	"tonumber", "rawget", "rawset", "rawequal", "rawlen", "setmetatable", "getmetatable", "unpack",
	"table", "string", "math", "coroutine", "utf8", "bit32", "buffer", "debug", "newproxy", "gcinfo",
}

-- Content (référence vers un objet ou un asset)
local ContentType = {
	none = { _none = true },
	fromObject = function(object)
		return { _object = object }
	end,
	fromUri = function(uri)
		return { _uri = uri }
	end,
	fromAssetId = function(id)
		return { _uri = "rbxassetid://" .. tostring(id) }
	end,
}

local datatypes = {
	Content = ContentType,
	Vector3 = roblox.Vector3,
	Vector2 = roblox.Vector2,
	CFrame = roblox.CFrame,
	Color3 = roblox.Color3,
	UDim = roblox.UDim,
	UDim2 = roblox.UDim2,
	Enum = roblox.Enum,
	NumberSequence = roblox.NumberSequence,
	NumberSequenceKeypoint = roblox.NumberSequenceKeypoint,
	ColorSequence = roblox.ColorSequence,
	ColorSequenceKeypoint = roblox.ColorSequenceKeypoint,
	NumberRange = roblox.NumberRange,
	Ray = roblox.Ray,
	Region3 = roblox.Region3,
	PhysicalProperties = roblox.PhysicalProperties,
	Font = roblox.Font,
	Rect = roblox.Rect,
	Faces = roblox.Faces,
	Axes = roblox.Axes,
	BrickColor = Engine.Types.BrickColor,
	TweenInfo = Engine.Types.TweenInfo,
	RaycastParams = Engine.Types.RaycastParams,
	OverlapParams = Engine.Types.OverlapParams,
	Random = Engine.Types.Random,
	DateTime = Engine.Types.DateTime,
}

local function ctxKey(ctx)
	return ctx == "server" and "server" or ctx
end

local InstanceAPI = {
	new = function(className, parent)
		return Instance.new(className, parent)
	end,
}

local makeEnv

local function requireModule(module)
	assert(Engine.IsInstance(module) and module:IsA("ModuleScript"), "require expects a ModuleScript, got " .. tostring(module))
	local builtin = rawget(module, "_builtin")
	if builtin then
		return builtin
	end
	local key = ctxKey(Engine.CurrentCtx())
	requireCache[key] = requireCache[key] or {}
	local cache = requireCache[key]
	if cache[module] ~= nil then
		return cache[module]
	end
	if loading[module] then
		error("Recursive require detected: " .. module:GetFullName())
	end
	local path = rawget(module, "_source")
	assert(path, "ModuleScript without source: " .. module:GetFullName())
	loading[module] = true
	local chunk = luau.load(readSource(path), { debugName = path, environment = makeEnv(module) })
	local ok, result = pcall(chunk)
	loading[module] = nil
	if not ok then
		error("Requested module experienced an error while loading: " .. module:GetFullName() .. "\n" .. tostring(result), 0)
	end
	cache[module] = result
	return result
end

World.Require = function(module)
	return requireModule(module)
end

local warnFn = function(...)
	local parts = {}
	for i = 1, select("#", ...) do
		parts[i] = tostring((select(i, ...)))
	end
	local msg = table.concat(parts, " ")
	table.insert(World.Warnings, msg)
	if not Engine.Quiet then
		print("\27[33m[warn] " .. msg .. "\27[0m")
	end
end

local printFn = function(...)
	if not Engine.Quiet then
		print(...)
	end
end

makeEnv = function(scriptInst)
	local env = {}
	for _, name in GLOBAL_NAMES do
		env[name] = (getfenv(0) :: any)[name]
	end
	env.print = printFn
	env.warn = warnFn
	env.typeof = Engine.typeof
	for k, v in datatypes do
		env[k] = v
	end
	env.Instance = InstanceAPI
	env.game = game
	env.Game = game
	env.workspace = workspace
	env.Workspace = workspace
	env.script = scriptInst
	env.require = requireModule
	env.task = task
	env.tick = function()
		return 1700000000 + Engine.Now()
	end
	env.time = function()
		return Engine.Now()
	end
	env.elapsedTime = env.time
	env.wait = task.wait
	env.delay = task.delay
	env.spawn = task.spawn
	env.os = {
		clock = function()
			return Engine.Now()
		end,
		time = function()
			return math.floor(1700000000 + Engine.Now())
		end,
		date = os.date,
		difftime = os.difftime,
	}
	env.shared = World.Shared
	env._G = env
	return env
end
World.Shared = {}

local function nodeToInstance(node, parent)
	local inst
	local existing = parent and parent:FindFirstChild(node.name)
	if existing and (existing.ClassName == node.className or node.className == "Folder") then
		inst = existing
	else
		inst = Instance.new(node.className)
		inst.Name = node.name
	end
	if node.filePaths then
		for _, p in node.filePaths do
			if string.match(p, "%.luau?$") then
				rawset(inst, "_source", p)
				sourceCache[p] = sourceCache[p] or fs.readFile(p)
			end
		end
	end
	for _, child in node.children or {} do
		nodeToInstance(child, inst)
	end
	if parent and inst.Parent ~= parent then
		inst.Parent = parent
	end
	return inst
end

function World.LoadSourcemap(path)
	local sm = serde.decode("json", fs.readFile(path))
	for _, child in sm.children or {} do
		local s = services[child.className]
		if s then
			for _, sub in child.children or {} do
				nodeToInstance(sub, s)
			end
		else
			nodeToInstance(child, game)
		end
	end
end

local function runScript(scriptInst, ctx)
	local path = rawget(scriptInst, "_source")
	if not path then
		return
	end
	local chunk = luau.load(readSource(path), { debugName = path, environment = makeEnv(scriptInst) })
	Engine.SpawnIn(ctx, chunk)
end

function World.StartServer()
	for _, d in ServerScriptService:GetDescendants() do
		if d.ClassName == "Script" then
			runScript(d, "server")
		end
	end
	for _, d in workspace:GetDescendants() do
		if d.ClassName == "Script" then
			runScript(d, "server")
		end
	end
end

function World.StartClient(player)
	local scripts = player:FindFirstChild("PlayerScripts")
	for _, child in StarterPlayerScripts:GetChildren() do
		child:Clone().Parent = scripts
	end
	local gui = player:FindFirstChild("PlayerGui")
	for _, child in StarterGui:GetChildren() do
		local c = child:Clone()
		if c then
			c.Parent = gui
		end
	end
	for _, d in scripts:GetDescendants() do
		if d.ClassName == "LocalScript" then
			runScript(d, player)
		end
	end
	for _, d in gui:GetDescendants() do
		if d.ClassName == "LocalScript" then
			runScript(d, player)
		end
	end
end

function World.Shutdown()
	for _, b in World.BindToClose do
		Engine.SpawnIn(b.ctx, b.fn)
	end
	Engine.Advance(5)
end

return World

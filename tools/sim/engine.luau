--!nocheck
--[[
	engine.luau : mini-moteur "faux Roblox" pour Lune.
	Objectif : exécuter le code serveur ET client du jeu hors de Studio pour
	attraper les erreurs d'exécution, simuler des manches entières en temps
	virtuel, et exporter la géométrie construite (rendus 3D).

	Ce n'est PAS une réimplémentation de Roblox : physique très simplifiée
	(sol plat, déplacement des Humanoid en ligne droite, balistique simple),
	réplication instantanée (serveur et clients partagent les mêmes objets).
]]

local robloxLib = require("@lune/roblox")

-- Correctif : CFrame.lookAt de Lune 0.8.9 renvoie une orientation miroir
-- (composante Z du LookVector inversée). On le remplace par un calcul exact
-- (même convention que Roblox : -Z vers la cible, Y vers le haut).
local function lookAt(pos, target, up)
	local V3 = robloxLib.Vector3
	local upVector = up or V3.new(0, 1, 0)
	local delta = target - pos
	if delta.Magnitude < 1e-9 then
		return robloxLib.CFrame.new(pos.X, pos.Y, pos.Z)
	end
	local look = delta.Unit
	local right = look:Cross(upVector)
	if right.Magnitude < 1e-6 then
		right = look:Cross(V3.new(0, 0, 1))
		if right.Magnitude < 1e-6 then
			right = look:Cross(V3.new(1, 0, 0))
		end
	end
	right = right.Unit
	local up2 = right:Cross(look).Unit
	local b = -look
	return robloxLib.CFrame.new(pos.X, pos.Y, pos.Z, right.X, up2.X, b.X, right.Y, up2.Y, b.Y, right.Z, up2.Z, b.Z)
end
local CFrameLib = setmetatable({ lookAt = lookAt }, { __index = robloxLib.CFrame })
local roblox = setmetatable({ CFrame = CFrameLib }, { __index = robloxLib })
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local serde = require("@lune/serde")

local Engine = {}

local Vector3, CFrame, Color3 = roblox.Vector3, roblox.CFrame, roblox.Color3
local Enum = roblox.Enum

-- ---------------------------------------------------------------------------
-- Contexte d'exécution ("server" ou un Player pour un client) et ordonnanceur
-- ---------------------------------------------------------------------------
local now = 0
local currentCtx = "server"
local threadCtx = setmetatable({}, { __mode = "k" })
local waiting = {} -- { {co=, at=, args=} }
local deferred = {}
local cancelled = setmetatable({}, { __mode = "k" })
Engine.Errors = {}
Engine.Logs = {}
Engine.Quiet = false

local function ctxName(ctx)
	if ctx == "server" then
		return "server"
	end
	return "client:" .. tostring(ctx and rawget(ctx, "_props") and ctx._props.Name or "?")
end

local seenErrors = {}
local function reportError(co, err)
	local key = tostring(err)
	if seenErrors[key] then
		seenErrors[key] += 1
		return
	end
	seenErrors[key] = 1
	local trace = debug.traceback(co, tostring(err))
	table.insert(Engine.Errors, "[" .. ctxName(threadCtx[co]) .. "] " .. trace)
	print("\27[31m[ERROR " .. ctxName(threadCtx[co]) .. "] " .. trace .. "\27[0m")
end

local function resume(co, ...)
	if cancelled[co] or coroutine.status(co) == "dead" then
		return
	end
	local prev = currentCtx
	currentCtx = threadCtx[co] or "server"
	local ok, err = coroutine.resume(co, ...)
	currentCtx = prev
	if not ok then
		reportError(co, err)
	end
end

local function spawnIn(ctx, fn, ...)
	local co = type(fn) == "thread" and fn or coroutine.create(fn)
	threadCtx[co] = threadCtx[co] or ctx
	resume(co, ...)
	return co
end
Engine.SpawnIn = spawnIn

function Engine.Now()
	return now
end

function Engine.CurrentCtx()
	return currentCtx
end

local task = {}
function task.spawn(fn, ...)
	return spawnIn(currentCtx, fn, ...)
end
function task.defer(fn, ...)
	local co = type(fn) == "thread" and fn or coroutine.create(fn)
	threadCtx[co] = threadCtx[co] or currentCtx
	table.insert(deferred, { co = co, args = table.pack(...) })
	return co
end
function task.delay(t, fn, ...)
	local co = coroutine.create(fn)
	threadCtx[co] = currentCtx
	table.insert(waiting, { co = co, at = now + (t or 0), args = table.pack(...) })
	return co
end
function task.wait(t)
	local co = coroutine.running()
	local start = now
	table.insert(waiting, { co = co, at = now + math.max(t or 0, 1 / 60), args = nil, start = start })
	coroutine.yield()
	return now - start
end
function task.cancel(co)
	cancelled[co] = true
end
function task.synchronize() end
function task.desynchronize() end
Engine.task = task

-- ---------------------------------------------------------------------------
-- Signaux
-- ---------------------------------------------------------------------------
local Signal = {}
Signal.__index = Signal

function Signal.new(name)
	return setmetatable({ _conns = {}, _name = name, _waiters = {} }, Signal)
end

function Signal:Connect(fn)
	local conn = { Connected = true, _fn = fn, _ctx = currentCtx, _signal = self }
	function conn.Disconnect(c)
		c.Connected = false
		local i = table.find(self._conns, c)
		if i then
			table.remove(self._conns, i)
		end
	end
	conn.disconnect = conn.Disconnect
	table.insert(self._conns, conn)
	return conn
end
Signal.connect = Signal.Connect

function Signal:Once(fn)
	local conn
	conn = self:Connect(function(...)
		conn:Disconnect()
		fn(...)
	end)
	return conn
end

function Signal:Wait()
	local co = coroutine.running()
	table.insert(self._waiters, co)
	return coroutine.yield()
end

-- filterCtx : si fourni, seuls les abonnés de ce contexte reçoivent l'appel
function Signal:FireFiltered(filterCtx, ...)
	local conns = table.clone(self._conns)
	for _, conn in conns do
		if conn.Connected and (filterCtx == nil or conn._ctx == filterCtx) then
			spawnIn(conn._ctx, conn._fn, ...)
		end
	end
	local waiters = self._waiters
	self._waiters = {}
	for _, co in waiters do
		if filterCtx == nil or threadCtx[co] == filterCtx then
			resume(co, ...)
		else
			table.insert(self._waiters, co)
		end
	end
end

function Signal:Fire(...)
	self:FireFiltered(nil, ...)
end

function Signal:FireClients(...)
	local conns = table.clone(self._conns)
	for _, conn in conns do
		if conn.Connected and conn._ctx ~= "server" then
			spawnIn(conn._ctx, conn._fn, ...)
		end
	end
end

function Signal:DisconnectAll()
	for _, c in self._conns do
		c.Connected = false
	end
	self._conns = {}
end
Engine.Signal = Signal

-- ---------------------------------------------------------------------------
-- Classes et valeurs par défaut
-- ---------------------------------------------------------------------------
local SUPER = {
	Part = "BasePart",
	SpawnLocation = "Part",
	WedgePart = "BasePart",
	CornerWedgePart = "BasePart",
	TrussPart = "BasePart",
	MeshPart = "BasePart",
	UnionOperation = "BasePart",
	BasePart = "PVInstance",
	Model = "PVInstance",
	Workspace = "Model",
	PVInstance = "Instance",
	Frame = "GuiObject",
	TextLabel = "GuiObject",
	TextButton = "GuiButton",
	ImageButton = "GuiButton",
	GuiButton = "GuiObject",
	ImageLabel = "GuiObject",
	TextBox = "GuiObject",
	ScrollingFrame = "GuiObject",
	CanvasGroup = "GuiObject",
	ViewportFrame = "GuiObject",
	GuiObject = "GuiBase2d",
	ScreenGui = "LayerCollector",
	SurfaceGui = "LayerCollector",
	BillboardGui = "LayerCollector",
	LayerCollector = "GuiBase2d",
	GuiBase2d = "Instance",
	Weld = "JointInstance",
	Motor6D = "JointInstance",
	JointInstance = "Instance",
	LinearVelocity = "Constraint",
	VectorForce = "Constraint",
	AlignOrientation = "Constraint",
	AlignPosition = "Constraint",
	HingeConstraint = "Constraint",
	AngularVelocity = "Constraint",
	Constraint = "Instance",
	Script = "BaseScript",
	LocalScript = "BaseScript",
	BaseScript = "LuaSourceContainer",
	ModuleScript = "LuaSourceContainer",
	LuaSourceContainer = "Instance",
	PointLight = "Light",
	SpotLight = "Light",
	SurfaceLight = "Light",
	Light = "Instance",
	ObjectValue = "ValueBase",
	StringValue = "ValueBase",
	IntValue = "ValueBase",
	NumberValue = "ValueBase",
	BoolValue = "ValueBase",
	ValueBase = "Instance",
	UIListLayout = "UIGridStyleLayout",
	UIGridLayout = "UIGridStyleLayout",
	UIGridStyleLayout = "UILayout",
	UILayout = "UIComponent",
	UICorner = "UIComponent",
	UIStroke = "UIComponent",
	UIPadding = "UIComponent",
	UIGradient = "UIComponent",
	UIScale = "UIComponent",
	UITextSizeConstraint = "UIConstraint",
	UIAspectRatioConstraint = "UIConstraint",
	UISizeConstraint = "UIConstraint",
	UIConstraint = "UIComponent",
	UIComponent = "Instance",
	Decal = "FaceInstance",
	Texture = "Decal",
	FaceInstance = "Instance",
	Accessory = "Accoutrement",
	Accoutrement = "Instance",
	Shirt = "Clothing",
	Pants = "Clothing",
	Clothing = "Instance",
	Camera = "PVInstance",
}

local function isA(className, target)
	if target == "Instance" then
		return true
	end
	local c = className
	while c do
		if c == target then
			return true
		end
		c = SUPER[c]
	end
	return false
end

local GREY = Color3.fromRGB(163, 162, 165)
local function partDefaults()
	return {
		Size = Vector3.new(4, 1, 2),
		CFrame = CFrame.new(),
		Anchored = false,
		CanCollide = true,
		CanTouch = true,
		CanQuery = true,
		Transparency = 0,
		Reflectance = 0,
		Color = GREY,
		Material = Enum.Material.Plastic,
		Shape = Enum.PartType.Block,
		AssemblyLinearVelocity = Vector3.zero,
		AssemblyAngularVelocity = Vector3.zero,
		Massless = false,
		Locked = false,
		CastShadow = true,
		CollisionGroup = "Default",
		TopSurface = Enum.SurfaceType.Smooth,
		BottomSurface = Enum.SurfaceType.Smooth,
	}
end

local function guiDefaults()
	return {
		Visible = true,
		Size = roblox.UDim2.new(0, 100, 0, 100),
		Position = roblox.UDim2.new(),
		AnchorPoint = roblox.Vector2.new(0, 0),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BackgroundTransparency = 0,
		BorderSizePixel = 1,
		ZIndex = 1,
		LayoutOrder = 0,
		Rotation = 0,
		Text = "",
		TextColor3 = Color3.new(0, 0, 0),
		TextTransparency = 0,
		TextStrokeTransparency = 1,
		TextStrokeColor3 = Color3.new(0, 0, 0),
		TextScaled = false,
		TextSize = 14,
		TextWrapped = false,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextYAlignment = Enum.TextYAlignment.Center,
		Font = Enum.Font.Legacy,
		Image = "",
		ImageColor3 = Color3.new(1, 1, 1),
		ImageTransparency = 0,
		AutoButtonColor = true,
		ClipsDescendants = false,
		Active = false,
		Selectable = false,
		AbsoluteSize = roblox.Vector2.new(100, 100),
		AbsolutePosition = roblox.Vector2.new(0, 0),
	}
end

local DEFAULTS = {
	Part = partDefaults,
	SpawnLocation = function()
		local d = partDefaults()
		d.Neutral = true
		d.Duration = 10
		d.Enabled = true
		return d
	end,
	WedgePart = partDefaults,
	CornerWedgePart = partDefaults,
	MeshPart = partDefaults,
	TrussPart = partDefaults,
	Humanoid = function()
		return {
			WalkSpeed = 16,
			JumpPower = 50,
			JumpHeight = 7.2,
			UseJumpPower = true,
			Health = 100,
			MaxHealth = 100,
			HipHeight = 2,
			MoveDirection = Vector3.zero,
			PlatformStand = false,
			Sit = false,
			Jump = false,
			AutoRotate = true,
			AutoJumpEnabled = true,
			DisplayDistanceType = Enum.HumanoidDisplayDistanceType.Viewer,
			NameDisplayDistance = 100,
			HealthDisplayDistance = 100,
			DisplayName = "",
			FloorMaterial = Enum.Material.Plastic,
			RigType = Enum.HumanoidRigType.R15,
			BreakJointsOnDeath = true,
			RequiresNeck = true,
			EvaluateStateMachine = true,
		}
	end,
	Model = function()
		return { PrimaryPart = nil, WorldPivot = CFrame.new() }
	end,
	Highlight = function()
		return {
			Enabled = true,
			FillColor = Color3.new(1, 0, 0),
			OutlineColor = Color3.new(1, 1, 1),
			FillTransparency = 0.5,
			OutlineTransparency = 0,
			DepthMode = Enum.HighlightDepthMode.AlwaysOnTop,
		}
	end,
	Sound = function()
		return { Volume = 0.5, Playing = false, Looped = false, TimeLength = 1, PlaybackSpeed = 1, SoundId = "" }
	end,
	ParticleEmitter = function()
		return { Enabled = true, Rate = 20 }
	end,
	Camera = function()
		return {
			CFrame = CFrame.new(0, 20, 20),
			FieldOfView = 70,
			ViewportSize = roblox.Vector2.new(1280, 720),
			CameraType = Enum.CameraType.Custom,
		}
	end,
	ScreenGui = function()
		return { Enabled = true, ResetOnSpawn = true, IgnoreGuiInset = false, DisplayOrder = 0, AbsoluteSize = roblox.Vector2.new(1280, 720) }
	end,
	SurfaceGui = function()
		return { Enabled = true, Face = Enum.NormalId.Front, PixelsPerStud = 50, AbsoluteSize = roblox.Vector2.new(800, 600) }
	end,
	BillboardGui = function()
		return { Enabled = true, Size = roblox.UDim2.new(0, 200, 0, 50), StudsOffset = Vector3.zero, AlwaysOnTop = false, AbsoluteSize = roblox.Vector2.new(200, 50) }
	end,
	ProximityPrompt = function()
		return { Enabled = true, ActionText = "Interact", ObjectText = "", MaxActivationDistance = 10, HoldDuration = 0 }
	end,
	Attachment = function()
		return { CFrame = CFrame.new(), Position = Vector3.zero }
	end,
	HumanoidDescription = function()
		return {
			HeadColor = GREY,
			TorsoColor = GREY,
			LeftArmColor = GREY,
			RightArmColor = GREY,
			LeftLegColor = GREY,
			RightLegColor = GREY,
			HeightScale = 1,
			WidthScale = 1,
			DepthScale = 1,
			HeadScale = 1,
			BodyTypeScale = 0,
			ProportionScale = 0,
		}
	end,
}
for _, name in { "Frame", "TextLabel", "TextButton", "ImageLabel", "ImageButton", "TextBox", "ScrollingFrame", "CanvasGroup" } do
	DEFAULTS[name] = guiDefaults
end

-- Événements connus (créés à la demande)
local EVENTS = {
	ChildAdded = true,
	ChildRemoved = true,
	DescendantAdded = true,
	DescendantRemoving = true,
	AncestryChanged = true,
	Changed = true,
	Destroying = true,
	AttributeChanged = true,
	Touched = true,
	TouchEnded = true,
	MoveToFinished = true,
	Died = true,
	StateChanged = true,
	Running = true,
	Jumping = true,
	FreeFalling = true,
	HealthChanged = true,
	Activated = true,
	MouseButton1Click = true,
	MouseButton1Down = true,
	MouseButton1Up = true,
	MouseEnter = true,
	MouseLeave = true,
	InputBegan = true,
	InputEnded = true,
	InputChanged = true,
	FocusLost = true,
	OnServerEvent = true,
	OnClientEvent = true,
	Event = true,
	Triggered = true,
	PromptShown = true,
	PromptHidden = true,
	TriggerEnded = true,
	MouseClick = true,
	CharacterAdded = true,
	CharacterRemoving = true,
	CharacterAppearanceLoaded = true,
	Chatted = true,
	PlayerAdded = true,
	PlayerRemoving = true,
	Heartbeat = true,
	Stepped = true,
	RenderStepped = true,
	PreSimulation = true,
	PostSimulation = true,
	PreRender = true,
	Completed = true,
	Ended = true,
	Stopped = true,
	DidLoop = true,
	KeyframeReached = true,
	Played = true,
	JumpRequest = true,
	TouchStarted = true,
	LastInputTypeChanged = true,
	PromptGamePassPurchaseFinished = true,
	PromptProductPurchaseFinished = true,
	ReachedTarget = true,
	Blocked = true,
	Unblocked = true,
}

-- ---------------------------------------------------------------------------
-- Instances
-- ---------------------------------------------------------------------------
local Instance = {}
local Methods = {}
local allInstances = setmetatable({}, { __mode = "k" })
local InstanceMT = {}
Engine.InstanceMT = InstanceMT

local function isInstance(v)
	return type(v) == "table" and getmetatable(v) == InstanceMT
end
Engine.IsInstance = isInstance

local function fireProp(self, key, value)
	local ev = rawget(self, "_events")
	local ps = ev._propSignals and ev._propSignals[key]
	if ps then
		ps:Fire()
	end
	if ev.Changed then
		ev.Changed:Fire(key)
	end
end

local function getEvent(self, key)
	local ev = rawget(self, "_events")
	local s = ev[key]
	if not s then
		s = Signal.new(key)
		ev[key] = s
	end
	return s
end

local function descendants(self, out)
	for _, child in rawget(self, "_children") do
		table.insert(out, child)
		descendants(child, out)
	end
	return out
end

local setParent

InstanceMT.__index = function(self, key)
	local own = rawget(self, "_methods")
	if own and own[key] ~= nil then
		return own[key]
	end
	local m = Methods[key]
	if m then
		return m
	end
	local props = rawget(self, "_props")
	local v = props[key]
	if v ~= nil then
		return v
	end
	if key == "ClassName" then
		return rawget(self, "_class")
	end
	if key == "Position" and props.CFrame then
		return props.CFrame.Position
	end
	if key == "Orientation" and props.CFrame then
		local rx, ry, rz = props.CFrame:ToOrientation()
		return Vector3.new(math.deg(rx), math.deg(ry), math.deg(rz))
	end
	if key == "AssemblyMass" then
		local s = props.Size or Vector3.one
		return s.X * s.Y * s.Z * 0.7
	end
	if key == "Mass" then
		local s = props.Size or Vector3.one
		return s.X * s.Y * s.Z * 0.7
	end
	if EVENTS[key] then
		return getEvent(self, key)
	end
	-- Accès à un enfant par son nom
	for _, child in rawget(self, "_children") do
		if rawget(child, "_props").Name == key then
			return child
		end
	end
	local hook = rawget(self, "_get")
	if hook then
		return hook(self, key)
	end
	return nil
end

InstanceMT.__newindex = function(self, key, value)
	local props = rawget(self, "_props")
	if key == "Parent" then
		setParent(self, value)
		return
	end
	local set = rawget(self, "_set")
	if set and set(self, key, value) then
		fireProp(self, key, value)
		return
	end
	if key == "Position" and props.CFrame then
		local cf = props.CFrame
		props.CFrame = cf - cf.Position + value
		fireProp(self, "CFrame", props.CFrame)
		fireProp(self, "Position", value)
		return
	end
	if key == "Orientation" and props.CFrame then
		props.CFrame = CFrame.new(props.CFrame.Position) * CFrame.fromOrientation(math.rad(value.X), math.rad(value.Y), math.rad(value.Z))
		fireProp(self, "CFrame", props.CFrame)
		return
	end
	if props[key] == value then
		return
	end
	props[key] = value
	fireProp(self, key, value)
end

InstanceMT.__tostring = function(self)
	return rawget(self, "_props").Name
end

function Instance.new(className, parent)
	local defaults = DEFAULTS[className]
	local props = defaults and defaults() or {}
	props.Name = className
	props.Archivable = true
	local self = setmetatable({
		_class = className,
		_props = props,
		_children = {},
		_attributes = {},
		_events = {},
		_tags = {},
	}, InstanceMT)
	allInstances[self] = true
	if className == "Humanoid" then
		Engine._setupHumanoid(self)
	end
	if Engine._classHooks[className] then
		Engine._classHooks[className](self)
	end
	if parent then
		setParent(self, parent)
	end
	return self
end
Engine.Instance = Instance
Engine._classHooks = {}

-- Ajoute des méthodes propres à une instance (services)
function Engine.AddMethods(inst, methods)
	local own = rawget(inst, "_methods")
	if not own then
		own = {}
		rawset(inst, "_methods", own)
	end
	for k, v in methods do
		own[k] = v
	end
end

local function fireDescendantAdded(parent, inst)
	local p = parent
	while p do
		local ev = rawget(p, "_events")
		if ev.DescendantAdded then
			ev.DescendantAdded:Fire(inst)
		end
		p = rawget(p, "_props").Parent
	end
end

setParent = function(self, newParent)
	if rawget(self, "_destroyed") then
		error("The Parent property of " .. tostring(self) .. " is locked, current parent: NULL", 3)
	end
	local props = rawget(self, "_props")
	local old = props.Parent
	if old == newParent then
		return
	end
	if newParent ~= nil and not isInstance(newParent) then
		error("Parent must be an Instance", 3)
	end
	if old then
		local list = rawget(old, "_children")
		local i = table.find(list, self)
		if i then
			table.remove(list, i)
		end
		local p = old
		while p do
			local ev = rawget(p, "_events")
			if ev.DescendantRemoving then
				ev.DescendantRemoving:Fire(self)
			end
			p = rawget(p, "_props").Parent
		end
		if rawget(old, "_events").ChildRemoved then
			rawget(old, "_events").ChildRemoved:Fire(self)
		end
	end
	props.Parent = newParent
	if newParent then
		table.insert(rawget(newParent, "_children"), self)
		local ev = rawget(newParent, "_events")
		if ev.ChildAdded then
			ev.ChildAdded:Fire(self)
		end
		fireDescendantAdded(newParent, self)
		for _, d in descendants(self, {}) do
			fireDescendantAdded(newParent, d)
		end
		-- WaitForChild en attente
		local w = rawget(newParent, "_waitForChild")
		if w and w[props.Name] then
			local list = w[props.Name]
			w[props.Name] = nil
			for _, co in list do
				resume(co, self)
			end
		end
	end
	if rawget(self, "_events").AncestryChanged then
		rawget(self, "_events").AncestryChanged:Fire(self, newParent)
	end
	fireProp(self, "Parent", newParent)
	if Engine._onParentChanged then
		Engine._onParentChanged(self, old, newParent)
	end
end

function Methods:IsA(name)
	return isA(rawget(self, "_class"), name)
end
function Methods:FindFirstChild(name, recursive)
	for _, child in rawget(self, "_children") do
		if rawget(child, "_props").Name == name then
			return child
		end
	end
	if recursive then
		for _, child in rawget(self, "_children") do
			local r = child:FindFirstChild(name, true)
			if r then
				return r
			end
		end
	end
	return nil
end
function Methods:FindFirstChildOfClass(cls)
	for _, child in rawget(self, "_children") do
		if rawget(child, "_class") == cls then
			return child
		end
	end
	return nil
end
function Methods:FindFirstChildWhichIsA(cls, recursive)
	for _, child in rawget(self, "_children") do
		if isA(rawget(child, "_class"), cls) then
			return child
		end
	end
	if recursive then
		for _, child in rawget(self, "_children") do
			local r = child:FindFirstChildWhichIsA(cls, true)
			if r then
				return r
			end
		end
	end
	return nil
end
function Methods:FindFirstAncestor(name)
	local p = rawget(self, "_props").Parent
	while p do
		if rawget(p, "_props").Name == name then
			return p
		end
		p = rawget(p, "_props").Parent
	end
	return nil
end
function Methods:FindFirstAncestorOfClass(cls)
	local p = rawget(self, "_props").Parent
	while p do
		if rawget(p, "_class") == cls then
			return p
		end
		p = rawget(p, "_props").Parent
	end
	return nil
end
function Methods:FindFirstAncestorWhichIsA(cls)
	local p = rawget(self, "_props").Parent
	while p do
		if isA(rawget(p, "_class"), cls) then
			return p
		end
		p = rawget(p, "_props").Parent
	end
	return nil
end
function Methods:WaitForChild(name, timeout)
	local c = self:FindFirstChild(name)
	if c then
		return c
	end
	local co = coroutine.running()
	local w = rawget(self, "_waitForChild")
	if not w then
		w = {}
		rawset(self, "_waitForChild", w)
	end
	w[name] = w[name] or {}
	table.insert(w[name], co)
	local limit = timeout or 5
	task.delay(limit, function()
		local list = w[name]
		if list then
			local i = table.find(list, co)
			if i then
				table.remove(list, i)
				if not timeout then
					print("[sim] Infinite yield possible on WaitForChild(" .. name .. ") in " .. self:GetFullName())
				end
				resume(co, nil)
			end
		end
	end)
	return coroutine.yield()
end
function Methods:GetChildren()
	return table.clone(rawget(self, "_children"))
end
function Methods:GetDescendants()
	return descendants(self, {})
end
function Methods:IsDescendantOf(other)
	local p = rawget(self, "_props").Parent
	while p do
		if p == other then
			return true
		end
		p = rawget(p, "_props").Parent
	end
	return false
end
function Methods:IsAncestorOf(other)
	return other:IsDescendantOf(self)
end
function Methods:GetFullName()
	local parts = {}
	local p = self
	while p and rawget(p, "_class") ~= "DataModel" do
		table.insert(parts, 1, rawget(p, "_props").Name)
		p = rawget(p, "_props").Parent
	end
	return table.concat(parts, ".")
end
function Methods:Destroy()
	if rawget(self, "_destroyed") then
		return
	end
	local ev = rawget(self, "_events")
	if ev.Destroying then
		ev.Destroying:Fire()
	end
	for _, child in table.clone(rawget(self, "_children")) do
		child:Destroy()
	end
	setParent(self, nil)
	rawset(self, "_destroyed", true)
	for _, s in ev do
		if getmetatable(s) == Signal then
			s:DisconnectAll()
		end
	end
	if Engine._onDestroy then
		Engine._onDestroy(self)
	end
end
function Methods:ClearAllChildren()
	for _, child in table.clone(rawget(self, "_children")) do
		child:Destroy()
	end
end
function Methods:Clone()
	if rawget(self, "_props").Archivable == false then
		return nil
	end
	local copy = Instance.new(rawget(self, "_class"))
	for k, v in rawget(self, "_props") do
		if k ~= "Parent" then
			rawget(copy, "_props")[k] = v
		end
	end
	for k, v in rawget(self, "_attributes") do
		rawget(copy, "_attributes")[k] = v
	end
	for k in rawget(self, "_tags") do
		rawget(copy, "_tags")[k] = true
	end
	for _, child in rawget(self, "_children") do
		local c = child:Clone()
		if c then
			c.Parent = copy
		end
	end
	if rawget(self, "_source") then
		rawset(copy, "_source", rawget(self, "_source"))
	end
	return copy
end
function Methods:SetAttribute(name, value)
	assert(type(name) == "string", "Attribute name must be a string")
	local t = typeof(value)
	if value ~= nil and not (t == "string" or t == "number" or t == "boolean" or t == "Vector3" or t == "Color3" or t == "CFrame" or t == "UDim2" or t == "Vector2" or t == "UDim" or t == "NumberRange" or t == "BrickColor") then
		error("SetAttribute: unsupported type " .. t .. " for " .. name, 2)
	end
	local attrs = rawget(self, "_attributes")
	if attrs[name] == value then
		return
	end
	attrs[name] = value
	local ev = rawget(self, "_events")
	if ev._attrSignals and ev._attrSignals[name] then
		ev._attrSignals[name]:Fire()
	end
	if ev.AttributeChanged then
		ev.AttributeChanged:Fire(name)
	end
end
function Methods:GetAttribute(name)
	return rawget(self, "_attributes")[name]
end
function Methods:GetAttributes()
	return table.clone(rawget(self, "_attributes"))
end
function Methods:GetAttributeChangedSignal(name)
	local ev = rawget(self, "_events")
	ev._attrSignals = ev._attrSignals or {}
	ev._attrSignals[name] = ev._attrSignals[name] or Signal.new("Attr:" .. name)
	return ev._attrSignals[name]
end
function Methods:GetPropertyChangedSignal(name)
	local ev = rawget(self, "_events")
	ev._propSignals = ev._propSignals or {}
	ev._propSignals[name] = ev._propSignals[name] or Signal.new("Prop:" .. name)
	return ev._propSignals[name]
end
function Methods:AddTag(tag)
	Engine.CollectionAdd(self, tag)
end
function Methods:RemoveTag(tag)
	Engine.CollectionRemove(self, tag)
end
function Methods:HasTag(tag)
	return rawget(self, "_tags")[tag] == true
end
function Methods:GetTags()
	local out = {}
	for k in rawget(self, "_tags") do
		table.insert(out, k)
	end
	return out
end

-- Pivot / géométrie
local function modelParts(self)
	local out = {}
	if self:IsA("BasePart") then
		table.insert(out, self)
	end
	for _, d in descendants(self, {}) do
		if d:IsA("BasePart") then
			table.insert(out, d)
		end
	end
	return out
end
function Methods:GetPivot()
	if self:IsA("BasePart") then
		return rawget(self, "_props").CFrame
	end
	local pp = rawget(self, "_props").PrimaryPart
	if pp then
		return rawget(pp, "_props").CFrame
	end
	local parts = modelParts(self)
	if #parts == 0 then
		return rawget(self, "_props").WorldPivot or CFrame.new()
	end
	local sum = Vector3.zero
	for _, p in parts do
		sum += rawget(p, "_props").CFrame.Position
	end
	return CFrame.new(sum / #parts)
end
function Methods:PivotTo(cf)
	local pivot = self:GetPivot()
	local delta = cf * pivot:Inverse()
	for _, p in modelParts(self) do
		local props = rawget(p, "_props")
		props.CFrame = delta * props.CFrame
		fireProp(p, "CFrame", props.CFrame)
	end
	if not self:IsA("BasePart") then
		rawget(self, "_props").WorldPivot = cf
	end
end
function Methods:SetPrimaryPartCFrame(cf)
	self:PivotTo(cf)
end
function Methods:GetBoundingBox()
	local parts = modelParts(self)
	if #parts == 0 then
		return CFrame.new(), Vector3.zero
	end
	local minV = Vector3.new(math.huge, math.huge, math.huge)
	local maxV = -minV
	for _, p in parts do
		local props = rawget(p, "_props")
		local half = props.Size / 2
		minV = minV:Min(props.CFrame.Position - half)
		maxV = maxV:Max(props.CFrame.Position + half)
	end
	return CFrame.new((minV + maxV) / 2), maxV - minV
end
function Methods:GetExtentsSize()
	local _, size = self:GetBoundingBox()
	return size
end
function Methods:ScaleTo(s)
	rawget(self, "_props")._scale = s
end
function Methods:GetScale()
	return rawget(self, "_props")._scale or 1
end
function Methods:SetNetworkOwner(owner)
	rawget(self, "_props")._networkOwner = owner
end
function Methods:GetNetworkOwner()
	return rawget(self, "_props")._networkOwner
end
function Methods:SetNetworkOwnershipAuto() end
function Methods:CanSetNetworkOwnership()
	return true, nil
end
function Methods:ApplyImpulse(impulse)
	local props = rawget(self, "_props")
	props.AssemblyLinearVelocity = (props.AssemblyLinearVelocity or Vector3.zero) + impulse / math.max(1, self.AssemblyMass)
end
function Methods:ApplyAngularImpulse() end
function Methods:GetTouchingParts()
	return {}
end
function Methods:BreakJoints() end
function Methods:GetConnectedParts()
	return { self }
end
function Methods:GetRootPart()
	return self
end
function Methods:GetMass()
	return self.AssemblyMass
end

-- GUI
function Methods:TweenPosition()
	return true
end
function Methods:TweenSize()
	return true
end
function Methods:TweenSizeAndPosition()
	return true
end
function Methods:CaptureFocus() end
function Methods:ReleaseFocus() end

-- Son / effets
function Methods:Play()
	rawget(self, "_props").Playing = true
	if rawget(self, "_class") == "Sound" then
		task.delay(rawget(self, "_props").TimeLength or 1, function()
			if not rawget(self, "_destroyed") then
				rawget(self, "_props").Playing = false
				getEvent(self, "Ended"):Fire()
			end
		end)
	end
end
function Methods:Stop()
	rawget(self, "_props").Playing = false
	local ev = rawget(self, "_events")
	if ev.Stopped then
		ev.Stopped:Fire()
	end
end
function Methods:Pause()
	rawget(self, "_props").Playing = false
end
function Methods:Resume()
	rawget(self, "_props").Playing = true
end
function Methods:Emit(n)
	rawget(self, "_props")._emitted = (rawget(self, "_props")._emitted or 0) + (n or 1)
end
function Methods:Clear() end

-- Remotes
function Methods:FireServer(...)
	assert(currentCtx ~= "server", "FireServer can only be called from the client")
	local player = currentCtx
	local args = Engine.CopyArgs(table.pack(...))
	local remote = self
	task.defer(function()
		currentCtx = "server"
		getEvent(remote, "OnServerEvent"):FireFiltered("server", player, table.unpack(args, 1, args.n))
	end)
	Engine.RemoteLog(remote, "FireServer", player, args)
end
function Methods:FireClient(player, ...)
	assert(currentCtx == "server", "FireClient can only be called from the server")
	assert(isInstance(player) and player:IsA("Player"), "FireClient: argument 1 must be a Player")
	local args = Engine.CopyArgs(table.pack(...))
	getEvent(self, "OnClientEvent"):FireFiltered(player, table.unpack(args, 1, args.n))
	Engine.RemoteLog(self, "FireClient", player, args)
end
function Methods:FireAllClients(...)
	assert(currentCtx == "server", "FireAllClients can only be called from the server")
	local args = Engine.CopyArgs(table.pack(...))
	getEvent(self, "OnClientEvent"):FireClients(table.unpack(args, 1, args.n))
	Engine.RemoteLog(self, "FireAllClients", nil, args)
end
function Methods:InvokeServer(...)
	local player = currentCtx
	local cb = rawget(self, "_props").OnServerInvoke
	assert(cb, "OnServerInvoke not set on " .. self:GetFullName())
	local args = Engine.CopyArgs(table.pack(...))
	local prev = currentCtx
	currentCtx = "server"
	local res = table.pack(cb(player, table.unpack(args, 1, args.n)))
	currentCtx = prev
	return table.unpack(Engine.CopyArgs(res), 1, res.n)
end
function Methods:Fire(...)
	-- BindableEvent
	getEvent(self, "Event"):Fire(...)
end
function Methods:Invoke(...)
	local cb = rawget(self, "_props").OnInvoke
	return cb(...)
end

Engine.RemoteCalls = {}
function Engine.RemoteLog(remote, kind, player, args)
	local key = rawget(remote, "_props").Name .. ":" .. kind
	Engine.RemoteCalls[key] = (Engine.RemoteCalls[key] or 0) + 1
	if Engine.OnRemote then
		Engine.OnRemote(remote, kind, player, args)
	end
end

-- Copie des arguments comme le ferait la sérialisation réseau
local function deepCopy(v, seen)
	if type(v) ~= "table" or isInstance(v) then
		return v
	end
	if getmetatable(v) ~= nil then
		return v -- datatypes
	end
	seen = seen or {}
	if seen[v] then
		error("Cyclic table cannot be sent over the network")
	end
	seen[v] = true
	local out = {}
	for k, val in v do
		if type(k) == "table" then
			error("Tables with table keys cannot be sent over the network")
		end
		out[k] = deepCopy(val, seen)
	end
	seen[v] = nil
	return out
end
function Engine.CopyArgs(packed)
	local out = { n = packed.n }
	for i = 1, packed.n do
		out[i] = deepCopy(packed[i])
	end
	return out
end

-- ---------------------------------------------------------------------------
-- Humanoid simplifié
-- ---------------------------------------------------------------------------
Engine.GroundY = 0
local humanoids = setmetatable({}, { __mode = "k" })

function Engine._setupHumanoid(h)
	humanoids[h] = true
	rawset(h, "_state", Enum.HumanoidStateType.Running)
	rawset(h, "_set", function(self, key, value)
		local props = rawget(self, "_props")
		if key == "Health" then
			local old = props.Health
			props.Health = math.clamp(value, 0, props.MaxHealth)
			if old > 0 and props.Health <= 0 then
				rawset(self, "_state", Enum.HumanoidStateType.Dead)
				getEvent(self, "Died"):Fire()
			end
			getEvent(self, "HealthChanged"):Fire(props.Health)
			return true
		end
		if key == "Jump" and value == true then
			props._jumpRequested = true
		end
		return false
	end)
	rawset(h, "_get", function(self, key)
		if key == "RootPart" then
			local model = rawget(self, "_props").Parent
			return model and model:FindFirstChild("HumanoidRootPart")
		end
		if key == "SeatPart" then
			return nil
		end
		return nil
	end)
end

function Methods:MoveTo(pos, part)
	local props = rawget(self, "_props")
	props._moveTarget = pos
	props._moveStart = now
	props._moveDir = nil
end
function Methods:Move(dir, relative)
	local props = rawget(self, "_props")
	props._moveTarget = nil
	if dir.Magnitude > 0 then
		props._moveDir = Vector3.new(dir.X, 0, dir.Z).Unit
	else
		props._moveDir = nil
	end
end
function Methods:ChangeState(state)
	local old = rawget(self, "_state")
	rawset(self, "_state", state)
	if state == Enum.HumanoidStateType.Jumping then
		local root = self.RootPart
		if root then
			local props = rawget(root, "_props")
			props.AssemblyLinearVelocity = Vector3.new(props.AssemblyLinearVelocity.X, rawget(self, "_props").JumpPower, props.AssemblyLinearVelocity.Z)
			props._airborne = true
		end
	end
	getEvent(self, "StateChanged"):Fire(old, state)
end
function Methods:GetState()
	return rawget(self, "_state")
end
function Methods:SetStateEnabled() end
function Methods:GetStateEnabled()
	return true
end
function Methods:TakeDamage(n)
	self.Health = self.Health - n
end
function Methods:ApplyDescription(desc)
	rawget(self, "_props")._description = desc
end
function Methods:GetAppliedDescription()
	return rawget(self, "_props")._description or Instance.new("HumanoidDescription")
end
function Methods:UnequipTools() end
function Methods:EquipTool() end
function Methods:GetPlayingAnimationTracks()
	return {}
end
function Methods:LoadAnimation(anim)
	local track = Instance.new("AnimationTrack")
	rawget(track, "_props").Animation = anim
	rawget(track, "_props").IsPlaying = false
	rawget(track, "_props").Length = 1
	rawget(track, "_props").Speed = 1
	rawget(track, "_props").Priority = Enum.AnimationPriority.Core
	rawget(track, "_props").Looped = false
	return track
end
function Methods:AdjustSpeed(s)
	rawget(self, "_props").Speed = s
end
function Methods:AdjustWeight() end

-- Pas de physique de simulation : déplace les Humanoid et intègre la balistique.
local GRAVITY = 196.2
function Engine.PhysicsStep(dt)
	for h in humanoids do
		if rawget(h, "_destroyed") then
			humanoids[h] = nil
			continue
		end
		local hp = rawget(h, "_props")
		local model = hp.Parent
		if not model or not model:IsDescendantOf(Engine.workspace) then
			continue
		end
		local root = model:FindFirstChild("HumanoidRootPart")
		if not root or hp.Health <= 0 then
			continue
		end
		local rp = rawget(root, "_props")
		if rp.Anchored then
			continue
		end
		local pos = rp.CFrame.Position
		local vel = rp.AssemblyLinearVelocity or Vector3.zero
		local groundY = Engine.GroundY + 3
		local airborne = rp._airborne or pos.Y > groundY + 0.05 or vel.Y > 0.01

		-- Contraintes de vitesse posées par le jeu (LinearVelocity actives)
		local forced = nil
		for _, d in descendants(model, {}) do
			if rawget(d, "_class") == "LinearVelocity" and rawget(d, "_props").Enabled ~= false then
				forced = rawget(d, "_props").VectorVelocity
			end
		end

		local horizontal = Vector3.zero
		local dir = nil
		if forced then
			horizontal = Vector3.new(forced.X, 0, forced.Z)
		elseif hp.PlatformStand or airborne then
			horizontal = Vector3.new(vel.X, 0, vel.Z)
		else
			if hp._moveTarget then
				local delta = hp._moveTarget - pos
				delta = Vector3.new(delta.X, 0, delta.Z)
				if delta.Magnitude < 1 or now - (hp._moveStart or now) > 8 then
					local reached = delta.Magnitude < 1
					hp._moveTarget = nil
					getEvent(h, "MoveToFinished"):Fire(reached)
				else
					dir = delta.Unit
				end
			elseif hp._moveDir then
				dir = hp._moveDir
			end
			if dir then
				horizontal = dir * hp.WalkSpeed
			end
		end
		hp.MoveDirection = dir or Vector3.zero

		if hp._jumpRequested and not airborne and not hp.PlatformStand then
			hp._jumpRequested = false
			vel = Vector3.new(vel.X, hp.JumpPower, vel.Z)
			airborne = true
		end
		hp._jumpRequested = false

		local vy = vel.Y
		if airborne then
			vy -= GRAVITY * dt
		end
		local newPos = pos + horizontal * dt + Vector3.new(0, vy * dt, 0)
		if newPos.Y <= groundY then
			newPos = Vector3.new(newPos.X, groundY, newPos.Z)
			vy = 0
			rp._airborne = false
			if airborne then
				-- Atterrissage : on conserve un peu de glisse si PlatformStand
				horizontal = hp.PlatformStand and horizontal * 0.5 or Vector3.zero
			end
		else
			rp._airborne = true
		end
		local newVel = Vector3.new(horizontal.X, vy, horizontal.Z)
		if not airborne and not forced and not hp.PlatformStand then
			newVel = Vector3.new(horizontal.X, 0, horizontal.Z)
		end
		rp.AssemblyLinearVelocity = newVel
		local look = (horizontal.Magnitude > 0.1 and hp.AutoRotate) and CFrame.lookAt(newPos, newPos + horizontal) or (CFrame.new(newPos) * (rp.CFrame - rp.CFrame.Position))
		model:PivotTo(look * (model:GetPivot():Inverse() * rp.CFrame):Inverse())
		-- Simulation du Touched entre personnages (utilisé par certains systèmes)
	end
end

-- ---------------------------------------------------------------------------
-- Raycast (boîtes orientées)
-- ---------------------------------------------------------------------------
local function rayBox(origin, dir, cf, size)
	local inv = cf:Inverse()
	local o = inv * origin
	local d = inv:VectorToWorldSpace(dir)
	local half = size / 2
	local tmin, tmax = 0, 1
	for _, axis in { "X", "Y", "Z" } do
		local oa, da, ha = o[axis], d[axis], half[axis]
		if math.abs(da) < 1e-9 then
			if oa < -ha or oa > ha then
				return nil
			end
		else
			local t1 = (-ha - oa) / da
			local t2 = (ha - oa) / da
			if t1 > t2 then
				t1, t2 = t2, t1
			end
			tmin = math.max(tmin, t1)
			tmax = math.min(tmax, t2)
			if tmin > tmax then
				return nil
			end
		end
	end
	return tmin
end

local function passesFilter(part, params)
	if not params then
		return true
	end
	local list = params.FilterDescendantsInstances or {}
	local inList = false
	for _, inst in list do
		if part == inst or part:IsDescendantOf(inst) then
			inList = true
			break
		end
	end
	if params.FilterType == Enum.RaycastFilterType.Include then
		return inList
	end
	return not inList
end

function Engine.Raycast(origin, direction, params)
	local best, bestT = nil, math.huge
	for _, part in descendants(Engine.workspace, {}) do
		if part:IsA("BasePart") then
			local props = rawget(part, "_props")
			if props.CanQuery ~= false and (params == nil or params.RespectCanCollide ~= true or props.CanCollide) and passesFilter(part, params) then
				local t = rayBox(origin, direction, props.CFrame, props.Size)
				if t and t < bestT then
					best, bestT = part, t
				end
			end
		end
	end
	if not best then
		return nil
	end
	local position = origin + direction * bestT
	return {
		Instance = best,
		Position = position,
		Normal = Vector3.yAxis,
		Distance = direction.Magnitude * bestT,
		Material = rawget(best, "_props").Material,
	}
end

function Engine.PartsInRadius(position, radius, params)
	local out = {}
	for _, part in descendants(Engine.workspace, {}) do
		if part:IsA("BasePart") and passesFilter(part, params) then
			local props = rawget(part, "_props")
			local half = props.Size / 2
			local local_ = props.CFrame:PointToObjectSpace(position)
			local clamped = Vector3.new(math.clamp(local_.X, -half.X, half.X), math.clamp(local_.Y, -half.Y, half.Y), math.clamp(local_.Z, -half.Z, half.Z))
			if (clamped - local_).Magnitude <= radius then
				table.insert(out, part)
			end
		end
	end
	return out
end

-- ---------------------------------------------------------------------------
-- Boucle de simulation
-- ---------------------------------------------------------------------------
Engine.Step = 1 / 30
Engine.HeartbeatSignal = Signal.new("Heartbeat")
Engine.SteppedSignal = Signal.new("Stepped")
Engine.RenderSteppedSignal = Signal.new("RenderStepped")
Engine.RenderBindings = {}

local function runDue()
	-- Threads différés
	local guard = 0
	while #deferred > 0 do
		guard += 1
		if guard > 10000 then
			error("Deferred loop runaway")
		end
		local d = table.remove(deferred, 1)
		resume(d.co, table.unpack(d.args, 1, d.args.n))
	end
	-- Threads en attente arrivés à échéance (dans l'ordre)
	while true do
		local idx, best = nil, math.huge
		for i, w in waiting do
			if w.at <= now and w.at < best then
				idx, best = i, w.at
			end
		end
		if not idx then
			break
		end
		local w = table.remove(waiting, idx)
		if w.args then
			resume(w.co, table.unpack(w.args, 1, w.args.n))
		else
			resume(w.co, now - (w.start or now))
		end
		while #deferred > 0 do
			local d = table.remove(deferred, 1)
			resume(d.co, table.unpack(d.args, 1, d.args.n))
		end
	end
end

function Engine.Advance(seconds)
	local target = now + seconds
	while now < target - 1e-9 do
		local dt = math.min(Engine.Step, target - now)
		now += dt
		runDue()
		Engine.SteppedSignal:Fire(now, dt)
		Engine.PhysicsStep(dt)
		Engine.HeartbeatSignal:Fire(dt)
		Engine.RenderSteppedSignal:Fire(dt)
		for _, binding in Engine.RenderBindings do
			spawnIn(binding.ctx, binding.fn, dt)
		end
		runDue()
		if Engine.OnStep then
			Engine.OnStep(now, dt)
		end
	end
end

-- Exécute une fonction dans le contexte donné et fait tourner les threads immédiats
function Engine.Run(ctx, fn, ...)
	local co = spawnIn(ctx, fn, ...)
	runDue()
	return co
end

-- ---------------------------------------------------------------------------
-- Datatypes manquants dans Lune
-- ---------------------------------------------------------------------------
local BrickColor = {}
BrickColor.__index = BrickColor
function BrickColor.new(v, g, b)
	local color
	if typeof(v) == "Color3" then
		color = v
	elseif type(v) == "number" and g then
		color = Color3.new(v, g, b)
	else
		color = GREY
	end
	return setmetatable({ Color = color, Name = typeof(v) == "string" and v or "Custom", Number = 0 }, BrickColor)
end
function BrickColor.random()
	return BrickColor.new(Color3.new(math.random(), math.random(), math.random()))
end
for _, n in { "White", "Gray", "DarkGray", "Black", "Red", "Yellow", "Green", "Blue" } do
	BrickColor[n] = function()
		return BrickColor.new(GREY)
	end
end

local TweenInfo = {}
function TweenInfo.new(time, style, direction, repeatCount, reverses, delay)
	return {
		Time = time or 1,
		EasingStyle = style or Enum.EasingStyle.Quad,
		EasingDirection = direction or Enum.EasingDirection.Out,
		RepeatCount = repeatCount or 0,
		Reverses = reverses or false,
		DelayTime = delay or 0,
		_isTweenInfo = true,
	}
end

local function paramsNew()
	return {
		FilterDescendantsInstances = {},
		FilterType = Enum.RaycastFilterType.Exclude,
		IgnoreWater = false,
		CollisionGroup = "Default",
		RespectCanCollide = false,
		MaxParts = 0,
		AddToFilter = function(self, x)
			if type(x) == "table" and not isInstance(x) then
				for _, i in x do
					table.insert(self.FilterDescendantsInstances, i)
				end
			else
				table.insert(self.FilterDescendantsInstances, x)
			end
		end,
	}
end
local RaycastParams = { new = paramsNew }
local OverlapParams = { new = paramsNew }

local RandomMT = {}
RandomMT.__index = RandomMT
local Random = {}
function Random.new(seed)
	local state = seed or math.random(1, 2 ^ 30)
	return setmetatable({ _s = state }, RandomMT)
end
function RandomMT:_next()
	self._s = (self._s * 1103515245 + 12345) % 2147483648
	return self._s / 2147483648
end
function RandomMT:NextNumber(a, b)
	a = a or 0
	b = b or 1
	return a + (b - a) * self:_next()
end
function RandomMT:NextInteger(a, b)
	return math.floor(a + (b - a + 1) * self:_next())
end
function RandomMT:NextUnitVector()
	local v = Vector3.new(self:_next() - 0.5, self:_next() - 0.5, self:_next() - 0.5)
	return v.Unit
end
function RandomMT:Shuffle(t)
	for i = #t, 2, -1 do
		local j = self:NextInteger(1, i)
		t[i], t[j] = t[j], t[i]
	end
end

local DateTime = {}
function DateTime.now()
	return { UnixTimestamp = math.floor(os.time()), UnixTimestampMillis = math.floor(os.time() * 1000), FormatUniversalTime = function()
		return "2026-01-01"
	end, ToUniversalTime = function()
		return { Year = 2026, Month = 1, Day = 1, Hour = 0, Minute = 0, Second = 0 }
	end }
end

Engine.Types = {
	BrickColor = BrickColor,
	TweenInfo = TweenInfo,
	RaycastParams = RaycastParams,
	OverlapParams = OverlapParams,
	Random = Random,
	DateTime = DateTime,
}

-- typeof qui reconnaît nos instances
local nativeTypeof = typeof
local function simTypeof(v)
	if isInstance(v) then
		return "Instance"
	end
	if type(v) == "table" then
		local mt = getmetatable(v)
		if mt == BrickColor then
			return "BrickColor"
		end
		if mt == RandomMT then
			return "Random"
		end
		if mt == Signal then
			return "RBXScriptSignal"
		end
		if v._isTweenInfo then
			return "TweenInfo"
		end
	end
	return nativeTypeof(v)
end
Engine.typeof = simTypeof
typeof = simTypeof

-- ---------------------------------------------------------------------------
-- Collection
-- ---------------------------------------------------------------------------
local tagged = {}
local tagAdded, tagRemoved = {}, {}
local function tagSignal(map, tag)
	map[tag] = map[tag] or Signal.new("Tag:" .. tag)
	return map[tag]
end
function Engine.CollectionAdd(inst, tag)
	local tags = rawget(inst, "_tags")
	if tags[tag] then
		return
	end
	tags[tag] = true
	tagged[tag] = tagged[tag] or {}
	tagged[tag][inst] = true
	tagSignal(tagAdded, tag):Fire(inst)
end
function Engine.CollectionRemove(inst, tag)
	local tags = rawget(inst, "_tags")
	if not tags[tag] then
		return
	end
	tags[tag] = nil
	if tagged[tag] then
		tagged[tag][inst] = nil
	end
	tagSignal(tagRemoved, tag):Fire(inst)
end
function Engine._onDestroy(inst)
	for tag in rawget(inst, "_tags") do
		if tagged[tag] then
			tagged[tag][inst] = nil
		end
	end
end
Engine.Collection = {
	GetTagged = function(_, tag)
		local out = {}
		for inst in tagged[tag] or {} do
			if not rawget(inst, "_destroyed") then
				table.insert(out, inst)
			end
		end
		return out
	end,
	AddTag = function(_, inst, tag)
		Engine.CollectionAdd(inst, tag)
	end,
	RemoveTag = function(_, inst, tag)
		Engine.CollectionRemove(inst, tag)
	end,
	HasTag = function(_, inst, tag)
		return rawget(inst, "_tags")[tag] == true
	end,
	GetInstanceAddedSignal = function(_, tag)
		return tagSignal(tagAdded, tag)
	end,
	GetInstanceRemovedSignal = function(_, tag)
		return tagSignal(tagRemoved, tag)
	end,
	GetTags = function(_, inst)
		return inst:GetTags()
	end,
}

Engine.Serde = serde
Engine.Fs = fs
Engine.Luau = luau
Engine.Roblox = roblox

return Engine

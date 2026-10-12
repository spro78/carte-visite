--[[
	EffectsController.lua
	Réactions visuelles et sonores aux événements du serveur (remote "Effect") :
	  Capture  : gerbe aux couleurs de l'effet de capture du chasseur (cosmétique),
	             onde de choc à la couleur du chasseur, "DOWN!", son, petite
	             secousse pour la victime, ligne dans le fil des captures
	  Carry    : petit nuage de poussière quand un coéquipier est ramassé
	  Revive   : étincelles de l'équipe, "SAVED!", son, ligne "X saved Y"
	  Convert  : onde à la couleur de la nouvelle équipe, ligne "Y joined the ..."
	  Dash / Ability / Bite / Launch / Grab / Geyser : petits effets + sons
	  Score    : confettis de l'équipe + son
	  Coins    : "+N" doré qui monte + son
	Et les sons de la manche : tic du décompte, départ, victoire / défaite.
	Les effets restent brefs et discrets pour ne jamais masquer un joueur.
]]

local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Remotes = require(Shared.Remotes)
local Teams = require(Shared.Teams)
local Lang = require(Shared.Lang)

local EffectsController = {}

local player = Players.LocalPlayer
local feed: any = nil
local hud: any = nil
local MAX_LIVE_EFFECTS = 24 -- plafond pour le mobile
local live = 0

-- ---------------------------------------------------------------------------
-- Sons
-- ---------------------------------------------------------------------------
local soundCache: { [string]: Sound } = {}

local function soundFor(key: string): Sound?
	local id = (Config.Sounds :: any)[key]
	if type(id) ~= "string" then
		return nil
	end
	local sound = soundCache[key]
	if not sound then
		sound = Instance.new("Sound")
		sound.Name = "HoH_" .. key
		sound.SoundId = id
		sound.Volume = Config.Sounds.Volume
		sound.Parent = SoundService
		soundCache[key] = sound
	end
	return sound
end

-- Son d'interface (non spatialisé)
function EffectsController.Play(key: string, volume: number?, pitch: number?)
	local sound = soundFor(key)
	if not sound then
		return
	end
	sound.Volume = Config.Sounds.Volume * (volume or 1)
	sound.PlaybackSpeed = pitch or 1
	SoundService:PlayLocalSound(sound)
end

-- Son spatialisé à une position (s'atténue avec la distance)
local function playAt(key: string, position: Vector3, volume: number?)
	local id = (Config.Sounds :: any)[key]
	if type(id) ~= "string" then
		return
	end
	local host = Instance.new("Attachment")
	host.WorldPosition = position
	host.Parent = workspace.Terrain
	local sound = Instance.new("Sound")
	sound.SoundId = id
	sound.Volume = Config.Sounds.Volume * (volume or 1)
	sound.RollOffMaxDistance = 160
	sound.Parent = host
	sound:Play()
	Debris:AddItem(host, 3)
end

-- ---------------------------------------------------------------------------
-- Effets visuels
-- ---------------------------------------------------------------------------
local function anchor(position: Vector3): Attachment
	local a = Instance.new("Attachment")
	a.WorldPosition = position
	a.Parent = workspace.Terrain
	return a
end

-- Gerbe de particules (couleurs données), émise une seule fois
local function burst(position: Vector3, colors: { Color3 }, count: number, speed: number, size: number?)
	if live >= MAX_LIVE_EFFECTS then
		return
	end
	live += 1
	local host = anchor(position)
	local keypoints = {}
	for i, c in colors do
		table.insert(keypoints, ColorSequenceKeypoint.new((i - 1) / math.max(1, #colors - 1), c))
	end
	if #keypoints == 1 then
		table.insert(keypoints, ColorSequenceKeypoint.new(1, colors[1]))
	end
	local emitter = Instance.new("ParticleEmitter")
	emitter.Color = ColorSequence.new(keypoints)
	emitter.LightEmission = 0.6
	emitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, size or 0.6), NumberSequenceKeypoint.new(1, 0) })
	emitter.Lifetime = NumberRange.new(0.5, 0.9)
	emitter.Speed = NumberRange.new(speed * 0.6, speed)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Acceleration = Vector3.new(0, -30, 0)
	emitter.Drag = 3
	emitter.Rate = 0
	emitter.Parent = host
	emitter:Emit(count)
	task.delay(1.2, function()
		live -= 1
		host:Destroy()
	end)
end

-- Onde de choc : anneau au sol qui s'élargit et s'efface
local function shockwave(position: Vector3, color: Color3, radius: number)
	if live >= MAX_LIVE_EFFECTS then
		return
	end
	live += 1
	local ring = Instance.new("Part")
	ring.Name = "HoH_Shockwave"
	ring.Anchored = true
	ring.CanCollide = false
	ring.CanQuery = false
	ring.CanTouch = false
	ring.CastShadow = false
	ring.Shape = Enum.PartType.Cylinder
	ring.Material = Enum.Material.Neon
	ring.Color = color
	ring.Transparency = 0.25
	ring.Size = Vector3.new(0.2, 1, 1)
	ring.CFrame = CFrame.new(position.X, position.Y - 2.6, position.Z) * CFrame.Angles(0, 0, math.rad(90))
	ring.Parent = workspace
	local tween = TweenService:Create(ring, TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.new(0.2, radius * 2, radius * 2),
		Transparency = 1,
	})
	tween:Play()
	task.delay(0.5, function()
		live -= 1
		ring:Destroy()
	end)
end

-- Texte flottant qui monte et disparaît (au-dessus d'une position du monde)
local function floatingText(position: Vector3, text: string, color: Color3, maxDistance: number?)
	if live >= MAX_LIVE_EFFECTS then
		return
	end
	live += 1
	local host = anchor(position + Vector3.new(0, 3, 0))
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(160, 44)
	gui.AlwaysOnTop = true
	gui.MaxDistance = maxDistance or 120
	gui.LightInfluence = 0
	gui.Adornee = host
	gui.Parent = host
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Text = text
	label.TextScaled = true
	label.Font = Enum.Font.GothamBlack
	label.TextColor3 = color
	label.TextStrokeTransparency = 0
	label.TextStrokeColor3 = Color3.fromRGB(10, 10, 18)
	label.Parent = gui
	TweenService:Create(gui, TweenInfo.new(1, Enum.EasingStyle.Quad), { StudsOffset = Vector3.new(0, 3, 0) }):Play()
	TweenService:Create(label, TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0, false, 0.6), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
	task.delay(1.05, function()
		live -= 1
		host:Destroy()
	end)
end

-- Petite secousse de caméra (décalage de la caméra du personnage)
local function shake(strength: number, duration: number)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end
	task.spawn(function()
		local t = 0
		while t < duration do
			local k = (1 - t / duration) * strength
			humanoid.CameraOffset = Vector3.new((math.random() - 0.5) * k, (math.random() - 0.5) * k, 0)
			t += task.wait()
		end
		humanoid.CameraOffset = Vector3.zero
	end)
end

local function myActorId(): string?
	local character = player.Character
	return character and character:GetAttribute("ActorId") or nil
end

local function actorPosition(actorId: any): Vector3?
	for _, model in CollectionService:GetTagged("HoH_Actor") do
		if model:IsA("Model") and model:GetAttribute("ActorId") == actorId then
			local root = model:FindFirstChild("HumanoidRootPart")
			if root and root:IsA("BasePart") then
				return root.Position
			end
		end
	end
	return nil
end

-- ---------------------------------------------------------------------------
-- Réactions par type d'événement
-- ---------------------------------------------------------------------------
local handlers: { [string]: (any) -> () } = {}

handlers.Capture = function(data)
	local position = typeof(data.Position) == "Vector3" and data.Position or nil
	local def = Teams.Get(data.Team)
	local fxDef = Config.Shop.CatchEffects[data.CatchEffect] or Config.Shop.CatchEffects.None
	local me = myActorId()
	if position then
		burst(position + Vector3.new(0, 1, 0), fxDef.Colors, data.CatchEffect == "Lightning" and 40 or 26, data.CatchEffect == "Stars" and 26 or 18, data.CatchEffect == "Hearts" and 0.9 or 0.6)
		if def then
			shockwave(position, def.Color, 9)
			-- Le texte nomme la victime et ne se voit que de près : une capture
			-- lointaine ne doit pas faire croire qu'on est soi-même à terre
			local victimName = type(data.VictimName) == "string" and data.VictimName or ""
			if me ~= nil and me == data.VictimId then
				floatingText(position, data.Downed and Lang.T("DOWN!") or (def.Display .. "!"), def.Color)
			else
				floatingText(position, data.Downed and Lang.F("%s DOWN!", victimName) or (victimName .. " → " .. def.Display), def.Color, 60)
			end
		end
	end
	if me ~= nil and me == data.VictimId then
		EffectsController.Play("Caught", 1)
		shake(0.6, 0.35)
	elseif me ~= nil and me == data.HunterId then
		EffectsController.Play("Capture", 1, 1.1)
	elseif position then
		playAt("Capture", position, 0.7)
	end
	if feed then
		feed.Push(data.HunterName, data.VictimName, data.Team, data.OldTeam, me == data.HunterId or me == data.VictimId)
	end
end

handlers.Carry = function(data)
	if typeof(data.Position) == "Vector3" then
		burst(data.Position - Vector3.new(0, 2.5, 0), { Color3.fromRGB(235, 225, 205), Color3.fromRGB(200, 190, 170) }, 10, 8, 0.7)
		playAt("Carry", data.Position, 0.6)
	end
end

handlers.Revive = function(data)
	local def = Teams.Get(data.Team)
	local position = typeof(data.Position) == "Vector3" and data.Position or nil
	local me = myActorId()
	if position and def then
		burst(position + Vector3.new(0, 1, 0), { def.Color, Color3.new(1, 1, 1) }, 30, 16, 0.6)
		shockwave(position, def.Color, 10)
		floatingText(position, Lang.T("SAVED!"), def.Color)
	end
	if me ~= nil and (me == data.VictimId or me == data.RescuerId) then
		EffectsController.Play("Revive", 1, 1.25)
	elseif position then
		playAt("Revive", position, 0.6)
	end
	if feed and data.RescuerName then
		feed.PushRescue(data.RescuerName, data.VictimName, data.Team, me == data.VictimId or me == data.RescuerId)
	end
end

handlers.Convert = function(data)
	local def = Teams.Get(data.Team)
	local position = typeof(data.Position) == "Vector3" and data.Position or nil
	local me = myActorId()
	if position and def then
		shockwave(position, def.Color, 9)
		floatingText(position, def.Display .. "!", def.Color)
	end
	if me ~= nil and me == data.VictimId then
		shake(0.4, 0.3)
	end
	if feed then
		feed.PushJoined(data.VictimName, data.OldTeam, data.Team, me == data.VictimId)
	end
end

handlers.Dash = function(data)
	local position = actorPosition(data.ActorId)
	if position then
		burst(position - Vector3.new(0, 2.5, 0), { Color3.fromRGB(235, 225, 205), Color3.fromRGB(200, 190, 170) }, 8, 8, 0.8)
		if data.ActorId == myActorId() then
			EffectsController.Play("Dash", 0.8)
		else
			playAt("Dash", position, 0.4)
		end
	end
end

handlers.Ability = function(data)
	local def = Teams.Get(data.Team)
	local position = actorPosition(data.ActorId)
	if position and def then
		shockwave(position, def.Color, 6)
		burst(position, { def.Color, Color3.new(1, 1, 1) }, 14, 12, 0.5)
		if data.ActorId == myActorId() then
			EffectsController.Play("Ability", 1, 1.2)
		else
			playAt("Ability", position, 0.5)
		end
	end
end

handlers.Bite = function(data)
	local position = actorPosition(data.To)
	if position then
		burst(position, { Color3.fromRGB(170, 255, 120), Color3.fromRGB(90, 200, 70) }, 16, 10, 0.5)
		floatingText(position, Lang.T("SLOWED"), Color3.fromRGB(170, 255, 120))
		if data.To == myActorId() then
			shake(0.3, 0.25)
		end
	end
end

handlers.Launch = function(data)
	if typeof(data.Position) == "Vector3" then
		burst(data.Position, { Color3.fromRGB(255, 255, 255), Color3.fromRGB(255, 220, 140) }, 18, 22, 0.7)
		playAt("Launch", data.Position, 0.9)
	end
end

handlers.Score = function(data)
	local def = Teams.Get(data.Team)
	local position = typeof(data.Position) == "Vector3" and data.Position or nil
	if def and position then
		burst(position + Vector3.new(0, 2, 0), { def.Color, Color3.fromRGB(255, 255, 255), Color3.fromRGB(255, 215, 60) }, 40, 28, 0.8)
		shockwave(position, def.Color, 14)
		floatingText(position, Lang.F("%s SCORE!", def.Plural), def.Color)
	end
	EffectsController.Play("Score", 1, 0.9)
end

handlers.Coins = function(data)
	local amount = tonumber(data.Amount) or 0
	if amount <= 0 then
		return
	end
	EffectsController.Play("Coins", 0.7, 1.3)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		floatingText(root.Position + Vector3.new(0, 2, 0), "+" .. amount, Color3.fromRGB(255, 205, 50))
	end
	if hud and hud.PulseCoins then
		hud.PulseCoins()
	end
end

handlers.Grab = function(data)
	if typeof(data.Position) == "Vector3" then
		burst(data.Position, { Color3.fromRGB(120, 200, 90), Color3.fromRGB(70, 140, 60) }, 14, 10, 0.6)
		playAt("Launch", data.Position, 0.5)
	end
end

handlers.Geyser = function(data)
	if typeof(data.Position) == "Vector3" then
		playAt("Geyser", data.Position, 0.9)
	end
end

-- ---------------------------------------------------------------------------
-- Sons de la manche (décompte, départ, fin)
-- ---------------------------------------------------------------------------
local lastPhase: string? = nil
local lastTick = -1

function EffectsController.OnState(state: { [string]: any })
	local phase = state.Phase
	if phase == "Countdown" then
		local remaining = math.ceil(tonumber(state.TimeLeft) or 0)
		if remaining ~= lastTick and remaining > 0 and remaining <= 5 then
			lastTick = remaining
			EffectsController.Play("Countdown", 0.8, 1 + (5 - remaining) * 0.05)
		end
	elseif phase == "Round" and lastPhase == "Countdown" then
		EffectsController.Play("Go", 1, 0.8)
		lastTick = -1
	elseif phase == "Results" and lastPhase ~= "Results" then
		local myTeam = player:GetAttribute("Team")
		if state.Winner ~= nil and state.Winner == myTeam then
			EffectsController.Play("Win", 1)
		end
	end
	lastPhase = phase
end

function EffectsController.Init(killFeed: any, hudModule: any)
	feed = killFeed
	hud = hudModule
	Remotes.Get("Effect").OnClientEvent:Connect(function(kind: any, data: any)
		if type(kind) ~= "string" or type(data) ~= "table" then
			return
		end
		local handler = handlers[kind]
		if handler then
			local ok, err = pcall(handler, data)
			if not ok then
				warn("[Effects] " .. kind .. " : " .. tostring(err))
			end
		end
	end)
end

return EffectsController

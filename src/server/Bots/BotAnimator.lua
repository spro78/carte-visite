--[[
	BotAnimator.lua
	Animations des bots côté serveur (les LocalScripts ne tournent pas sur les
	PNJ) : repos, marche, course, saut, chute, selon l'état de l'Humanoid.
	Les identifiants sont dans Config.Bots.Animations.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)

local BotAnimator = {}
BotAnimator.__index = BotAnimator

export type BotAnimator = typeof(setmetatable({} :: {
	Tracks: { [string]: AnimationTrack },
	Current: string?,
}, BotAnimator))

function BotAnimator.new(humanoid: Humanoid): BotAnimator
	local animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		animator = Instance.new("Animator")
		animator.Parent = humanoid
	end
	local tracks = {}
	local set = Config.Bots.Animations[humanoid.RigType == Enum.HumanoidRigType.R6 and "R6" or "R15"]
	for key, id in set do
		local animation = Instance.new("Animation")
		animation.Name = key
		animation.AnimationId = id
		local ok, track = pcall(function()
			return (animator :: Animator):LoadAnimation(animation)
		end)
		if ok and track then
			track.Looped = key ~= "Jump"
			tracks[key] = track
		end
	end
	return setmetatable({ Tracks = tracks, Current = nil }, BotAnimator)
end

function BotAnimator.Play(self: BotAnimator, key: string, speed: number?)
	if self.Current == key then
		local track = self.Tracks[key]
		if track and speed then
			track:AdjustSpeed(speed)
		end
		return
	end
	if self.Current then
		local previous = self.Tracks[self.Current]
		if previous then
			previous:Stop(0.15)
		end
	end
	self.Current = key
	local track = self.Tracks[key]
	if track then
		track:Play(0.15, 1, speed or 1)
	end
end

-- À appeler régulièrement avec l'état courant
function BotAnimator.Update(self: BotAnimator, humanoid: Humanoid, speed: number)
	local state = humanoid:GetState()
	if humanoid.PlatformStand then
		self:Play("Fall")
	elseif state == Enum.HumanoidStateType.Jumping then
		self:Play("Jump")
	elseif state == Enum.HumanoidStateType.Freefall then
		self:Play("Fall")
	elseif speed > 12 then
		self:Play("Run", speed / 16)
	elseif speed > 0.5 then
		self:Play("Walk", speed / 10)
	else
		self:Play("Idle")
	end
end

function BotAnimator.Destroy(self: BotAnimator)
	for _, track in self.Tracks do
		track:Stop(0)
		track:Destroy()
	end
	table.clear(self.Tracks)
end

return BotAnimator

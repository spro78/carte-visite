--[[
	KillFeed.lua
	Fil des captures, en haut à droite sous le tableau des équipes :
	"Alice  >  Bob" (couleurs : équipe du chasseur, ancienne équipe de la victime).
	Les lignes qui te concernent sont surlignées. 4 lignes au maximum, chacune
	s'efface après quelques secondes. On comprend en un coup d'œil qui attrape qui.
]]

local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Teams = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Teams"))
local Theme = require(script.Parent.Theme)

local KillFeed = {}

local MAX_LINES = 4
local LIFETIME = 5

local container: Frame? = nil
local lines: { Frame } = {}
local order = 0

local function colorOf(teamId: any): Color3
	local def = Teams.Get(teamId)
	return def and def.Color or Theme.White
end

local function fadeOut(line: Frame)
	local stroke = line:FindFirstChildOfClass("UIStroke")
	TweenService:Create(line, TweenInfo.new(0.35), { BackgroundTransparency = 1 }):Play()
	if stroke then
		TweenService:Create(stroke, TweenInfo.new(0.35), { Transparency = 1 }):Play()
	end
	local label = line:FindFirstChild("Text")
	if label and label:IsA("TextLabel") then
		TweenService:Create(label, TweenInfo.new(0.35), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
	end
	task.delay(0.4, function()
		local index = table.find(lines, line)
		if index then
			table.remove(lines, index)
		end
		line:Destroy()
	end)
end

local function addLine(richText: string, highlight: boolean)
	if not container then
		return
	end
	order += 1
	local line: Frame = Theme.New("Frame", {
		Name = "Line",
		Size = UDim2.new(1, 0, 0.23, 0),
		BackgroundColor3 = highlight and Color3.fromRGB(60, 52, 18) or Theme.Panel,
		BackgroundTransparency = 0.2,
		LayoutOrder = -order,
	}, container)
	Theme.CornerScale(line, 0.3)
	if highlight then
		Theme.Stroke(line, 2, Theme.Gold)
	end
	Theme.Label(line, {
		Name = "Text",
		Size = UDim2.fromScale(0.92, 0.7),
		Position = UDim2.fromScale(0.04, 0.15),
		Text = richText,
		RichText = true,
		FontFace = Theme.FaceHeavy,
		TextXAlignment = Enum.TextXAlignment.Right,
		TextStrokeTransparency = 0.4,
	})
	table.insert(lines, 1, line)
	while #lines > MAX_LINES do
		local old = table.remove(lines) :: Frame
		old:Destroy()
	end
	task.delay(LIFETIME, function()
		if line.Parent then
			fadeOut(line)
		end
	end)
end

-- Capture : chasseur > victime
function KillFeed.Push(hunterName: any, victimName: any, hunterTeam: any, victimOldTeam: any, involvesMe: boolean?)
	local text = string.format(
		'<font color="%s">%s</font>  <font color="#ffffff">></font>  <font color="%s">%s</font>',
		Theme.Hex(colorOf(hunterTeam)),
		tostring(hunterName or "?"),
		Theme.Hex(colorOf(victimOldTeam)),
		tostring(victimName or "?")
	)
	addLine(text, involvesMe == true)
end

-- Ligne de texte libre (objectif marqué...)
function KillFeed.PushText(text: string, color: Color3)
	addLine(string.format('<font color="%s">%s</font>', Theme.Hex(color), text), false)
end

function KillFeed.Clear()
	for _, line in lines do
		line:Destroy()
	end
	table.clear(lines)
end

function KillFeed.Init(screen: ScreenGui)
	container = Theme.New("Frame", {
		Name = "KillFeed",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -14, 0, 150),
		Size = UDim2.fromOffset(250, 130),
		BackgroundTransparency = 1,
	}, screen)
	Theme.New("UIListLayout", {
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0.03, 0),
		HorizontalAlignment = Enum.HorizontalAlignment.Right,
	}, container)
end

-- Taille compacte sur téléphone
function KillFeed.Rescale(compact: boolean)
	if container then
		container.Size = compact and UDim2.fromOffset(190, 96) or UDim2.fromOffset(250, 130)
		container.Position = compact and UDim2.new(1, -8, 0, 108) or UDim2.new(1, -14, 0, 150)
	end
end

return KillFeed

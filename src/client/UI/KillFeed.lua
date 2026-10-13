--[[
	KillFeed.lua
	Fil des captures, en haut à droite sous le tableau des équipes :
	"Alice  >  Bob" (couleurs : équipe du chasseur, équipe de la victime), puis
	"Carl saved Bob" (sauvetage) ou "Bob joined the FOXES" (conversion).
	Les lignes qui te concernent sont surlignées. 4 lignes au maximum, chacune
	s'efface après quelques secondes. On comprend en un coup d'œil qui attrape qui.
]]

local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Teams = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Teams"))
local Lang = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Lang"))
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

-- Ligne libre (sauvetage, conversion), déjà en texte riche
function KillFeed.PushText(richText: string, involvesMe: boolean?)
	addLine(richText, involvesMe == true)
end

-- Sauvetage : "Alice saved Bob" (couleur de leur équipe)
function KillFeed.PushRescue(rescuerName: any, victimName: any, team: any, involvesMe: boolean?)
	local hex = Theme.Hex(colorOf(team))
	addLine(string.format('<font color="%s">%s</font>  <font color="#ffffff">%s</font>  <font color="%s">%s</font>', hex, tostring(rescuerName or "?"), Lang.T("saved"), hex, tostring(victimName or "?")), involvesMe == true)
end

-- Conversion : "Bob joined the FOXES" (couleur de la nouvelle équipe)
function KillFeed.PushJoined(victimName: any, oldTeam: any, newTeam: any, involvesMe: boolean?)
	local def = Teams.Get(newTeam)
	addLine(string.format('<font color="%s">%s</font>  <font color="#ffffff">%s</font>  <font color="%s">%s</font>', Theme.Hex(colorOf(oldTeam)), tostring(victimName or "?"), Lang.T("joined the"), Theme.Hex(colorOf(newTeam)), def and def.Plural or "?"), involvesMe == true)
end

function KillFeed.SetVisible(visible: boolean)
	if container then
		container.Visible = visible
	end
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
	local camera = workspace.CurrentCamera
	if camera then
		local function update()
			local size = camera.ViewportSize
			KillFeed.Rescale(math.min(size.X, size.Y) < 500, size.Y > size.X)
		end
		camera:GetPropertyChangedSignal("ViewportSize"):Connect(update)
		update()
	end
end

-- Taille compacte sur téléphone : sous le panneau des équipes, au-dessus des
-- boutons tactiles (le bloc central du HUD tient compte de cette largeur).
-- En portrait : à droite du tableau des équipes, sous le bloc du haut.
function KillFeed.Rescale(compact: boolean, portrait: boolean?)
	if container then
		container.Size = compact and UDim2.fromOffset(170, 84) or UDim2.fromOffset(250, 130)
		local y = portrait and 94 or (compact and 100 or 150)
		container.Position = compact and UDim2.new(1, -8, 0, y) or UDim2.new(1, -14, 0, y)
	end
end

return KillFeed

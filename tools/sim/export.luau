--!nocheck
--[[
	export.luau : sérialise en JSON les Parts (et les SurfaceGui) présentes dans
	le workspace autour d'un point, pour le rendu 3D (tools/preview).
]]

local World = require("./world")
local Engine = World.Engine
local roblox = Engine.Roblox
local Enum = roblox.Enum

local Export = {}

local function props(inst)
	return rawget(inst, "_props")
end

local function c3(c)
	return { math.floor(c.R * 255 + 0.5), math.floor(c.G * 255 + 0.5), math.floor(c.B * 255 + 0.5) }
end

local function udim2(u)
	return { u.X.Scale, u.X.Offset, u.Y.Scale, u.Y.Offset }
end

local function exportGui(node)
	local p = props(node)
	if p.Visible == false or p.Enabled == false then
		return nil
	end
	local cls = rawget(node, "_class")
	local out = { class = cls, name = p.Name, children = {} }
	if p.Size then
		out.size = udim2(p.Size)
	end
	if p.Position then
		out.position = udim2(p.Position)
	end
	if p.AnchorPoint then
		out.anchor = { p.AnchorPoint.X, p.AnchorPoint.Y }
	end
	if p.BackgroundColor3 then
		out.bg = c3(p.BackgroundColor3)
		out.bgT = p.BackgroundTransparency
	end
	if p.Text and p.Text ~= "" then
		out.text = p.Text
		out.textColor = c3(p.TextColor3)
		out.textT = p.TextTransparency
		out.stroke = p.TextStrokeTransparency < 1 and c3(p.TextStrokeColor3) or nil
		out.scaled = p.TextScaled
		out.textSize = p.TextSize
		out.xAlign = p.TextXAlignment and p.TextXAlignment.Name
		out.yAlign = p.TextYAlignment and p.TextYAlignment.Name
		out.rotation = p.Rotation
		out.font = p.Font and p.Font.Name or "FredokaOne"
		local face = p.FontFace
		if face then
			out.weight = face.Weight and face.Weight.Name or "Regular"
			out.italic = face.Style == Enum.FontStyle.Italic
			out.font = "Face"
		end
		out.rich = p.RichText == true
	end
	if p.Image and p.Image ~= "" then
		out.image = p.Image
	end
	out.zindex = p.ZIndex
	out.layoutOrder = p.LayoutOrder
	for _, child in node:GetChildren() do
		local ccls = rawget(child, "_class")
		local cp = props(child)
		if ccls == "UICorner" then
			out.corner = { cp.CornerRadius and cp.CornerRadius.Scale or 0, cp.CornerRadius and cp.CornerRadius.Offset or 8 }
		elseif ccls == "UIStroke" then
			if cp.Enabled ~= false then
				out.uiStroke = { color = c3(cp.Color or roblox.Color3.new()), thickness = cp.Thickness or 1, transparency = cp.Transparency or 0 }
			end
		elseif ccls == "UIListLayout" then
			out.list = {
				dir = cp.FillDirection and cp.FillDirection.Name or "Vertical",
				padding = cp.Padding and { cp.Padding.Scale, cp.Padding.Offset } or { 0, 0 },
				h = cp.HorizontalAlignment and cp.HorizontalAlignment.Name or "Left",
				v = cp.VerticalAlignment and cp.VerticalAlignment.Name or "Top",
			}
		elseif ccls == "UIGridLayout" then
			out.grid = {
				cell = cp.CellSize and udim2(cp.CellSize) or { 0, 100, 0, 100 },
				padding = cp.CellPadding and udim2(cp.CellPadding) or { 0, 5, 0, 5 },
			}
		elseif ccls == "UIPadding" then
			out.padding = {
				cp.PaddingTop and { cp.PaddingTop.Scale, cp.PaddingTop.Offset } or { 0, 0 },
				cp.PaddingRight and { cp.PaddingRight.Scale, cp.PaddingRight.Offset } or { 0, 0 },
				cp.PaddingBottom and { cp.PaddingBottom.Scale, cp.PaddingBottom.Offset } or { 0, 0 },
				cp.PaddingLeft and { cp.PaddingLeft.Scale, cp.PaddingLeft.Offset } or { 0, 0 },
			}
		elseif ccls == "UIAspectRatioConstraint" then
			out.aspect = cp.AspectRatio or 1
		elseif ccls == "UITextSizeConstraint" then
			out.maxText = cp.MaxTextSize
		elseif ccls == "UIScale" then
			out.uiScale = cp.Scale or 1
		elseif ccls == "UISizeConstraint" then
			local mx, mn = cp.MaxSize, cp.MinSize
			out.maxSize = mx and { mx.X, mx.Y } or nil
			out.minSize = mn and { mn.X, mn.Y } or nil
		elseif ccls == "UIGradient" then
			-- ignoré
		elseif child:IsA("GuiObject") then
			local e = exportGui(child)
			if e then
				table.insert(out.children, e)
			end
		end
	end
	return out
end
Export.Gui = exportGui

-- Exporte toutes les BaseParts visibles dans un rayon (plan XZ) autour de center
function Export.Parts(center, radius)
	local parts = {}
	for _, d in World.workspace:GetDescendants() do
		if d:IsA("BasePart") then
			local p = props(d)
			local pos = p.CFrame.Position
			local dx, dz = pos.X - center.X, pos.Z - center.Z
			if dx * dx + dz * dz <= radius * radius and (p.Transparency or 0) < 0.98 then
				local entry = {
					name = p.Name,
					cls = rawget(d, "_class"),
					shape = p.Shape and p.Shape.Name or "Block",
					size = { p.Size.X, p.Size.Y, p.Size.Z },
					cf = { p.CFrame:GetComponents() },
					color = c3(p.Color),
					t = p.Transparency or 0,
					material = p.Material and p.Material.Name or "Plastic",
					neon = p.Material == Enum.Material.Neon,
					studs = p.TopSurface == Enum.SurfaceType.Studs,
				}
				local guis = {}
				for _, child in d:GetChildren() do
					if rawget(child, "_class") == "SurfaceGui" then
						local gp = props(child)
						local g = { face = gp.Face and gp.Face.Name or "Front", children = {} }
						for _, gc in child:GetChildren() do
							if gc:IsA("GuiObject") then
								local e = exportGui(gc)
								if e then
									table.insert(g.children, e)
								end
							end
						end
						table.insert(guis, g)
					elseif rawget(child, "_class") == "BillboardGui" and props(child).Enabled ~= false then
						local bp = props(child)
						local b = { offset = { bp.StudsOffset.X, bp.StudsOffset.Y, bp.StudsOffset.Z }, size = udim2(bp.Size), children = {} }
						for _, gc in child:GetChildren() do
							if gc:IsA("GuiObject") then
								local e = exportGui(gc)
								if e then
									table.insert(b.children, e)
								end
							end
						end
						entry.billboards = entry.billboards or {}
						table.insert(entry.billboards, b)
					elseif rawget(child, "_class") == "Decal" then
						-- ignoré
					end
				end
				if #guis > 0 then
					entry.guis = guis
				end
				-- Contours (Highlight) visibles par le joueur observateur
				local model = d:FindFirstAncestorOfClass("Model")
				if model then
					entry.model = props(model).Name
				end
				-- Pièce d'un personnage (tête arrondie, visage, membres arrondis)
				local anc = props(d).Parent
				while anc and anc ~= World.workspace do
					if rawget(anc, "_class") == "Model" and anc:FindFirstChildOfClass("Humanoid") then
						entry.char = true
						entry.charName = props(anc).Name
						break
					end
					anc = props(anc).Parent
				end
				table.insert(parts, entry)
			end
		end
	end
	-- Highlights
	local highlights = {}
	for _, d in World.workspace:GetDescendants() do
		if rawget(d, "_class") == "Highlight" then
			local p = props(d)
			local adornee = p.Adornee or p.Parent
			if p.Enabled ~= false and adornee then
				table.insert(highlights, { model = props(adornee).Name, outline = c3(p.OutlineColor), fill = c3(p.FillColor), fillT = p.FillTransparency })
			end
		end
	end
	-- Terrain : opérations de remplissage proches du centre
	local terrain = {}
	for _, op in World.TerrainOps do
		local x, z, reach
		if op.center then
			x, z, reach = op.center[1], op.center[3], op.radius
		else
			x, z = op.cf[1], op.cf[3]
			reach = op.size and math.max(op.size[1], op.size[3]) or math.max(op.radius or 0, op.height or 0)
		end
		local dx, dz = x - center.X, z - center.Z
		if math.sqrt(dx * dx + dz * dz) <= radius + 700 + reach then
			table.insert(terrain, op)
		end
	end
	local colors = {}
	for name, color in World.TerrainColors do
		colors[name] = c3(color)
	end
	local tp = props(World.workspace.Terrain)
	local lighting = World.game:GetService("Lighting")
	local lp = props(lighting)
	local light = {
		clock = lp.ClockTime or 14,
		brightness = lp.Brightness or 2,
		ambient = lp.Ambient and c3(lp.Ambient) or { 110, 110, 120 },
		outdoor = lp.OutdoorAmbient and c3(lp.OutdoorAmbient) or { 150, 150, 160 },
	}
	for _, child in lighting:GetChildren() do
		local cls = rawget(child, "_class")
		local cp = props(child)
		if cls == "Atmosphere" then
			light.atmosphere = { density = cp.Density, haze = cp.Haze, color = cp.Color and c3(cp.Color), decay = cp.Decay and c3(cp.Decay), offset = cp.Offset }
		elseif cls == "ColorCorrectionEffect" then
			light.cc = { brightness = cp.Brightness, contrast = cp.Contrast, saturation = cp.Saturation, tint = cp.TintColor and c3(cp.TintColor) }
		elseif cls == "BloomEffect" then
			light.bloom = { intensity = cp.Intensity, size = cp.Size, threshold = cp.Threshold }
		end
	end
	return {
		parts = parts,
		highlights = highlights,
		terrain = terrain,
		terrainColors = colors,
		water = { color = c3(tp.WaterColor), transparency = tp.WaterTransparency },
		lighting = light,
	}
end

-- Exporte le PlayerGui d'un joueur
function Export.PlayerGui(player)
	local gui = player:FindFirstChild("PlayerGui")
	local screens = {}
	for _, sg in gui:GetChildren() do
		if rawget(sg, "_class") == "ScreenGui" and props(sg).Enabled ~= false then
			local entry = { name = props(sg).Name, display = props(sg).DisplayOrder or 0, inset = props(sg).IgnoreGuiInset, children = {} }
			for _, c in sg:GetChildren() do
				if c:IsA("GuiObject") then
					local e = exportGui(c)
					if e then
						table.insert(entry.children, e)
					end
				end
			end
			table.insert(screens, entry)
		end
	end
	table.sort(screens, function(a, b)
		return a.display < b.display
	end)
	return screens
end

return Export

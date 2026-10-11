--!nocheck
--[[
	layout.luau : position à l'écran (en pixels) des interfaces simulées, avec
	les mêmes règles que le rendu (tools/preview/page.html) : AnchorPoint,
	Position, Size, UIAspectRatioConstraint, UISizeConstraint, UIScale,
	UIPadding et UIListLayout.
	Sert aux tests de disposition : chevauchements, éléments hors de l'écran,
	cibles tactiles trop petites.
]]

local Enum = require("@lune/roblox").Enum

local Layout = {}

local function component(gui, className)
	return gui:FindFirstChildOfClass(className)
end

local function isGuiObject(inst)
	return inst:IsA("GuiObject")
end

-- Rectangle propre d'un élément dans le rectangle (px, py, pw, ph) de son parent ;
-- k = facteur d'échelle cumulé des UIScale parents (appliqué aux offsets)
local function ownRect(gui, px, py, pw, ph, k, ignorePosition)
	local size, pos, anchor = gui.Size, gui.Position, gui.AnchorPoint
	local w = size.X.Scale * pw + size.X.Offset * k
	local h = size.Y.Scale * ph + size.Y.Offset * k
	local aspect = component(gui, "UIAspectRatioConstraint")
	if aspect then
		local r = aspect.AspectRatio or 1
		if h > 0 and w / h > r then
			w = h * r
		else
			h = w / r
		end
	end
	local limits = component(gui, "UISizeConstraint")
	if limits then
		local maxSize, minSize = limits.MaxSize, limits.MinSize
		if maxSize then
			w = math.min(w, maxSize.X * k)
			h = math.min(h, maxSize.Y * k)
		end
		if minSize then
			w = math.max(w, minSize.X * k)
			h = math.max(h, minSize.Y * k)
		end
	end
	local scale = component(gui, "UIScale")
	if scale and scale.Scale then
		w *= scale.Scale
		h *= scale.Scale
	end
	if ignorePosition then
		return 0, 0, w, h
	end
	local x = px + pos.X.Scale * pw + pos.X.Offset * k - anchor.X * w
	local y = py + pos.Y.Scale * ph + pos.Y.Offset * k - anchor.Y * h
	return x, y, w, h
end

local function sortedChildren(gui)
	local kids = {}
	for _, child in gui:GetChildren() do
		if isGuiObject(child) then
			table.insert(kids, child)
		end
	end
	return kids
end

-- Parcourt l'arbre et appelle visit(gui, x, y, w, h, visible)
local function walk(gui, x, y, w, h, k, visible, visit)
	visit(gui, x, y, w, h, visible)
	local scale = component(gui, "UIScale")
	local kk = k * ((scale and scale.Scale) or 1)
	local ix, iy, iw, ih = x, y, w, h
	local padding = component(gui, "UIPadding")
	if padding then
		local function u(udim, span)
			return udim and (udim.Scale * span + udim.Offset * kk) or 0
		end
		local pt, pb = u(padding.PaddingTop, h), u(padding.PaddingBottom, h)
		local pl, pr = u(padding.PaddingLeft, w), u(padding.PaddingRight, w)
		ix, iy, iw, ih = x + pl, y + pt, w - pl - pr, h - pt - pb
	end
	local kids = sortedChildren(gui)
	local list = component(gui, "UIListLayout")
	if list then
		table.sort(kids, function(a, b)
			return (a.LayoutOrder or 0) < (b.LayoutOrder or 0)
		end)
		-- Valeur par défaut de Roblox : Vertical
		local vertical = list.FillDirection ~= Enum.FillDirection.Horizontal
		local padUDim = list.Padding
		local pad = padUDim and (padUDim.Scale * (vertical and ih or iw) + padUDim.Offset * kk) or 0
		local sizes = {}
		local total = 0
		local shown = 0
		for i, kid in kids do
			local _, _, kw, kh = ownRect(kid, 0, 0, iw, ih, kk, true)
			sizes[i] = { kw, kh }
			-- Roblox ne place pas les enfants invisibles dans une liste
			if kid.Visible ~= false then
				total += vertical and kh or kw
				shown += 1
			end
		end
		total += pad * math.max(0, shown - 1)
		local span = vertical and ih or iw
		local align = vertical and list.VerticalAlignment or list.HorizontalAlignment
		local cursor = 0
		if align == Enum.VerticalAlignment.Center or align == Enum.HorizontalAlignment.Center then
			cursor = (span - total) / 2
		elseif align == Enum.VerticalAlignment.Bottom or align == Enum.HorizontalAlignment.Right then
			cursor = span - total
		end
		for i, kid in kids do
			local kw, kh = sizes[i][1], sizes[i][2]
			local kx, ky
			if vertical then
				ky = iy + cursor
				if list.HorizontalAlignment == Enum.HorizontalAlignment.Center then
					kx = ix + (iw - kw) / 2
				elseif list.HorizontalAlignment == Enum.HorizontalAlignment.Right then
					kx = ix + iw - kw
				else
					kx = ix
				end
			else
				kx = ix + cursor
				if list.VerticalAlignment == Enum.VerticalAlignment.Center then
					ky = iy + (ih - kh) / 2
				elseif list.VerticalAlignment == Enum.VerticalAlignment.Bottom then
					ky = iy + ih - kh
				else
					ky = iy
				end
			end
			if kid.Visible ~= false then
				cursor += (vertical and kh or kw) + pad
			end
			walk(kid, kx, ky, kw, kh, kk, visible and kid.Visible ~= false, visit)
		end
		return
	end
	for _, kid in kids do
		local kx, ky, kw, kh = ownRect(kid, ix, iy, iw, ih, kk)
		walk(kid, kx, ky, kw, kh, kk, visible and kid.Visible ~= false, visit)
	end
end

-- Rectangles de tous les éléments d'un ScreenGui pour un écran de taille viewport.
-- Résultat : { [GuiObject] = { X, Y, W, H, Visible } }
function Layout.Rects(screenGui, viewport)
	local rects = {}
	local enabled = screenGui.Enabled ~= false
	for _, top in sortedChildren(screenGui) do
		local x, y, w, h = ownRect(top, 0, 0, viewport.X, viewport.Y, 1)
		walk(top, x, y, w, h, 1, enabled and top.Visible ~= false, function(gui, gx, gy, gw, gh, visible)
			rects[gui] = { X = gx, Y = gy, W = gw, H = gh, Visible = visible }
		end)
	end
	return rects
end

-- Surface commune de deux rectangles (0 si disjoints)
function Layout.Overlap(a, b)
	local w = math.min(a.X + a.W, b.X + b.W) - math.max(a.X, b.X)
	local h = math.min(a.Y + a.H, b.Y + b.H) - math.max(a.Y, b.Y)
	if w <= 0 or h <= 0 then
		return 0
	end
	return w * h
end

-- Le rectangle tient-il entièrement dans l'écran ?
function Layout.Inside(r, viewport, margin)
	margin = margin or 0
	return r.X >= margin and r.Y >= margin and r.X + r.W <= viewport.X - margin and r.Y + r.H <= viewport.Y - margin
end

-- Blocs visibles du HUD du jeu qui ne doivent jamais se chevaucher (contenu
-- réel : pastilles, lignes du bloc du haut, panneaux), puis liste des problèmes
local TOUCH_ACTIONS = { "DashLeft", "DashRight", "Stop", "Ability" }
function Layout.HudBlocks(hud, rects)
	local blocks = {}
	local function add(name, gui)
		local r = gui and rects[gui]
		if r and r.Visible and r.W > 0 and r.H > 0 then
			table.insert(blocks, { Name = name, Rect = r })
		end
	end
	for _, pill in hud.Pills:GetChildren() do
		if pill:IsA("GuiButton") then
			add("pill " .. pill.Name, pill)
		end
	end
	-- Haut centre : capsule chrono, ruban de rôle, ligne d'objectif
	add("top Clock", hud.TopCenter:FindFirstChild("Clock"))
	for _, name in { "Main", "Sub" } do
		local label = hud.TopCenter:FindFirstChild(name)
		if label and label.Text ~= "" then
			add("top " .. name, label)
		end
	end
	add("teams", hud.Teams)
	add("kill feed", hud:FindFirstChild("KillFeed"))
	add("announce", hud.Announce)
	for _, panel in hud.Currency:GetChildren() do
		if panel:IsA("Frame") then
			add("currency " .. panel.Name, panel)
		end
	end
	-- Dock des médaillons : chaque médaillon visible
	for _, medallion in hud.BottomCenter:GetChildren() do
		if medallion:IsA("Frame") then
			add("dock " .. medallion.Name, medallion)
		end
	end
	add("vote panel", hud.VotePanel)
	add("results", hud.Results)
	add("spectator", hud.Spectator)
	local touch = hud:FindFirstChild("TouchActions")
	if touch then
		for _, action in TOUCH_ACTIONS do
			add("touch " .. action, touch:FindFirstChild(action))
		end
	end
	return blocks
end

function Layout.HudProblems(hud, viewport)
	local rects = Layout.Rects(hud, viewport)
	local blocks = Layout.HudBlocks(hud, rects)
	local problems = {}
	for i = 1, #blocks do
		for j = i + 1, #blocks do
			local a, b = blocks[i], blocks[j]
			if Layout.Overlap(a.Rect, b.Rect) > 1 then
				table.insert(problems, a.Name .. " " .. Layout.Describe(a.Rect) .. " / " .. b.Name .. " " .. Layout.Describe(b.Rect))
			end
		end
		if not Layout.Inside(blocks[i].Rect, viewport, -1) then
			table.insert(problems, blocks[i].Name .. " hors écran " .. Layout.Describe(blocks[i].Rect))
		end
	end
	return problems, #blocks, rects
end

function Layout.Describe(r)
	return string.format("(%d,%d %dx%d)", math.floor(r.X + 0.5), math.floor(r.Y + 0.5), math.floor(r.W + 0.5), math.floor(r.H + 0.5))
end

return Layout

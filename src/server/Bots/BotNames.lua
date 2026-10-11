--[[
	BotNames.lua
	Pseudos crédibles pour les bots, générés par combinaison (aucun nom de
	compte réel n'est utilisé). Les noms déjà pris dans la partie sont évités.
]]

local BotNames = {}

local FIRST = {
	"Pixel", "Shadow", "Lucky", "Blocky", "Turbo", "Cosmic", "Sunny", "Frosty", "Ninja", "Mochi",
	"Taco", "Pepper", "Rocket", "Echo", "Nova", "Luna", "Maple", "Zippy", "Bubble", "Cookie",
	"Waffle", "Jelly", "Comet", "Storm", "Blaze", "Misty", "Pickle", "Noodle", "Sprinkle", "Biscuit",
	"Hazel", "Ruby", "Jade", "Ollie", "Milo", "Kira", "Nico", "Zara", "Teo", "Ivy",
}

local SECOND = {
	"Gamer", "Star", "Kid", "Dash", "Byte", "Wolf", "Bean", "Cat", "Pro", "Plays",
	"Bunny", "Panda", "Hopper", "Racer", "Builder", "Jumper", "Runner", "Spark", "Cloud", "Paws",
}

local SUFFIX = { "", "", "", "_07", "_99", "2013", "2015", "XD", "_YT", "123", "_x", "Official", "TV", "_1", "42" }

local random = Random.new()

local function pick<T>(list: { T }): T
	return list[random:NextInteger(1, #list)]
end

local function generate(): string
	local style = random:NextInteger(1, 5)
	if style == 1 then
		return pick(FIRST) .. pick(SECOND) .. pick(SUFFIX)
	elseif style == 2 then
		return string.lower(pick(FIRST)) .. "_" .. string.lower(pick(SECOND))
	elseif style == 3 then
		return pick(FIRST) .. tostring(random:NextInteger(10, 9999))
	elseif style == 4 then
		return "x" .. pick(FIRST) .. pick(SECOND) .. "x"
	end
	return pick(FIRST) .. "The" .. pick(SECOND)
end

-- Retourne un pseudo qui n'est pas dans "taken" (table de noms déjà utilisés)
function BotNames.Generate(taken: { [string]: boolean }): string
	for _ = 1, 30 do
		local name = generate()
		if not taken[name] and #name <= 20 then
			return name
		end
	end
	return "Player" .. tostring(random:NextInteger(1000, 99999))
end

return BotNames

--[[
	Signal.lua
	Petit signal Lua pour la communication entre services serveur
	(plus léger qu'un BindableEvent, passe les tables par référence).
]]

local Signal = {}
Signal.__index = Signal

export type Connection = { Disconnect: (Connection) -> (), Connected: boolean }

function Signal.new()
	return setmetatable({ _handlers = {} }, Signal)
end

function Signal:Connect(handler: (...any) -> ())
	local connection = { Connected = true }
	local handlers = self._handlers
	function connection.Disconnect(conn)
		conn.Connected = false
		local index = table.find(handlers, handler)
		if index then
			table.remove(handlers, index)
		end
	end
	table.insert(handlers, handler)
	return connection
end

function Signal:Fire(...: any)
	for _, handler in table.clone(self._handlers) do
		task.spawn(handler, ...)
	end
end

return Signal

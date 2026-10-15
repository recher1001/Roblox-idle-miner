--!strict
--[[
	Signal
	======
	Leichtgewichtiges Event-System (ohne BindableEvent).

		local s = Signal.new()
		local conn = s:Connect(function(x) print(x) end)
		s:Fire(5)
		conn:Disconnect()
]]

export type Connection = {
	Connected: boolean,
	Disconnect: (self: Connection) -> (),
}

export type Signal<T...> = {
	Connect: (self: Signal<T...>, fn: (T...) -> ()) -> Connection,
	Once: (self: Signal<T...>, fn: (T...) -> ()) -> Connection,
	Fire: (self: Signal<T...>, T...) -> (),
	DisconnectAll: (self: Signal<T...>) -> (),
}

local Signal = {}

function Signal.new<T...>(): Signal<T...>
	local handlers: { [Connection]: (T...) -> () } = {}

	local self = {} :: Signal<T...>

	function self.Connect(_: Signal<T...>, fn: (T...) -> ()): Connection
		local conn = { Connected = true } :: Connection
		function conn.Disconnect(c: Connection)
			if c.Connected then
				c.Connected = false
				handlers[c] = nil
			end
		end
		handlers[conn] = fn
		return conn
	end

	function self.Once(s: Signal<T...>, fn: (T...) -> ()): Connection
		local conn: Connection
		conn = s:Connect(function(...: T...)
			conn:Disconnect()
			fn(...)
		end)
		return conn
	end

	function self.Fire(_: Signal<T...>, ...: T...)
		-- Kopie, damit Handler sich während Fire trennen dürfen
		local conns: { Connection } = {}
		local fns: { (T...) -> () } = {}
		for conn, fn in handlers do
			table.insert(conns, conn)
			table.insert(fns, fn)
		end
		for i, conn in conns do
			if conn.Connected then
				task.spawn(fns[i], ...)
			end
		end
	end

	function self.DisconnectAll(_: Signal<T...>)
		for conn in handlers do
			conn.Connected = false
		end
		table.clear(handlers)
	end

	return self
end

return Signal

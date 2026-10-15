--!strict
--[[
	Maid
	====
	Sammelt Aufräum-Aufgaben (Connections, Instanzen, Funktionen, Threads)
	und räumt alles auf einmal auf. Wird u. a. pro Spieler-Session benutzt,
	damit beim Verlassen keine Connections übrig bleiben.
]]

export type Task = RBXScriptConnection | Instance | () -> () | thread | { Disconnect: (any) -> () }

export type Maid = {
	Give: (self: Maid, t: Task) -> Task,
	Clean: (self: Maid) -> (),
}

local Maid = {}

local function cleanTask(t: any)
	local kind = typeof(t)
	if kind == "RBXScriptConnection" or (kind == "table" and type(t.Disconnect) == "function") then
		t:Disconnect()
	elseif kind == "Instance" then
		t:Destroy()
	elseif kind == "function" then
		t()
	elseif kind == "thread" then
		pcall(task.cancel, t)
	end
end

function Maid.new(): Maid
	local tasks: { any } = {}
	local self = {} :: Maid

	function self.Give(_: Maid, t: Task): Task
		table.insert(tasks, t)
		return t
	end

	function self.Clean(_: Maid)
		-- in umgekehrter Reihenfolge aufräumen
		for i = #tasks, 1, -1 do
			local t = tasks[i]
			tasks[i] = nil
			local ok, err = pcall(function()
				cleanTask(t)
			end)
			if not ok then
				warn("[Maid] Aufräumen fehlgeschlagen:", err)
			end
		end
	end

	return self
end

return Maid

--!strict
--[[
	Remote
	======
	Wrapper für Anfragen an den Server. Bei Fehlern wird automatisch ein
	Toast mit der Server-Meldung angezeigt.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Net)
local Signal = require(Shared.Signal)

local Remote = {}

export type Result = { ok: boolean, msg: string?, data: any? }

-- Wird bei Fehlermeldungen gefeuert (Toasts hängen sich hier ein)
Remote.Failed = Signal.new() :: Signal.Signal<string>

function Remote.request(action: string, payload: { [string]: any }?): Result
	local ok, result = pcall(function()
		return Net.func("Request"):InvokeServer(action, payload or {})
	end)
	if not ok or type(result) ~= "table" then
		Remote.Failed:Fire("Verbindungsfehler - bitte erneut versuchen")
		return { ok = false, msg = "Verbindungsfehler" }
	end
	local r = result :: Result
	if not r.ok and r.msg then
		Remote.Failed:Fire(r.msg)
	end
	return r
end

--- Anfrage ohne zu blockieren
function Remote.send(action: string, payload: { [string]: any }?, callback: ((Result) -> ())?)
	task.spawn(function()
		local r = Remote.request(action, payload)
		if callback then
			callback(r)
		end
	end)
end

return Remote

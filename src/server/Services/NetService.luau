--!strict
--[[
	NetService
	==========
	Einziger Eingang für Client-Anfragen (RemoteFunction "Request").

	Jede Aktion wird mit einem Schema registriert. Vor dem Handler wird geprüft:
	  1. Aktion existiert
	  2. Rate-Limit (Token-Bucket pro Spieler + Aktion)
	  3. Spieler hat eine geladene Session
	  4. Payload ist eine Tabelle und alle Felder haben den erwarteten Typ
	     (Zahlen endlich, Strings kurz, keine unerwarteten Felder)
	Der Handler läuft in pcall - ein Fehler crasht nie den Server.

	Antwort an den Client: { ok: boolean, msg: string?, data: any? }
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Net)

local SessionService = require(script.Parent.SessionService)
local RateLimiter = require(script.Parent.Parent.Modules.RateLimiter)

type Session = SessionService.Session

-- Feldtypen: "string", "number", "boolean", "integer"; mit "?" am Ende optional
export type Schema = { [string]: string }
export type Handler = (session: Session, payload: { [string]: any }) -> (boolean, string?, any?)

type Entry = { Schema: Schema, Handler: Handler }

local NetService = {}

local actions: { [string]: Entry } = {}

local MAX_STRING = 64

function NetService.register(action: string, schema: Schema, handler: Handler)
	assert(actions[action] == nil, "Aktion doppelt registriert: " .. action)
	actions[action] = { Schema = schema, Handler = handler }
end

local function isFiniteNumber(v: any): boolean
	return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

local function validate(schema: Schema, payload: any): (boolean, { [string]: any })
	local clean: { [string]: any } = {}
	if payload == nil then
		payload = {}
	end
	if type(payload) ~= "table" then
		return false, clean
	end
	-- keine unbekannten Felder
	for k in payload do
		if type(k) ~= "string" or schema[k] == nil then
			return false, clean
		end
	end
	for field, typeName in schema do
		local optional = string.sub(typeName, -1) == "?"
		local base = if optional then string.sub(typeName, 1, -2) else typeName
		local v = payload[field]
		if v == nil then
			if not optional then
				return false, clean
			end
		elseif base == "string" then
			if type(v) ~= "string" or #v > MAX_STRING then
				return false, clean
			end
		elseif base == "number" then
			if not isFiniteNumber(v) then
				return false, clean
			end
		elseif base == "integer" then
			if not isFiniteNumber(v) or math.floor(v) ~= v then
				return false, clean
			end
		elseif base == "boolean" then
			if type(v) ~= "boolean" then
				return false, clean
			end
		else
			return false, clean
		end
		clean[field] = v
	end
	return true, clean
end

local function onInvoke(player: Player, action: any, payload: any): { ok: boolean, msg: string?, data: any? }
	if type(action) ~= "string" then
		return { ok = false, msg = "Ungültige Anfrage" }
	end
	local entry = actions[action]
	if not entry then
		return { ok = false, msg = "Unbekannte Aktion" }
	end
	if not RateLimiter.allow(player, action) then
		return { ok = false, msg = "Nicht so schnell!" }
	end
	local session = SessionService.get(player)
	if not session then
		return { ok = false, msg = "Deine Daten werden noch geladen..." }
	end
	local valid, clean = validate(entry.Schema, payload)
	if not valid then
		warn(string.format("[NetService] Ungültige Daten von %s für %s", player.Name, action))
		return { ok = false, msg = "Ungültige Anfrage" }
	end
	local success, ok, msg, data = pcall(entry.Handler, session, clean)
	if not success then
		warn(string.format("[NetService] Fehler in %s: %s", action, tostring(ok)))
		return { ok = false, msg = "Interner Fehler" }
	end
	return { ok = ok == true, msg = msg, data = data }
end

function NetService.start()
	Net.func("Request").OnServerInvoke = onInvoke
end

return NetService

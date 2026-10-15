--!strict
--[[
	Clock
	=====
	Einheitliche Zeitquelle für Server und Client.
	workspace:GetServerTimeNow() liefert Epoch-Sekunden (mit Nachkommastellen),
	die auf dem Client mit dem Server synchronisiert sind. Damit können
	Zyklus-Zeiten direkt für Animationen auf dem Client genutzt werden und
	Zeitstempel (Boosts, Cooldowns) sind auch nach Server-Wechseln gültig.
]]

local Clock = {}

function Clock.now(): number
	return workspace:GetServerTimeNow()
end

return Clock

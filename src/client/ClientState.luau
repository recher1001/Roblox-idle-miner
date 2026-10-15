--!strict
--[[
	ClientState
	===========
	Hält den letzten Zustand vom Server (Snapshot). Der Client rechnet NIE
	selbst Geld aus - er zeigt nur an, was der Server schickt. Für Anzeigen
	(Kosten, Raten) nutzt er die gleichen Formeln wie der Server.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Clock = require(Shared.Clock)
local Config = require(Shared.Config)
local Net = require(Shared.Net)
local Signal = require(Shared.Signal)
local Types = require(Shared.Types)

local ClientState = {}

ClientState.Snapshot = nil :: Types.Snapshot?
ClientState.Changed = Signal.new() :: Signal.Signal<Types.Snapshot>

function ClientState.get(): Types.Snapshot?
	return ClientState.Snapshot
end

--- Wartet, bis der erste Snapshot da ist
function ClientState.wait(): Types.Snapshot
	while not ClientState.Snapshot do
		task.wait(0.1)
	end
	return ClientState.Snapshot :: Types.Snapshot
end

--- Berechnungskontext für Formulas (nur zur Anzeige)
function ClientState.context(): Types.CalcContext
	local snap = ClientState.Snapshot
	local now = Clock.now()
	local cashMult, speedMult = 1, 1
	if snap and snap.Event and snap.Event.EndsAt > now then
		for _, e in Config.Events.List do
			if e.Id == snap.Event.Id then
				cashMult = e.CashMultiplier
				speedMult = e.SpeedMultiplier
			end
		end
	end
	return {
		Now = now,
		Passes = if snap then snap.Passes else {},
		EventCashMultiplier = cashMult,
		EventSpeedMultiplier = speedMult,
	}
end

function ClientState.start()
	Net.event("Sync").OnClientEvent:Connect(function(snapshot: Types.Snapshot)
		-- große Listen kommen nur bei Änderungen: sonst die alten übernehmen
		local previous = ClientState.Snapshot
		local data = snapshot.Data :: any
		if data.Shafts == nil then
			data.Shafts = if previous then previous.Data.Shafts else {}
		end
		if data.Managers == nil then
			data.Managers = if previous then previous.Data.Managers else {}
		end
		ClientState.Snapshot = snapshot
		ClientState.Changed:Fire(snapshot)
	end)
end

return ClientState

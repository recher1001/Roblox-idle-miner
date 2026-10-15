--!strict
--[[
	MineService
	===========
	Die eigentliche Simulation (100 % serverseitig):

	  Schacht  : Kumpel bauen Erz ab -> Schachtlager (bis Kapazität)
	  Aufzug   : holt Erz aus den Schachtlagern -> Aufzugslager (Oberfläche, stehlbar)
	  Lager    : Transporter bringen Erz zum Händler -> Geld

	Jede Station arbeitet in Zyklen. Ohne Manager startet der Spieler jeden
	Zyklus selbst (Klick/Tippen). Mit Manager startet der nächste Zyklus
	automatisch.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local BigNum = require(Shared.BigNum)
local Clock = require(Shared.Clock)
local Config = require(Shared.Config)
local Formulas = require(Shared.Formulas)

local NetService = require(script.Parent.NetService)
local PlotService = require(script.Parent.PlotService)
local SessionService = require(script.Parent.SessionService)
local RateLimiter = require(script.Parent.Parent.Modules.RateLimiter)

type Session = SessionService.Session
type BigNum = BigNum.BigNum

local MineService = {}

local lastVisualUpdate: { [Session]: number } = {}

----------------------------------------------------------------------
-- Zyklen verwalten
----------------------------------------------------------------------
local function setCycle(session: Session, key: string, running: boolean, start: number, finish: number)
	local cycle = session.Cycles[key]
	if not cycle then
		cycle = { Running = false, Start = 0, End = 0, Id = 0 }
		session.Cycles[key] = cycle
	end
	cycle.Running = running
	cycle.Start = start
	cycle.End = finish
	if running then
		cycle.Id += 1
	end
	PlotService.setCycle(session, key, cycle)
	session.Dirty = true
end

--- Stellt sicher, dass für jede Station ein Zyklus-Eintrag existiert
function MineService.ensureCycles(session: Session)
	local valid: { [string]: boolean } = {}
	for _, key in Formulas.allStationKeys(session.Data) do
		valid[key] = true
		if not session.Cycles[key] then
			session.Cycles[key] = { Running = false, Start = 0, End = 0, Id = 0 }
			PlotService.setCycle(session, key, session.Cycles[key])
		end
	end
	-- Einträge für nicht mehr existierende Schächte entfernen (nach Rebirth)
	for key in session.Cycles do
		if not valid[key] then
			session.Cycles[key] = nil
			session.Pending[key] = nil
		end
	end
end

--- Alle Zyklen stoppen (z. B. beim Rebirth)
function MineService.resetCycles(session: Session)
	for key, cycle in session.Cycles do
		cycle.Running = false
		session.Pending[key] = nil
		PlotService.setCycle(session, key, cycle)
	end
	MineService.ensureCycles(session)
	session.Dirty = true
end

local function totalShaftStock(session: Session): BigNum
	local sum = BigNum.zero()
	for _, shaft in session.Data.Shafts do
		sum = BigNum.add(sum, shaft.Stock)
	end
	return sum
end

--- Versucht, einen Zyklus zu starten. Gibt (ok, Fehlermeldung) zurück.
function MineService.tryStart(session: Session, key: string): (boolean, string?)
	local cycle = session.Cycles[key]
	if cycle and cycle.Running then
		return false, nil -- läuft schon (kein Fehler, nur nichts zu tun)
	end
	local data = session.Data
	local ctx = SessionService.context(session)
	local now = ctx.Now
	local area, index = Formulas.parseKey(key)

	if area == "Shaft" and index then
		local shaft = data.Shafts[index]
		if not shaft then
			return false, "Ebene nicht freigeschaltet"
		end
		if BigNum.gte(shaft.Stock, Formulas.shaftCapacity(data, index)) then
			return false, "Schachtlager voll! Aufzug starten."
		end
		session.Pending[key] = Formulas.shaftYield(data, index, ctx)
		setCycle(session, key, true, now, now + Formulas.shaftDuration(data, index, ctx))
		return true, nil
	elseif area == "Elevator" then
		if BigNum.isZero(totalShaftStock(session)) then
			return false, "Nichts abzuholen - erst abbauen!"
		end
		session.Pending[key] = Formulas.elevatorLoad(data, ctx)
		setCycle(session, key, true, now, now + Formulas.elevatorDuration(data, ctx))
		return true, nil
	elseif area == "Warehouse" then
		if BigNum.isZero(data.Elevator.Stock) then
			return false, "Aufzugslager leer - Aufzug starten!"
		end
		session.Pending[key] = Formulas.warehouseLoad(data, ctx)
		setCycle(session, key, true, now, now + Formulas.warehouseDuration(data, ctx))
		return true, nil
	end
	return false, "Unbekannte Station"
end

--- Zyklus abschließen und Ergebnis anwenden
local function complete(session: Session, key: string)
	local data = session.Data
	local amount = session.Pending[key] or BigNum.zero()
	session.Pending[key] = nil
	local cycle = session.Cycles[key]
	setCycle(session, key, false, cycle.Start, cycle.End)

	local area, index = Formulas.parseKey(key)
	if area == "Shaft" and index then
		local shaft = data.Shafts[index]
		if shaft then
			local cap = Formulas.shaftCapacity(data, index)
			shaft.Stock = BigNum.min(BigNum.add(shaft.Stock, amount), cap)
		end
	elseif area == "Elevator" then
		-- von oben nach unten einsammeln, bis die Kabine voll ist
		local remaining = amount
		local collected = BigNum.zero()
		for _, shaft in data.Shafts do
			if BigNum.isZero(remaining) or BigNum.isNegative(remaining) then
				break
			end
			local take = BigNum.min(shaft.Stock, remaining)
			if not BigNum.isZero(take) then
				shaft.Stock = BigNum.clampPositive(BigNum.sub(shaft.Stock, take))
				remaining = BigNum.sub(remaining, take)
				collected = BigNum.add(collected, take)
			end
		end
		data.Elevator.Stock = BigNum.add(data.Elevator.Stock, collected)
	elseif area == "Warehouse" then
		local take = BigNum.min(amount, data.Elevator.Stock)
		if not BigNum.isZero(take) then
			data.Elevator.Stock = BigNum.clampPositive(BigNum.sub(data.Elevator.Stock, take))
			local cash = Formulas.saleValue(data, take, SessionService.context(session))
			SessionService.addCash(session, cash)
			SessionService.effect(session.Player, "Sale", { Amount = cash })
		end
	end
	session.Dirty = true
end

----------------------------------------------------------------------
-- Spieler-Aktion "Arbeiten" (Klick auf Station oder UI-Button)
----------------------------------------------------------------------
function MineService.work(session: Session, key: string): (boolean, string?)
	if not Formulas.parseKey(key) or not Formulas.getStation(session.Data, key) then
		return false, "Unbekannte Station"
	end
	local cycle = session.Cycles[key]
	if cycle and cycle.Running then
		return true, nil
	end
	local ok, msg = MineService.tryStart(session, key)
	if ok then
		SessionService.effect(session.Player, "Work", { Key = key })
	end
	return ok, msg
end

----------------------------------------------------------------------
-- Tick
----------------------------------------------------------------------
local function tickSession(session: Session, now: number)
	for key, cycle in session.Cycles do
		if cycle.Running and now >= cycle.End then
			complete(session, key)
		end
	end
	-- Automatisierung: Stationen mit Manager starten selbst
	for _, manager in session.Data.Managers do
		local key = manager.AssignedTo
		if key then
			local cycle = session.Cycles[key]
			if cycle and not cycle.Running then
				MineService.tryStart(session, key)
			end
		end
	end
	local last = lastVisualUpdate[session] or 0
	if now - last >= Config.World.LabelUpdateInterval then
		lastVisualUpdate[session] = now
		PlotService.updateVisuals(session)
	end
end

function MineService.start()
	SessionService.onStart(20, function(session)
		MineService.ensureCycles(session)
	end)
	SessionService.onEnd(10, function(session)
		lastVisualUpdate[session] = nil
	end)

	PlotService.setStationClickHandler(function(session, key)
		if not RateLimiter.allow(session.Player, "Work") then
			return
		end
		local ok, msg = MineService.work(session, key)
		if not ok and msg then
			SessionService.notify(session.Player, msg, "warn")
		end
	end)

	NetService.register("Work", { Key = "string" }, function(session, payload)
		return MineService.work(session, payload.Key)
	end)
	NetService.register("SetSection", { Section = "integer" }, function(session, payload)
		PlotService.setSection(session, payload.Section)
		return true
	end)
	NetService.register("RequestSync", {}, function(session)
		SessionService.resendAll(session)
		SessionService.syncNow(session)
		return true
	end)

	local accumulator = 0
	RunService.Heartbeat:Connect(function(dt)
		accumulator += dt
		if accumulator < Config.World.TickInterval then
			return
		end
		accumulator = 0
		local now = Clock.now()
		for _, session in SessionService.all() do
			local ok, err = pcall(function()
				tickSession(session, now)
			end)
			if not ok then
				warn("[MineService] Tick-Fehler:", err)
			end
		end
	end)
end

return MineService

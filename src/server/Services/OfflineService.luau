--!strict
--[[
	OfflineService
	==============
	Berechnet beim Beitreten, was seit dem letzten Besuch verdient wurde.
	Nur automatisierte Stationen (mit Manager) arbeiten offline. Gerechnet
	wird mit dem Engpass aus Schächten, Aufzug und Lager (wie online).
	Obergrenze: Config.Offline.MaxHours (mit Gamepass MaxHoursWithPass).

	Der Spieler sieht ein Popup und kann normal oder für Gems x2 einsammeln.
	Verlässt er das Spiel ohne Einsammeln, wird automatisch gutgeschrieben.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local BigNum = require(Shared.BigNum)
local Config = require(Shared.Config)
local Formulas = require(Shared.Formulas)
local Net = require(Shared.Net)

local NetService = require(script.Parent.NetService)
local SessionService = require(script.Parent.SessionService)

type Session = SessionService.Session
type Pending = { Amount: BigNum.BigNum, Seconds: number }

local OfflineService = {}

local pending: { [Session]: Pending } = {}

--- Reine Berechnung (auch für Tests nutzbar)
function OfflineService.compute(session: Session, elapsed: number): (BigNum.BigNum, number, boolean)
	local cap = Formulas.offlineCapSeconds(session.Passes)
	local seconds = math.clamp(elapsed, 0, cap)
	-- ohne Server-Event rechnen (Events gelten nur live)
	local ctx = SessionService.context(session)
	ctx.EventCashMultiplier = 1
	ctx.EventSpeedMultiplier = 1
	local income = Formulas.incomePerSecond(session.Data, ctx, true)
	local amount = BigNum.mulNum(income, seconds * Config.Offline.Efficiency)
	return amount, seconds, elapsed > cap
end

local function grant(session: Session, double: boolean): (boolean, string?)
	local p = pending[session]
	if not p then
		return false, "Nichts einzusammeln"
	end
	local amount = p.Amount
	if double then
		if not SessionService.spendGems(session, Config.Offline.DoubleGemCost) then
			return false, "Nicht genug Gems"
		end
		amount = BigNum.mulNum(amount, 2)
	end
	pending[session] = nil
	SessionService.addCash(session, amount)
	SessionService.effect(session.Player, "Cash", { Amount = amount })
	return true, nil
end

local function onStart(session: Session)
	local data = session.Data
	if data.LastOnline <= 0 then
		return -- neuer Spieler
	end
	local elapsed = os.time() - data.LastOnline
	if elapsed < Config.Offline.MinSeconds then
		return
	end
	local amount, seconds, capped = OfflineService.compute(session, elapsed)
	if BigNum.isZero(amount) then
		if elapsed > 300 then
			SessionService.notify(session.Player, "Tipp: Stelle Manager ein, dann verdienst du auch offline!", "info")
		end
		return
	end
	pending[session] = { Amount = amount, Seconds = seconds }
	-- kurz warten, bis die UI des Clients steht
	task.delay(2.5, function()
		if pending[session] and session.Player.Parent then
			Net.event("OfflineEarnings"):FireClient(session.Player, {
				Amount = amount,
				Seconds = seconds,
				Capped = capped,
			})
		end
	end)
end

--- Nur für Tests: tut so, als wäre der Spieler X Sekunden offline gewesen
--- (Popup erscheint und kann wirklich eingesammelt werden)
function OfflineService.simulate(session: Session, elapsed: number)
	local amount, seconds, capped = OfflineService.compute(session, elapsed)
	if BigNum.isZero(amount) then
		SessionService.notify(session.Player, "Offline verdienen nur Stationen MIT Manager!", "warn")
		return
	end
	pending[session] = { Amount = amount, Seconds = seconds }
	Net.event("OfflineEarnings"):FireClient(session.Player, { Amount = amount, Seconds = seconds, Capped = capped })
end

function OfflineService.start()
	SessionService.onStart(30, onStart)
	-- Nicht eingesammelt? Beim Verlassen automatisch gutschreiben (vor dem Speichern)
	SessionService.onEnd(1, function(session)
		if pending[session] then
			grant(session, false)
		end
		pending[session] = nil
	end)
	NetService.register("ClaimOffline", { Double = "boolean" }, function(session, payload)
		return grant(session, payload.Double)
	end)
end

return OfflineService

--!strict
--[[
	UpgradeService
	==============
	Kauf von Level-Upgrades (Tempo, Erzwert, Kapazität ...) und Freischalten
	neuer Ebenen. Kosten kommen aus Formulas.upgradeQuote, also exakt die
	gleiche Rechnung, die der Client anzeigt. Der Server prüft alles erneut.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Clock = require(Shared.Clock)
local Config = require(Shared.Config)
local Formulas = require(Shared.Formulas)

local DataTemplate = require(script.Parent.Parent.Modules.DataTemplate)
local MineService = require(script.Parent.MineService)
local NetService = require(script.Parent.NetService)
local PlotService = require(script.Parent.PlotService)
local SessionService = require(script.Parent.SessionService)

type Session = SessionService.Session

local UpgradeService = {}

function UpgradeService.upgrade(session: Session, key: string, trackId: string, amount: number): (boolean, string?)
	if not table.find(Config.BuyAmounts, amount) then
		return false, "Ungültige Menge"
	end
	local area = Formulas.parseKey(key)
	local station = Formulas.getStation(session.Data, key)
	if not area or not station or not Formulas.trackDef(area, trackId) then
		return false, "Unbekanntes Upgrade"
	end
	local quote = Formulas.upgradeQuote(session.Data, key, trackId, amount, Clock.now())
	if not quote then
		return false, "Unbekanntes Upgrade"
	end
	if quote.Maxed then
		return false, "Maximales Level erreicht!"
	end
	if not quote.Affordable or not SessionService.spendCash(session, quote.Cost) then
		return false, "Nicht genug Geld"
	end
	station.Levels[trackId] = Formulas.level(station, trackId) + quote.Levels
	if area == "Shaft" then
		SessionService.shaftsChanged(session)
	end
	SessionService.effect(session.Player, "Purchase", {
		Key = key,
		Track = trackId,
		Levels = quote.Levels,
		Cost = quote.Cost,
	})
	PlotService.updateVisuals(session)
	return true, nil
end

function UpgradeService.unlockShaft(session: Session): (boolean, string?)
	local data = session.Data
	local nextIndex = #data.Shafts + 1
	local cost = Formulas.nextShaftCost(data)
	if not cost then
		return false, "Alle Ebenen freigeschaltet!"
	end
	if not SessionService.spendCash(session, cost) then
		return false, "Nicht genug Geld"
	end
	local def = Formulas.shaftDef(nextIndex)
	data.Shafts[nextIndex] = DataTemplate.newStation("Shaft")
	SessionService.shaftsChanged(session)
	session.ViewSection = 0 -- automatisch zum neuen tiefsten Abschnitt
	MineService.ensureCycles(session)
	PlotService.refreshLevels(session)
	SessionService.effect(session.Player, "Unlock", { Index = nextIndex, Name = def.Name })
	SessionService.notify(session.Player, string.format("⛏️ Neue Ebene: %s!", def.Name), "success")
	return true, nil
end

function UpgradeService.start()
	NetService.register("Upgrade", { Key = "string", Track = "string", Amount = "integer" }, function(session, payload)
		return UpgradeService.upgrade(session, payload.Key, payload.Track, payload.Amount)
	end)
	NetService.register("UnlockShaft", {}, function(session)
		return UpgradeService.unlockShaft(session)
	end)
end

return UpgradeService

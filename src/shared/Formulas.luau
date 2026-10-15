--!strict
--[[
	Formulas
	========
	Alle Spielformeln an einem Ort. Wird vom Server (autoritativ) UND vom Client
	(nur zur Anzeige) benutzt, damit die angezeigten Werte exakt stimmen.

	Stationen werden über einen "StationKey" adressiert:
		"Shaft:1" ... "Shaft:10", "Elevator", "Warehouse"
]]

local BigNum = require(script.Parent.BigNum)
local Config = require(script.Parent.Config)
local Types = require(script.Parent.Types)

type BigNum = BigNum.BigNum
type PlayerData = Types.PlayerData
type StationData = Types.StationData
type ManagerData = Types.ManagerData
type CalcContext = Types.CalcContext

local Formulas = {}

----------------------------------------------------------------------
-- Station-Keys
----------------------------------------------------------------------
function Formulas.shaftKey(index: number): string
	return "Shaft:" .. tostring(index)
end

--- Liefert Bereich und (bei Schächten) Index. Ungültige Keys -> nil
function Formulas.parseKey(key: string): (string?, number?)
	if key == "Elevator" or key == "Warehouse" then
		return key, nil
	end
	local idx = string.match(key, "^Shaft:(%d+)$")
	if idx then
		local n = tonumber(idx)
		if n and n >= 1 and n <= #Config.Shafts then
			return "Shaft", n
		end
	end
	return nil, nil
end

function Formulas.getStation(data: PlayerData, key: string): StationData?
	local area, index = Formulas.parseKey(key)
	if area == "Shaft" and index then
		return data.Shafts[index]
	elseif area == "Elevator" then
		return data.Elevator
	elseif area == "Warehouse" then
		return data.Warehouse
	end
	return nil
end

--- Alle existierenden Stationen des Spielers in fester Reihenfolge
function Formulas.allStationKeys(data: PlayerData): { string }
	local keys = {}
	for i = 1, #data.Shafts do
		table.insert(keys, Formulas.shaftKey(i))
	end
	table.insert(keys, "Elevator")
	table.insert(keys, "Warehouse")
	return keys
end

function Formulas.stationDisplayName(key: string): string
	local area, index = Formulas.parseKey(key)
	if area == "Shaft" and index then
		return string.format("Ebene %d: %s", index, Config.Shafts[index].Name)
	elseif area == "Elevator" then
		return "Aufzug"
	elseif area == "Warehouse" then
		return "Lager & Verkauf"
	end
	return key
end

----------------------------------------------------------------------
-- Tracks
----------------------------------------------------------------------
function Formulas.tracksFor(area: string): { Config.TrackDef }
	local t = (Config.Tracks :: any)[area]
	return if t then t else {}
end

function Formulas.trackDef(area: string, trackId: string): Config.TrackDef?
	for _, def in Formulas.tracksFor(area) do
		if def.Id == trackId then
			return def
		end
	end
	return nil
end

function Formulas.level(station: StationData, trackId: string): number
	local l = station.Levels[trackId]
	return if type(l) == "number" and l >= 1 then l else 1
end

local function linearMult(def: Config.TrackDef?, level: number): number
	if not def then
		return 1
	end
	local mult = 1 + (def.PerLevel or 0) * (level - 1)
	if def.MilestoneEvery and def.MilestoneMultiplier then
		mult *= def.MilestoneMultiplier ^ (level // def.MilestoneEvery)
	end
	return mult
end

local function loadFor(def: Config.TrackDef?, level: number): BigNum
	if not def then
		return BigNum.new(1)
	end
	local base = def.BaseLoad or 1
	local growth = def.LoadGrowth or 1
	return BigNum.mul(BigNum.new(base), BigNum.powNum(growth, level - 1))
end

----------------------------------------------------------------------
-- Manager
----------------------------------------------------------------------
function Formulas.rarityDef(id: string): Config.RarityDef
	for _, r in Config.Managers.Rarities do
		if r.Id == id then
			return r
		end
	end
	return Config.Managers.Rarities[1]
end

function Formulas.rarityIndex(id: string): number
	for i, r in Config.Managers.Rarities do
		if r.Id == id then
			return i
		end
	end
	return 1
end

function Formulas.managerFor(data: PlayerData, key: string): ManagerData?
	for _, m in data.Managers do
		if m.AssignedTo == key then
			return m
		end
	end
	return nil
end

function Formulas.findManager(data: PlayerData, id: string): ManagerData?
	for _, m in data.Managers do
		if m.Id == id then
			return m
		end
	end
	return nil
end

function Formulas.isAbilityActive(manager: ManagerData?, now: number): boolean
	return manager ~= nil and manager.ActiveUntil > now
end

--- Multiplikator einer aktiven Fähigkeit eines bestimmten Typs, sonst 1
local function abilityMult(manager: ManagerData?, abilityId: string, now: number): number
	if manager and manager.Ability == abilityId and manager.ActiveUntil > now then
		return Formulas.rarityDef(manager.Rarity).AbilityMultiplier
	end
	return 1
end

local function passiveSpeed(manager: ManagerData?): number
	if manager then
		return Formulas.rarityDef(manager.Rarity).PassiveSpeed
	end
	return 1
end

function Formulas.abilityValueText(manager: ManagerData): string
	local rarity = Formulas.rarityDef(manager.Rarity)
	if manager.Ability == "Discount" then
		return string.format("%d%%", math.floor(rarity.Discount * 100 + 0.5))
	end
	return string.format("x%s", tostring(rarity.AbilityMultiplier))
end

function Formulas.abilityDescription(manager: ManagerData): string
	local def = Config.Managers.Abilities[manager.Ability]
	if not def then
		return ""
	end
	return string.format(def.Description, Formulas.abilityValueText(manager))
end

function Formulas.managerHireCost(data: PlayerData, area: string): BigNum
	local base = Config.Managers.HireBaseCost[area] or 100
	local hired = data.ManagersHired[area] or 0
	return BigNum.mul(BigNum.new(base), BigNum.powNum(Config.Managers.HireCostGrowth, hired))
end

----------------------------------------------------------------------
-- Globale Multiplikatoren
----------------------------------------------------------------------
function Formulas.isBoostActive(data: PlayerData, boostId: string, now: number): boolean
	local untilTime = data.Boosts[boostId]
	return type(untilTime) == "number" and untilTime > now
end

--- Hat der Spieler eine Admin-Kraft?
function Formulas.hasPower(data: PlayerData, powerId: string): boolean
	return data.Powers ~= nil and data.Powers[powerId] == true
end

function Formulas.rebirthMultiplier(points: number): number
	return 1 + points * Config.Rebirth.MultiplierPerPoint
end

--- Alles, was den Verkaufserlös multipliziert (ohne Lager-Verkaufspreis)
function Formulas.cashMultiplier(data: PlayerData, ctx: CalcContext): number
	local mult = Formulas.rebirthMultiplier(data.RebirthPoints)
	if Formulas.isBoostActive(data, "Cash", ctx.Now) then
		mult *= 2
	end
	if ctx.Passes.DoubleCash then
		mult *= 2
	end
	mult *= ctx.EventCashMultiplier
	if Formulas.hasPower(data, "GoldenTouch") then
		mult *= Config.Admin.GoldenTouchMultiplier
	end
	return mult
end

function Formulas.globalSpeedMultiplier(data: PlayerData, ctx: CalcContext): number
	local mult = ctx.EventSpeedMultiplier
	if Formulas.isBoostActive(data, "Speed", ctx.Now) then
		mult *= 2
	end
	if Formulas.hasPower(data, "MineTurbo") then
		mult *= Config.Admin.MineTurboMultiplier
	end
	return mult
end

local function clampDuration(d: number): number
	return math.max(Config.MinCycleDuration, d)
end

----------------------------------------------------------------------
-- Schacht
----------------------------------------------------------------------
--- Erzwert pro Zyklus OHNE aktive Fähigkeit (Basis für Lagerplatz)
function Formulas.shaftBaseYield(data: PlayerData, index: number): BigNum
	local def = Config.Shafts[index]
	local station = data.Shafts[index]
	if not def or not station then
		return BigNum.zero()
	end
	local valueMult = linearMult(Formulas.trackDef("Shaft", "Value"), Formulas.level(station, "Value"))
	return BigNum.mulNum(BigNum.new(def.BaseYield), valueMult)
end

function Formulas.shaftYield(data: PlayerData, index: number, ctx: CalcContext): BigNum
	local key = Formulas.shaftKey(index)
	local manager = Formulas.managerFor(data, key)
	return BigNum.mulNum(Formulas.shaftBaseYield(data, index), abilityMult(manager, "Value", ctx.Now))
end

function Formulas.shaftDuration(data: PlayerData, index: number, ctx: CalcContext, ignoreAbility: boolean?): number
	local def = Config.Shafts[index]
	local station = data.Shafts[index]
	if not def or not station then
		return math.huge
	end
	local manager = Formulas.managerFor(data, Formulas.shaftKey(index))
	local speed = linearMult(Formulas.trackDef("Shaft", "Speed"), Formulas.level(station, "Speed"))
	speed *= passiveSpeed(manager)
	if not ignoreAbility then
		speed *= abilityMult(manager, "Speed", ctx.Now)
	end
	speed *= Formulas.globalSpeedMultiplier(data, ctx)
	return clampDuration(def.BaseCycle / speed)
end

function Formulas.shaftCapacity(data: PlayerData, index: number): BigNum
	local station = data.Shafts[index]
	if not station then
		return BigNum.zero()
	end
	local def = Formulas.trackDef("Shaft", "Capacity")
	local level = Formulas.level(station, "Capacity")
	local cycles = ((def and def.BaseCycles) or 10) + ((def and def.PerLevel) or 0) * (level - 1)
	return BigNum.mulNum(Formulas.shaftBaseYield(data, index), cycles)
end

----------------------------------------------------------------------
-- Aufzug
----------------------------------------------------------------------
function Formulas.elevatorDuration(data: PlayerData, ctx: CalcContext, ignoreAbility: boolean?): number
	local manager = Formulas.managerFor(data, "Elevator")
	local base = Config.Elevator.BaseTrip + Config.Elevator.PerShaftTrip * #data.Shafts
	local speed = linearMult(Formulas.trackDef("Elevator", "Speed"), Formulas.level(data.Elevator, "Speed"))
	speed *= passiveSpeed(manager)
	if not ignoreAbility then
		speed *= abilityMult(manager, "Speed", ctx.Now)
	end
	speed *= Formulas.globalSpeedMultiplier(data, ctx)
	return clampDuration(base / speed)
end

function Formulas.elevatorLoad(data: PlayerData, ctx: CalcContext, ignoreAbility: boolean?): BigNum
	local manager = Formulas.managerFor(data, "Elevator")
	local load = loadFor(Formulas.trackDef("Elevator", "Capacity"), Formulas.level(data.Elevator, "Capacity"))
	if not ignoreAbility then
		load = BigNum.mulNum(load, abilityMult(manager, "Capacity", ctx.Now))
	end
	return load
end

----------------------------------------------------------------------
-- Lager / Verkauf
----------------------------------------------------------------------
function Formulas.warehouseDuration(data: PlayerData, ctx: CalcContext, ignoreAbility: boolean?): number
	local manager = Formulas.managerFor(data, "Warehouse")
	local speed = linearMult(Formulas.trackDef("Warehouse", "Speed"), Formulas.level(data.Warehouse, "Speed"))
	speed *= passiveSpeed(manager)
	if not ignoreAbility then
		speed *= abilityMult(manager, "Speed", ctx.Now)
	end
	speed *= Formulas.globalSpeedMultiplier(data, ctx)
	return clampDuration(Config.Warehouse.BaseCycle / speed)
end

function Formulas.warehouseLoad(data: PlayerData, ctx: CalcContext, ignoreAbility: boolean?): BigNum
	local manager = Formulas.managerFor(data, "Warehouse")
	local load = loadFor(Formulas.trackDef("Warehouse", "Capacity"), Formulas.level(data.Warehouse, "Capacity"))
	if not ignoreAbility then
		load = BigNum.mulNum(load, abilityMult(manager, "Capacity", ctx.Now))
	end
	return load
end

function Formulas.sellPriceMultiplier(data: PlayerData): number
	return linearMult(Formulas.trackDef("Warehouse", "Value"), Formulas.level(data.Warehouse, "Value"))
end

--- Erlös für eine bestimmte Erzmenge (inkl. aller Multiplikatoren)
function Formulas.saleValue(data: PlayerData, oreValue: BigNum, ctx: CalcContext): BigNum
	return BigNum.mulNum(oreValue, Formulas.sellPriceMultiplier(data) * Formulas.cashMultiplier(data, ctx))
end

----------------------------------------------------------------------
-- Einkommen pro Sekunde (Engpass-Rechnung)
--   requireAutomation = true: nur Stationen mit Manager zählen (Offline)
----------------------------------------------------------------------
function Formulas.incomePerSecond(data: PlayerData, ctx: CalcContext, requireAutomation: boolean): BigNum
	local shaftSum = BigNum.zero()
	for i = 1, #data.Shafts do
		local automated = Formulas.managerFor(data, Formulas.shaftKey(i)) ~= nil
		if automated or not requireAutomation then
			local rate = BigNum.divNum(Formulas.shaftBaseYield(data, i), Formulas.shaftDuration(data, i, ctx, true))
			shaftSum = BigNum.add(shaftSum, rate)
		end
	end
	local elevatorRate = BigNum.zero()
	if not requireAutomation or Formulas.managerFor(data, "Elevator") then
		elevatorRate = BigNum.divNum(Formulas.elevatorLoad(data, ctx, true), Formulas.elevatorDuration(data, ctx, true))
	end
	local warehouseRate = BigNum.zero()
	if not requireAutomation or Formulas.managerFor(data, "Warehouse") then
		warehouseRate =
			BigNum.divNum(Formulas.warehouseLoad(data, ctx, true), Formulas.warehouseDuration(data, ctx, true))
	end
	local bottleneck = BigNum.min(shaftSum, BigNum.min(elevatorRate, warehouseRate))
	return Formulas.saleValue(data, bottleneck, ctx)
end

----------------------------------------------------------------------
-- Upgrade-Kosten
----------------------------------------------------------------------
local function trackBaseCost(area: string, index: number?, def: Config.TrackDef): number
	if area == "Shaft" and index then
		return (def.CostFactor or 1) * Config.Shafts[index].BaseYield
	end
	return def.BaseCost or 10
end

--- Rabatt durch aktive "Sparfuchs"-Fähigkeit
function Formulas.discountFor(data: PlayerData, key: string, now: number): number
	local manager = Formulas.managerFor(data, key)
	if manager and manager.Ability == "Discount" and manager.ActiveUntil > now then
		return Formulas.rarityDef(manager.Rarity).Discount
	end
	return 0
end

--- Kosten für n Level ab aktuellem Level (geometrische Reihe)
local function costForLevels(base: number, growth: number, level: number, n: number, discount: number): BigNum
	local first = BigNum.mul(BigNum.new(base), BigNum.powNum(growth, level - 1))
	local seriesFactor: BigNum
	if growth == 1 then
		seriesFactor = BigNum.new(n)
	else
		-- (g^n - 1) / (g - 1)
		seriesFactor = BigNum.divNum(BigNum.sub(BigNum.powNum(growth, n), BigNum.one()), growth - 1)
	end
	return BigNum.mulNum(BigNum.mul(first, seriesFactor), 1 - discount)
end

export type UpgradeQuote = {
	Levels: number, -- wie viele Level gekauft werden
	Cost: BigNum,
	Affordable: boolean,
	Maxed: boolean,
}

--- Angebot für einen Upgrade-Kauf. amount = 1, 10, ... oder -1 (Maximum leistbar)
function Formulas.upgradeQuote(
	data: PlayerData,
	key: string,
	trackId: string,
	amount: number,
	now: number
): UpgradeQuote?
	local area, index = Formulas.parseKey(key)
	if not area then
		return nil
	end
	local station = Formulas.getStation(data, key)
	local def = Formulas.trackDef(area, trackId)
	if not station or not def then
		return nil
	end
	local level = Formulas.level(station, trackId)
	local remaining = def.MaxLevel - level
	if remaining <= 0 then
		return { Levels = 0, Cost = BigNum.zero(), Affordable = false, Maxed = true }
	end
	local base = trackBaseCost(area, index, def)
	local discount = Formulas.discountFor(data, key, now)
	local n: number
	if amount == -1 then
		-- maximal leistbare Anzahl: n = floor(log_g(cash*(g-1)/first + 1))
		local first = costForLevels(base, def.Growth, level, 1, discount)
		if BigNum.lt(data.Cash, first) then
			n = 1
		elseif def.Growth == 1 then
			n = math.floor(BigNum.toNumber(BigNum.div(data.Cash, first)))
		else
			local ratio = BigNum.add(BigNum.mulNum(BigNum.div(data.Cash, first), def.Growth - 1), BigNum.one())
			n = math.floor(BigNum.log10(ratio) / math.log10(def.Growth))
			-- Fließkomma-Sicherheit: notfalls eins zurück
			if n >= 1 and BigNum.gt(costForLevels(base, def.Growth, level, n, discount), data.Cash) then
				n -= 1
			end
			n = math.max(n, 1)
		end
	else
		n = math.max(1, math.floor(amount))
	end
	n = math.clamp(n, 1, remaining)
	local cost = costForLevels(base, def.Growth, level, n, discount)
	return {
		Levels = n,
		Cost = cost,
		Affordable = BigNum.gte(data.Cash, cost),
		Maxed = false,
	}
end

--- Text für die Wirkung eines Tracks auf einem Level (für die UI)
function Formulas.trackEffectText(data: PlayerData, key: string, trackId: string, level: number): string
	local area, index = Formulas.parseKey(key)
	local def = if area then Formulas.trackDef(area, trackId) else nil
	if not area or not def then
		return ""
	end
	if trackId == "Speed" then
		local base: number
		if area == "Shaft" and index then
			base = Config.Shafts[index].BaseCycle
		elseif area == "Elevator" then
			base = Config.Elevator.BaseTrip + Config.Elevator.PerShaftTrip * #data.Shafts
		else
			base = Config.Warehouse.BaseCycle
		end
		local duration = math.max(Config.MinCycleDuration, base / linearMult(def, level))
		return string.format("%.2fs / Zyklus", duration)
	elseif trackId == "Value" then
		if area == "Shaft" and index then
			local yield = BigNum.mulNum(BigNum.new(Config.Shafts[index].BaseYield), linearMult(def, level))
			return BigNum.formatMoney(yield, Config.CurrencySymbol) .. " / Zyklus"
		end
		return string.format("x%.2f Preis", linearMult(def, level))
	elseif trackId == "Capacity" then
		if area == "Shaft" then
			local cycles = (def.BaseCycles or 10) + (def.PerLevel or 0) * (level - 1)
			return string.format("%d Zyklen Lager", cycles)
		end
		return BigNum.format(loadFor(def, level)) .. " pro Fahrt"
	end
	return ""
end

----------------------------------------------------------------------
-- Schacht freischalten
----------------------------------------------------------------------
function Formulas.nextShaftCost(data: PlayerData): BigNum?
	local nextIndex = #data.Shafts + 1
	local def = Config.Shafts[nextIndex]
	if not def then
		return nil
	end
	return BigNum.new(def.UnlockCost)
end

----------------------------------------------------------------------
-- Rebirth
----------------------------------------------------------------------
function Formulas.rebirthPointsFor(runCash: BigNum): number
	local cfg = Config.Rebirth
	local ratio = BigNum.divNum(runCash, cfg.MinRunCash)
	if BigNum.lt(ratio, BigNum.one()) then
		return 0
	end
	local l = BigNum.log10(ratio) * cfg.PointsExponent
	if l > 300 then
		l = 300
	end
	return math.floor(cfg.PointsScale * 10 ^ l)
end

function Formulas.rebirthGems(points: number): number
	local cfg = Config.Rebirth
	return cfg.GemsBase + math.floor(points / 10) * cfg.GemsPerTenPoints
end

----------------------------------------------------------------------
-- Offline / Daily
----------------------------------------------------------------------
function Formulas.offlineCapSeconds(passes: { [string]: boolean }): number
	local hours = if passes.LongOffline then Config.Offline.MaxHoursWithPass else Config.Offline.MaxHours
	return hours * 3600
end

--- Belohnung für einen Tag der Serie (1-basiert, wiederholt sich nach dem letzten Tag)
function Formulas.dailyReward(streakDay: number): Config.DailyReward
	local rewards = Config.Daily.Rewards
	local idx = ((streakDay - 1) % #rewards) + 1
	return rewards[idx]
end

--- Tägliche Belohnung verfügbar? (neuer UTC-Kalendertag seit dem letzten Abholen)
function Formulas.dailyAvailable(data: PlayerData, now: number): boolean
	return math.floor(now / 86400) > math.floor(data.LastDailyClaim / 86400)
end

--- Welcher Tag der Serie wäre die nächste Abholung? (Serie bricht nach StreakResetHours)
function Formulas.nextDailyStreak(data: PlayerData, now: number): number
	if data.LastDailyClaim <= 0 or now - data.LastDailyClaim > Config.Daily.StreakResetHours * 3600 then
		return 1
	end
	return data.DailyStreak + 1
end

--- Formatiert Sekunden als "1h 23m" / "4m 05s" / "12s"
function Formulas.formatDuration(seconds: number): string
	seconds = math.max(0, math.floor(seconds))
	local h = seconds // 3600
	local m = (seconds % 3600) // 60
	local s = seconds % 60
	if h > 0 then
		return string.format("%dh %02dm", h, m)
	elseif m > 0 then
		return string.format("%dm %02ds", m, s)
	end
	return string.format("%ds", s)
end

return Formulas

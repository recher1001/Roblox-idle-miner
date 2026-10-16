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
-- Ebenen (1-10 handgemacht in Config.Shafts, danach automatisch erzeugt)
----------------------------------------------------------------------
export type ShaftInfo = {
	Index: number,
	Name: string,
	Ore: string,
	OreColor: Color3,
	RockColor: Color3,
	BaseCycle: number,
	BaseYield: BigNum,
	UnlockCost: BigNum,
	Tier: number,
}

local ROMAN = { "I", "II", "III", "IV", "V", "VI", "VII", "VIII", "IX", "X" }
local function roman(n: number): string
	if n <= #ROMAN then
		return ROMAN[n]
	end
	local tens = n // 10
	local rest = n % 10
	return string.rep("X", tens) .. (if rest > 0 then ROMAN[rest] else "")
end

local shaftCache: { [number]: ShaftInfo } = {}

function Formulas.shaftCount(): number
	return Config.ShaftCount
end

function Formulas.shaftDef(index: number): ShaftInfo
	local cached = shaftCache[index]
	if cached then
		return cached
	end
	local gen = Config.ShaftGen
	local ores = gen.Ores
	local ore = ores[((index - 1) % #ores) + 1]
	local tier = (index - 1) // #ores + 1
	local hand = Config.Shafts[index]
	local info: ShaftInfo
	if hand then
		info = {
			Index = index,
			Name = hand.Name,
			Ore = hand.Ore,
			OreColor = hand.OreColor,
			RockColor = hand.RockColor,
			BaseCycle = hand.BaseCycle,
			BaseYield = BigNum.new(hand.BaseYield),
			UnlockCost = BigNum.new(hand.UnlockCost),
			Tier = 1,
		}
	else
		local last = Config.Shafts[#Config.Shafts]
		local steps = index - #Config.Shafts
		local h = (index * 0.061) % 1
		info = {
			Index = index,
			Name = ore.Name .. (if tier > 1 then " " .. roman(tier) else "") .. "-Ader",
			Ore = ore.Name .. (if tier > 1 then " " .. roman(tier) else ""),
			OreColor = ore.Color,
			RockColor = Color3.fromHSV(h, 0.32, 0.42),
			BaseCycle = math.min(gen.CycleMax, gen.CycleBase + gen.CyclePerLevel * index),
			BaseYield = BigNum.mul(BigNum.new(last.BaseYield), BigNum.powNum(gen.YieldGrowth, steps)),
			UnlockCost = BigNum.mul(BigNum.new(last.UnlockCost), BigNum.powNum(gen.UnlockGrowth, steps)),
			Tier = tier,
		}
	end
	shaftCache[index] = info
	return info
end

--- Abschnitt (Seite der Grube), in dem eine Ebene liegt
function Formulas.sectionOf(index: number): number
	return (index - 1) // Config.ShaftGen.SectionSize + 1
end

function Formulas.sectionCount(): number
	return math.ceil(Config.ShaftCount / Config.ShaftGen.SectionSize)
end

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
		if n and n >= 1 and n <= Config.ShaftCount then
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
		return string.format("Ebene %d: %s", index, Formulas.shaftDef(index).Name)
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

--- Aufzug und Händler wachsen mit der Tiefe der Mine mit (tiefere Erze sind
--- wertvoller -> mehr Wert pro Ladung). Exponent < 1, damit Upgrades wichtig bleiben.
local function depthFactor(data: PlayerData): BigNum
	local n = math.max(#data.Shafts, 1)
	local ratio = BigNum.div(Formulas.shaftDef(n).BaseYield, Formulas.shaftDef(1).BaseYield)
	return BigNum.pow(ratio, Config.Elevator.DepthExponent)
end
Formulas.depthFactor = depthFactor

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

-- Index StationKey -> Manager (wichtig bei hunderten Managern).
-- Wird neu gebaut, wenn sich die Manager-Liste ändert; nach Änderungen an
-- AssignedTo muss Formulas.invalidateManagers(data) aufgerufen werden.
type ManagerIndex = { List: { ManagerData }, Count: number, Map: { [string]: ManagerData } }
local managerIndex: { [any]: ManagerIndex } = setmetatable({}, { __mode = "k" }) :: any

function Formulas.invalidateManagers(data: PlayerData)
	managerIndex[data] = nil
end

function Formulas.managerFor(data: PlayerData, key: string): ManagerData?
	local idx = managerIndex[data]
	if idx and idx.List == data.Managers and idx.Count == #data.Managers then
		return idx.Map[key]
	end
	local map: { [string]: ManagerData } = {}
	for _, m in data.Managers do
		if m.AssignedTo then
			map[m.AssignedTo] = m
		end
	end
	managerIndex[data] = { List = data.Managers, Count = #data.Managers, Map = map }
	return map[key]
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

----------------------------------------------------------------------
-- Pets & Eier
----------------------------------------------------------------------
local petById: { [string]: Config.PetDef } = {}
for _, def in Config.Pets.List do
	petById[def.Id] = def
end
local petRarityById: { [string]: Config.PetRarityDef } = {}
local petRarityIndex: { [string]: number } = {}
for i, def in Config.Pets.Rarities do
	petRarityById[def.Id] = def
	petRarityIndex[def.Id] = i
end

function Formulas.petDef(petId: string): Config.PetDef?
	return petById[petId]
end

function Formulas.petRarity(rarityId: string): Config.PetRarityDef
	return petRarityById[rarityId] or Config.Pets.Rarities[1]
end

function Formulas.petRarityIndex(rarityId: string): number
	return petRarityIndex[rarityId] or 1
end

function Formulas.eggDef(eggId: string): Config.EggDef?
	for _, egg in Config.Eggs do
		if egg.Id == eggId then
			return egg
		end
	end
	return nil
end

--- Chance (in %) auf ein bestimmtes Pet, falls es aus irgendeinem Ei kommt
function Formulas.petChance(petId: string): number?
	for _, egg in Config.Eggs do
		for _, c in egg.Chances do
			if c.Pet == petId then
				return c.Chance
			end
		end
	end
	return nil
end

--- "1%", "0.5%", "0.012%"
function Formulas.formatChance(chance: number): string
	local text = string.format(if chance >= 10 then "%.1f" else "%.3f", chance)
	text = string.gsub(text, "0+$", "")
	text = string.gsub(text, "%.$", "")
	return text .. "%"
end

function Formulas.formatPetMultiplier(m: number): string
	if m >= 100 then
		return string.format("x%d", math.floor(m + 0.5))
	end
	local text = string.format("%.2f", m)
	text = string.gsub(text, "0+$", "")
	text = string.gsub(text, "%.$", "")
	return "x" .. text
end

--- Ausrüst-Slots (Basis + mit Geld + mit Robux gekaufte, mit Limit)
function Formulas.petSlots(data: PlayerData): number
	return math.min(Config.Pets.MaxSlots, Config.Pets.BaseSlots + data.PetSlotsBought + data.PetSlotsRobux)
end

--- Geld-Preis für den nächsten Slot (nil = alle Geld-Slots gekauft)
function Formulas.nextCashSlotCost(data: PlayerData): BigNum?
	local cost = Config.Pets.CashSlotCosts[data.PetSlotsBought + 1]
	if not cost or Formulas.petSlots(data) >= Config.Pets.MaxSlots then
		return nil
	end
	return BigNum.new(cost)
end

--- Kann noch ein Robux-Slot gekauft werden?
function Formulas.canBuyRobuxSlot(data: PlayerData): boolean
	return data.PetSlotsRobux < Config.Pets.RobuxSlots and Formulas.petSlots(data) < Config.Pets.MaxSlots
end

--- Einkommens-Multiplikator aller ausgerüsteten Pets (Boni addieren sich)
function Formulas.petMultiplier(data: PlayerData): number
	local bonus = 0
	local counted = 0
	local slots = Formulas.petSlots(data)
	for _, pet in data.Pets do
		if pet.Equipped and counted < slots then
			local def = petById[pet.Pet]
			if def then
				bonus += def.Multiplier - 1
				counted += 1
			end
		end
	end
	return 1 + bonus
end

function Formulas.equippedCount(data: PlayerData): number
	local n = 0
	for _, pet in data.Pets do
		if pet.Equipped then
			n += 1
		end
	end
	return n
end

--- Pets nach Stärke sortiert (stärkstes zuerst) - für "Beste ausrüsten"
function Formulas.sortPetsByPower(pets: { Types.PetData }): { Types.PetData }
	local sorted = table.clone(pets)
	table.sort(sorted, function(a, b)
		local da, db = petById[a.Pet], petById[b.Pet]
		local ma = if da then da.Multiplier else 0
		local mb = if db then db.Multiplier else 0
		if ma ~= mb then
			return ma > mb
		end
		return a.Id < b.Id
	end)
	return sorted
end

--- Preis eines Eis (Geld-Eier werden mit der tiefsten Ebene teurer)
function Formulas.eggCost(data: PlayerData, egg: Config.EggDef): BigNum
	local base = BigNum.new(egg.BaseCost)
	if egg.Currency ~= "Cash" or not egg.DepthFactor then
		return base
	end
	local depthCost = BigNum.mulNum(Formulas.shaftDef(#data.Shafts).UnlockCost, egg.DepthFactor)
	return BigNum.max(base, depthCost)
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
	mult *= Formulas.petMultiplier(data)
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
	local station = data.Shafts[index]
	if not station then
		return BigNum.zero()
	end
	local def = Formulas.shaftDef(index)
	local valueMult = linearMult(Formulas.trackDef("Shaft", "Value"), Formulas.level(station, "Value"))
	return BigNum.mulNum(def.BaseYield, valueMult)
end

function Formulas.shaftYield(data: PlayerData, index: number, ctx: CalcContext): BigNum
	local key = Formulas.shaftKey(index)
	local manager = Formulas.managerFor(data, key)
	return BigNum.mulNum(Formulas.shaftBaseYield(data, index), abilityMult(manager, "Value", ctx.Now))
end

function Formulas.shaftDuration(data: PlayerData, index: number, ctx: CalcContext, ignoreAbility: boolean?): number
	local station = data.Shafts[index]
	if not station then
		return math.huge
	end
	local def = Formulas.shaftDef(index)
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
function Formulas.elevatorBaseTrip(data: PlayerData): number
	local shafts = math.min(#data.Shafts, Config.Elevator.TripShaftCap)
	return Config.Elevator.BaseTrip + Config.Elevator.PerShaftTrip * shafts
end

function Formulas.elevatorDuration(data: PlayerData, ctx: CalcContext, ignoreAbility: boolean?): number
	local manager = Formulas.managerFor(data, "Elevator")
	local base = Formulas.elevatorBaseTrip(data)
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
	local load = BigNum.mul(
		loadFor(Formulas.trackDef("Elevator", "Capacity"), Formulas.level(data.Elevator, "Capacity")),
		depthFactor(data)
	)
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
	local load = BigNum.mul(
		loadFor(Formulas.trackDef("Warehouse", "Capacity"), Formulas.level(data.Warehouse, "Capacity")),
		depthFactor(data)
	)
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
local function trackBaseCost(area: string, index: number?, def: Config.TrackDef): BigNum
	if area == "Shaft" and index then
		return BigNum.mulNum(Formulas.shaftDef(index).BaseYield, def.CostFactor or 1)
	end
	return BigNum.new(def.BaseCost or 10)
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
local function costForLevels(base: BigNum, growth: number, level: number, n: number, discount: number): BigNum
	local first = BigNum.mul(base, BigNum.powNum(growth, level - 1))
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
			base = Formulas.shaftDef(index).BaseCycle
		elseif area == "Elevator" then
			base = Formulas.elevatorBaseTrip(data)
		else
			base = Config.Warehouse.BaseCycle
		end
		local duration = math.max(Config.MinCycleDuration, base / linearMult(def, level))
		return string.format("%.2fs / Zyklus", duration)
	elseif trackId == "Value" then
		if area == "Shaft" and index then
			local yield = BigNum.mulNum(Formulas.shaftDef(index).BaseYield, linearMult(def, level))
			return BigNum.formatMoney(yield, Config.CurrencySymbol) .. " / Zyklus"
		end
		return string.format("x%.2f Preis", linearMult(def, level))
	elseif trackId == "Capacity" then
		if area == "Shaft" then
			local cycles = (def.BaseCycles or 10) + (def.PerLevel or 0) * (level - 1)
			return string.format("%d Zyklen Lager", cycles)
		end
		return BigNum.format(BigNum.mul(loadFor(def, level), depthFactor(data))) .. " pro Fahrt"
	end
	return ""
end

----------------------------------------------------------------------
-- Schacht freischalten
----------------------------------------------------------------------
function Formulas.nextShaftCost(data: PlayerData): BigNum?
	local nextIndex = #data.Shafts + 1
	if nextIndex > Config.ShaftCount then
		return nil
	end
	return Formulas.shaftDef(nextIndex).UnlockCost
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
	return math.floor(cfg.PointsScale * (1 + BigNum.log10(ratio)) ^ cfg.PointsPower)
end

--- Wie viel muss in einem Durchlauf verdient werden, um diese Punktzahl zu bekommen?
function Formulas.rebirthCashFor(points: number): BigNum
	local cfg = Config.Rebirth
	local l = (math.max(points, 0) / cfg.PointsScale) ^ (1 / cfg.PointsPower) - 1
	return BigNum.mulNum(BigNum.fromLog10(math.max(l, 0)), cfg.MinRunCash)
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

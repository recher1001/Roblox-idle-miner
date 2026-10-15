--!strict
--[[
	DataTemplate
	============
	Erstellt neue Spielstände und bereinigt/migriert geladene Daten.
	Alles, was aus dem DataStore kommt, wird hier gegen das erwartete
	Format geprüft -> kaputte oder manipulierte Werte können das Spiel
	nicht crashen.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local BigNum = require(Shared.BigNum)
local Config = require(Shared.Config)
local Formulas = require(Shared.Formulas)
local Types = require(Shared.Types)

type PlayerData = Types.PlayerData
type StationData = Types.StationData
type ManagerData = Types.ManagerData

local DataTemplate = {}

DataTemplate.CurrentVersion = 1

local function newStation(area: string): StationData
	local levels = {}
	for _, def in Formulas.tracksFor(area) do
		levels[def.Id] = 1
	end
	return { Levels = levels, Stock = BigNum.zero() }
end

DataTemplate.newStation = newStation

function DataTemplate.new(): PlayerData
	return {
		Version = DataTemplate.CurrentVersion,
		Cash = BigNum.new(Config.StartingCash),
		RunCash = BigNum.zero(),
		TotalCash = BigNum.zero(),
		Gems = 0,
		RebirthPoints = 0,
		Rebirths = 0,
		Shafts = { newStation("Shaft") },
		Elevator = newStation("Elevator"),
		Warehouse = newStation("Warehouse"),
		Managers = {},
		ManagersHired = {},
		NextManagerId = 1,
		Boosts = {},
		LastOnline = 0,
		PlaytimeSeconds = 0,
		PlaytimeGemTimer = 0,
		DailyStreak = 0,
		LastDailyClaim = 0,
		LockCooldownUntil = 0,
		ReceiptIds = {},
		Powers = {},
		Stats = {
			StealsDone = 0,
			TimesRobbed = 0,
		},
	}
end

----------------------------------------------------------------------
-- Bereinigung
----------------------------------------------------------------------
local function num(v: any, default: number, minValue: number?, maxValue: number?): number
	if type(v) ~= "number" or v ~= v or v == math.huge or v == -math.huge then
		return default
	end
	if minValue and v < minValue then
		return minValue
	end
	if maxValue and v > maxValue then
		return maxValue
	end
	return v
end

local function positiveBig(v: any): BigNum.BigNum
	return BigNum.clampPositive(BigNum.from(v))
end

local function sanitizeStation(raw: any, area: string): StationData
	local station = newStation(area)
	if type(raw) ~= "table" then
		return station
	end
	if type(raw.Levels) == "table" then
		for _, def in Formulas.tracksFor(area) do
			station.Levels[def.Id] = math.floor(num(raw.Levels[def.Id], 1, 1, def.MaxLevel))
		end
	end
	station.Stock = positiveBig(raw.Stock)
	return station
end

local function validArea(area: any): boolean
	return area == "Shaft" or area == "Elevator" or area == "Warehouse"
end

local function validRarity(id: any): boolean
	for _, r in Config.Managers.Rarities do
		if r.Id == id then
			return true
		end
	end
	return false
end

local function validAbility(area: string, ability: any): boolean
	local list = Config.Managers.AbilitiesByArea[area]
	if not list then
		return false
	end
	return table.find(list, ability) ~= nil
end

local function sanitizeManagers(raw: any, data: PlayerData): { ManagerData }
	local result: { ManagerData } = {}
	if type(raw) ~= "table" then
		return result
	end
	local usedIds: { [string]: boolean } = {}
	local usedStations: { [string]: boolean } = {}
	for _, m in raw do
		if #result >= Config.Managers.MaxOwned then
			break
		end
		if
			type(m) == "table"
			and type(m.Id) == "string"
			and not usedIds[m.Id]
			and validArea(m.Area)
			and validRarity(m.Rarity)
			and validAbility(m.Area, m.Ability)
		then
			local assigned: string? = nil
			if type(m.AssignedTo) == "string" and not usedStations[m.AssignedTo] then
				local area = Formulas.parseKey(m.AssignedTo)
				if area == m.Area and Formulas.getStation(data, m.AssignedTo) ~= nil then
					assigned = m.AssignedTo
					usedStations[m.AssignedTo] = true
				end
			end
			usedIds[m.Id] = true
			table.insert(result, {
				Id = m.Id,
				Name = if type(m.Name) == "string" then string.sub(m.Name, 1, 24) else "Manager",
				FriendUserId = if type(m.FriendUserId) == "number" and m.FriendUserId > 0
					then math.floor(m.FriendUserId)
					else nil,
				Area = m.Area,
				Rarity = m.Rarity,
				Ability = m.Ability,
				AssignedTo = assigned,
				ActiveUntil = num(m.ActiveUntil, 0, 0),
				CooldownUntil = num(m.CooldownUntil, 0, 0),
			})
		end
	end
	return result
end

--- Nimmt beliebige Rohdaten und liefert garantiert gültige PlayerData
function DataTemplate.sanitize(raw: any): PlayerData
	local data = DataTemplate.new()
	if type(raw) ~= "table" then
		return data
	end

	-- Migrationen (Version für Version) kämen hier hin:
	-- if raw.Version == 1 then ... raw.Version = 2 end

	data.Cash = positiveBig(raw.Cash)
	data.RunCash = positiveBig(raw.RunCash)
	data.TotalCash = positiveBig(raw.TotalCash)
	data.Gems = math.floor(num(raw.Gems, 0, 0))
	data.RebirthPoints = math.floor(num(raw.RebirthPoints, 0, 0))
	data.Rebirths = math.floor(num(raw.Rebirths, 0, 0))

	if type(raw.Shafts) == "table" and #raw.Shafts >= 1 then
		data.Shafts = {}
		for i = 1, math.min(#raw.Shafts, Formulas.shaftCount()) do
			data.Shafts[i] = sanitizeStation(raw.Shafts[i], "Shaft")
		end
	end
	data.Elevator = sanitizeStation(raw.Elevator, "Elevator")
	data.Warehouse = sanitizeStation(raw.Warehouse, "Warehouse")

	data.Managers = sanitizeManagers(raw.Managers, data)
	if type(raw.ManagersHired) == "table" then
		for _, area in { "Shaft", "Elevator", "Warehouse" } do
			data.ManagersHired[area] = math.floor(num(raw.ManagersHired[area], 0, 0))
		end
	end
	data.NextManagerId = math.floor(num(raw.NextManagerId, 1, 1))

	if type(raw.Boosts) == "table" then
		for id, untilTime in raw.Boosts do
			if type(id) == "string" and type(untilTime) == "number" then
				data.Boosts[id] = untilTime
			end
		end
	end

	data.LastOnline = num(raw.LastOnline, 0, 0)
	data.PlaytimeSeconds = num(raw.PlaytimeSeconds, 0, 0)
	data.PlaytimeGemTimer = num(raw.PlaytimeGemTimer, 0, 0)
	data.DailyStreak = math.floor(num(raw.DailyStreak, 0, 0))
	data.LastDailyClaim = num(raw.LastDailyClaim, 0, 0)
	data.LockCooldownUntil = num(raw.LockCooldownUntil, 0, 0)

	if type(raw.ReceiptIds) == "table" then
		for _, id in raw.ReceiptIds do
			if type(id) == "string" then
				table.insert(data.ReceiptIds, id)
			end
		end
		while #data.ReceiptIds > Config.Data.MaxReceiptHistory do
			table.remove(data.ReceiptIds, 1)
		end
	end

	if type(raw.Powers) == "table" then
		for _, def in Config.Admin.Powers do
			if raw.Powers[def.Id] == true then
				data.Powers[def.Id] = true
			end
		end
	end

	if type(raw.Stats) == "table" then
		data.Stats.StealsDone = math.floor(num(raw.Stats.StealsDone, 0, 0))
		data.Stats.TimesRobbed = math.floor(num(raw.Stats.TimesRobbed, 0, 0))
	end

	data.Version = DataTemplate.CurrentVersion
	return data
end

--- Tiefe Kopie für das Speichern (DataStore-sicher, keine Referenzen)
function DataTemplate.serialize(data: PlayerData): any
	local function copy(v: any): any
		if type(v) == "table" then
			local t = {}
			for k, val in v do
				t[k] = copy(val)
			end
			return t
		end
		return v
	end
	return copy(data)
end

return DataTemplate

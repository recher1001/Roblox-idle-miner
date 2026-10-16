--!strict
--[[
	ManagerService
	==============
	Manager einstellen (zufällige Seltenheit + Fähigkeit), zuweisen,
	abziehen, entlassen und Fähigkeiten aktivieren.

	  * Ein Manager automatisiert seine Station (MineService startet Zyklen selbst)
	  * Passiver Tempo-Bonus je nach Seltenheit
	  * Aktive Fähigkeit (Turbo, Goldader, Schwerlast, Sparfuchs) mit Dauer
	    und Abklingzeit - boostet alle Arbeiter der Station
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Clock = require(Shared.Clock)
local Config = require(Shared.Config)
local Formulas = require(Shared.Formulas)
local Net = require(Shared.Net)
local Types = require(Shared.Types)

local AvatarService = require(script.Parent.AvatarService)
local NetService = require(script.Parent.NetService)
local PlotService = require(script.Parent.PlotService)
local SessionService = require(script.Parent.SessionService)

type Session = SessionService.Session
type ManagerData = Types.ManagerData

local ManagerService = {}

local rng = Random.new()

local AREAS = { Shaft = true, Elevator = true, Warehouse = true }

local function rollRarity(lucky: boolean): Config.RarityDef
	local rarities = Config.Managers.Rarities
	local total = 0
	local weights: { number } = {}
	for i, r in rarities do
		local w = r.Weight
		if lucky and i > 1 then
			w *= Config.Managers.LuckyMultiplier
		end
		weights[i] = w
		total += w
	end
	local roll = rng:NextNumber(0, total)
	for i, r in rarities do
		roll -= weights[i]
		if roll <= 0 then
			return r
		end
	end
	return rarities[1]
end

--- Erste Station des Bereichs ohne Manager (Schächte von oben nach unten)
function ManagerService.firstFreeStation(data: Types.PlayerData, area: string): string?
	if area == "Shaft" then
		for i = 1, #data.Shafts do
			local key = Formulas.shaftKey(i)
			if not Formulas.managerFor(data, key) then
				return key
			end
		end
		return nil
	end
	return if Formulas.managerFor(data, area) then nil else area
end

function ManagerService.hire(session: Session, area: string): (boolean, string?, any?)
	if not AREAS[area] then
		return false, "Ungültiger Bereich"
	end
	local data = session.Data
	if #data.Managers >= Config.Managers.MaxOwned then
		return false, string.format("Maximal %d Manager! Entlasse einen.", Config.Managers.MaxOwned)
	end
	local cost = Formulas.managerHireCost(data, area)
	if not SessionService.spendCash(session, cost) then
		return false, "Nicht genug Geld"
	end
	local rarity = rollRarity(session.Passes.LuckyManagers == true)
	local abilities = Config.Managers.AbilitiesByArea[area]
	local names = Config.Managers.Names
	-- Manager bekommen den Avatar + Namen eines Freundes des Spielers
	local friend = if Config.Avatars.Enabled then AvatarService.pickFriend(session) else nil
	local manager: ManagerData = {
		Id = "M" .. tostring(data.NextManagerId),
		Name = if friend then string.sub(friend.Name, 1, 24) else names[rng:NextInteger(1, #names)],
		FriendUserId = if friend then friend.UserId else nil,
		Area = area,
		Rarity = rarity.Id,
		Ability = abilities[rng:NextInteger(1, #abilities)],
		AssignedTo = ManagerService.firstFreeStation(data, area),
		ActiveUntil = 0,
		CooldownUntil = 0,
	}
	data.NextManagerId += 1
	data.ManagersHired[area] = (data.ManagersHired[area] or 0) + 1
	table.insert(data.Managers, manager)
	SessionService.managersChanged(session)
	PlotService.updateVisuals(session)
	Net.event("ManagerReveal"):FireClient(session.Player, manager)
	return true, nil, manager
end

function ManagerService.assign(session: Session, managerId: string, key: string): (boolean, string?)
	local data = session.Data
	local manager = Formulas.findManager(data, managerId)
	if not manager then
		return false, "Manager nicht gefunden"
	end
	local area = Formulas.parseKey(key)
	if area ~= manager.Area or not Formulas.getStation(data, key) then
		return false, "Dieser Manager passt nicht zu dieser Station"
	end
	local current = Formulas.managerFor(data, key)
	if current and current ~= manager then
		current.AssignedTo = nil -- Tausch: alter Manager geht in die Reserve
	end
	manager.AssignedTo = key
	SessionService.managersChanged(session)
	PlotService.updateVisuals(session)
	return true, nil
end

function ManagerService.unassign(session: Session, managerId: string): (boolean, string?)
	local manager = Formulas.findManager(session.Data, managerId)
	if not manager then
		return false, "Manager nicht gefunden"
	end
	manager.AssignedTo = nil
	SessionService.managersChanged(session)
	PlotService.updateVisuals(session)
	return true, nil
end

function ManagerService.fire(session: Session, managerId: string): (boolean, string?)
	local data = session.Data
	for i, m in data.Managers do
		if m.Id == managerId then
			table.remove(data.Managers, i)
			SessionService.managersChanged(session)
			PlotService.updateVisuals(session)
			return true, nil
		end
	end
	return false, "Manager nicht gefunden"
end

local function activate(session: Session, manager: ManagerData, now: number): boolean
	if not manager.AssignedTo or manager.CooldownUntil > now then
		return false
	end
	local rarity = Formulas.rarityDef(manager.Rarity)
	manager.ActiveUntil = now + rarity.AbilityDuration
	manager.CooldownUntil = manager.ActiveUntil + rarity.AbilityCooldown
	SessionService.effect(session.Player, "Ability", { Key = manager.AssignedTo, Ability = manager.Ability })
	return true
end

function ManagerService.activateAbility(session: Session, managerId: string): (boolean, string?)
	local manager = Formulas.findManager(session.Data, managerId)
	if not manager then
		return false, "Manager nicht gefunden"
	end
	if not manager.AssignedTo then
		return false, "Manager muss einer Station zugewiesen sein"
	end
	local now = Clock.now()
	if manager.CooldownUntil > now then
		return false, "Fähigkeit lädt noch: " .. Formulas.formatDuration(manager.CooldownUntil - now)
	end
	activate(session, manager, now)
	SessionService.managersChanged(session)
	PlotService.updateVisuals(session)
	return true, nil
end

--- "Alle boosten": aktiviert alle bereiten Fähigkeiten
function ManagerService.activateAll(session: Session): (boolean, string?, any?)
	local now = Clock.now()
	local count = 0
	for _, manager in session.Data.Managers do
		if activate(session, manager, now) then
			count += 1
		end
	end
	if count == 0 then
		return false, "Keine Fähigkeit bereit"
	end
	SessionService.managersChanged(session)
	PlotService.updateVisuals(session)
	return true, string.format("%d Fähigkeiten aktiviert!", count), count
end

function ManagerService.start()
	NetService.register("HireManager", { Area = "string" }, function(session, payload)
		return ManagerService.hire(session, payload.Area)
	end)
	NetService.register("AssignManager", { ManagerId = "string", Key = "string" }, function(session, payload)
		return ManagerService.assign(session, payload.ManagerId, payload.Key)
	end)
	NetService.register("UnassignManager", { ManagerId = "string" }, function(session, payload)
		return ManagerService.unassign(session, payload.ManagerId)
	end)
	NetService.register("FireManager", { ManagerId = "string" }, function(session, payload)
		return ManagerService.fire(session, payload.ManagerId)
	end)
	NetService.register("ActivateAbility", { ManagerId = "string" }, function(session, payload)
		return ManagerService.activateAbility(session, payload.ManagerId)
	end)
	NetService.register("ActivateAll", {}, function(session)
		return ManagerService.activateAll(session)
	end)
end

return ManagerService

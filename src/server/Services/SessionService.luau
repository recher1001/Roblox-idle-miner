--!strict
--[[
	SessionService
	==============
	Verwaltet eine "Session" pro Spieler (gespeicherte Daten + Laufzeitzustand).
	Andere Services hängen sich über onStart/onEnd-Hooks ein (mit Priorität,
	damit z. B. der Plot vor der Mine existiert).

	Sendet geänderte Zustände gedrosselt an den Client (Sync) und pflegt
	die leaderstats (Bestenliste im Spielermenü).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local BigNum = require(Shared.BigNum)
local Clock = require(Shared.Clock)
local Config = require(Shared.Config)
local Formulas = require(Shared.Formulas)
local Maid = require(Shared.Maid)
local Net = require(Shared.Net)
local Types = require(Shared.Types)

local DataService = require(script.Parent.DataService)
local RateLimiter = require(script.Parent.Parent.Modules.RateLimiter)

type PlayerData = Types.PlayerData
type CycleState = Types.CycleState
type CalcContext = Types.CalcContext

export type Session = {
	Player: Player,
	Profile: DataService.Profile,
	Data: PlayerData,
	Cycles: { [string]: CycleState },
	Pending: { [string]: BigNum.BigNum }, -- Menge, die der laufende Zyklus bewegt
	Maid: Maid.Maid,
	JoinTime: number,
	Passes: { [string]: boolean },
	PlotIndex: number,
	Dirty: boolean,
	LockedUntil: number,
	LastStealAt: number,
	LastRobbedAt: number,
	Ending: boolean,
	Admin: Types.AdminInfo?, -- gesetzt vom AdminService
	ViewSection: number, -- angezeigter Abschnitt der Grube (0 = automatisch der tiefste)
	-- Versionen für sparsamen Sync (große Listen nur bei Änderung senden)
	ShaftsVersion: number,
	ManagersVersion: number,
	SentShaftsVersion: number,
	SentManagersVersion: number,
}

type Hook = { Priority: number, Fn: (Session) -> () }

local SessionService = {}

local sessions: { [Player]: Session } = {}
local startHooks: { Hook } = {}
local endHooks: { Hook } = {}

-- Globales Server-Event (gesetzt vom EventService)
local currentEvent: { Id: string, EndsAt: number, Cash: number, Speed: number }? = nil

----------------------------------------------------------------------
-- Hooks
----------------------------------------------------------------------
local function addHook(list: { Hook }, priority: number, fn: (Session) -> ())
	table.insert(list, { Priority = priority, Fn = fn })
	table.sort(list, function(a, b)
		return a.Priority < b.Priority
	end)
end

--- fn wird beim Session-Start aufgerufen (niedrige Priorität zuerst)
function SessionService.onStart(priority: number, fn: (Session) -> ())
	addHook(startHooks, priority, fn)
end

--- fn wird beim Verlassen aufgerufen, BEVOR gespeichert wird
function SessionService.onEnd(priority: number, fn: (Session) -> ())
	addHook(endHooks, priority, fn)
end

----------------------------------------------------------------------
-- Zugriff
----------------------------------------------------------------------
function SessionService.get(player: Player): Session?
	local s = sessions[player]
	if s and not s.Ending then
		return s
	end
	return nil
end

function SessionService.all(): { Session }
	local list = {}
	for _, s in sessions do
		if not s.Ending then
			table.insert(list, s)
		end
	end
	return list
end

function SessionService.markDirty(session: Session)
	session.Dirty = true
end

function SessionService.setEvent(event: { Id: string, EndsAt: number, Cash: number, Speed: number }?)
	currentEvent = event
	for _, s in sessions do
		s.Dirty = true
	end
end

function SessionService.getEvent(): { Id: string, EndsAt: number, Cash: number, Speed: number }?
	if currentEvent and currentEvent.EndsAt > Clock.now() then
		return currentEvent
	end
	return nil
end

--- Berechnungskontext (Zeit, Gamepasses, Event-Multiplikatoren)
function SessionService.context(session: Session): CalcContext
	local event = SessionService.getEvent()
	return {
		Now = Clock.now(),
		Passes = session.Passes,
		EventCashMultiplier = if event then event.Cash else 1,
		EventSpeedMultiplier = if event then event.Speed else 1,
	}
end

--- Geld gutschreiben (zählt auch für Rebirth- und Gesamt-Statistik)
function SessionService.addCash(session: Session, amount: BigNum.BigNum)
	if BigNum.isNegative(amount) or BigNum.isZero(amount) then
		return
	end
	local data = session.Data
	data.Cash = BigNum.add(data.Cash, amount)
	data.RunCash = BigNum.add(data.RunCash, amount)
	data.TotalCash = BigNum.add(data.TotalCash, amount)
	session.Dirty = true
end

--- Geld abziehen. false wenn nicht genug vorhanden.
function SessionService.spendCash(session: Session, amount: BigNum.BigNum): boolean
	local data = session.Data
	if BigNum.isNegative(amount) or BigNum.lt(data.Cash, amount) then
		return false
	end
	data.Cash = BigNum.clampPositive(BigNum.sub(data.Cash, amount))
	session.Dirty = true
	return true
end

function SessionService.spendGems(session: Session, amount: number): boolean
	if amount < 0 or session.Data.Gems < amount then
		return false
	end
	session.Data.Gems -= amount
	session.Dirty = true
	return true
end

function SessionService.addGems(session: Session, amount: number)
	if amount <= 0 then
		return
	end
	session.Data.Gems += math.floor(amount)
	session.Dirty = true
end

----------------------------------------------------------------------
-- Client-Kommunikation
----------------------------------------------------------------------
function SessionService.notify(player: Player, text: string, kind: string?)
	Net.event("Notify"):FireClient(player, text, kind or "info")
end

function SessionService.effect(player: Player, kind: string, payload: { [string]: any })
	Net.event("Effect"):FireClient(player, kind, payload)
end

--- Ebenen haben sich geändert (Level, Freischaltung, Rebirth ...)
function SessionService.shaftsChanged(session: Session)
	session.ShaftsVersion += 1
	session.Dirty = true
end

--- Manager haben sich geändert (eingestellt, zugewiesen, Fähigkeit ...)
function SessionService.managersChanged(session: Session)
	Formulas.invalidateManagers(session.Data)
	session.ManagersVersion += 1
	session.Dirty = true
end

--- Angezeigter Abschnitt der Grube (Seite mit SectionSize Ebenen)
function SessionService.currentSection(session: Session): number
	local count = #session.Data.Shafts
	local maxSection = Formulas.sectionOf(math.max(count, 1))
	if session.ViewSection >= 1 then
		return math.clamp(session.ViewSection, 1, maxSection)
	end
	return maxSection
end

local function buildSnapshot(session: Session): Types.Snapshot
	local event = SessionService.getEvent()
	local now = Clock.now()
	local data = session.Data
	-- Flache Kopie: Ebenen- und Manager-Listen (bis zu 500/600 Einträge) nur
	-- senden, wenn sie sich geändert haben. Der Client behält sonst die alten.
	local wire = table.clone(data) :: any
	if session.SentShaftsVersion == session.ShaftsVersion then
		wire.Shafts = nil
	else
		local light = table.create(#data.Shafts)
		for i, shaft in data.Shafts do
			light[i] = { Levels = shaft.Levels }
		end
		wire.Shafts = light
		session.SentShaftsVersion = session.ShaftsVersion
	end
	if session.SentManagersVersion == session.ManagersVersion then
		wire.Managers = nil
	else
		session.SentManagersVersion = session.ManagersVersion
	end
	local stockAny = false
	for _, shaft in data.Shafts do
		if not BigNum.isZero(shaft.Stock) then
			stockAny = true
			break
		end
	end
	return {
		Data = wire,
		Passes = session.Passes,
		ProtectedUntil = session.JoinTime + Config.Steal.NewPlayerProtection,
		LockedUntil = session.LockedUntil,
		Event = if event then { Id = event.Id, EndsAt = event.EndsAt } else nil,
		PlotIndex = session.PlotIndex,
		DailyAvailable = Formulas.dailyAvailable(session.Data, now),
		Admin = session.Admin,
		Section = SessionService.currentSection(session),
		ShaftStockAny = stockAny,
	}
end

--- Nach einem Neuladen des Clients alles neu senden
function SessionService.resendAll(session: Session)
	session.SentShaftsVersion = 0
	session.SentManagersVersion = 0
	session.Dirty = true
end

function SessionService.syncNow(session: Session)
	session.Dirty = false
	Net.event("Sync"):FireClient(session.Player, buildSnapshot(session))
	SessionService.updateLeaderstats(session)
end

----------------------------------------------------------------------
-- leaderstats
----------------------------------------------------------------------
local function setupLeaderstats(session: Session)
	local folder = Instance.new("Folder")
	folder.Name = "leaderstats"
	local cash = Instance.new("StringValue")
	cash.Name = "Geld"
	cash.Parent = folder
	local rebirths = Instance.new("IntValue")
	rebirths.Name = "Rebirths"
	rebirths.Parent = folder
	folder.Parent = session.Player
end

function SessionService.updateLeaderstats(session: Session)
	local folder = session.Player:FindFirstChild("leaderstats")
	if not folder then
		return
	end
	local cash = folder:FindFirstChild("Geld")
	if cash and cash:IsA("StringValue") then
		cash.Value = BigNum.formatMoney(session.Data.Cash, Config.CurrencySymbol)
	end
	local rebirths = folder:FindFirstChild("Rebirths")
	if rebirths and rebirths:IsA("IntValue") then
		rebirths.Value = session.Data.Rebirths
	end
end

----------------------------------------------------------------------
-- Lebenszyklus
----------------------------------------------------------------------
local function onPlayerAdded(player: Player)
	local profile = DataService.load(player)
	if not profile or not player:IsDescendantOf(Players) then
		return
	end
	local session: Session = {
		Player = player,
		Profile = profile,
		Data = profile.Data,
		Cycles = {},
		Pending = {},
		Maid = Maid.new(),
		JoinTime = Clock.now(),
		Passes = {},
		PlotIndex = 0,
		Dirty = true,
		LockedUntil = 0,
		LastStealAt = 0,
		LastRobbedAt = 0,
		Ending = false,
		Admin = nil,
		ViewSection = 0,
		ShaftsVersion = 1,
		ManagersVersion = 1,
		SentShaftsVersion = 0,
		SentManagersVersion = 0,
	}
	sessions[player] = session
	setupLeaderstats(session)

	for _, hook in startHooks do
		local ok, err = pcall(function()
			hook.Fn(session)
		end)
		if not ok then
			warn("[SessionService] Start-Hook Fehler:", err)
		end
	end
	SessionService.syncNow(session)
end

local function onPlayerRemoving(player: Player)
	local session = sessions[player]
	RateLimiter.clear(player)
	if not session then
		-- Profil evtl. geladen, aber Session nie gestartet
		DataService.release(player)
		return
	end
	session.Ending = true
	for _, hook in endHooks do
		local ok, err = pcall(function()
			hook.Fn(session)
		end)
		if not ok then
			warn("[SessionService] End-Hook Fehler:", err)
		end
	end
	session.Maid:Clean()
	DataService.release(player)
	sessions[player] = nil
end

function SessionService.start()
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end

	-- Gedrosselter Sync an die Clients
	task.spawn(function()
		while true do
			task.wait(Config.World.SyncInterval)
			for _, session in sessions do
				if session.Dirty and not session.Ending then
					local ok, err = pcall(function()
						SessionService.syncNow(session)
					end)
					if not ok then
						warn("[SessionService] Sync-Fehler:", err)
					end
				end
			end
		end
	end)
end

return SessionService

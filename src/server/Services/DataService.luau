--!strict
--[[
	DataService
	===========
	Laden/Speichern der Spielstände mit Schutz vor Datenverlust:

	  * Session-Locking: Beim Laden wird ein Lock {JobId, Time} in den Datensatz
	    geschrieben. Ein anderer Server darf die Daten nicht überschreiben, solange
	    der Lock frisch ist. Jeder Save prüft, dass der Lock noch uns gehört.
	  * Retry mit exponentiellem Backoff + Beachtung des Request-Budgets.
	  * Autosave alle Config.Data.AutosaveInterval Sekunden (gestaffelt).
	  * Speichern beim Verlassen und bei BindToClose (Server-Shutdown).
	  * Schlägt das Laden fehl, wird NIE gespeichert (sonst würde ein leerer
	    Spielstand den echten überschreiben). Der Spieler wird gekickt.
	  * Studio ohne API-Zugriff: Spiel läuft mit temporären Daten weiter.
]]

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Types = require(Shared.Types)

local DataTemplate = require(script.Parent.Parent.Modules.DataTemplate)

type PlayerData = Types.PlayerData

export type Profile = {
	Player: Player,
	Key: string,
	Data: PlayerData,
	Persistent: boolean, -- false = wird nicht gespeichert (Studio-Fallback)
	Released: boolean,
	Saving: boolean,
	LastSaved: number,
}

local DataService = {}

local profiles: { [Player]: Profile } = {}
local store: DataStore? = nil
local mockMode = false
local shuttingDown = false

local CFG = Config.Data

----------------------------------------------------------------------
-- Hilfsfunktionen
----------------------------------------------------------------------
local function log(...: any)
	print("[DataService]", ...)
end

local function isStudioApiError(err: string): boolean
	return string.find(err, "StudioAccessToApisNotAllowed", 1, true) ~= nil
		or string.find(err, "publish", 1, true) ~= nil
		or string.find(err, "403", 1, true) ~= nil
end

local function waitForBudget(requestType: Enum.DataStoreRequestType)
	local waited = 0
	while DataStoreService:GetRequestBudgetForRequestType(requestType) < 1 and waited < 10 do
		task.wait(0.5)
		waited += 0.5
	end
end

--- Führt fn mit Retries aus. Gibt (ok, ergebnis/fehler) zurück.
local function withRetries(label: string, fn: () -> any): (boolean, any)
	local lastErr: any = nil
	for attempt = 1, CFG.MaxRetries do
		waitForBudget(Enum.DataStoreRequestType.UpdateAsync)
		local ok, result = pcall(fn)
		if ok then
			return true, result
		end
		lastErr = result
		warn(
			string.format(
				"[DataService] %s fehlgeschlagen (Versuch %d/%d): %s",
				label,
				attempt,
				CFG.MaxRetries,
				tostring(result)
			)
		)
		if RunService:IsStudio() and isStudioApiError(tostring(result)) then
			break -- in Studio ohne API-Zugriff nicht unnötig warten
		end
		if attempt < CFG.MaxRetries then
			task.wait(CFG.RetryBaseDelay * 2 ^ (attempt - 1))
		end
	end
	return false, lastErr
end

local function enableMockMode(reason: string)
	if not mockMode then
		mockMode = true
		warn("[DataService] Temporärer Modus (keine Speicherung): " .. reason)
		warn("[DataService] Tipp: Game Settings > Security > 'Enable Studio Access to API Services' aktivieren.")
	end
end

----------------------------------------------------------------------
-- Laden
----------------------------------------------------------------------
type LoadResult = "ok" | "locked" | "error"

local function tryLoad(key: string, forceSteal: boolean): (LoadResult, any)
	local activeStore = store
	if not activeStore then
		return "error", "kein DataStore"
	end
	local lockedByOther = false
	local loadedRaw: any = nil
	local ok, err = withRetries("Laden " .. key, function()
		activeStore:UpdateAsync(key, function(old: any)
			lockedByOther = false
			local record = if type(old) == "table" then old else {}
			local lock = record.Lock
			local now = os.time()
			if
				not forceSteal
				and type(lock) == "table"
				and lock.JobId ~= game.JobId
				and type(lock.Time) == "number"
				and now - lock.Time < CFG.SessionLockTimeout
			then
				lockedByOther = true
				return nil -- nichts schreiben
			end
			loadedRaw = record.Data
			record.Lock = { JobId = game.JobId, Time = now }
			return record
		end)
		return true
	end)
	if not ok then
		return "error", err
	end
	if lockedByOther then
		return "locked", nil
	end
	return "ok", loadedRaw
end

--- Lädt die Daten eines Spielers. Gibt das Profil zurück oder nil (Spieler wurde gekickt).
function DataService.load(player: Player): Profile?
	local key = CFG.KeyPrefix .. tostring(player.UserId)

	local function makeProfile(raw: any, persistent: boolean): Profile
		local profile: Profile = {
			Player = player,
			Key = key,
			Data = DataTemplate.sanitize(raw),
			Persistent = persistent,
			Released = false,
			Saving = false,
			LastSaved = os.clock(),
		}
		profiles[player] = profile
		return profile
	end

	if mockMode or not store then
		return makeProfile(nil, false)
	end

	for attempt = 1, CFG.LockWaitAttempts do
		-- Beim letzten Versuch wird ein fremder Lock übernommen. Der alte Server
		-- kann danach nicht mehr speichern (sein Lock-Check schlägt fehl).
		local forceSteal = attempt == CFG.LockWaitAttempts
		local result, value = tryLoad(key, forceSteal)
		if not player:IsDescendantOf(Players) then
			-- Spieler ist während des Ladens gegangen: Lock sofort wieder freigeben
			if result == "ok" then
				local profile = makeProfile(value, true)
				DataService.save(profile, true)
				profiles[player] = nil
			end
			return nil
		end
		if result == "ok" then
			log("Geladen:", player.Name, if forceSteal then "(Lock übernommen)" else "")
			return makeProfile(value, true)
		elseif result == "locked" then
			log(string.format("%s ist noch auf einem anderen Server gesperrt, warte... (%d)", player.Name, attempt))
			task.wait(CFG.LockWaitDelay)
		else
			if RunService:IsStudio() then
				enableMockMode(tostring(value))
				return makeProfile(nil, false)
			end
			player:Kick(
				"Deine Daten konnten nicht geladen werden. Bitte tritt erneut bei. (Dein Fortschritt ist sicher.)"
			)
			return nil
		end
	end
	player:Kick("Deine Daten werden noch auf einem anderen Server verwendet. Bitte versuche es gleich erneut.")
	return nil
end

----------------------------------------------------------------------
-- Speichern
----------------------------------------------------------------------
function DataService.save(profile: Profile, release: boolean): boolean
	if not profile.Persistent then
		if release then
			profile.Released = true
		end
		return true
	end
	if profile.Released then
		return true
	end
	-- Nur ein Save gleichzeitig pro Profil
	while profile.Saving do
		task.wait(0.1)
	end
	if profile.Released then
		return true
	end
	profile.Saving = true

	local activeStore = store :: DataStore
	profile.Data.LastOnline = os.time()
	local payload = DataTemplate.serialize(profile.Data)
	local lostLock = false

	local ok, err = withRetries("Speichern " .. profile.Key, function()
		activeStore:UpdateAsync(profile.Key, function(old: any)
			lostLock = false
			local record = if type(old) == "table" then old else {}
			local lock = record.Lock
			if type(lock) == "table" and lock.JobId ~= game.JobId then
				lostLock = true
				return nil -- ein anderer Server besitzt die Daten -> nicht überschreiben
			end
			record.Data = payload
			record.SavedAt = os.time()
			record.Lock = if release then nil else { JobId = game.JobId, Time = os.time() }
			return record
		end)
		return true
	end)

	profile.Saving = false
	profile.LastSaved = os.clock()

	if not ok then
		warn("[DataService] Speichern endgültig fehlgeschlagen für", profile.Key, err)
		return false
	end
	if lostLock then
		warn("[DataService] Lock verloren für", profile.Key, "- Daten werden von einem anderen Server verwendet.")
		profile.Released = true
		profile.Persistent = false
		if profile.Player:IsDescendantOf(Players) then
			profile.Player:Kick("Dein Spielstand wurde auf einem anderen Server geöffnet.")
		end
		return false
	end
	if release then
		profile.Released = true
	end
	return true
end

function DataService.getProfile(player: Player): Profile?
	return profiles[player]
end

function DataService.getData(player: Player): PlayerData?
	local p = profiles[player]
	return if p then p.Data else nil
end

--- Speichert und entfernt das Profil (beim Verlassen)
function DataService.release(player: Player)
	local profile = profiles[player]
	if not profile then
		return
	end
	DataService.save(profile, true)
	profiles[player] = nil
end

function DataService.isMock(): boolean
	return mockMode
end

function DataService.isShuttingDown(): boolean
	return shuttingDown
end

----------------------------------------------------------------------
-- Start
----------------------------------------------------------------------
function DataService.start()
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(CFG.StoreName)
	end)
	if ok then
		store = result
	else
		enableMockMode(tostring(result))
	end

	-- Autosave: gestaffelt über das Intervall verteilt
	task.spawn(function()
		while not shuttingDown do
			local list: { Profile } = {}
			for _, profile in profiles do
				table.insert(list, profile)
			end
			if #list == 0 then
				task.wait(CFG.AutosaveInterval)
			else
				local gap = CFG.AutosaveInterval / #list
				for _, profile in list do
					if shuttingDown then
						break
					end
					if not profile.Released and profiles[profile.Player] == profile then
						task.spawn(DataService.save, profile, false)
					end
					task.wait(gap)
				end
			end
		end
	end)

	game:BindToClose(function()
		shuttingDown = true
		local pending = 0
		for player, profile in profiles do
			pending += 1
			task.spawn(function()
				DataService.save(profile, true)
				profiles[player] = nil
				pending -= 1
			end)
		end
		local started = os.clock()
		while pending > 0 and os.clock() - started < 25 do
			task.wait(0.1)
		end
		if pending > 0 then
			warn("[DataService] BindToClose: nicht alle Saves wurden rechtzeitig fertig:", pending)
		end
	end)
end

return DataService

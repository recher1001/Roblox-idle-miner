--!strict
--[[
	Types
	=====
	Gemeinsame Datentypen für Server und Client.
]]

local BigNum = require(script.Parent.BigNum)

export type BigNum = BigNum.BigNum

-- "Shaft" | "Elevator" | "Warehouse"
export type Area = string

export type StationData = {
	Levels: { [string]: number }, -- TrackId -> Level
	Stock: BigNum, -- Schacht: Schachtlager, Aufzug: Aufzugslager (stehlbar!), Lager: ungenutzt
}

export type ManagerData = {
	Id: string,
	Name: string,
	Area: Area,
	Rarity: string,
	Ability: string,
	FriendUserId: number?, -- Avatar eines Freundes (nil = Standardfigur)
	AssignedTo: string?, -- StationKey ("Shaft:2", "Elevator", "Warehouse") oder nil
	ActiveUntil: number, -- Server-Zeit (Epoch-Sekunden)
	CooldownUntil: number,
}

export type PlayerData = {
	Version: number,
	Cash: BigNum,
	RunCash: BigNum, -- seit dem letzten Rebirth verdient
	TotalCash: BigNum, -- insgesamt verdient
	Gems: number,
	RebirthPoints: number,
	Rebirths: number,
	Shafts: { StationData },
	Elevator: StationData,
	Warehouse: StationData,
	Managers: { ManagerData },
	ManagersHired: { [string]: number },
	NextManagerId: number,
	Boosts: { [string]: number }, -- BoostId -> läuft ab um (Epoch)
	LastOnline: number,
	PlaytimeSeconds: number,
	PlaytimeGemTimer: number,
	DailyStreak: number,
	LastDailyClaim: number,
	LockCooldownUntil: number,
	ReceiptIds: { string },
	Stats: {
		StealsDone: number,
		TimesRobbed: number,
	},
}

-- Laufzeitzustand eines Arbeitszyklus (nicht gespeichert)
export type CycleState = {
	Running: boolean,
	Start: number,
	End: number,
	Id: number,
}

-- Was der Client vom Server bekommt
export type Snapshot = {
	Data: PlayerData,
	Cycles: { [string]: CycleState },
	Passes: { [string]: boolean },
	ProtectedUntil: number,
	LockedUntil: number,
	Event: { Id: string, EndsAt: number }?,
	PlotIndex: number,
	DailyAvailable: boolean,
}

-- Kontext für Berechnungen (Boosts, Gamepasses, Events)
export type CalcContext = {
	Now: number,
	Passes: { [string]: boolean },
	EventCashMultiplier: number,
	EventSpeedMultiplier: number,
}

return {}

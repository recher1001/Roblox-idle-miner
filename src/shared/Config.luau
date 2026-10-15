--!strict
--[[
	Config
	======
	Zentrale Balancing-Datei. ALLE Spielwerte (Kosten, Raten, Multiplikatoren, Zeiten)
	stehen hier, damit das Spiel ohne Code-Änderungen balanciert werden kann.

	Einheiten:
	  - Zeiten in Sekunden
	  - Geldwerte als normale Zahlen (werden intern in BigNum umgewandelt)
	  - "Growth"-Werte sind Faktoren pro Level (1.15 = +15 % pro Level)
]]

local Config = {}

----------------------------------------------------------------------
-- Allgemein
----------------------------------------------------------------------
Config.StartingCash = 50
Config.CurrencySymbol = "$"
Config.MinCycleDuration = 0.6 -- kein Arbeitszyklus wird schneller als das

----------------------------------------------------------------------
-- Schächte (Mine-Ebenen). Reihenfolge = Tiefe.
--   UnlockCost  : Preis zum Freischalten (erste Ebene ist gratis)
--   BaseYield   : Erzwert pro Abbau-Zyklus auf Level 1
--   BaseCycle   : Dauer eines Abbau-Zyklus auf Level 1
----------------------------------------------------------------------
export type ShaftDef = {
	Name: string,
	Ore: string,
	OreColor: Color3,
	RockColor: Color3,
	UnlockCost: number,
	BaseYield: number,
	BaseCycle: number,
}

Config.Shafts = {
	{
		Name = "Kohleflöz",
		Ore = "Kohle",
		OreColor = Color3.fromRGB(45, 45, 50),
		RockColor = Color3.fromRGB(96, 84, 74),
		UnlockCost = 0,
		BaseYield = 8,
		BaseCycle = 4,
	},
	{
		Name = "Kupferader",
		Ore = "Kupfer",
		OreColor = Color3.fromRGB(214, 120, 64),
		RockColor = Color3.fromRGB(104, 82, 70),
		UnlockCost = 300,
		BaseYield = 60,
		BaseCycle = 4.5,
	},
	{
		Name = "Eisengrube",
		Ore = "Eisen",
		OreColor = Color3.fromRGB(176, 170, 165),
		RockColor = Color3.fromRGB(90, 86, 84),
		UnlockCost = 7500,
		BaseYield = 700,
		BaseCycle = 5,
	},
	{
		Name = "Silberstollen",
		Ore = "Silber",
		OreColor = Color3.fromRGB(220, 228, 235),
		RockColor = Color3.fromRGB(78, 82, 92),
		UnlockCost = 150e3,
		BaseYield = 8e3,
		BaseCycle = 5.5,
	},
	{
		Name = "Goldader",
		Ore = "Gold",
		OreColor = Color3.fromRGB(255, 200, 40),
		RockColor = Color3.fromRGB(98, 78, 58),
		UnlockCost = 4e6,
		BaseYield = 95e3,
		BaseCycle = 6,
	},
	{
		Name = "Smaragdhöhle",
		Ore = "Smaragd",
		OreColor = Color3.fromRGB(40, 210, 110),
		RockColor = Color3.fromRGB(60, 78, 70),
		UnlockCost = 150e6,
		BaseYield = 1.1e6,
		BaseCycle = 6.5,
	},
	{
		Name = "Rubinkammer",
		Ore = "Rubin",
		OreColor = Color3.fromRGB(230, 40, 70),
		RockColor = Color3.fromRGB(84, 58, 62),
		UnlockCost = 6e9,
		BaseYield = 13e6,
		BaseCycle = 7,
	},
	{
		Name = "Saphirgrotte",
		Ore = "Saphir",
		OreColor = Color3.fromRGB(50, 110, 255),
		RockColor = Color3.fromRGB(56, 62, 92),
		UnlockCost = 300e9,
		BaseYield = 160e6,
		BaseCycle = 7.5,
	},
	{
		Name = "Diamantmine",
		Ore = "Diamant",
		OreColor = Color3.fromRGB(170, 245, 255),
		RockColor = Color3.fromRGB(64, 72, 86),
		UnlockCost = 15e12,
		BaseYield = 2e9,
		BaseCycle = 8,
	},
	{
		Name = "Mythrilkern",
		Ore = "Mythril",
		OreColor = Color3.fromRGB(190, 90, 255),
		RockColor = Color3.fromRGB(58, 44, 78),
		UnlockCost = 800e12,
		BaseYield = 25e9,
		BaseCycle = 8.5,
	},
} :: { ShaftDef }

----------------------------------------------------------------------
-- Ab Ebene 11 werden die Ebenen automatisch erzeugt (bis Config.ShaftCount).
-- Jede Ebene: Ertrag x YieldGrowth, Freischalten x UnlockGrowth gegenüber
-- der vorherigen. Die Erze wiederholen sich mit Stufe (Kohle II, Kohle III ...).
-- In der Grube sind immer SectionSize Ebenen gleichzeitig sichtbar (Abschnitt).
----------------------------------------------------------------------
Config.ShaftCount = 500

export type OreDef = { Name: string, Color: Color3 }

Config.ShaftGen = {
	YieldGrowth = 11,
	UnlockGrowth = 12,
	CycleBase = 8.5,
	CyclePerLevel = 0.004, -- tiefere Ebenen brauchen minimal länger
	CycleMax = 12,
	SectionSize = 10,
	Ores = {
		{ Name = "Kohle", Color = Color3.fromRGB(60, 60, 70) },
		{ Name = "Kupfer", Color = Color3.fromRGB(255, 120, 40) },
		{ Name = "Eisen", Color = Color3.fromRGB(190, 190, 200) },
		{ Name = "Silber", Color = Color3.fromRGB(230, 240, 255) },
		{ Name = "Gold", Color = Color3.fromRGB(255, 210, 0) },
		{ Name = "Smaragd", Color = Color3.fromRGB(0, 230, 110) },
		{ Name = "Rubin", Color = Color3.fromRGB(255, 20, 70) },
		{ Name = "Saphir", Color = Color3.fromRGB(30, 110, 255) },
		{ Name = "Diamant", Color = Color3.fromRGB(140, 250, 255) },
		{ Name = "Mythril", Color = Color3.fromRGB(190, 80, 255) },
		{ Name = "Obsidian", Color = Color3.fromRGB(90, 40, 140) },
		{ Name = "Amethyst", Color = Color3.fromRGB(200, 90, 255) },
		{ Name = "Topas", Color = Color3.fromRGB(255, 170, 30) },
		{ Name = "Jade", Color = Color3.fromRGB(40, 220, 150) },
		{ Name = "Platin", Color = Color3.fromRGB(225, 230, 250) },
		{ Name = "Titan", Color = Color3.fromRGB(120, 180, 230) },
		{ Name = "Opal", Color = Color3.fromRGB(255, 160, 230) },
		{ Name = "Bernstein", Color = Color3.fromRGB(255, 140, 0) },
		{ Name = "Kristall", Color = Color3.fromRGB(120, 255, 255) },
		{ Name = "Meteorit", Color = Color3.fromRGB(255, 90, 40) },
		{ Name = "Plasma", Color = Color3.fromRGB(255, 40, 220) },
		{ Name = "Sternenstaub", Color = Color3.fromRGB(255, 245, 120) },
		{ Name = "Void", Color = Color3.fromRGB(140, 0, 255) },
		{ Name = "Chrono", Color = Color3.fromRGB(0, 255, 190) },
		{ Name = "Kosmos", Color = Color3.fromRGB(60, 140, 255) },
	} :: { OreDef },
}

----------------------------------------------------------------------
-- Upgrade-Tracks pro Stationstyp
--   Jeder Track hat ein eigenes Level (Start 1).
--   Kosten für Level L -> L+1:  BaseCost * Growth^(L-1)
--   Für Schächte wird BaseCost zusätzlich mit dem BaseYield des Schachts skaliert
--   (CostFactor * BaseYield), damit tiefere Ebenen teurer sind.
--
--   Effekt-Formeln (siehe Formulas.luau):
--     Speed    : Multiplikator = 1 + PerLevel * (L-1)      (Zyklus wird kürzer)
--     Value    : Multiplikator = 1 + PerLevel * (L-1), * MilestoneMultiplier je MilestoneEvery Level
--     Capacity : Schacht -> Lagerplatz in "Zyklen"  = BaseCycles + PerLevel*(L-1)
--                Aufzug/Lager -> Ladung = BaseLoad * LoadGrowth^(L-1)
----------------------------------------------------------------------
export type TrackDef = {
	Id: string,
	Name: string,
	Description: string,
	Icon: string,
	MaxLevel: number,
	BaseCost: number?, -- feste Basis (Aufzug/Lager)
	CostFactor: number?, -- Faktor auf BaseYield (Schächte)
	Growth: number,
	PerLevel: number?,
	MilestoneEvery: number?,
	MilestoneMultiplier: number?,
	BaseCycles: number?,
	BaseLoad: number?,
	LoadGrowth: number?,
}

Config.Tracks = {
	Shaft = {
		{
			Id = "Speed",
			Name = "Abbautempo",
			Description = "Kumpel graben schneller",
			Icon = "⚡",
			MaxLevel = 100,
			CostFactor = 3,
			Growth = 1.16,
			PerLevel = 0.05,
		},
		{
			Id = "Value",
			Name = "Erzwert",
			Description = "Mehr Geld pro Abbau",
			Icon = "💎",
			MaxLevel = 800,
			CostFactor = 2,
			Growth = 1.13,
			PerLevel = 0.25,
			MilestoneEvery = 25,
			MilestoneMultiplier = 2,
		},
		{
			Id = "Capacity",
			Name = "Lagerplatz",
			Description = "Mehr Erz im Schachtlager",
			Icon = "📦",
			MaxLevel = 300,
			CostFactor = 1.5,
			Growth = 1.12,
			PerLevel = 2,
			BaseCycles = 10,
		},
	} :: { TrackDef },

	Elevator = {
		{
			Id = "Speed",
			Name = "Aufzugstempo",
			Description = "Aufzug fährt schneller",
			Icon = "⚡",
			MaxLevel = 100,
			BaseCost = 60,
			Growth = 1.22,
			PerLevel = 0.06,
		},
		{
			Id = "Capacity",
			Name = "Ladekapazität",
			Description = "Mehr Erz pro Fahrt",
			Icon = "📦",
			MaxLevel = 1500,
			BaseCost = 40,
			Growth = 1.17,
			BaseLoad = 40,
			LoadGrowth = 1.15,
		},
	} :: { TrackDef },

	Warehouse = {
		{
			Id = "Speed",
			Name = "Transporttempo",
			Description = "Transporter laufen schneller",
			Icon = "⚡",
			MaxLevel = 100,
			BaseCost = 60,
			Growth = 1.22,
			PerLevel = 0.06,
		},
		{
			Id = "Capacity",
			Name = "Transportmenge",
			Description = "Mehr Erz pro Verkauf",
			Icon = "📦",
			MaxLevel = 1500,
			BaseCost = 40,
			Growth = 1.17,
			BaseLoad = 35,
			LoadGrowth = 1.15,
		},
		{
			Id = "Value",
			Name = "Verkaufspreis",
			Description = "Höherer Preis beim Händler",
			Icon = "💰",
			MaxLevel = 500,
			BaseCost = 150,
			Growth = 1.2,
			PerLevel = 0.04,
			MilestoneEvery = 50,
			MilestoneMultiplier = 1.5,
		},
	} :: { TrackDef },
}

-- Basis-Zyklusdauern für Aufzug und Lager
Config.Elevator = {
	BaseTrip = 3, -- Grundzeit einer Fahrt
	PerShaftTrip = 0.8, -- zusätzliche Zeit pro freigeschaltetem Schacht
	TripShaftCap = 10, -- ab so vielen Schächten wird die Fahrt nicht länger
	-- Ladung von Aufzug/Händler wächst mit (Ertrag tiefste Ebene / Ertrag Ebene 1) ^ DepthExponent
	DepthExponent = 0.85,
}

Config.Warehouse = {
	BaseCycle = 3.5,
}

-- Kauf-Mengen im Upgrade-Menü (-1 = Maximum)
Config.BuyAmounts = { 1, 10, -1 }

----------------------------------------------------------------------
-- Manager
--   Ohne Manager muss der Spieler jeden Zyklus selbst starten (Tippen).
--   Ein Manager automatisiert seine Station, gibt einen passiven Tempo-Bonus
--   und hat eine aktive Fähigkeit, die alle Arbeiter der Station boostet.
----------------------------------------------------------------------
export type RarityDef = {
	Id: string,
	Name: string,
	Weight: number,
	Color: Color3,
	PassiveSpeed: number, -- dauerhafter Tempo-Multiplikator
	AbilityMultiplier: number, -- Multiplikator der aktiven Fähigkeit
	AbilityDuration: number,
	AbilityCooldown: number,
	Discount: number, -- Rabatt-Fähigkeit (0.3 = 30 % günstiger)
}

export type AbilityDef = {
	Id: string,
	Name: string,
	Icon: string,
	Description: string, -- %s wird durch den Wert ersetzt
}

Config.Managers = {
	HireBaseCost = {
		Shaft = 50,
		Elevator = 60,
		Warehouse = 60,
	} :: { [string]: number },
	HireCostGrowth = 3.5, -- pro bereits eingestelltem Manager dieses Bereichs
	MaxOwned = 600, -- genug für 500 Ebenen + Aufzug + Händler
	-- Seltenheiten (Gewicht = relative Wahrscheinlichkeit)
	Rarities = {
		{
			Id = "Common",
			Name = "Gewöhnlich",
			Weight = 55,
			Color = Color3.fromRGB(170, 178, 189),
			PassiveSpeed = 1.0,
			AbilityMultiplier = 2,
			AbilityDuration = 30,
			AbilityCooldown = 240,
			Discount = 0.2,
		},
		{
			Id = "Rare",
			Name = "Selten",
			Weight = 28,
			Color = Color3.fromRGB(70, 160, 255),
			PassiveSpeed = 1.1,
			AbilityMultiplier = 2.5,
			AbilityDuration = 45,
			AbilityCooldown = 220,
			Discount = 0.3,
		},
		{
			Id = "Epic",
			Name = "Episch",
			Weight = 12,
			Color = Color3.fromRGB(176, 92, 255),
			PassiveSpeed = 1.2,
			AbilityMultiplier = 3,
			AbilityDuration = 60,
			AbilityCooldown = 200,
			Discount = 0.4,
		},
		{
			Id = "Legendary",
			Name = "Legendär",
			Weight = 4.5,
			Color = Color3.fromRGB(255, 184, 40),
			PassiveSpeed = 1.35,
			AbilityMultiplier = 4,
			AbilityDuration = 75,
			AbilityCooldown = 180,
			Discount = 0.5,
		},
		{
			Id = "Mythic",
			Name = "Mythisch",
			Weight = 0.5,
			Color = Color3.fromRGB(255, 70, 140),
			PassiveSpeed = 1.6,
			AbilityMultiplier = 6,
			AbilityDuration = 90,
			AbilityCooldown = 150,
			Discount = 0.65,
		},
	} :: { RarityDef },
	-- Mit Glücks-Gamepass werden die Gewichte ab "Rare" damit multipliziert
	LuckyMultiplier = 2,
	-- Mögliche Fähigkeiten je Bereich
	AbilitiesByArea = {
		Shaft = { "Speed", "Value", "Discount" },
		Elevator = { "Speed", "Capacity", "Discount" },
		Warehouse = { "Speed", "Capacity", "Discount" },
	} :: { [string]: { string } },
	Abilities = {
		Speed = { Id = "Speed", Name = "Turbo", Icon = "⚡", Description = "Arbeiter %s schneller" },
		Value = { Id = "Value", Name = "Goldader", Icon = "💎", Description = "Erzwert %s" },
		Capacity = { Id = "Capacity", Name = "Schwerlast", Icon = "📦", Description = "Ladung %s" },
		Discount = { Id = "Discount", Name = "Sparfuchs", Icon = "🏷️", Description = "Upgrades %s günstiger" },
	} :: { [string]: AbilityDef },
	Names = {
		"Gustav",
		"Helga",
		"Bruno",
		"Frieda",
		"Otto",
		"Greta",
		"Karl",
		"Ilse",
		"Heinz",
		"Erna",
		"Fritz",
		"Lotte",
		"Willi",
		"Hanna",
		"Kurt",
		"Rosi",
		"Egon",
		"Trude",
		"Paul",
		"Mia",
	},
}

----------------------------------------------------------------------
-- Avatare: Kumpel und Manager tragen die Roblox-Avatare der Freunde
-- des Spielers (mit Bauarbeiterhelm). Ohne Freunde: eigener Avatar,
-- sonst die Block-Figur.
----------------------------------------------------------------------
Config.Avatars = {
	Enabled = true,
	UseFriends = true,
	OwnAvatarFallback = true,
	MaxFriends = 60, -- so viele Freunde werden geladen
	MinerHatColor = Color3.fromRGB(255, 204, 40),
	MaxAvatarsPerServer = 250, -- Schutz für die Performance
}

----------------------------------------------------------------------
-- Rebirth / Prestige
--   Punkte = floor(PointsScale * (1 + log10(RunCash / MinRunCash)) ^ PointsPower)
--   (logarithmisch: lohnt sich immer, explodiert aber nicht)
--   Multiplikator = 1 + Punkte * MultiplierPerPoint
----------------------------------------------------------------------
Config.Rebirth = {
	MinRunCash = 1e6, -- so viel muss in diesem Durchlauf verdient worden sein
	PointsScale = 10,
	PointsPower = 2.6,
	MultiplierPerPoint = 0.05,
	GemsBase = 10,
	GemsPerTenPoints = 1,
}

----------------------------------------------------------------------
-- Offline-Einnahmen
----------------------------------------------------------------------
Config.Offline = {
	MaxHours = 8,
	MaxHoursWithPass = 24,
	Efficiency = 1.0, -- Anteil des normalen Einkommens
	MinSeconds = 60, -- darunter kein Popup
	DoubleGemCost = 10, -- "x2 einsammeln" kostet so viele Gems
}

----------------------------------------------------------------------
-- Stehlen aus fremden Aufzugslagern
----------------------------------------------------------------------
Config.Steal = {
	Enabled = true,
	HoldDuration = 4, -- so lange muss der Prompt gehalten werden
	MaxActivationDistance = 10,
	Percent = 0.15, -- Anteil des Aufzugslagers
	CapSecondsOfThiefIncome = 180, -- max. Beute = so viele Sekunden Einkommen des Diebs
	MinCap = 250, -- ... aber mindestens so viel
	ThiefCooldown = 60, -- Dieb kann so oft stehlen
	VictimCooldown = 120, -- Opfer kann so oft bestohlen werden
	NewPlayerProtection = 600, -- Schutz nach dem Beitreten
	GuardRadius = 18, -- steht der Besitzer so nah an seinem Aufzug, scheitert der Diebstahl
	-- Basis abschließen (Steal-a-Brainrot-Stil): gratis, mit Abklingzeit
	LockDuration = 60,
	LockCooldown = 180,
}

----------------------------------------------------------------------
-- Sprinten (Shift oder Strg halten, auf dem Handy Sprint-Button)
----------------------------------------------------------------------
Config.Sprint = {
	Multiplier = 1.7, -- Laufgeschwindigkeit x
	FovBoost = 10, -- Sichtfeld wird beim Sprinten etwas weiter (Tempo-Gefühl)
}

----------------------------------------------------------------------
-- Gems & Belohnungen
----------------------------------------------------------------------
Config.Gems = {
	PlaytimeInterval = 600, -- alle X Sekunden online...
	PlaytimeAmount = 2, -- ...gibt es so viele Gems
}

-- Tägliche Login-Belohnung. Serie bricht nach 48h ohne Login ab.
-- Cash-Belohnungen sind "Sekunden Einkommen" (mind. MinCash).
export type DailyReward = { Gems: number, IncomeSeconds: number, MinCash: number }
Config.Daily = {
	StreakResetHours = 48,
	Rewards = {
		{ Gems = 5, IncomeSeconds = 300, MinCash = 100 },
		{ Gems = 5, IncomeSeconds = 600, MinCash = 250 },
		{ Gems = 10, IncomeSeconds = 900, MinCash = 500 },
		{ Gems = 10, IncomeSeconds = 1200, MinCash = 1000 },
		{ Gems = 15, IncomeSeconds = 1800, MinCash = 2500 },
		{ Gems = 20, IncomeSeconds = 2700, MinCash = 5000 },
		{ Gems = 40, IncomeSeconds = 3600, MinCash = 10000 },
	} :: { DailyReward },
}

----------------------------------------------------------------------
-- Server-Events ("Goldrausch")
----------------------------------------------------------------------
Config.Events = {
	Enabled = true,
	MinInterval = 600,
	MaxInterval = 1200,
	List = {
		{
			Id = "GoldRush",
			Name = "GOLDRAUSCH!",
			Description = "2x Einkommen für alle",
			Duration = 90,
			CashMultiplier = 2,
			SpeedMultiplier = 1,
		},
		{
			Id = "Frenzy",
			Name = "ARBEITSFIEBER!",
			Description = "Alle Arbeiter 2x schneller",
			Duration = 90,
			CashMultiplier = 1,
			SpeedMultiplier = 2,
		},
	},
}

----------------------------------------------------------------------
-- Shop
--   Gem-Items: Boosts mit Laufzeit (stapelbar bis MaxBoostSeconds)
--   Robux: ProductId / GamePassId auf 0 lassen, bis du eigene IDs hast.
----------------------------------------------------------------------
export type GemItem = {
	Id: string,
	Name: string,
	Description: string,
	Icon: string,
	Cost: number,
	Boost: string?, -- "Cash" | "Speed" | "Shield"
	Duration: number?,
	InstantIncomeSeconds: number?,
}

export type ProductDef = {
	Id: string,
	Name: string,
	Description: string,
	Icon: string,
	ProductId: number,
	Gems: number?,
	IncomeSeconds: number?,
}

export type PassDef = {
	Id: string,
	Name: string,
	Description: string,
	Icon: string,
	GamePassId: number,
}

Config.Shop = {
	MaxBoostSeconds = 24 * 3600,
	GemItems = {
		{
			Id = "Cash2x",
			Name = "2x Geld",
			Description = "Doppeltes Einkommen für 15 Minuten",
			Icon = "💰",
			Cost = 25,
			Boost = "Cash",
			Duration = 900,
		},
		{
			Id = "Speed2x",
			Name = "2x Tempo",
			Description = "Alle Arbeiter doppelt so schnell (15 Min)",
			Icon = "⚡",
			Cost = 25,
			Boost = "Speed",
			Duration = 900,
		},
		{
			Id = "Shield",
			Name = "Diebstahl-Schild",
			Description = "30 Minuten unbestehlbar",
			Icon = "🛡️",
			Cost = 15,
			Boost = "Shield",
			Duration = 1800,
		},
		{
			Id = "CashCase",
			Name = "Geldkoffer",
			Description = "Sofort 30 Minuten Einkommen",
			Icon = "💼",
			Cost = 30,
			InstantIncomeSeconds = 1800,
		},
	} :: { GemItem },
	Products = {
		{
			Id = "Gems100",
			Name = "100 Gems",
			Description = "Ein Beutel Edelsteine",
			Icon = "💎",
			ProductId = 0,
			Gems = 100,
		},
		{
			Id = "Gems550",
			Name = "550 Gems",
			Description = "Eine Kiste Edelsteine",
			Icon = "💎",
			ProductId = 0,
			Gems = 550,
		},
		{
			Id = "Gems1200",
			Name = "1200 Gems",
			Description = "Ein Schatz voller Edelsteine",
			Icon = "💎",
			ProductId = 0,
			Gems = 1200,
		},
		{
			Id = "CashBag",
			Name = "Geldsack",
			Description = "Sofort 2 Stunden Einkommen",
			Icon = "💰",
			ProductId = 0,
			IncomeSeconds = 7200,
		},
	} :: { ProductDef },
	Passes = {
		{
			Id = "DoubleCash",
			Name = "2x Geld",
			Description = "Für immer doppeltes Einkommen",
			Icon = "💰",
			GamePassId = 0,
		},
		{
			Id = "LongOffline",
			Name = "Nachtschicht",
			Description = "24h statt 8h Offline-Einnahmen",
			Icon = "🌙",
			GamePassId = 0,
		},
		{
			Id = "LuckyManagers",
			Name = "Glücks-Manager",
			Description = "2x Chance auf seltene Manager",
			Icon = "🍀",
			GamePassId = 0,
		},
	} :: { PassDef },
}

----------------------------------------------------------------------
-- Admin-System
--   Der Owner (du) hat IMMER alle Rechte, kann nicht entfernt und von
--   Admins nicht negativ beeinflusst werden (nichts wegnehmen, kein Kick).
--   Admins vergibt nur der Owner im Admin-Menü, inkl. einzelner Rechte.
----------------------------------------------------------------------
export type AdminPermissionDef = { Id: string, Name: string, Icon: string, Default: boolean }
export type PowerDef = { Id: string, Name: string, Icon: string, Description: string }

Config.Admin = {
	OwnerName = "recher1001",
	-- Optional, aber sicherer: deine Roblox-UserId (Zahl aus roblox.com/users/<ID>/profile).
	-- Bei 0 wird die ID beim Serverstart automatisch über den Namen ermittelt.
	OwnerUserId = 0,
	-- In Roblox Studio ist jeder Test-Spieler Owner (zum Testen). false = nur echter Owner.
	StudioEveryoneOwner = true,
	StoreName = "IdleMiner_Admins_v1",
	Permissions = {
		{ Id = "Cash", Name = "Geld geben/nehmen", Icon = "💰", Default = true },
		{ Id = "Gems", Name = "Gems geben/nehmen", Icon = "💎", Default = true },
		{ Id = "Progress", Name = "Ebenen, Manager, Cooldowns", Icon = "🔓", Default = true },
		{ Id = "Powers", Name = "Kräfte geben/nehmen", Icon = "⚡", Default = true },
		{ Id = "Events", Name = "Events starten", Icon = "🔥", Default = false },
		{ Id = "Kick", Name = "Spieler kicken", Icon = "👢", Default = false },
		{ Id = "Reset", Name = "Spielstand zurücksetzen", Icon = "♻", Default = false },
	} :: { AdminPermissionDef },
	-- OP-Kräfte, die Admins vergeben/wegnehmen können (werden gespeichert)
	Powers = {
		{
			Id = "Carpet",
			Name = "Fliegender Teppich",
			Icon = "🧞",
			Description = "Fliegen! Leertaste/▲ hoch, Q/▼ runter",
		},
		{
			Id = "Speed",
			Name = "Super-Speed",
			Icon = "⚡",
			Description = "Item im Inventar: ausrüsten = 4x schneller",
		},
		{
			Id = "Jump",
			Name = "Mega-Sprung",
			Icon = "🦘",
			Description = "Item im Inventar: ausrüsten = Mega-Sprung",
		},
		{ Id = "Shield", Name = "Unbestehlbar", Icon = "🛡️", Description = "Niemand kann dich bestehlen" },
		{ Id = "MineTurbo", Name = "Turbo-Mine", Icon = "🚀", Description = "Alle Arbeiter 3x schneller" },
		{ Id = "GoldenTouch", Name = "Goldener Händler", Icon = "💰", Description = "3x Einkommen" },
	} :: { PowerDef },
	WalkSpeed = 64,
	JumpPower = 125,
	MineTurboMultiplier = 3,
	GoldenTouchMultiplier = 3,
	CarpetSpeed = 70,
}

----------------------------------------------------------------------
-- Datenspeicherung
----------------------------------------------------------------------
Config.Data = {
	StoreName = "IdleMiner_PlayerData_v1",
	KeyPrefix = "Player_",
	AutosaveInterval = 60,
	MaxRetries = 5,
	RetryBaseDelay = 1, -- exponentielles Backoff: 1, 2, 4, 8 ...
	SessionLockTimeout = 600, -- ein fremder Lock gilt nach X Sekunden als verwaist
	LockWaitAttempts = 6, -- so oft wird bei fremdem Lock gewartet
	LockWaitDelay = 5,
	MaxReceiptHistory = 50,
}

----------------------------------------------------------------------
-- Netzwerk / Exploit-Schutz: Token-Bucket pro Spieler und Aktion
--   Rate = Tokens pro Sekunde, Burst = maximale Tokens
----------------------------------------------------------------------
Config.RateLimits = {
	Default = { Rate = 4, Burst = 8 },
	Work = { Rate = 12, Burst = 20 },
	Upgrade = { Rate = 10, Burst = 20 },
	HireManager = { Rate = 2, Burst = 4 },
	RequestSync = { Rate = 1, Burst = 3 },
	AdminAction = { Rate = 8, Burst = 16 },
	AdminInfo = { Rate = 4, Burst = 8 },
	ToggleCarpet = { Rate = 2, Burst = 4 },
} :: { [string]: { Rate: number, Burst: number } }

----------------------------------------------------------------------
-- Welt / Plots
----------------------------------------------------------------------
Config.World = {
	MaxPlots = 6,
	PlotSpacing = 130,
	LevelHeight = 14,
	LabelUpdateInterval = 0.5,
	TickInterval = 0.1,
	SyncInterval = 0.25,
}

----------------------------------------------------------------------
-- Beleuchtung
----------------------------------------------------------------------
Config.Lighting = {
	ClockTime = 14.6,
	Brightness = 3,
	Ambient = Color3.fromRGB(96, 84, 120),
	OutdoorAmbient = Color3.fromRGB(150, 140, 170),
	FogColor = Color3.fromRGB(190, 170, 255),
	Bloom = { Intensity = 0.8, Size = 30, Threshold = 1.4 },
	ColorCorrection = {
		Brightness = 0.05,
		Contrast = 0.16,
		Saturation = 0.38, -- kräftige, satte Farben
		TintColor = Color3.fromRGB(255, 246, 255),
	},
	Atmosphere = {
		Density = 0.26,
		Offset = 0.12,
		Color = Color3.fromRGB(200, 180, 255),
		Decay = Color3.fromRGB(150, 100, 200),
		Glare = 0.4,
		Haze = 1.2,
	},
	SunRays = { Intensity = 0.08, Spread = 0.9 },
}

----------------------------------------------------------------------
-- Sounds (rbxasset:// sind eingebaute Roblox-Sounds; durch eigene
-- "rbxassetid://123" ersetzen. Leerer String = stumm)
----------------------------------------------------------------------
Config.Sounds = {
	Click = "rbxasset://sounds/clickfast.wav",
	Purchase = "rbxasset://sounds/electronicpingshort.wav",
	Error = "rbxasset://sounds/clickfast.wav",
	Coin = "rbxasset://sounds/electronicpingshort.wav",
	Reveal = "rbxasset://sounds/electronicpingshort.wav",
	Alarm = "rbxasset://sounds/clickfast.wav",
	Rebirth = "rbxasset://sounds/electronicpingshort.wav",
} :: { [string]: string }

return Config

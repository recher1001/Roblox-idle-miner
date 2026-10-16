--!strict
--[[
	PetService
	==========
	  * Eier öffnen (1x oder 3x): Würfeln passiert NUR auf dem Server
	  * Pets ausrüsten / ablegen / "Beste ausrüsten" / freilassen
	  * Zusätzliche Ausrüst-Slots: mit Spielgeld bis 5, mit Robux bis 10
	    (Robux-Slots kommen über ShopService/ProcessReceipt)
	  * Trading-Tickets kaufen (Geld)
	  * Seltene Pets (<= 1 %) werden dem ganzen Server verkündet

	Die ausgerüsteten Pets stehen als Attribut "Pets" am Spieler, damit alle
	Clients sie hinter dem Spieler herfliegen lassen können.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local BigNum = require(Shared.BigNum)
local Config = require(Shared.Config)
local Formulas = require(Shared.Formulas)
local Net = require(Shared.Net)
local Types = require(Shared.Types)

local NetService = require(script.Parent.NetService)
local SessionService = require(script.Parent.SessionService)

type Session = SessionService.Session
type PetData = Types.PetData

local PetService = {}

-- Vom TradeService gesetzt: Pets in einem laufenden Handelsangebot sind gesperrt
PetService.isLocked = function(_session: Session, _petUid: string): boolean
	return false
end

local rng = Random.new()

local function rollPet(egg: Config.EggDef): Config.EggChance
	local total = 0
	for _, c in egg.Chances do
		total += c.Chance
	end
	local roll = rng:NextNumber(0, total)
	for _, c in egg.Chances do
		roll -= c.Chance
		if roll <= 0 then
			return c
		end
	end
	return egg.Chances[1]
end

local function findPet(data: Types.PlayerData, petUid: string): (PetData?, number?)
	for i, pet in data.Pets do
		if pet.Id == petUid then
			return pet, i
		end
	end
	return nil, nil
end

PetService.findPet = findPet

--- Attribut für die Folge-Pets aktualisieren + Client synchronisieren
function PetService.refresh(session: Session)
	local ids = {}
	for _, pet in Formulas.sortPetsByPower(session.Data.Pets) do
		if pet.Equipped then
			table.insert(ids, pet.Pet)
		end
	end
	session.Player:SetAttribute("Pets", table.concat(ids, ","))
	session.Dirty = true
end

--- Fügt ein Pet ins Inventar ein (nil = Inventar voll / unbekanntes Pet)
function PetService.add(session: Session, petId: string, autoEquip: boolean): PetData?
	local data = session.Data
	if not Formulas.petDef(petId) or #data.Pets >= Config.Pets.MaxOwned then
		return nil
	end
	local pet: PetData = {
		Id = "P" .. tostring(data.NextPetId),
		Pet = petId,
		Equipped = autoEquip and Formulas.equippedCount(data) < Formulas.petSlots(data),
	}
	data.NextPetId += 1
	table.insert(data.Pets, pet)
	return pet
end

--- Entfernt ein Pet aus dem Inventar
function PetService.remove(session: Session, petUid: string): PetData?
	local pet, index = findPet(session.Data, petUid)
	if pet and index then
		table.remove(session.Data.Pets, index)
	end
	return pet
end

local function announce(player: Player, def: Config.PetDef, chance: number)
	local text = string.format(
		"🎉 %s hat %s %s (%s) geschlüpft!",
		player.DisplayName,
		def.Icon,
		def.Name,
		Formulas.formatChance(chance)
	)
	for _, other in Players:GetPlayers() do
		SessionService.notify(other, text, "gold")
	end
end

function PetService.openEgg(session: Session, eggId: string, count: number): (boolean, string?)
	local egg = Formulas.eggDef(eggId)
	if not egg then
		return false, "Unbekanntes Ei"
	end
	if not table.find(Config.Pets.MultiOpen, count) then
		return false, "Ungültige Anzahl"
	end
	local data = session.Data
	if #data.Pets + count > Config.Pets.MaxOwned then
		return false, string.format("Inventar voll (%d)! Lass Pets frei.", Config.Pets.MaxOwned)
	end
	local cost = BigNum.mulNum(Formulas.eggCost(data, egg), count)
	if egg.Currency == "Gems" then
		if not SessionService.spendGems(session, BigNum.toNumber(cost)) then
			return false, "Nicht genug Gems"
		end
	elseif not SessionService.spendCash(session, cost) then
		return false, "Nicht genug Geld"
	end

	local results = {}
	for _ = 1, count do
		local chance = rollPet(egg)
		local pet = PetService.add(session, chance.Pet, true)
		local def = Formulas.petDef(chance.Pet)
		if pet and def then
			table.insert(results, { Id = pet.Id, Pet = pet.Pet, Chance = chance.Chance, Equipped = pet.Equipped })
			if chance.Chance <= Config.Pets.AnnounceBelow then
				announce(session.Player, def, chance.Chance)
			end
		end
	end
	data.EggsOpened += count
	PetService.refresh(session)
	Net.event("EggHatch"):FireClient(session.Player, { EggId = egg.Id, Pets = results })
	return true, nil
end

function PetService.equip(session: Session, petUid: string, on: boolean): (boolean, string?)
	local data = session.Data
	local pet = findPet(data, petUid)
	if not pet then
		return false, "Pet nicht gefunden"
	end
	if on and not pet.Equipped then
		local slots = Formulas.petSlots(data)
		if Formulas.equippedCount(data) >= slots then
			return false, string.format("Alle %d Slots belegt! Kaufe mehr Slots oder lege ein Pet ab.", slots)
		end
	end
	pet.Equipped = on
	PetService.refresh(session)
	return true, nil
end

function PetService.equipBest(session: Session): (boolean, string?)
	local data = session.Data
	local slots = Formulas.petSlots(data)
	for _, pet in data.Pets do
		pet.Equipped = false
	end
	for i, pet in Formulas.sortPetsByPower(data.Pets) do
		if i > slots then
			break
		end
		pet.Equipped = true
	end
	PetService.refresh(session)
	return true, nil
end

function PetService.release(session: Session, petUid: string): (boolean, string?)
	local pet = findPet(session.Data, petUid)
	if not pet then
		return false, "Pet nicht gefunden"
	end
	if PetService.isLocked(session, petUid) then
		return false, "Dieses Pet ist gerade im Handel"
	end
	PetService.remove(session, petUid)
	PetService.refresh(session)
	return true, nil
end

--- Alle nicht ausgerüsteten Pets bis einschließlich dieser Seltenheit freilassen
function PetService.releaseUpTo(session: Session, rarityId: string): (boolean, string?)
	local maxIndex = Formulas.petRarityIndex(rarityId)
	if maxIndex > 2 then
		return false, "Nur Gewöhnlich/Ungewöhnlich auf einmal"
	end
	local data = session.Data
	local kept: { PetData } = {}
	local released = 0
	for _, pet in data.Pets do
		local def = Formulas.petDef(pet.Pet)
		local weak = def ~= nil and Formulas.petRarityIndex(def.Rarity) <= maxIndex
		if weak and not pet.Equipped and not PetService.isLocked(session, pet.Id) then
			released += 1
		else
			table.insert(kept, pet)
		end
	end
	if released == 0 then
		return false, "Nichts zum Freilassen"
	end
	data.Pets = kept
	PetService.refresh(session)
	SessionService.notify(session.Player, string.format("🐾 %d Pets freigelassen", released), "info")
	return true, nil
end

function PetService.buySlot(session: Session): (boolean, string?)
	local cost = Formulas.nextCashSlotCost(session.Data)
	if not cost then
		return false, "Alle Geld-Slots gekauft - weitere Slots gibt's für Robux im Shop"
	end
	if not SessionService.spendCash(session, cost) then
		return false, "Nicht genug Geld"
	end
	session.Data.PetSlotsBought += 1
	PetService.refresh(session)
	SessionService.notify(
		session.Player,
		string.format("🐾 Neuer Pet-Slot! Jetzt %d Slots", Formulas.petSlots(session.Data)),
		"success"
	)
	return true, nil
end

function PetService.buyTickets(session: Session, count: number): (boolean, string?)
	if count < 1 or count > 10 then
		return false, "Ungültige Anzahl"
	end
	local data = session.Data
	if data.TradeTickets + count > Config.Trading.MaxTickets then
		return false, string.format("Maximal %d Tickets", Config.Trading.MaxTickets)
	end
	if not SessionService.spendCash(session, BigNum.new(Config.Trading.TicketCost * count)) then
		return false, "Nicht genug Geld"
	end
	data.TradeTickets += count
	session.Dirty = true
	SessionService.notify(session.Player, string.format("🎟️ +%d Trading-Ticket", count), "success")
	return true, nil
end

function PetService.start()
	SessionService.onStart(30, PetService.refresh)

	NetService.register("OpenEgg", { EggId = "string", Count = "integer" }, function(session, payload)
		return PetService.openEgg(session, payload.EggId, payload.Count)
	end)
	NetService.register("EquipPet", { PetId = "string", On = "boolean" }, function(session, payload)
		return PetService.equip(session, payload.PetId, payload.On)
	end)
	NetService.register("EquipBestPets", {}, function(session)
		return PetService.equipBest(session)
	end)
	NetService.register("ReleasePet", { PetId = "string" }, function(session, payload)
		return PetService.release(session, payload.PetId)
	end)
	NetService.register("ReleaseWeakPets", { Rarity = "string" }, function(session, payload)
		return PetService.releaseUpTo(session, payload.Rarity)
	end)
	NetService.register("BuyPetSlot", {}, function(session)
		return PetService.buySlot(session)
	end)
	NetService.register("BuyTradeTickets", { Count = "integer" }, function(session, payload)
		return PetService.buyTickets(session, payload.Count)
	end)
end

return PetService

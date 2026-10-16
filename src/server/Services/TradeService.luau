--!strict
--[[
	TradeService
	============
	Pet-Handel zwischen zwei Spielern - nur Pets, niemals Geld oder Gems.

	Ablauf:
	  1. Spieler A schickt eine Anfrage (braucht 1 Trading-Ticket)
	  2. Spieler B nimmt an (braucht ebenfalls 1 Ticket)
	  3. Beide legen Pets ins Angebot. Jede Änderung setzt "Bereit" zurück.
	  4. Beide "Bereit" -> Countdown (Config.Trading.ConfirmCountdown). Ändert
	     jemand etwas, wird der Countdown abgebrochen.
	  5. Ausführung: alles wird neu geprüft (Besitz, Platz, Tickets), dann
	     tauschen die Pets atomar die Besitzer und beide Spielstände werden
	     sofort gespeichert. Jeder zahlt 1 Ticket.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Clock = require(Shared.Clock)
local Config = require(Shared.Config)
local Net = require(Shared.Net)
local Types = require(Shared.Types)

local DataService = require(script.Parent.DataService)
local NetService = require(script.Parent.NetService)
local PetService = require(script.Parent.PetService)
local SessionService = require(script.Parent.SessionService)

type Session = SessionService.Session

type Side = { Session: Session, Offer: { string }, Ready: boolean }
type Trade = { Id: number, A: Side, B: Side, ConfirmAt: number?, Token: number, Done: boolean }

local TradeService = {}

local trades: { [Player]: Trade } = {}
local invites: { [Player]: { [Player]: number } } = {} -- invites[Empfänger][Absender] = läuft ab
local nextTradeId = 1

local function sides(trade: Trade, player: Player): (Side, Side)
	if trade.A.Session.Player == player then
		return trade.A, trade.B
	end
	return trade.B, trade.A
end

local function offerData(side: Side): { Types.PetData }
	local list = {}
	for _, uid in side.Offer do
		local pet = PetService.findPet(side.Session.Data, uid)
		if pet then
			table.insert(list, { Id = pet.Id, Pet = pet.Pet, Equipped = pet.Equipped })
		end
	end
	return list
end

local function push(trade: Trade)
	for _, side in { trade.A, trade.B } do
		local me, other = sides(trade, side.Session.Player)
		local view: Types.TradeView = {
			Id = trade.Id,
			PartnerUserId = other.Session.Player.UserId,
			PartnerName = other.Session.Player.DisplayName,
			MyOffer = offerData(me),
			TheirOffer = offerData(other),
			MyReady = me.Ready,
			TheirReady = other.Ready,
			ConfirmAt = trade.ConfirmAt,
		}
		Net.event("Trade"):FireClient(side.Session.Player, view)
	end
end

local function finish(trade: Trade, message: string?, kind: string?)
	if trade.Done then
		return
	end
	trade.Done = true
	trade.Token += 1
	for _, side in { trade.A, trade.B } do
		local player = side.Session.Player
		if trades[player] == trade then
			trades[player] = nil
		end
		if player.Parent then
			Net.event("Trade"):FireClient(player, nil)
			if message then
				SessionService.notify(player, message, kind or "info")
			end
		end
	end
end

local function resetReady(trade: Trade)
	trade.A.Ready = false
	trade.B.Ready = false
	trade.ConfirmAt = nil
	trade.Token += 1
end

local function startTrade(a: Session, b: Session)
	local trade: Trade = {
		Id = nextTradeId,
		A = { Session = a, Offer = {}, Ready = false },
		B = { Session = b, Offer = {}, Ready = false },
		ConfirmAt = nil,
		Token = 0,
		Done = false,
	}
	nextTradeId += 1
	trades[a.Player] = trade
	trades[b.Player] = trade
	if invites[a.Player] then
		invites[a.Player][b.Player] = nil
	end
	if invites[b.Player] then
		invites[b.Player][a.Player] = nil
	end
	push(trade)
end

----------------------------------------------------------------------
-- Ausführung
----------------------------------------------------------------------
local function ownsAll(session: Session, offer: { string }): boolean
	for _, uid in offer do
		if not PetService.findPet(session.Data, uid) then
			return false
		end
	end
	return true
end

local function execute(trade: Trade)
	if trade.Done then
		return
	end
	local a, b = trade.A.Session, trade.B.Session
	if SessionService.get(a.Player) ~= a or SessionService.get(b.Player) ~= b then
		finish(trade, "Handel abgebrochen", "warn")
		return
	end
	if not ownsAll(a, trade.A.Offer) or not ownsAll(b, trade.B.Offer) then
		finish(trade, "Handel abgebrochen: ein Pet fehlt", "warn")
		return
	end
	if #trade.A.Offer == 0 and #trade.B.Offer == 0 then
		resetReady(trade)
		push(trade)
		return
	end
	local max = Config.Pets.MaxOwned
	if #a.Data.Pets - #trade.A.Offer + #trade.B.Offer > max then
		finish(trade, a.Player.DisplayName .. " hat kein Platz im Pet-Inventar", "warn")
		return
	end
	if #b.Data.Pets - #trade.B.Offer + #trade.A.Offer > max then
		finish(trade, b.Player.DisplayName .. " hat kein Platz im Pet-Inventar", "warn")
		return
	end
	if a.Data.TradeTickets < 1 or b.Data.TradeTickets < 1 then
		finish(trade, "Handel abgebrochen: jemand hat kein Trading-Ticket", "warn")
		return
	end

	-- Ab hier keine yields: Pets entfernen und beim Partner neu anlegen
	local fromA: { string } = {}
	local fromB: { string } = {}
	for _, uid in trade.A.Offer do
		local pet = PetService.remove(a, uid)
		if pet then
			table.insert(fromA, pet.Pet)
		end
	end
	for _, uid in trade.B.Offer do
		local pet = PetService.remove(b, uid)
		if pet then
			table.insert(fromB, pet.Pet)
		end
	end
	for _, petId in fromA do
		PetService.add(b, petId, false)
	end
	for _, petId in fromB do
		PetService.add(a, petId, false)
	end
	a.Data.TradeTickets -= 1
	b.Data.TradeTickets -= 1
	PetService.refresh(a)
	PetService.refresh(b)
	print(
		string.format(
			"[Trade] %s <-> %s: [%s] gegen [%s]",
			a.Player.Name,
			b.Player.Name,
			table.concat(fromA, ","),
			table.concat(fromB, ",")
		)
	)
	finish(trade, "🤝 Handel erfolgreich!", "success")
	SessionService.effect(a.Player, "Trade", {})
	SessionService.effect(b.Player, "Trade", {})
	-- sofort speichern, damit kein Pet durch einen Server-Absturz doppelt existiert
	task.spawn(function()
		DataService.save(a.Profile, false)
	end)
	task.spawn(function()
		DataService.save(b.Profile, false)
	end)
end

----------------------------------------------------------------------
-- Aktionen
----------------------------------------------------------------------
function TradeService.request(session: Session, targetUserId: number): (boolean, string?)
	local player = session.Player
	local targetPlayer = Players:GetPlayerByUserId(targetUserId)
	local target = if targetPlayer then SessionService.get(targetPlayer) else nil
	if not target or not targetPlayer then
		return false, "Spieler nicht gefunden"
	end
	if targetPlayer == player then
		return false, "Du kannst nicht mit dir selbst handeln"
	end
	if trades[player] then
		return false, "Du handelst bereits"
	end
	if trades[targetPlayer] then
		return false, targetPlayer.DisplayName .. " handelt gerade"
	end
	if session.Data.TradeTickets < 1 then
		return false, "Du brauchst ein 🎟️ Trading-Ticket (Shop)"
	end
	-- Hat der andere uns schon gefragt? Dann direkt starten.
	local mine = invites[player]
	if mine and mine[targetPlayer] and mine[targetPlayer] > Clock.now() then
		startTrade(target, session)
		return true, nil
	end
	invites[targetPlayer] = invites[targetPlayer] or {}
	local expiresAt = Clock.now() + Config.Trading.InviteTimeout
	invites[targetPlayer][player] = expiresAt
	Net.event("TradeInvite"):FireClient(targetPlayer, {
		FromUserId = player.UserId,
		FromName = player.DisplayName,
		ExpiresAt = expiresAt,
	})
	SessionService.notify(player, "📨 Handelsanfrage an " .. targetPlayer.DisplayName .. " gesendet", "info")
	return true, nil
end

function TradeService.respond(session: Session, fromUserId: number, accept: boolean): (boolean, string?)
	local player = session.Player
	local fromPlayer = Players:GetPlayerByUserId(fromUserId)
	local list = invites[player]
	local expiresAt = if list and fromPlayer then list[fromPlayer] else nil
	if not fromPlayer or not list or not expiresAt then
		return false, "Anfrage nicht mehr gültig"
	end
	list[fromPlayer] = nil
	if expiresAt < Clock.now() then
		return false, "Anfrage ist abgelaufen"
	end
	if not accept then
		SessionService.notify(fromPlayer, player.DisplayName .. " hat abgelehnt", "warn")
		return true, nil
	end
	local from = SessionService.get(fromPlayer)
	if not from then
		return false, "Spieler nicht gefunden"
	end
	if trades[player] or trades[fromPlayer] then
		return false, "Einer von euch handelt bereits"
	end
	if session.Data.TradeTickets < 1 then
		return false, "Du brauchst ein 🎟️ Trading-Ticket (Shop)"
	end
	startTrade(from, session)
	return true, nil
end

function TradeService.setOffer(session: Session, petList: string): (boolean, string?)
	local trade = trades[session.Player]
	if not trade or trade.Done then
		return false, "Kein Handel aktiv"
	end
	local me = sides(trade, session.Player)
	local offer: { string } = {}
	local seen: { [string]: boolean } = {}
	for uid in string.gmatch(petList, "[^,]+") do
		if #offer >= Config.Trading.MaxPetsPerSide then
			return false, string.format("Maximal %d Pets pro Seite", Config.Trading.MaxPetsPerSide)
		end
		if seen[uid] or not PetService.findPet(session.Data, uid) then
			return false, "Ungültiges Pet"
		end
		seen[uid] = true
		table.insert(offer, uid)
	end
	me.Offer = offer
	resetReady(trade)
	push(trade)
	return true, nil
end

function TradeService.setReady(session: Session, ready: boolean): (boolean, string?)
	local trade = trades[session.Player]
	if not trade or trade.Done then
		return false, "Kein Handel aktiv"
	end
	local me, other = sides(trade, session.Player)
	if ready and #me.Offer == 0 and #other.Offer == 0 then
		return false, "Legt zuerst Pets in den Handel"
	end
	me.Ready = ready
	trade.ConfirmAt = nil
	trade.Token += 1
	if trade.A.Ready and trade.B.Ready then
		local token = trade.Token
		trade.ConfirmAt = Clock.now() + Config.Trading.ConfirmCountdown
		task.delay(Config.Trading.ConfirmCountdown, function()
			if trade.Token == token and not trade.Done then
				execute(trade)
			end
		end)
	end
	push(trade)
	return true, nil
end

function TradeService.cancel(session: Session): (boolean, string?)
	local trade = trades[session.Player]
	if not trade then
		return false, "Kein Handel aktiv"
	end
	finish(trade, "❌ Handel abgebrochen von " .. session.Player.DisplayName, "warn")
	return true, nil
end

function TradeService.start()
	PetService.isLocked = function(session: Session, petUid: string): boolean
		local trade = trades[session.Player]
		if not trade or trade.Done then
			return false
		end
		local me = sides(trade, session.Player)
		return table.find(me.Offer, petUid) ~= nil
	end

	SessionService.onEnd(5, function(session)
		local player = session.Player
		local trade = trades[player]
		if trade then
			finish(trade, "Handel abgebrochen: " .. player.DisplayName .. " hat das Spiel verlassen", "warn")
		end
		invites[player] = nil
		for _, list in invites do
			list[player] = nil
		end
	end)

	NetService.register("TradeRequest", { Target = "integer" }, function(session, payload)
		return TradeService.request(session, payload.Target)
	end)
	NetService.register("TradeRespond", { From = "integer", Accept = "boolean" }, function(session, payload)
		return TradeService.respond(session, payload.From, payload.Accept)
	end)
	NetService.register("TradeOffer", { Pets = "string" }, function(session, payload)
		if #payload.Pets > 400 then
			return false, "Ungültiges Angebot"
		end
		return TradeService.setOffer(session, payload.Pets)
	end)
	NetService.register("TradeReady", { Ready = "boolean" }, function(session, payload)
		return TradeService.setReady(session, payload.Ready)
	end)
	NetService.register("TradeCancel", {}, function(session)
		return TradeService.cancel(session)
	end)
end

return TradeService

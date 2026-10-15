--!strict
--[[
	ShopService
	===========
	  * Gem-Items: Boosts (2x Geld, 2x Tempo, Schild) und Sofort-Einkommen
	  * Gamepasses: Besitz wird beim Beitreten geprüft und nach Kauf aktualisiert
	  * Developer Products: ProcessReceipt mit Idempotenz (PurchaseId wird
	    gespeichert, damit nie doppelt gutgeschrieben wird) und sofortigem Save
]]

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local BigNum = require(Shared.BigNum)
local Clock = require(Shared.Clock)
local Config = require(Shared.Config)
local Formulas = require(Shared.Formulas)

local DataService = require(script.Parent.DataService)
local NetService = require(script.Parent.NetService)
local PlotService = require(script.Parent.PlotService)
local SessionService = require(script.Parent.SessionService)

type Session = SessionService.Session

local ShopService = {}

--- Einkommen für x Sekunden (mindestens ein kleiner Grundbetrag)
local function incomeFor(session: Session, seconds: number, minimum: number): BigNum.BigNum
	local income = Formulas.incomePerSecond(session.Data, SessionService.context(session), false)
	return BigNum.max(BigNum.mulNum(income, seconds), BigNum.new(minimum))
end

local function addBoost(session: Session, boostId: string, duration: number)
	local now = Clock.now()
	local current = session.Data.Boosts[boostId] or 0
	local newUntil = math.max(now, current) + duration
	session.Data.Boosts[boostId] = math.min(newUntil, now + Config.Shop.MaxBoostSeconds)
	session.Dirty = true
end

function ShopService.buyGemItem(session: Session, itemId: string): (boolean, string?)
	local item: Config.GemItem? = nil
	for _, i in Config.Shop.GemItems do
		if i.Id == itemId then
			item = i
		end
	end
	if not item then
		return false, "Unbekannter Artikel"
	end
	if not SessionService.spendGems(session, item.Cost) then
		return false, "Nicht genug Gems"
	end
	if item.Boost and item.Duration then
		addBoost(session, item.Boost, item.Duration)
		SessionService.notify(session.Player, item.Icon .. " " .. item.Name .. " aktiviert!", "success")
		if item.Boost == "Shield" then
			PlotService.updateVisuals(session)
		end
	end
	if item.InstantIncomeSeconds then
		local cash = incomeFor(session, item.InstantIncomeSeconds, 100)
		SessionService.addCash(session, cash)
		SessionService.effect(session.Player, "Cash", { Amount = cash })
	end
	return true, nil
end

----------------------------------------------------------------------
-- Gamepasses
----------------------------------------------------------------------
local function checkPasses(session: Session)
	for _, pass in Config.Shop.Passes do
		if pass.GamePassId ~= 0 then
			local ok, owns = pcall(function()
				return MarketplaceService:UserOwnsGamePassAsync(session.Player.UserId, pass.GamePassId)
			end)
			if ok and owns then
				session.Passes[pass.Id] = true
			end
		end
	end
	session.Dirty = true
end

----------------------------------------------------------------------
-- Developer Products
----------------------------------------------------------------------
local function processReceipt(receipt: { [string]: any }): Enum.ProductPurchaseDecision
	local player = Players:GetPlayerByUserId(receipt.PlayerId)
	local session = if player then SessionService.get(player) else nil
	if not session then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local purchaseId = tostring(receipt.PurchaseId)
	local data = session.Data
	if table.find(data.ReceiptIds, purchaseId) then
		return Enum.ProductPurchaseDecision.PurchaseGranted -- schon gutgeschrieben
	end
	local product: Config.ProductDef? = nil
	for _, p in Config.Shop.Products do
		if p.ProductId ~= 0 and p.ProductId == receipt.ProductId then
			product = p
		end
	end
	if not product then
		warn("[ShopService] Unbekanntes Produkt:", receipt.ProductId)
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	if product.Gems then
		SessionService.addGems(session, product.Gems)
		SessionService.effect(session.Player, "Gems", { Amount = product.Gems })
	end
	if product.IncomeSeconds then
		local cash = incomeFor(session, product.IncomeSeconds, 1000)
		SessionService.addCash(session, cash)
		SessionService.effect(session.Player, "Cash", { Amount = cash })
	end
	table.insert(data.ReceiptIds, purchaseId)
	while #data.ReceiptIds > Config.Data.MaxReceiptHistory do
		table.remove(data.ReceiptIds, 1)
	end
	SessionService.notify(session.Player, "Danke für deinen Kauf! " .. product.Icon, "success")

	-- sofort speichern, damit der Kauf sicher ist
	if DataService.save(session.Profile, false) then
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end
	-- Speichern fehlgeschlagen: Roblox versucht es später erneut. Die PurchaseId
	-- ist bereits vermerkt, deshalb wird dann nicht doppelt gutgeschrieben.
	return Enum.ProductPurchaseDecision.NotProcessedYet
end

function ShopService.start()
	SessionService.onStart(25, checkPasses)

	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, passId, purchased)
		if not purchased then
			return
		end
		local session = SessionService.get(player)
		if not session then
			return
		end
		for _, pass in Config.Shop.Passes do
			if pass.GamePassId == passId then
				session.Passes[pass.Id] = true
				session.Dirty = true
				SessionService.notify(player, pass.Icon .. " " .. pass.Name .. " freigeschaltet!", "success")
			end
		end
	end)

	MarketplaceService.ProcessReceipt = processReceipt

	NetService.register("BuyGemItem", { ItemId = "string" }, function(session, payload)
		return ShopService.buyGemItem(session, payload.ItemId)
	end)
end

return ShopService

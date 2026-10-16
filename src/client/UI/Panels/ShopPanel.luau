--!strict
--[[
	ShopPanel
	=========
	  Boosts für Gems (zeitlich begrenzt, stapelbar)
	  Gems / Geld für Robux (Developer Products)
	  Pets & Handel (Eier, Pet-Slots für Geld, Trading-Tickets)
	  Waffen (Schläger, Slaps) und Stehl-Gadgets (ab X Rebirths)
	  Gamepasses (dauerhaft)
	Robux-Käufe werden vom Server in ProcessReceipt bestätigt.
]]

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local BigNum = require(Shared.BigNum)
local Clock = require(Shared.Clock)
local Config = require(Shared.Config)
local Formulas = require(Shared.Formulas)

local ClientState = require(script.Parent.Parent.Parent.ClientState)
local Remote = require(script.Parent.Parent.Parent.Remote)
local Components = require(script.Parent.Parent.Components)
local PanelManager = require(script.Parent.Parent.PanelManager)
local Theme = require(script.Parent.Parent.Theme)
local Util = require(script.Parent.Parent.Util)

local ShopPanel = {}

type Entry = { Button: Components.Button, Update: () -> () }

local entries: { Entry } = {}
local list: ScrollingFrame

local function section(text: string, order: number)
	local l = Util.label({
		Size = UDim2.new(1, 0, 0, 36),
		LayoutOrder = order,
		Text = text,
		Font = Theme.Fonts.Title,
		TextSize = 24,
		TextColor3 = Theme.Colors.Gold,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = list,
	})
	Util.textStroke(1).Parent = l
end

local function grid(order: number): Frame
	return Util.new("Frame", {
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		LayoutOrder = order,
		Parent = list,
	}, {
		Util.new("UIGridLayout", {
			CellSize = UDim2.fromOffset(372, 150),
			CellPadding = UDim2.fromOffset(12, 12),
			SortOrder = Enum.SortOrder.LayoutOrder,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
		}),
	})
end

local function itemCard(
	parent: Instance,
	icon: string,
	name: string,
	desc: string,
	accent: Color3,
	order: number
): Frame
	local card = Components.card({ LayoutOrder = order, Parent = parent }, accent)
	local iconFrame: Frame = Util.new("Frame", {
		Size = UDim2.fromOffset(72, 72),
		Position = UDim2.fromOffset(14, 14),
		BackgroundColor3 = Color3.new(1, 1, 1),
		Parent = card,
	}, {
		Util.round(),
		Util.gradient(Theme.lighten(accent, 0.25), Theme.darken(accent, 0.35)),
	})
	Util.label({ Size = UDim2.fromScale(1, 1), Text = icon, TextSize = 38, Parent = iconFrame })
	local title = Util.label({
		Size = UDim2.new(1, -110, 0, 30),
		Position = UDim2.fromOffset(98, 12),
		Text = name,
		Font = Theme.Fonts.Title,
		TextSize = 22,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = card,
	})
	Util.textStroke(1).Parent = title
	Util.label({
		Size = UDim2.new(1, -110, 0, 44),
		Position = UDim2.fromOffset(98, 42),
		Text = desc,
		TextSize = 15,
		TextWrapped = true,
		TextColor3 = Theme.Colors.SubText,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		Parent = card,
	})
	return card
end

local function buyButton(card: Frame, color: Color3, onClick: () -> ()): Components.Button
	return Components.button({
		Text = "",
		Color = color,
		Size = UDim2.new(1, -28, 0, 46),
		Position = UDim2.new(0.5, 0, 1, -12),
		AnchorPoint = Vector2.new(0.5, 1),
		TextSize = 19,
		Parent = card,
		Sound = "Purchase",
		OnClick = onClick,
	})
end

local function build()
	local order = 0
	local function nextOrder(): number
		order += 1
		return order
	end

	section("💎 Boosts", nextOrder())
	local boosts = grid(nextOrder())
	for i, item in Config.Shop.GemItems do
		local card = itemCard(boosts, item.Icon, item.Name, item.Description, Theme.Colors.Gem, i)
		local button = buyButton(card, Theme.Colors.Purple, function()
			Remote.send("BuyGemItem", { ItemId = item.Id })
		end)
		table.insert(entries, {
			Button = button,
			Update = function()
				local snap = ClientState.Snapshot
				if not snap then
					return
				end
				local now = Clock.now()
				local untilTime = if item.Boost then snap.Data.Boosts[item.Boost] else nil
				local suffix = if untilTime and untilTime > now
					then "  (" .. Formulas.formatDuration(untilTime - now) .. ")"
					else ""
				button.SetText(string.format("%d 💎%s", item.Cost, suffix))
				button.SetEnabled(snap.Data.Gems >= item.Cost)
			end,
		})
	end

	section("🐾 Pets & Handel", nextOrder())
	local pets = grid(nextOrder())
	local eggCard = itemCard(
		pets,
		"🥚",
		"Eier & Pets",
		"Pets boosten dein Einkommen! Schau dir die Chancen an.",
		Theme.Colors.Orange,
		1
	)
	buyButton(eggCard, Theme.Colors.Orange, function()
		PanelManager.open("Pets", "Eggs")
	end).SetText("Zu den Eiern")
	local slotCard = itemCard(
		pets,
		"➕",
		"Pet-Slot",
		string.format(
			"Ein Pet mehr ausrüsten (mit Geld bis %d Slots)",
			Config.Pets.BaseSlots + #Config.Pets.CashSlotCosts
		),
		Theme.Colors.Green,
		2
	)
	local slotButton = buyButton(slotCard, Theme.Colors.Green, function()
		Remote.send("BuyPetSlot")
	end)
	table.insert(entries, {
		Button = slotButton,
		Update = function()
			local snap = ClientState.Snapshot
			if not snap then
				return
			end
			local cost = Formulas.nextCashSlotCost(snap.Data)
			if cost then
				slotButton.SetText(BigNum.formatMoney(cost, Config.CurrencySymbol))
				slotButton.SetEnabled(BigNum.gte(snap.Data.Cash, cost))
			else
				slotButton.SetText("✅ Alle Geld-Slots")
				slotButton.SetEnabled(false)
			end
		end,
	})
	for i, count in { 1, 5 } do
		local card = itemCard(
			pets,
			"🎟️",
			if count == 1 then "Trading-Ticket" else "5 Trading-Tickets",
			"Damit kannst du Pets mit anderen Spielern tauschen",
			Theme.Colors.Gold,
			2 + i
		)
		local cost = BigNum.new(Config.Trading.TicketCost * count)
		local button = buyButton(card, Theme.Colors.Gold, function()
			Remote.send("BuyTradeTickets", { Count = count })
		end)
		table.insert(entries, {
			Button = button,
			Update = function()
				local snap = ClientState.Snapshot
				if not snap then
					return
				end
				button.SetText(
					string.format(
						"%s  (hast %d)",
						BigNum.formatMoney(cost, Config.CurrencySymbol),
						snap.Data.TradeTickets
					)
				)
				button.SetEnabled(
					BigNum.gte(snap.Data.Cash, cost) and snap.Data.TradeTickets + count <= Config.Trading.MaxTickets
				)
			end,
		})
	end

	section("⚔️ Waffen", nextOrder())
	local weapons = grid(nextOrder())
	for i, item in Config.Combat.Items do
		local accent = if item.Currency == "Gems" then Theme.Colors.Gem else Theme.Colors.Red
		local card = itemCard(weapons, item.Icon, item.Name, item.Description, accent, i)
		local button = buyButton(
			card,
			if item.Currency == "Gems" then Theme.Colors.Purple else Theme.Colors.Red,
			function()
				Remote.send("BuyCombatItem", { ItemId = item.Id })
			end
		)
		table.insert(entries, {
			Button = button,
			Update = function()
				local snap = ClientState.Snapshot
				if not snap then
					return
				end
				local data = snap.Data
				if item.Currency == nil then
					button.SetText("✅ Gratis im Inventar")
					button.SetEnabled(false)
				elseif data.Items[item.Id] then
					button.SetText("✅ Besitzt du")
					button.SetEnabled(false)
				elseif item.Currency == "Gems" then
					button.SetText(string.format("%d 💎", item.Cost))
					button.SetEnabled(data.Gems >= item.Cost)
				else
					local cost = BigNum.new(item.Cost)
					button.SetText(BigNum.formatMoney(cost, Config.CurrencySymbol))
					button.SetEnabled(BigNum.gte(data.Cash, cost))
				end
			end,
		})
	end

	section("🕵️ Stehl-Gadgets", nextOrder())
	local gadgets = grid(nextOrder())
	for i, gadget in Config.Gadgets do
		local card = itemCard(
			gadgets,
			gadget.Icon,
			gadget.Name,
			gadget.Description
				.. string.format("  (ab %d Rebirth%s)", gadget.Rebirths, if gadget.Rebirths == 1 then "" else "s"),
			Theme.Colors.Cyan,
			i
		)
		local cost = BigNum.new(gadget.Cost)
		local button = buyButton(card, Theme.Colors.Cyan, function()
			Remote.send("BuyCombatItem", { ItemId = gadget.Id })
		end)
		table.insert(entries, {
			Button = button,
			Update = function()
				local snap = ClientState.Snapshot
				if not snap then
					return
				end
				local data = snap.Data
				if data.Items[gadget.Id] then
					button.SetText("✅ Besitzt du")
					button.SetEnabled(false)
				elseif data.Rebirths < gadget.Rebirths then
					button.SetText(string.format("🔒 %d/%d Rebirths", data.Rebirths, gadget.Rebirths))
					button.SetEnabled(false)
				else
					button.SetText(BigNum.formatMoney(cost, Config.CurrencySymbol))
					button.SetEnabled(BigNum.gte(data.Cash, cost))
				end
			end,
		})
	end

	section("🛒 Gems & Geld", nextOrder())
	local products = grid(nextOrder())
	for i, product in Config.Shop.Products do
		local card = itemCard(products, product.Icon, product.Name, product.Description, Theme.Colors.Green, i)
		local button = buyButton(card, Theme.Colors.Green, function()
			if product.ProductId ~= 0 then
				MarketplaceService:PromptProductPurchase(Players.LocalPlayer, product.ProductId)
			end
		end)
		button.SetText(if product.ProductId ~= 0 then " Kaufen (Robux)" else "Bald verfügbar")
		button.SetEnabled(product.ProductId ~= 0)
		if product.PetSlots and product.ProductId ~= 0 then
			table.insert(entries, {
				Button = button,
				Update = function()
					local snap = ClientState.Snapshot
					local canBuy = snap ~= nil and Formulas.canBuyRobuxSlot(snap.Data)
					button.SetText(if canBuy then " Kaufen (Robux)" else "✅ Max. Slots")
					button.SetEnabled(canBuy)
				end,
			})
		end
	end

	section("🎟️ Gamepasses", nextOrder())
	local passes = grid(nextOrder())
	for i, pass in Config.Shop.Passes do
		local card = itemCard(passes, pass.Icon, pass.Name, pass.Description, Theme.Colors.Gold, i)
		local button = buyButton(card, Theme.Colors.Gold, function()
			if pass.GamePassId ~= 0 then
				MarketplaceService:PromptGamePassPurchase(Players.LocalPlayer, pass.GamePassId)
			end
		end)
		table.insert(entries, {
			Button = button,
			Update = function()
				local snap = ClientState.Snapshot
				local owned = snap ~= nil and snap.Passes[pass.Id] == true
				if owned then
					button.SetText("✅ Besitzt du")
					button.SetEnabled(false)
				elseif pass.GamePassId == 0 then
					button.SetText("Bald verfügbar")
					button.SetEnabled(false)
				else
					button.SetText("Kaufen (Robux)")
					button.SetEnabled(true)
				end
			end,
		})
	end
end

local function update()
	for _, e in entries do
		e.Update()
	end
end

function ShopPanel.start()
	local window = Components.window("Shop", "🛒", Theme.Colors.Pink, Vector2.new(820, 580), function()
		PanelManager.close()
	end)
	list = Components.scrollList({ Parent = window.Content }, 10)
	build()
	PanelManager.register("Shop", window, update)
	ClientState.Changed:Connect(function()
		if PanelManager.isOpen("Shop") then
			update()
		end
	end)
	task.spawn(function()
		while true do
			task.wait(1)
			if PanelManager.isOpen("Shop") then
				update()
			end
		end
	end)
end

return ShopPanel

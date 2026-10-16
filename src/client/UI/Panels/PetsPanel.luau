--!strict
--[[
	PetsPanel
	=========
	  🥚 Eier     - alle Eier mit Preis und den Chancen jedes Pets, 1x / 3x öffnen
	  🐾 Pets     - Inventar: ausrüsten, "Beste ausrüsten", Slots kaufen, freilassen
	  🤝 Handeln  - Trading-Tickets kaufen, Spieler zum Handeln einladen
	Alles wird vom Server entschieden, das Menü zeigt nur an und fragt an.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local BigNum = require(Shared.BigNum)
local Config = require(Shared.Config)
local Formulas = require(Shared.Formulas)
local Types = require(Shared.Types)

local ClientState = require(script.Parent.Parent.Parent.ClientState)
local Remote = require(script.Parent.Parent.Parent.Remote)
local Components = require(script.Parent.Parent.Components)
local PanelManager = require(script.Parent.Parent.PanelManager)
local PetVisuals = require(script.Parent.Parent.PetVisuals)
local Popups = require(script.Parent.Parent.Popups)
local Theme = require(script.Parent.Parent.Theme)
local Util = require(script.Parent.Parent.Util)

local PetsPanel = {}

local TABS = {
	{ Id = "Eggs", Text = "🥚 Eier", Color = Theme.Colors.Orange },
	{ Id = "Pets", Text = "🐾 Meine Pets", Color = Theme.Colors.Green },
	{ Id = "Trade", Text = "🤝 Handeln", Color = Theme.Colors.Cyan },
}

local localPlayer = Players.LocalPlayer
local tabButtons: { [string]: Components.Button } = {}
local tabFrames: { [string]: GuiObject } = {}
local currentTab = "Eggs"

type EggEntry = { Price: TextLabel, One: Components.Button, Three: Components.Button, Egg: Config.EggDef }
local eggEntries: { EggEntry } = {}

-- Pets-Tab
local statsLabel: TextLabel
local bestButton: Components.Button
local slotButton: Components.Button
local releaseButton: Components.Button
local petGrid: ScrollingFrame
local petSignature = ""

-- Handel-Tab
local ticketLabel: TextLabel
local ticketButtons: { { Button: Components.Button, Count: number } } = {}
local playerList: ScrollingFrame

local function snapshot(): Types.Snapshot?
	return ClientState.Snapshot
end

local function money(n: BigNum.BigNum): string
	return BigNum.formatMoney(n, Config.CurrencySymbol)
end

----------------------------------------------------------------------
-- 🥚 Eier
----------------------------------------------------------------------
local function chanceCell(parent: Instance, chance: Config.EggChance, order: number)
	local def = Formulas.petDef(chance.Pet)
	if not def then
		return
	end
	local rarity = Formulas.petRarity(def.Rarity)
	local tile = PetVisuals.petTile({ LayoutOrder = order, Parent = parent }, def.Id, 34)
	local mult = Util.label({
		Size = UDim2.new(1, 0, 0, 18),
		Position = UDim2.fromOffset(0, 44),
		Text = Formulas.formatPetMultiplier(def.Multiplier),
		TextSize = 15,
		Parent = tile,
	})
	Util.textStroke(1.5).Parent = mult
	local pct = Util.label({
		Size = UDim2.new(1, 0, 0, 20),
		Position = UDim2.fromOffset(0, 62),
		Text = Formulas.formatChance(chance.Chance),
		Font = Theme.Fonts.Number,
		TextSize = if chance.Chance < 0.1 then 14 else 17,
		TextColor3 = Theme.lighten(rarity.Color, 0.55),
		Parent = tile,
	})
	Util.textStroke(1.8).Parent = pct
end

local function buildEggs(parent: Frame)
	local list = Components.scrollList({ Parent = parent }, 10)
	local intro = Util.label({
		Size = UDim2.new(1, 0, 0, 30),
		LayoutOrder = 0,
		Text = "Pets boosten dein Einkommen! Ausgerüstete Pets addieren sich (zwei x2 = x3).",
		TextSize = 17,
		TextColor3 = Theme.Colors.SubText,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = list,
	})
	Util.textStroke(1).Parent = intro
	for i, egg in Config.Eggs do
		local card = Components.card({ Size = UDim2.new(1, 0, 0, 200), LayoutOrder = i, Parent = list }, egg.Color)
		PetVisuals.egg({
			Position = UDim2.fromOffset(88, 10),
			AnchorPoint = Vector2.new(0.5, 0),
			Parent = card,
		}, egg.Color, 82)
		local name = Util.label({
			Size = UDim2.fromOffset(170, 26),
			Position = UDim2.fromOffset(4, 94),
			Text = egg.Name,
			Font = Theme.Fonts.Title,
			TextSize = 22,
			Parent = card,
		})
		Util.textStroke(1.5).Parent = name
		local price = Util.label({
			Size = UDim2.fromOffset(170, 22),
			Position = UDim2.fromOffset(4, 120),
			Text = "",
			Font = Theme.Fonts.Number,
			TextSize = 18,
			TextColor3 = if egg.Currency == "Gems" then Theme.Colors.Gem else Theme.Colors.Money,
			Parent = card,
		})
		Util.textStroke(1.5).Parent = price
		local function open(count: number)
			if Popups.isHatching() then
				return
			end
			Remote.send("OpenEgg", { EggId = egg.Id, Count = count })
		end
		local one = Components.button({
			Text = "Öffnen",
			Color = Theme.Colors.Green,
			Size = UDim2.fromOffset(82, 46),
			Position = UDim2.fromOffset(10, 146),
			TextSize = 17,
			Parent = card,
			Sound = "Purchase",
			OnClick = function()
				open(1)
			end,
		})
		local three = Components.button({
			Text = "3x",
			Color = Theme.Colors.Orange,
			Size = UDim2.fromOffset(72, 46),
			Position = UDim2.fromOffset(98, 146),
			TextSize = 19,
			Parent = card,
			Sound = "Purchase",
			Shine = true,
			OnClick = function()
				open(3)
			end,
		})
		local chances: Frame = Util.new("Frame", {
			Size = UDim2.new(1, -190, 1, -20),
			Position = UDim2.fromOffset(182, 10),
			BackgroundTransparency = 1,
			Parent = card,
		}, {
			Util.new("UIGridLayout", {
				CellSize = UDim2.fromOffset(74, 86),
				CellPadding = UDim2.fromOffset(6, 6),
				SortOrder = Enum.SortOrder.LayoutOrder,
				VerticalAlignment = Enum.VerticalAlignment.Center,
			}),
		})
		for n, chance in egg.Chances do
			chanceCell(chances, chance, n)
		end
		table.insert(eggEntries, { Price = price, One = one, Three = three, Egg = egg })
	end
end

local function updateEggs()
	local snap = snapshot()
	if not snap then
		return
	end
	local data = snap.Data
	local free = Config.Pets.MaxOwned - #data.Pets
	for _, e in eggEntries do
		local cost = Formulas.eggCost(data, e.Egg)
		local canOne, canThree
		if e.Egg.Currency == "Gems" then
			local gems = BigNum.toNumber(cost)
			e.Price.Text = string.format("%d 💎", gems)
			canOne = data.Gems >= gems
			canThree = data.Gems >= gems * 3
		else
			e.Price.Text = money(cost)
			canOne = BigNum.gte(data.Cash, cost)
			canThree = BigNum.gte(data.Cash, BigNum.mulNum(cost, 3))
		end
		e.One.SetEnabled(canOne and free >= 1)
		e.Three.SetEnabled(canThree and free >= 3)
	end
end

----------------------------------------------------------------------
-- 🐾 Meine Pets
----------------------------------------------------------------------
local function petCell(pet: Types.PetData, order: number)
	local def = Formulas.petDef(pet.Pet)
	if not def then
		return
	end
	local tile = PetVisuals.petTile({ LayoutOrder = order, Parent = petGrid }, def.Id, 50)
	if pet.Equipped then
		local stroke = tile:FindFirstChildOfClass("UIStroke")
		if stroke then
			stroke.Color = Theme.Colors.Selected
			stroke.Thickness = 4
		end
		local badge: Frame = Util.new("Frame", {
			Size = UDim2.fromOffset(32, 32),
			Position = UDim2.fromOffset(6, 6),
			BackgroundColor3 = Theme.Colors.Green,
			ZIndex = 3,
			Parent = tile,
		}, { Util.round(), Util.stroke(Color3.new(1, 1, 1), 2) })
		Util.label({ Size = UDim2.fromScale(1, 1), Text = "✓", TextSize = 20, ZIndex = 4, Parent = badge })
	end
	local name = Util.label({
		Size = UDim2.new(1, -8, 0, 22),
		Position = UDim2.fromOffset(4, 64),
		Text = def.Name,
		Font = Theme.Fonts.Title,
		TextSize = 17,
		TextScaled = false,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Parent = tile,
	})
	Util.textStroke(1.5).Parent = name
	local mult = Util.label({
		Size = UDim2.new(1, 0, 0, 22),
		Position = UDim2.fromOffset(0, 86),
		Text = "💰 " .. Formulas.formatPetMultiplier(def.Multiplier),
		Font = Theme.Fonts.Number,
		TextSize = 17,
		TextColor3 = Theme.Colors.Money,
		Parent = tile,
	})
	Util.textStroke(1.5).Parent = mult
	Components.button({
		Text = if pet.Equipped then "Ablegen" else "Ausrüsten",
		Color = if pet.Equipped then Theme.Colors.Orange else Theme.Colors.Green,
		Size = UDim2.new(1, -14, 0, 42),
		Position = UDim2.new(0.5, 0, 1, -8),
		AnchorPoint = Vector2.new(0.5, 1),
		TextSize = 17,
		Parent = tile,
		OnClick = function()
			Remote.send("EquipPet", { PetId = pet.Id, On = not pet.Equipped })
		end,
	})
	Components.button({
		Text = "🗑",
		Color = Theme.Colors.Red,
		Size = UDim2.fromOffset(34, 34),
		Position = UDim2.new(1, -6, 0, 6),
		AnchorPoint = Vector2.new(1, 0),
		TextSize = 16,
		ZIndex = 3,
		Parent = tile,
		OnClick = function()
			Popups.confirm(
				string.format("%s %s freilassen?\nDas kann nicht rückgängig gemacht werden.", def.Icon, def.Name),
				function()
					Remote.send("ReleasePet", { PetId = pet.Id })
				end,
				"Freilassen"
			)
		end,
	})
end

local function rebuildPets(data: Types.PlayerData)
	local parts = {}
	for _, pet in data.Pets do
		table.insert(parts, pet.Id .. (if pet.Equipped then "+" else "-"))
	end
	local sig = table.concat(parts, ",")
	if sig == petSignature then
		return
	end
	petSignature = sig
	for _, child in petGrid:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	-- ausgerüstete zuerst, dann nach Stärke
	local sorted = Formulas.sortPetsByPower(data.Pets)
	local order = 0
	for _, equippedFirst in { true, false } do
		for _, pet in sorted do
			if pet.Equipped == equippedFirst then
				order += 1
				petCell(pet, order)
			end
		end
	end
	if #data.Pets == 0 then
		Util.label({
			Size = UDim2.fromOffset(600, 60),
			Text = "Noch keine Pets - öffne ein Ei! 🥚",
			Font = Theme.Fonts.Title,
			TextSize = 24,
			Parent = petGrid,
		})
	end
end

local function buildPets(parent: Frame)
	statsLabel = Util.label({
		Size = UDim2.new(1, 0, 0, 34),
		Text = "",
		Font = Theme.Fonts.Title,
		TextSize = 22,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = parent,
	})
	Util.textStroke(1.5).Parent = statsLabel
	local row: Frame = Util.new("Frame", {
		Size = UDim2.new(1, 0, 0, 56),
		Position = UDim2.fromOffset(0, 38),
		BackgroundTransparency = 1,
		Parent = parent,
	}, { Util.list(Enum.FillDirection.Horizontal, 10, Enum.HorizontalAlignment.Left) })
	bestButton = Components.button({
		Text = "⭐ Beste ausrüsten",
		Color = Theme.Colors.Gold,
		Size = UDim2.fromOffset(250, 54),
		TextSize = 19,
		LayoutOrder = 1,
		Parent = row,
		Shine = true,
		OnClick = function()
			Remote.send("EquipBestPets")
		end,
	})
	slotButton = Components.button({
		Text = "",
		Color = Theme.Colors.Green,
		Size = UDim2.fromOffset(280, 54),
		TextSize = 18,
		LayoutOrder = 2,
		Parent = row,
		Sound = "Purchase",
		OnClick = function()
			local snap = snapshot()
			if snap and Formulas.nextCashSlotCost(snap.Data) then
				Remote.send("BuyPetSlot")
			else
				PanelManager.open("Shop")
			end
		end,
	})
	releaseButton = Components.button({
		Text = "🗑 Schwache freilassen",
		Color = Theme.Colors.Red,
		Size = UDim2.fromOffset(270, 54),
		TextSize = 18,
		LayoutOrder = 3,
		Parent = row,
		OnClick = function()
			Popups.confirm("Alle NICHT ausgerüsteten gewöhnlichen und ungewöhnlichen Pets freilassen?", function()
				Remote.send("ReleaseWeakPets", { Rarity = "Uncommon" })
			end, "Freilassen")
		end,
	})
	petGrid = Components.scrollList({
		Size = UDim2.new(1, 0, 1, -104),
		Position = UDim2.fromOffset(0, 104),
		Parent = parent,
	}, 10)
	local layout = petGrid:FindFirstChildOfClass("UIListLayout")
	if layout then
		layout:Destroy()
	end
	Util.new("UIGridLayout", {
		CellSize = UDim2.fromOffset(156, 168),
		CellPadding = UDim2.fromOffset(10, 10),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = petGrid,
	})
end

local function updatePets()
	local snap = snapshot()
	if not snap then
		return
	end
	local data = snap.Data
	local slots = Formulas.petSlots(data)
	statsLabel.Text = string.format(
		"💰 Pet-Boost: %s     🐾 Ausgerüstet: %d/%d     🎒 %d/%d",
		Formulas.formatPetMultiplier(Formulas.petMultiplier(data)),
		Formulas.equippedCount(data),
		slots,
		#data.Pets,
		Config.Pets.MaxOwned
	)
	bestButton.SetEnabled(#data.Pets > 0)
	local cashCost = Formulas.nextCashSlotCost(data)
	if cashCost then
		slotButton.SetText("➕ Slot  " .. money(cashCost))
		slotButton.SetColor(Theme.Colors.Green)
		slotButton.SetEnabled(BigNum.gte(data.Cash, cashCost))
	elseif Formulas.canBuyRobuxSlot(data) then
		slotButton.SetText("➕ Mehr Slots (Robux)")
		slotButton.SetColor(Theme.Colors.Purple)
		slotButton.SetEnabled(true)
	else
		slotButton.SetText(string.format("✓ Max. %d Slots", Config.Pets.MaxSlots))
		slotButton.SetEnabled(false)
	end
	releaseButton.SetEnabled(#data.Pets > 0)
	rebuildPets(data)
end

----------------------------------------------------------------------
-- 🤝 Handeln
----------------------------------------------------------------------
local function rebuildPlayers()
	for _, child in playerList:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	local others = 0
	for _, player in Players:GetPlayers() do
		if player ~= localPlayer then
			others += 1
			local card = Components.card({ Size = UDim2.new(1, 0, 0, 80), LayoutOrder = others, Parent = playerList })
			Util.new("ImageLabel", {
				Size = UDim2.fromOffset(62, 62),
				Position = UDim2.fromOffset(10, 9),
				BackgroundColor3 = Theme.Colors.Track,
				Image = string.format("rbxthumb://type=AvatarHeadShot&id=%d&w=150&h=150", player.UserId),
				Parent = card,
			}, { Util.round(), Util.stroke(Color3.new(1, 1, 1), 2) })
			local name = Util.label({
				Size = UDim2.new(1, -330, 1, 0),
				Position = UDim2.fromOffset(86, 0),
				Text = player.DisplayName .. '  <font size="15">@' .. player.Name .. "</font>",
				RichText = true,
				Font = Theme.Fonts.Title,
				TextSize = 22,
				TextXAlignment = Enum.TextXAlignment.Left,
				Parent = card,
			})
			Util.textStroke(1.5).Parent = name
			Components.button({
				Text = "🤝 Handeln",
				Color = Theme.Colors.Cyan,
				Size = UDim2.fromOffset(200, 56),
				Position = UDim2.new(1, -12, 0.5, 0),
				AnchorPoint = Vector2.new(1, 0.5),
				TextSize = 20,
				Parent = card,
				OnClick = function()
					Remote.send("TradeRequest", { Target = player.UserId })
				end,
			})
		end
	end
	if others == 0 then
		Util.label({
			Size = UDim2.new(1, 0, 0, 60),
			Text = "Gerade ist niemand sonst auf dem Server 😢",
			Font = Theme.Fonts.Title,
			TextSize = 22,
			Parent = playerList,
		})
	end
end

local function buildTrade(parent: Frame)
	ticketLabel = Util.label({
		Size = UDim2.new(1, 0, 0, 34),
		Text = "",
		Font = Theme.Fonts.Title,
		TextSize = 24,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = parent,
	})
	Util.textStroke(1.5).Parent = ticketLabel
	local row: Frame = Util.new("Frame", {
		Size = UDim2.new(1, 0, 0, 56),
		Position = UDim2.fromOffset(0, 38),
		BackgroundTransparency = 1,
		Parent = parent,
	}, { Util.list(Enum.FillDirection.Horizontal, 10, Enum.HorizontalAlignment.Left) })
	for i, count in { 1, 5 } do
		local b = Components.button({
			Text = "",
			Color = Theme.Colors.Gold,
			Size = UDim2.fromOffset(270, 54),
			TextSize = 18,
			LayoutOrder = i,
			Parent = row,
			Sound = "Purchase",
			OnClick = function()
				Remote.send("BuyTradeTickets", { Count = count })
			end,
		})
		table.insert(ticketButtons, { Button = b, Count = count })
	end
	local hint = Util.label({
		Size = UDim2.new(1, 0, 0, 26),
		Position = UDim2.fromOffset(0, 100),
		Text = "Nur Pets gegen Pets - kein Geld. Jeder Handel kostet beide 1 🎟️ Ticket.",
		TextSize = 16,
		TextColor3 = Theme.Colors.SubText,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = parent,
	})
	Util.textStroke(1).Parent = hint
	playerList = Components.scrollList({
		Size = UDim2.new(1, 0, 1, -134),
		Position = UDim2.fromOffset(0, 134),
		Parent = parent,
	}, 8)
end

local function updateTrade()
	local snap = snapshot()
	if not snap then
		return
	end
	local data = snap.Data
	ticketLabel.Text = string.format("🎟️ Deine Trading-Tickets: %d", data.TradeTickets)
	for _, t in ticketButtons do
		local cost = BigNum.new(Config.Trading.TicketCost * t.Count)
		t.Button.SetText(
			string.format("🎟️ %d Ticket%s  %s", t.Count, if t.Count > 1 then "s" else "", money(cost))
		)
		t.Button.SetEnabled(BigNum.gte(data.Cash, cost) and data.TradeTickets + t.Count <= Config.Trading.MaxTickets)
	end
end

----------------------------------------------------------------------
local function update()
	if currentTab == "Eggs" then
		updateEggs()
	elseif currentTab == "Pets" then
		updatePets()
	else
		updateTrade()
	end
end

local function selectTab(id: string)
	currentTab = id
	for tabId, b in tabButtons do
		b.SetColor(if tabId == id then Theme.Colors.Selected else Theme.Colors.CardLight)
		tabFrames[tabId].Visible = tabId == id
	end
	if id == "Trade" then
		rebuildPlayers()
	end
	update()
end

function PetsPanel.start()
	local window = Components.window("Pets & Eier", "🐾", Theme.Colors.Green, Vector2.new(900, 600), function()
		PanelManager.close()
	end)
	local tabBar: Frame = Util.new("Frame", {
		Size = UDim2.new(1, 0, 0, 58),
		BackgroundTransparency = 1,
		Parent = window.Content,
	}, { Util.list(Enum.FillDirection.Horizontal, 8, Enum.HorizontalAlignment.Left) })
	for i, tab in TABS do
		tabButtons[tab.Id] = Components.button({
			Text = tab.Text,
			Color = Theme.Colors.CardLight,
			Size = UDim2.fromOffset(220, 54),
			TextSize = 20,
			LayoutOrder = i,
			Parent = tabBar,
			OnClick = function()
				selectTab(tab.Id)
			end,
		})
		local frame: Frame = Util.new("Frame", {
			Name = tab.Id,
			Size = UDim2.new(1, 0, 1, -66),
			Position = UDim2.fromOffset(0, 66),
			BackgroundTransparency = 1,
			Visible = false,
			Parent = window.Content,
		})
		tabFrames[tab.Id] = frame
	end
	buildEggs(tabFrames.Eggs :: Frame)
	buildPets(tabFrames.Pets :: Frame)
	buildTrade(tabFrames.Trade :: Frame)

	PanelManager.register("Pets", window, function(arg: any)
		selectTab(if type(arg) == "string" and tabFrames[arg] then arg else currentTab)
	end)
	ClientState.Changed:Connect(function()
		if PanelManager.isOpen("Pets") then
			update()
		end
	end)
	local function onPlayersChanged()
		if PanelManager.isOpen("Pets") and currentTab == "Trade" then
			rebuildPlayers()
		end
	end
	Players.PlayerAdded:Connect(onPlayersChanged)
	Players.PlayerRemoving:Connect(function()
		task.defer(onPlayersChanged)
	end)
end

return PetsPanel

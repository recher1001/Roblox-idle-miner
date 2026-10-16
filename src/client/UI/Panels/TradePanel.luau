--!strict
--[[
	TradePanel
	==========
	Fenster für einen laufenden Pet-Handel. Öffnet sich automatisch, sobald
	der Server einen Handel startet, und schließt sich, wenn er endet.

	  oben    - dein Angebot | Angebot des Partners (+ Bereit-Status)
	  Mitte   - Status / Countdown, Bereit- und Abbrechen-Knopf
	  unten   - deine Pets: antippen = ins Angebot legen / herausnehmen
	Schließen des Fensters bricht den Handel ab.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Clock = require(Shared.Clock)
local Config = require(Shared.Config)
local Formulas = require(Shared.Formulas)
local Net = require(Shared.Net)
local Types = require(Shared.Types)

local ClientState = require(script.Parent.Parent.Parent.ClientState)
local Remote = require(script.Parent.Parent.Parent.Remote)
local Sounds = require(script.Parent.Parent.Parent.Controllers.Sounds)
local Components = require(script.Parent.Parent.Components)
local PanelManager = require(script.Parent.Parent.PanelManager)
local PetVisuals = require(script.Parent.Parent.PetVisuals)
local Theme = require(script.Parent.Parent.Theme)
local Util = require(script.Parent.Parent.Util)

local TradePanel = {}

local window: Components.Window
local view: Types.TradeView? = nil

type OfferSide = { Card: Frame, Title: TextLabel, Grid: Frame, Value: TextLabel, Ready: TextLabel }
local mySide: OfferSide
local theirSide: OfferSide
local statusLabel: TextLabel
local readyButton: Components.Button
local inventory: ScrollingFrame
local inventorySignature = ""

local function offerValue(offer: { Types.PetData }): number
	local bonus = 0
	for _, pet in offer do
		local def = Formulas.petDef(pet.Pet)
		if def then
			bonus += def.Multiplier - 1
		end
	end
	return bonus
end

local function miniTile(parent: Instance, petId: string, order: number, selected: boolean): Frame
	local def = Formulas.petDef(petId)
	local tile = PetVisuals.petTile({ LayoutOrder = order, Parent = parent }, petId, 32)
	local mult = Util.label({
		Size = UDim2.new(1, 0, 0, 18),
		Position = UDim2.new(0, 0, 1, -22),
		Text = if def then Formulas.formatPetMultiplier(def.Multiplier) else "",
		Font = Theme.Fonts.Number,
		TextSize = 14,
		Parent = tile,
	})
	Util.textStroke(1.5).Parent = mult
	if selected then
		local stroke = tile:FindFirstChildOfClass("UIStroke")
		if stroke then
			stroke.Color = Theme.Colors.Selected
			stroke.Thickness = 4
		end
		local badge: Frame = Util.new("Frame", {
			Size = UDim2.fromOffset(24, 24),
			Position = UDim2.new(1, -4, 0, 4),
			AnchorPoint = Vector2.new(1, 0),
			BackgroundColor3 = Theme.Colors.Green,
			ZIndex = 3,
			Parent = tile,
		}, { Util.round() })
		Util.label({ Size = UDim2.fromScale(1, 1), Text = "✔️", TextSize = 15, ZIndex = 4, Parent = badge })
	end
	return tile
end

local function buildSide(x: number, titleText: string, accent: Color3): OfferSide
	local card = Components.card({
		Size = UDim2.new(0.5, -6, 0, 220),
		Position = UDim2.new(x, if x > 0 then 6 else 0, 0, 0),
		Parent = window.Content,
	}, accent)
	local title = Util.label({
		Size = UDim2.new(1, -20, 0, 32),
		Position = UDim2.fromOffset(12, 6),
		Text = titleText,
		Font = Theme.Fonts.Title,
		TextSize = 22,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = card,
	})
	Util.textStroke(1.5).Parent = title
	local grid: Frame = Util.new("Frame", {
		Size = UDim2.new(1, -20, 0, 140),
		Position = UDim2.fromOffset(10, 40),
		BackgroundTransparency = 1,
		Parent = card,
	}, {
		Util.new("UIGridLayout", {
			CellSize = UDim2.fromOffset(98, 66),
			CellPadding = UDim2.fromOffset(6, 6),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	})
	local value = Util.label({
		Size = UDim2.new(0.6, 0, 0, 28),
		Position = UDim2.new(0, 12, 1, -34),
		Text = "",
		TextSize = 17,
		TextColor3 = Theme.Colors.Money,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = card,
	})
	Util.textStroke(1.2).Parent = value
	local ready = Util.label({
		Size = UDim2.new(0.4, -12, 0, 28),
		Position = UDim2.new(1, -12, 1, -34),
		AnchorPoint = Vector2.new(1, 0),
		Text = "",
		Font = Theme.Fonts.Title,
		TextSize = 19,
		TextXAlignment = Enum.TextXAlignment.Right,
		Parent = card,
	})
	Util.textStroke(1.5).Parent = ready
	return { Card = card, Title = title, Grid = grid, Value = value, Ready = ready }
end

local function renderSide(side: OfferSide, offer: { Types.PetData }, isReady: boolean)
	for _, child in side.Grid:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	for i, pet in offer do
		miniTile(side.Grid, pet.Pet, i, false)
	end
	if #offer == 0 then
		Util.label({ Size = UDim2.fromOffset(300, 66), Text = "(leer)", TextSize = 18, Parent = side.Grid })
	end
	side.Value.Text = string.format("💰 +%s Boost", Formulas.formatPetMultiplier(offerValue(offer)))
	side.Ready.Text = if isReady then "✅ Bereit" else "⏳ Wählt..."
	side.Ready.TextColor3 = if isReady then Theme.Colors.Green else Theme.Colors.SubText
end

local function myOfferIds(): { string }
	local ids = {}
	if view then
		for _, pet in view.MyOffer do
			table.insert(ids, pet.Id)
		end
	end
	return ids
end

local function toggleOffer(petUid: string)
	if not view then
		return
	end
	local ids = myOfferIds()
	local index = table.find(ids, petUid)
	if index then
		table.remove(ids, index)
	elseif #ids < Config.Trading.MaxPetsPerSide then
		table.insert(ids, petUid)
	else
		return
	end
	Remote.send("TradeOffer", { Pets = table.concat(ids, ",") })
end

local function renderInventory()
	local snap = ClientState.Snapshot
	if not snap or not view then
		return
	end
	local offered = myOfferIds()
	local parts = { table.concat(offered, ",") }
	for _, pet in snap.Data.Pets do
		table.insert(parts, pet.Id)
	end
	local sig = table.concat(parts, ";")
	if sig == inventorySignature then
		return
	end
	inventorySignature = sig
	for _, child in inventory:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	for i, pet in Formulas.sortPetsByPower(snap.Data.Pets) do
		local tile = miniTile(inventory, pet.Pet, i, table.find(offered, pet.Id) ~= nil)
		local hit: TextButton = Util.new("TextButton", {
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			Text = "",
			ZIndex = 5,
			Parent = tile,
		})
		hit.Activated:Connect(function()
			Sounds.play("Click")
			toggleOffer(pet.Id)
		end)
	end
end

local function render()
	local v = view
	if not v then
		return
	end
	theirSide.Title.Text = "🎁 Angebot von " .. v.PartnerName
	renderSide(mySide, v.MyOffer, v.MyReady)
	renderSide(theirSide, v.TheirOffer, v.TheirReady)
	readyButton.SetText(if v.MyReady then "↩️ Nicht bereit" else "✅ Bereit")
	readyButton.SetColor(if v.MyReady then Theme.Colors.Orange else Theme.Colors.Green)
	renderInventory()
end

local function updateStatus()
	local v = view
	if not v then
		return
	end
	local snap = ClientState.Snapshot
	local tickets = if snap then snap.Data.TradeTickets else 0
	if v.ConfirmAt then
		statusLabel.Text = string.format("⏳ Handel in %ds ...", math.max(0, math.ceil(v.ConfirmAt - Clock.now())))
		statusLabel.TextColor3 = Theme.Colors.Gold
	elseif v.MyReady then
		statusLabel.Text = "Warte auf " .. v.PartnerName .. " ..."
		statusLabel.TextColor3 = Theme.Colors.SubText
	else
		statusLabel.Text = string.format("Tippe deine Pets an  •  🎟️ %d Tickets", tickets)
		statusLabel.TextColor3 = Theme.Colors.Text
	end
end

function TradePanel.start()
	window = Components.window("Handel", "🤝", Theme.Colors.Cyan, Vector2.new(940, 600), function()
		PanelManager.close()
	end)
	mySide = buildSide(0, "📦 Dein Angebot", Theme.Colors.Green)
	theirSide = buildSide(0.5, "🎁 Angebot", Theme.Colors.Cyan)

	statusLabel = Util.label({
		Size = UDim2.new(1, -440, 0, 56),
		Position = UDim2.fromOffset(4, 228),
		Text = "",
		Font = Theme.Fonts.Title,
		TextSize = 21,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = window.Content,
	})
	Util.textStroke(1.5).Parent = statusLabel
	readyButton = Components.button({
		Text = "✅ Bereit",
		Color = Theme.Colors.Green,
		Size = UDim2.fromOffset(220, 56),
		Position = UDim2.new(1, -194, 0, 228),
		AnchorPoint = Vector2.new(1, 0),
		TextSize = 20,
		Parent = window.Content,
		Shine = true,
		OnClick = function()
			local v = view
			if v then
				Remote.send("TradeReady", { Ready = not v.MyReady })
			end
		end,
	})
	Components.button({
		Text = "❌ Abbrechen",
		Color = Theme.Colors.Red,
		Size = UDim2.fromOffset(180, 56),
		Position = UDim2.new(1, 0, 0, 228),
		AnchorPoint = Vector2.new(1, 0),
		TextSize = 19,
		Parent = window.Content,
		OnClick = function()
			PanelManager.close()
		end,
	})
	local invTitle = Util.label({
		Size = UDim2.new(1, 0, 0, 26),
		Position = UDim2.fromOffset(4, 290),
		Text = string.format("Deine Pets (max. %d pro Handel):", Config.Trading.MaxPetsPerSide),
		TextSize = 17,
		TextColor3 = Theme.Colors.SubText,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = window.Content,
	})
	Util.textStroke(1).Parent = invTitle
	inventory = Components.scrollList({
		Size = UDim2.new(1, 0, 1, -320),
		Position = UDim2.fromOffset(0, 320),
		Parent = window.Content,
	}, 6)
	local layout = inventory:FindFirstChildOfClass("UIListLayout")
	if layout then
		layout:Destroy()
	end
	Util.new("UIGridLayout", {
		CellSize = UDim2.fromOffset(98, 66),
		CellPadding = UDim2.fromOffset(6, 6),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = inventory,
	})

	PanelManager.register("Trade", window, function()
		inventorySignature = ""
		render()
		updateStatus()
	end, function()
		-- Fenster zu = Handel abbrechen (falls noch aktiv)
		if view then
			view = nil
			Remote.send("TradeCancel")
		end
	end)

	Net.event("Trade").OnClientEvent:Connect(function(newView: Types.TradeView?)
		view = newView
		if not newView then
			if PanelManager.isOpen("Trade") then
				PanelManager.close()
			end
			return
		end
		if not PanelManager.isOpen("Trade") then
			PanelManager.open("Trade")
		else
			render()
			updateStatus()
		end
	end)
	ClientState.Changed:Connect(function()
		if view and PanelManager.isOpen("Trade") then
			renderInventory()
		end
	end)
	task.spawn(function()
		while true do
			task.wait(0.2)
			if view and PanelManager.isOpen("Trade") then
				updateStatus()
			end
		end
	end)
end

return TradePanel

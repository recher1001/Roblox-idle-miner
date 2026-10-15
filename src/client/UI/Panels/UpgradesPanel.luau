--!strict
--[[
	UpgradesPanel
	=============
	Zweispaltig und übersichtlich:
	  Links:  Liste aller Stationen (Händler, Aufzug, Ebenen, Neue Ebene).
	          Ein grüner ⬆-Punkt zeigt, wo du dir gerade ein Upgrade leisten kannst.
	  Rechts: Name + Kennzahlen der gewählten Station, Kaufmenge (x1/x10/MAX)
	          und eine große Zeile pro Upgrade (Level, jetzt ➜ danach, Preis).
	Alle Werte kommen aus Formulas = exakt die Rechnung des Servers.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local BigNum = require(Shared.BigNum)
local Clock = require(Shared.Clock)
local Config = require(Shared.Config)
local Formulas = require(Shared.Formulas)
local Types = require(Shared.Types)

local ClientState = require(script.Parent.Parent.Parent.ClientState)
local Remote = require(script.Parent.Parent.Parent.Remote)
local Components = require(script.Parent.Parent.Components)
local PanelManager = require(script.Parent.Parent.PanelManager)
local Theme = require(script.Parent.Parent.Theme)
local Util = require(script.Parent.Parent.Util)

local UpgradesPanel = {}

local UNLOCK_TAB = "Unlock"
local LIST_WIDTH = 230

type Row = {
	TrackId: string,
	Level: TextLabel,
	Effect: TextLabel,
	Button: Components.Button,
}

type ListEntry = {
	Button: Components.Button,
	Dot: Frame,
}

local window: Components.Window
local stationList: ScrollingFrame
local titleLabel: TextLabel
local statsRow: Frame
local body: ScrollingFrame
local amountButtons: { [number]: Components.Button } = {}
local listEntries: { [string]: ListEntry } = {}

local selectedKey = "Shaft:1"
local buyAmount = 1
local rows: { Row } = {}
local unlockButton: Components.Button? = nil
local lastListSignature = ""

local function money(b: BigNum.BigNum): string
	return BigNum.formatMoney(b, Config.CurrencySymbol)
end

local function stationColor(key: string): Color3
	local area, index = Formulas.parseKey(key)
	if area == "Shaft" and index then
		return Config.Shafts[index].OreColor
	elseif area == "Elevator" then
		return Theme.Colors.Blue
	elseif area == "Warehouse" then
		return Theme.Colors.Gold
	end
	return Theme.Colors.Green
end

local function listKeys(data: Types.PlayerData): { string }
	local keys = { "Warehouse", "Elevator" }
	for i = 1, #data.Shafts do
		table.insert(keys, Formulas.shaftKey(i))
	end
	if #data.Shafts < #Config.Shafts then
		table.insert(keys, UNLOCK_TAB)
	end
	return keys
end

local function listText(key: string): string
	local area, index = Formulas.parseKey(key)
	if key == UNLOCK_TAB then
		return "🔓 Neue Ebene"
	elseif area == "Shaft" and index then
		return string.format("⛏ %d · %s", index, Config.Shafts[index].Ore)
	elseif area == "Elevator" then
		return "🛗 Aufzug"
	end
	return "🏪 Händler"
end

--- Kann sich der Spieler bei dieser Station gerade ein Upgrade leisten?
local function hasAffordable(data: Types.PlayerData, key: string, now: number): boolean
	if key == UNLOCK_TAB then
		local cost = Formulas.nextShaftCost(data)
		return cost ~= nil and BigNum.gte(data.Cash, cost)
	end
	local area = Formulas.parseKey(key)
	if not area then
		return false
	end
	for _, def in Formulas.tracksFor(area) do
		local q = Formulas.upgradeQuote(data, key, def.Id, 1, now)
		if q and q.Affordable then
			return true
		end
	end
	return false
end

----------------------------------------------------------------------
-- Kennzahlen-Chips unter dem Titel
----------------------------------------------------------------------
local function chip(text: string, order: number)
	local f = Components.pill({
		Size = UDim2.fromOffset(0, 34),
		AutomaticSize = Enum.AutomaticSize.X,
		LayoutOrder = order,
		Parent = statsRow,
	}, Theme.Colors.Stroke)
	Util.padding(0, 12).Parent = f
	local l = Util.label({
		Size = UDim2.fromScale(0, 1),
		AutomaticSize = Enum.AutomaticSize.X,
		Text = text,
		TextSize = 16,
		Parent = f,
	})
	Util.textStroke(1).Parent = l
end

local function refreshStats(data: Types.PlayerData)
	for _, child in statsRow:GetChildren() do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end
	if selectedKey == UNLOCK_TAB then
		return
	end
	local ctx = ClientState.context()
	local area, index = Formulas.parseKey(selectedKey)
	if area == "Shaft" and index then
		chip("💰 " .. money(Formulas.shaftYield(data, index, ctx)) .. " / Zyklus", 1)
		chip(string.format("⏱ %.2fs", Formulas.shaftDuration(data, index, ctx)), 2)
	elseif area == "Elevator" then
		chip("📦 " .. BigNum.format(Formulas.elevatorLoad(data, ctx)) .. " pro Fahrt", 1)
		chip(string.format("⏱ %.2fs", Formulas.elevatorDuration(data, ctx)), 2)
	elseif area == "Warehouse" then
		chip("📦 " .. BigNum.format(Formulas.warehouseLoad(data, ctx)), 1)
		chip(string.format("⏱ %.2fs", Formulas.warehouseDuration(data, ctx)), 2)
		chip(string.format("💰 Preis x%.2f", Formulas.sellPriceMultiplier(data)), 3)
	end
	local manager = Formulas.managerFor(data, selectedKey)
	chip(if manager then "👔 " .. manager.Name else "👔 Kein Manager", 4)
end

----------------------------------------------------------------------
-- Rechte Seite aufbauen
----------------------------------------------------------------------
local function clearBody()
	for _, child in body:GetChildren() do
		child:Destroy()
	end
	table.clear(rows)
	unlockButton = nil
	Util.list(Enum.FillDirection.Vertical, 10, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Top).Parent =
		body
	Util.new("UIPadding", { PaddingRight = UDim.new(0, 10), PaddingTop = UDim.new(0, 4), Parent = body })
end

local function buildTrackRow(key: string, def: Config.TrackDef, order: number)
	local color = stationColor(key)
	local card = Components.card({ Size = UDim2.new(1, 0, 0, 108), LayoutOrder = order, Parent = body })
	local icon: Frame = Util.new("Frame", {
		Size = UDim2.fromOffset(72, 72),
		Position = UDim2.new(0, 14, 0.5, 0),
		AnchorPoint = Vector2.new(0, 0.5),
		BackgroundColor3 = Color3.new(1, 1, 1),
		Parent = card,
	}, {
		Util.round(),
		Util.gradient(Theme.lighten(color, 0.35), Theme.darken(color, 0.15)),
		Util.stroke(Color3.new(1, 1, 1), 2.5, 0.2),
	})
	Util.label({ Size = UDim2.fromScale(1, 1), Text = def.Icon, TextSize = 38, Parent = icon })

	local textWidth = -330
	local name = Util.label({
		Size = UDim2.new(1, textWidth, 0, 30),
		Position = UDim2.fromOffset(100, 10),
		Text = def.Name,
		Font = Theme.Fonts.Title,
		TextSize = 25,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = card,
	})
	Util.textStroke(1.5).Parent = name
	local level = Util.label({
		Size = UDim2.new(1, textWidth, 0, 22),
		Position = UDim2.fromOffset(100, 42),
		Text = "",
		TextSize = 17,
		TextColor3 = Theme.Colors.Gold,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = card,
	})
	Util.textStroke(1).Parent = level
	local effect = Util.label({
		Size = UDim2.new(1, textWidth, 0, 26),
		Position = UDim2.fromOffset(100, 70),
		Text = "",
		TextSize = 18,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = card,
	})
	Util.textStroke(1).Parent = effect

	local button: Components.Button
	button = Components.button({
		Text = "",
		Color = Theme.Colors.Green,
		Size = UDim2.fromOffset(206, 76),
		Position = UDim2.new(1, -14, 0.5, 0),
		AnchorPoint = Vector2.new(1, 0.5),
		TextSize = 24,
		Parent = card,
		Sound = "Purchase",
		OnClick = function()
			local r = Remote.request("Upgrade", { Key = key, Track = def.Id, Amount = buyAmount })
			if r.ok then
				button.Pop()
			end
		end,
	})
	table.insert(rows, { TrackId = def.Id, Level = level, Effect = effect, Button = button })
end

local function buildUnlock(data: Types.PlayerData)
	local nextIndex = #data.Shafts + 1
	local def = Config.Shafts[nextIndex]
	if not def then
		return
	end
	local card = Components.card({ Size = UDim2.new(1, 0, 0, 250), LayoutOrder = 1, Parent = body }, def.OreColor)
	local orb: Frame = Util.new("Frame", {
		Size = UDim2.fromOffset(120, 120),
		Position = UDim2.new(0.5, 0, 0, 18),
		AnchorPoint = Vector2.new(0.5, 0),
		BackgroundColor3 = Color3.new(1, 1, 1),
		Parent = card,
	}, {
		Util.round(),
		Util.gradient(Theme.lighten(def.OreColor, 0.4), Theme.darken(def.OreColor, 0.2)),
		Util.stroke(Color3.new(1, 1, 1), 3, 0.2),
	})
	Util.label({ Size = UDim2.fromScale(1, 1), Text = "⛏", TextSize = 56, Parent = orb })
	local title = Util.label({
		Size = UDim2.new(1, 0, 0, 36),
		Position = UDim2.fromOffset(0, 144),
		Text = string.format("Ebene %d: %s", nextIndex, def.Name),
		Font = Theme.Fonts.Title,
		TextSize = 28,
		Parent = card,
	})
	Util.textStroke(1.5).Parent = title
	local info = Util.label({
		Size = UDim2.new(1, 0, 0, 26),
		Position = UDim2.fromOffset(0, 184),
		Text = string.format("%s  •  %s pro Zyklus", def.Ore, money(BigNum.new(def.BaseYield))),
		TextSize = 19,
		Parent = card,
	})
	Util.textStroke(1).Parent = info
	local button: Components.Button
	button = Components.button({
		Text = "Freischalten",
		Color = Theme.Colors.Green,
		Size = UDim2.fromOffset(340, 76),
		LayoutOrder = 2,
		TextSize = 26,
		Sound = "Purchase",
		Parent = body,
		OnClick = function()
			local r = Remote.request("UnlockShaft")
			if r.ok then
				button.Pop()
				selectedKey = Formulas.shaftKey(nextIndex)
				UpgradesPanel.rebuild()
			end
		end,
	})
	unlockButton = button
end

----------------------------------------------------------------------
-- Aktualisieren
----------------------------------------------------------------------
local function updateTexts()
	local snap = ClientState.Snapshot
	if not snap then
		return
	end
	local data = snap.Data
	local now = Clock.now()
	local station = Formulas.getStation(data, selectedKey)
	local area = Formulas.parseKey(selectedKey)
	if station and area then
		for _, row in rows do
			local level = Formulas.level(station, row.TrackId)
			local quote = Formulas.upgradeQuote(data, selectedKey, row.TrackId, buyAmount, now)
			if quote then
				local nowText = Formulas.trackEffectText(data, selectedKey, row.TrackId, level)
				if quote.Maxed then
					row.Level.Text = string.format("Level %d  •  MAX", level)
					row.Effect.Text = nowText
					row.Button.SetText("MAX")
					row.Button.SetEnabled(false)
				else
					local nextLevel = level + quote.Levels
					row.Level.Text = string.format("Level %d  ➜  %d", level, nextLevel)
					row.Effect.Text = string.format(
						'%s  ➜  <font color="#9BFFAE">%s</font>',
						nowText,
						Formulas.trackEffectText(data, selectedKey, row.TrackId, nextLevel)
					)
					row.Button.SetText(
						string.format('%s\n<font size="15">+%d Level</font>', money(quote.Cost), quote.Levels)
					)
					row.Button.SetEnabled(quote.Affordable)
				end
			end
		end
		refreshStats(data)
	end
	if unlockButton then
		local cost = Formulas.nextShaftCost(data)
		if cost then
			unlockButton.SetText("Freischalten  " .. money(cost))
			unlockButton.SetEnabled(BigNum.gte(data.Cash, cost))
		end
	end
	for key, entry in listEntries do
		entry.Button.SetColor(if key == selectedKey then Theme.Colors.Selected else Theme.Colors.CardLight)
		entry.Dot.Visible = key ~= selectedKey and hasAffordable(data, key, now)
	end
	for amount, b in amountButtons do
		b.SetColor(if amount == buyAmount then Theme.Colors.Selected else Theme.Colors.CardLight)
	end
end

local function rebuildList(data: Types.PlayerData)
	local keys = listKeys(data)
	local signature = table.concat(keys, ",")
	if signature == lastListSignature then
		return
	end
	lastListSignature = signature
	for _, entry in listEntries do
		entry.Button.Instance:Destroy()
	end
	table.clear(listEntries)
	for i, key in keys do
		local button = Components.button({
			Text = listText(key),
			Color = Theme.Colors.CardLight,
			Size = UDim2.new(1, -12, 0, 56),
			TextSize = 19,
			LayoutOrder = i,
			Parent = stationList,
			OnClick = function()
				selectedKey = key
				UpgradesPanel.rebuild()
			end,
		})
		button.Label.TextXAlignment = Enum.TextXAlignment.Left
		Util.padding(0, 14).Parent = button.Label
		local dot: Frame = Util.new("Frame", {
			Name = "Affordable",
			Size = UDim2.fromOffset(26, 26),
			Position = UDim2.new(1, -8, 0.5, 0),
			AnchorPoint = Vector2.new(1, 0.5),
			BackgroundColor3 = Theme.Colors.Green,
			Visible = false,
			ZIndex = 4,
			Parent = button.Instance,
		}, { Util.round(), Util.stroke(Color3.new(1, 1, 1), 2) })
		Util.label({ Size = UDim2.fromScale(1, 1), Text = "⬆", TextSize = 16, ZIndex = 5, Parent = dot })
		listEntries[key] = { Button = button, Dot = dot }
	end
end

function UpgradesPanel.rebuild()
	local snap = ClientState.Snapshot
	if not snap then
		return
	end
	local data = snap.Data
	rebuildList(data)
	if selectedKey ~= UNLOCK_TAB and not Formulas.getStation(data, selectedKey) then
		selectedKey = "Shaft:1"
	end
	if selectedKey == UNLOCK_TAB and #data.Shafts >= #Config.Shafts then
		selectedKey = "Shaft:1"
	end
	clearBody()
	titleLabel.Text = if selectedKey == UNLOCK_TAB then "🔓 Neue Ebene" else Formulas.stationDisplayName(selectedKey)
	if selectedKey == UNLOCK_TAB then
		buildUnlock(data)
	else
		local area = Formulas.parseKey(selectedKey)
		if area then
			for i, def in Formulas.tracksFor(area) do
				buildTrackRow(selectedKey, def, i)
			end
		end
	end
	updateTexts()
end

function UpgradesPanel.start()
	window = Components.window("Upgrades", "⬆️", Theme.Colors.Gold, Vector2.new(940, 590), function()
		PanelManager.close()
	end)
	local content = window.Content

	-- Linke Spalte: Stationen
	stationList = Components.scrollList({
		Size = UDim2.new(0, LIST_WIDTH, 1, 0),
		Parent = content,
	}, 8)

	-- Rechte Spalte
	local right: Frame = Util.new("Frame", {
		Name = "Right",
		Size = UDim2.new(1, -(LIST_WIDTH + 14), 1, 0),
		Position = UDim2.fromOffset(LIST_WIDTH + 14, 0),
		BackgroundTransparency = 1,
		Parent = content,
	})
	titleLabel = Util.label({
		Size = UDim2.new(1, -250, 0, 40),
		Text = "",
		Font = Theme.Fonts.Title,
		TextSize = 28,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Parent = right,
	})
	Util.textStroke(1.5).Parent = titleLabel

	local amounts: Frame = Util.new("Frame", {
		Name = "Amounts",
		Size = UDim2.fromOffset(244, 50),
		Position = UDim2.fromScale(1, 0),
		AnchorPoint = Vector2.new(1, 0),
		BackgroundTransparency = 1,
		Parent = right,
	}, { Util.list(Enum.FillDirection.Horizontal, 6, Enum.HorizontalAlignment.Right) })
	for i, amount in Config.BuyAmounts do
		amountButtons[amount] = Components.button({
			Text = if amount == -1 then "MAX" else "x" .. amount,
			Color = Theme.Colors.CardLight,
			Size = UDim2.fromOffset(76, 48),
			TextSize = 20,
			LayoutOrder = i,
			Parent = amounts,
			OnClick = function()
				buyAmount = amount
				updateTexts()
			end,
		})
	end

	statsRow = Util.new("Frame", {
		Name = "Stats",
		Size = UDim2.new(1, 0, 0, 36),
		Position = UDim2.fromOffset(0, 56),
		BackgroundTransparency = 1,
		Parent = right,
	}, { Util.list(Enum.FillDirection.Horizontal, 8, Enum.HorizontalAlignment.Left) })

	body = Util.new("ScrollingFrame", {
		Name = "Body",
		Size = UDim2.new(1, 0, 1, -104),
		Position = UDim2.fromOffset(0, 104),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 6,
		ScrollBarImageColor3 = Theme.Colors.Stroke,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		Parent = right,
	})

	PanelManager.register("Upgrades", window, function(arg: any)
		if type(arg) == "string" then
			selectedKey = arg
		end
		UpgradesPanel.rebuild()
	end)

	local lastUpdate = 0
	ClientState.Changed:Connect(function(snap)
		if not PanelManager.isOpen("Upgrades") then
			return
		end
		rebuildList(snap.Data)
		local now = os.clock()
		if now - lastUpdate > 0.15 then
			lastUpdate = now
			updateTexts()
		end
	end)
end

return UpgradesPanel

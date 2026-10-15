--!strict
--[[
	UpgradesPanel
	=============
	Oben: Tabs für jede Station (Händler, Aufzug, Ebene 1..n, Neue Ebene)
	      + Kaufmenge (x1 / x10 / MAX)
	Mitte: Upgrade-Zeilen der gewählten Station (Level, Wirkung jetzt -> danach,
	      Kaufen-Button mit Preis). Alle Werte über Formulas = exakt wie Server.
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

type Row = {
	TrackId: string,
	Level: TextLabel,
	Effect: TextLabel,
	Button: Components.Button,
}

local window: Components.Window
local tabsFrame: ScrollingFrame
local body: Frame
local amountButtons: { [number]: Components.Button } = {}
local tabButtons: { [string]: Components.Button } = {}

local selectedKey = "Shaft:1"
local buyAmount = 1
local rows: { Row } = {}
local headerInfo: TextLabel? = nil
local unlockButton: Components.Button? = nil
local lastTabSignature = ""

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

local function tabKeys(data: Types.PlayerData): { string }
	local keys = { "Warehouse", "Elevator" }
	for i = 1, #data.Shafts do
		table.insert(keys, Formulas.shaftKey(i))
	end
	if #data.Shafts < #Config.Shafts then
		table.insert(keys, UNLOCK_TAB)
	end
	return keys
end

local function tabText(key: string): string
	local area, index = Formulas.parseKey(key)
	if key == UNLOCK_TAB then
		return "🔓 Neu"
	elseif area == "Shaft" and index then
		return "⛏ " .. index
	elseif area == "Elevator" then
		return "🛗 Aufzug"
	end
	return "🏪 Händler"
end

----------------------------------------------------------------------
-- Inhalt aufbauen
----------------------------------------------------------------------
local function clearBody()
	for _, child in body:GetChildren() do
		child:Destroy()
	end
	table.clear(rows)
	headerInfo = nil
	unlockButton = nil
end

local function stationInfoText(data: Types.PlayerData, key: string): string
	local ctx = ClientState.context()
	local area, index = Formulas.parseKey(key)
	local manager = Formulas.managerFor(data, key)
	local managerText = if manager
		then string.format("👔 %s (%s)", manager.Name, Formulas.rarityDef(manager.Rarity).Name)
		else "👔 Kein Manager - tippe auf die Station!"
	if area == "Shaft" and index then
		return string.format(
			"%s pro Zyklus  •  %.2fs  •  %s",
			money(Formulas.shaftYield(data, index, ctx)),
			Formulas.shaftDuration(data, index, ctx),
			managerText
		)
	elseif area == "Elevator" then
		return string.format(
			"Ladung %s  •  %.2fs pro Fahrt  •  %s",
			BigNum.format(Formulas.elevatorLoad(data, ctx)),
			Formulas.elevatorDuration(data, ctx),
			managerText
		)
	end
	return string.format(
		"Transport %s  •  %.2fs  •  Preis x%.2f  •  %s",
		BigNum.format(Formulas.warehouseLoad(data, ctx)),
		Formulas.warehouseDuration(data, ctx),
		Formulas.sellPriceMultiplier(data),
		managerText
	)
end

local function buildHeader(key: string)
	local color = stationColor(key)
	local card = Components.card({ Size = UDim2.new(1, 0, 0, 74), LayoutOrder = 0, Parent = body }, color)
	local title = Util.label({
		Size = UDim2.new(1, -24, 0, 34),
		Position = UDim2.fromOffset(16, 6),
		Text = Formulas.stationDisplayName(key),
		Font = Theme.Fonts.Title,
		TextSize = 26,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = card,
	})
	Util.textStroke(1.5).Parent = title
	headerInfo = Util.label({
		Size = UDim2.new(1, -24, 0, 26),
		Position = UDim2.fromOffset(16, 40),
		Text = "",
		TextSize = 15,
		TextColor3 = Theme.Colors.SubText,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Parent = card,
	})
end

local function buildTrackRow(key: string, def: Config.TrackDef, order: number)
	local card = Components.card({ Size = UDim2.new(1, 0, 0, 96), LayoutOrder = order, Parent = body })
	local icon: Frame = Util.new("Frame", {
		Size = UDim2.fromOffset(66, 66),
		Position = UDim2.fromOffset(14, 15),
		BackgroundColor3 = Color3.new(1, 1, 1),
		Parent = card,
	}, {
		Util.round(),
		Util.gradient(Theme.lighten(stationColor(key), 0.2), Theme.darken(stationColor(key), 0.35)),
		Util.stroke(Color3.new(0, 0, 0), 2, 0.5),
	})
	Util.label({ Size = UDim2.fromScale(1, 1), Text = def.Icon, TextSize = 34, Parent = icon })

	local name = Util.label({
		Size = UDim2.new(1, -330, 0, 30),
		Position = UDim2.fromOffset(94, 10),
		Text = def.Name,
		Font = Theme.Fonts.Title,
		TextSize = 23,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = card,
	})
	Util.textStroke(1.2).Parent = name
	local level = Util.label({
		Size = UDim2.new(1, -330, 0, 22),
		Position = UDim2.fromOffset(94, 40),
		Text = "",
		TextSize = 15,
		TextColor3 = Theme.Colors.Gold,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = card,
	})
	local effect = Util.label({
		Size = UDim2.new(1, -330, 0, 22),
		Position = UDim2.fromOffset(94, 64),
		Text = "",
		TextSize = 15,
		TextColor3 = Theme.Colors.SubText,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = card,
	})

	local button: Components.Button
	button = Components.button({
		Text = "",
		Color = Theme.Colors.Green,
		Size = UDim2.fromOffset(210, 66),
		Position = UDim2.new(1, -14, 0.5, 0),
		AnchorPoint = Vector2.new(1, 0.5),
		TextSize = 20,
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
	local card = Components.card({ Size = UDim2.new(1, 0, 0, 260), LayoutOrder = 1, Parent = body }, def.OreColor)
	local orb: Frame = Util.new("Frame", {
		Size = UDim2.fromOffset(120, 120),
		Position = UDim2.new(0.5, 0, 0, 20),
		AnchorPoint = Vector2.new(0.5, 0),
		BackgroundColor3 = Color3.new(1, 1, 1),
		Parent = card,
	}, {
		Util.round(),
		Util.gradient(Theme.lighten(def.OreColor, 0.35), Theme.darken(def.OreColor, 0.3)),
		Util.stroke(Color3.new(1, 1, 1), 3, 0.3),
	})
	Util.label({ Size = UDim2.fromScale(1, 1), Text = "⛏", TextSize = 56, Parent = orb })
	local title = Util.label({
		Size = UDim2.new(1, 0, 0, 36),
		Position = UDim2.fromOffset(0, 146),
		Text = string.format("Ebene %d: %s", nextIndex, def.Name),
		Font = Theme.Fonts.Title,
		TextSize = 28,
		Parent = card,
	})
	Util.textStroke(1.5).Parent = title
	Util.label({
		Size = UDim2.new(1, 0, 0, 24),
		Position = UDim2.fromOffset(0, 182),
		Text = string.format(
			"%s  •  Startwert %s pro Zyklus",
			def.Ore,
			BigNum.formatMoney(BigNum.new(def.BaseYield), Config.CurrencySymbol)
		),
		TextSize = 17,
		TextColor3 = Theme.Colors.SubText,
		Parent = card,
	})
	local button: Components.Button
	button = Components.button({
		Text = "Freischalten",
		Color = Theme.Colors.Green,
		Size = UDim2.fromOffset(300, 70),
		LayoutOrder = 2,
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
	if headerInfo then
		headerInfo.Text = stationInfoText(data, selectedKey)
	end
	local station = Formulas.getStation(data, selectedKey)
	if station then
		for _, row in rows do
			local level = Formulas.level(station, row.TrackId)
			local quote = Formulas.upgradeQuote(data, selectedKey, row.TrackId, buyAmount, now)
			local area = Formulas.parseKey(selectedKey)
			local def = if area then Formulas.trackDef(area, row.TrackId) else nil
			if not quote or not def then
				continue
			end
			if quote.Maxed then
				row.Level.Text = string.format("Level %d  (MAX)", level)
				row.Effect.Text = Formulas.trackEffectText(data, selectedKey, row.TrackId, level)
				row.Button.SetText("MAX")
				row.Button.SetEnabled(false)
			else
				local nextLevel = level + quote.Levels
				row.Level.Text = string.format("Level %d  ➜  %d", level, nextLevel)
				row.Effect.Text = string.format(
					'%s  ➜  <font color="#78FF8C">%s</font>',
					Formulas.trackEffectText(data, selectedKey, row.TrackId, level),
					Formulas.trackEffectText(data, selectedKey, row.TrackId, nextLevel)
				)
				row.Button.SetText(
					string.format('%s\n<font size="14">+%d Level</font>', money(quote.Cost), quote.Levels)
				)
				row.Button.SetEnabled(quote.Affordable)
			end
		end
	end
	if unlockButton then
		local cost = Formulas.nextShaftCost(data)
		if cost then
			unlockButton.SetText("Freischalten  " .. money(cost))
			unlockButton.SetEnabled(BigNum.gte(data.Cash, cost))
		end
	end
	for key, b in tabButtons do
		b.SetColor(if key == selectedKey then Theme.Colors.Gold else Theme.Colors.CardLight)
	end
	for amount, b in amountButtons do
		b.SetColor(if amount == buyAmount then Theme.Colors.Gold else Theme.Colors.CardLight)
	end
end

local function rebuildTabs(data: Types.PlayerData)
	local keys = tabKeys(data)
	local signature = table.concat(keys, ",")
	if signature == lastTabSignature then
		return
	end
	lastTabSignature = signature
	for _, b in tabButtons do
		b.Instance:Destroy()
	end
	table.clear(tabButtons)
	for i, key in keys do
		tabButtons[key] = Components.button({
			Text = tabText(key),
			Color = Theme.Colors.CardLight,
			Size = UDim2.fromOffset(if key == "Warehouse" or key == "Elevator" then 120 else 76, 50),
			TextSize = 17,
			LayoutOrder = i,
			Parent = tabsFrame,
			OnClick = function()
				selectedKey = key
				UpgradesPanel.rebuild()
			end,
		})
	end
end

function UpgradesPanel.rebuild()
	local snap = ClientState.Snapshot
	if not snap then
		return
	end
	local data = snap.Data
	rebuildTabs(data)
	if selectedKey ~= UNLOCK_TAB and not Formulas.getStation(data, selectedKey) then
		selectedKey = "Shaft:1"
	end
	if selectedKey == UNLOCK_TAB and #data.Shafts >= #Config.Shafts then
		selectedKey = "Shaft:1"
	end
	clearBody()
	Util.list(Enum.FillDirection.Vertical, 10, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Top).Parent =
		body
	if selectedKey == UNLOCK_TAB then
		buildUnlock(data)
	else
		buildHeader(selectedKey)
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
	window = Components.window("Upgrades", "⬆️", Theme.Colors.Gold, Vector2.new(820, 560), function()
		PanelManager.close()
	end)

	tabsFrame = Util.new("ScrollingFrame", {
		Name = "Tabs",
		Size = UDim2.new(1, -250, 0, 62),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 4,
		ScrollingDirection = Enum.ScrollingDirection.X,
		AutomaticCanvasSize = Enum.AutomaticSize.X,
		CanvasSize = UDim2.new(),
		Parent = window.Content,
	}, {
		Util.list(Enum.FillDirection.Horizontal, 8, Enum.HorizontalAlignment.Left),
		Util.padding(4, 6),
	})

	local amounts: Frame = Util.new("Frame", {
		Name = "Amounts",
		Size = UDim2.fromOffset(240, 62),
		Position = UDim2.fromScale(1, 0),
		AnchorPoint = Vector2.new(1, 0),
		BackgroundTransparency = 1,
		Parent = window.Content,
	}, { Util.list(Enum.FillDirection.Horizontal, 6, Enum.HorizontalAlignment.Right) })
	for i, amount in Config.BuyAmounts do
		amountButtons[amount] = Components.button({
			Text = if amount == -1 then "MAX" else "x" .. amount,
			Color = Theme.Colors.CardLight,
			Size = UDim2.fromOffset(72, 50),
			TextSize = 19,
			LayoutOrder = i,
			Parent = amounts,
			OnClick = function()
				buyAmount = amount
				updateTexts()
			end,
		})
	end

	body = Util.new("ScrollingFrame", {
		Name = "Body",
		Size = UDim2.new(1, 0, 1, -72),
		Position = UDim2.fromOffset(0, 72),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 6,
		ScrollBarImageColor3 = Theme.Colors.Stroke,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		Parent = window.Content,
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
		rebuildTabs(snap.Data)
		local now = os.clock()
		if now - lastUpdate > 0.15 then
			lastUpdate = now
			updateTexts()
		end
	end)
end

return UpgradesPanel

--!strict
--[[
	UpgradesPanel
	=============
	Links:  Händler, Aufzug und die Ebenen seitenweise (◀ Ebenen 11–20 ▶).
	        Ein grüner ⬆-Punkt zeigt, wo du dir gerade ein Upgrade leisten kannst.
	Rechts: buntes Minen-Banner der gewählten Station (Erz, Zyklus-Fortschritt,
	        Kennzahlen, "👆 Abbauen" und "🎥 Zeigen"), Kaufmenge x1/x10/MAX und
	        große Upgrade-Zeilen. Alle Werte über Formulas = Rechnung des Servers.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local BigNum = require(Shared.BigNum)
local Clock = require(Shared.Clock)
local Config = require(Shared.Config)
local Formulas = require(Shared.Formulas)
local Types = require(Shared.Types)

local ClientState = require(script.Parent.Parent.Parent.ClientState)
local PlotLocator = require(script.Parent.Parent.Parent.PlotLocator)
local Remote = require(script.Parent.Parent.Parent.Remote)
local CameraController = require(script.Parent.Parent.Parent.Controllers.CameraController)
local Anim = require(script.Parent.Parent.Anim)
local Components = require(script.Parent.Parent.Components)
local PanelManager = require(script.Parent.Parent.PanelManager)
local Theme = require(script.Parent.Parent.Theme)
local Util = require(script.Parent.Parent.Util)

local UpgradesPanel = {}

local UNLOCK_TAB = "Unlock"
local LIST_WIDTH = 246
local SECTION = Config.ShaftGen.SectionSize

type Row = {
	TrackId: string,
	Level: TextLabel,
	Effect: TextLabel,
	Button: Components.Button,
}

type ListEntry = { Button: Components.Button, Dot: Frame }

local window: Components.Window
local stationList: ScrollingFrame
local right: Frame
local body: ScrollingFrame
local amountBar: Frame
local amountButtons: { [number]: Components.Button } = {}
local listEntries: { [string]: ListEntry } = {}

local selectedKey = "Shaft:1"
local listSection = 1
local buyAmount = 1
local rows: { Row } = {}
local unlockButton: Components.Button? = nil
local bannerProgress: Components.ProgressBar? = nil
local bannerStats: TextLabel? = nil
local lastListSignature = ""

local function money(b: BigNum.BigNum): string
	return BigNum.formatMoney(b, Config.CurrencySymbol)
end

local function stationColor(key: string): Color3
	local area, index = Formulas.parseKey(key)
	if area == "Shaft" and index then
		return Formulas.shaftDef(index).OreColor
	elseif area == "Elevator" then
		return Theme.Colors.Blue
	elseif area == "Warehouse" then
		return Theme.Colors.Gold
	end
	return Theme.Colors.Green
end

--- Für die Lesbarkeit: sehr dunkle/helle Erzfarben etwas Richtung Mitte ziehen
local function buttonColor(c: Color3): Color3
	local h, sat, v = c:ToHSV()
	return Color3.fromHSV(h, math.max(sat, 0.55), math.clamp(v, 0.55, 0.9))
end

local function maxListSection(data: Types.PlayerData): number
	return Formulas.sectionOf(math.min(#data.Shafts + 1, Formulas.shaftCount()))
end

--- Kann sich der Spieler bei dieser Station gerade ein Upgrade leisten?
local function hasAffordable(data: Types.PlayerData, key: string, now: number): boolean
	if key == UNLOCK_TAB then
		local cost = Formulas.nextShaftCost(data)
		return cost ~= nil and BigNum.gte(data.Cash, cost)
	end
	local area = Formulas.parseKey(key)
	if not area or not Formulas.getStation(data, key) then
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
-- Linke Liste
----------------------------------------------------------------------
local function listButton(key: string, text: string, color: Color3, order: number)
	local button = Components.button({
		Text = text,
		Color = color,
		Size = UDim2.new(1, -14, 0, 54),
		TextSize = 19,
		LayoutOrder = order,
		Parent = stationList,
		OnClick = function()
			selectedKey = key
			UpgradesPanel.rebuild()
		end,
	})
	button.Label.TextXAlignment = Enum.TextXAlignment.Left
	button.Label.TextTruncate = Enum.TextTruncate.AtEnd
	Util.padding(0, 14).Parent = button.Label
	local dot: Frame = Util.new("Frame", {
		Name = "Affordable",
		Size = UDim2.fromOffset(28, 28),
		Position = UDim2.new(1, -8, 0.5, 0),
		AnchorPoint = Vector2.new(1, 0.5),
		BackgroundColor3 = Theme.Colors.Lime,
		Visible = false,
		ZIndex = 6,
		Parent = button.Instance,
	}, { Util.round(), Util.stroke(Color3.new(1, 1, 1), 2.5) })
	Util.label({ Size = UDim2.fromScale(1, 1), Text = "⬆", TextSize = 17, ZIndex = 7, Parent = dot })
	local dotScale: UIScale = Util.new("UIScale", { Parent = dot })
	Anim.pulse(dotScale, 0.15, 6)
	listEntries[key] = { Button = button, Dot = dot }
end

local function rebuildList(data: Types.PlayerData)
	local maxSection = maxListSection(data)
	listSection = math.clamp(listSection, 1, maxSection)
	local first = (listSection - 1) * SECTION + 1
	local last = math.min(first + SECTION - 1, #data.Shafts)
	local unlockVisible = #data.Shafts < Formulas.shaftCount() and Formulas.sectionOf(#data.Shafts + 1) == listSection
	local signature = string.format("%d|%d|%d|%s", listSection, first, last, tostring(unlockVisible))
	if signature == lastListSignature then
		return
	end
	lastListSignature = signature
	for _, child in stationList:GetChildren() do
		if not child:IsA("UIListLayout") and not child:IsA("UIPadding") then
			child:Destroy()
		end
	end
	table.clear(listEntries)

	listButton("Warehouse", "🏪 Händler", Theme.Colors.Gold, 1)
	listButton("Elevator", "🛗 Aufzug", Theme.Colors.Blue, 2)

	-- Seitenwahl für die Ebenen
	local pager: Frame = Util.new("Frame", {
		Size = UDim2.new(1, -14, 0, 50),
		LayoutOrder = 3,
		BackgroundTransparency = 1,
		Parent = stationList,
	})
	Components.button({
		Text = "◀",
		Color = Theme.Colors.Purple,
		Size = UDim2.fromOffset(48, 48),
		TextSize = 24,
		Parent = pager,
		OnClick = function()
			listSection -= 1
			lastListSignature = ""
			UpgradesPanel.rebuild()
		end,
	}).SetEnabled(listSection > 1)
	local pageLabel = Util.label({
		Size = UDim2.new(1, -108, 1, 0),
		Position = UDim2.fromOffset(54, 0),
		Text = string.format("Ebenen %d–%d", first, first + SECTION - 1),
		Font = Theme.Fonts.Title,
		TextSize = 19,
		Parent = pager,
	})
	Util.textStroke(1.5).Parent = pageLabel
	Components.button({
		Text = "▶",
		Color = Theme.Colors.Purple,
		Size = UDim2.fromOffset(48, 48),
		Position = UDim2.fromScale(1, 0),
		AnchorPoint = Vector2.new(1, 0),
		TextSize = 24,
		Parent = pager,
		OnClick = function()
			listSection += 1
			lastListSignature = ""
			UpgradesPanel.rebuild()
		end,
	}).SetEnabled(listSection < maxSection)

	for i = first, last do
		local def = Formulas.shaftDef(i)
		listButton(Formulas.shaftKey(i), string.format("⛏ %d · %s", i, def.Ore), buttonColor(def.OreColor), 10 + i)
	end
	if unlockVisible then
		listButton(
			UNLOCK_TAB,
			string.format("🔓 Ebene %d", #data.Shafts + 1),
			Theme.Colors.Lime,
			10 + #data.Shafts + 1
		)
	end
end

----------------------------------------------------------------------
-- Minen-Banner (rechts oben)
----------------------------------------------------------------------
local function clearRight()
	for _, child in body:GetChildren() do
		child:Destroy()
	end
	local banner = right:FindFirstChild("Banner")
	if banner then
		banner:Destroy()
	end
	table.clear(rows)
	unlockButton = nil
	bannerProgress = nil
	bannerStats = nil
	Util.list(Enum.FillDirection.Vertical, 10, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Top).Parent =
		body
	Util.new("UIPadding", { PaddingRight = UDim.new(0, 10), PaddingTop = UDim.new(0, 4), Parent = body })
end

local function buildBanner(key: string, title: string, subtitle: string, icon: string, color: Color3)
	local c = buttonColor(color)
	local banner: Frame = Util.new("Frame", {
		Name = "Banner",
		Size = UDim2.new(1, 0, 0, 150),
		BackgroundColor3 = Color3.new(1, 1, 1),
		Parent = right,
	}, {
		Util.corner(Theme.Radius.Large),
		Util.gradient(Theme.lighten(c, 0.15), Theme.darken(c, 0.35), 20),
	})
	Components.rainbowBorder(banner, 4)
	Anim.shine(banner, Theme.Radius.Large, 5)
	-- Deko-Kristalle
	for n = 1, 6 do
		local gem = Util.label({
			Size = UDim2.fromOffset(40, 40),
			Position = UDim2.fromScale(0.5 + (n - 3.5) * 0.09, if n % 2 == 0 then 0.12 else 0.62),
			Text = if n % 3 == 0 then "✨" else "💎",
			TextSize = 22 + (n % 3) * 6,
			TextTransparency = 0.45,
			Rotation = (n * 37) % 40 - 20,
			Parent = banner,
		})
		gem.ZIndex = 1
	end
	local orb = Components.icon(icon, 110, c, {
		Position = UDim2.new(0, 18, 0.5, 0),
		AnchorPoint = Vector2.new(0, 0.5),
		ZIndex = 3,
		Parent = banner,
	})
	local orbScale: UIScale = Util.new("UIScale", { Parent = orb })
	Anim.pulse(orbScale, 0.05, 3)

	local titleLabel = Util.label({
		Size = UDim2.new(1, -330, 0, 40),
		Position = UDim2.fromOffset(142, 12),
		Text = title,
		Font = Theme.Fonts.Title,
		TextSize = 30,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		ZIndex = 4,
		Parent = banner,
	})
	Util.textStroke(2.5).Parent = titleLabel
	local sub = Util.label({
		Size = UDim2.new(1, -330, 0, 24),
		Position = UDim2.fromOffset(142, 52),
		Text = subtitle,
		TextSize = 17,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 4,
		Parent = banner,
	})
	Util.textStroke(1.5).Parent = sub
	bannerStats = Util.label({
		Size = UDim2.new(1, -330, 0, 24),
		Position = UDim2.fromOffset(142, 78),
		Text = "",
		TextSize = 17,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		ZIndex = 4,
		Parent = banner,
	})
	Util.textStroke(1.5).Parent = bannerStats
	if key ~= UNLOCK_TAB then
		local bar = Components.progressBar({
			Size = UDim2.new(1, -340, 0, 20),
			Position = UDim2.fromOffset(142, 112),
			ZIndex = 4,
			Parent = banner,
		}, Theme.Colors.Lime)
		bar.SetText("Zyklus")
		bannerProgress = bar
	end

	-- Aktionen rechts im Banner
	local actions: Frame = Util.new("Frame", {
		Size = UDim2.fromOffset(180, 130),
		Position = UDim2.new(1, -14, 0.5, 0),
		AnchorPoint = Vector2.new(1, 0.5),
		BackgroundTransparency = 1,
		ZIndex = 4,
		Parent = banner,
	}, { Util.list(Enum.FillDirection.Vertical, 10) })
	if key ~= UNLOCK_TAB then
		local snap = ClientState.Snapshot
		local hasManager = snap ~= nil and Formulas.managerFor(snap.Data, key) ~= nil
		if not hasManager then
			Components.button({
				Text = "👆 Abbauen",
				Color = Theme.Colors.Lime,
				Size = UDim2.fromOffset(176, 58),
				TextSize = 21,
				LayoutOrder = 1,
				Parent = actions,
				Shine = true,
				OnClick = function()
					Remote.send("Work", { Key = key })
				end,
			})
		end
		Components.button({
			Text = "🎥 Zeigen",
			Color = Theme.Colors.Cyan,
			Size = UDim2.fromOffset(176, 58),
			TextSize = 21,
			LayoutOrder = 2,
			Parent = actions,
			OnClick = function()
				local _, index = Formulas.parseKey(key)
				PanelManager.close()
				if index then
					CameraController.focusLevel(index)
				elseif not CameraController.isActive() then
					CameraController.setActive(true)
				end
			end,
		})
	end
end

local function statsText(data: Types.PlayerData, key: string): string
	local ctx = ClientState.context()
	local area, index = Formulas.parseKey(key)
	local manager = Formulas.managerFor(data, key)
	local managerText = if manager then "👔 " .. manager.Name else "👔 Kein Manager"
	if area == "Shaft" and index then
		return string.format(
			"💰 %s / Zyklus  •  ⏱ %.2fs  •  %s",
			money(Formulas.shaftYield(data, index, ctx)),
			Formulas.shaftDuration(data, index, ctx),
			managerText
		)
	elseif area == "Elevator" then
		return string.format(
			"📦 %s pro Fahrt  •  ⏱ %.2fs  •  %s",
			BigNum.format(Formulas.elevatorLoad(data, ctx)),
			Formulas.elevatorDuration(data, ctx),
			managerText
		)
	end
	return string.format(
		"📦 %s  •  ⏱ %.2fs  •  💰 x%.2f  •  %s",
		BigNum.format(Formulas.warehouseLoad(data, ctx)),
		Formulas.warehouseDuration(data, ctx),
		Formulas.sellPriceMultiplier(data),
		managerText
	)
end

----------------------------------------------------------------------
-- Upgrade-Zeilen
----------------------------------------------------------------------
local function buildTrackRow(key: string, def: Config.TrackDef, order: number)
	local color = buttonColor(stationColor(key))
	local card = Components.card({ Size = UDim2.new(1, 0, 0, 108), LayoutOrder = order, Parent = body }, color)
	Components.icon(def.Icon, 76, color, {
		Position = UDim2.new(0, 14, 0.5, 0),
		AnchorPoint = Vector2.new(0, 0.5),
		Parent = card,
	})

	local textWidth = -330
	local name = Util.label({
		Size = UDim2.new(1, textWidth, 0, 30),
		Position = UDim2.fromOffset(102, 10),
		Text = def.Name,
		Font = Theme.Fonts.Title,
		TextSize = 25,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = card,
	})
	Util.textStroke(1.8).Parent = name
	local level = Util.label({
		Size = UDim2.new(1, textWidth, 0, 22),
		Position = UDim2.fromOffset(102, 42),
		Text = "",
		Font = Theme.Fonts.Number,
		TextSize = 17,
		TextColor3 = Theme.Colors.Selected,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = card,
	})
	Util.textStroke(1.5).Parent = level
	local effect = Util.label({
		Size = UDim2.new(1, textWidth, 0, 26),
		Position = UDim2.fromOffset(102, 70),
		Text = "",
		TextSize = 18,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = card,
	})
	Util.textStroke(1.5).Parent = effect

	local button: Components.Button
	button = Components.button({
		Text = "",
		Color = Theme.Colors.Green,
		Size = UDim2.fromOffset(206, 78),
		Position = UDim2.new(1, -14, 0.5, 0),
		AnchorPoint = Vector2.new(1, 0.5),
		TextSize = 24,
		Parent = card,
		Sound = "Purchase",
		Shine = true,
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
	if nextIndex > Formulas.shaftCount() then
		return
	end
	local def = Formulas.shaftDef(nextIndex)
	buildBanner(
		UNLOCK_TAB,
		string.format("Ebene %d: %s", nextIndex, def.Name),
		string.format("%s  •  %s pro Zyklus", def.Ore, money(def.BaseYield)),
		"🔓",
		def.OreColor
	)
	local button: Components.Button
	button = Components.button({
		Text = "Freischalten",
		Color = Theme.Colors.Lime,
		Size = UDim2.fromOffset(380, 84),
		LayoutOrder = 1,
		TextSize = 28,
		Sound = "Purchase",
		Shine = true,
		Rainbow = true,
		Parent = body,
		OnClick = function()
			local r = Remote.request("UnlockShaft")
			if r.ok then
				button.Pop()
				selectedKey = Formulas.shaftKey(nextIndex)
				listSection = Formulas.sectionOf(nextIndex)
				lastListSignature = ""
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
					row.Level.Text = string.format("LEVEL %d  •  MAX", level)
					row.Effect.Text = nowText
					row.Button.SetText("MAX")
					row.Button.SetEnabled(false)
				else
					local nextLevel = level + quote.Levels
					row.Level.Text = string.format("LEVEL %d  ➜  %d", level, nextLevel)
					row.Effect.Text = string.format(
						'%s  ➜  <font color="#A8FF4F">%s</font>',
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
		local stats = bannerStats
		if stats then
			stats.Text = statsText(data, selectedKey)
		end
	end
	if unlockButton then
		local cost = Formulas.nextShaftCost(data)
		if cost then
			unlockButton.SetText("🔓 Freischalten  " .. money(cost))
			unlockButton.SetEnabled(BigNum.gte(data.Cash, cost))
		end
	end
	for key, entry in listEntries do
		local selected = key == selectedKey
		if selected then
			entry.Button.SetColor(Theme.Colors.Selected)
		else
			entry.Button.SetColor(
				if key == UNLOCK_TAB
					then Theme.Colors.Lime
					elseif key == "Warehouse" then Theme.Colors.Gold
					elseif key == "Elevator" then Theme.Colors.Blue
					else buttonColor(stationColor(key))
			)
		end
		entry.Dot.Visible = not selected and hasAffordable(data, key, now)
	end
	for amount, b in amountButtons do
		b.SetColor(if amount == buyAmount then Theme.Colors.Selected else Theme.Colors.Purple)
	end
end

function UpgradesPanel.rebuild()
	local snap = ClientState.Snapshot
	if not snap then
		return
	end
	local data = snap.Data
	if selectedKey ~= UNLOCK_TAB and not Formulas.getStation(data, selectedKey) then
		selectedKey = "Shaft:1"
	end
	if selectedKey == UNLOCK_TAB and #data.Shafts >= Formulas.shaftCount() then
		selectedKey = "Shaft:1"
	end
	rebuildList(data)
	clearRight()
	amountBar.Visible = selectedKey ~= UNLOCK_TAB
	if selectedKey == UNLOCK_TAB then
		buildUnlock(data)
	else
		local area, index = Formulas.parseKey(selectedKey)
		if area == "Shaft" and index then
			local def = Formulas.shaftDef(index)
			buildBanner(
				selectedKey,
				string.format("Ebene %d: %s", index, def.Name),
				string.format("%s  •  Abschnitt %d", def.Ore, Formulas.sectionOf(index)),
				"⛏",
				def.OreColor
			)
		elseif area == "Elevator" then
			buildBanner(selectedKey, "Aufzug", "Bringt das Erz nach oben ins Aufzugslager", "🛗", Theme.Colors.Blue)
		elseif area == "Warehouse" then
			buildBanner(selectedKey, "Händler", "Verkauft das Erz für Geld", "🏪", Theme.Colors.Gold)
		end
		if area then
			for i, def in Formulas.tracksFor(area) do
				buildTrackRow(selectedKey, def, i)
			end
		end
	end
	updateTexts()
end

function UpgradesPanel.start()
	window = Components.window("Upgrades", "⬆️", Theme.Colors.Gold, Vector2.new(980, 610), function()
		PanelManager.close()
	end)
	local content = window.Content

	stationList = Components.scrollList({
		Size = UDim2.new(0, LIST_WIDTH, 1, 0),
		Parent = content,
	}, 8)

	right = Util.new("Frame", {
		Name = "Right",
		Size = UDim2.new(1, -(LIST_WIDTH + 14), 1, 0),
		Position = UDim2.fromOffset(LIST_WIDTH + 14, 0),
		BackgroundTransparency = 1,
		Parent = content,
	})

	amountBar = Util.new("Frame", {
		Name = "Amounts",
		Size = UDim2.new(1, 0, 0, 50),
		Position = UDim2.fromOffset(0, 158),
		BackgroundTransparency = 1,
		Parent = right,
	}, { Util.list(Enum.FillDirection.Horizontal, 8, Enum.HorizontalAlignment.Right) })
	local amountLabel = Util.label({
		Size = UDim2.fromOffset(110, 48),
		Text = "Menge:",
		Font = Theme.Fonts.Title,
		TextSize = 21,
		LayoutOrder = 0,
		Parent = amountBar,
	})
	Util.textStroke(1.5).Parent = amountLabel
	for i, amount in Config.BuyAmounts do
		amountButtons[amount] = Components.button({
			Text = if amount == -1 then "MAX" else "x" .. amount,
			Color = Theme.Colors.Purple,
			Size = UDim2.fromOffset(84, 48),
			TextSize = 21,
			LayoutOrder = i,
			Parent = amountBar,
			OnClick = function()
				buyAmount = amount
				updateTexts()
			end,
		})
	end

	body = Util.new("ScrollingFrame", {
		Name = "Body",
		Size = UDim2.new(1, 0, 1, -216),
		Position = UDim2.fromOffset(0, 216),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 6,
		ScrollBarImageColor3 = Theme.Colors.Stroke,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		Parent = right,
	})

	PanelManager.register("Upgrades", window, function(arg: any)
		local snap = ClientState.Snapshot
		if type(arg) == "string" then
			selectedKey = arg
		end
		if snap then
			local _, index = Formulas.parseKey(selectedKey)
			if selectedKey == UNLOCK_TAB then
				index = #snap.Data.Shafts + 1
			end
			listSection = if index then Formulas.sectionOf(index) else maxListSection(snap.Data)
		end
		lastListSignature = ""
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

	-- Zyklus-Fortschritt im Banner live anzeigen
	RunService.RenderStepped:Connect(function()
		local bar = bannerProgress
		if not bar or not PanelManager.isOpen("Upgrades") then
			return
		end
		local station = PlotLocator.station(PlotLocator.ownPlot(), selectedKey)
		if not station then
			bar.Set(0)
			bar.SetText("Nicht im angezeigten Abschnitt")
			return
		end
		local running = station:GetAttribute("Running") == true
		local s = station:GetAttribute("CycleStart")
		local e = station:GetAttribute("CycleEnd")
		if running and type(s) == "number" and type(e) == "number" and e > s then
			bar.Set((Clock.now() - s) / (e - s))
			bar.SetText("⚙ arbeitet ...")
		else
			bar.Set(0)
			bar.SetText(if station:GetAttribute("HasManager") then "wartet auf Erz" else "👆 Tippen zum Arbeiten")
		end
	end)
end

return UpgradesPanel

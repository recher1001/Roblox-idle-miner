--!strict
--[[
	HUD
	===
	  Oben:    Geld (hochzählend) + Einkommen/s, Gems, Rebirth-Multiplikator
	           darunter aktive Boosts / Events / Schutz als Chips mit Timer
	  Links:   Menü (Upgrades, Manager, Rebirth, Shop, Täglich, Ansicht)
	  Rechts:  "Alle boosten" und "Basis abschließen"
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local BigNum = require(Shared.BigNum)
local Clock = require(Shared.Clock)
local Config = require(Shared.Config)
local Formulas = require(Shared.Formulas)
local Types = require(Shared.Types)

local ClientState = require(script.Parent.Parent.ClientState)
local Remote = require(script.Parent.Parent.Remote)
local Anim = require(script.Parent.Anim)
local Components = require(script.Parent.Components)
local FloatingText = require(script.Parent.FloatingText)
local PanelManager = require(script.Parent.PanelManager)
local Root = require(script.Parent.Root)
local Theme = require(script.Parent.Theme)
local Util = require(script.Parent.Util)

type BigNum = BigNum.BigNum

local HUD = {}

local cashLabel: TextLabel
local incomeLabel: TextLabel
local cashScale: UIScale
local gemsLabel: TextLabel
local gemsScale: UIScale
local rebirthLabel: TextLabel
local chipRow: Frame
local boostAllButton: Components.Button
local lockButton: Components.Button
local menuDots: { [string]: Frame } = {}

local displayedCash: BigNum = BigNum.zero()
local targetCash: BigNum = BigNum.zero()
local lastGems = -1

local CASH_POS = UDim2.new(0.5, 0, 0, 52)

function HUD.cashPosition(): UDim2
	return CASH_POS + UDim2.fromOffset(0, 50)
end

----------------------------------------------------------------------
-- Oben: Währungen
----------------------------------------------------------------------
local function buildTopBar(parent: Frame)
	local bar: Frame = Util.new("Frame", {
		Name = "TopBar",
		Size = UDim2.fromOffset(760, 80),
		Position = UDim2.new(0.5, 0, 0, 8),
		AnchorPoint = Vector2.new(0.5, 0),
		BackgroundTransparency = 1,
		Parent = parent,
	}, { Util.list(Enum.FillDirection.Horizontal, 12) })

	-- Rebirth
	local rebirth =
		Components.pill({ Size = UDim2.fromOffset(150, 56), LayoutOrder = 1, Parent = bar }, Theme.Colors.Purple)
	rebirthLabel = Util.label({
		Size = UDim2.fromScale(1, 1),
		Text = "⭐ x1.00",
		Font = Theme.Fonts.Number,
		TextSize = 22,
		Parent = rebirth,
	})
	Util.textStroke(1.5).Parent = rebirthLabel

	-- Geld
	cashScale = Util.new("UIScale")
	local cash = Components.pill({ Size = UDim2.fromOffset(330, 76), LayoutOrder = 2, Parent = bar }, Theme.Colors.Gold)
	Components.rainbowBorder(cash, 4)
	cashScale.Parent = cash
	Util.label({
		Size = UDim2.fromOffset(60, 76),
		Position = UDim2.fromOffset(8, 0),
		Text = "💰",
		TextSize = 40,
		Parent = cash,
	})
	cashLabel = Util.label({
		Size = UDim2.new(1, -80, 0, 46),
		Position = UDim2.fromOffset(66, 4),
		Text = "$0",
		Font = Theme.Fonts.Number,
		TextSize = 38,
		TextColor3 = Theme.Colors.Gold,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = cash,
	})
	Util.textStroke(2).Parent = cashLabel
	incomeLabel = Util.label({
		Size = UDim2.new(1, -80, 0, 22),
		Position = UDim2.fromOffset(68, 48),
		Text = "+$0/s",
		TextSize = 17,
		TextColor3 = Theme.Colors.Money,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = cash,
	})
	Util.textStroke(1).Parent = incomeLabel

	-- Gems
	gemsScale = Util.new("UIScale")
	local gems = Components.pill({ Size = UDim2.fromOffset(170, 56), LayoutOrder = 3, Parent = bar }, Theme.Colors.Gem)
	gemsScale.Parent = gems
	gemsLabel = Util.label({
		Size = UDim2.new(1, -50, 1, 0),
		Position = UDim2.fromOffset(12, 0),
		Text = "💎 0",
		Font = Theme.Fonts.Number,
		TextSize = 22,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = gems,
	})
	Util.textStroke(1.5).Parent = gemsLabel
	Components.button({
		Text = "+",
		Color = Theme.Colors.Green,
		Size = UDim2.fromOffset(40, 40),
		Position = UDim2.new(1, -8, 0.5, 0),
		AnchorPoint = Vector2.new(1, 0.5),
		TextSize = 28,
		Parent = gems,
		OnClick = function()
			PanelManager.open("Shop")
		end,
	})

	-- Chips (Boosts, Events, Schutz)
	chipRow = Util.new("Frame", {
		Name = "Chips",
		Size = UDim2.fromOffset(900, 34),
		Position = UDim2.new(0.5, 0, 0, 94),
		AnchorPoint = Vector2.new(0.5, 0),
		BackgroundTransparency = 1,
		Parent = parent,
	}, { Util.list(Enum.FillDirection.Horizontal, 8) })
end

local function chip(text: string, color: Color3, order: number)
	local f = Components.pill({
		Size = UDim2.fromOffset(0, 32),
		AutomaticSize = Enum.AutomaticSize.X,
		LayoutOrder = order,
		Parent = chipRow,
	}, color)
	Util.padding(0, 14).Parent = f
	local l = Util.label({
		Size = UDim2.fromScale(0, 1),
		AutomaticSize = Enum.AutomaticSize.X,
		Text = text,
		TextSize = 15,
		Parent = f,
	})
	Util.textStroke(1).Parent = l
end

local function refreshChips(snap: Types.Snapshot)
	for _, child in chipRow:GetChildren() do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end
	local now = Clock.now()
	local data = snap.Data
	local order = 0
	if snap.Event and snap.Event.EndsAt > now then
		for _, e in Config.Events.List do
			if e.Id == snap.Event.Id then
				order += 1
				chip(
					"🔥 " .. e.Name .. " " .. Formulas.formatDuration(snap.Event.EndsAt - now),
					Theme.Colors.Orange,
					order
				)
			end
		end
	end
	local boostNames: { [string]: { string } } = {
		Cash = { "💰 2x Geld", "Gold" },
		Speed = { "⚡ 2x Tempo", "Blue" },
		Shield = { "🛡️ Schild", "Green" },
	}
	for id, info in boostNames do
		local untilTime = data.Boosts[id]
		if untilTime and untilTime > now then
			order += 1
			chip(info[1] .. " " .. Formulas.formatDuration(untilTime - now), (Theme.Colors :: any)[info[2]], order)
		end
	end
	if snap.ProtectedUntil > now then
		order += 1
		chip("🐣 Neulingsschutz " .. Formulas.formatDuration(snap.ProtectedUntil - now), Theme.Colors.Green, order)
	end
	if snap.LockedUntil > now then
		order += 1
		chip("🔒 Abgeschlossen " .. Formulas.formatDuration(snap.LockedUntil - now), Theme.Colors.Blue, order)
	end
end

----------------------------------------------------------------------
-- Links: Menü
----------------------------------------------------------------------
local function menuButton(
	parent: Frame,
	order: number,
	icon: string,
	text: string,
	color: Color3,
	onClick: () -> ()
): Components.Button
	local b = Components.button({
		Text = string.format('<font size="40">%s</font>\n%s', icon, text),
		Color = color,
		Size = UDim2.fromOffset(106, 94),
		TextSize = 17,
		LayoutOrder = order,
		Parent = parent,
		OnClick = onClick,
		Shine = true,
	})
	b.Label.LineHeight = 0.95
	return b
end

local function notificationDot(button: Components.Button): Frame
	local dot: Frame = Util.new("Frame", {
		Name = "Dot",
		Size = UDim2.fromOffset(26, 26),
		Position = UDim2.new(1, 4, 0, -4),
		AnchorPoint = Vector2.new(1, 0),
		BackgroundColor3 = Theme.Colors.Red,
		Visible = false,
		ZIndex = 5,
		Parent = button.Instance,
	}, { Util.round(), Util.stroke(Color3.new(1, 1, 1), 2) })
	Util.label({ Size = UDim2.fromScale(1, 1), Text = "!", TextSize = 18, ZIndex = 6, Parent = dot })
	return dot
end

local function buildSidebar(parent: Frame)
	-- 2x3-Raster: kompakt, damit es auf Handys nicht mit dem Joystick kollidiert
	local side: Frame = Util.new("Frame", {
		Name = "Sidebar",
		Size = UDim2.fromOffset(222, 310),
		Position = UDim2.new(0, 14, 0.5, -10),
		AnchorPoint = Vector2.new(0, 0.5),
		BackgroundTransparency = 1,
		Parent = parent,
	}, {
		Util.new("UIGridLayout", {
			CellSize = UDim2.fromOffset(106, 94),
			CellPadding = UDim2.fromOffset(10, 10),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	})

	menuButton(side, 1, "⬆️", "Upgrades", Theme.Colors.Gold, function()
		PanelManager.toggle("Upgrades")
	end)
	local managers = menuButton(side, 2, "👔", "Manager", Theme.Colors.Blue, function()
		PanelManager.toggle("Managers")
	end)
	local rebirth = menuButton(side, 3, "⭐", "Rebirth", Theme.Colors.Purple, function()
		PanelManager.toggle("Rebirth")
	end)
	menuButton(side, 4, "🛒", "Shop", Theme.Colors.Pink, function()
		PanelManager.toggle("Shop")
	end)
	local daily = menuButton(side, 5, "🎁", "Täglich", Theme.Colors.Green, function()
		PanelManager.toggle("Daily")
	end)
	menuButton(side, 6, "🐾", "Pets", Theme.Colors.Orange, function()
		PanelManager.toggle("Pets")
	end)

	menuDots.Managers = notificationDot(managers)
	menuDots.Rebirth = notificationDot(rebirth)
	menuDots.Daily = notificationDot(daily)
end

----------------------------------------------------------------------
-- Rechts: Aktionen
----------------------------------------------------------------------
local function buildActions(parent: Frame)
	local right: Frame = Util.new("Frame", {
		Name = "Actions",
		Size = UDim2.fromOffset(190, 200),
		Position = UDim2.new(1, -14, 0.5, -40),
		AnchorPoint = Vector2.new(1, 0.5),
		BackgroundTransparency = 1,
		Parent = parent,
	}, { Util.list(Enum.FillDirection.Vertical, 12, Enum.HorizontalAlignment.Right) })

	boostAllButton = Components.button({
		Text = "⚡ Alle boosten",
		Color = Theme.Colors.Gold,
		Size = UDim2.fromOffset(186, 62),
		TextSize = 20,
		LayoutOrder = 1,
		Parent = right,
		Sound = "Purchase",
		OnClick = function()
			local r = Remote.request("ActivateAll")
			if r.ok then
				boostAllButton.Pop()
			end
		end,
	})
	lockButton = Components.button({
		Text = "🔒 Abschließen",
		Color = Theme.Colors.Blue,
		Size = UDim2.fromOffset(186, 62),
		TextSize = 20,
		LayoutOrder = 2,
		Parent = right,
		OnClick = function()
			local r = Remote.request("LockBase")
			if r.ok then
				lockButton.Pop()
			end
		end,
	})
end

local function refreshActions(snap: Types.Snapshot)
	local now = Clock.now()
	local data = snap.Data
	local assigned, ready = 0, 0
	for _, m in data.Managers do
		if m.AssignedTo then
			assigned += 1
			if m.CooldownUntil <= now then
				ready += 1
			end
		end
	end
	boostAllButton.Instance.Visible = assigned > 0
	boostAllButton.SetEnabled(ready > 0)
	boostAllButton.SetText(if ready > 0 then string.format("⚡ Alle boosten (%d)", ready) else "⚡ Lädt...")
	menuDots.Managers.Visible = ready > 0

	if snap.LockedUntil > now then
		lockButton.SetEnabled(false)
		lockButton.SetText("🔒 " .. Formulas.formatDuration(snap.LockedUntil - now))
	elseif data.LockCooldownUntil > now then
		lockButton.SetEnabled(false)
		lockButton.SetText("⏳ " .. Formulas.formatDuration(data.LockCooldownUntil - now))
	else
		lockButton.SetEnabled(true)
		lockButton.SetText("🔒 Abschließen")
	end
	lockButton.Instance.Visible = Config.Steal.Enabled

	menuDots.Daily.Visible = snap.DailyAvailable
	menuDots.Rebirth.Visible = Formulas.rebirthPointsFor(data.RunCash) > 0
end

----------------------------------------------------------------------
-- Updates
----------------------------------------------------------------------
local function onSnapshot(snap: Types.Snapshot)
	local data = snap.Data
	targetCash = BigNum.from(data.Cash)
	if lastGems ~= data.Gems then
		if lastGems >= 0 and data.Gems > lastGems then
			Util.pop(gemsScale, 0.15)
		end
		lastGems = data.Gems
		gemsLabel.Text = "💎 " .. BigNum.format(BigNum.new(data.Gems))
	end
	rebirthLabel.Text =
		string.format("⭐ x%s", BigNum.format(BigNum.new(Formulas.rebirthMultiplier(data.RebirthPoints))))
	local income = Formulas.incomePerSecond(data, ClientState.context(), false)
	incomeLabel.Text = "+" .. BigNum.formatMoney(income, Config.CurrencySymbol) .. "/s"
	refreshChips(snap)
	refreshActions(snap)
end

--- Visuelles Feedback bei Verkauf (vom Effects-Controller aufgerufen)
function HUD.onSale(amount: BigNum)
	Util.pop(cashScale, 0.06)
	FloatingText.screen(
		"+" .. BigNum.formatMoney(amount, Config.CurrencySymbol),
		Theme.Colors.Money,
		HUD.cashPosition() + UDim2.fromOffset(math.random(-60, 60), 10),
		26
	)
end

function HUD.onSpend(amount: BigNum)
	FloatingText.screen(
		"-" .. BigNum.formatMoney(amount, Config.CurrencySymbol),
		Theme.Colors.Red,
		HUD.cashPosition() + UDim2.fromOffset(math.random(-40, 40), 10),
		22
	)
end

--- Großer, gut sichtbarer Button für die 2D-Minenansicht (unten Mitte)
local function buildCameraButton(parent: Frame, onCamera: () -> boolean, isActive: () -> boolean)
	local holder: Frame = Util.new("Frame", {
		Name = "CameraButton",
		Size = UDim2.fromOffset(270, 76),
		Position = UDim2.new(0.5, 0, 1, -14),
		AnchorPoint = Vector2.new(0.5, 1),
		BackgroundTransparency = 1,
		Parent = parent,
	})
	local pulse: UIScale = Util.new("UIScale", { Parent = holder })
	Anim.pulse(pulse, 0.04, 3)
	local button: Components.Button
	button = Components.button({
		Text = "🎥 2D-MINENANSICHT",
		Color = Theme.Colors.Cyan,
		Size = UDim2.fromScale(1, 1),
		TextSize = 22,
		Parent = holder,
		Shine = true,
		Rainbow = true,
		OnClick = function()
			local active = onCamera()
			button.SetText(if active then "⬅️ ZURÜCK ZUM SPIEL" else "🎥 2D-MINENANSICHT")
			button.SetColor(if active then Theme.Colors.Orange else Theme.Colors.Cyan)
		end,
	})
	-- Text aktuell halten (die Ansicht kann auch anders geschlossen werden)
	task.spawn(function()
		while holder.Parent do
			task.wait(0.3)
			local active = isActive()
			button.SetText(if active then "⬅️ ZURÜCK ZUM SPIEL" else "🎥 2D-MINENANSICHT")
			button.SetColor(if active then Theme.Colors.Orange else Theme.Colors.Cyan)
		end
	end)
end

function HUD.start(onCamera: () -> boolean, isCameraActive: () -> boolean)
	local hud = Root.layer("Hud")
	buildTopBar(hud)
	buildSidebar(hud)
	buildActions(hud)
	buildCameraButton(hud, onCamera, isCameraActive)

	ClientState.Changed:Connect(onSnapshot)
	if ClientState.Snapshot then
		onSnapshot(ClientState.Snapshot)
		displayedCash = BigNum.from(ClientState.Snapshot.Data.Cash)
	end

	-- Hochzählende Geldanzeige
	RunService.RenderStepped:Connect(function(dt)
		if not BigNum.eq(displayedCash, targetCash) then
			local alpha = 1 - math.exp(-dt * 10)
			local nextValue = BigNum.lerp(displayedCash, targetCash, alpha)
			-- einrasten, wenn fast gleich
			local diff = BigNum.abs(BigNum.sub(targetCash, nextValue))
			if BigNum.lt(diff, BigNum.max(BigNum.mulNum(BigNum.abs(targetCash), 0.0005), BigNum.new(0.5))) then
				nextValue = targetCash
			end
			displayedCash = nextValue
			cashLabel.Text = BigNum.formatMoney(BigNum.floor(displayedCash), Config.CurrencySymbol)
		end
	end)

	-- Timer in Chips/Buttons jede Sekunde aktualisieren
	task.spawn(function()
		while true do
			task.wait(1)
			local snap = ClientState.Snapshot
			if snap then
				refreshChips(snap)
				refreshActions(snap)
			end
		end
	end)
end

return HUD

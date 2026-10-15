--!strict
--[[
	ManagersPanel
	=============
	Übersichtlich in Reitern:
	  ⛏ Schächte | 🛗 Aufzug | 🏪 Händler | 📦 Reserve
	Jeder Stations-Reiter zeigt oben "Einstellen" (Preis + Chancen) und darunter
	jede Station: Manager mit Seltenheit, Fähigkeit (aktivieren) oder "Zuweisen".
	Die Reserve listet alle nicht zugewiesenen Manager (entlassen möglich).
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
local Popups = require(script.Parent.Parent.Popups)
local Theme = require(script.Parent.Parent.Theme)
local Util = require(script.Parent.Parent.Util)

type ManagerData = Types.ManagerData

local ManagersPanel = {}

local AREA_INFO: { [string]: { Name: string, Icon: string, Plural: string } } = {
	Shaft = { Name = "Schacht", Icon = "⛏", Plural = "Schächte" },
	Elevator = { Name = "Aufzug", Icon = "🛗", Plural = "Aufzug" },
	Warehouse = { Name = "Händler", Icon = "🏪", Plural = "Händler" },
}
local TABS = { "Shaft", "Elevator", "Warehouse", "Reserve" }

local window: Components.Window
local list: ScrollingFrame
local tabButtons: { [string]: Components.Button } = {}
local abilityButtons: { [string]: Components.Button } = {} -- ManagerId -> Button
local hireButton: Components.Button? = nil
local currentTab = "Shaft"
local expandedKey: string? = nil
local lastSignature = ""

local function money(b: BigNum.BigNum): string
	return BigNum.formatMoney(b, Config.CurrencySymbol)
end

local function stationName(key: string): string
	local area, index = Formulas.parseKey(key)
	if area == "Shaft" and index then
		return string.format("⛏ Ebene %d", index)
	end
	local info = AREA_INFO[area or "Shaft"]
	return info.Icon .. " " .. info.Name
end

----------------------------------------------------------------------
-- Bausteine
----------------------------------------------------------------------
local function rarityPill(parent: Instance, rarity: Config.RarityDef, position: UDim2)
	local pill: Frame = Util.new("Frame", {
		Size = UDim2.fromOffset(0, 26),
		AutomaticSize = Enum.AutomaticSize.X,
		Position = position,
		BackgroundColor3 = Color3.new(1, 1, 1),
		Parent = parent,
	}, {
		Util.round(),
		Util.gradient(Theme.lighten(rarity.Color, 0.2), Theme.darken(rarity.Color, 0.15)),
		Util.stroke(Color3.new(1, 1, 1), 1.5, 0.3),
		Util.padding(0, 10),
	})
	local l = Util.label({
		Size = UDim2.fromScale(0, 1),
		AutomaticSize = Enum.AutomaticSize.X,
		Text = rarity.Name,
		TextSize = 15,
		Parent = pill,
	})
	Util.textStroke(1).Parent = l
end

local function avatarBadge(parent: Instance, m: ManagerData, position: UDim2, size: number)
	local rarity = Formulas.rarityDef(m.Rarity)
	local badge: Frame = Util.new("Frame", {
		Size = UDim2.fromOffset(size, size),
		Position = position,
		BackgroundColor3 = Color3.new(1, 1, 1),
		Parent = parent,
	}, {
		Util.round(),
		Util.gradient(Theme.lighten(rarity.Color, 0.3), Theme.darken(rarity.Color, 0.2)),
		Util.stroke(rarity.Color, 3),
	})
	if m.FriendUserId then
		Util.new("ImageLabel", {
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			Image = string.format("rbxthumb://type=AvatarHeadShot&id=%d&w=150&h=150", m.FriendUserId),
			Parent = badge,
		}, { Util.round() })
	else
		Util.label({ Size = UDim2.fromScale(1, 1), Text = "👔", TextSize = size * 0.5, Parent = badge })
	end
end

--- Name + Seltenheit + Fähigkeit
local function managerText(parent: Instance, m: ManagerData, x: number, width: number)
	local rarity = Formulas.rarityDef(m.Rarity)
	local ability = Config.Managers.Abilities[m.Ability]
	local name = Util.label({
		Size = UDim2.fromOffset(width, 28),
		Position = UDim2.fromOffset(x, 10),
		Text = m.Name,
		Font = Theme.Fonts.Title,
		TextSize = 22,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		AutomaticSize = Enum.AutomaticSize.None,
		Parent = parent,
	})
	Util.textStroke(1.2).Parent = name
	rarityPill(parent, rarity, UDim2.fromOffset(x, 40))
	local abilityLabel = Util.label({
		Size = UDim2.fromOffset(width, 22),
		Position = UDim2.fromOffset(x, 70),
		Text = string.format(
			"%s %s: %s",
			ability and ability.Icon or "",
			ability and ability.Name or "",
			Formulas.abilityDescription(m)
		),
		TextSize = 16,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Parent = parent,
	})
	Util.textStroke(1).Parent = abilityLabel
end

----------------------------------------------------------------------
-- Inhalt der Reiter
----------------------------------------------------------------------
local function hireCard(area: string, order: number)
	local info = AREA_INFO[area]
	local card =
		Components.card({ Size = UDim2.new(1, 0, 0, 96), LayoutOrder = order, Parent = list }, Theme.Colors.Green)
	local title = Util.label({
		Size = UDim2.new(1, -300, 0, 32),
		Position = UDim2.fromOffset(18, 12),
		Text = info.Icon .. " " .. info.Name .. "-Manager einstellen",
		Font = Theme.Fonts.Title,
		TextSize = 23,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = card,
	})
	Util.textStroke(1.2).Parent = title
	local chances = {}
	local total = 0
	for _, r in Config.Managers.Rarities do
		total += r.Weight
	end
	for _, r in Config.Managers.Rarities do
		table.insert(
			chances,
			string.format(
				'<font color="#%s">%s %g%%</font>',
				r.Color:ToHex(),
				r.Name,
				math.floor(r.Weight / total * 1000 + 0.5) / 10
			)
		)
	end
	local chanceLabel = Util.label({
		Size = UDim2.new(1, -300, 0, 40),
		Position = UDim2.fromOffset(18, 48),
		Text = table.concat(chances, "  "),
		TextSize = 15,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = card,
	})
	Util.textStroke(1).Parent = chanceLabel
	hireButton = Components.button({
		Text = "",
		Color = Theme.Colors.Green,
		Size = UDim2.fromOffset(250, 72),
		Position = UDim2.new(1, -14, 0.5, 0),
		AnchorPoint = Vector2.new(1, 0.5),
		TextSize = 22,
		Sound = "Purchase",
		Parent = card,
		OnClick = function()
			Remote.send("HireManager", { Area = area })
		end,
	})
end

local function stationRow(data: Types.PlayerData, key: string, order: number)
	local manager = Formulas.managerFor(data, key)
	local accent = if manager then Formulas.rarityDef(manager.Rarity).Color else nil
	local card = Components.card({ Size = UDim2.new(1, 0, 0, 100), LayoutOrder = order * 100, Parent = list }, accent)
	local label = Util.label({
		Size = UDim2.fromOffset(140, 100),
		Position = UDim2.fromOffset(16, 0),
		Text = stationName(key),
		Font = Theme.Fonts.Title,
		TextSize = 21,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = card,
	})
	Util.textStroke(1.2).Parent = label

	if manager then
		avatarBadge(card, manager, UDim2.fromOffset(156, 16), 68)
		managerText(card, manager, 236, 250)
		local ability: Components.Button
		ability = Components.button({
			Text = "",
			Color = Theme.Colors.Gold,
			Size = UDim2.fromOffset(170, 66),
			Position = UDim2.new(1, -78, 0.5, 0),
			AnchorPoint = Vector2.new(1, 0.5),
			TextSize = 19,
			Parent = card,
			Sound = "Purchase",
			OnClick = function()
				local r = Remote.request("ActivateAbility", { ManagerId = manager.Id })
				if r.ok then
					ability.Pop()
				end
			end,
		})
		abilityButtons[manager.Id] = ability
		Components.button({
			Text = "↩",
			Color = Theme.Colors.CardLight,
			Size = UDim2.fromOffset(54, 54),
			Position = UDim2.new(1, -14, 0.5, 0),
			AnchorPoint = Vector2.new(1, 0.5),
			TextSize = 26,
			Parent = card,
			OnClick = function()
				Remote.send("UnassignManager", { ManagerId = manager.Id })
			end,
		})
		return
	end

	local area = Formulas.parseKey(key) or "Shaft"
	local hint = Util.label({
		Size = UDim2.fromOffset(280, 100),
		Position = UDim2.fromOffset(160, 0),
		Text = 'Kein Manager\n<font size="15">Du musst selbst tippen!</font>',
		TextSize = 20,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = card,
	})
	Util.textStroke(1).Parent = hint
	local candidates = {}
	for _, m in data.Managers do
		if m.Area == area and not m.AssignedTo then
			table.insert(candidates, m)
		end
	end
	if #candidates > 0 then
		Components.button({
			Text = if expandedKey == key then "Schließen" else string.format("Zuweisen (%d)", #candidates),
			Color = Theme.Colors.Blue,
			Size = UDim2.fromOffset(210, 66),
			Position = UDim2.new(1, -14, 0.5, 0),
			AnchorPoint = Vector2.new(1, 0.5),
			TextSize = 21,
			Parent = card,
			OnClick = function()
				expandedKey = if expandedKey == key then nil else key
				ManagersPanel.rebuild(true)
			end,
		})
	else
		local cost = Formulas.managerHireCost(data, area)
		local hire = Components.button({
			Text = "Einstellen\n" .. money(cost),
			Color = Theme.Colors.Green,
			Size = UDim2.fromOffset(210, 66),
			Position = UDim2.new(1, -14, 0.5, 0),
			AnchorPoint = Vector2.new(1, 0.5),
			TextSize = 19,
			Parent = card,
			Sound = "Purchase",
			OnClick = function()
				Remote.send("HireManager", { Area = area })
			end,
		})
		hire.SetEnabled(BigNum.gte(data.Cash, cost))
	end
	if expandedKey == key then
		table.sort(candidates, function(a, b)
			return Formulas.rarityIndex(a.Rarity) > Formulas.rarityIndex(b.Rarity)
		end)
		for i, m in candidates do
			local pick = Components.card({
				Size = UDim2.new(0.94, 0, 0, 100),
				LayoutOrder = order * 100 + i,
				Parent = list,
			}, Formulas.rarityDef(m.Rarity).Color)
			avatarBadge(pick, m, UDim2.fromOffset(14, 16), 68)
			managerText(pick, m, 94, 330)
			Components.button({
				Text = "✓ Zuweisen",
				Color = Theme.Colors.Green,
				Size = UDim2.fromOffset(170, 62),
				Position = UDim2.new(1, -14, 0.5, 0),
				AnchorPoint = Vector2.new(1, 0.5),
				TextSize = 20,
				Parent = pick,
				OnClick = function()
					expandedKey = nil
					Remote.send("AssignManager", { ManagerId = m.Id, Key = key })
				end,
			})
		end
	end
end

local function reserveRow(m: ManagerData, order: number)
	local card = Components.card({
		Size = UDim2.new(1, 0, 0, 100),
		LayoutOrder = order,
		Parent = list,
	}, Formulas.rarityDef(m.Rarity).Color)
	avatarBadge(card, m, UDim2.fromOffset(14, 16), 68)
	managerText(card, m, 94, 360)
	local info = AREA_INFO[m.Area]
	local areaLabel = Util.label({
		Size = UDim2.fromOffset(150, 24),
		Position = UDim2.new(1, -170, 0, 12),
		Text = info.Icon .. " " .. info.Name,
		TextSize = 16,
		Parent = card,
	})
	Util.textStroke(1).Parent = areaLabel
	Components.button({
		Text = "Entlassen",
		Color = Theme.Colors.Red,
		Size = UDim2.fromOffset(150, 48),
		Position = UDim2.new(1, -14, 1, -12),
		AnchorPoint = Vector2.new(1, 1),
		TextSize = 18,
		Parent = card,
		OnClick = function()
			Popups.confirm(
				string.format("%s wirklich entlassen?\nDas kann nicht rückgängig gemacht werden.", m.Name),
				function()
					Remote.send("FireManager", { ManagerId = m.Id })
				end
			)
		end,
	})
end

local function emptyHint(text: string, order: number)
	local l = Util.label({
		Size = UDim2.new(1, 0, 0, 80),
		LayoutOrder = order,
		Text = text,
		TextSize = 19,
		TextWrapped = true,
		Parent = list,
	})
	Util.textStroke(1).Parent = l
end

----------------------------------------------------------------------
-- Aufbau / Aktualisierung
----------------------------------------------------------------------
local function reserveCount(data: Types.PlayerData): number
	local n = 0
	for _, m in data.Managers do
		if not m.AssignedTo then
			n += 1
		end
	end
	return n
end

local function signature(data: Types.PlayerData): string
	local parts = { currentTab, tostring(#data.Shafts), tostring(expandedKey) }
	for _, m in data.Managers do
		table.insert(parts, m.Id .. ":" .. tostring(m.AssignedTo))
	end
	-- Einstell-Buttons in freien Zeilen hängen vom Geld ab: grob mitnehmen
	table.insert(parts, tostring(math.floor(BigNum.log10(BigNum.add(data.Cash, BigNum.one())) * 4)))
	return table.concat(parts, "|")
end

local function updateDynamic()
	local snap = ClientState.Snapshot
	if not snap then
		return
	end
	local data = snap.Data
	local now = Clock.now()
	for id, button in abilityButtons do
		local m = Formulas.findManager(data, id)
		if m then
			local def = Config.Managers.Abilities[m.Ability]
			if m.ActiveUntil > now then
				button.SetText("✨ Aktiv\n" .. Formulas.formatDuration(m.ActiveUntil - now))
				button.SetEnabled(false)
			elseif m.CooldownUntil > now then
				button.SetText("⏳ Lädt\n" .. Formulas.formatDuration(m.CooldownUntil - now))
				button.SetEnabled(false)
			else
				button.SetText((def and def.Icon or "⚡") .. " " .. (def and def.Name or "Boost") .. "\nAKTIVIEREN")
				button.SetEnabled(true)
			end
		end
	end
	if hireButton and AREA_INFO[currentTab] then
		local cost = Formulas.managerHireCost(data, currentTab)
		local full = #data.Managers >= Config.Managers.MaxOwned
		hireButton.SetText(if full then "Reserve voll" else "Einstellen\n" .. money(cost))
		hireButton.SetEnabled(not full and BigNum.gte(data.Cash, cost))
	end
	for tab, b in tabButtons do
		b.SetColor(if tab == currentTab then Theme.Colors.Selected else Theme.Colors.CardLight)
	end
	local reserve = tabButtons.Reserve
	if reserve then
		reserve.SetText(string.format("📦 Reserve (%d)", reserveCount(data)))
	end
end

function ManagersPanel.rebuild(force: boolean?)
	local snap = ClientState.Snapshot
	if not snap then
		return
	end
	local data = snap.Data
	local sig = signature(data)
	if not force and sig == lastSignature then
		updateDynamic()
		return
	end
	lastSignature = sig
	for _, child in list:GetChildren() do
		if not child:IsA("UIListLayout") and not child:IsA("UIPadding") then
			child:Destroy()
		end
	end
	table.clear(abilityButtons)
	hireButton = nil

	if currentTab == "Reserve" then
		local reserve = {}
		for _, m in data.Managers do
			if not m.AssignedTo then
				table.insert(reserve, m)
			end
		end
		table.sort(reserve, function(a, b)
			return Formulas.rarityIndex(a.Rarity) > Formulas.rarityIndex(b.Rarity)
		end)
		if #reserve == 0 then
			emptyHint("Keine Manager in der Reserve.\nNeue Manager werden automatisch freien Stationen zugewiesen.", 1)
		end
		for i, m in reserve do
			reserveRow(m, i)
		end
	else
		hireCard(currentTab, 0)
		if currentTab == "Shaft" then
			for i = 1, #data.Shafts do
				stationRow(data, Formulas.shaftKey(i), i)
			end
		else
			stationRow(data, currentTab, 1)
		end
	end
	updateDynamic()
end

function ManagersPanel.start()
	window = Components.window("Manager", "👔", Theme.Colors.Blue, Vector2.new(900, 600), function()
		PanelManager.close()
	end)

	local tabBar: Frame = Util.new("Frame", {
		Size = UDim2.new(1, 0, 0, 58),
		BackgroundTransparency = 1,
		Parent = window.Content,
	}, { Util.list(Enum.FillDirection.Horizontal, 8, Enum.HorizontalAlignment.Left) })
	for i, tab in TABS do
		local info = AREA_INFO[tab]
		tabButtons[tab] = Components.button({
			Text = if info then info.Icon .. " " .. info.Plural else "📦 Reserve",
			Color = Theme.Colors.CardLight,
			Size = UDim2.fromOffset(200, 54),
			TextSize = 20,
			LayoutOrder = i,
			Parent = tabBar,
			OnClick = function()
				currentTab = tab
				expandedKey = nil
				ManagersPanel.rebuild(true)
			end,
		})
	end

	list = Components.scrollList({
		Size = UDim2.new(1, 0, 1, -68),
		Position = UDim2.fromOffset(0, 68),
		Parent = window.Content,
	}, 10)

	PanelManager.register("Managers", window, function()
		expandedKey = nil
		ManagersPanel.rebuild(true)
	end)

	ClientState.Changed:Connect(function()
		if PanelManager.isOpen("Managers") then
			ManagersPanel.rebuild(false)
		end
	end)
	task.spawn(function()
		while true do
			task.wait(1)
			if PanelManager.isOpen("Managers") then
				updateDynamic()
			end
		end
	end)
end

return ManagersPanel

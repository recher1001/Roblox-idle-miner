--!strict
--[[
	ManagersPanel
	=============
	Oben:   Manager einstellen (Schacht / Aufzug / Händler) mit Preis
	Liste:  jede Station mit ihrem Manager (Fähigkeit aktivieren, abziehen)
	        oder "Zuweisen" aus der Reserve
	Reserve: nicht zugewiesene Manager (entlassen)
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

local AREA_INFO: { [string]: { Name: string, Icon: string } } = {
	Shaft = { Name = "Schacht", Icon = "⛏" },
	Elevator = { Name = "Aufzug", Icon = "🛗" },
	Warehouse = { Name = "Händler", Icon = "🏪" },
}
local AREA_ORDER = { "Warehouse", "Elevator", "Shaft" }

local window: Components.Window
local list: ScrollingFrame
local hireButtons: { [string]: Components.Button } = {}
local abilityButtons: { [string]: Components.Button } = {} -- ManagerId -> Button
local expandedKey: string? = nil
local lastSignature = ""

local function money(b: BigNum.BigNum): string
	return BigNum.formatMoney(b, Config.CurrencySymbol)
end

local function areaOf(key: string): string
	local area = Formulas.parseKey(key)
	return area or "Shaft"
end

----------------------------------------------------------------------
-- Manager-Karte (Inhalt)
----------------------------------------------------------------------
local function managerInfo(parent: Instance, m: ManagerData, position: UDim2, width: number)
	local rarity = Formulas.rarityDef(m.Rarity)
	local ability = Config.Managers.Abilities[m.Ability]
	local badge: Frame = Util.new("Frame", {
		Size = UDim2.fromOffset(56, 56),
		Position = position,
		BackgroundColor3 = Color3.new(1, 1, 1),
		Parent = parent,
	}, {
		Util.round(),
		Util.gradient(Theme.lighten(rarity.Color, 0.25), Theme.darken(rarity.Color, 0.35)),
		Util.stroke(Color3.new(1, 1, 1), 2, 0.4),
	})
	if m.FriendUserId then
		-- Kopfbild des Freundes (rbxthumb lädt ohne API-Aufruf)
		Util.new("ImageLabel", {
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			Image = string.format("rbxthumb://type=AvatarHeadShot&id=%d&w=150&h=150", m.FriendUserId),
			Parent = badge,
		}, { Util.round() })
	else
		Util.label({ Size = UDim2.fromScale(1, 1), Text = "👔", TextSize = 30, Parent = badge })
	end
	local name = Util.label({
		Size = UDim2.fromOffset(width - 66, 26),
		Position = position + UDim2.fromOffset(66, 0),
		Text = string.format('%s  <font color="#%s">%s</font>', m.Name, rarity.Color:ToHex(), rarity.Name),
		Font = Theme.Fonts.Title,
		TextSize = 20,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = parent,
	})
	Util.textStroke(1).Parent = name
	Util.label({
		Size = UDim2.fromOffset(width - 66, 22),
		Position = position + UDim2.fromOffset(66, 28),
		Text = string.format(
			"%s %s: %s  •  Tempo x%.2f",
			ability and ability.Icon or "",
			ability and ability.Name or "",
			Formulas.abilityDescription(m),
			rarity.PassiveSpeed
		),
		TextSize = 15,
		TextColor3 = Theme.Colors.SubText,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Parent = parent,
	})
end

----------------------------------------------------------------------
-- Zeilen
----------------------------------------------------------------------
local function stationRow(data: Types.PlayerData, key: string, order: number)
	local manager = Formulas.managerFor(data, key)
	local accent = if manager then Formulas.rarityDef(manager.Rarity).Color else nil
	local card = Components.card({ Size = UDim2.new(1, 0, 0, 82), LayoutOrder = order * 100, Parent = list }, accent)
	local area = areaOf(key)
	local stationLabel = Util.label({
		Size = UDim2.fromOffset(150, 82),
		Position = UDim2.fromOffset(14, 0),
		Text = AREA_INFO[area].Icon .. " " .. (if area == "Shaft"
			then "Ebene " .. tostring(select(2, Formulas.parseKey(key)))
			else AREA_INFO[area].Name),
		Font = Theme.Fonts.Title,
		TextSize = 20,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = card,
	})
	Util.textStroke(1).Parent = stationLabel

	if manager then
		managerInfo(card, manager, UDim2.fromOffset(160, 13), 330)
		local ability: Components.Button
		ability = Components.button({
			Text = "",
			Color = Theme.Colors.Gold,
			Size = UDim2.fromOffset(150, 56),
			Position = UDim2.new(1, -72, 0.5, 0),
			AnchorPoint = Vector2.new(1, 0.5),
			TextSize = 17,
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
			Size = UDim2.fromOffset(52, 52),
			Position = UDim2.new(1, -12, 0.5, 0),
			AnchorPoint = Vector2.new(1, 0.5),
			TextSize = 24,
			Parent = card,
			OnClick = function()
				Remote.send("UnassignManager", { ManagerId = manager.Id })
			end,
		})
	else
		Util.label({
			Size = UDim2.fromOffset(260, 82),
			Position = UDim2.fromOffset(160, 0),
			Text = "Kein Manager - du musst selbst tippen!",
			TextSize = 15,
			TextColor3 = Theme.Colors.Muted,
			TextXAlignment = Enum.TextXAlignment.Left,
			Parent = card,
		})
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
				Size = UDim2.fromOffset(190, 56),
				Position = UDim2.new(1, -12, 0.5, 0),
				AnchorPoint = Vector2.new(1, 0.5),
				TextSize = 18,
				Parent = card,
				OnClick = function()
					expandedKey = if expandedKey == key then nil else key
					ManagersPanel.rebuild(true)
				end,
			})
		else
			local cost = Formulas.managerHireCost(data, area)
			local hire = Components.button({
				Text = "Einstellen " .. money(cost),
				Color = Theme.Colors.Green,
				Size = UDim2.fromOffset(220, 56),
				Position = UDim2.new(1, -12, 0.5, 0),
				AnchorPoint = Vector2.new(1, 0.5),
				TextSize = 17,
				Parent = card,
				OnClick = function()
					Remote.send("HireManager", { Area = area })
				end,
			})
			hire.SetEnabled(BigNum.gte(data.Cash, cost))
		end
		-- Auswahl der Reserve-Manager
		if expandedKey == key then
			for i, m in candidates do
				local pick =
					Components.card({ Size = UDim2.new(0.94, 0, 0, 76), LayoutOrder = order * 100 + i, Parent = list })
				managerInfo(pick, m, UDim2.fromOffset(12, 10), 420)
				Components.button({
					Text = "Zuweisen",
					Color = Theme.Colors.Green,
					Size = UDim2.fromOffset(150, 52),
					Position = UDim2.new(1, -12, 0.5, 0),
					AnchorPoint = Vector2.new(1, 0.5),
					TextSize = 18,
					Parent = pick,
					OnClick = function()
						expandedKey = nil
						Remote.send("AssignManager", { ManagerId = m.Id, Key = key })
					end,
				})
			end
		end
	end
end

local function sectionTitle(text: string, order: number)
	local l = Util.label({
		Size = UDim2.new(1, 0, 0, 34),
		LayoutOrder = order * 100,
		Text = text,
		Font = Theme.Fonts.Title,
		TextSize = 22,
		TextColor3 = Theme.Colors.Gold,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = list,
	})
	Util.textStroke(1).Parent = l
end

local function reserveRow(m: ManagerData, order: number)
	local card = Components.card({ Size = UDim2.new(1, 0, 0, 76), LayoutOrder = order * 100, Parent = list })
	managerInfo(card, m, UDim2.fromOffset(12, 10), 460)
	Util.label({
		Size = UDim2.fromOffset(120, 20),
		Position = UDim2.new(1, -150, 0, 6),
		Text = AREA_INFO[m.Area].Icon .. " " .. AREA_INFO[m.Area].Name,
		TextSize = 14,
		TextColor3 = Theme.Colors.Muted,
		Parent = card,
	})
	Components.button({
		Text = "Entlassen",
		Color = Theme.Colors.Red,
		Size = UDim2.fromOffset(130, 44),
		Position = UDim2.new(1, -12, 1, -10),
		AnchorPoint = Vector2.new(1, 1),
		TextSize = 16,
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

----------------------------------------------------------------------
-- Aufbau / Aktualisierung
----------------------------------------------------------------------
local function signature(data: Types.PlayerData): string
	local parts = { tostring(#data.Shafts), tostring(expandedKey) }
	for _, m in data.Managers do
		table.insert(parts, m.Id .. ":" .. tostring(m.AssignedTo))
	end
	-- Einstell-Buttons in freien Zeilen hängen vom Geld ab: grob mitnehmen
	table.insert(parts, tostring(math.floor(BigNum.log10(BigNum.add(data.Cash, BigNum.one())) * 4)))
	return table.concat(parts, "|")
end

local function updateAbilityButtons()
	local snap = ClientState.Snapshot
	if not snap then
		return
	end
	local now = Clock.now()
	for id, button in abilityButtons do
		local m = Formulas.findManager(snap.Data, id)
		if m then
			local def = Config.Managers.Abilities[m.Ability]
			if m.ActiveUntil > now then
				button.SetText("✨ " .. Formulas.formatDuration(m.ActiveUntil - now))
				button.SetEnabled(false)
			elseif m.CooldownUntil > now then
				button.SetText("⏳ " .. Formulas.formatDuration(m.CooldownUntil - now))
				button.SetEnabled(false)
			else
				button.SetText((def and def.Icon or "⚡") .. " " .. (def and def.Name or "Boost"))
				button.SetEnabled(true)
			end
		end
	end
	for area, button in hireButtons do
		local cost = Formulas.managerHireCost(snap.Data, area)
		button.SetText(string.format("%s %s\n%s", AREA_INFO[area].Icon, AREA_INFO[area].Name, money(cost)))
		button.SetEnabled(BigNum.gte(snap.Data.Cash, cost) and #snap.Data.Managers < Config.Managers.MaxOwned)
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
		updateAbilityButtons()
		return
	end
	lastSignature = sig
	for _, child in list:GetChildren() do
		if not child:IsA("UIListLayout") and not child:IsA("UIPadding") then
			child:Destroy()
		end
	end
	table.clear(abilityButtons)

	local order = 0
	sectionTitle("Stationen", order)
	order += 1
	stationRow(data, "Warehouse", order)
	order += 1
	stationRow(data, "Elevator", order)
	for i = 1, #data.Shafts do
		order += 1
		stationRow(data, Formulas.shaftKey(i), order)
	end

	local reserve = {}
	for _, m in data.Managers do
		if not m.AssignedTo then
			table.insert(reserve, m)
		end
	end
	if #reserve > 0 then
		order += 1
		sectionTitle(string.format("Reserve (%d)", #reserve), order)
		table.sort(reserve, function(a, b)
			return Formulas.rarityIndex(a.Rarity) > Formulas.rarityIndex(b.Rarity)
		end)
		for _, m in reserve do
			order += 1
			reserveRow(m, order)
		end
	end
	updateAbilityButtons()
end

function ManagersPanel.start()
	window = Components.window("Manager", "👔", Theme.Colors.Blue, Vector2.new(860, 580), function()
		PanelManager.close()
	end)

	-- Einstellen-Leiste
	local hireBar: Frame = Util.new("Frame", {
		Size = UDim2.new(1, 0, 0, 74),
		BackgroundTransparency = 1,
		Parent = window.Content,
	}, { Util.list(Enum.FillDirection.Horizontal, 10) })
	for i, area in AREA_ORDER do
		hireButtons[area] = Components.button({
			Text = "",
			Color = Theme.Colors.Green,
			Size = UDim2.fromOffset(250, 68),
			TextSize = 18,
			LayoutOrder = i,
			Parent = hireBar,
			Sound = "Purchase",
			OnClick = function()
				Remote.send("HireManager", { Area = area })
			end,
		})
	end
	-- Chancen-Info
	local chances = {}
	local total = 0
	for _, r in Config.Managers.Rarities do
		total += r.Weight
	end
	for _, r in Config.Managers.Rarities do
		table.insert(
			chances,
			string.format('<font color="#%s">%s %.1f%%</font>', r.Color:ToHex(), r.Name, r.Weight / total * 100)
		)
	end
	Util.label({
		Size = UDim2.new(1, 0, 0, 22),
		Position = UDim2.fromOffset(0, 76),
		Text = "Chancen: " .. table.concat(chances, "  "),
		TextSize = 15,
		TextColor3 = Theme.Colors.SubText,
		Parent = window.Content,
	})

	list = Components.scrollList({
		Size = UDim2.new(1, 0, 1, -104),
		Position = UDim2.fromOffset(0, 104),
		Parent = window.Content,
	}, 8)

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
				updateAbilityButtons()
			end
		end
	end)
end

return ManagersPanel

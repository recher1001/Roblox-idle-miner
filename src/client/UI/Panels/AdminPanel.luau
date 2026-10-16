--!strict
--[[
	AdminPanel
	==========
	Admin-Menü (Button "🛠 Admin" unten links) - nur sichtbar für den Owner und
	für Admins. Der Server prüft jede Aktion erneut, der Client zeigt nur an.

	Reiter:
	  🎯 Spieler - Ziel wählen, Geld/Gems geben oder wegnehmen, Fortschritt, Kick, Reset
	  ⚡ Kräfte  - OP-Kräfte geben/wegnehmen (Teppich, Speed, Sprung, ...)
	  🌍 Server  - Events starten
	  👑 Admins  - (nur Owner) Admins ernennen und einzelne Rechte einstellen
]]

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local BigNum = require(Shared.BigNum)
local Config = require(Shared.Config)
local Types = require(Shared.Types)

local ClientState = require(script.Parent.Parent.Parent.ClientState)
local Remote = require(script.Parent.Parent.Parent.Remote)
local Components = require(script.Parent.Parent.Components)
local PanelManager = require(script.Parent.Parent.PanelManager)
local Popups = require(script.Parent.Parent.Popups)
local Root = require(script.Parent.Parent.Root)
local Theme = require(script.Parent.Parent.Theme)
local Util = require(script.Parent.Parent.Util)

local AdminPanel = {}

local TABS = {
	{ Id = "Player", Text = "🎯 Spieler" },
	{ Id = "Powers", Text = "⚡ Kräfte" },
	{ Id = "Server", Text = "🌍 Server" },
	{ Id = "Admins", Text = "👑 Admins" },
}

local localPlayer = Players.LocalPlayer

local window: Components.Window
local openButton: Components.Button
local tabButtons: { [string]: Components.Button } = {}
local targetBar: ScrollingFrame
local list: ScrollingFrame
local currentTab = "Player"
local targetUserId: number = localPlayer.UserId
local targetInfo: { [string]: any }? = nil

local function admin(): Types.AdminInfo?
	local snap = ClientState.Snapshot
	return if snap then snap.Admin else nil
end

local function can(perm: string): boolean
	local info = admin()
	return info ~= nil and info.Permissions[perm] == true
end

----------------------------------------------------------------------
-- Bausteine
----------------------------------------------------------------------
local function clearList()
	for _, child in list:GetChildren() do
		if not child:IsA("UIListLayout") and not child:IsA("UIPadding") then
			child:Destroy()
		end
	end
end

local order = 0
local function nextOrder(): number
	order += 1
	return order
end

local function section(text: string)
	local l = Util.label({
		Size = UDim2.new(1, 0, 0, 34),
		LayoutOrder = nextOrder(),
		Text = text,
		Font = Theme.Fonts.Title,
		TextSize = 23,
		TextColor3 = Theme.Colors.Gold,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = list,
	})
	Util.textStroke(1.2).Parent = l
end

local function buttonGrid(): Frame
	return Util.new("Frame", {
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		LayoutOrder = nextOrder(),
		Parent = list,
	}, {
		Util.new("UIGridLayout", {
			CellSize = UDim2.fromOffset(196, 60),
			CellPadding = UDim2.fromOffset(10, 10),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	})
end

local function actionButton(grid: Frame, text: string, color: Color3, action: string, value: string?, confirm: string?)
	Components.button({
		Text = text,
		Color = color,
		Size = UDim2.fromOffset(196, 60),
		TextSize = 19,
		Parent = grid,
		OnClick = function()
			local function run()
				Remote.send("AdminAction", { Action = action, Target = targetUserId, Value = value or "" }, function(r)
					if r.ok then
						AdminPanel.refreshTarget()
					end
				end)
			end
			if confirm then
				Popups.confirm(confirm, run)
			else
				run()
			end
		end,
	})
end

local function infoLine(text: string)
	local l = Util.label({
		Size = UDim2.new(1, 0, 0, 30),
		LayoutOrder = nextOrder(),
		Text = text,
		TextSize = 18,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = list,
	})
	Util.textStroke(1).Parent = l
end

----------------------------------------------------------------------
-- Ziel-Auswahl
----------------------------------------------------------------------
local function rebuildTargets()
	for _, child in targetBar:GetChildren() do
		if child:IsA("GuiButton") then
			child:Destroy()
		end
	end
	if not Players:GetPlayerByUserId(targetUserId) then
		targetUserId = localPlayer.UserId
	end
	for i, p in Players:GetPlayers() do
		local selected = p.UserId == targetUserId
		local b = Components.button({
			Text = (if p == localPlayer then "🙂 Ich" else p.DisplayName),
			Color = if selected then Theme.Colors.Selected else Theme.Colors.CardLight,
			Size = UDim2.fromOffset(170, 50),
			TextSize = 18,
			LayoutOrder = if p == localPlayer then 0 else i,
			Parent = targetBar,
			OnClick = function()
				targetUserId = p.UserId
				rebuildTargets()
				AdminPanel.refreshTarget()
			end,
		})
		b.Label.TextTruncate = Enum.TextTruncate.AtEnd
	end
end

----------------------------------------------------------------------
-- Reiter-Inhalte
----------------------------------------------------------------------
local function buildPlayerTab()
	local info = targetInfo
	if info then
		infoLine(
			string.format(
				"%s%s  •  💰 %s  •  💎 %s  •  ⭐ %d Rebirths  •  ⛏ %d Ebenen",
				if info.IsOwner then "👑 " else "",
				tostring(info.Name),
				BigNum.formatMoney(BigNum.from(info.Cash), Config.CurrencySymbol),
				BigNum.format(BigNum.new(tonumber(info.Gems) or 0)),
				tonumber(info.Rebirths) or 0,
				tonumber(info.Shafts) or 1
			)
		)
	end
	local any = false
	if can("Cash") then
		any = true
		section("💰 Geld")
		local g = buttonGrid()
		actionButton(g, "+$1K", Theme.Colors.Green, "cash", "1000")
		actionButton(g, "+$1M", Theme.Colors.Green, "cash", "1e6")
		actionButton(g, "+$1B", Theme.Colors.Green, "cash", "1e9")
		actionButton(g, "+$1T", Theme.Colors.Green, "cash", "1e12")
		actionButton(g, "Geld x1000", Theme.Colors.Gold, "multcash", "1000")
		actionButton(g, "Geld halbieren", Theme.Colors.Orange, "halfcash")
		actionButton(g, "Geld auf 0", Theme.Colors.Red, "zerocash", nil, "Wirklich das ganze Geld wegnehmen?")
	end
	if can("Gems") then
		any = true
		section("💎 Gems")
		local g = buttonGrid()
		actionButton(g, "+100 💎", Theme.Colors.Purple, "gems", "100")
		actionButton(g, "+1000 💎", Theme.Colors.Purple, "gems", "1000")
		actionButton(g, "Gems auf 0", Theme.Colors.Red, "zerogems", nil, "Wirklich alle Gems wegnehmen?")
	end
	if can("Progress") then
		any = true
		section("🔓 Fortschritt")
		local g = buttonGrid()
		actionButton(g, "🔓 Alle Ebenen", Theme.Colors.Blue, "unlockall")
		actionButton(g, "👔 Manager überall", Theme.Colors.Blue, "managers")
		actionButton(g, "⏱ Cooldowns weg", Theme.Colors.Blue, "cooldowns")
		actionButton(g, "🎁 Daily neu", Theme.Colors.Pink, "daily")
		actionButton(g, "🌙 Offline 2h", Theme.Colors.Pink, "offline", "7200")
	end
	if can("Kick") or can("Reset") then
		any = true
		section("🛡 Moderation")
		local g = buttonGrid()
		if can("Kick") then
			actionButton(g, "👢 Kicken", Theme.Colors.Red, "kick", nil, "Diesen Spieler wirklich kicken?")
		end
		if can("Reset") then
			actionButton(
				g,
				"♻ Spielstand zurücksetzen",
				Theme.Colors.Red,
				"reset",
				nil,
				"Spielstand dieses Spielers wirklich komplett zurücksetzen?\nDas wird gespeichert!"
			)
		end
	end
	if not any then
		infoLine("Du hast keine Rechte für diesen Bereich.")
	end
end

local function buildPowersTab()
	if not can("Powers") then
		infoLine("Du hast keine Berechtigung, Kräfte zu vergeben.")
		return
	end
	local powers = if targetInfo and type(targetInfo.Powers) == "table" then targetInfo.Powers else {}
	section("⚡ OP-Kräfte" .. (if targetInfo then " für " .. tostring(targetInfo.Name) else ""))
	for _, def in Config.Admin.Powers do
		local has = powers[def.Id] == true
		local card = Components.card({
			Size = UDim2.new(1, 0, 0, 84),
			LayoutOrder = nextOrder(),
			Parent = list,
		}, if has then Theme.Colors.Green else nil)
		Components.icon(def.Icon, 62, if has then Theme.Colors.Green else Theme.Colors.Purple, {
			Position = UDim2.new(0, 12, 0.5, 0),
			AnchorPoint = Vector2.new(0, 0.5),
			Parent = card,
		})
		local name = Util.label({
			Size = UDim2.new(1, -320, 0, 30),
			Position = UDim2.fromOffset(84, 12),
			Text = def.Name,
			Font = Theme.Fonts.Title,
			TextSize = 23,
			TextXAlignment = Enum.TextXAlignment.Left,
			Parent = card,
		})
		Util.textStroke(1.2).Parent = name
		local desc = Util.label({
			Size = UDim2.new(1, -320, 0, 26),
			Position = UDim2.fromOffset(84, 46),
			Text = def.Description,
			TextSize = 16,
			TextXAlignment = Enum.TextXAlignment.Left,
			Parent = card,
		})
		Util.textStroke(1).Parent = desc
		Components.button({
			Text = if has then "✓ AN  (wegnehmen)" else "AUS  (geben)",
			Color = if has then Theme.Colors.Green else Theme.Colors.CardLight,
			Size = UDim2.fromOffset(220, 60),
			Position = UDim2.new(1, -14, 0.5, 0),
			AnchorPoint = Vector2.new(1, 0.5),
			TextSize = 18,
			Parent = card,
			OnClick = function()
				Remote.send(
					"AdminAction",
					{ Action = if has then "powertake" else "powergive", Target = targetUserId, Value = def.Id },
					function(r)
						if r.ok then
							AdminPanel.refreshTarget()
						end
					end
				)
			end,
		})
	end
end

local function buildServerTab()
	if not can("Events") then
		infoLine("Du hast keine Berechtigung, Events zu starten.")
		return
	end
	section("🔥 Events (für alle Spieler)")
	local g = buttonGrid()
	for _, e in Config.Events.List do
		actionButton(g, e.Name, Theme.Colors.Orange, "event", e.Id)
	end
end

local function permissionToggles(parent: Frame, userId: number, perms: { [string]: boolean })
	local grid: Frame = Util.new("Frame", {
		Size = UDim2.new(1, -24, 0, 0),
		Position = UDim2.fromOffset(12, 58),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		Parent = parent,
	}, {
		Util.new("UIGridLayout", {
			CellSize = UDim2.fromOffset(268, 46),
			CellPadding = UDim2.fromOffset(8, 8),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	})
	for i, p in Config.Admin.Permissions do
		local on = perms[p.Id] == true
		Components.button({
			Text = string.format("%s %s %s", if on then "✅" else "⬜", p.Icon, p.Name),
			Color = if on then Theme.Colors.Green else Theme.Colors.CardLight,
			Size = UDim2.fromOffset(268, 46),
			TextSize = 16,
			LayoutOrder = i,
			Parent = grid,
			OnClick = function()
				Remote.send("AdminSetPerm", { UserId = userId, Perm = p.Id, On = not on })
			end,
		})
	end
end

local function buildAdminsTab()
	local info = admin()
	if not info or not info.IsOwner then
		infoLine("Nur der Owner kann Admins verwalten. 👑")
		return
	end
	local adminList: { Types.AdminEntry } = info.Admins or {}
	local byId: { [number]: Types.AdminEntry } = {}
	for _, entry in adminList do
		byId[entry.UserId] = entry
	end

	section("👥 Spieler auf diesem Server")
	local others = 0
	for _, p in Players:GetPlayers() do
		if p ~= localPlayer then
			others += 1
			local entry = byId[p.UserId]
			local card = Components.card({
				Size = UDim2.new(1, 0, 0, if entry then 230 else 70),
				LayoutOrder = nextOrder(),
				Parent = list,
			}, if entry then Theme.Colors.Gold else nil)
			local name = Util.label({
				Size = UDim2.new(1, -260, 0, 50),
				Position = UDim2.fromOffset(16, 6),
				Text = (if entry then "👑 " else "🙂 ") .. p.DisplayName .. "  (@" .. p.Name .. ")",
				Font = Theme.Fonts.Title,
				TextSize = 22,
				TextXAlignment = Enum.TextXAlignment.Left,
				TextTruncate = Enum.TextTruncate.AtEnd,
				Parent = card,
			})
			Util.textStroke(1.2).Parent = name
			Components.button({
				Text = if entry then "Admin entfernen" else "Zum Admin machen",
				Color = if entry then Theme.Colors.Red else Theme.Colors.Green,
				Size = UDim2.fromOffset(230, 50),
				Position = UDim2.new(1, -12, 0, 8),
				AnchorPoint = Vector2.new(1, 0),
				TextSize = 18,
				Parent = card,
				OnClick = function()
					Remote.send("AdminSetAdmin", { UserId = p.UserId, Name = p.Name, On = entry == nil })
				end,
			})
			if entry then
				permissionToggles(card, p.UserId, entry.Permissions)
			end
		end
	end
	if others == 0 then
		infoLine("Keine anderen Spieler auf dem Server. Lade Freunde ein, um sie zum Admin zu machen!")
	end

	-- Gespeicherte Admins, die gerade nicht online sind
	local offline = {}
	for _, entry in adminList do
		if not Players:GetPlayerByUserId(entry.UserId) then
			table.insert(offline, entry)
		end
	end
	if #offline > 0 then
		section("💤 Admins (gerade offline)")
		for _, entry in offline do
			local card = Components.card({ Size = UDim2.new(1, 0, 0, 230), LayoutOrder = nextOrder(), Parent = list })
			local name = Util.label({
				Size = UDim2.new(1, -260, 0, 50),
				Position = UDim2.fromOffset(16, 6),
				Text = "👑 @" .. entry.Name,
				Font = Theme.Fonts.Title,
				TextSize = 22,
				TextXAlignment = Enum.TextXAlignment.Left,
				Parent = card,
			})
			Util.textStroke(1.2).Parent = name
			Components.button({
				Text = "Admin entfernen",
				Color = Theme.Colors.Red,
				Size = UDim2.fromOffset(230, 50),
				Position = UDim2.new(1, -12, 0, 8),
				AnchorPoint = Vector2.new(1, 0),
				TextSize = 18,
				Parent = card,
				OnClick = function()
					Remote.send("AdminSetAdmin", { UserId = entry.UserId, Name = entry.Name, On = false })
				end,
			})
			permissionToggles(card, entry.UserId, entry.Permissions)
		end
	end
end

----------------------------------------------------------------------
-- Aufbau
----------------------------------------------------------------------
local function rebuild()
	if not PanelManager.isOpen("Admin") then
		return
	end
	order = 0
	clearList()
	targetBar.Visible = currentTab == "Player" or currentTab == "Powers"
	list.Position = UDim2.fromOffset(0, if targetBar.Visible then 128 else 68)
	list.Size = UDim2.new(1, 0, 1, if targetBar.Visible then -128 else -68)
	local info = admin()
	for id, b in tabButtons do
		b.SetColor(if id == currentTab then Theme.Colors.Selected else Theme.Colors.CardLight)
		if id == "Admins" then
			b.Instance.Visible = info ~= nil and info.IsOwner
		end
	end
	if currentTab == "Player" then
		buildPlayerTab()
	elseif currentTab == "Powers" then
		buildPowersTab()
	elseif currentTab == "Server" then
		buildServerTab()
	elseif currentTab == "Admins" then
		buildAdminsTab()
	end
end

function AdminPanel.refreshTarget()
	task.spawn(function()
		local r = Remote.request("AdminInfo", { Target = targetUserId })
		targetInfo = if r.ok and type(r.data) == "table" then r.data else nil
		rebuild()
	end)
end

local lastAdminSignature = ""
local function onSnapshot()
	local info = admin()
	openButton.Instance.Visible = info ~= nil
	if not info and PanelManager.isOpen("Admin") then
		PanelManager.close()
	end
	-- Admin-Tab neu zeichnen, wenn sich Admins/Rechte geändert haben
	local parts = {}
	if info then
		for perm in info.Permissions do
			table.insert(parts, perm)
		end
		local entries: { Types.AdminEntry } = info.Admins or {}
		for _, e in entries do
			table.insert(parts, tostring(e.UserId))
			for perm in e.Permissions do
				table.insert(parts, perm)
			end
		end
	end
	table.sort(parts)
	local sig = table.concat(parts, ",")
	if sig ~= lastAdminSignature then
		lastAdminSignature = sig
		rebuild()
	end
end

function AdminPanel.start()
	window = Components.window("Admin-Menü", "🛠", Theme.Colors.Orange, Vector2.new(940, 600), function()
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
			Size = UDim2.fromOffset(200, 54),
			TextSize = 20,
			LayoutOrder = i,
			Parent = tabBar,
			OnClick = function()
				currentTab = tab.Id
				rebuild()
			end,
		})
	end

	targetBar = Util.new("ScrollingFrame", {
		Name = "Targets",
		Size = UDim2.new(1, 0, 0, 58),
		Position = UDim2.fromOffset(0, 64),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 4,
		ScrollingDirection = Enum.ScrollingDirection.X,
		AutomaticCanvasSize = Enum.AutomaticSize.X,
		CanvasSize = UDim2.new(),
		Parent = window.Content,
	}, {
		Util.list(Enum.FillDirection.Horizontal, 8, Enum.HorizontalAlignment.Left),
		Util.padding(2, 4),
	})

	list = Components.scrollList({
		Size = UDim2.new(1, 0, 1, -128),
		Position = UDim2.fromOffset(0, 128),
		Parent = window.Content,
	}, 10)

	PanelManager.register("Admin", window, function()
		rebuildTargets()
		AdminPanel.refreshTarget()
		rebuild()
	end)

	openButton = Components.button({
		Text = "🛠 Admin",
		Color = Theme.Colors.Orange,
		Size = UDim2.fromOffset(130, 52),
		-- oben links (unten links liegt auf dem Handy der Joystick)
		Position = UDim2.fromOffset(14, 10),
		TextSize = 20,
		Parent = Root.layer("Hud"),
		OnClick = function()
			PanelManager.toggle("Admin")
		end,
	})
	openButton.Instance.Visible = false

	-- 🪄 Admin-Stab: auf einen Spieler klicken -> Admin-Menü für diesen Spieler
	local function hookWand(tool: Instance)
		if not tool:IsA("Tool") or tool:GetAttribute("PowerTool") ~= "AdminWand" or tool:GetAttribute("WandHooked") then
			return
		end
		tool:SetAttribute("WandHooked", true)
		tool.Activated:Connect(function()
			local camera = workspace.CurrentCamera
			if not camera then
				return
			end
			local mouse = UserInputService:GetMouseLocation()
			local ray = camera:ViewportPointToRay(mouse.X, mouse.Y)
			local params = RaycastParams.new()
			params.FilterType = Enum.RaycastFilterType.Exclude
			params.FilterDescendantsInstances = { localPlayer.Character :: Instance }
			local hit = workspace:Raycast(ray.Origin, ray.Direction * 500, params)
			local target: Player? = nil
			if hit then
				local model = hit.Instance:FindFirstAncestorOfClass("Model")
				while model and not target do
					target = Players:GetPlayerFromCharacter(model)
					model = model:FindFirstAncestorOfClass("Model")
				end
			end
			targetUserId = if target then target.UserId else localPlayer.UserId
			currentTab = "Player"
			if PanelManager.isOpen("Admin") then
				rebuildTargets()
				AdminPanel.refreshTarget()
			else
				PanelManager.open("Admin")
			end
		end)
	end
	local function watch(container: Instance)
		for _, child in container:GetChildren() do
			hookWand(child)
		end
		container.ChildAdded:Connect(hookWand)
	end
	task.spawn(function()
		watch(localPlayer:WaitForChild("Backpack"))
	end)
	localPlayer.CharacterAdded:Connect(function(character)
		watch(character)
		task.spawn(function()
			watch(localPlayer:WaitForChild("Backpack"))
		end)
	end)
	if localPlayer.Character then
		watch(localPlayer.Character)
	end

	ClientState.Changed:Connect(onSnapshot)
	Players.PlayerAdded:Connect(function()
		if PanelManager.isOpen("Admin") then
			rebuildTargets()
			rebuild()
		end
	end)
	Players.PlayerRemoving:Connect(function()
		task.defer(function()
			if PanelManager.isOpen("Admin") then
				rebuildTargets()
				rebuild()
			end
		end)
	end)
end

return AdminPanel

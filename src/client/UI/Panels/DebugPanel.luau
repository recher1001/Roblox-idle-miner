--!strict
--[[
	DebugPanel
	==========
	Test-Menü - erscheint NUR in Roblox Studio (Button "🛠 Test" unten links).
	Gibt Geld/Gems, schaltet Ebenen frei, startet Events usw. Der Server führt
	die Befehle ebenfalls nur in Studio aus.
]]

local RunService = game:GetService("RunService")

local Remote = require(script.Parent.Parent.Parent.Remote)
local Components = require(script.Parent.Parent.Components)
local PanelManager = require(script.Parent.Parent.PanelManager)
local Popups = require(script.Parent.Parent.Popups)
local Root = require(script.Parent.Parent.Root)
local Theme = require(script.Parent.Parent.Theme)
local Util = require(script.Parent.Parent.Util)

local DebugPanel = {}

type Action = { Text: string, Cmd: string, Arg: string?, Color: Color3, Confirm: boolean? }

local ACTIONS: { Action } = {
	{ Text = "+$1K", Cmd = "cash", Arg = "1000", Color = Theme.Colors.Green },
	{ Text = "+$1M", Cmd = "cash", Arg = "1e6", Color = Theme.Colors.Green },
	{ Text = "+$1B", Cmd = "cash", Arg = "1e9", Color = Theme.Colors.Green },
	{ Text = "+$1T", Cmd = "cash", Arg = "1e12", Color = Theme.Colors.Green },
	{ Text = "Geld x1000", Cmd = "mult", Arg = "1000", Color = Theme.Colors.Gold },
	{ Text = "+100 💎", Cmd = "gems", Arg = "100", Color = Theme.Colors.Purple },
	{ Text = "+1000 💎", Cmd = "gems", Arg = "1000", Color = Theme.Colors.Purple },
	{ Text = "🔓 Alle Ebenen", Cmd = "unlockall", Color = Theme.Colors.Blue },
	{ Text = "👔 Manager überall", Cmd = "managers", Color = Theme.Colors.Blue },
	{ Text = "⏱ Cooldowns weg", Cmd = "cooldowns", Color = Theme.Colors.Blue },
	{ Text = "🔥 Goldrausch", Cmd = "event", Arg = "GoldRush", Color = Theme.Colors.Orange },
	{ Text = "⚡ Arbeitsfieber", Cmd = "event", Arg = "Frenzy", Color = Theme.Colors.Orange },
	{ Text = "🌙 Offline 2h", Cmd = "offline", Arg = "7200", Color = Theme.Colors.Pink },
	{ Text = "🎁 Daily neu", Cmd = "daily", Color = Theme.Colors.Pink },
	{ Text = "♻ Alles zurücksetzen", Cmd = "reset", Color = Theme.Colors.Red, Confirm = true },
}

local function run(action: Action)
	Remote.send("Debug", { Cmd = action.Cmd, Arg = action.Arg or "" })
end

function DebugPanel.start()
	if not RunService:IsStudio() then
		return
	end

	local window = Components.window(
		"Test-Menü (nur Studio)",
		"🛠",
		Theme.Colors.Orange,
		Vector2.new(780, 470),
		function()
			PanelManager.close()
		end
	)
	local grid: Frame = Util.new("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Parent = window.Content,
	}, {
		Util.new("UIGridLayout", {
			CellSize = UDim2.fromOffset(236, 64),
			CellPadding = UDim2.fromOffset(12, 12),
			SortOrder = Enum.SortOrder.LayoutOrder,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
		}),
	})
	for i, action in ACTIONS do
		Components.button({
			Text = action.Text,
			Color = action.Color,
			Size = UDim2.fromOffset(236, 64),
			TextSize = 20,
			LayoutOrder = i,
			Parent = grid,
			OnClick = function()
				if action.Confirm then
					Popups.confirm("Wirklich den ganzen Spielstand zurücksetzen?", function()
						run(action)
					end)
				else
					run(action)
				end
			end,
		})
	end
	PanelManager.register("Debug", window)

	Components.button({
		Text = "🛠 Test",
		Color = Theme.Colors.Orange,
		Size = UDim2.fromOffset(110, 52),
		Position = UDim2.new(0, 14, 1, -14),
		AnchorPoint = Vector2.new(0, 1),
		TextSize = 20,
		Parent = Root.layer("Hud"),
		OnClick = function()
			PanelManager.toggle("Debug")
		end,
	})
end

return DebugPanel

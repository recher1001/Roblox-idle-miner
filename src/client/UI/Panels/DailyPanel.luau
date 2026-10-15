--!strict
--[[
	DailyPanel
	==========
	Tägliche Login-Belohnung mit 7-Tage-Serie. Die Serie bricht ab, wenn man
	zu lange nicht abholt (Config.Daily.StreakResetHours).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Clock = require(Shared.Clock)
local Config = require(Shared.Config)
local Formulas = require(Shared.Formulas)

local ClientState = require(script.Parent.Parent.Parent.ClientState)
local Remote = require(script.Parent.Parent.Parent.Remote)
local Components = require(script.Parent.Parent.Components)
local PanelManager = require(script.Parent.Parent.PanelManager)
local Theme = require(script.Parent.Parent.Theme)
local Util = require(script.Parent.Parent.Util)

local DailyPanel = {}

type Tile = { Frame: Frame, Stroke: UIStroke, Check: TextLabel }

local tiles: { Tile } = {}
local claimButton: Components.Button
local infoLabel: TextLabel

local function update()
	local snap = ClientState.Snapshot
	if not snap then
		return
	end
	local data = snap.Data
	local now = Clock.now()
	local available = snap.DailyAvailable
	local nextStreak = Formulas.nextDailyStreak(data, now)
	-- welche Kachel ist "heute"?
	local count = #Config.Daily.Rewards
	local todayIndex = ((nextStreak - 1) % count) + 1
	local claimedUpTo = if available then todayIndex - 1 else ((data.DailyStreak - 1) % count) + 1
	for i, tile in tiles do
		local isToday = available and i == todayIndex
		tile.Stroke.Color = if isToday then Theme.Colors.Gold else Theme.Colors.Stroke
		tile.Stroke.Thickness = if isToday then 4 else 2
		tile.Check.Visible = i <= claimedUpTo and nextStreak > 1
	end
	if available then
		claimButton.SetEnabled(true)
		claimButton.SetText(string.format("🎁 Tag %d abholen!", nextStreak))
		infoLabel.Text = string.format("Serie: %d Tage  •  Nicht abreißen lassen!", math.max(0, nextStreak - 1))
	else
		claimButton.SetEnabled(false)
		local nextDay = (math.floor(now / 86400) + 1) * 86400
		claimButton.SetText("⏳ " .. Formulas.formatDuration(nextDay - now))
		infoLabel.Text = string.format("Serie: %d Tage  •  Komm morgen wieder!", data.DailyStreak)
	end
end

function DailyPanel.start()
	local window = Components.window(
		"Tägliche Belohnung",
		"🎁",
		Theme.Colors.Green,
		Vector2.new(860, 440),
		function()
			PanelManager.close()
		end
	)
	local c = window.Content
	local row: Frame = Util.new("Frame", {
		Size = UDim2.new(1, 0, 0, 170),
		Position = UDim2.fromOffset(0, 10),
		BackgroundTransparency = 1,
		Parent = c,
	}, { Util.list(Enum.FillDirection.Horizontal, 10) })

	for i, reward in Config.Daily.Rewards do
		local isBig = i == #Config.Daily.Rewards
		local card = Components.card({
			Size = UDim2.fromOffset(102, 160),
			LayoutOrder = i,
			Parent = row,
		}, if isBig then Theme.Colors.Gold else nil)
		local stroke = card:FindFirstChildOfClass("UIStroke") :: UIStroke
		Util.label({
			Size = UDim2.new(1, 0, 0, 26),
			Position = UDim2.fromOffset(0, 8),
			Text = "Tag " .. i,
			Font = Theme.Fonts.Title,
			TextSize = 20,
			Parent = card,
		})
		Util.label({
			Size = UDim2.new(1, 0, 0, 50),
			Position = UDim2.fromOffset(0, 36),
			Text = if isBig then "👑" else "💎",
			TextSize = 40,
			Parent = card,
		})
		Util.label({
			Size = UDim2.new(1, -8, 0, 22),
			Position = UDim2.fromOffset(4, 92),
			Text = string.format("%d 💎", reward.Gems),
			TextSize = 16,
			TextColor3 = Theme.Colors.Gem,
			Parent = card,
		})
		Util.label({
			Size = UDim2.new(1, -8, 0, 36),
			Position = UDim2.fromOffset(4, 114),
			Text = string.format("+%s Einkommen", Formulas.formatDuration(reward.IncomeSeconds)),
			TextSize = 13,
			TextWrapped = true,
			TextColor3 = Theme.Colors.Money,
			Parent = card,
		})
		local check = Util.label({
			Size = UDim2.fromScale(1, 1),
			Text = "✅",
			TextSize = 54,
			BackgroundTransparency = 0.35,
			BackgroundColor3 = Color3.new(0, 0, 0),
			Visible = false,
			ZIndex = 5,
			Parent = card,
		})
		Util.corner(Theme.Radius.Medium).Parent = check
		table.insert(tiles, { Frame = card, Stroke = stroke, Check = check })
	end

	infoLabel = Util.label({
		Size = UDim2.new(1, 0, 0, 28),
		Position = UDim2.fromOffset(0, 192),
		Text = "",
		TextSize = 18,
		TextColor3 = Theme.Colors.SubText,
		Parent = c,
	})
	claimButton = Components.button({
		Text = "",
		Color = Theme.Colors.Green,
		Size = UDim2.fromOffset(360, 76),
		Position = UDim2.new(0.5, 0, 1, -10),
		AnchorPoint = Vector2.new(0.5, 1),
		TextSize = 26,
		Sound = "Purchase",
		Parent = c,
		OnClick = function()
			local r = Remote.request("ClaimDaily")
			if r.ok then
				claimButton.Pop()
			end
		end,
	})

	PanelManager.register("Daily", window, update)
	ClientState.Changed:Connect(function()
		if PanelManager.isOpen("Daily") then
			update()
		end
	end)
	task.spawn(function()
		while true do
			task.wait(1)
			if PanelManager.isOpen("Daily") then
				update()
			end
		end
	end)
end

return DailyPanel

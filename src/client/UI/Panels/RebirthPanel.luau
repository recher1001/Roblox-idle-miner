--!strict
--[[
	RebirthPanel
	============
	Zeigt aktuellen und neuen Multiplikator, Fortschritt zum Rebirth und
	was zurückgesetzt bzw. behalten wird.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local BigNum = require(Shared.BigNum)
local Config = require(Shared.Config)
local Formulas = require(Shared.Formulas)

local ClientState = require(script.Parent.Parent.Parent.ClientState)
local Remote = require(script.Parent.Parent.Parent.Remote)
local Components = require(script.Parent.Parent.Components)
local PanelManager = require(script.Parent.Parent.PanelManager)
local Popups = require(script.Parent.Parent.Popups)
local Theme = require(script.Parent.Parent.Theme)
local Util = require(script.Parent.Parent.Util)

local RebirthPanel = {}

local multLabel: TextLabel
local gainLabel: TextLabel
local statsLabel: TextLabel
local progress: Components.ProgressBar
local rebirthButton: Components.Button

local function money(b: BigNum.BigNum): string
	return BigNum.formatMoney(b, Config.CurrencySymbol)
end

local function update()
	local snap = ClientState.Snapshot
	if not snap then
		return
	end
	local data = snap.Data
	local cfg = Config.Rebirth
	local points = Formulas.rebirthPointsFor(data.RunCash)
	local current = Formulas.rebirthMultiplier(data.RebirthPoints)
	local after = Formulas.rebirthMultiplier(data.RebirthPoints + points)
	multLabel.Text = string.format(
		'x%s  ➜  <font color="#78FF8C">x%s</font>',
		BigNum.format(BigNum.new(current)),
		BigNum.format(BigNum.new(after))
	)
	if points > 0 then
		gainLabel.Text = string.format(
			"+%s Prestige-Punkte  •  +%d 💎",
			BigNum.format(BigNum.new(points)),
			Formulas.rebirthGems(points)
		)
		-- Fortschritt zum nächsten Punkt
		local nextNeeded = Formulas.rebirthCashFor(points + 1)
		local prevNeeded = Formulas.rebirthCashFor(points)
		-- Fortschritt im Log-Raum (funktioniert auch bei riesigen Zahlen)
		local lo = BigNum.log10(prevNeeded)
		local hi = BigNum.log10(nextNeeded)
		local ratio = (BigNum.log10(data.RunCash) - lo) / math.max(hi - lo, 1e-9)
		progress.Set(ratio, true)
		progress.SetText("Nächster Punkt bei " .. money(nextNeeded))
		rebirthButton.SetEnabled(true)
	else
		gainLabel.Text = "Verdiene mehr, um Prestige-Punkte zu bekommen!"
		local ratio = BigNum.toNumber(BigNum.divNum(data.RunCash, cfg.MinRunCash))
		progress.Set(ratio, true)
		progress.SetText(string.format("%s / %s verdient", money(data.RunCash), money(BigNum.new(cfg.MinRunCash))))
		rebirthButton.SetEnabled(false)
	end
	statsLabel.Text = string.format(
		"Rebirths: %d   •   Insgesamt verdient: %s   •   Prestige: %s",
		data.Rebirths,
		money(data.TotalCash),
		BigNum.format(BigNum.new(data.RebirthPoints))
	)
end

function RebirthPanel.start()
	local window = Components.window("Rebirth", "⭐", Theme.Colors.Purple, Vector2.new(720, 540), function()
		PanelManager.close()
	end)
	local c = window.Content

	local star: Frame = Util.new("Frame", {
		Size = UDim2.fromOffset(110, 110),
		Position = UDim2.new(0.5, 0, 0, 4),
		AnchorPoint = Vector2.new(0.5, 0),
		BackgroundColor3 = Color3.new(1, 1, 1),
		Parent = c,
	}, {
		Util.round(),
		Util.gradient(Theme.lighten(Theme.Colors.Purple, 0.3), Theme.darken(Theme.Colors.Purple, 0.3)),
		Util.stroke(Color3.new(1, 1, 1), 3, 0.3),
	})
	Util.label({ Size = UDim2.fromScale(1, 1), Text = "⭐", TextSize = 64, Parent = star })

	Util.label({
		Size = UDim2.new(1, 0, 0, 24),
		Position = UDim2.fromOffset(0, 120),
		Text = "Einkommens-Multiplikator",
		TextSize = 17,
		TextColor3 = Theme.Colors.SubText,
		Parent = c,
	})
	multLabel = Util.label({
		Size = UDim2.new(1, 0, 0, 50),
		Position = UDim2.fromOffset(0, 144),
		Text = "",
		Font = Theme.Fonts.Number,
		TextSize = 42,
		Parent = c,
	})
	Util.textStroke(2).Parent = multLabel
	gainLabel = Util.label({
		Size = UDim2.new(1, 0, 0, 28),
		Position = UDim2.fromOffset(0, 198),
		Text = "",
		TextSize = 20,
		TextColor3 = Theme.Colors.Gold,
		Parent = c,
	})
	progress = Components.progressBar({
		Size = UDim2.new(0.86, 0, 0, 30),
		Position = UDim2.new(0.5, 0, 0, 236),
		AnchorPoint = Vector2.new(0.5, 0),
		Parent = c,
	}, Theme.Colors.Purple)

	Util.label({
		Size = UDim2.new(1, -40, 0, 54),
		Position = UDim2.fromOffset(20, 278),
		Text = '<font color="#FF8C8C">Zurückgesetzt:</font> Geld, Ebenen, Upgrades, Lager\n'
			.. '<font color="#78FF8C">Du behältst:</font> Manager, Gems, Prestige, Gamepasses',
		TextSize = 16,
		TextWrapped = true,
		Parent = c,
	})
	statsLabel = Util.label({
		Size = UDim2.new(1, -20, 0, 24),
		Position = UDim2.fromOffset(10, 336),
		Text = "",
		TextSize = 15,
		TextColor3 = Theme.Colors.Muted,
		Parent = c,
	})
	rebirthButton = Components.button({
		Text = "⭐ REBIRTH",
		Color = Theme.Colors.Purple,
		Size = UDim2.fromOffset(320, 76),
		Position = UDim2.new(0.5, 0, 1, -8),
		AnchorPoint = Vector2.new(0.5, 1),
		TextSize = 30,
		Parent = c,
		OnClick = function()
			Popups.confirm(
				"Wirklich Rebirth machen?\nDein Fortschritt wird zurückgesetzt,\ndafür verdienst du dauerhaft mehr!",
				function()
					local r = Remote.request("Rebirth")
					if r.ok then
						PanelManager.close()
					end
				end,
				"Rebirth!"
			)
		end,
	})

	PanelManager.register("Rebirth", window, update)
	ClientState.Changed:Connect(function()
		if PanelManager.isOpen("Rebirth") then
			update()
		end
	end)
end

return RebirthPanel

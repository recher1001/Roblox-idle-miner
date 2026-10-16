--!strict
--[[
	AfkController
	=============
	Zeigt unten in der Mitte eine Leiste, solange man in der AFK-Zone steht:
	Fortschritt bis zum nächsten Gem + wie viele Gems man dort schon verdient
	hat. Die Werte kommen als Attribute vom Server (AfkService).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)

local Components = require(script.Parent.Parent.UI.Components)
local Root = require(script.Parent.Parent.UI.Root)
local Theme = require(script.Parent.Parent.UI.Theme)
local Util = require(script.Parent.Parent.UI.Util)

local AfkController = {}

function AfkController.start()
	local player = Players.LocalPlayer
	local scale: UIScale = Util.new("UIScale", { Scale = 0 })
	local card: Frame = Util.new("Frame", {
		Name = "AfkBar",
		Size = UDim2.fromOffset(440, 96),
		Position = UDim2.new(0.5, 0, 1, -120),
		AnchorPoint = Vector2.new(0.5, 1),
		BackgroundColor3 = Color3.new(1, 1, 1),
		Visible = false,
		Parent = Root.layer("Hud"),
	}, {
		Util.corner(Theme.Radius.Large),
		Util.gradient(Color3.fromRGB(150, 70, 255), Color3.fromRGB(60, 30, 170)),
		Util.stroke(Color3.new(1, 1, 1), 3),
		scale,
	})
	local title = Util.label({
		Size = UDim2.new(1, -20, 0, 34),
		Position = UDim2.fromOffset(10, 6),
		Text = "",
		Font = Theme.Fonts.Title,
		TextSize = 23,
		Parent = card,
	})
	Util.textStroke(1.5).Parent = title
	local bar = Components.progressBar({
		Size = UDim2.new(1, -30, 0, 30),
		Position = UDim2.new(0.5, 0, 1, -12),
		AnchorPoint = Vector2.new(0.5, 1),
	}, Theme.Colors.Gem)
	bar.Instance.Parent = card

	local shown = false
	local function update()
		local inZone = player:GetAttribute("AfkZone") == true
		local progress = tonumber(player:GetAttribute("AfkProgress")) or 0
		local gems = tonumber(player:GetAttribute("AfkGems")) or 0
		if inZone ~= shown then
			shown = inZone
			if inZone then
				card.Visible = true
				Util.tween(scale, 0.35, { Scale = 1 }, Enum.EasingStyle.Back)
			else
				Util.tween(scale, 0.2, { Scale = 0 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In).Completed
					:Once(function()
						if not shown then
							card.Visible = false
						end
					end)
			end
		end
		if inZone then
			local interval = Config.Afk.Interval
			title.Text = string.format("💤 AFK-Zone   •   +%d 💎 verdient", gems)
			bar.Set(progress / interval, true)
			bar.SetText(string.format("Nächstes 💎 + Minen-Geld in %ds", math.max(0, interval - progress)))
		end
	end
	for _, attr in { "AfkZone", "AfkProgress", "AfkGems" } do
		player:GetAttributeChangedSignal(attr):Connect(update)
	end
	update()
end

return AfkController

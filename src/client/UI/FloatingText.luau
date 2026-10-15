--!strict
--[[
	FloatingText
	============
	Aufsteigender Text als Feedback ("+$250", "-$1.2K", "LEVEL UP!").
	screen(): im HUD (Referenz-Pixel)   world(): über einer Weltposition
]]

local Players = game:GetService("Players")

local Root = require(script.Parent.Root)
local Theme = require(script.Parent.Theme)
local Util = require(script.Parent.Util)

local FloatingText = {}

function FloatingText.screen(text: string, color: Color3, position: UDim2, size: number?)
	local scale: UIScale = Util.new("UIScale", { Scale = 0.4 })
	local label = Util.label({
		Size = UDim2.fromOffset(300, 40),
		Position = position,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Text = text,
		Font = Theme.Fonts.Title,
		TextSize = size or 30,
		TextColor3 = color,
		Rotation = math.random(-8, 8),
		Parent = Root.layer("Effects"),
	})
	Util.textStroke(2.5).Parent = label
	scale.Parent = label
	Util.tween(scale, 0.25, { Scale = 1 }, Enum.EasingStyle.Back)
	Util.tween(label, 1.1, { Position = position - UDim2.fromOffset(math.random(-30, 30), 70) }, Enum.EasingStyle.Quad)
	task.delay(0.6, function()
		Util.tween(label, 0.5, { TextTransparency = 1 })
		local stroke = label:FindFirstChildOfClass("UIStroke")
		if stroke then
			Util.tween(stroke, 0.5, { Transparency = 1 })
		end
	end)
	task.delay(1.2, function()
		label:Destroy()
	end)
end

function FloatingText.world(text: string, color: Color3, position: Vector3, size: number?)
	local player = Players.LocalPlayer
	local attachment = Instance.new("Attachment")
	attachment.WorldPosition = position
	attachment.Parent = workspace.Terrain

	local gui: BillboardGui = Util.new("BillboardGui", {
		Size = UDim2.fromOffset(260, 60),
		AlwaysOnTop = true,
		LightInfluence = 0,
		Adornee = attachment,
		MaxDistance = 250,
		Parent = player:WaitForChild("PlayerGui"),
	})
	local label = Util.label({
		Size = UDim2.fromScale(1, 1),
		Text = text,
		Font = Theme.Fonts.Title,
		TextSize = size or 34,
		TextColor3 = color,
		Parent = gui,
	})
	Util.textStroke(2.5).Parent = label
	local scale: UIScale = Util.new("UIScale", { Scale = 0.3, Parent = label })
	Util.tween(scale, 0.3, { Scale = 1 }, Enum.EasingStyle.Back)
	Util.tween(gui, 1.4, { StudsOffsetWorldSpace = Vector3.new(0, 6, 0) }, Enum.EasingStyle.Quad)
	task.delay(0.8, function()
		Util.tween(label, 0.5, { TextTransparency = 1 })
	end)
	task.delay(1.4, function()
		gui:Destroy()
		attachment:Destroy()
	end)
end

return FloatingText

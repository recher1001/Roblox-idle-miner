--!strict
--[[
	Toasts
	======
	Kurze Benachrichtigungen oben in der Mitte (Erfolg, Warnung, Fehler, Info).
]]

local Root = require(script.Parent.Root)
local Theme = require(script.Parent.Theme)
local Util = require(script.Parent.Util)

local Toasts = {}

local container: Frame? = nil
local order = 0
local MAX_TOASTS = 4

local KIND_COLORS: { [string]: Color3 } = {
	info = Theme.Colors.Blue,
	success = Theme.Colors.Green,
	warn = Theme.Colors.Orange,
	error = Theme.Colors.Red,
	gold = Theme.Colors.Gold,
	alarm = Theme.Colors.Red,
}

local function getContainer(): Frame
	if container then
		return container
	end
	local c: Frame = Util.new("Frame", {
		Name = "Toasts",
		Size = UDim2.fromOffset(560, 400),
		Position = UDim2.new(0.5, 0, 0, 132),
		AnchorPoint = Vector2.new(0.5, 0),
		BackgroundTransparency = 1,
		Parent = Root.layer("Toast"),
	}, {
		Util.list(Enum.FillDirection.Vertical, 8, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Top),
	})
	container = c
	return c
end

function Toasts.show(text: string, kind: string?, duration: number?)
	local c = getContainer()
	local color = KIND_COLORS[kind or "info"] or Theme.Colors.Blue
	order += 1

	-- älteste entfernen, wenn zu viele
	local existing = {}
	for _, child in c:GetChildren() do
		if child:IsA("Frame") then
			table.insert(existing, child)
		end
	end
	if #existing >= MAX_TOASTS then
		table.sort(existing, function(a, b)
			return a.LayoutOrder < b.LayoutOrder
		end)
		existing[1]:Destroy()
	end

	local scale: UIScale = Util.new("UIScale", { Scale = 0.6 })
	local frame: Frame = Util.new("Frame", {
		Name = "Toast",
		Size = UDim2.fromOffset(0, 46),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundColor3 = Color3.new(1, 1, 1),
		LayoutOrder = order,
		Parent = c,
	}, {
		Util.round(),
		Util.gradient(Theme.Colors.PillTop, Theme.Colors.PillBottom),
		Util.stroke(color, 2.5),
		Util.padding(0, 22),
		scale,
	})
	local label = Util.label({
		Size = UDim2.fromScale(0, 1),
		AutomaticSize = Enum.AutomaticSize.X,
		Text = text,
		TextColor3 = Color3.new(1, 1, 1),
		TextSize = Theme.TextSize.Body,
		Parent = frame,
	})
	Util.textStroke(1).Parent = label

	Util.tween(scale, 0.3, { Scale = 1 }, Enum.EasingStyle.Back)
	task.delay(duration or 3, function()
		if frame.Parent then
			Util.tween(scale, 0.2, { Scale = 0.6 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
			Util.tween(frame, 0.2, { BackgroundTransparency = 1 })
			Util.tween(label, 0.2, { TextTransparency = 1 })
			task.wait(0.22)
			frame:Destroy()
		end
	end)
end

return Toasts

--!strict
--[[
	Components
	==========
	Wiederverwendbare UI-Bausteine im einheitlichen Stil:
	abgerundete Ecken, Farbverläufe, Outlines, Hover/Klick/Pop-Tweens.
]]

local Theme = require(script.Parent.Theme)
local Util = require(script.Parent.Util)
local Sounds = require(script.Parent.Parent.Controllers.Sounds)

local Components = {}

----------------------------------------------------------------------
-- Button
----------------------------------------------------------------------
export type ButtonProps = {
	Text: string,
	Color: Color3?,
	Size: UDim2,
	Position: UDim2?,
	AnchorPoint: Vector2?,
	TextSize: number?,
	Font: Enum.Font?,
	LayoutOrder: number?,
	Parent: Instance?,
	OnClick: (() -> ())?,
	Sound: string?,
	ZIndex: number?,
}

export type Button = {
	Instance: TextButton,
	Label: TextLabel,
	Scale: UIScale,
	SetEnabled: (enabled: boolean) -> (),
	SetColor: (color: Color3) -> (),
	SetText: (text: string) -> (),
	Pop: () -> (),
	IsEnabled: () -> boolean,
}

function Components.button(props: ButtonProps): Button
	local color = props.Color or Theme.Colors.Green
	local enabled = true

	local scale: UIScale = Util.new("UIScale")
	local gradient = Util.gradient(Theme.lighten(color, 0.18), Theme.darken(color, 0.12))
	local stroke = Util.stroke(Theme.darken(color, 0.45), 2.5)

	local label: TextLabel = Util.label({
		Name = "Label",
		Size = UDim2.fromScale(1, 1),
		Text = props.Text,
		Font = props.Font or Theme.Fonts.Title,
		TextSize = props.TextSize or Theme.TextSize.Large,
		TextWrapped = true,
		ZIndex = (props.ZIndex or 1) + 1,
	})
	Util.textStroke(1.5).Parent = label

	local button: TextButton = Util.new("TextButton", {
		Name = "Button",
		Size = props.Size,
		Position = props.Position or UDim2.new(),
		AnchorPoint = props.AnchorPoint or Vector2.zero,
		BackgroundColor3 = Color3.new(1, 1, 1),
		AutoButtonColor = false,
		Text = "",
		LayoutOrder = props.LayoutOrder or 0,
		ZIndex = props.ZIndex or 1,
		Parent = props.Parent,
	}, {
		Util.corner(Theme.Radius.Medium),
		gradient,
		stroke,
		scale,
		label,
	})

	-- Glanz-Streifen oben
	Util.new("Frame", {
		Name = "Shine",
		Size = UDim2.new(1, -8, 0.42, 0),
		Position = UDim2.fromOffset(4, 3),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BackgroundTransparency = 0.82,
		ZIndex = props.ZIndex or 1,
		Parent = button,
	}, { Util.corner(Theme.Radius.Medium - 3) })

	local hovering = false
	button.MouseEnter:Connect(function()
		hovering = true
		if enabled then
			Util.tween(scale, 0.15, { Scale = 1.06 }, Enum.EasingStyle.Quad)
		end
	end)
	button.MouseLeave:Connect(function()
		hovering = false
		Util.tween(scale, 0.15, { Scale = 1 }, Enum.EasingStyle.Quad)
	end)
	button.MouseButton1Down:Connect(function()
		if enabled then
			Util.tween(scale, 0.08, { Scale = 0.92 }, Enum.EasingStyle.Quad)
		end
	end)
	button.MouseButton1Up:Connect(function()
		Util.tween(scale, 0.2, { Scale = if hovering then 1.06 else 1 }, Enum.EasingStyle.Back)
	end)
	button.Activated:Connect(function()
		if not enabled then
			Sounds.play("Error", 0.8)
			Util.tween(scale, 0.05, { Scale = 0.96 }).Completed:Wait()
			Util.tween(scale, 0.2, { Scale = 1 }, Enum.EasingStyle.Back)
			return
		end
		Sounds.play(props.Sound or "Click", 1 + math.random() * 0.1)
		if props.OnClick then
			props.OnClick()
		end
	end)

	local self: Button
	local function applyColor(c: Color3)
		gradient.Color = ColorSequence.new(Theme.lighten(c, 0.18), Theme.darken(c, 0.12))
		stroke.Color = Theme.darken(c, 0.45)
	end
	self = {
		Instance = button,
		Label = label,
		Scale = scale,
		SetEnabled = function(value: boolean)
			if enabled == value then
				return
			end
			enabled = value
			applyColor(if value then color else Theme.Colors.Disabled)
			label.TextTransparency = if value then 0 else 0.1
		end,
		SetColor = function(c: Color3)
			color = c
			if enabled then
				applyColor(c)
			end
		end,
		SetText = function(text: string)
			if label.Text ~= text then
				label.Text = text
			end
		end,
		Pop = function()
			Util.pop(scale, 0.12)
		end,
		IsEnabled = function()
			return enabled
		end,
	}
	return self
end

----------------------------------------------------------------------
-- Karte (Hintergrund für Listeneinträge)
----------------------------------------------------------------------
function Components.card(props: { [string]: any }, accent: Color3?): Frame
	local defaults: { [string]: any } = {
		BackgroundColor3 = Color3.new(1, 1, 1),
		Size = UDim2.new(1, 0, 0, 90),
	}
	for k, v in props do
		defaults[k] = v
	end
	local frame: Frame = Util.new("Frame", defaults, {
		Util.corner(Theme.Radius.Medium),
		Util.gradient(Theme.Colors.CardLight, Theme.Colors.Card),
		Util.stroke(accent or Theme.Colors.Stroke, 2, if accent then 0.1 else 0.4),
	})
	return frame
end

----------------------------------------------------------------------
-- Fortschrittsbalken
----------------------------------------------------------------------
export type ProgressBar = {
	Instance: Frame,
	Set: (ratio: number, animate: boolean?) -> (),
	SetText: (text: string) -> (),
}

function Components.progressBar(props: { [string]: any }, color: Color3): ProgressBar
	local defaults: { [string]: any } = {
		BackgroundColor3 = Theme.Colors.Track,
		Size = UDim2.new(1, 0, 0, 22),
	}
	for k, v in props do
		defaults[k] = v
	end
	local bar: Frame = Util.new("Frame", defaults, { Util.round(), Util.stroke(Theme.Colors.Stroke, 1.5, 0.3) })
	local fill: Frame = Util.new("Frame", {
		Name = "Fill",
		Size = UDim2.fromScale(0, 1),
		BackgroundColor3 = Color3.new(1, 1, 1),
		Parent = bar,
	}, { Util.round(), Util.gradient(Theme.lighten(color, 0.2), Theme.darken(color, 0.1)) })
	local text = Util.label({
		Size = UDim2.fromScale(1, 1),
		Text = "",
		TextSize = Theme.TextSize.Small,
		ZIndex = 3,
		Parent = bar,
	})
	Util.textStroke(1).Parent = text
	return {
		Instance = bar,
		Set = function(ratio: number, animate: boolean?)
			local target = UDim2.fromScale(math.clamp(ratio, 0, 1), 1)
			if animate then
				Util.tween(fill, 0.3, { Size = target })
			else
				fill.Size = target
			end
		end,
		SetText = function(t: string)
			text.Text = t
		end,
	}
end

----------------------------------------------------------------------
-- Fenster (Modal-Panel mit Titel und Schließen-Button)
----------------------------------------------------------------------
export type Window = {
	Root: CanvasGroup,
	Content: Frame,
	Scale: UIScale,
	Title: TextLabel,
	CloseButton: Button,
}

function Components.window(title: string, icon: string, accent: Color3, size: Vector2, onClose: () -> ()): Window
	local scale: UIScale = Util.new("UIScale")
	local root: CanvasGroup = Util.new("CanvasGroup", {
		Name = "Window",
		Size = UDim2.fromOffset(size.X, size.Y),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = Color3.new(1, 1, 1),
		GroupTransparency = 0,
		Visible = false,
	}, {
		Util.corner(Theme.Radius.Large),
		Util.gradient(Theme.Colors.Panel, Theme.darken(Theme.Colors.Panel, 0.1)),
		scale,
	})
	-- Rahmen außerhalb der CanvasGroup würde abgeschnitten -> innen zeichnen
	Util.new("Frame", {
		Name = "Border",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ZIndex = 10,
		Parent = root,
	}, { Util.corner(Theme.Radius.Large), Util.stroke(accent, 3) })

	-- Kopfzeile
	local header: Frame = Util.new("Frame", {
		Name = "Header",
		Size = UDim2.new(1, 0, 0, 64),
		BackgroundColor3 = Color3.new(1, 1, 1),
		Parent = root,
	}, {
		Util.corner(Theme.Radius.Large),
		Util.gradient(Theme.lighten(accent, 0.1), Theme.darken(accent, 0.3)),
	})
	-- untere Ecken der Kopfzeile gerade machen
	Util.new("Frame", {
		Size = UDim2.new(1, 0, 0, 20),
		Position = UDim2.new(0, 0, 1, -20),
		BorderSizePixel = 0,
		BackgroundColor3 = Color3.new(1, 1, 1),
		Parent = header,
	}, { Util.gradient(Theme.darken(accent, 0.22), Theme.darken(accent, 0.3)) })

	local titleLabel = Util.label({
		Name = "Title",
		Size = UDim2.new(1, -140, 1, 0),
		Position = UDim2.fromOffset(24, 0),
		Text = icon .. "  " .. title,
		Font = Theme.Fonts.Title,
		TextSize = Theme.TextSize.Title,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 2,
		Parent = header,
	})
	Util.textStroke(2).Parent = titleLabel

	local close = Components.button({
		Text = "✕",
		Color = Theme.Colors.Red,
		Size = UDim2.fromOffset(48, 48),
		Position = UDim2.new(1, -14, 0.5, 0),
		AnchorPoint = Vector2.new(1, 0.5),
		TextSize = 24,
		Parent = header,
		OnClick = onClose,
		ZIndex = 3,
	})

	local content: Frame = Util.new("Frame", {
		Name = "Content",
		Size = UDim2.new(1, -32, 1, -84),
		Position = UDim2.fromOffset(16, 72),
		BackgroundTransparency = 1,
		Parent = root,
	})

	return {
		Root = root,
		Content = content,
		Scale = scale,
		Title = titleLabel,
		CloseButton = close,
	}
end

----------------------------------------------------------------------
-- Scroll-Liste
----------------------------------------------------------------------
function Components.scrollList(props: { [string]: any }, padding: number?): ScrollingFrame
	local defaults: { [string]: any } = {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 8,
		ScrollBarImageColor3 = Theme.Colors.Stroke,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		ScrollingDirection = Enum.ScrollingDirection.Y,
	}
	for k, v in props do
		defaults[k] = v
	end
	local list: ScrollingFrame = Util.new("ScrollingFrame", defaults, {
		Util.list(
			Enum.FillDirection.Vertical,
			padding or 10,
			Enum.HorizontalAlignment.Center,
			Enum.VerticalAlignment.Top
		),
		Util.new("UIPadding", {
			PaddingTop = UDim.new(0, 4),
			PaddingBottom = UDim.new(0, 8),
			PaddingLeft = UDim.new(0, 4),
			PaddingRight = UDim.new(0, 14),
		}),
	})
	return list
end

--- Pille mit Icon + Text (z. B. Geldanzeige)
function Components.pill(props: { [string]: any }, accent: Color3): Frame
	local defaults: { [string]: any } = {
		BackgroundColor3 = Color3.new(1, 1, 1),
		Size = UDim2.fromOffset(200, 52),
	}
	for k, v in props do
		defaults[k] = v
	end
	return Util.new("Frame", defaults, {
		Util.round(),
		Util.gradient(Theme.Colors.PillTop, Theme.Colors.PillBottom),
		Util.stroke(accent, 2.5),
	})
end

return Components

--!strict
--[[
	Util
	====
	Kleine Helfer zum Erzeugen von UI per Code.

		local frame = Util.new("Frame", { Size = UDim2.fromScale(1, 1), Parent = gui }, {
			Util.corner(12),
			Util.stroke(Color3.new(1, 1, 1), 2),
		})
]]

local TweenService = game:GetService("TweenService")

local Theme = require(script.Parent.Theme)

local Util = {}

--- Erstellt eine Instanz mit Eigenschaften und Kindern. Parent wird zuletzt gesetzt.
function Util.new(className: string, props: { [string]: any }?, children: { any }?): any
	local inst = (Instance.new :: any)(className)
	local parent: Instance? = nil
	if props then
		for k, v in props do
			if k == "Parent" then
				parent = v
			else
				inst[k] = v
			end
		end
	end
	if children then
		for _, child in children do
			child.Parent = inst
		end
	end
	if parent then
		inst.Parent = parent
	end
	return inst
end

function Util.corner(radius: number?): any
	return Util.new("UICorner", { CornerRadius = UDim.new(0, radius or Theme.Radius.Medium) })
end

function Util.round(): any
	return Util.new("UICorner", { CornerRadius = UDim.new(1, 0) })
end

function Util.stroke(color: Color3, thickness: number?, transparency: number?): any
	return Util.new("UIStroke", {
		Color = color,
		Thickness = thickness or 2,
		Transparency = transparency or 0,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	})
end

function Util.textStroke(thickness: number?): any
	-- dicke, dunkle Kontur = Sticker-/Cartoon-Look (auch für Emojis im Text)
	return Util.new("UIStroke", {
		Color = Color3.fromRGB(26, 14, 10),
		Thickness = thickness or 2,
		Transparency = 0,
		LineJoinMode = Enum.LineJoinMode.Round,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual,
	})
end

--- Emoji als "Sticker": große Glyphe mit dicker dunkler Umrandung
function Util.emoji(props: { [string]: any }): TextLabel
	local label = Util.label(props)
	local size = label.TextSize
	Util.textStroke(math.max(2, size / 14)).Parent = label
	return label
end

--- Vertikaler Farbverlauf (oben hell -> unten dunkel)
function Util.gradient(top: Color3, bottom: Color3, rotation: number?): any
	return Util.new("UIGradient", {
		Color = ColorSequence.new(top, bottom),
		Rotation = rotation or 90,
	})
end

function Util.padding(all: number, horizontal: number?): any
	local h = horizontal or all
	return Util.new("UIPadding", {
		PaddingTop = UDim.new(0, all),
		PaddingBottom = UDim.new(0, all),
		PaddingLeft = UDim.new(0, h),
		PaddingRight = UDim.new(0, h),
	})
end

function Util.list(
	direction: Enum.FillDirection,
	padding: number,
	hAlign: Enum.HorizontalAlignment?,
	vAlign: Enum.VerticalAlignment?
): any
	return Util.new("UIListLayout", {
		FillDirection = direction,
		Padding = UDim.new(0, padding),
		HorizontalAlignment = hAlign or Enum.HorizontalAlignment.Center,
		VerticalAlignment = vAlign or Enum.VerticalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
	})
end

function Util.tween(
	inst: Instance,
	time: number,
	props: { [string]: any },
	style: Enum.EasingStyle?,
	direction: Enum.EasingDirection?
): Tween
	local tween = TweenService:Create(
		inst,
		TweenInfo.new(time, style or Enum.EasingStyle.Quad, direction or Enum.EasingDirection.Out),
		props
	)
	tween:Play()
	return tween
end

--- Kurzer "Pop"-Effekt über einen UIScale
function Util.pop(scale: UIScale, amount: number?)
	scale.Scale = 1 + (amount or 0.12)
	Util.tween(scale, 0.35, { Scale = 1 }, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
end

--- Textlabel mit Standardwerten
function Util.label(props: { [string]: any }): TextLabel
	local defaults: { [string]: any } = {
		BackgroundTransparency = 1,
		Font = Theme.Fonts.Body,
		TextColor3 = Theme.Colors.Text,
		TextSize = Theme.TextSize.Body,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextYAlignment = Enum.TextYAlignment.Center,
		RichText = true,
	}
	for k, v in props do
		defaults[k] = v
	end
	return Util.new("TextLabel", defaults)
end

return Util

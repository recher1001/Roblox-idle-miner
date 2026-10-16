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
	return Util.new("UIStroke", {
		Color = Color3.new(0, 0, 0),
		Thickness = thickness or 1.5,
		Transparency = 0.35,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual,
	})
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
----------------------------------------------------------------------
-- Emoji-Design im Cartoon-Stil: jedes Emoji bekommt eine dicke, dunkle
-- Umrandung (RichText <stroke>) - der restliche Text bleibt unverändert.
----------------------------------------------------------------------
local EMOJI_OUTLINE = "#1E100A"

local function isEmoji(cp: number): boolean
	return (cp >= 0x2190 and cp <= 0x2BFF) -- Pfeile, Symbole, Dingbats (⬆ ⚡ ⭐ ✨ ❤ ...)
		or (cp >= 0x1F000 and cp <= 0x1FAFF) -- Emojis (💰 💎 👔 🛒 🎁 ...)
		or cp == 0xFE0F -- Emoji-Variante
		or cp == 0x200D -- Verbinder (zusammengesetzte Emojis)
end

--- Umschließt alle Emojis eines Textes mit einer dicken dunklen Umrandung
function Util.outlineEmojis(text: string, thickness: number): string
	if text == "" or string.find(text, "<stroke", 1, true) then
		return text
	end
	local ok, result = pcall(function()
		local out = {}
		local run = {}
		local inTag = false
		local function flush()
			if #run > 0 then
				table.insert(
					out,
					string.format(
						'<stroke color="%s" thickness="%d" joins="round">%s</stroke>',
						EMOJI_OUTLINE,
						thickness,
						table.concat(run)
					)
				)
				table.clear(run)
			end
		end
		for _, cp in utf8.codes(text) do
			local ch = utf8.char(cp)
			if ch == "<" then
				inTag = true
			end
			if not inTag and isEmoji(cp) then
				table.insert(run, ch)
			else
				flush()
				table.insert(out, ch)
			end
			if ch == ">" then
				inTag = false
			end
		end
		flush()
		return table.concat(out)
	end)
	return if ok then result else text
end

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
	local label: TextLabel = Util.new("TextLabel", defaults)
	-- Emojis automatisch im Cartoon-Stil umranden (auch bei späteren Textänderungen)
	local applying = false
	local function apply()
		if applying or not label.RichText then
			return
		end
		applying = true
		-- große Emojis (z. B. <font size="40">) bekommen eine dickere Umrandung
		local fontSize = tonumber(string.match(label.Text, '<font size="(%d+)"')) or 0
		local thickness = math.max(2, math.floor(math.max(label.TextSize, fontSize) / 11))
		local wrapped = Util.outlineEmojis(label.Text, thickness)
		if wrapped ~= label.Text then
			label.Text = wrapped
		end
		applying = false
	end
	apply()
	label:GetPropertyChangedSignal("Text"):Connect(apply)
	return label
end

return Util

--!strict
--[[
	Theme
	=====
	Einheitliche Farbpalette, Schriften und Maße für die komplette UI.
	Alle Größen sind in "Referenz-Pixeln" (1280x720). Der Root-UIScale
	skaliert alles passend auf jeden Bildschirm (auch Handy/Tablet).
]]

local Theme = {}

Theme.ReferenceSize = Vector2.new(1280, 720)

Theme.Colors = {
	Overlay = Color3.fromRGB(8, 6, 14),
	Panel = Color3.fromRGB(32, 29, 46),
	PanelTop = Color3.fromRGB(48, 43, 70),
	Card = Color3.fromRGB(44, 40, 62),
	CardLight = Color3.fromRGB(58, 53, 80),
	Stroke = Color3.fromRGB(96, 86, 134),
	Text = Color3.fromRGB(255, 255, 255),
	SubText = Color3.fromRGB(194, 186, 218),
	Muted = Color3.fromRGB(130, 122, 156),
	Gold = Color3.fromRGB(255, 196, 54),
	Green = Color3.fromRGB(78, 210, 104),
	Blue = Color3.fromRGB(64, 156, 255),
	Purple = Color3.fromRGB(170, 96, 255),
	Pink = Color3.fromRGB(255, 92, 160),
	Red = Color3.fromRGB(238, 76, 76),
	Orange = Color3.fromRGB(255, 140, 50),
	Disabled = Color3.fromRGB(92, 88, 108),
	Money = Color3.fromRGB(120, 255, 140),
	Gem = Color3.fromRGB(196, 120, 255),
}

Theme.Fonts = {
	Title = Enum.Font.FredokaOne,
	Body = Enum.Font.GothamBold,
	Number = Enum.Font.GothamBlack,
}

Theme.Radius = {
	Small = 8,
	Medium = 14,
	Large = 22,
}

Theme.TextSize = {
	Small = 14,
	Body = 17,
	Large = 22,
	Title = 30,
	Huge = 44,
}

-- Mindestgröße für Touch-Buttons (Referenz-Pixel)
Theme.TouchMin = 52

function Theme.darken(c: Color3, amount: number): Color3
	return c:Lerp(Color3.new(0, 0, 0), amount)
end

function Theme.lighten(c: Color3, amount: number): Color3
	return c:Lerp(Color3.new(1, 1, 1), amount)
end

return Theme

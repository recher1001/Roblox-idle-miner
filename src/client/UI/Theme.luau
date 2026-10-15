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
	Overlay = Color3.fromRGB(20, 18, 32),
	Panel = Color3.fromRGB(70, 64, 104),
	PanelTop = Color3.fromRGB(96, 88, 140),
	Card = Color3.fromRGB(88, 81, 128),
	CardLight = Color3.fromRGB(112, 104, 158),
	Stroke = Color3.fromRGB(170, 160, 222),
	Text = Color3.fromRGB(255, 255, 255),
	SubText = Color3.fromRGB(232, 228, 250),
	Muted = Color3.fromRGB(196, 190, 224),
	PillTop = Color3.fromRGB(98, 90, 142),
	PillBottom = Color3.fromRGB(66, 60, 100),
	Track = Color3.fromRGB(52, 47, 80),
	Gold = Color3.fromRGB(255, 196, 54),
	Green = Color3.fromRGB(78, 210, 104),
	Blue = Color3.fromRGB(64, 156, 255),
	Purple = Color3.fromRGB(170, 96, 255),
	Pink = Color3.fromRGB(255, 92, 160),
	Red = Color3.fromRGB(238, 76, 76),
	Orange = Color3.fromRGB(255, 140, 50),
	Disabled = Color3.fromRGB(128, 124, 146),
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

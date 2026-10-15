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
	-- Hintergründe: kräftiges Violett/Blau (satt, nicht grau)
	Overlay = Color3.fromRGB(16, 8, 40),
	Panel = Color3.fromRGB(64, 34, 176),
	PanelTop = Color3.fromRGB(112, 56, 255),
	PanelBottom = Color3.fromRGB(28, 84, 220),
	Card = Color3.fromRGB(86, 52, 214),
	CardLight = Color3.fromRGB(126, 88, 255),
	Stroke = Color3.fromRGB(255, 255, 255),
	Text = Color3.fromRGB(255, 255, 255),
	SubText = Color3.fromRGB(244, 238, 255),
	Muted = Color3.fromRGB(222, 210, 255),
	PillTop = Color3.fromRGB(122, 70, 255),
	PillBottom = Color3.fromRGB(62, 34, 196),
	Track = Color3.fromRGB(34, 16, 100),
	Selected = Color3.fromRGB(255, 214, 0),
	-- Vordergrund / Buttons: Neon-Farben mit hoher Sättigung
	Gold = Color3.fromRGB(255, 200, 0),
	Green = Color3.fromRGB(20, 232, 90),
	Blue = Color3.fromRGB(0, 158, 255),
	Cyan = Color3.fromRGB(0, 226, 255),
	Purple = Color3.fromRGB(178, 56, 255),
	Pink = Color3.fromRGB(255, 46, 170),
	Red = Color3.fromRGB(255, 44, 78),
	Orange = Color3.fromRGB(255, 122, 0),
	Lime = Color3.fromRGB(150, 255, 0),
	Disabled = Color3.fromRGB(130, 116, 182),
	Money = Color3.fromRGB(110, 255, 120),
	Gem = Color3.fromRGB(226, 120, 255),
}

-- Regenbogen für animierte Ränder
Theme.Rainbow = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 46, 120)),
	ColorSequenceKeypoint.new(0.2, Color3.fromRGB(255, 170, 0)),
	ColorSequenceKeypoint.new(0.4, Color3.fromRGB(160, 255, 0)),
	ColorSequenceKeypoint.new(0.6, Color3.fromRGB(0, 226, 255)),
	ColorSequenceKeypoint.new(0.8, Color3.fromRGB(150, 70, 255)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 46, 120)),
})

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

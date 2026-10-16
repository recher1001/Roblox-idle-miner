--!strict
--[[
	Faces
	=====
	Die Cartoon-Emojis (wie im Referenzbild) komplett per Code gezeichnet:
	abgerundetes Quadrat, dicke dunkle Umrandung, große glänzende Augen.
	Keine Bild-Assets nötig.

		local face = Faces.create("Cool", 48)   -- Frame 48x48
		face.Parent = irgendwo

	Verfügbare Gesichter:
	  Laughing, Pleading, Crying, Flushed, Clown, Cursing, Devil, Skull,
	  MindBlown, Poop, Cold, Kissing, Disguise, Cool, KissHeart, Hug,
	  Sleeping, Cowboy, Cigar, Nerd
]]

local Faces = {}

local DARK = Color3.fromRGB(42, 24, 16)
local WHITE = Color3.new(1, 1, 1)
local YELLOW_TOP = Color3.fromRGB(255, 218, 72)
local YELLOW_BOTTOM = Color3.fromRGB(246, 168, 32)
local BLUSH = Color3.fromRGB(255, 120, 120)
local RED = Color3.fromRGB(226, 40, 50)
local TEAR = Color3.fromRGB(70, 170, 255)

type Ctx = { Root: Frame, Size: number, Z: number }

----------------------------------------------------------------------
-- Zeichen-Helfer (alle Positionen/Größen relativ zum Gesicht, 0..1)
----------------------------------------------------------------------
type Opts = {
	Round: number?, -- Eckenradius als Anteil (0.5 = Kreis/Pille)
	Rot: number?, -- Rotation in Grad
	Z: number?, -- Ebene (über dem Gesicht)
	Stroke: number?, -- Umrandungsdicke relativ zur Größe
	StrokeColor: Color3?,
	Transparency: number?,
	Anchor: Vector2?,
	Gradient: { Color3 }?,
	Clip: boolean?,
	Parent: Instance?,
}

local function el(ctx: Ctx, x: number, y: number, w: number, h: number, color: Color3, opts: Opts?): Frame
	local o: Opts = opts or {}
	local f = Instance.new("Frame")
	f.AnchorPoint = o.Anchor or Vector2.new(0.5, 0.5)
	f.Position = UDim2.fromScale(x, y)
	f.Size = UDim2.fromScale(w, h)
	f.BackgroundColor3 = color
	f.BackgroundTransparency = o.Transparency or 0
	f.BorderSizePixel = 0
	f.Rotation = o.Rot or 0
	f.ZIndex = ctx.Z + (o.Z or 2)
	f.ClipsDescendants = o.Clip == true
	if o.Round then
		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(o.Round, 0)
		c.Parent = f
	end
	if o.Stroke then
		local s = Instance.new("UIStroke")
		s.Color = o.StrokeColor or DARK
		s.Thickness = math.max(1, ctx.Size * o.Stroke)
		s.LineJoinMode = Enum.LineJoinMode.Round
		s.Parent = f
	end
	if o.Gradient then
		local g = Instance.new("UIGradient")
		g.Color = ColorSequence.new(o.Gradient[1], o.Gradient[2])
		g.Rotation = 90
		g.Parent = f
		f.BackgroundColor3 = WHITE
	end
	f.Parent = o.Parent or ctx.Root
	return f
end

local function circle(ctx: Ctx, x: number, y: number, d: number, color: Color3, opts: Opts?): Frame
	local o: Opts = opts or {}
	o.Round = 0.5
	return el(ctx, x, y, d, d, color, o)
end

--- Gesichtsgrundform (abgerundetes Quadrat mit dicker Umrandung + Glanz)
local function base(ctx: Ctx, top: Color3, bottom: Color3, round: number?): Frame
	local b = el(ctx, 0.5, 0.5, 0.88, 0.88, top, {
		Round = round or 0.36,
		Z = 1,
		Stroke = 0.055,
		Gradient = { top, bottom },
	})
	-- weicher Glanz oben
	el(ctx, 0.5, 0.2, 0.5, 0.12, WHITE, { Round = 0.5, Z = 1, Transparency = 0.7 })
	return b
end

--- Großes Cartoon-Auge: weiß, schwarze Pupille, Glanzpunkt
local function eye(ctx: Ctx, x: number, y: number, d: number?, pupil: number?)
	local size = d or 0.2
	circle(ctx, x, y, size, WHITE, { Z = 3, Stroke = 0.025 })
	local p = size * (pupil or 0.62)
	circle(ctx, x, y + size * 0.06, p, DARK, { Z = 4 })
	circle(ctx, x + p * 0.22, y - p * 0.12, p * 0.34, WHITE, { Z = 5 })
end

--- Bogen (halber Ring): up=true -> "^" (oberer Teil), sonst "u"
local function arc(ctx: Ctx, x: number, y: number, w: number, up: boolean, thick: number?, color: Color3?)
	local clip = el(ctx, x, y, w, w / 2, WHITE, {
		Transparency = 1,
		Clip = true,
		Anchor = Vector2.new(0.5, if up then 1 else 0),
		Z = 4,
	})
	local ring = Instance.new("Frame")
	ring.AnchorPoint = Vector2.new(0.5, if up then 0 else 1)
	ring.Position = UDim2.fromScale(0.5, if up then 0 else 1)
	ring.Size = UDim2.fromScale(0.86, 1.72)
	ring.BackgroundTransparency = 1
	ring.ZIndex = ctx.Z + 4
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0.5, 0)
	c.Parent = ring
	local s = Instance.new("UIStroke")
	s.Color = color or DARK
	s.Thickness = math.max(1.5, ctx.Size * (thick or 0.045))
	s.Parent = ring
	ring.Parent = clip
end

--- Gefüllter Mund (untere Halbkreis-Form), optional mit Zähnen + Zunge
local function mouth(ctx: Ctx, x: number, y: number, w: number, h: number, teeth: boolean?, tongue: boolean?)
	local clip = el(ctx, x, y, w, h, WHITE, {
		Transparency = 1,
		Clip = true,
		Anchor = Vector2.new(0.5, 0),
		Z = 4,
	})
	local inner = Instance.new("Frame")
	inner.AnchorPoint = Vector2.new(0.5, 1)
	inner.Position = UDim2.fromScale(0.5, 1)
	inner.Size = UDim2.fromScale(1, 2)
	inner.BackgroundColor3 = Color3.fromRGB(120, 24, 30)
	inner.BorderSizePixel = 0
	inner.ZIndex = ctx.Z + 4
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0.5, 0)
	c.Parent = inner
	local s = Instance.new("UIStroke")
	s.Color = DARK
	s.Thickness = math.max(1, ctx.Size * 0.03)
	s.Parent = inner
	inner.Parent = clip
	if teeth then
		local t = Instance.new("Frame")
		t.AnchorPoint = Vector2.new(0.5, 0)
		t.Position = UDim2.fromScale(0.5, 0)
		t.Size = UDim2.fromScale(0.9, 0.3)
		t.BackgroundColor3 = WHITE
		t.BorderSizePixel = 0
		t.ZIndex = ctx.Z + 5
		t.Parent = clip
	end
	if tongue then
		local t = Instance.new("Frame")
		t.AnchorPoint = Vector2.new(0.5, 1)
		t.Position = UDim2.fromScale(0.5, 1.15)
		t.Size = UDim2.fromScale(0.55, 0.7)
		t.BackgroundColor3 = Color3.fromRGB(255, 90, 100)
		t.BorderSizePixel = 0
		t.ZIndex = ctx.Z + 5
		local tc = Instance.new("UICorner")
		tc.CornerRadius = UDim.new(0.5, 0)
		tc.Parent = t
		t.Parent = clip
	end
end

local function bar(ctx: Ctx, x: number, y: number, w: number, h: number, rot: number, color: Color3?)
	el(ctx, x, y, w, h, color or DARK, { Round = 0.5, Rot = rot, Z = 4 })
end

local function text(ctx: Ctx, x: number, y: number, w: number, h: number, t: string, color: Color3, z: number?)
	local l = Instance.new("TextLabel")
	l.AnchorPoint = Vector2.new(0.5, 0.5)
	l.Position = UDim2.fromScale(x, y)
	l.Size = UDim2.fromScale(w, h)
	l.BackgroundTransparency = 1
	l.Font = Enum.Font.FredokaOne
	l.TextScaled = true
	l.Text = t
	l.TextColor3 = color
	l.ZIndex = ctx.Z + (z or 6)
	l.Parent = ctx.Root
end

local function blush(ctx: Ctx)
	el(ctx, 0.24, 0.6, 0.16, 0.09, BLUSH, { Round = 0.5, Z = 2, Transparency = 0.35 })
	el(ctx, 0.76, 0.6, 0.16, 0.09, BLUSH, { Round = 0.5, Z = 2, Transparency = 0.35 })
end

local function heart(ctx: Ctx, x: number, y: number, s: number)
	circle(ctx, x - s * 0.22, y - s * 0.12, s * 0.55, RED, { Z = 6 })
	circle(ctx, x + s * 0.22, y - s * 0.12, s * 0.55, RED, { Z = 6 })
	el(ctx, x, y + s * 0.1, s * 0.62, s * 0.62, RED, { Rot = 45, Z = 6, Round = 0.15 })
end

local function yellowBase(ctx: Ctx)
	base(ctx, YELLOW_TOP, YELLOW_BOTTOM)
end

----------------------------------------------------------------------
-- Die Gesichter
----------------------------------------------------------------------
local DRAW: { [string]: (Ctx) -> () } = {}

DRAW.Laughing = function(ctx) -- 😆
	yellowBase(ctx)
	bar(ctx, 0.3, 0.36, 0.17, 0.05, 25)
	bar(ctx, 0.3, 0.44, 0.17, 0.05, -25)
	bar(ctx, 0.7, 0.36, 0.17, 0.05, -25)
	bar(ctx, 0.7, 0.44, 0.17, 0.05, 25)
	mouth(ctx, 0.5, 0.55, 0.5, 0.25, true, true)
end

DRAW.Pleading = function(ctx) -- 🥹
	yellowBase(ctx)
	eye(ctx, 0.32, 0.45, 0.24, 0.7)
	eye(ctx, 0.68, 0.45, 0.24, 0.7)
	el(ctx, 0.32, 0.54, 0.2, 0.07, TEAR, { Round = 0.5, Z = 6, Transparency = 0.1 })
	el(ctx, 0.68, 0.54, 0.2, 0.07, TEAR, { Round = 0.5, Z = 6, Transparency = 0.1 })
	arc(ctx, 0.5, 0.66, 0.2, false, 0.04)
end

DRAW.Crying = function(ctx) -- 😭
	yellowBase(ctx)
	arc(ctx, 0.32, 0.38, 0.18, true, 0.045)
	arc(ctx, 0.68, 0.38, 0.18, true, 0.045)
	el(ctx, 0.3, 0.4, 0.12, 0.48, TEAR, { Anchor = Vector2.new(0.5, 0), Round = 0.4, Z = 3 })
	el(ctx, 0.7, 0.4, 0.12, 0.48, TEAR, { Anchor = Vector2.new(0.5, 0), Round = 0.4, Z = 3 })
	el(ctx, 0.5, 0.66, 0.22, 0.2, Color3.fromRGB(120, 24, 30), { Round = 0.5, Z = 4, Stroke = 0.03 })
	el(ctx, 0.5, 0.71, 0.13, 0.08, Color3.fromRGB(255, 90, 100), { Round = 0.5, Z = 5 })
end

DRAW.Flushed = function(ctx) -- 😳
	yellowBase(ctx)
	blush(ctx)
	eye(ctx, 0.33, 0.43, 0.22, 0.42)
	eye(ctx, 0.67, 0.43, 0.22, 0.42)
	bar(ctx, 0.5, 0.68, 0.1, 0.045, 0)
end

DRAW.Clown = function(ctx) -- 🤡
	circle(ctx, 0.17, 0.18, 0.26, RED, { Z = 0, Stroke = 0.04 })
	circle(ctx, 0.83, 0.18, 0.26, RED, { Z = 0, Stroke = 0.04 })
	base(ctx, WHITE, Color3.fromRGB(228, 228, 240))
	circle(ctx, 0.32, 0.42, 0.26, Color3.fromRGB(80, 160, 255), { Z = 2, Transparency = 0.2 })
	circle(ctx, 0.68, 0.42, 0.26, Color3.fromRGB(80, 160, 255), { Z = 2, Transparency = 0.2 })
	eye(ctx, 0.32, 0.42, 0.17, 0.62)
	eye(ctx, 0.68, 0.42, 0.17, 0.62)
	mouth(ctx, 0.5, 0.64, 0.46, 0.2, true, false)
	circle(ctx, 0.5, 0.58, 0.17, RED, { Z = 7, Stroke = 0.03 })
end

DRAW.Cursing = function(ctx) -- 🤬
	base(ctx, Color3.fromRGB(226, 46, 36), Color3.fromRGB(255, 150, 40))
	bar(ctx, 0.32, 0.3, 0.2, 0.06, 20)
	bar(ctx, 0.68, 0.3, 0.2, 0.06, -20)
	eye(ctx, 0.33, 0.44, 0.18, 0.62)
	eye(ctx, 0.67, 0.44, 0.18, 0.62)
	el(ctx, 0.5, 0.7, 0.52, 0.18, DARK, { Round = 0.25, Z = 4 })
	text(ctx, 0.5, 0.7, 0.46, 0.15, "!#$&", WHITE)
end

DRAW.Devil = function(ctx) -- 😈
	local purple = Color3.fromRGB(160, 70, 255)
	el(ctx, 0.2, 0.14, 0.2, 0.2, purple, { Rot = 30, Z = 0, Stroke = 0.04, Round = 0.15 })
	el(ctx, 0.8, 0.14, 0.2, 0.2, purple, { Rot = -30, Z = 0, Stroke = 0.04, Round = 0.15 })
	base(ctx, Color3.fromRGB(186, 100, 255), Color3.fromRGB(122, 40, 220))
	bar(ctx, 0.32, 0.34, 0.2, 0.06, 18)
	bar(ctx, 0.68, 0.34, 0.2, 0.06, -18)
	eye(ctx, 0.33, 0.46, 0.18, 0.62)
	eye(ctx, 0.67, 0.46, 0.18, 0.62)
	arc(ctx, 0.5, 0.64, 0.34, false, 0.05)
end

DRAW.Skull = function(ctx) -- 💀
	base(ctx, Color3.fromRGB(250, 250, 255), Color3.fromRGB(205, 210, 225), 0.42)
	circle(ctx, 0.33, 0.45, 0.25, DARK, { Z = 3 })
	circle(ctx, 0.67, 0.45, 0.25, DARK, { Z = 3 })
	el(ctx, 0.5, 0.63, 0.08, 0.08, DARK, { Rot = 45, Z = 3, Round = 0.2 })
	for i = -1, 1 do
		bar(ctx, 0.5 + i * 0.1, 0.8, 0.035, 0.1, 0)
	end
end

DRAW.MindBlown = function(ctx) -- 🤯
	yellowBase(ctx)
	local cloud = Color3.fromRGB(255, 250, 240)
	circle(ctx, 0.3, 0.18, 0.28, cloud, { Z = 6, Stroke = 0.03 })
	circle(ctx, 0.5, 0.1, 0.32, cloud, { Z = 6, Stroke = 0.03 })
	circle(ctx, 0.7, 0.18, 0.28, cloud, { Z = 6, Stroke = 0.03 })
	el(ctx, 0.5, 0.22, 0.5, 0.14, cloud, { Z = 7, Round = 0.5 })
	el(ctx, 0.85, 0.12, 0.12, 0.12, Color3.fromRGB(255, 200, 0), { Rot = 45, Z = 8, Stroke = 0.02 })
	eye(ctx, 0.33, 0.5, 0.21, 0.5)
	eye(ctx, 0.67, 0.5, 0.21, 0.5)
	el(ctx, 0.5, 0.73, 0.12, 0.13, Color3.fromRGB(120, 24, 30), { Round = 0.5, Z = 4, Stroke = 0.03 })
end

DRAW.Poop = function(ctx) -- 💩
	local brown = Color3.fromRGB(150, 86, 50)
	local light = Color3.fromRGB(190, 120, 72)
	el(ctx, 0.5, 0.8, 0.86, 0.3, brown, { Round = 0.5, Z = 1, Stroke = 0.05, Gradient = { light, brown } })
	el(ctx, 0.5, 0.56, 0.66, 0.28, brown, { Round = 0.5, Z = 1, Stroke = 0.05, Gradient = { light, brown } })
	el(ctx, 0.5, 0.34, 0.42, 0.22, brown, { Round = 0.5, Z = 1, Stroke = 0.05, Gradient = { light, brown } })
	circle(ctx, 0.56, 0.18, 0.16, brown, { Z = 1, Stroke = 0.05 })
	eye(ctx, 0.38, 0.55, 0.16, 0.6)
	eye(ctx, 0.62, 0.55, 0.16, 0.6)
	mouth(ctx, 0.5, 0.72, 0.3, 0.12, false, true)
end

DRAW.Cold = function(ctx) -- 🥶
	base(ctx, Color3.fromRGB(190, 232, 255), Color3.fromRGB(96, 170, 240))
	el(ctx, 0.5, 0.16, 0.6, 0.08, WHITE, { Round = 0.5, Z = 2, Transparency = 0.2 })
	eye(ctx, 0.33, 0.42, 0.2, 0.55)
	eye(ctx, 0.67, 0.42, 0.2, 0.55)
	el(ctx, 0.5, 0.68, 0.5, 0.16, WHITE, { Round = 0.3, Z = 4, Stroke = 0.035 })
	for i = -2, 2 do
		bar(ctx, 0.5 + i * 0.09, 0.68, 0.02, 0.14, 0, Color3.fromRGB(120, 170, 220))
	end
	bar(ctx, 0.5, 0.68, 0.46, 0.02, 0, Color3.fromRGB(120, 170, 220))
end

DRAW.Kissing = function(ctx) -- 😚
	yellowBase(ctx)
	blush(ctx)
	arc(ctx, 0.32, 0.44, 0.18, false, 0.045)
	arc(ctx, 0.68, 0.44, 0.18, false, 0.045)
	text(ctx, 0.52, 0.68, 0.16, 0.18, "3", DARK)
	-- Hand
	local hand = Color3.fromRGB(255, 200, 70)
	el(ctx, 0.2, 0.8, 0.22, 0.2, hand, { Round = 0.45, Z = 6, Stroke = 0.035, Rot = -20 })
end

DRAW.Disguise = function(ctx) -- 🥸
	yellowBase(ctx)
	el(ctx, 0.32, 0.3, 0.24, 0.07, Color3.fromRGB(110, 60, 30), { Round = 0.5, Z = 6 })
	el(ctx, 0.68, 0.3, 0.24, 0.07, Color3.fromRGB(110, 60, 30), { Round = 0.5, Z = 6 })
	eye(ctx, 0.32, 0.44, 0.17, 0.6)
	eye(ctx, 0.68, 0.44, 0.17, 0.6)
	circle(
		ctx,
		0.32,
		0.44,
		0.25,
		WHITE,
		{ Z = 5, Transparency = 1, Stroke = 0.04, StrokeColor = Color3.fromRGB(80, 80, 90) }
	)
	circle(
		ctx,
		0.68,
		0.44,
		0.25,
		WHITE,
		{ Z = 5, Transparency = 1, Stroke = 0.04, StrokeColor = Color3.fromRGB(80, 80, 90) }
	)
	bar(ctx, 0.5, 0.42, 0.1, 0.03, 0, Color3.fromRGB(80, 80, 90))
	circle(ctx, 0.5, 0.6, 0.17, Color3.fromRGB(230, 140, 80), { Z = 6, Stroke = 0.03 })
	el(ctx, 0.5, 0.73, 0.4, 0.09, Color3.fromRGB(110, 60, 30), { Round = 0.5, Z = 6 })
end

DRAW.Cool = function(ctx) -- 😎
	yellowBase(ctx)
	local glass = Color3.fromRGB(40, 50, 70)
	el(ctx, 0.31, 0.44, 0.3, 0.17, glass, { Round = 0.35, Z = 5, Stroke = 0.03 })
	el(ctx, 0.69, 0.44, 0.3, 0.17, glass, { Round = 0.35, Z = 5, Stroke = 0.03 })
	bar(ctx, 0.5, 0.4, 0.86, 0.04, 0, glass)
	el(ctx, 0.25, 0.4, 0.08, 0.04, WHITE, { Round = 0.5, Z = 6, Transparency = 0.4 })
	el(ctx, 0.63, 0.4, 0.08, 0.04, WHITE, { Round = 0.5, Z = 6, Transparency = 0.4 })
	arc(ctx, 0.5, 0.65, 0.34, false, 0.05)
end

DRAW.KissHeart = function(ctx) -- 😘
	yellowBase(ctx)
	blush(ctx)
	eye(ctx, 0.33, 0.44, 0.18, 0.62)
	arc(ctx, 0.67, 0.46, 0.18, true, 0.045)
	text(ctx, 0.47, 0.68, 0.16, 0.18, "3", DARK)
	heart(ctx, 0.74, 0.74, 0.2)
end

DRAW.Hug = function(ctx) -- 🤗 / Winken
	yellowBase(ctx)
	eye(ctx, 0.35, 0.5, 0.15, 0.62)
	eye(ctx, 0.65, 0.5, 0.15, 0.62)
	arc(ctx, 0.5, 0.66, 0.26, false, 0.045)
	local hand = Color3.fromRGB(255, 226, 90)
	el(ctx, 0.72, 0.2, 0.26, 0.24, hand, { Round = 0.45, Z = 7, Stroke = 0.035, Rot = 15 })
	for i = 0, 2 do
		el(ctx, 0.66 + i * 0.07, 0.08, 0.06, 0.13, hand, { Round = 0.5, Z = 7, Stroke = 0.025, Rot = 15 })
	end
end

DRAW.Sleeping = function(ctx) -- 😴
	yellowBase(ctx)
	arc(ctx, 0.32, 0.48, 0.18, false, 0.045)
	arc(ctx, 0.68, 0.48, 0.18, false, 0.045)
	el(ctx, 0.5, 0.72, 0.11, 0.12, Color3.fromRGB(120, 24, 30), { Round = 0.5, Z = 4, Stroke = 0.03 })
	text(ctx, 0.62, 0.17, 0.36, 0.22, "zz", Color3.fromRGB(60, 120, 255))
end

DRAW.Cowboy = function(ctx) -- 🤠
	yellowBase(ctx)
	local hat = Color3.fromRGB(170, 96, 52)
	el(ctx, 0.5, 0.25, 0.98, 0.12, hat, { Round = 0.5, Z = 6, Stroke = 0.04 })
	el(ctx, 0.5, 0.12, 0.52, 0.2, hat, { Round = 0.3, Z = 6, Stroke = 0.04 })
	bar(ctx, 0.5, 0.2, 0.52, 0.04, 0, Color3.fromRGB(220, 60, 50))
	eye(ctx, 0.34, 0.48, 0.16, 0.62)
	eye(ctx, 0.66, 0.48, 0.16, 0.62)
	mouth(ctx, 0.5, 0.62, 0.42, 0.2, true, true)
end

DRAW.Cigar = function(ctx) -- 🫢 mit Zigarre
	yellowBase(ctx)
	eye(ctx, 0.33, 0.43, 0.18, 0.6)
	eye(ctx, 0.67, 0.43, 0.18, 0.6)
	el(ctx, 0.5, 0.67, 0.1, 0.1, Color3.fromRGB(120, 24, 30), { Round = 0.5, Z = 4, Stroke = 0.03 })
	el(ctx, 0.68, 0.7, 0.32, 0.08, Color3.fromRGB(150, 80, 40), { Round = 0.4, Z = 6, Stroke = 0.03, Rot = -12 })
	circle(ctx, 0.84, 0.67, 0.07, Color3.fromRGB(255, 120, 40), { Z = 7 })
end

DRAW.Nerd = function(ctx) -- 🤓
	yellowBase(ctx)
	eye(ctx, 0.32, 0.44, 0.18, 0.6)
	eye(ctx, 0.68, 0.44, 0.18, 0.6)
	local frame = Color3.fromRGB(70, 80, 100)
	circle(ctx, 0.32, 0.44, 0.27, WHITE, { Z = 5, Transparency = 1, Stroke = 0.045, StrokeColor = frame })
	circle(ctx, 0.68, 0.44, 0.27, WHITE, { Z = 5, Transparency = 1, Stroke = 0.045, StrokeColor = frame })
	bar(ctx, 0.5, 0.43, 0.09, 0.035, 0, frame)
	mouth(ctx, 0.5, 0.64, 0.36, 0.15, false, false)
	el(ctx, 0.46, 0.645, 0.07, 0.07, WHITE, { Z = 6, Anchor = Vector2.new(0.5, 0), Round = 0.15 })
	el(ctx, 0.54, 0.645, 0.07, 0.07, WHITE, { Z = 6, Anchor = Vector2.new(0.5, 0), Round = 0.15 })
end

--- Erstellt ein Gesicht als Frame (size in Pixeln, z = ZIndex-Basis)
function Faces.create(name: string, size: number, z: number?): Frame
	local root = Instance.new("Frame")
	root.Name = "Face_" .. name
	root.Size = UDim2.fromOffset(size, size)
	root.BackgroundTransparency = 1
	root.ZIndex = z or 1
	local draw = DRAW[name] or DRAW.Laughing
	draw({ Root = root, Size = size, Z = z or 1 })
	return root
end

function Faces.has(name: string): boolean
	return DRAW[name] ~= nil
end

Faces.Names = {
	"Laughing",
	"Pleading",
	"Crying",
	"Flushed",
	"Clown",
	"Cursing",
	"Devil",
	"Skull",
	"MindBlown",
	"Poop",
	"Cold",
	"Kissing",
	"Disguise",
	"Cool",
	"KissHeart",
	"Hug",
	"Sleeping",
	"Cowboy",
	"Cigar",
	"Nerd",
}

return Faces

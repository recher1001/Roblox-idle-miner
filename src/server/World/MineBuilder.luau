--!strict
--[[
	MineBuilder
	===========
	Baut die komplette Mine eines Plots prozedural aus Parts.
	Keine externen Assets nötig.

	EIGENE MODELLE: Lege in ServerStorage einen Ordner "MineAssets" an und
	füge Models mit diesen Namen ein, sie ersetzen dann die Platzhalter:
	  "Miner"     - ein Kumpel (optional mit einem Part "Pickaxe", wird animiert)
	  "Manager"   - Manager-Figur (Parts mit Attribut "RarityColor" werden eingefärbt)
	  "Crate"     - Schachtlager-Kiste
	  "Depot"     - Aufzugslager-Kiste an der Oberfläche
	  "Cabin"     - Aufzugskabine
	  "Warehouse" - Lagergebäude
	  "Cart"      - Transportwagen
	Jedes Model braucht einen PrimaryPart (oder wird über GetPivot platziert).
	Unterseite = Pivot. Blickrichtung = -Z (zur Rückwand der Mine).

	Koordinaten (lokal zum Plot, +Z = Vorderseite/Gehweg, Y=0 = Boden):
	  Grube:      X [-10, 38], Z [-40, -14]
	  Aufzug:     X [-10, -4] (in der Grube links)
	  Ebene i:    Boden-Oberkante bei Y = -LevelHeight * i
]]

local ServerStorage = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)

local MineBuilder = {}

local LH = Config.World.LevelHeight
local MAX_LEVELS = #Config.Shafts
local PIT_MIN_X, PIT_MAX_X = -10, 38
local PIT_BACK_Z, PIT_FRONT_Z = -40, -14
local LEVEL_MIN_X = -4
local PIT_BOTTOM = -LH * MAX_LEVELS - 6
local PLOT_HALF = Config.World.PlotSpacing / 2

MineBuilder.Layout = {
	PitMinX = PIT_MIN_X,
	PitMaxX = PIT_MAX_X,
	PitBackZ = PIT_BACK_Z,
	PitFrontZ = PIT_FRONT_Z,
	LevelHeight = LH,
	ElevatorX = -7,
	ElevatorZ = -34,
	DepotPos = Vector3.new(-19, 0, -31),
	WarehouseDoor = Vector3.new(-33, 0, -31),
	SpawnPos = Vector3.new(14, 0, 24),
}

local COLORS = {
	Grass = Color3.fromRGB(110, 148, 72),
	Dirt = Color3.fromRGB(120, 92, 64),
	Rock = Color3.fromRGB(92, 84, 78),
	DarkRock = Color3.fromRGB(58, 52, 50),
	Wood = Color3.fromRGB(140, 96, 58),
	DarkWood = Color3.fromRGB(96, 64, 40),
	Metal = Color3.fromRGB(120, 124, 132),
	DarkMetal = Color3.fromRGB(64, 66, 72),
	Gold = Color3.fromRGB(255, 196, 64),
	Roof = Color3.fromRGB(176, 60, 48),
	Wall = Color3.fromRGB(226, 208, 176),
	Lamp = Color3.fromRGB(255, 196, 120),
	Skin = Color3.fromRGB(240, 196, 160),
	Shirt = Color3.fromRGB(64, 110, 176),
	Pants = Color3.fromRGB(58, 62, 84),
	Helmet = Color3.fromRGB(255, 204, 40),
}
MineBuilder.Colors = COLORS

----------------------------------------------------------------------
-- Grundbausteine
----------------------------------------------------------------------
type PartProps = {
	Name: string?,
	Size: Vector3,
	CFrame: CFrame,
	Color: Color3?,
	Material: Enum.Material?,
	Transparency: number?,
	CanCollide: boolean?,
	Shape: Enum.PartType?,
	Parent: Instance?,
}

local function P(props: PartProps): Part
	local p = Instance.new("Part")
	p.Name = props.Name or "Part"
	p.Anchored = true
	p.Size = props.Size
	p.CFrame = props.CFrame
	p.Color = props.Color or COLORS.Rock
	p.Material = props.Material or Enum.Material.SmoothPlastic
	p.Transparency = props.Transparency or 0
	p.CanCollide = if props.CanCollide == nil then true else props.CanCollide
	if props.Shape then
		p.Shape = props.Shape
	end
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = props.Parent
	return p
end
MineBuilder.Part = P

--- Part zwischen zwei Ecken (lokal), relativ zu origin
local function box(
	origin: CFrame,
	minV: Vector3,
	maxV: Vector3,
	color: Color3,
	material: Enum.Material,
	parent: Instance,
	name: string?
): Part
	local size = maxV - minV
	local center = (minV + maxV) / 2
	return P({
		Name = name,
		Size = Vector3.new(math.abs(size.X), math.abs(size.Y), math.abs(size.Z)),
		CFrame = origin * CFrame.new(center),
		Color = color,
		Material = material,
		Parent = parent,
	})
end

local function model(name: string, parent: Instance?): Model
	local m = Instance.new("Model")
	m.Name = name
	m.Parent = parent
	return m
end

local function folder(name: string, parent: Instance?): Folder
	local f = Instance.new("Folder")
	f.Name = name
	f.Parent = parent
	return f
end

--- Eigenes Asset aus ServerStorage.MineAssets klonen (falls vorhanden)
local function customAsset(name: string): Model?
	local assets = ServerStorage:FindFirstChild("MineAssets")
	if not assets then
		return nil
	end
	local m = assets:FindFirstChild(name)
	if m and m:IsA("Model") then
		local clone = m:Clone()
		for _, d in clone:GetDescendants() do
			if d:IsA("BasePart") then
				d.Anchored = true
			end
		end
		return clone
	end
	return nil
end

local function addLight(part: BasePart, range: number, brightness: number, color: Color3?)
	local light = Instance.new("PointLight")
	light.Range = range
	light.Brightness = brightness
	light.Color = color or COLORS.Lamp
	light.Shadows = false
	light.Parent = part
end

----------------------------------------------------------------------
-- Billboards (Info-Schilder über Stationen)
----------------------------------------------------------------------
function MineBuilder.makeInfoBillboard(anchor: BasePart, accent: Color3): BillboardGui
	local gui = Instance.new("BillboardGui")
	gui.Name = "Info"
	gui.Size = UDim2.fromScale(13, 3.6)
	gui.StudsOffset = Vector3.new(0, 0, 0)
	gui.MaxDistance = 160
	gui.LightInfluence = 0
	gui.AlwaysOnTop = false
	gui.Adornee = anchor

	local frame = Instance.new("Frame")
	frame.Name = "Panel"
	frame.Size = UDim2.fromScale(1, 1)
	frame.BackgroundColor3 = Color3.fromRGB(72, 66, 106)
	frame.BackgroundTransparency = 0.05
	frame.Parent = gui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.25, 0)
	corner.Parent = frame
	local stroke = Instance.new("UIStroke")
	stroke.Color = accent:Lerp(Color3.new(1, 1, 1), 0.3)
	stroke.Thickness = 3
	stroke.Parent = frame

	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.BackgroundTransparency = 1
	title.Size = UDim2.fromScale(0.94, 0.5)
	title.Position = UDim2.fromScale(0.03, 0.04)
	title.Font = Enum.Font.FredokaOne
	title.TextScaled = true
	title.TextColor3 = Color3.new(1, 1, 1)
	title.TextStrokeTransparency = 0.35
	title.Text = ""
	title.Parent = frame

	local sub = Instance.new("TextLabel")
	sub.Name = "Sub"
	sub.BackgroundTransparency = 1
	sub.Size = UDim2.fromScale(0.94, 0.4)
	sub.Position = UDim2.fromScale(0.03, 0.54)
	sub.Font = Enum.Font.GothamBold
	sub.TextScaled = true
	-- Akzentfarbe nur aufgehellt nutzen, damit auch dunkle Erze (Kohle) lesbar bleiben
	sub.TextColor3 = accent:Lerp(Color3.new(1, 1, 1), 0.65)
	sub.TextStrokeTransparency = 0.35
	sub.Text = ""
	sub.Parent = frame

	gui.Parent = anchor
	return gui
end

----------------------------------------------------------------------
-- Figuren (Kumpel / Manager)
----------------------------------------------------------------------
local function buildFigure(name: string, cf: CFrame, shirt: Color3, hat: Color3, withPickaxe: boolean): Model
	local custom = customAsset(if withPickaxe then "Miner" else "Manager")
	if custom then
		custom.Name = name
		custom:PivotTo(cf)
		custom:SetAttribute("FloorCFrame", cf)
		return custom
	end
	local m = model(name)
	m:SetAttribute("FloorCFrame", cf)
	local legs = P({
		Name = "Legs",
		Size = Vector3.new(1.6, 1.8, 0.9),
		CFrame = cf * CFrame.new(0, 0.9, 0),
		Color = COLORS.Pants,
		Parent = m,
	})
	local body = P({
		Name = "Body",
		Size = Vector3.new(2, 2, 1),
		CFrame = cf * CFrame.new(0, 2.8, 0),
		Color = shirt,
		Parent = m,
	})
	body:SetAttribute("RarityColor", true)
	P({
		Name = "Head",
		Size = Vector3.new(1.3, 1.3, 1.3),
		CFrame = cf * CFrame.new(0, 4.45, 0),
		Color = COLORS.Skin,
		Shape = Enum.PartType.Ball,
		Parent = m,
	})
	P({
		Name = "Hat",
		Size = Vector3.new(1.5, 0.5, 1.5),
		CFrame = cf * CFrame.new(0, 5.05, 0),
		Color = hat,
		Material = Enum.Material.SmoothPlastic,
		Parent = m,
	})
	if withPickaxe then
		local lamp = P({
			Name = "HatLamp",
			Size = Vector3.new(0.4, 0.4, 0.2),
			CFrame = cf * CFrame.new(0, 5.05, -0.8),
			Color = COLORS.Lamp,
			Material = Enum.Material.Neon,
			CanCollide = false,
			Parent = m,
		})
		addLight(lamp, 8, 0.8)
		-- Spitzhacke: Griff + Kopf als ein Model, Drehpunkt an der Schulter
		local pick = model("Pickaxe", m)
		local shoulder = cf * CFrame.new(0.9, 3.5, 0)
		local handle = P({
			Name = "Handle",
			Size = Vector3.new(0.25, 0.25, 3),
			CFrame = shoulder * CFrame.new(0, 0, -1.5),
			Color = COLORS.Wood,
			CanCollide = false,
			Parent = pick,
		})
		P({
			Name = "Head",
			Size = Vector3.new(0.3, 1.8, 0.35),
			CFrame = shoulder * CFrame.new(0, 0, -2.9),
			Color = COLORS.Metal,
			Material = Enum.Material.Metal,
			CanCollide = false,
			Parent = pick,
		})
		pick.PrimaryPart = handle
		pick:SetAttribute("Shoulder", shoulder)
	end
	for _, d in m:GetDescendants() do
		if d:IsA("BasePart") then
			d.CanCollide = false
		end
	end
	m.PrimaryPart = legs
	return m
end

----------------------------------------------------------------------
-- Plot-Grundstruktur (einmal pro Plot, unabhängig vom Besitzer)
----------------------------------------------------------------------
function MineBuilder.buildBase(plot: Model, origin: CFrame)
	local base = folder("Base", plot)

	-- Bodenplatten rund um die Grube (Oberkante Y=0)
	local function ground(minV: Vector3, maxV: Vector3)
		box(origin, minV, maxV, COLORS.Grass, Enum.Material.Grass, base, "Ground")
		-- Erdschicht darunter
		box(
			origin,
			Vector3.new(minV.X, minV.Y - 6, minV.Z),
			Vector3.new(maxV.X, minV.Y, maxV.Z),
			COLORS.Dirt,
			Enum.Material.Ground,
			base,
			"Dirt"
		)
	end
	ground(Vector3.new(-PLOT_HALF, -2, PIT_FRONT_Z), Vector3.new(PLOT_HALF, 0, 60))
	ground(Vector3.new(-PLOT_HALF, -2, -60), Vector3.new(PLOT_HALF, 0, PIT_BACK_Z))
	ground(Vector3.new(-PLOT_HALF, -2, PIT_BACK_Z), Vector3.new(PIT_MIN_X, 0, PIT_FRONT_Z))
	ground(Vector3.new(PIT_MAX_X, -2, PIT_BACK_Z), Vector3.new(PLOT_HALF, 0, PIT_FRONT_Z))

	-- Grubenwände
	local rock = folder("PitWalls", base)
	box(
		origin,
		Vector3.new(PIT_MIN_X - 4, PIT_BOTTOM, PIT_BACK_Z - 4),
		Vector3.new(PIT_MAX_X + 4, -2, PIT_BACK_Z),
		COLORS.Rock,
		Enum.Material.Slate,
		rock,
		"BackWall"
	)
	box(
		origin,
		Vector3.new(PIT_MIN_X - 4, PIT_BOTTOM, PIT_BACK_Z),
		Vector3.new(PIT_MIN_X, -2, PIT_FRONT_Z),
		COLORS.Rock,
		Enum.Material.Slate,
		rock,
		"LeftWall"
	)
	box(
		origin,
		Vector3.new(PIT_MAX_X, PIT_BOTTOM, PIT_BACK_Z),
		Vector3.new(PIT_MAX_X + 4, -2, PIT_FRONT_Z),
		COLORS.Rock,
		Enum.Material.Slate,
		rock,
		"RightWall"
	)
	-- Vorderwand: wird im Minen-Kameramodus clientseitig ausgeblendet
	local front = box(
		origin,
		Vector3.new(PIT_MIN_X - 4, PIT_BOTTOM, PIT_FRONT_Z),
		Vector3.new(PIT_MAX_X + 4, -2, PIT_FRONT_Z + 4),
		COLORS.Rock,
		Enum.Material.Slate,
		rock,
		"FrontWall"
	)
	front:SetAttribute("HideInMineView", true)
	box(
		origin,
		Vector3.new(PIT_MIN_X - 4, PIT_BOTTOM - 4, PIT_BACK_Z - 4),
		Vector3.new(PIT_MAX_X + 4, PIT_BOTTOM, PIT_FRONT_Z + 4),
		COLORS.DarkRock,
		Enum.Material.Slate,
		rock,
		"Bottom"
	)

	-- Unsichtbare Absperrung um die Grubenöffnung + sichtbares Geländer
	local barrier = folder("Barrier", base)
	local function wall(minV: Vector3, maxV: Vector3)
		local w = box(origin, minV, maxV, Color3.new(1, 1, 1), Enum.Material.SmoothPlastic, barrier, "InvisibleWall")
		w.Transparency = 1
	end
	wall(Vector3.new(PIT_MIN_X - 1, 0, PIT_FRONT_Z), Vector3.new(PIT_MAX_X + 1, 40, PIT_FRONT_Z + 1))
	wall(Vector3.new(PIT_MIN_X - 1, 0, PIT_BACK_Z - 1), Vector3.new(PIT_MAX_X + 1, 40, PIT_BACK_Z))
	wall(Vector3.new(PIT_MIN_X - 1, 0, PIT_BACK_Z), Vector3.new(PIT_MIN_X, 40, PIT_FRONT_Z))
	wall(Vector3.new(PIT_MAX_X, 0, PIT_BACK_Z), Vector3.new(PIT_MAX_X + 1, 40, PIT_FRONT_Z))

	local railing = folder("Railing", base)
	local function rail(fromV: Vector3, toV: Vector3)
		local len = (toV - fromV).Magnitude
		local mid = (fromV + toV) / 2
		P({
			Name = "Rail",
			Size = Vector3.new(0.4, 0.4, len),
			CFrame = origin * CFrame.lookAt(mid + Vector3.new(0, 3.2, 0), toV + Vector3.new(0, 3.2, 0)),
			Color = COLORS.DarkWood,
			Material = Enum.Material.Wood,
			Parent = railing,
		})
		local steps = math.floor(len / 6)
		for s = 0, steps do
			local pos = fromV:Lerp(toV, s / math.max(steps, 1))
			P({
				Name = "Post",
				Size = Vector3.new(0.5, 3.4, 0.5),
				CFrame = origin * CFrame.new(pos + Vector3.new(0, 1.7, 0)),
				Color = COLORS.DarkWood,
				Material = Enum.Material.Wood,
				Parent = railing,
			})
		end
	end
	rail(Vector3.new(PIT_MIN_X, 0, PIT_FRONT_Z + 0.5), Vector3.new(PIT_MAX_X, 0, PIT_FRONT_Z + 0.5))
	rail(Vector3.new(PIT_MAX_X - 0.5, 0, PIT_BACK_Z), Vector3.new(PIT_MAX_X - 0.5, 0, PIT_FRONT_Z))
	rail(Vector3.new(PIT_MIN_X + 7, 0, PIT_BACK_Z + 0.5), Vector3.new(PIT_MAX_X, 0, PIT_BACK_Z + 0.5))

	-- Schild mit Besitzername
	P({
		Name = "SignPost",
		Size = Vector3.new(1, 8, 1),
		CFrame = origin * CFrame.new(14, 4, 52),
		Color = COLORS.DarkWood,
		Material = Enum.Material.Wood,
		Parent = base,
	})
	local sign = P({
		Name = "Sign",
		Size = Vector3.new(22, 5, 0.6),
		CFrame = origin * CFrame.new(14, 9, 52),
		Color = COLORS.Wood,
		Material = Enum.Material.WoodPlanks,
		Parent = base,
	})
	local surface = Instance.new("SurfaceGui")
	surface.Name = "SignGui"
	surface.Face = Enum.NormalId.Front
	surface.CanvasSize = Vector2.new(440, 100)
	surface.LightInfluence = 0.3
	surface.Parent = sign
	local label = Instance.new("TextLabel")
	label.Name = "Owner"
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.TextColor3 = Color3.fromRGB(255, 240, 210)
	label.TextStrokeTransparency = 0.4
	label.Text = "Freie Mine"
	label.Parent = surface
	-- Schild zeigt zum Gehweg (+Z): Vorderseite des Parts zeigt nach -Z, also drehen
	sign.CFrame = origin * CFrame.new(14, 9, 52) * CFrame.Angles(0, math.pi, 0)

	-- Spawnpunkt des Plots (unsichtbar, nur als Position)
	P({
		Name = "SpawnPad",
		Size = Vector3.new(6, 0.2, 6),
		CFrame = origin * CFrame.new(MineBuilder.Layout.SpawnPos + Vector3.new(0, 0.1, 0)),
		Color = COLORS.Gold,
		Material = Enum.Material.Neon,
		Transparency = 0.6,
		CanCollide = false,
		Parent = base,
	})

	-- Deko: Laternen am Rand
	for _, x in { -40, 0, 40 } do
		local post = P({
			Name = "LampPost",
			Size = Vector3.new(0.6, 9, 0.6),
			CFrame = origin * CFrame.new(x, 4.5, 40),
			Color = COLORS.DarkMetal,
			Material = Enum.Material.Metal,
			Parent = base,
		})
		local lamp = P({
			Name = "Lamp",
			Size = Vector3.new(1.4, 1.4, 1.4),
			CFrame = post.CFrame * CFrame.new(0, 5, 0),
			Color = COLORS.Lamp,
			Material = Enum.Material.Neon,
			Parent = base,
		})
		addLight(lamp, 24, 1.2)
	end
end

----------------------------------------------------------------------
-- Ebenen (Schächte)
----------------------------------------------------------------------
local function levelY(i: number): number
	return -LH * i
end

local function buildCrate(name: string, cf: CFrame, size: Vector3, parent: Instance, customName: string): Model
	local custom = customAsset(customName)
	if custom then
		custom.Name = name
		custom:PivotTo(cf)
		custom.Parent = parent
		return custom
	end
	local m = model(name, parent)
	local thickness = 0.4
	local function side(offset: Vector3, s: Vector3)
		P({
			Name = "Side",
			Size = s,
			CFrame = cf * CFrame.new(offset),
			Color = COLORS.Wood,
			Material = Enum.Material.WoodPlanks,
			Parent = m,
		})
	end
	side(Vector3.new(0, thickness / 2, 0), Vector3.new(size.X, thickness, size.Z))
	side(Vector3.new(0, size.Y / 2, size.Z / 2 - thickness / 2), Vector3.new(size.X, size.Y, thickness))
	side(Vector3.new(0, size.Y / 2, -size.Z / 2 + thickness / 2), Vector3.new(size.X, size.Y, thickness))
	side(Vector3.new(size.X / 2 - thickness / 2, size.Y / 2, 0), Vector3.new(thickness, size.Y, size.Z))
	side(Vector3.new(-size.X / 2 + thickness / 2, size.Y / 2, 0), Vector3.new(thickness, size.Y, size.Z))
	-- Füllstand (wird vom Server je nach Lagerstand skaliert)
	local fill = P({
		Name = "Fill",
		Size = Vector3.new(size.X - thickness * 2, 0.05, size.Z - thickness * 2),
		CFrame = cf * CFrame.new(0, thickness, 0),
		Color = COLORS.DarkRock,
		Material = Enum.Material.Slate,
		CanCollide = false,
		Parent = m,
	})
	fill:SetAttribute("BaseY", thickness)
	fill:SetAttribute("MaxHeight", size.Y - thickness - 0.2)
	m:SetAttribute("CrateBase", cf)
	return m
end

--- Setzt die Füllhöhe einer Kiste (0..1)
function MineBuilder.setCrateFill(crate: Model, ratio: number, color: Color3?)
	local fill = crate:FindFirstChild("Fill")
	local base = crate:GetAttribute("CrateBase")
	if not fill or not fill:IsA("BasePart") or typeof(base) ~= "CFrame" then
		return
	end
	local maxH = fill:GetAttribute("MaxHeight")
	local baseY = fill:GetAttribute("BaseY")
	if type(maxH) ~= "number" or type(baseY) ~= "number" then
		return
	end
	ratio = math.clamp(ratio, 0, 1)
	local h = math.max(0.05, maxH * ratio)
	fill.Size = Vector3.new(fill.Size.X, h, fill.Size.Z)
	fill.CFrame = base * CFrame.new(0, baseY + h / 2, 0)
	fill.Transparency = if ratio <= 0 then 1 else 0
	if color then
		fill.Color = color
	end
end

local function buildLevel(mine: Instance, origin: CFrame, i: number): Model
	local def = Config.Shafts[i]
	local y = levelY(i)
	local m = model("Shaft_" .. i, mine)
	m:SetAttribute("Key", "Shaft:" .. i)
	m:SetAttribute("Index", i)

	-- Boden (Holzplanken auf Fels)
	box(
		origin,
		Vector3.new(LEVEL_MIN_X, y - 2, PIT_BACK_Z),
		Vector3.new(PIT_MAX_X, y, PIT_BACK_Z + 12),
		def.RockColor,
		Enum.Material.Slate,
		m,
		"Floor"
	)
	box(
		origin,
		Vector3.new(LEVEL_MIN_X, y, PIT_BACK_Z + 6),
		Vector3.new(PIT_MAX_X, y + 0.2, PIT_BACK_Z + 12),
		COLORS.Wood,
		Enum.Material.WoodPlanks,
		m,
		"Planks"
	)

	-- Erzadern in der Rückwand
	local rng = Random.new(i * 7919)
	local veins = model("Veins", m)
	for _ = 1, 9 do
		local x = rng:NextNumber(6, PIT_MAX_X - 3)
		local vy = y + rng:NextNumber(1.5, LH - 4)
		local s = rng:NextNumber(1.4, 3)
		local vein = P({
			Name = "Ore",
			Size = Vector3.new(s, s * rng:NextNumber(0.6, 1.1), 1.6),
			CFrame = origin * CFrame.new(x, vy, PIT_BACK_Z + 0.4) * CFrame.Angles(0, 0, rng:NextNumber(-0.6, 0.6)),
			Color = def.OreColor,
			Material = if i >= 5 then Enum.Material.Neon else Enum.Material.Glass,
			Parent = veins,
		})
		if i >= 5 then
			vein.Transparency = 0.15
		end
	end

	-- Stützbalken
	for _, x in { LEVEL_MIN_X + 1, 18, PIT_MAX_X - 1 } do
		P({
			Name = "Beam",
			Size = Vector3.new(1, LH - 2, 1),
			CFrame = origin * CFrame.new(x, y + (LH - 2) / 2, PIT_BACK_Z + 11),
			Color = COLORS.DarkWood,
			Material = Enum.Material.Wood,
			Parent = m,
		})
	end
	P({
		Name = "CrossBeam",
		Size = Vector3.new(PIT_MAX_X - LEVEL_MIN_X, 1, 1),
		CFrame = origin * CFrame.new((LEVEL_MIN_X + PIT_MAX_X) / 2, y + LH - 2.5, PIT_BACK_Z + 11),
		Color = COLORS.DarkWood,
		Material = Enum.Material.Wood,
		Parent = m,
	})

	-- Laterne
	local lantern = P({
		Name = "Lantern",
		Size = Vector3.new(0.9, 1.2, 0.9),
		CFrame = origin * CFrame.new(18, y + LH - 4, PIT_BACK_Z + 10),
		Color = COLORS.Lamp,
		Material = Enum.Material.Neon,
		CanCollide = false,
		Parent = m,
	})
	addLight(lantern, 26, 1.4)

	-- Schachtlager (Kiste neben dem Aufzug)
	buildCrate("Crate", origin * CFrame.new(-1, y, PIT_BACK_Z + 6), Vector3.new(4, 3, 4), m, "Crate")

	-- Kumpel
	local miners = folder("Miners", m)
	miners:SetAttribute("Count", 0)

	-- Manager-Platz (Figur wird erst bei Zuweisung gebaut)
	m:SetAttribute("ManagerSpot", origin * CFrame.new(3, y + 0.2, PIT_BACK_Z + 9) * CFrame.Angles(0, math.rad(200), 0))

	-- Klickfläche (unsichtbar, ganze Ebene)
	local hit = box(
		origin,
		Vector3.new(LEVEL_MIN_X, y, PIT_BACK_Z),
		Vector3.new(PIT_MAX_X, y + LH - 2, PIT_BACK_Z + 12),
		Color3.new(1, 1, 1),
		Enum.Material.SmoothPlastic,
		m,
		"Hitbox"
	)
	hit.Transparency = 1
	hit.CanCollide = false
	hit.CanTouch = false

	-- Info-Anker
	local anchor = P({
		Name = "InfoAnchor",
		Size = Vector3.new(0.2, 0.2, 0.2),
		CFrame = origin * CFrame.new(24, y + LH - 5.5, PIT_BACK_Z + 12.5),
		Transparency = 1,
		CanCollide = false,
		Parent = m,
	})
	MineBuilder.makeInfoBillboard(anchor, def.OreColor)

	m.PrimaryPart = hit
	return m
end

--- Setzt die Kumpel einer Ebene. signature beschreibt den gewünschten Zustand
--- (Anzahl + Avatar-IDs). Gibt die neu gebauten Figuren zurück (oder nil, wenn
--- sich nichts geändert hat), damit sie danach mit Avataren eingekleidet werden.
function MineBuilder.setMinerCount(
	level: Model,
	origin: CFrame,
	index: number,
	count: number,
	signature: string
): { Model }?
	local miners = level:FindFirstChild("Miners")
	if not miners then
		return nil
	end
	if miners:GetAttribute("Signature") == signature then
		return nil
	end
	miners:ClearAllChildren()
	miners:SetAttribute("Count", count)
	miners:SetAttribute("Signature", signature)
	local y = levelY(index)
	local spacing = (PIT_MAX_X - 8) / math.max(count, 1)
	local created = {}
	for n = 1, count do
		local x = 8 + spacing * (n - 0.5)
		local figure = buildFigure(
			"Miner_" .. n,
			origin * CFrame.new(x, y + 0.2, PIT_BACK_Z + 3.4),
			COLORS.Shirt,
			COLORS.Helmet,
			true
		)
		figure.Parent = miners
		table.insert(created, figure)
	end
	return created
end

local function buildLockedLevel(mine: Instance, origin: CFrame, i: number): Model
	local def = Config.Shafts[i]
	local y = levelY(i)
	local m = model("Locked", mine)
	m:SetAttribute("Index", i)
	box(
		origin,
		Vector3.new(LEVEL_MIN_X, y - 2, PIT_BACK_Z),
		Vector3.new(PIT_MAX_X, y, PIT_BACK_Z + 12),
		def.RockColor,
		Enum.Material.Slate,
		m,
		"Floor"
	)
	-- Bretter vor dem Eingang
	for n = 0, 3 do
		P({
			Name = "Board",
			Size = Vector3.new(PIT_MAX_X - LEVEL_MIN_X, 1.2, 0.4),
			CFrame = origin
				* CFrame.new((LEVEL_MIN_X + PIT_MAX_X) / 2, y + 2 + n * 2.6, PIT_BACK_Z + 11)
				* CFrame.Angles(0, 0, math.rad(if n % 2 == 0 then 2 else -2)),
			Color = COLORS.DarkWood,
			Material = Enum.Material.WoodPlanks,
			Parent = m,
		})
	end
	local sign = P({
		Name = "Sign",
		Size = Vector3.new(16, 6, 0.5),
		CFrame = origin * CFrame.new(18, y + 6, PIT_BACK_Z + 11.6) * CFrame.Angles(0, math.pi, 0),
		Color = COLORS.Wood,
		Material = Enum.Material.WoodPlanks,
		Parent = m,
	})
	local surface = Instance.new("SurfaceGui")
	surface.Face = Enum.NormalId.Front
	surface.CanvasSize = Vector2.new(320, 120)
	surface.LightInfluence = 0.2
	surface.Parent = sign
	local label = Instance.new("TextLabel")
	label.Name = "Text"
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.TextColor3 = Color3.fromRGB(255, 236, 200)
	label.TextStrokeTransparency = 0.3
	label.Text = string.format("🔒 Ebene %d: %s", i, def.Name)
	label.Parent = surface
	local click = Instance.new("ClickDetector")
	click.Name = "UnlockClick"
	click.MaxActivationDistance = 2000
	click.Parent = sign
	return m
end

local function buildRockFill(mine: Instance, origin: CFrame, i: number): Part
	local y = levelY(i)
	local rock = box(
		origin,
		Vector3.new(LEVEL_MIN_X, y - 2, PIT_BACK_Z),
		Vector3.new(PIT_MAX_X, y + LH - 2, PIT_FRONT_Z),
		COLORS.DarkRock,
		Enum.Material.Slate,
		mine,
		"RockFill_" .. i
	)
	return rock
end

----------------------------------------------------------------------
-- Aufzug
----------------------------------------------------------------------
local function buildCabin(cf: CFrame): Model
	local custom = customAsset("Cabin")
	if custom then
		custom.Name = "Cabin"
		custom:PivotTo(cf)
		return custom
	end
	local m = model("Cabin")
	local floor = P({
		Name = "Floor",
		Size = Vector3.new(5, 0.4, 5),
		CFrame = cf * CFrame.new(0, 0.2, 0),
		Color = COLORS.DarkMetal,
		Material = Enum.Material.DiamondPlate,
		Parent = m,
	})
	P({
		Name = "Roof",
		Size = Vector3.new(5, 0.4, 5),
		CFrame = cf * CFrame.new(0, 5.8, 0),
		Color = COLORS.Gold,
		Material = Enum.Material.Metal,
		Parent = m,
	})
	for _, off in
		{ Vector3.new(-2.3, 3, -2.3), Vector3.new(2.3, 3, -2.3), Vector3.new(-2.3, 3, 2.3), Vector3.new(2.3, 3, 2.3) }
	do
		P({
			Name = "Bar",
			Size = Vector3.new(0.4, 5.6, 0.4),
			CFrame = cf * CFrame.new(off),
			Color = COLORS.Gold,
			Material = Enum.Material.Metal,
			Parent = m,
		})
	end
	P({
		Name = "Back",
		Size = Vector3.new(5, 2, 0.3),
		CFrame = cf * CFrame.new(0, 1.4, -2.3),
		Color = COLORS.Metal,
		Material = Enum.Material.Metal,
		Parent = m,
	})
	P({
		Name = "Load",
		Size = Vector3.new(4, 1.4, 4),
		CFrame = cf * CFrame.new(0, 1.1, 0),
		Color = COLORS.DarkRock,
		Material = Enum.Material.Slate,
		Transparency = 1,
		Parent = m,
	})
	for _, d in m:GetDescendants() do
		if d:IsA("BasePart") then
			d.CanCollide = false
		end
	end
	m.PrimaryPart = floor
	return m
end

local function buildElevator(mine: Instance, origin: CFrame): Model
	local m = model("Elevator", mine)
	m:SetAttribute("Key", "Elevator")
	local L = MineBuilder.Layout
	local topY = 18
	local bottomY = PIT_BOTTOM
	local height = topY - bottomY
	-- Schachtgerüst (4 Pfosten)
	for _, off in { Vector2.new(-3, -3), Vector2.new(3, -3), Vector2.new(-3, 3), Vector2.new(3, 3) } do
		P({
			Name = "Post",
			Size = Vector3.new(0.7, height, 0.7),
			CFrame = origin * CFrame.new(L.ElevatorX + off.X, bottomY + height / 2, L.ElevatorZ + off.Y),
			Color = COLORS.DarkMetal,
			Material = Enum.Material.Metal,
			Parent = m,
		})
	end
	-- Kopf mit Seilrad
	P({
		Name = "Head",
		Size = Vector3.new(7.4, 1, 7.4),
		CFrame = origin * CFrame.new(L.ElevatorX, topY, L.ElevatorZ),
		Color = COLORS.DarkMetal,
		Material = Enum.Material.Metal,
		Parent = m,
	})
	P({
		Name = "Wheel",
		Size = Vector3.new(0.8, 5, 5),
		CFrame = origin * CFrame.new(L.ElevatorX, topY + 2.8, L.ElevatorZ),
		Color = COLORS.Gold,
		Material = Enum.Material.Metal,
		Shape = Enum.PartType.Cylinder,
		Parent = m,
	})
	-- Kabine (Ruheposition: Oberfläche)
	local cabin = buildCabin(origin * CFrame.new(L.ElevatorX, 0, L.ElevatorZ))
	cabin.Parent = m
	-- Seil
	P({
		Name = "Cable",
		Size = Vector3.new(0.25, topY - 6, 0.25),
		CFrame = origin * CFrame.new(L.ElevatorX, 6 + (topY - 6) / 2, L.ElevatorZ),
		Color = Color3.fromRGB(30, 30, 30),
		CanCollide = false,
		Parent = m,
	})
	-- Plattform an der Oberfläche (zum Depot)
	box(
		origin,
		Vector3.new(L.ElevatorX - 3, -0.6, L.ElevatorZ + 3.2),
		Vector3.new(L.ElevatorX + 3, 0, L.ElevatorZ + 6),
		COLORS.DarkMetal,
		Enum.Material.DiamondPlate,
		m,
		"Landing"
	)

	-- Aufzugslager (Depot) an der Oberfläche: hier kann gestohlen werden!
	local depot = buildCrate("Depot", origin * CFrame.new(L.DepotPos), Vector3.new(6, 4, 6), m, "Depot")
	local promptPart = P({
		Name = "PromptPart",
		Size = Vector3.new(1, 1, 1),
		CFrame = origin * CFrame.new(L.DepotPos + Vector3.new(0, 3, 0)),
		Transparency = 1,
		CanCollide = false,
		Parent = depot,
	})
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "StealPrompt"
	prompt.ActionText = "Stehlen"
	prompt.ObjectText = "Aufzugslager"
	prompt.HoldDuration = Config.Steal.HoldDuration
	prompt.MaxActivationDistance = Config.Steal.MaxActivationDistance
	prompt.RequiresLineOfSight = false
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.Enabled = Config.Steal.Enabled
	prompt.Parent = promptPart
	local depotAnchor = P({
		Name = "DepotAnchor",
		Size = Vector3.new(0.2, 0.2, 0.2),
		CFrame = origin * CFrame.new(L.DepotPos + Vector3.new(0, 8, 0)),
		Transparency = 1,
		CanCollide = false,
		Parent = m,
	})
	local depotInfo = MineBuilder.makeInfoBillboard(depotAnchor, COLORS.Gold)
	depotInfo.Name = "DepotInfo"

	-- Schutzkuppel (sichtbar, wenn die Basis abgeschlossen ist)
	local dome = P({
		Name = "LockDome",
		Size = Vector3.new(14, 14, 14),
		CFrame = origin * CFrame.new(L.DepotPos),
		Color = Color3.fromRGB(80, 170, 255),
		Material = Enum.Material.ForceField,
		Shape = Enum.PartType.Ball,
		Transparency = 1,
		CanCollide = false,
		Parent = m,
	})
	dome.CanQuery = false

	-- Manager-Platz neben dem Depot
	m:SetAttribute(
		"ManagerSpot",
		origin * CFrame.new(L.ElevatorX - 7, 0, L.ElevatorZ + 8) * CFrame.Angles(0, math.rad(160), 0)
	)

	-- Klickfläche: Aufzugsturm
	local hit = P({
		Name = "Hitbox",
		Size = Vector3.new(7, topY + 4, 7),
		CFrame = origin * CFrame.new(L.ElevatorX, (topY + 4) / 2 - 2, L.ElevatorZ),
		Transparency = 1,
		CanCollide = false,
		Parent = m,
	})
	hit.CanTouch = false

	local anchor = P({
		Name = "InfoAnchor",
		Size = Vector3.new(0.2, 0.2, 0.2),
		CFrame = origin * CFrame.new(L.ElevatorX, topY + 7, L.ElevatorZ),
		Transparency = 1,
		CanCollide = false,
		Parent = m,
	})
	MineBuilder.makeInfoBillboard(anchor, Color3.fromRGB(120, 200, 255))

	m.PrimaryPart = hit
	m:SetAttribute("TopY", 0)
	return m
end

----------------------------------------------------------------------
-- Lager / Verkauf
----------------------------------------------------------------------
local function buildCart(cf: CFrame): Model
	local custom = customAsset("Cart")
	if custom then
		custom.Name = "Cart"
		custom:PivotTo(cf)
		return custom
	end
	local m = model("Cart")
	local body = P({
		Name = "Body",
		Size = Vector3.new(3.2, 1.6, 2.4),
		CFrame = cf * CFrame.new(0, 1.4, 0),
		Color = COLORS.Metal,
		Material = Enum.Material.Metal,
		Parent = m,
	})
	P({
		Name = "Load",
		Size = Vector3.new(2.8, 0.8, 2),
		CFrame = cf * CFrame.new(0, 2.3, 0),
		Color = COLORS.Gold,
		Material = Enum.Material.Slate,
		Transparency = 1,
		Parent = m,
	})
	for _, off in
		{
			Vector3.new(-1, 0.45, 1.2),
			Vector3.new(1, 0.45, 1.2),
			Vector3.new(-1, 0.45, -1.2),
			Vector3.new(1, 0.45, -1.2),
		}
	do
		P({
			Name = "Wheel",
			Size = Vector3.new(0.3, 0.9, 0.9),
			CFrame = cf * CFrame.new(off) * CFrame.Angles(0, math.pi / 2, 0),
			Color = COLORS.DarkMetal,
			Shape = Enum.PartType.Cylinder,
			Parent = m,
		})
	end
	for _, d in m:GetDescendants() do
		if d:IsA("BasePart") then
			d.CanCollide = false
		end
	end
	m.PrimaryPart = body
	return m
end

local function buildWarehouse(mine: Instance, origin: CFrame): Model
	local m = model("Warehouse", mine)
	m:SetAttribute("Key", "Warehouse")
	local L = MineBuilder.Layout
	local center = Vector3.new(-44, 0, -31)
	local custom = customAsset("Warehouse")
	if custom then
		custom.Name = "Building"
		custom:PivotTo(origin * CFrame.new(center))
		custom.Parent = m
	else
		local building = model("Building", m)
		local w, d, h = 20, 18, 12
		-- Wände
		box(
			origin,
			center + Vector3.new(-w / 2, 0, -d / 2),
			center + Vector3.new(w / 2, h, -d / 2 + 1),
			COLORS.Wall,
			Enum.Material.Brick,
			building,
			"Wall"
		)
		box(
			origin,
			center + Vector3.new(-w / 2, 0, d / 2 - 1),
			center + Vector3.new(w / 2, h, d / 2),
			COLORS.Wall,
			Enum.Material.Brick,
			building,
			"Wall"
		)
		box(
			origin,
			center + Vector3.new(-w / 2, 0, -d / 2),
			center + Vector3.new(-w / 2 + 1, h, d / 2),
			COLORS.Wall,
			Enum.Material.Brick,
			building,
			"Wall"
		)
		-- Rechte Wand mit Tor (zum Depot)
		box(
			origin,
			center + Vector3.new(w / 2 - 1, 0, -d / 2),
			center + Vector3.new(w / 2, h, -3),
			COLORS.Wall,
			Enum.Material.Brick,
			building,
			"Wall"
		)
		box(
			origin,
			center + Vector3.new(w / 2 - 1, 0, 3),
			center + Vector3.new(w / 2, h, d / 2),
			COLORS.Wall,
			Enum.Material.Brick,
			building,
			"Wall"
		)
		box(
			origin,
			center + Vector3.new(w / 2 - 1, 7, -3),
			center + Vector3.new(w / 2, h, 3),
			COLORS.Wall,
			Enum.Material.Brick,
			building,
			"Wall"
		)
		-- Dach (zwei Schrägen)
		for side = -1, 1, 2 do
			P({
				Name = "Roof",
				Size = Vector3.new(w + 2, 1, d / 2 + 2.5),
				CFrame = origin
					* CFrame.new(center + Vector3.new(0, h + 2.4, side * d / 4))
					* CFrame.Angles(math.rad(side * 24), 0, 0),
				Color = COLORS.Roof,
				Material = Enum.Material.Slate,
				Parent = building,
			})
		end
		-- Schild
		local sign = P({
			Name = "Sign",
			Size = Vector3.new(10, 3, 0.4),
			CFrame = origin * CFrame.new(center + Vector3.new(0, h - 2, d / 2 + 0.3)) * CFrame.Angles(0, math.pi, 0),
			Color = COLORS.DarkWood,
			Material = Enum.Material.Wood,
			Parent = building,
		})
		local surface = Instance.new("SurfaceGui")
		surface.Face = Enum.NormalId.Front
		surface.CanvasSize = Vector2.new(300, 90)
		surface.LightInfluence = 0.2
		surface.Parent = sign
		local label = Instance.new("TextLabel")
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundTransparency = 1
		label.Font = Enum.Font.FredokaOne
		label.TextScaled = true
		label.TextColor3 = COLORS.Gold
		label.Text = "💰 HÄNDLER"
		label.Parent = surface
		-- Licht drinnen
		local lamp = P({
			Name = "Lamp",
			Size = Vector3.new(1, 1, 1),
			CFrame = origin * CFrame.new(center + Vector3.new(0, h - 1.5, 0)),
			Color = COLORS.Lamp,
			Material = Enum.Material.Neon,
			Parent = building,
		})
		addLight(lamp, 22, 1.2)
		-- Münzstapel als Deko
		for n = 1, 6 do
			P({
				Name = "Coins",
				Size = Vector3.new(0.4, 1.6, 1.6),
				CFrame = origin
					* CFrame.new(center + Vector3.new(-6 + n * 0.9, 0.2 + (n % 2) * 0.4, -5))
					* CFrame.Angles(0, 0, math.pi / 2),
				Color = COLORS.Gold,
				Material = Enum.Material.Metal,
				Shape = Enum.PartType.Cylinder,
				Parent = building,
			})
		end
	end

	-- Schienen zwischen Depot und Tor
	local railStart = L.DepotPos + Vector3.new(-4, 0, 0)
	local railEnd = L.WarehouseDoor
	for _, dz in { -1, 1 } do
		local a = railStart + Vector3.new(0, 0.1, dz)
		local b = railEnd + Vector3.new(0, 0.1, dz)
		P({
			Name = "Rail",
			Size = Vector3.new((a - b).Magnitude, 0.2, 0.3),
			CFrame = origin * CFrame.new((a + b) / 2),
			Color = COLORS.DarkMetal,
			Material = Enum.Material.Metal,
			Parent = m,
		})
	end
	local cart = buildCart(origin * CFrame.new(railStart) * CFrame.Angles(0, 0, 0))
	cart.Parent = m
	m:SetAttribute("CartFrom", railStart)
	m:SetAttribute("CartTo", railEnd)

	m:SetAttribute(
		"ManagerSpot",
		origin * CFrame.new(L.WarehouseDoor + Vector3.new(1, 0, 6)) * CFrame.Angles(0, math.rad(200), 0)
	)

	local hit = P({
		Name = "Hitbox",
		Size = Vector3.new(22, 16, 20),
		CFrame = origin * CFrame.new(center + Vector3.new(0, 8, 0)),
		Transparency = 1,
		CanCollide = false,
		Parent = m,
	})
	hit.CanTouch = false

	local anchor = P({
		Name = "InfoAnchor",
		Size = Vector3.new(0.2, 0.2, 0.2),
		CFrame = origin * CFrame.new(center + Vector3.new(0, 20, 0)),
		Transparency = 1,
		CanCollide = false,
		Parent = m,
	})
	MineBuilder.makeInfoBillboard(anchor, COLORS.Gold)

	m.PrimaryPart = hit
	return m
end

----------------------------------------------------------------------
-- Öffentliche API
----------------------------------------------------------------------
--- Baut den besitzerabhängigen Teil der Mine (Aufzug, Lager, Ebenen)
function MineBuilder.buildMine(plot: Model, origin: CFrame, shaftCount: number): Folder
	local existing = plot:FindFirstChild("Mine")
	if existing then
		existing:Destroy()
	end
	local mine = folder("Mine", plot)
	buildElevator(mine, origin)
	buildWarehouse(mine, origin)
	MineBuilder.syncLevels(plot, origin, shaftCount)
	return mine
end

--- Passt die Ebenen an die Anzahl freigeschalteter Schächte an
function MineBuilder.syncLevels(plot: Model, origin: CFrame, shaftCount: number)
	local mine = plot:FindFirstChild("Mine")
	if not mine then
		return
	end
	for i = 1, MAX_LEVELS do
		local level = mine:FindFirstChild("Shaft_" .. i)
		local rock = mine:FindFirstChild("RockFill_" .. i)
		if i <= shaftCount then
			if rock then
				rock:Destroy()
			end
			if not level then
				buildLevel(mine, origin, i)
			end
		else
			if level then
				level:Destroy()
			end
			if i > shaftCount + 1 and not rock then
				buildRockFill(mine, origin, i)
			elseif i == shaftCount + 1 and rock then
				rock:Destroy()
			end
		end
	end
	local locked = mine:FindFirstChild("Locked")
	if locked and locked:GetAttribute("Index") ~= shaftCount + 1 then
		locked:Destroy()
		locked = nil
	end
	if not locked and shaftCount < MAX_LEVELS then
		buildLockedLevel(mine, origin, shaftCount + 1)
	end
	plot:SetAttribute("LevelCount", shaftCount)
end

--- Entfernt die Mine (Plot wird frei)
function MineBuilder.clearMine(plot: Model)
	local mine = plot:FindFirstChild("Mine")
	if mine then
		mine:Destroy()
	end
end

--- Baut/entfernt die Manager-Figur einer Station. signature beschreibt den
--- gewünschten Manager ("" = keiner). Gibt eine neu gebaute Figur zurück, damit
--- sie mit dem Avatar eines Freundes eingekleidet werden kann.
function MineBuilder.setManagerFigure(station: Model, color: Color3?, abilityActive: boolean, signature: string): Model?
	local created: Model? = nil
	if station:GetAttribute("ManagerSig") ~= signature then
		station:SetAttribute("ManagerSig", signature)
		local old = station:FindFirstChild("Manager")
		if old then
			old:Destroy()
		end
		local spot = station:GetAttribute("ManagerSpot")
		if color and typeof(spot) == "CFrame" then
			local figure = buildFigure("Manager", spot, color, color, false)
			for _, d in figure:GetDescendants() do
				if d:IsA("BasePart") and d:GetAttribute("RarityColor") then
					d.Color = color
				end
			end
			figure.Parent = station
			created = figure
		end
	end
	local figure = station:FindFirstChild("Manager")
	if not figure then
		return created
	end
	local sparkle = figure:FindFirstChild("AbilitySparkle", true)
	if abilityActive and color and not sparkle then
		local body = figure:FindFirstChild("UpperTorso", true)
			or figure:FindFirstChild("Body", true)
			or figure:FindFirstChildWhichIsA("BasePart", true)
		if body and body:IsA("BasePart") then
			local s = Instance.new("Sparkles")
			s.Name = "AbilitySparkle"
			s.SparkleColor = color
			s.Parent = body
		end
	elseif not abilityActive and sparkle then
		sparkle:Destroy()
	end
	return created
end

----------------------------------------------------------------------
-- Avatare (Roblox-Avatare von Freunden mit Bauarbeiterhelm)
----------------------------------------------------------------------
local function weldTo(part: BasePart, target: BasePart)
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = target
	weld.Part1 = part
	weld.Parent = part
end

local function addHardHat(head: BasePart, color: Color3, parent: Instance)
	local top = head.CFrame * CFrame.new(0, head.Size.Y * 0.42, 0)
	local dome = P({
		Name = "HardHat",
		Size = Vector3.new(1.45, 1.45, 1.45),
		CFrame = top * CFrame.new(0, 0.18, 0),
		Color = color,
		Material = Enum.Material.SmoothPlastic,
		Shape = Enum.PartType.Ball,
		CanCollide = false,
		Parent = parent,
	})
	local brim = P({
		Name = "HardHatBrim",
		Size = Vector3.new(0.12, 1.75, 1.75),
		CFrame = top * CFrame.new(0, -0.08, -0.12) * CFrame.Angles(0, 0, math.pi / 2),
		Color = color,
		Material = Enum.Material.SmoothPlastic,
		Shape = Enum.PartType.Cylinder,
		CanCollide = false,
		Parent = parent,
	})
	local lamp = P({
		Name = "HatLamp",
		Size = Vector3.new(0.32, 0.32, 0.18),
		CFrame = top * CFrame.new(0, 0.25, -0.68),
		Color = COLORS.Lamp,
		Material = Enum.Material.Neon,
		CanCollide = false,
		Parent = parent,
	})
	for _, p in { dome, brim, lamp } do
		p.Anchored = false
		p.Massless = true
		p.CanQuery = false
		weldTo(p, head)
	end
end

local function addPickaxe(hand: BasePart, parent: Instance)
	local grip = hand.CFrame * CFrame.new(0, -0.15, 0) * CFrame.Angles(math.rad(-90), 0, 0)
	local handle = P({
		Name = "PickHandle",
		Size = Vector3.new(0.22, 0.22, 2.8),
		CFrame = grip * CFrame.new(0, 0, -1.1),
		Color = COLORS.Wood,
		CanCollide = false,
		Parent = parent,
	})
	local head = P({
		Name = "PickHead",
		Size = Vector3.new(0.28, 1.7, 0.32),
		CFrame = grip * CFrame.new(0, 0, -2.4),
		Color = COLORS.Metal,
		Material = Enum.Material.Metal,
		CanCollide = false,
		Parent = parent,
	})
	for _, p in { handle, head } do
		p.Anchored = false
		p.Massless = true
		p.CanQuery = false
		weldTo(p, hand)
	end
end

--- Ersetzt eine Platzhalter-Figur durch einen Avatar (Klon eines Templates).
--- Gibt die neue Figur zurück.
function MineBuilder.replaceWithAvatar(figure: Model, template: Model, hatColor: Color3, withPickaxe: boolean): Model?
	local floor = figure:GetAttribute("FloorCFrame")
	if typeof(floor) ~= "CFrame" or not figure.Parent then
		return nil
	end
	local avatar = template:Clone()
	avatar.Name = figure.Name
	local humanoid = avatar:FindFirstChildOfClass("Humanoid")
	local root = avatar:FindFirstChild("HumanoidRootPart")
	if not humanoid or not root or not root:IsA("BasePart") then
		avatar:Destroy()
		return nil
	end
	avatar.PrimaryPart = root
	local height = humanoid.HipHeight + root.Size.Y / 2
	avatar:PivotTo(floor * CFrame.new(0, height, 0))
	-- Hüte entfernen (der Bauarbeiterhelm kommt drauf), Haare bleiben
	for _, acc in avatar:GetChildren() do
		if acc:IsA("Accessory") and acc.AccessoryType == Enum.AccessoryType.Hat then
			acc:Destroy()
		end
	end
	local head = avatar:FindFirstChild("Head")
	if head and head:IsA("BasePart") then
		addHardHat(head, hatColor, avatar)
	end
	if withPickaxe then
		local hand = avatar:FindFirstChild("RightHand")
		if hand and hand:IsA("BasePart") then
			addPickaxe(hand, avatar)
		end
	end
	avatar:SetAttribute("FloorCFrame", floor)
	avatar:SetAttribute("IsAvatar", true)
	avatar.Parent = figure.Parent
	figure:Destroy()
	return avatar
end

return MineBuilder

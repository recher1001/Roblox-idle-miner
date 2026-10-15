--!strict
--[[
	WorldSetup
	==========
	Atmosphärische Beleuchtung (Lighting, Bloom, ColorCorrection, Atmosphere,
	SunRays, Sky) und die gemeinsame Welt (Gehweg, Platz, Spawn, Kulisse).
	Alle Werte kommen aus Config.Lighting.
]]

local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)

local MineBuilder = require(script.Parent.MineBuilder)

local WorldSetup = {}

local function getOrCreate<T>(className: string, name: string, parent: Instance): T
	local existing = parent:FindFirstChild(name)
	if existing and existing.ClassName == className then
		return (existing :: any) :: T
	end
	if existing then
		existing:Destroy()
	end
	local inst = Instance.new(className)
	inst.Name = name
	inst.Parent = parent
	return (inst :: any) :: T
end

function WorldSetup.applyLighting()
	local cfg = Config.Lighting
	Lighting.ClockTime = cfg.ClockTime
	Lighting.Brightness = cfg.Brightness
	Lighting.Ambient = cfg.Ambient
	Lighting.OutdoorAmbient = cfg.OutdoorAmbient
	Lighting.FogColor = cfg.FogColor
	Lighting.EnvironmentDiffuseScale = 0.6
	Lighting.EnvironmentSpecularScale = 0.6
	Lighting.GlobalShadows = true
	Lighting.ShadowSoftness = 0.25
	pcall(function()
		Lighting.Technology = Enum.Technology.Future
	end)

	-- Alte Effekte entfernen, damit nur unsere aktiv sind
	for _, child in Lighting:GetChildren() do
		if child:IsA("PostEffect") or child:IsA("Atmosphere") or child:IsA("Sky") then
			child:Destroy()
		end
	end

	local bloom = getOrCreate("BloomEffect", "MineBloom", Lighting) :: BloomEffect
	bloom.Intensity = cfg.Bloom.Intensity
	bloom.Size = cfg.Bloom.Size
	bloom.Threshold = cfg.Bloom.Threshold

	local cc = getOrCreate("ColorCorrectionEffect", "MineColor", Lighting) :: ColorCorrectionEffect
	cc.Brightness = cfg.ColorCorrection.Brightness
	cc.Contrast = cfg.ColorCorrection.Contrast
	cc.Saturation = cfg.ColorCorrection.Saturation
	cc.TintColor = cfg.ColorCorrection.TintColor

	local rays = getOrCreate("SunRaysEffect", "MineSunRays", Lighting) :: SunRaysEffect
	rays.Intensity = cfg.SunRays.Intensity
	rays.Spread = cfg.SunRays.Spread

	local atmo = getOrCreate("Atmosphere", "MineAtmosphere", Lighting) :: Atmosphere
	atmo.Density = cfg.Atmosphere.Density
	atmo.Offset = cfg.Atmosphere.Offset
	atmo.Color = cfg.Atmosphere.Color
	atmo.Decay = cfg.Atmosphere.Decay
	atmo.Glare = cfg.Atmosphere.Glare
	atmo.Haze = cfg.Atmosphere.Haze

	local sky = getOrCreate("Sky", "MineSky", Lighting) :: Sky
	sky.SunAngularSize = 14
	sky.MoonAngularSize = 8
	sky.StarCount = 1500
end

--- Gehweg, Platz in der Mitte, Spawn und Kulisse
function WorldSetup.buildWorld(plotCenters: { Vector3 })
	local existing = workspace:FindFirstChild("World")
	if existing then
		existing:Destroy()
	end
	local world = Instance.new("Folder")
	world.Name = "World"
	world.Parent = workspace

	local P = MineBuilder.Part
	local C = MineBuilder.Colors
	local minX, maxX = math.huge, -math.huge
	for _, c in plotCenters do
		minX = math.min(minX, c.X)
		maxX = math.max(maxX, c.X)
	end
	local width = (maxX - minX) + Config.World.PlotSpacing
	local centerX = (minX + maxX) / 2

	-- Gehweg vor allen Plots
	P({
		Name = "Walkway",
		Size = Vector3.new(width, 2, 40),
		CFrame = CFrame.new(centerX, -1, 80),
		Color = Color3.fromRGB(170, 150, 120),
		Material = Enum.Material.Cobblestone,
		Parent = world,
	})
	-- Wiese dahinter
	P({
		Name = "Meadow",
		Size = Vector3.new(width + 200, 2, 140),
		CFrame = CFrame.new(centerX, -1.05, 170),
		Color = C.Grass,
		Material = Enum.Material.Grass,
		Parent = world,
	})
	-- Seitliche Wiesen
	for side = -1, 1, 2 do
		P({
			Name = "SideMeadow",
			Size = Vector3.new(100, 2, 180),
			CFrame = CFrame.new(centerX + side * (width / 2 + 50), -1.05, 10),
			Color = C.Grass,
			Material = Enum.Material.Grass,
			Parent = world,
		})
	end
	-- Bergkulisse hinter den Minen
	local rng = Random.new(42)
	for n = 0, math.floor((width + 200) / 30) do
		local x = centerX - (width + 200) / 2 + n * 30 + rng:NextNumber(-6, 6)
		local h = rng:NextNumber(40, 110)
		local s = rng:NextNumber(40, 70)
		P({
			Name = "Mountain",
			Size = Vector3.new(s, h, s),
			CFrame = CFrame.new(x, h / 2 - 4, -95 - rng:NextNumber(0, 30))
				* CFrame.Angles(0, rng:NextNumber(0, math.pi), 0),
			Color = C.Rock:Lerp(C.DarkRock, rng:NextNumber(0, 0.6)),
			Material = Enum.Material.Rock,
			Parent = world,
		})
	end
	-- Rückseitiger Boden zur Kulisse
	P({
		Name = "BackGround",
		Size = Vector3.new(width + 200, 2, 80),
		CFrame = CFrame.new(centerX, -1.05, -100),
		Color = C.Dirt,
		Material = Enum.Material.Ground,
		Parent = world,
	})

	-- Zentraler Spawn (Fallback, Spieler werden zu ihrem Plot teleportiert)
	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "CentralSpawn"
	spawn.Anchored = true
	spawn.Size = Vector3.new(10, 1, 10)
	spawn.CFrame = CFrame.new(centerX, 0.5, 80)
	spawn.Color = C.Gold
	spawn.Material = Enum.Material.Neon
	spawn.Transparency = 0.3
	spawn.Neutral = true
	spawn.Duration = 0
	spawn.Parent = world

	WorldSetup.decorate(world, centerX, width)
end

----------------------------------------------------------------------
-- Map-Deko: Platz mit Brunnen, Leuchtschild, Bäume, Kristalle, Blumen,
-- Wimpelketten. Alles aus Parts, bunt und satt.
----------------------------------------------------------------------
local NEON = {
	Color3.fromRGB(255, 46, 140),
	Color3.fromRGB(255, 170, 0),
	Color3.fromRGB(150, 255, 0),
	Color3.fromRGB(0, 226, 255),
	Color3.fromRGB(160, 70, 255),
	Color3.fromRGB(255, 90, 40),
}

local function light(part: BasePart, color: Color3, range: number, brightness: number)
	local l = Instance.new("PointLight")
	l.Color = color
	l.Range = range
	l.Brightness = brightness
	l.Shadows = false
	l.Parent = part
end

local function buildFountain(parent: Instance, center: Vector3)
	local P = MineBuilder.Part
	local f = Instance.new("Model")
	f.Name = "Fountain"
	f.Parent = parent
	-- Platz
	P({
		Name = "Plaza",
		Size = Vector3.new(1, 54, 54),
		CFrame = CFrame.new(center + Vector3.new(0, 0.05, 0)) * CFrame.Angles(0, 0, math.pi / 2),
		Color = Color3.fromRGB(255, 220, 170),
		Material = Enum.Material.Pebble,
		Shape = Enum.PartType.Cylinder,
		Parent = f,
	})
	for i, c in NEON do
		local a = (i / #NEON) * math.pi * 2
		local ring = P({
			Name = "Tile",
			Size = Vector3.new(0.2, 7, 7),
			CFrame = CFrame.new(center + Vector3.new(math.cos(a) * 21, 0.62, math.sin(a) * 21))
				* CFrame.Angles(0, 0, math.pi / 2),
			Color = c,
			Material = Enum.Material.Neon,
			Shape = Enum.PartType.Cylinder,
			Parent = f,
		})
		ring.CanCollide = false
	end
	-- Becken + Wasser
	P({
		Name = "Basin",
		Size = Vector3.new(3, 26, 26),
		CFrame = CFrame.new(center + Vector3.new(0, 1.5, 0)) * CFrame.Angles(0, 0, math.pi / 2),
		Color = Color3.fromRGB(240, 240, 255),
		Material = Enum.Material.Marble,
		Shape = Enum.PartType.Cylinder,
		Parent = f,
	})
	local water = P({
		Name = "Water",
		Size = Vector3.new(0.4, 23, 23),
		CFrame = CFrame.new(center + Vector3.new(0, 3.05, 0)) * CFrame.Angles(0, 0, math.pi / 2),
		Color = Color3.fromRGB(0, 200, 255),
		Material = Enum.Material.Glass,
		Shape = Enum.PartType.Cylinder,
		Transparency = 0.2,
		Parent = f,
	})
	water.CanCollide = false
	P({
		Name = "Pillar",
		Size = Vector3.new(9, 3, 3),
		CFrame = CFrame.new(center + Vector3.new(0, 7.5, 0)) * CFrame.Angles(0, 0, math.pi / 2),
		Color = Color3.fromRGB(240, 240, 255),
		Material = Enum.Material.Marble,
		Shape = Enum.PartType.Cylinder,
		Parent = f,
	})
	local gem = P({
		Name = "Gem",
		Size = Vector3.new(5, 5, 5),
		CFrame = CFrame.new(center + Vector3.new(0, 14, 0)) * CFrame.Angles(math.rad(45), math.rad(45), 0),
		Color = Color3.fromRGB(255, 60, 200),
		Material = Enum.Material.Neon,
		Parent = f,
	})
	light(gem, Color3.fromRGB(255, 80, 220), 40, 2)
	local spray = Instance.new("ParticleEmitter")
	spray.Color = ColorSequence.new(Color3.fromRGB(120, 230, 255), Color3.fromRGB(255, 255, 255))
	spray.LightEmission = 0.6
	spray.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.6), NumberSequenceKeypoint.new(1, 0.1) })
	spray.Transparency = NumberSequence.new(0.2, 1)
	spray.Lifetime = NumberRange.new(1.2, 1.8)
	spray.Speed = NumberRange.new(14, 20)
	spray.SpreadAngle = Vector2.new(25, 25)
	spray.Acceleration = Vector3.new(0, -30, 0)
	spray.Rate = 60
	spray.EmissionDirection = Enum.NormalId.Top
	spray.Parent = gem
end

local function buildSign(parent: Instance, position: Vector3)
	local P = MineBuilder.Part
	for _, dx in { -18, 18 } do
		P({
			Name = "SignPost",
			Size = Vector3.new(2, 22, 2),
			CFrame = CFrame.new(position + Vector3.new(dx, -9, 0)),
			Color = Color3.fromRGB(120, 60, 255),
			Material = Enum.Material.SmoothPlastic,
			Parent = parent,
		})
	end
	local board = P({
		Name = "TitleSign",
		Size = Vector3.new(42, 12, 1.2),
		CFrame = CFrame.new(position),
		Color = Color3.fromRGB(40, 20, 120),
		Material = Enum.Material.SmoothPlastic,
		Parent = parent,
	})
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.CanvasSize = Vector2.new(840, 240)
	gui.LightInfluence = 0
	gui.Brightness = 2
	gui.Parent = board
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.Text = "⛏ IDLE MINER TYCOON ⛏"
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextStrokeTransparency = 0
	label.Parent = gui
	local gradient = Instance.new("UIGradient")
	gradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 60, 160)),
		ColorSequenceKeypoint.new(0.35, Color3.fromRGB(255, 200, 0)),
		ColorSequenceKeypoint.new(0.7, Color3.fromRGB(0, 230, 255)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(170, 80, 255)),
	})
	gradient.Parent = label
	-- Neon-Rahmen
	for _, dy in { -6.3, 6.3 } do
		local bar = P({
			Name = "Neon",
			Size = Vector3.new(43, 0.6, 1.4),
			CFrame = CFrame.new(position + Vector3.new(0, dy, 0)),
			Color = Color3.fromRGB(0, 230, 255),
			Material = Enum.Material.Neon,
			Parent = parent,
		})
		light(bar, Color3.fromRGB(0, 230, 255), 24, 1)
	end
end

local function buildTree(parent: Instance, position: Vector3, rng: Random)
	local P = MineBuilder.Part
	local h = rng:NextNumber(10, 16)
	P({
		Name = "Trunk",
		Size = Vector3.new(h, 1.8, 1.8),
		CFrame = CFrame.new(position + Vector3.new(0, h / 2, 0)) * CFrame.Angles(0, 0, math.pi / 2),
		Color = Color3.fromRGB(130, 80, 50),
		Material = Enum.Material.Wood,
		Shape = Enum.PartType.Cylinder,
		Parent = parent,
	})
	local blossom = rng:NextNumber() < 0.35
	local leaf = if blossom
		then Color3.fromRGB(255, 120, 200)
		else Color3.fromHSV(rng:NextNumber(0.25, 0.4), 0.85, rng:NextNumber(0.7, 0.9))
	for n = 1, 3 do
		local s = rng:NextNumber(6, 9)
		P({
			Name = "Leaves",
			Size = Vector3.new(s, s, s),
			CFrame = CFrame.new(
				position
					+ Vector3.new(
						rng:NextNumber(-2.5, 2.5),
						h + rng:NextNumber(-1, 3) + n * 0.6,
						rng:NextNumber(-2.5, 2.5)
					)
			),
			Color = leaf,
			Material = Enum.Material.Grass,
			Shape = Enum.PartType.Ball,
			Parent = parent,
		})
	end
end

local function buildCrystals(parent: Instance, position: Vector3, rng: Random)
	local P = MineBuilder.Part
	local color = NEON[rng:NextInteger(1, #NEON)]
	for n = 1, rng:NextInteger(3, 5) do
		local h = rng:NextNumber(4, 10)
		local c = P({
			Name = "Crystal",
			Size = Vector3.new(1.6, h, 1.6),
			CFrame = CFrame.new(
				position + Vector3.new(rng:NextNumber(-2.5, 2.5), h / 2 - 0.5, rng:NextNumber(-2.5, 2.5))
			) * CFrame.Angles(rng:NextNumber(-0.4, 0.4), rng:NextNumber(0, math.pi), rng:NextNumber(-0.4, 0.4)),
			Color = color,
			Material = Enum.Material.Neon,
			Transparency = 0.1,
			Parent = parent,
		})
		if n == 1 then
			light(c, color, 16, 1.2)
		end
	end
end

local function buildFlowers(parent: Instance, position: Vector3, rng: Random)
	local P = MineBuilder.Part
	for _ = 1, 6 do
		local f = P({
			Name = "Flower",
			Size = Vector3.new(1.1, 1.1, 1.1),
			CFrame = CFrame.new(position + Vector3.new(rng:NextNumber(-3, 3), 0.5, rng:NextNumber(-3, 3))),
			Color = NEON[rng:NextInteger(1, #NEON)],
			Material = Enum.Material.SmoothPlastic,
			Shape = Enum.PartType.Ball,
			Parent = parent,
		})
		f.CanCollide = false
	end
end

local function buildBunting(parent: Instance, fromX: number, toX: number, z: number, y: number)
	local P = MineBuilder.Part
	local len = toX - fromX
	P({
		Name = "Rope",
		Size = Vector3.new(len, 0.15, 0.15),
		CFrame = CFrame.new((fromX + toX) / 2, y, z),
		Color = Color3.fromRGB(255, 255, 255),
		CanCollide = false,
		Parent = parent,
	})
	local i = 0
	for x = fromX + 3, toX - 3, 6 do
		i += 1
		local flag = Instance.new("WedgePart")
		flag.Name = "Flag"
		flag.Anchored = true
		flag.CanCollide = false
		flag.CanQuery = false
		flag.Size = Vector3.new(0.1, 2.4, 2)
		flag.CFrame = CFrame.new(x, y - 1.3, z) * CFrame.Angles(math.pi, math.pi / 2, 0)
		flag.Color = NEON[(i % #NEON) + 1]
		flag.Material = Enum.Material.SmoothPlastic
		flag.Parent = parent
	end
end

function WorldSetup.decorate(world: Instance, centerX: number, width: number)
	local deco = Instance.new("Folder")
	deco.Name = "Decoration"
	deco.Parent = world
	local rng = Random.new(1337)

	local plaza = Vector3.new(centerX, 0, 128)
	buildFountain(deco, plaza)
	buildSign(deco, Vector3.new(centerX, 22, 160))

	-- Wimpelketten über dem Gehweg
	local half = width / 2
	buildBunting(deco, centerX - half, centerX + half, 62, 16)
	buildBunting(deco, centerX - half, centerX + half, 98, 16)
	for x = centerX - half, centerX + half, 60 do
		for _, z in { 62, 98 } do
			MineBuilder.Part({
				Name = "Pole",
				Size = Vector3.new(0.8, 17, 0.8),
				CFrame = CFrame.new(x, 8.5, z),
				Color = Color3.fromRGB(255, 255, 255),
				Material = Enum.Material.SmoothPlastic,
				Parent = deco,
			})
		end
	end

	-- Bäume, Kristalle, Blumen auf der Wiese (nicht auf Platz/Gehweg)
	local function freeSpot(): Vector3?
		for _ = 1, 10 do
			local p = Vector3.new(rng:NextNumber(centerX - half - 80, centerX + half + 80), 0, rng:NextNumber(104, 235))
			if (p - plaza).Magnitude > 40 and math.abs(p.X - centerX) > 26 or p.Z > 175 then
				return p
			end
		end
		return nil
	end
	for _ = 1, 40 do
		local p = freeSpot()
		if p then
			buildTree(deco, p, rng)
		end
	end
	for _ = 1, 22 do
		local p = freeSpot()
		if p then
			buildCrystals(deco, p, rng)
		end
	end
	for _ = 1, 30 do
		local p = freeSpot()
		if p then
			buildFlowers(deco, p, rng)
		end
	end
	-- Kristalle vor den Bergen hinter den Minen
	for n = 0, math.floor((width + 160) / 45) do
		buildCrystals(deco, Vector3.new(centerX - half - 80 + n * 45 + rng:NextNumber(-8, 8), 0, -72), rng)
	end
end

return WorldSetup

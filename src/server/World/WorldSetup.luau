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
	label.Text = "⛏️ IDLE MINER TYCOON ⛏️"
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

----------------------------------------------------------------------
-- Shop-Stand (Marktstand wie in Grow a Garden) mit Händler-NPC.
-- Vorderseite zeigt nach -Z (zu den Minen/zum Gehweg).
-- Der ProximityPrompt öffnet auf dem Client das Shop-Menü.
----------------------------------------------------------------------
local WOOD_DARK = Color3.fromRGB(86, 58, 40)
local WOOD = Color3.fromRGB(116, 76, 48)
local SKIN = Color3.fromRGB(234, 184, 146)
local DENIM = Color3.fromRGB(52, 98, 178)

local function stallPart(
	parent: Instance,
	name: string,
	size: Vector3,
	cf: CFrame,
	color: Color3,
	material: Enum.Material?
): Part
	return MineBuilder.Part({
		Name = name,
		Size = size,
		CFrame = cf,
		Color = color,
		Material = material or Enum.Material.WoodPlanks,
		Parent = parent,
	})
end

--- Händler im klassischen Roblox-Look: Latzhose, Cowboyhut, Smiley-Gesicht
local function buildShopkeeper(parent: Instance, feet: CFrame, overalls: Color3): Model
	local npc = Instance.new("Model")
	npc.Name = "Shopkeeper"
	npc.Parent = parent
	local function part(name: string, size: Vector3, offset: Vector3, color: Color3, mat: Enum.Material?): Part
		local p = stallPart(npc, name, size, feet * CFrame.new(offset), color, mat or Enum.Material.SmoothPlastic)
		p.CanCollide = false
		return p
	end
	part("LeftLeg", Vector3.new(1, 2, 1), Vector3.new(-0.5, 1, 0), overalls)
	part("RightLeg", Vector3.new(1, 2, 1), Vector3.new(0.5, 1, 0), overalls)
	part("Torso", Vector3.new(2, 2, 1), Vector3.new(0, 3, 0), SKIN)
	-- Latzhose (Latz + Träger)
	part("Bib", Vector3.new(1.4, 1.3, 1.05), Vector3.new(0, 2.65, 0), overalls)
	part("StrapL", Vector3.new(0.3, 0.9, 1.05), Vector3.new(-0.55, 3.55, 0), overalls)
	part("StrapR", Vector3.new(0.3, 0.9, 1.05), Vector3.new(0.55, 3.55, 0), overalls)
	part("Belt", Vector3.new(2.02, 0.5, 1.03), Vector3.new(0, 2.15, 0), overalls)
	part("LeftArm", Vector3.new(1, 2, 1), Vector3.new(-1.5, 3, 0), SKIN)
	part("RightArm", Vector3.new(1, 2, 1), Vector3.new(1.5, 3, 0), SKIN)
	local head = part("Head", Vector3.new(2, 1, 1), Vector3.new(0, 4.5, 0), SKIN)
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Head
	mesh.Scale = Vector3.new(1.25, 1.25, 1.25)
	mesh.Parent = head
	local face = Instance.new("Decal")
	face.Name = "face"
	face.Face = Enum.NormalId.Front
	face.Texture = "rbxasset://textures/face.png"
	face.Parent = head
	-- Cowboyhut
	local hat = Color3.fromRGB(122, 82, 46)
	local brim = part("HatBrim", Vector3.new(0.2, 3.6, 3.6), Vector3.new(0, 5.1, 0), hat)
	brim.Shape = Enum.PartType.Cylinder
	brim.CFrame = feet * CFrame.new(0, 5.1, 0) * CFrame.Angles(0, 0, math.pi / 2)
	local crown = part("HatCrown", Vector3.new(1.2, 1.8, 1.8), Vector3.new(0, 5.75, 0), hat)
	crown.Shape = Enum.PartType.Cylinder
	crown.CFrame = feet * CFrame.new(0, 5.75, 0) * CFrame.Angles(0, 0, math.pi / 2)
	local band = part("HatBand", Vector3.new(0.3, 1.85, 1.85), Vector3.new(0, 5.35, 0), Color3.fromRGB(70, 44, 26))
	band.Shape = Enum.PartType.Cylinder
	band.CFrame = feet * CFrame.new(0, 5.35, 0) * CFrame.Angles(0, 0, math.pi / 2)
	npc.PrimaryPart = head
	return npc
end

export type StallStyle = {
	Name: string,
	AwningA: Color3,
	AwningB: Color3,
	Sign: string,
	Keeper: string,
	Prompt: string,
	Panel: string,
	Eggs: boolean, -- Eier statt Edelsteine auf der Theke
	Overalls: Color3,
}

local SHOP_STYLE: StallStyle = {
	Name = "ShopStall",
	AwningA = Color3.fromRGB(30, 130, 255),
	AwningB = Color3.fromRGB(245, 248, 255),
	Sign = "SHOP",
	Keeper = "🛒 Händler Hans",
	Prompt = "Shop öffnen",
	Panel = "Shop",
	Eggs = false,
	Overalls = DENIM,
}

local EGG_STYLE: StallStyle = {
	Name = "EggStall",
	AwningA = Color3.fromRGB(255, 70, 170),
	AwningB = Color3.fromRGB(255, 226, 60),
	Sign = "EIER",
	Keeper = "🥚 Eier-Emma",
	Prompt = "Eier & Pets",
	Panel = "Pets",
	Eggs = true,
	Overalls = Color3.fromRGB(220, 60, 150),
}

local function buildShopStall(parent: Instance, origin: CFrame, style: StallStyle)
	local stall = Instance.new("Model")
	stall.Name = style.Name
	stall.Parent = parent
	local function at(x: number, y: number, z: number): CFrame
		return origin * CFrame.new(x, y, z)
	end
	-- Pfosten (hinten höher -> schräges Dach)
	for _, x in { -7.5, 7.5 } do
		stallPart(stall, "Post", Vector3.new(1, 9.4, 1), at(x, 4.7, -3.6), WOOD_DARK, Enum.Material.Wood)
		stallPart(stall, "Post", Vector3.new(1, 11.4, 1), at(x, 5.7, 3.6), WOOD_DARK, Enum.Material.Wood)
	end
	-- Theke vorne: zwei Bretter + graue Ablage
	stallPart(stall, "Counter", Vector3.new(15, 1.3, 0.7), at(0, 1.2, -3.6), WOOD)
	stallPart(stall, "Counter", Vector3.new(15, 1.3, 0.7), at(0, 2.75, -3.6), WOOD)
	stallPart(
		stall,
		"CounterTop",
		Vector3.new(16.2, 0.4, 1.6),
		at(0, 3.6, -3.4),
		Color3.fromRGB(96, 96, 108),
		Enum.Material.SmoothPlastic
	)
	-- Ware auf der Theke: Edelsteine + Geldsack oder bunte Eier
	if style.Eggs then
		for i, egg in Config.Eggs do
			local e = stallPart(
				stall,
				"Egg",
				Vector3.new(1.3, 1.7, 1.3),
				at(-7.4 + i * 2.1, 4.65, -3.3) * CFrame.Angles(0, 0, math.rad((i % 2) * 14 - 7)),
				egg.Color,
				Enum.Material.SmoothPlastic
			)
			e.CanCollide = false
			local mesh = Instance.new("SpecialMesh")
			mesh.MeshType = Enum.MeshType.Sphere
			mesh.Parent = e
		end
	end
	local gemColors: { Color3 } = if style.Eggs
		then {}
		else {
			Color3.fromRGB(0, 226, 255),
			Color3.fromRGB(255, 60, 170),
			Color3.fromRGB(150, 255, 0),
			Color3.fromRGB(255, 200, 0),
		}
	for i, c in gemColors do
		local gem = stallPart(
			stall,
			"Gem",
			Vector3.new(0.9, 0.9, 0.9),
			at(-5.8 + i * 1.1, 4.3, -3.3) * CFrame.Angles(0.6, i, 0.4),
			c,
			Enum.Material.Neon
		)
		gem.CanCollide = false
	end
	if not style.Eggs then
		local bag = stallPart(
			stall,
			"MoneyBag",
			Vector3.new(1.6, 1.6, 1.6),
			at(4.6, 4.6, -3.3),
			Color3.fromRGB(200, 160, 90),
			Enum.Material.Fabric
		)
		bag.Shape = Enum.PartType.Ball
	end
	-- Dach: blau-weiße Streifen, hinten hoch, vorne tief
	local slope = math.atan(2 / 8.6)
	local stripes = 8
	for i = 0, stripes - 1 do
		local x = -8 + 1 + i * 2
		stallPart(
			stall,
			"Awning",
			Vector3.new(2, 0.45, 9.4),
			at(x, 10.4, 0) * CFrame.Angles(-slope, 0, 0),
			if i % 2 == 0 then style.AwningA else style.AwningB,
			Enum.Material.SmoothPlastic
		)
	end
	stallPart(
		stall,
		"AwningTrim",
		Vector3.new(16.4, 0.7, 0.5),
		at(0, 9.1, -4.6),
		style.AwningA,
		Enum.Material.SmoothPlastic
	)

	-- Schild "SHOP" daneben (wie im Referenzbild)
	stallPart(stall, "SignPost", Vector3.new(1, 4.5, 1), at(-11.5, 2.25, -3.6), WOOD_DARK, Enum.Material.Wood)
	local board =
		stallPart(stall, "SignBoard", Vector3.new(6.5, 4.2, 0.6), at(-11.5, 5.6, -3.6), WOOD, Enum.Material.WoodPlanks)
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.CanvasSize = Vector2.new(320, 210)
	gui.LightInfluence = 0.4
	gui.Parent = board
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(0.92, 0.9)
	label.Position = UDim2.fromScale(0.04, 0.05)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.Text = style.Sign
	label.TextColor3 = Color3.fromRGB(255, 255, 255)
	label.TextStrokeTransparency = 0
	label.TextStrokeColor3 = Color3.fromRGB(30, 18, 12)
	label.Parent = gui

	-- Händler hinter der Theke
	local npc = buildShopkeeper(stall, at(0, 0, -1.4), style.Overalls)
	local head = npc:FindFirstChild("Head") :: BasePart
	local tag = Instance.new("BillboardGui")
	tag.Size = UDim2.fromScale(8, 2.4)
	tag.StudsOffset = Vector3.new(0, 3.4, 0)
	tag.MaxDistance = 90
	tag.LightInfluence = 0
	tag.Adornee = head
	tag.Parent = head
	local tagLabel = Instance.new("TextLabel")
	tagLabel.Size = UDim2.fromScale(1, 1)
	tagLabel.BackgroundTransparency = 1
	tagLabel.Font = Enum.Font.FredokaOne
	tagLabel.TextScaled = true
	tagLabel.Text = style.Keeper
	tagLabel.TextColor3 = Color3.fromRGB(255, 220, 60)
	tagLabel.TextStrokeTransparency = 0
	tagLabel.Parent = tag

	-- Prompt an der Theke: öffnet das Shop-Menü
	local promptPart = stallPart(stall, "PromptPart", Vector3.new(4, 3, 1), at(0, 3, -4.2), Color3.new(1, 1, 1))
	promptPart.Transparency = 1
	promptPart.CanCollide = false
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = style.Prompt
	prompt.ObjectText = string.gsub(style.Keeper, "^%S+%s", "")
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 12
	prompt.RequiresLineOfSight = false
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt:SetAttribute("OpenPanel", style.Panel)
	prompt.Parent = promptPart
end

WorldSetup.ShopStallOffset = Vector3.new(-44, 0, 112)
WorldSetup.EggStallOffset = Vector3.new(44, 0, 112)
WorldSetup.AfkZoneOffset = Vector3.new(0, 0, 208)
-- Tafeln der Bestenlisten (der LeaderboardService beschriftet sie)
WorldSetup.LeaderboardBoards = {} :: { [string]: BasePart }

--- Große Tafel mit Pfosten und Neon-Rahmen. Vorderseite zeigt nach -Z.
local function buildLeaderboard(parent: Instance, id: string, position: Vector3, color: Color3)
	local model = Instance.new("Model")
	model.Name = "Leaderboard_" .. id
	model.Parent = parent
	local width, height = 18, 24
	local bottom = 3
	for _, x in { -width / 2 - 0.6, width / 2 + 0.6 } do
		MineBuilder.Part({
			Name = "Post",
			Size = Vector3.new(1.4, bottom + height + 1, 1.4),
			CFrame = CFrame.new(position + Vector3.new(x, (bottom + height + 1) / 2, 0)),
			Color = Color3.fromRGB(60, 40, 120),
			Material = Enum.Material.SmoothPlastic,
			Parent = model,
		})
	end
	local frame = MineBuilder.Part({
		Name = "Frame",
		Size = Vector3.new(width + 1.2, height + 1.2, 1),
		CFrame = CFrame.new(position + Vector3.new(0, bottom + height / 2, 0.3)),
		Color = color,
		Material = Enum.Material.Neon,
		Parent = model,
	})
	light(frame, color, 26, 1.2)
	local board = MineBuilder.Part({
		Name = "Board",
		Size = Vector3.new(width, height, 1),
		CFrame = CFrame.new(position + Vector3.new(0, bottom + height / 2, 0)),
		Color = Color3.fromRGB(40, 22, 110),
		Material = Enum.Material.SmoothPlastic,
		Parent = model,
	})
	WorldSetup.LeaderboardBoards[id] = board
end

-- Wird von decorate() gesetzt, der AfkService prüft damit die Position
WorldSetup.AfkZone = nil :: { Center: Vector3, Radius: number }?

--- AFK-Zone: leuchtende Plattform mit Schild. Wer drinsteht, bekommt
--- Gems und das Offline-Einkommen seiner Minen (siehe AfkService).
local function buildAfkZone(parent: Instance, center: Vector3)
	local zone = Instance.new("Model")
	zone.Name = "AfkZone"
	zone.Parent = parent
	local radius = Config.Afk.Radius
	local function disc(name: string, r: number, height: number, y: number, color: Color3, mat: Enum.Material): Part
		local p = MineBuilder.Part({
			Name = name,
			Size = Vector3.new(height, r * 2, r * 2),
			CFrame = CFrame.new(center + Vector3.new(0, y, 0)) * CFrame.Angles(0, 0, math.pi / 2),
			Color = color,
			Material = mat,
			Parent = zone,
		})
		p.Shape = Enum.PartType.Cylinder
		return p
	end
	disc("Rim", radius + 1.2, 0.8, 0.1, Color3.fromRGB(255, 255, 255), Enum.Material.SmoothPlastic)
	local glow = disc("Glow", radius + 0.4, 0.9, 0.15, Color3.fromRGB(160, 70, 255), Enum.Material.Neon)
	disc("Floor", radius - 0.6, 1, 0.2, Color3.fromRGB(70, 30, 170), Enum.Material.SmoothPlastic)
	light(glow, Color3.fromRGB(170, 90, 255), 30, 2)
	-- schwebende Kristalle rundherum
	for i = 0, 5 do
		local a = i / 6 * math.pi * 2
		local crystal = MineBuilder.Part({
			Name = "Crystal",
			Size = Vector3.new(1.6, 3.2, 1.6),
			CFrame = CFrame.new(center + Vector3.new(math.cos(a) * (radius + 3), 5, math.sin(a) * (radius + 3)))
				* CFrame.Angles(0, a, math.rad(20)),
			Color = NEON[i + 1],
			Material = Enum.Material.Neon,
			Parent = zone,
		})
		crystal.CanCollide = false
	end
	-- Schild über der Zone
	local anchor = MineBuilder.Part({
		Name = "SignAnchor",
		Size = Vector3.new(1, 1, 1),
		CFrame = CFrame.new(center + Vector3.new(0, 12, 0)),
		Color = Color3.new(1, 1, 1),
		Parent = zone,
	})
	anchor.Transparency = 1
	anchor.CanCollide = false
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromScale(22, 7)
	gui.MaxDistance = 220
	gui.LightInfluence = 0
	gui.Parent = anchor
	local title = Instance.new("TextLabel")
	title.Size = UDim2.fromScale(1, 0.6)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.FredokaOne
	title.TextScaled = true
	title.Text = "💤 AFK-ZONE 💤"
	title.TextColor3 = Color3.fromRGB(220, 170, 255)
	title.TextStrokeTransparency = 0
	title.Parent = gui
	local sub = Instance.new("TextLabel")
	sub.Size = UDim2.fromScale(1, 0.4)
	sub.Position = UDim2.fromScale(0, 0.6)
	sub.BackgroundTransparency = 1
	sub.Font = Enum.Font.FredokaOne
	sub.TextScaled = true
	sub.Text = string.format("+%d 💎 pro Minute + Minen-Geld", Config.Afk.Gems)
	sub.TextColor3 = Color3.fromRGB(255, 255, 255)
	sub.TextStrokeTransparency = 0
	sub.Parent = gui
	WorldSetup.AfkZone = { Center = center, Radius = radius }
end

function WorldSetup.decorate(world: Instance, centerX: number, width: number)
	local deco = Instance.new("Folder")
	deco.Name = "Decoration"
	deco.Parent = world
	local rng = Random.new(1337)

	local plaza = Vector3.new(centerX, 0, 128)
	buildFountain(deco, plaza)
	buildSign(deco, Vector3.new(centerX, 22, 160))
	local stallPos = Vector3.new(centerX, 0, 0) + WorldSetup.ShopStallOffset
	buildShopStall(deco, CFrame.new(stallPos), SHOP_STYLE)
	local eggStallPos = Vector3.new(centerX, 0, 0) + WorldSetup.EggStallOffset
	buildShopStall(deco, CFrame.new(eggStallPos), EGG_STYLE)
	local afkPos = Vector3.new(centerX, 0, 0) + WorldSetup.AfkZoneOffset
	buildAfkZone(deco, afkPos)
	local moneyBoardPos = Vector3.new(centerX, 0, 0) + Config.Leaderboards.MoneyOffset
	local incomeBoardPos = Vector3.new(centerX, 0, 0) + Config.Leaderboards.IncomeOffset
	buildLeaderboard(deco, "Money", moneyBoardPos, Color3.fromRGB(255, 200, 0))
	buildLeaderboard(deco, "Income", incomeBoardPos, Color3.fromRGB(0, 226, 255))

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
			local nearStall = (p - stallPos).Magnitude < 20
				or (p - eggStallPos).Magnitude < 20
				or (p - afkPos).Magnitude < Config.Afk.Radius + 12
				or (p - moneyBoardPos).Magnitude < 22
				or (p - incomeBoardPos).Magnitude < 22
			if not nearStall and ((p - plaza).Magnitude > 40 and math.abs(p.X - centerX) > 26 or p.Z > 175) then
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

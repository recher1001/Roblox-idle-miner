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
end

return WorldSetup

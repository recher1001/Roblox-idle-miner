--!strict
--[[
	MineVisuals
	===========
	Animiert ALLE Minen auf dem Client (auch die der anderen Spieler) anhand
	der Zyklus-Attribute, die der Server setzt (CycleStart/CycleEnd/CycleId/Running):

	  Schacht : Kumpel schwingen die Spitzhacke, Gesteinspartikel spritzen,
	            fertige Zyklen schicken Erzbrocken in die Schachtkiste
	  Aufzug  : Kabine fährt runter und wieder hoch, Seil + Rad bewegen sich,
	            oben fliegt das Erz ins Aufzugslager
	  Händler : Wagen fährt auf Schienen zum Händler, Münzen sprühen

	Alles hier ist rein visuell und lokal - der Server rechnet unabhängig davon.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Clock = require(Shared.Clock)
local Config = require(Shared.Config)

local PlotLocator = require(script.Parent.Parent.PlotLocator)
local Effects = require(script.Parent.Effects)

local MineVisuals = {}

local LH = Config.World.LevelHeight
local MAX_CHUNKS = 220

type CycleTrack = { LastId: number, LastRunning: boolean }
type Chunk = {
	Part: Part,
	P0: Vector3,
	P1: Vector3,
	P2: Vector3,
	Start: number,
	Duration: number,
}

local tracks: { [Instance]: CycleTrack } = {}
local baseC0: { [Motor6D]: CFrame } = {}
local basePivot: { [Instance]: CFrame } = {}
local emitters: { [Instance]: ParticleEmitter } = {}
local lastEmit: { [Instance]: number } = {}
local chunks: { Chunk } = {}
local fxFolder: Folder

----------------------------------------------------------------------
-- Hilfen
----------------------------------------------------------------------
local function attrNumber(inst: Instance, name: string): number
	local v = inst:GetAttribute(name)
	return if type(v) == "number" then v else 0
end

local function progress(station: Instance, now: number): (boolean, number)
	local running = station:GetAttribute("Running") == true
	local s = attrNumber(station, "CycleStart")
	local e = attrNumber(station, "CycleEnd")
	if not running or e <= s then
		return false, 0
	end
	return true, math.clamp((now - s) / (e - s), 0, 1)
end

local function smooth(t: number): number
	return t * t * (3 - 2 * t)
end

--- Erkennt abgeschlossene Zyklen (auch wenn ein Manager sofort neu startet)
local function cycleCompleted(station: Instance): boolean
	local id = attrNumber(station, "CycleId")
	local running = station:GetAttribute("Running") == true
	local track = tracks[station]
	if not track then
		tracks[station] = { LastId = id, LastRunning = running }
		return false
	end
	local completed = (track.LastRunning and not running) or (track.LastRunning and id ~= track.LastId)
	track.LastId = id
	track.LastRunning = running
	return completed
end

local function spawnChunk(from: Vector3, to: Vector3, color: Color3, delay: number)
	if #chunks >= MAX_CHUNKS then
		return
	end
	local part = Instance.new("Part")
	part.Name = "OreChunk"
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Size = Vector3.new(0.7, 0.6, 0.7) * (0.8 + math.random() * 0.5)
	part.Color = color
	part.Material = Enum.Material.Glass
	part.CFrame = CFrame.new(from) * CFrame.Angles(math.random() * 6, math.random() * 6, 0)
	part.Transparency = 1
	part.Parent = fxFolder
	local mid = (from + to) / 2 + Vector3.new(0, 4 + math.random() * 3, 0)
	table.insert(chunks, {
		Part = part,
		P0 = from,
		P1 = mid,
		P2 = to,
		Start = os.clock() + delay,
		Duration = 0.55 + math.random() * 0.3,
	})
end

local function oreColor(station: Instance): Color3
	local veins = station:FindFirstChild("Veins")
	local ore = veins and veins:FindFirstChildWhichIsA("BasePart")
	return if ore then ore.Color else Color3.fromRGB(120, 110, 100)
end

local function partPosition(container: Instance?, name: string): Vector3?
	if not container then
		return nil
	end
	local inst = container:FindFirstChild(name, true)
	if inst and inst:IsA("BasePart") then
		return inst.Position
	elseif inst and inst:IsA("Model") then
		return inst:GetPivot().Position
	end
	return nil
end

----------------------------------------------------------------------
-- Schacht
----------------------------------------------------------------------
local function rockEmitter(station: Model, origin: CFrame, levelIndex: number): ParticleEmitter
	local existing = emitters[station]
	if existing and existing.Parent then
		return existing
	end
	local part = Instance.new("Part")
	part.Name = "RockFX"
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.Transparency = 1
	part.Size = Vector3.new(24, 4, 1)
	part.CFrame = origin * CFrame.new(20, -LH * levelIndex + 3.5, -38.6)
	part.Parent = fxFolder
	local e = Instance.new("ParticleEmitter")
	e.Rate = 0
	e.Color = ColorSequence.new(oreColor(station), Color3.fromRGB(110, 100, 92))
	e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 0.05) })
	e.Lifetime = NumberRange.new(0.4, 0.8)
	e.Speed = NumberRange.new(6, 12)
	e.SpreadAngle = Vector2.new(50, 50)
	e.Acceleration = Vector3.new(0, -40, 0)
	e.EmissionDirection = Enum.NormalId.Back
	e.LightEmission = 0.2
	e.Parent = part
	emitters[station] = e
	station.Destroying:Once(function()
		part:Destroy()
		emitters[station] = nil
	end)
	return e
end

local function swingAvatar(figure: Model, angle: number)
	local arm = figure:FindFirstChild("RightUpperArm")
	local motor = arm and arm:FindFirstChild("RightShoulder")
	if not motor or not motor:IsA("Motor6D") then
		return
	end
	local base = baseC0[motor]
	if not base then
		base = motor.C0
		baseC0[motor] = base
		motor.Destroying:Once(function()
			baseC0[motor] = nil
		end)
	end
	motor.C0 = base * CFrame.Angles(angle, 0, 0)
end

local function swingPlaceholder(figure: Model, angle: number)
	local pick = figure:FindFirstChild("Pickaxe")
	if not pick or not pick:IsA("Model") then
		return
	end
	local shoulder = pick:GetAttribute("Shoulder")
	if typeof(shoulder) ~= "CFrame" then
		return
	end
	local base = basePivot[pick]
	if not base then
		base = pick:GetPivot()
		basePivot[pick] = base
		pick.Destroying:Once(function()
			basePivot[pick] = nil
		end)
	end
	pick:PivotTo(shoulder * CFrame.Angles(angle, 0, 0) * shoulder:Inverse() * base)
end

local function animateShaft(station: Model, origin: CFrame, now: number, t: number)
	local index = attrNumber(station, "Index")
	local running = progress(station, now)
	local miners = station:FindFirstChild("Miners")
	if miners then
		for n, figure in miners:GetChildren() do
			if figure:IsA("Model") then
				local angle = 0
				if running then
					local phase = t * 9 + n * 1.3
					angle = (0.5 + 0.5 * math.sin(phase)) * 1.6
				end
				if figure:GetAttribute("IsAvatar") then
					swingAvatar(figure, angle)
				else
					swingPlaceholder(figure, -angle * 0.8)
				end
			end
		end
	end
	if running then
		local last = lastEmit[station] or 0
		if os.clock() - last > 0.22 then
			lastEmit[station] = os.clock()
			rockEmitter(station, origin, index):Emit(3)
		end
	end
	if cycleCompleted(station) then
		local crate = partPosition(station, "Crate")
		if crate and miners then
			local color = oreColor(station)
			for n, figure in miners:GetChildren() do
				if figure:IsA("Model") then
					local from = figure:GetPivot().Position + Vector3.new(0, 1, -1.5)
					spawnChunk(from, crate + Vector3.new(0, 2, 0), color, n * 0.05)
				end
			end
		end
	end
end

----------------------------------------------------------------------
-- Aufzug
----------------------------------------------------------------------
local function animateElevator(station: Model, plot: Model, now: number, dt: number)
	local cabin = station:FindFirstChild("Cabin")
	if not cabin or not cabin:IsA("Model") then
		return
	end
	local base = basePivot[cabin]
	if not base then
		base = cabin:GetPivot()
		basePivot[cabin] = base
		cabin.Destroying:Once(function()
			basePivot[cabin] = nil
		end)
	end
	local levels = attrNumber(plot, "LevelCount")
	local depth = LH * math.max(levels, 1)
	local running, p = progress(station, now)
	local offset = 0
	if running then
		if p < 0.5 then
			offset = -depth * smooth(p * 2)
		else
			offset = -depth * (1 - smooth((p - 0.5) * 2))
		end
	end
	cabin:PivotTo(base * CFrame.new(0, offset, 0))
	local load = cabin:FindFirstChild("Load")
	if load and load:IsA("BasePart") then
		load.Transparency = if running and p >= 0.5 then 0 else 1
	end
	-- Seil zwischen Kopf und Kabinendach
	local head = station:FindFirstChild("Head")
	local cable = station:FindFirstChild("Cable")
	if head and head:IsA("BasePart") and cable and cable:IsA("BasePart") then
		local top = head.Position.Y
		local cabinTop = base.Position.Y + offset + 6
		local len = math.max(0.1, top - cabinTop)
		cable.Size = Vector3.new(cable.Size.X, len, cable.Size.Z)
		cable.CFrame = CFrame.new(head.Position.X, cabinTop + len / 2, head.Position.Z)
	end
	-- Rad drehen
	local wheel = station:FindFirstChild("Wheel")
	if wheel and wheel:IsA("BasePart") and running then
		wheel.CFrame = wheel.CFrame * CFrame.Angles(dt * 6, 0, 0)
	end
	if cycleCompleted(station) then
		local depot = partPosition(station, "Depot")
		if depot then
			local from = base.Position + Vector3.new(0, 2, 0)
			for n = 1, 5 do
				spawnChunk(from, depot + Vector3.new(0, 3, 0), Color3.fromRGB(255, 196, 64), n * 0.06)
			end
		end
	end
end

----------------------------------------------------------------------
-- Händler
----------------------------------------------------------------------
local function animateWarehouse(station: Model, origin: CFrame, now: number)
	local cart = station:FindFirstChild("Cart")
	if not cart or not cart:IsA("Model") then
		return
	end
	local fromLocal = station:GetAttribute("CartFrom")
	local toLocal = station:GetAttribute("CartTo")
	if typeof(fromLocal) ~= "Vector3" or typeof(toLocal) ~= "Vector3" then
		return
	end
	local base = basePivot[cart]
	if not base then
		base = cart:GetPivot()
		basePivot[cart] = base
		cart.Destroying:Once(function()
			basePivot[cart] = nil
		end)
	end
	local fromWorld = origin * fromLocal
	local toWorld = origin * toLocal
	local running, p = progress(station, now)
	local pos = fromWorld
	if running then
		if p < 0.5 then
			pos = fromWorld:Lerp(toWorld, smooth(p * 2))
		else
			pos = toWorld:Lerp(fromWorld, smooth((p - 0.5) * 2))
		end
	end
	cart:PivotTo(base + (pos - fromWorld))
	local load = cart:FindFirstChild("Load")
	if load and load:IsA("BasePart") then
		load.Transparency = if running and p < 0.5 then 0 else 1
	end
	if cycleCompleted(station) then
		Effects.burst(toWorld + Vector3.new(0, 3, 0), Color3.fromRGB(255, 210, 60), 18)
	end
end

----------------------------------------------------------------------
-- Haupt-Loop
----------------------------------------------------------------------
local function updateChunks()
	local clock = os.clock()
	for i = #chunks, 1, -1 do
		local c = chunks[i]
		local t = (clock - c.Start) / c.Duration
		if t >= 1 then
			c.Part:Destroy()
			table.remove(chunks, i)
		elseif t >= 0 then
			c.Part.Transparency = 0
			local a = c.P0:Lerp(c.P1, t)
			local b = c.P1:Lerp(c.P2, t)
			c.Part.CFrame = CFrame.new(a:Lerp(b, t)) * CFrame.Angles(clock * 5, clock * 3, 0)
		end
	end
end

function MineVisuals.start()
	fxFolder = Instance.new("Folder")
	fxFolder.Name = "ClientFX"
	fxFolder.Parent = workspace

	RunService.RenderStepped:Connect(function(dt)
		local now = Clock.now()
		local t = os.clock()
		for _, plot in PlotLocator.plots() do
			local mine = plot:FindFirstChild("Mine")
			if mine then
				local origin = PlotLocator.origin(plot)
				for _, station in mine:GetChildren() do
					if station:IsA("Model") then
						local name = station.Name
						if string.sub(name, 1, 6) == "Shaft_" then
							animateShaft(station, origin, now, t)
						elseif name == "Elevator" then
							animateElevator(station, plot, now, dt)
						elseif name == "Warehouse" then
							animateWarehouse(station, origin, now)
						end
					end
				end
			end
		end
		updateChunks()
	end)

	-- Verwaiste Einträge aufräumen (Stationen wurden zerstört)
	task.spawn(function()
		while true do
			task.wait(5)
			for station in tracks do
				if not station.Parent then
					tracks[station] = nil
					lastEmit[station] = nil
				end
			end
		end
	end)
end

return MineVisuals

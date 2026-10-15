--!strict
--[[
	CameraController
	================
	"Minenansicht": seitlicher Querschnitt durch die eigene Mine (wie in
	klassischen Idle-Miner-Spielen). Die Vorderwand der Grube wird lokal
	ausgeblendet. Scrollen per Mausrad, Wischen oder ▲/▼-Buttons.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage:WaitForChild("Shared").Config)

local PlotLocator = require(script.Parent.Parent.PlotLocator)
local Components = require(script.Parent.Parent.UI.Components)
local Root = require(script.Parent.Parent.UI.Root)
local Theme = require(script.Parent.Parent.UI.Theme)
local Util = require(script.Parent.Parent.UI.Util)

local CameraController = {}

local active = false
local targetY = -8
local currentY = -8
local controls: Frame? = nil
local hiddenParts: { BasePart } = {}
local renderName = "IdleMinerMineView"

local LH = Config.World.LevelHeight
local VIEW_X = 14 -- Mitte der Grube (lokal)
local VIEW_Z = 6 -- Kamera-Abstand vor der Grube (lokal)

local function levelCount(plot: Model): number
	local n = plot:GetAttribute("LevelCount")
	return if type(n) == "number" then n else 1
end

local function clampY(plot: Model, y: number): number
	local minY = -LH * (levelCount(plot) + 1) + 8
	return math.clamp(y, minY, 6)
end

local function setFrontHidden(plot: Model, hidden: boolean)
	for _, p in hiddenParts do
		p.LocalTransparencyModifier = 0
	end
	table.clear(hiddenParts)
	if hidden then
		for _, d in plot:GetDescendants() do
			if d:IsA("BasePart") and d:GetAttribute("HideInMineView") then
				d.LocalTransparencyModifier = 1
				table.insert(hiddenParts, d)
			end
		end
	end
end

local function buildControls()
	local frame: Frame = Util.new("Frame", {
		Name = "MineViewControls",
		Size = UDim2.fromOffset(90, 260),
		Position = UDim2.new(1, -220, 0.5, 0),
		AnchorPoint = Vector2.new(1, 0.5),
		BackgroundTransparency = 1,
		Visible = false,
		Parent = Root.layer("Hud"),
	}, { Util.list(Enum.FillDirection.Vertical, 10) })
	Components.button({
		Text = "▲",
		Color = Theme.Colors.Blue,
		Size = UDim2.fromOffset(80, 70),
		TextSize = 32,
		LayoutOrder = 1,
		Parent = frame,
		OnClick = function()
			targetY += LH
		end,
	})
	Components.button({
		Text = "▼",
		Color = Theme.Colors.Blue,
		Size = UDim2.fromOffset(80, 70),
		TextSize = 32,
		LayoutOrder = 2,
		Parent = frame,
		OnClick = function()
			targetY -= LH
		end,
	})
	Components.button({
		Text = "✕",
		Color = Theme.Colors.Red,
		Size = UDim2.fromOffset(80, 70),
		TextSize = 30,
		LayoutOrder = 3,
		Parent = frame,
		OnClick = function()
			CameraController.setActive(false)
		end,
	})
	controls = frame
end

function CameraController.setActive(value: boolean)
	local plot = PlotLocator.ownPlot()
	local camera = workspace.CurrentCamera
	if value and (not plot or not camera) then
		return
	end
	active = value
	if controls then
		controls.Visible = value
	end
	if value and plot and camera then
		setFrontHidden(plot, true)
		camera.CameraType = Enum.CameraType.Scriptable
		targetY = -LH * 0.5
		currentY = 10
		RunService:BindToRenderStep(renderName, Enum.RenderPriority.Camera.Value + 1, function(dt)
			local p = PlotLocator.ownPlot()
			local cam = workspace.CurrentCamera
			if not p or not cam then
				CameraController.setActive(false)
				return
			end
			targetY = clampY(p, targetY)
			currentY += (targetY - currentY) * (1 - math.exp(-dt * 8))
			local origin = PlotLocator.origin(p)
			local pos = origin * Vector3.new(VIEW_X, currentY, VIEW_Z)
			local look = origin * Vector3.new(VIEW_X, currentY - 4, -40)
			cam.CFrame = CFrame.lookAt(pos, look)
			cam.FieldOfView = 70
		end)
	else
		pcall(function()
			RunService:UnbindFromRenderStep(renderName)
		end)
		if plot then
			setFrontHidden(plot, false)
		end
		if camera then
			camera.CameraType = Enum.CameraType.Custom
			camera.FieldOfView = 70
		end
	end
end

function CameraController.toggle()
	CameraController.setActive(not active)
end

function CameraController.isActive(): boolean
	return active
end

function CameraController.start()
	buildControls()
	UserInputService.InputChanged:Connect(function(input: InputObject, processed: boolean)
		if not active or processed then
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseWheel then
			targetY += input.Position.Z * 6
		end
	end)
	-- Wischen auf dem Handy
	UserInputService.TouchPan:Connect(
		function(_, _totalTranslation: Vector2, velocity: Vector2, state: Enum.UserInputState, processed: boolean)
			if not active or processed then
				return
			end
			if state == Enum.UserInputState.Change then
				targetY += velocity.Y * 0.004
			end
		end
	)
end

return CameraController

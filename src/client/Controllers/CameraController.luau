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

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Formulas = require(Shared.Formulas)

local ClientState = require(script.Parent.Parent.ClientState)
local PlotLocator = require(script.Parent.Parent.PlotLocator)
local Remote = require(script.Parent.Parent.Remote)
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

local sectionLabel: TextLabel? = nil

local function currentSection(): (number, number)
	local snap = ClientState.Snapshot
	if not snap then
		return 1, 1
	end
	local maxSection = Formulas.sectionOf(math.max(#snap.Data.Shafts, 1))
	return snap.Section or maxSection, maxSection
end

local function updateSectionLabel()
	local label = sectionLabel
	if not label then
		return
	end
	local section, maxSection = currentSection()
	local size = Config.ShaftGen.SectionSize
	label.Text = string.format(
		'Abschnitt %d/%d\n<font size="15">Ebenen %d–%d</font>',
		section,
		maxSection,
		(section - 1) * size + 1,
		section * size
	)
end

local function changeSection(delta: number)
	local section, maxSection = currentSection()
	local target = math.clamp(section + delta, 1, maxSection)
	if target ~= section then
		Remote.send("SetSection", { Section = if target == maxSection then 0 else target })
	end
end

local function buildControls()
	local frame: Frame = Util.new("Frame", {
		Name = "MineViewControls",
		Size = UDim2.fromOffset(190, 400),
		Position = UDim2.new(1, -214, 0.5, 0),
		AnchorPoint = Vector2.new(1, 0.5),
		BackgroundTransparency = 1,
		Visible = false,
		Parent = Root.layer("Hud"),
	}, { Util.list(Enum.FillDirection.Vertical, 10) })

	-- Abschnitt wechseln (500 Ebenen = 50 Abschnitte à 10 Ebenen)
	local sectionCard = Components.pill({
		Size = UDim2.fromOffset(186, 62),
		LayoutOrder = 1,
		Parent = frame,
	}, Theme.Colors.Gold)
	sectionLabel = Util.label({
		Size = UDim2.fromScale(1, 1),
		Text = "",
		Font = Theme.Fonts.Title,
		TextSize = 19,
		Parent = sectionCard,
	})
	Util.textStroke(1.5).Parent = sectionLabel
	local row: Frame = Util.new("Frame", {
		Size = UDim2.fromOffset(186, 66),
		LayoutOrder = 2,
		BackgroundTransparency = 1,
		Parent = frame,
	}, { Util.list(Enum.FillDirection.Horizontal, 10) })
	Components.button({
		Text = "◀",
		Color = Theme.Colors.Gold,
		Size = UDim2.fromOffset(88, 64),
		TextSize = 30,
		LayoutOrder = 1,
		Parent = row,
		OnClick = function()
			changeSection(-1)
		end,
	})
	Components.button({
		Text = "▶",
		Color = Theme.Colors.Gold,
		Size = UDim2.fromOffset(88, 64),
		TextSize = 30,
		LayoutOrder = 2,
		Parent = row,
		OnClick = function()
			changeSection(1)
		end,
	})
	local scroll: Frame = Util.new("Frame", {
		Size = UDim2.fromOffset(186, 66),
		LayoutOrder = 3,
		BackgroundTransparency = 1,
		Parent = frame,
	}, { Util.list(Enum.FillDirection.Horizontal, 10) })
	Components.button({
		Text = "▲",
		Color = Theme.Colors.Cyan,
		Size = UDim2.fromOffset(88, 64),
		TextSize = 30,
		LayoutOrder = 1,
		Parent = scroll,
		OnClick = function()
			targetY += LH
		end,
	})
	Components.button({
		Text = "▼",
		Color = Theme.Colors.Cyan,
		Size = UDim2.fromOffset(88, 64),
		TextSize = 30,
		LayoutOrder = 2,
		Parent = scroll,
		OnClick = function()
			targetY -= LH
		end,
	})
	Components.button({
		Text = "❌ Schließen",
		Color = Theme.Colors.Red,
		Size = UDim2.fromOffset(186, 60),
		TextSize = 22,
		LayoutOrder = 4,
		Parent = frame,
		OnClick = function()
			CameraController.setActive(false)
		end,
	})
	controls = frame
	ClientState.Changed:Connect(updateSectionLabel)
	updateSectionLabel()
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

function CameraController.toggle(): boolean
	CameraController.setActive(not active)
	return active
end

--- Öffnet die 2D-Ansicht genau bei einer bestimmten Ebene (wechselt den Abschnitt)
function CameraController.focusLevel(index: number)
	local section, maxSection = currentSection()
	local wanted = Formulas.sectionOf(index)
	if wanted ~= section then
		Remote.send("SetSection", { Section = if wanted == maxSection then 0 else wanted })
	end
	local slot = (index - 1) % Config.ShaftGen.SectionSize + 1
	if not active then
		CameraController.setActive(true)
	end
	targetY = -LH * slot + LH * 0.6
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

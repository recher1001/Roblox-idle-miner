--!strict
--[[
	SprintController
	================
	Sprinten: Shift oder Strg gedrückt halten (Tastatur), auf Touch-Geräten
	gibt es einen "🏃 Sprint"-Button zum Umschalten.

	Die normale Geschwindigkeit setzt der Server (z. B. Speed-Spule). Der
	Client merkt sich diesen Wert und multipliziert ihn nur beim Sprinten.
	Shift-Lock ist im Projekt deaktiviert, damit Shift frei zum Sprinten ist.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage:WaitForChild("Shared").Config)

local Components = require(script.Parent.Parent.UI.Components)
local Root = require(script.Parent.Parent.UI.Root)
local Theme = require(script.Parent.Parent.UI.Theme)
local Util = require(script.Parent.Parent.UI.Util)

local SprintController = {}

local player = Players.LocalPlayer
local SPRINT_KEYS: { [Enum.KeyCode]: boolean } = {
	[Enum.KeyCode.LeftShift] = true,
	[Enum.KeyCode.RightShift] = true,
	[Enum.KeyCode.LeftControl] = true,
	[Enum.KeyCode.RightControl] = true,
}

local keysHeld = 0
local touchSprint = false
local sprinting = false
local baseSpeed = 16
local applying = false
local humanoid: Humanoid? = nil
local touchButton: Components.Button? = nil

local function apply()
	local h = humanoid
	if not h then
		return
	end
	-- beim Fliegen (Teppich) nicht eingreifen
	local character = player.Character
	local flying = character ~= nil and character:GetAttribute("CarpetActive") == true
	local active = sprinting and not flying
	applying = true
	h.WalkSpeed = if active then baseSpeed * Config.Sprint.Multiplier else baseSpeed
	applying = false
	local camera = workspace.CurrentCamera
	if camera and camera.CameraType ~= Enum.CameraType.Scriptable then
		Util.tween(camera, 0.25, { FieldOfView = 70 + (if active then Config.Sprint.FovBoost else 0) })
	end
end

local function setSprinting(value: boolean)
	if sprinting == value then
		return
	end
	sprinting = value
	apply()
	local b = touchButton
	if b then
		b.SetColor(if value then Theme.Colors.Lime else Theme.Colors.Orange)
		b.SetText(if value then "SPRINT AN" else "Sprint")
	end
end

local function refresh()
	setSprinting(keysHeld > 0 or touchSprint)
end

local function bindCharacter(character: Model)
	local h = character:WaitForChild("Humanoid", 10)
	if not h or not h:IsA("Humanoid") then
		return
	end
	humanoid = h
	baseSpeed = h.WalkSpeed
	-- Änderungen vom Server (Speed-Spule an/aus) als neue Basis übernehmen
	h:GetPropertyChangedSignal("WalkSpeed"):Connect(function()
		if applying then
			return
		end
		baseSpeed = h.WalkSpeed
		if sprinting then
			apply()
		end
	end)
	apply()
end

function SprintController.start()
	UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
		if processed or not SPRINT_KEYS[input.KeyCode] then
			return
		end
		keysHeld += 1
		refresh()
	end)
	UserInputService.InputEnded:Connect(function(input: InputObject)
		if not SPRINT_KEYS[input.KeyCode] then
			return
		end
		keysHeld = math.max(0, keysHeld - 1)
		refresh()
	end)
	-- Fenster verliert den Fokus -> Tasten gelten als losgelassen
	UserInputService.WindowFocusReleased:Connect(function()
		keysHeld = 0
		refresh()
	end)

	if UserInputService.TouchEnabled then
		touchButton = Components.button({
			Text = "Sprint",
			Color = Theme.Colors.Orange,
			Size = UDim2.fromOffset(150, 66),
			Position = UDim2.new(1, -14, 1, -250),
			AnchorPoint = Vector2.new(1, 1),
			TextSize = 21,
			Parent = Root.layer("Hud"),
			Shine = true,
			OnClick = function()
				touchSprint = not touchSprint
				refresh()
			end,
		})
		Components.addFace(touchButton :: Components.Button, "Laughing", 46)
	end

	player.CharacterAdded:Connect(bindCharacter)
	if player.Character then
		task.spawn(bindCharacter, player.Character)
	end
end

return SprintController

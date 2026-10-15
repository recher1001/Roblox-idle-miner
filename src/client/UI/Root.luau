--!strict
--[[
	Root
	====
	Haupt-ScreenGui. Alles wird in Referenz-Pixeln (1280x720) gebaut und über
	einen UIScale an die echte Bildschirmgröße angepasst. Auf Touch-Geräten
	wird etwas größer skaliert, damit Buttons gut tippbar sind.

	Ebenen (ZIndex aufsteigend):
	  Hud      - Geldanzeige, Seitenleiste, Buttons
	  Effects  - Floating-Text, Partikel
	  Modal    - Abdunklung + Fenster
	  Popup    - Reveal, Offline-Popup, Bestätigungen
	  Toast    - Benachrichtigungen
]]

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

local Theme = require(script.Parent.Theme)
local Util = require(script.Parent.Util)

local Root = {}

Root.Gui = nil :: ScreenGui?
Root.Scale = 1

local layers: { [string]: Frame } = {}

function Root.layer(name: string): Frame
	local l = layers[name]
	assert(l, "Unbekannte UI-Ebene: " .. name)
	return l
end

function Root.start()
	local player = Players.LocalPlayer
	local playerGui = player:WaitForChild("PlayerGui")

	local gui: ScreenGui = Util.new("ScreenGui", {
		Name = "IdleMinerUI",
		ResetOnSpawn = false,
		IgnoreGuiInset = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		DisplayOrder = 5,
		Parent = playerGui,
	})
	Root.Gui = gui

	local uiScale: UIScale = Util.new("UIScale")
	local scaled: Frame = Util.new("Frame", {
		Name = "Scaled",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Parent = gui,
	}, { uiScale })

	for i, name in { "Hud", "Effects", "Modal", "Popup", "Toast" } do
		layers[name] = Util.new("Frame", {
			Name = name,
			BackgroundTransparency = 1,
			Size = UDim2.fromScale(1, 1),
			ZIndex = i * 10,
			Parent = scaled,
		})
	end

	local function updateScale()
		local camera = workspace.CurrentCamera
		if not camera then
			return
		end
		local vp = camera.ViewportSize
		if vp.X <= 1 or vp.Y <= 1 then
			return
		end
		local s = math.min(vp.X / Theme.ReferenceSize.X, vp.Y / Theme.ReferenceSize.Y)
		if UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled then
			s *= 1.25 -- größere Touch-Ziele auf Handys
		end
		s = math.clamp(s, 0.45, 1.6)
		Root.Scale = s
		uiScale.Scale = s
		-- Rahmen so groß, dass er nach dem Skalieren genau den Bildschirm füllt
		scaled.Size = UDim2.fromScale(1 / s, 1 / s)
	end

	local function bindCamera()
		local camera = workspace.CurrentCamera
		if camera then
			camera:GetPropertyChangedSignal("ViewportSize"):Connect(updateScale)
		end
		updateScale()
	end
	workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(bindCamera)
	bindCamera()
end

return Root

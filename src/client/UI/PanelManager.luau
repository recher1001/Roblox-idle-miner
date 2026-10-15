--!strict
--[[
	PanelManager
	============
	Öffnet/schließt Fenster mit sanfter Animation (Fade + Scale).
	Es ist immer höchstens ein Fenster offen. Klick auf die Abdunklung schließt.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Signal = require(ReplicatedStorage:WaitForChild("Shared").Signal)

local Components = require(script.Parent.Components)
local Root = require(script.Parent.Root)
local Theme = require(script.Parent.Theme)
local Util = require(script.Parent.Util)

type Window = Components.Window

type Entry = {
	Window: Window,
	OnOpen: ((arg: any) -> ())?,
	OnClose: (() -> ())?,
}

local PanelManager = {}

PanelManager.Opened = Signal.new() :: Signal.Signal<string?>

local panels: { [string]: Entry } = {}
local current: string? = nil
local overlay: TextButton? = nil

local function getOverlay(): TextButton
	if overlay then
		return overlay
	end
	local o: TextButton = Util.new("TextButton", {
		Name = "Dim",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Theme.Colors.Overlay,
		BackgroundTransparency = 1,
		AutoButtonColor = false,
		Text = "",
		Visible = false,
		Parent = Root.layer("Modal"),
	})
	o.Activated:Connect(function()
		PanelManager.close()
	end)
	overlay = o
	return o
end

function PanelManager.register(name: string, window: Window, onOpen: ((arg: any) -> ())?, onClose: (() -> ())?)
	window.Root.Parent = Root.layer("Modal")
	window.Root.ZIndex = 5
	panels[name] = { Window = window, OnOpen = onOpen, OnClose = onClose }
end

local function hide(name: string)
	local entry = panels[name]
	if not entry then
		return
	end
	local root = entry.Window.Root
	if entry.OnClose then
		entry.OnClose()
	end
	Util.tween(root, 0.18, { GroupTransparency = 1 })
	local t = Util.tween(entry.Window.Scale, 0.18, { Scale = 0.88 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	t.Completed:Once(function()
		if current ~= name then
			root.Visible = false
		end
	end)
end

function PanelManager.open(name: string, arg: any?)
	local entry = panels[name]
	if not entry then
		return
	end
	if current and current ~= name then
		hide(current)
	end
	current = name
	local o = getOverlay()
	o.Visible = true
	Util.tween(o, 0.2, { BackgroundTransparency = 0.7 })

	local root = entry.Window.Root
	root.Visible = true
	root.GroupTransparency = 1
	entry.Window.Scale.Scale = 0.85
	Util.tween(root, 0.22, { GroupTransparency = 0 })
	Util.tween(entry.Window.Scale, 0.35, { Scale = 1 }, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	if entry.OnOpen then
		entry.OnOpen(arg)
	end
	PanelManager.Opened:Fire(name)
end

function PanelManager.close()
	if not current then
		return
	end
	local name = current
	current = nil
	hide(name)
	local o = getOverlay()
	Util.tween(o, 0.2, { BackgroundTransparency = 1 }).Completed:Once(function()
		if not current then
			o.Visible = false
		end
	end)
	PanelManager.Opened:Fire(nil)
end

function PanelManager.toggle(name: string, arg: any?)
	if current == name then
		PanelManager.close()
	else
		PanelManager.open(name, arg)
	end
end

function PanelManager.isOpen(name: string): boolean
	return current == name
end

function PanelManager.current(): string?
	return current
end

return PanelManager

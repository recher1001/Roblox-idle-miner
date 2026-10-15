--!strict
--[[
	Client-Einstiegspunkt: baut die komplette UI per Code und startet die
	Controller. Der Client sendet nur Anfragen - alle Werte kommen vom Server.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

ReplicatedStorage:WaitForChild("Shared")
ReplicatedStorage:WaitForChild("Remotes")

local Client = script.Parent
local ClientState = require(Client.ClientState)
local Remote = require(Client.Remote)

local UI = Client.UI
local Root = require(UI.Root)
local HUD = require(UI.HUD)
local Panels = UI.Panels
local UpgradesPanel = require(Panels.UpgradesPanel)
local ManagersPanel = require(Panels.ManagersPanel)
local RebirthPanel = require(Panels.RebirthPanel)
local ShopPanel = require(Panels.ShopPanel)
local DailyPanel = require(Panels.DailyPanel)
local AdminPanel = require(Panels.AdminPanel)

local Controllers = Client.Controllers
local CameraController = require(Controllers.CameraController)
local CarpetController = require(Controllers.CarpetController)
local Effects = require(Controllers.Effects)
local MineVisuals = require(Controllers.MineVisuals)
local StationBadges = require(Controllers.StationBadges)

ClientState.start()
Root.start()

HUD.start(CameraController.toggle, CameraController.isActive)
UpgradesPanel.start()
ManagersPanel.start()
RebirthPanel.start()
ShopPanel.start()
DailyPanel.start()
AdminPanel.start() -- nur für Owner/Admins sichtbar

Effects.start()
StationBadges.start()
CameraController.start()
CarpetController.start()
MineVisuals.start()

-- Falls der erste Sync vor dem Verbinden kam: Zustand neu anfordern
task.spawn(function()
	task.wait(1)
	if not ClientState.Snapshot then
		Remote.request("RequestSync")
	end
end)

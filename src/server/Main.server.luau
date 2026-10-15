--!strict
--[[
	Server-Einstiegspunkt. Startet alle Services in der richtigen Reihenfolge.
	Jeder Service registriert seine eigenen Hooks und Remote-Aktionen.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage:WaitForChild("Shared").Net)

local Services = script.Parent.Services
local World = script.Parent.World

local WorldSetup = require(World.WorldSetup)
local DataService = require(Services.DataService)
local SessionService = require(Services.SessionService)
local NetService = require(Services.NetService)
local PlotService = require(Services.PlotService)
local MineService = require(Services.MineService)
local UpgradeService = require(Services.UpgradeService)
local ManagerService = require(Services.ManagerService)

Net.setupServer()
WorldSetup.applyLighting()

DataService.start()
PlotService.start()
MineService.start()
UpgradeService.start()
ManagerService.start()
NetService.start()

-- SessionService zuletzt: erst dann kommen Spieler-Sessions herein
SessionService.start()

print("[IdleMiner] Server gestartet")

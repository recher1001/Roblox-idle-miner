--!strict
--[[
	Server-Einstiegspunkt. Startet alle Services in der richtigen Reihenfolge.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage:WaitForChild("Shared").Net)

local Services = script.Parent.Services
local DataService = require(Services.DataService)
local SessionService = require(Services.SessionService)

Net.setupServer()
DataService.start()
SessionService.start()

print("[IdleMiner] Server gestartet")

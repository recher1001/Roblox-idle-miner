--!strict
--[[
	PlotLocator
	===========
	Findet Plots und Stationen in workspace.Plots (eigene und fremde).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Formulas = require(ReplicatedStorage:WaitForChild("Shared").Formulas)

local PlotLocator = {}

function PlotLocator.plots(): { Model }
	local folder = workspace:FindFirstChild("Plots")
	local list = {}
	if folder then
		for _, p in folder:GetChildren() do
			if p:IsA("Model") then
				table.insert(list, p)
			end
		end
	end
	return list
end

function PlotLocator.ownPlot(): Model?
	local userId = Players.LocalPlayer.UserId
	for _, p in PlotLocator.plots() do
		if p:GetAttribute("OwnerUserId") == userId then
			return p
		end
	end
	return nil
end

function PlotLocator.origin(plot: Model): CFrame
	local o = plot:GetAttribute("Origin")
	return if typeof(o) == "CFrame" then o else CFrame.new()
end

function PlotLocator.station(plot: Model?, key: string): Model?
	if not plot then
		return nil
	end
	local mine = plot:FindFirstChild("Mine")
	if not mine then
		return nil
	end
	local area, index = Formulas.parseKey(key)
	local name = if area == "Shaft" then "Shaft_" .. tostring(index) else area
	if not name then
		return nil
	end
	local m = mine:FindFirstChild(name)
	return if m and m:IsA("Model") then m else nil
end

--- Weltposition über einer Station (für Floating-Text)
function PlotLocator.stationPosition(plot: Model?, key: string): Vector3?
	local station = PlotLocator.station(plot, key)
	if not station then
		return nil
	end
	local anchor = station:FindFirstChild("InfoAnchor")
	if anchor and anchor:IsA("BasePart") then
		return anchor.Position
	end
	return station:GetPivot().Position
end

return PlotLocator

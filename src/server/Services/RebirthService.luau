--!strict
--[[
	RebirthService
	==============
	Prestige: setzt Geld, Ebenen, Upgrades und Lager zurück und gibt dafür
	Prestige-Punkte (dauerhafter Einkommens-Multiplikator) und Gems.
	Manager bleiben erhalten (Schacht-Manager tieferer Ebenen gehen in die Reserve).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local BigNum = require(Shared.BigNum)
local Config = require(Shared.Config)
local Formulas = require(Shared.Formulas)

local DataTemplate = require(script.Parent.Parent.Modules.DataTemplate)
local MineService = require(script.Parent.MineService)
local NetService = require(script.Parent.NetService)
local PlotService = require(script.Parent.PlotService)
local SessionService = require(script.Parent.SessionService)

type Session = SessionService.Session

local RebirthService = {}

function RebirthService.rebirth(session: Session): (boolean, string?)
	local data = session.Data
	local points = Formulas.rebirthPointsFor(data.RunCash)
	if points <= 0 then
		return false,
			"Du musst erst "
				.. BigNum.formatMoney(BigNum.new(Config.Rebirth.MinRunCash), Config.CurrencySymbol)
				.. " verdienen!"
	end
	local gems = Formulas.rebirthGems(points)

	data.RebirthPoints += points
	data.Rebirths += 1
	data.Cash = BigNum.new(Config.StartingCash)
	data.RunCash = BigNum.zero()
	data.Shafts = { DataTemplate.newStation("Shaft") }
	data.Elevator = DataTemplate.newStation("Elevator")
	data.Warehouse = DataTemplate.newStation("Warehouse")
	for _, m in data.Managers do
		if m.AssignedTo and not Formulas.getStation(data, m.AssignedTo) then
			m.AssignedTo = nil
		end
	end
	SessionService.addGems(session, gems)

	MineService.resetCycles(session)
	PlotService.refreshLevels(session)
	session.Dirty = true

	local mult = Formulas.rebirthMultiplier(data.RebirthPoints)
	SessionService.effect(session.Player, "Rebirth", { Multiplier = BigNum.format(BigNum.new(mult)) })
	SessionService.effect(session.Player, "Gems", { Amount = gems })
	return true, nil
end

function RebirthService.start()
	NetService.register("Rebirth", {}, function(session)
		return RebirthService.rebirth(session)
	end)
end

return RebirthService

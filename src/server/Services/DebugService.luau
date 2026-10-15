--!strict
--[[
	DebugService
	============
	Test-Werkzeuge - funktionieren NUR in Roblox Studio (im echten Spiel aus).

	1) Test-Menü: Button "🛠 Test" unten links (Client: UI/Panels/DebugPanel)
	2) Chat-Befehle (falls der Chat sie durchlässt):
	     /cash 1e9   /gems 100   /event   /offline 3600   /reset
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local BigNum = require(Shared.BigNum)
local Config = require(Shared.Config)
local Formulas = require(Shared.Formulas)

local DataTemplate = require(script.Parent.Parent.Modules.DataTemplate)
local EventService = require(script.Parent.EventService)
local ManagerService = require(script.Parent.ManagerService)
local MineService = require(script.Parent.MineService)
local NetService = require(script.Parent.NetService)
local OfflineService = require(script.Parent.OfflineService)
local PlotService = require(script.Parent.PlotService)
local SessionService = require(script.Parent.SessionService)

type Session = SessionService.Session

local DebugService = {}

--- Führt einen Testbefehl aus. Gibt (ok, Meldung) zurück.
function DebugService.run(session: Session, cmd: string, arg: string): (boolean, string?)
	local player = session.Player
	local n = tonumber(arg)
	if cmd == "cash" then
		SessionService.addCash(session, BigNum.new(n or 1e6))
	elseif cmd == "mult" then
		SessionService.addCash(session, BigNum.mulNum(session.Data.Cash, (n or 1000) - 1))
	elseif cmd == "gems" then
		SessionService.addGems(session, n or 100)
	elseif cmd == "event" then
		EventService.trigger(if arg ~= "" then arg else nil)
	elseif cmd == "offline" then
		OfflineService.simulate(session, n or 3600)
	elseif cmd == "unlockall" then
		local data = session.Data
		while #data.Shafts < #Config.Shafts do
			table.insert(data.Shafts, DataTemplate.newStation("Shaft"))
		end
		MineService.ensureCycles(session)
		PlotService.refreshLevels(session)
	elseif cmd == "managers" then
		-- jede Station ohne Manager bekommt einen (Kosten werden vorher geschenkt)
		local keys = Formulas.allStationKeys(session.Data)
		for _, key in keys do
			if not Formulas.managerFor(session.Data, key) then
				local area = Formulas.parseKey(key) or "Shaft"
				SessionService.addCash(session, Formulas.managerHireCost(session.Data, area))
				ManagerService.hire(session, area)
			end
		end
	elseif cmd == "cooldowns" then
		for _, m in session.Data.Managers do
			m.CooldownUntil = 0
			m.ActiveUntil = 0
		end
		session.Data.LockCooldownUntil = 0
		session.LockedUntil = 0
		session.LastStealAt = 0
		session.JoinTime = 0 -- Neulingsschutz aus (zum Stehlen-Testen)
	elseif cmd == "daily" then
		session.Data.LastDailyClaim = 0
	elseif cmd == "reset" then
		local fresh = DataTemplate.new()
		for k, v in fresh :: any do
			(session.Data :: any)[k] = v
		end
		MineService.resetCycles(session)
		PlotService.refreshLevels(session)
	else
		return false, "Unbekannter Testbefehl"
	end
	session.Dirty = true
	PlotService.updateVisuals(session)
	SessionService.notify(player, "🛠 Test: " .. cmd .. (if arg ~= "" then " " .. arg else ""), "info")
	return true, nil
end

function DebugService.start()
	if not RunService:IsStudio() then
		return
	end

	NetService.register("Debug", { Cmd = "string", Arg = "string?" }, function(session, payload)
		return DebugService.run(session, payload.Cmd, payload.Arg or "")
	end)

	local function hook(player: Player)
		player.Chatted:Connect(function(message)
			local session = SessionService.get(player)
			local cmd, arg = string.match(message, "^/(%a+)%s*(%S*)")
			if session and cmd then
				DebugService.run(session, cmd, arg or "")
			end
		end)
	end
	Players.PlayerAdded:Connect(hook)
	for _, p in Players:GetPlayers() do
		hook(p)
	end
	print("[DebugService] Studio-Testmodus aktiv: Button '🛠 Test' unten links")
end

return DebugService

--!strict
--[[
	DebugService
	============
	Test-Befehle im Chat - funktionieren NUR in Roblox Studio:
	  /cash 1e9        Geld hinzufügen
	  /gems 100        Gems hinzufügen
	  /event           Server-Event sofort starten
	  /offline 3600    Offline-Popup mit X Sekunden simulieren
	  /reset           Spielstand zurücksetzen (nur diese Session)
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local BigNum = require(Shared.BigNum)
local Net = require(Shared.Net)

local DataTemplate = require(script.Parent.Parent.Modules.DataTemplate)
local EventService = require(script.Parent.EventService)
local MineService = require(script.Parent.MineService)
local OfflineService = require(script.Parent.OfflineService)
local PlotService = require(script.Parent.PlotService)
local SessionService = require(script.Parent.SessionService)

local DebugService = {}

local function handle(player: Player, message: string)
	local session = SessionService.get(player)
	if not session then
		return
	end
	local cmd, arg = string.match(message, "^/(%a+)%s*(%S*)")
	if not cmd then
		return
	end
	local n = tonumber(arg)
	if cmd == "cash" then
		SessionService.addCash(session, BigNum.new(n or 1e6))
	elseif cmd == "gems" then
		SessionService.addGems(session, n or 100)
	elseif cmd == "event" then
		EventService.trigger(if arg ~= "" then arg else nil)
	elseif cmd == "offline" then
		local amount, seconds, capped = OfflineService.compute(session, n or 3600)
		Net.event("OfflineEarnings"):FireClient(player, { Amount = amount, Seconds = seconds, Capped = capped })
		SessionService.notify(player, "Simuliert (nur Anzeige). Einsammeln geht nur nach echtem Offline.", "info")
	elseif cmd == "reset" then
		local fresh = DataTemplate.new()
		for k, v in fresh :: any do
			(session.Data :: any)[k] = v
		end
		MineService.resetCycles(session)
		PlotService.refreshLevels(session)
	else
		return
	end
	session.Dirty = true
	SessionService.notify(player, "Debug: /" .. cmd .. " " .. (arg or ""), "info")
end

function DebugService.start()
	if not RunService:IsStudio() then
		return
	end
	local function hook(player: Player)
		player.Chatted:Connect(function(message)
			handle(player, message)
		end)
	end
	Players.PlayerAdded:Connect(hook)
	for _, p in Players:GetPlayers() do
		hook(p)
	end
	print("[DebugService] Studio-Testbefehle aktiv: /cash /gems /event /offline /reset")
end

return DebugService

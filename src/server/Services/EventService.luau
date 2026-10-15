--!strict
--[[
	EventService
	============
	Zufällige Server-Events ("Goldrausch", "Arbeitsfieber") in regelmäßigen
	Abständen. Alle Spieler profitieren gleichzeitig -> Grund, online zu bleiben.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Clock = require(Shared.Clock)
local Config = require(Shared.Config)
local Net = require(Shared.Net)

local SessionService = require(script.Parent.SessionService)

local EventService = {}

local rng = Random.new()
local running = false

--- Startet ein Event sofort (auch für Tests)
function EventService.trigger(eventId: string?)
	if running then
		return
	end
	local list = Config.Events.List
	local event = list[rng:NextInteger(1, #list)]
	if eventId then
		for _, e in list do
			if e.Id == eventId then
				event = e
			end
		end
	end
	running = true
	SessionService.setEvent({
		Id = event.Id,
		EndsAt = Clock.now() + event.Duration,
		Cash = event.CashMultiplier,
		Speed = event.SpeedMultiplier,
	})
	Net.event("ServerEvent"):FireAllClients({ Started = true, Name = event.Name, Description = event.Description })
	task.delay(event.Duration, function()
		SessionService.setEvent(nil)
		running = false
		Net.event("ServerEvent"):FireAllClients({ Started = false, Name = event.Name })
	end)
end

function EventService.start()
	if not Config.Events.Enabled then
		return
	end
	task.spawn(function()
		while true do
			task.wait(rng:NextNumber(Config.Events.MinInterval, Config.Events.MaxInterval))
			if #SessionService.all() > 0 then
				EventService.trigger(nil)
			end
		end
	end)
end

return EventService

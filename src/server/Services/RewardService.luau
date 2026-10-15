--!strict
--[[
	RewardService
	=============
	  * Spielzeit-Gems: alle Config.Gems.PlaytimeInterval Sekunden online
	  * Tägliche Login-Belohnung mit Serie (Gems + Einkommen)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local BigNum = require(Shared.BigNum)
local Clock = require(Shared.Clock)
local Config = require(Shared.Config)
local Formulas = require(Shared.Formulas)

local NetService = require(script.Parent.NetService)
local SessionService = require(script.Parent.SessionService)

type Session = SessionService.Session

local RewardService = {}

function RewardService.claimDaily(session: Session): (boolean, string?)
	local data = session.Data
	local now = Clock.now()
	if not Formulas.dailyAvailable(data, now) then
		return false, "Heute schon abgeholt - komm morgen wieder!"
	end
	local streak = Formulas.nextDailyStreak(data, now)
	local reward = Formulas.dailyReward(streak)
	data.DailyStreak = streak
	data.LastDailyClaim = now

	SessionService.addGems(session, reward.Gems)
	local income = Formulas.incomePerSecond(data, SessionService.context(session), false)
	local cash = BigNum.max(BigNum.mulNum(income, reward.IncomeSeconds), BigNum.new(reward.MinCash))
	SessionService.addCash(session, cash)
	SessionService.effect(session.Player, "Gems", { Amount = reward.Gems })
	SessionService.effect(session.Player, "Cash", { Amount = cash })
	SessionService.notify(
		session.Player,
		string.format("🎁 Tag %d abgeholt! Serie läuft weiter 🔥", streak),
		"success"
	)
	return true, nil
end

function RewardService.start()
	NetService.register("ClaimDaily", {}, function(session)
		return RewardService.claimDaily(session)
	end)

	SessionService.onStart(40, function(session)
		task.delay(4, function()
			if session.Player.Parent and Formulas.dailyAvailable(session.Data, Clock.now()) then
				SessionService.notify(session.Player, "🎁 Deine tägliche Belohnung wartet!", "gold")
			end
		end)
	end)

	-- Spielzeit-Gems
	task.spawn(function()
		while true do
			task.wait(1)
			for _, session in SessionService.all() do
				local data = session.Data
				data.PlaytimeSeconds += 1
				data.PlaytimeGemTimer += 1
				if data.PlaytimeGemTimer >= Config.Gems.PlaytimeInterval then
					data.PlaytimeGemTimer = 0
					SessionService.addGems(session, Config.Gems.PlaytimeAmount)
					SessionService.effect(session.Player, "Gems", { Amount = Config.Gems.PlaytimeAmount })
					SessionService.notify(
						session.Player,
						"Danke fürs Spielen! +" .. Config.Gems.PlaytimeAmount .. " 💎",
						"success"
					)
				end
			end
		end
	end)
end

return RewardService

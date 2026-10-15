--!strict
--[[
	StealService
	============
	Stehlen aus fremden Aufzugslagern (Steal-a-Brainrot-Prinzip) - alles
	serverseitig geprüft:
	  * nicht beim eigenen Plot, Distanz-Check zum Depot
	  * Cooldowns für Dieb und Opfer
	  * Neulingsschutz, Schild-Boost, abgeschlossene Basis
	  * Besitzer in der Nähe seines Aufzugs = bewacht -> Diebstahl scheitert
	  * Beute: Prozent des Lagers, gedeckelt auf X Sekunden Einkommen des Diebs

	Basis abschließen: gratis, für LockDuration Sekunden, danach Abklingzeit.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local BigNum = require(Shared.BigNum)
local Clock = require(Shared.Clock)
local Config = require(Shared.Config)
local Formulas = require(Shared.Formulas)

local NetService = require(script.Parent.NetService)
local PlotService = require(script.Parent.PlotService)
local SessionService = require(script.Parent.SessionService)

type Session = SessionService.Session

local StealService = {}

local CFG = Config.Steal
local lastAttemptAlert: { [Session]: number } = {}

local function rootPosition(player: Player): Vector3?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return root.Position
	end
	return nil
end

--- Grund, warum das Opfer geschützt ist (oder nil)
local function protectionReason(victim: Session, now: number): string?
	if victim.LockedUntil > now then
		return "Diese Basis ist abgeschlossen! 🔒"
	end
	if victim.JoinTime + CFG.NewPlayerProtection > now then
		return "Dieser Spieler hat noch Neulingsschutz 🐣"
	end
	if Formulas.isBoostActive(victim.Data, "Shield", now) or Formulas.hasPower(victim.Data, "Shield") then
		return "Dieses Lager ist durch ein Schild geschützt 🛡️"
	end
	return nil
end

local function attempt(thief: Player, victim: Session)
	local thiefSession = SessionService.get(thief)
	if not thiefSession or thiefSession == victim then
		return
	end
	local now = Clock.now()

	-- Distanz prüfen (Prompt-Distanz + Toleranz)
	local depotPos = PlotService.getDepotPosition(victim)
	local thiefPos = rootPosition(thief)
	if not depotPos or not thiefPos or (thiefPos - depotPos).Magnitude > CFG.MaxActivationDistance + 6 then
		return
	end

	local reason = protectionReason(victim, now)
	if reason then
		SessionService.notify(thief, reason, "warn")
		return
	end
	local thiefWait = thiefSession.LastStealAt + CFG.ThiefCooldown - now
	if thiefWait > 0 then
		SessionService.notify(thief, "Du musst noch " .. Formulas.formatDuration(thiefWait) .. " warten", "warn")
		return
	end
	if victim.LastRobbedAt + CFG.VictimCooldown > now then
		SessionService.notify(thief, "Dieses Lager wurde gerade erst geplündert!", "warn")
		return
	end
	-- Bewacht?
	local ownerPos = rootPosition(victim.Player)
	if ownerPos and (ownerPos - depotPos).Magnitude <= CFG.GuardRadius then
		thiefSession.LastStealAt = now -- Strafe: Cooldown trotzdem
		SessionService.notify(thief, "Der Besitzer bewacht sein Lager! 👮", "error")
		SessionService.notify(victim.Player, "Du hast " .. thief.DisplayName .. " verjagt! 💪", "success")
		return
	end
	local stock = victim.Data.Elevator.Stock
	if BigNum.isZero(stock) then
		SessionService.notify(thief, "Das Lager ist leer!", "warn")
		return
	end

	local thiefIncome = Formulas.incomePerSecond(thiefSession.Data, SessionService.context(thiefSession), false)
	local cap = BigNum.max(BigNum.mulNum(thiefIncome, CFG.CapSecondsOfThiefIncome), BigNum.new(CFG.MinCap))
	local amount = BigNum.min(BigNum.mulNum(stock, CFG.Percent), cap)
	if BigNum.isZero(amount) then
		return
	end

	victim.Data.Elevator.Stock = BigNum.clampPositive(BigNum.sub(stock, amount))
	victim.LastRobbedAt = now
	victim.Data.Stats.TimesRobbed += 1
	victim.Dirty = true
	thiefSession.LastStealAt = now
	thiefSession.Data.Stats.StealsDone += 1
	SessionService.addCash(thiefSession, amount)
	PlotService.updateVisuals(victim)

	local text = BigNum.formatMoney(amount, Config.CurrencySymbol)
	SessionService.effect(thief, "Stolen", { Amount = amount })
	SessionService.effect(victim.Player, "Robbed", { Thief = thief.DisplayName, Amount = amount })
	SessionService.notify(
		victim.Player,
		string.format("%s hat %s gestohlen! Schließ deine Basis ab 🔒", thief.DisplayName, text),
		"error"
	)
	for _, other in Players:GetPlayers() do
		if other ~= thief and other ~= victim.Player then
			SessionService.notify(
				other,
				string.format("💰 %s hat %s ausgeraubt!", thief.DisplayName, victim.Player.DisplayName),
				"gold"
			)
		end
	end
end

local function onPrompt(thief: Player, victim: Session, phase: string)
	if not CFG.Enabled or thief == victim.Player then
		return
	end
	if phase == "begin" then
		local now = Clock.now()
		if protectionReason(victim, now) then
			return
		end
		local last = lastAttemptAlert[victim] or 0
		if now - last > 8 then
			lastAttemptAlert[victim] = now
			SessionService.effect(victim.Player, "StealAttempt", { Thief = thief.DisplayName })
		end
	elseif phase == "trigger" then
		attempt(thief, victim)
	end
end

function StealService.lock(session: Session): (boolean, string?)
	local now = Clock.now()
	if session.LockedUntil > now then
		return false, "Schon abgeschlossen"
	end
	if session.Data.LockCooldownUntil > now then
		return false, "Schloss lädt noch: " .. Formulas.formatDuration(session.Data.LockCooldownUntil - now)
	end
	session.LockedUntil = now + CFG.LockDuration
	session.Data.LockCooldownUntil = now + CFG.LockDuration + CFG.LockCooldown
	session.Dirty = true
	PlotService.updateVisuals(session)
	SessionService.notify(
		session.Player,
		string.format("🔒 Basis für %ds abgeschlossen!", CFG.LockDuration),
		"success"
	)
	task.delay(CFG.LockDuration + 0.1, function()
		if session.Player.Parent then
			PlotService.updateVisuals(session)
			session.Dirty = true
		end
	end)
	return true, nil
end

function StealService.start()
	PlotService.setDepotPromptHandler(onPrompt)
	SessionService.onEnd(5, function(session)
		lastAttemptAlert[session] = nil
	end)
	NetService.register("LockBase", {}, function(session)
		if not CFG.Enabled then
			return false, "Stehlen ist deaktiviert"
		end
		return StealService.lock(session)
	end)
end

return StealService

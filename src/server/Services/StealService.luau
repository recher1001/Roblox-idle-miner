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

	Manager klauen: F halten am Manager einer fremden Station (tiefer = länger),
	dann den Manager in die eigene Basis tragen. Treffer mit Schläger/Slap,
	Tod oder Zeitablauf -> Manager geht zurück zum Besitzer.

	Basis abschließen: gratis, für LockDuration Sekunden, danach Abklingzeit.
	Während die Basis geschützt ist, steht eine Laserwand um den Plot und
	fremde Spieler werden hinausgeschoben.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local BigNum = require(Shared.BigNum)
local Clock = require(Shared.Clock)
local Config = require(Shared.Config)
local Formulas = require(Shared.Formulas)
local Types = require(Shared.Types)

local ManagerService = require(script.Parent.ManagerService)
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

--- Laser-Brecher aktiv? (Gadget aus dem CombatService)
local function breaksLasers(player: Player?, now: number): boolean
	local character = player and player.Character
	local untilTime = character and character:GetAttribute("LaserBreakUntil")
	return type(untilTime) == "number" and untilTime > now
end

--- Grund, warum das Opfer geschützt ist (oder nil)
local function protectionReason(victim: Session, now: number, thief: Player?): string?
	if victim.LockedUntil > now and not breaksLasers(thief, now) then
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

----------------------------------------------------------------------
-- Manager klauen (tragen -> in die eigene Basis bringen)
----------------------------------------------------------------------
type Carry = {
	Thief: Session,
	Victim: Session,
	ManagerId: string,
	FromKey: string,
	Until: number,
}

local MCFG = Config.ManagerSteal
local carries: { [Player]: Carry } = {}
local lastManagerSteal: { [Session]: number } = {}
local lastManagerRobbed: { [Session]: number } = {}

local function isFrozen(player: Player): boolean
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return root ~= nil and root:IsA("BasePart") and root.Anchored
end

local function setCarryVisual(player: Player, manager: Types.ManagerData?)
	local character = player.Character
	if not character then
		return
	end
	local old = character:FindFirstChild("CarriedManager")
	if old then
		old:Destroy()
	end
	character:SetAttribute("Carrying", manager ~= nil)
	local head = character:FindFirstChild("Head")
	if not manager or not head or not head:IsA("BasePart") then
		return
	end
	local color = Formulas.rarityDef(manager.Rarity).Color
	local ball = Instance.new("Part")
	ball.Name = "CarriedManager"
	ball.Shape = Enum.PartType.Ball
	ball.Size = Vector3.new(2.2, 2.2, 2.2)
	ball.Color = color
	ball.Material = Enum.Material.Neon
	ball.Transparency = 0.25
	ball.CanCollide = false
	ball.CanQuery = false
	ball.CanTouch = false
	ball.Massless = true
	ball.CFrame = head.CFrame * CFrame.new(0, 2.6, 0)
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = head
	weld.Part1 = ball
	weld.Parent = ball
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromScale(7, 2.2)
	gui.StudsOffset = Vector3.new(0, 2.2, 0)
	gui.LightInfluence = 0
	gui.Parent = ball
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.Text = "👔 " .. manager.Name .. " 🏃"
	label.TextColor3 = color
	label.TextStrokeTransparency = 0
	label.Parent = gui
	local sparkle = Instance.new("Sparkles")
	sparkle.SparkleColor = color
	sparkle.Parent = ball
	-- mit Unsichtbarkeitsmantel bleibt auch der Manager unsichtbar
	if character:GetAttribute("Invisible") == true then
		ball:SetAttribute("OrigT", ball.Transparency)
		ball.Transparency = 1
		gui:SetAttribute("OrigEnabled", true)
		gui.Enabled = false
		sparkle:SetAttribute("OrigEnabled", true)
		sparkle.Enabled = false
	end
	ball.Parent = character
end

--- Manager geht zurück zum Besitzer (Treffer, Tod, Zeit abgelaufen ...)
local function dropCarry(carry: Carry, reason: string)
	local thiefPlayer = carry.Thief.Player
	if carries[thiefPlayer] ~= carry then
		return
	end
	carries[thiefPlayer] = nil
	setCarryVisual(thiefPlayer, nil)
	local victim = carry.Victim
	if SessionService.get(victim.Player) == victim then
		local manager = Formulas.findManager(victim.Data, carry.ManagerId)
		if manager and manager.AssignedTo == nil and not Formulas.managerFor(victim.Data, carry.FromKey) then
			manager.AssignedTo = carry.FromKey
		end
		SessionService.managersChanged(victim)
		PlotService.updateVisuals(victim)
		SessionService.notify(victim.Player, "✅ Dein Manager ist zurück! (" .. reason .. ")", "success")
	end
	if thiefPlayer.Parent then
		SessionService.notify(thiefPlayer, "❌ Manager verloren: " .. reason, "warn")
	end
end

--- Dieb ist in seiner Basis angekommen: Manager wechselt den Besitzer
local function deliver(carry: Carry)
	local thief, victim = carry.Thief, carry.Victim
	local manager = Formulas.findManager(victim.Data, carry.ManagerId)
	if not manager or #thief.Data.Managers >= Config.Managers.MaxOwned then
		dropCarry(carry, if manager then "kein Platz für weitere Manager" else "Manager existiert nicht mehr")
		return
	end
	carries[thief.Player] = nil
	setCarryVisual(thief.Player, nil)
	local index = table.find(victim.Data.Managers, manager)
	if index then
		table.remove(victim.Data.Managers, index)
	end
	local stolen: Types.ManagerData = {
		Id = "M" .. tostring(thief.Data.NextManagerId),
		Name = manager.Name,
		FriendUserId = manager.FriendUserId,
		Area = manager.Area,
		Rarity = manager.Rarity,
		Ability = manager.Ability,
		AssignedTo = ManagerService.firstFreeStation(thief.Data, manager.Area),
		ActiveUntil = 0,
		CooldownUntil = 0,
	}
	thief.Data.NextManagerId += 1
	table.insert(thief.Data.Managers, stolen)
	lastManagerRobbed[victim] = Clock.now()
	victim.Data.Stats.TimesRobbed += 1
	thief.Data.Stats.StealsDone += 1
	SessionService.managersChanged(victim)
	SessionService.managersChanged(thief)
	PlotService.updateVisuals(victim)
	PlotService.updateVisuals(thief)
	local rarity = Formulas.rarityDef(stolen.Rarity)
	SessionService.effect(thief.Player, "ManagerStolen", { Name = stolen.Name, Rarity = rarity.Name })
	SessionService.notify(
		victim.Player,
		string.format(
			"😭 %s hat deinen Manager %s geklaut! Schütze deine Basis 🔒",
			thief.Player.DisplayName,
			stolen.Name
		),
		"error"
	)
	for _, other in Players:GetPlayers() do
		if other ~= thief.Player and other ~= victim.Player then
			SessionService.notify(
				other,
				string.format(
					"👔 %s hat %s einen %s Manager geklaut!",
					thief.Player.DisplayName,
					victim.Player.DisplayName,
					rarity.Name
				),
				"gold"
			)
		end
	end
end

local function startManagerSteal(thief: Player, victim: Session, key: string)
	local thiefSession = SessionService.get(thief)
	if not thiefSession or thiefSession == victim or not MCFG.Enabled then
		return
	end
	local now = Clock.now()
	if carries[thief] then
		SessionService.notify(thief, "Du trägst schon einen Manager!", "warn")
		return
	end
	if isFrozen(thief) then
		return
	end
	local station = PlotService.getStation(victim, key)
	local spot = station and station:FindFirstChild("StealSpot")
	local thiefPos = rootPosition(thief)
	if
		not spot
		or not spot:IsA("BasePart")
		or not thiefPos
		or (thiefPos - spot.Position).Magnitude > MCFG.MaxActivationDistance + 6
	then
		return
	end
	local reason = protectionReason(victim, now, thief)
	if reason then
		SessionService.notify(thief, reason, "warn")
		return
	end
	local thiefWait = (lastManagerSteal[thiefSession] or 0) + MCFG.ThiefCooldown - now
	if thiefWait > 0 then
		SessionService.notify(
			thief,
			"Du kannst erst in " .. Formulas.formatDuration(thiefWait) .. " wieder klauen",
			"warn"
		)
		return
	end
	if (lastManagerRobbed[victim] or 0) + MCFG.VictimCooldown > now then
		SessionService.notify(thief, "Diesem Spieler wurde gerade erst ein Manager geklaut!", "warn")
		return
	end
	if #thiefSession.Data.Managers >= Config.Managers.MaxOwned then
		SessionService.notify(thief, "Du hast schon die maximale Anzahl Manager", "warn")
		return
	end
	local manager = Formulas.managerFor(victim.Data, key)
	if not manager then
		return
	end
	manager.AssignedTo = nil
	SessionService.managersChanged(victim)
	PlotService.updateVisuals(victim)
	lastManagerSteal[thiefSession] = now
	carries[thief] = {
		Thief = thiefSession,
		Victim = victim,
		ManagerId = manager.Id,
		FromKey = key,
		Until = now + MCFG.CarryTime,
	}
	setCarryVisual(thief, manager)
	SessionService.notify(
		thief,
		string.format("👔 Lauf! Bring %s in %ds in deine Basis!", manager.Name, MCFG.CarryTime),
		"gold"
	)
	SessionService.effect(victim.Player, "ManagerTheft", { Thief = thief.DisplayName, Name = manager.Name })
end

local function onManagerPrompt(thief: Player, victim: Session, key: string, phase: string)
	if thief == victim.Player then
		return
	end
	if phase == "begin" then
		local now = Clock.now()
		if protectionReason(victim, now, thief) then
			return
		end
		local last = lastAttemptAlert[victim] or 0
		if now - last > 8 then
			lastAttemptAlert[victim] = now
			SessionService.notify(
				victim.Player,
				"🚨 " .. thief.DisplayName .. " versucht deinen Manager zu klauen! Lauf hin!",
				"alarm"
			)
		end
	elseif phase == "trigger" then
		startManagerSteal(thief, victim, key)
	end
end

--- Von CombatService: getroffene Diebe verlieren ihren Manager
function StealService.dropCarried(player: Player, reason: string)
	local carry = carries[player]
	if carry then
		dropCarry(carry, reason)
	end
end

function StealService.isCarrying(player: Player): boolean
	return carries[player] ~= nil
end

local function carryTick()
	local now = Clock.now()
	for player, carry in carries do
		local thiefAlive = SessionService.get(player) == carry.Thief
		local victimAlive = SessionService.get(carry.Victim.Player) == carry.Victim
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local pos = rootPosition(player)
		if not thiefAlive or not victimAlive then
			dropCarry(carry, "Spieler hat das Spiel verlassen")
		elseif not humanoid or humanoid.Health <= 0 or not pos then
			dropCarry(carry, "Dieb wurde besiegt")
		elseif now > carry.Until then
			dropCarry(carry, "Zeit abgelaufen")
		elseif PlotService.isOnSurfaceOf(carry.Thief, pos) then
			deliver(carry)
		end
	end
end

--- Abgeschlossene Basen: fremde Spieler werden hinausgeschoben
local pushNotified: { [Player]: number } = {}
local function pushOutTick()
	local now = Clock.now()
	for _, session in SessionService.all() do
		if session.LockedUntil > now then
			for _, other in Players:GetPlayers() do
				if other ~= session.Player and not breaksLasers(other, now) then
					local pos = rootPosition(other)
					if pos and PlotService.plotIndexAt(pos) == session.PlotIndex then
						local cf = PlotService.outsideCFrame(session.PlotIndex, pos)
						local character = other.Character
						if cf and character then
							character:PivotTo(cf)
							if (pushNotified[other] or 0) + 3 < now then
								pushNotified[other] = now
								SessionService.notify(other, "🔒 Diese Basis ist geschützt!", "warn")
							end
						end
					end
				end
			end
		end
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
	PlotService.setManagerPromptHandler(onManagerPrompt)
	PlotService.setLockPromptHandler(function(player, session)
		if player ~= session.Player then
			SessionService.notify(player, "Das ist nicht deine Basis!", "warn")
			return
		end
		local ok, msg = StealService.lock(session)
		if not ok and msg then
			SessionService.notify(player, msg, "warn")
		end
	end)
	SessionService.onEnd(5, function(session)
		lastAttemptAlert[session] = nil
		local carry = carries[session.Player]
		if carry then
			dropCarry(carry, "Spieler hat das Spiel verlassen")
		end
		-- trägt jemand einen Manager dieses Spielers? -> abbrechen
		for _, c in carries do
			if c.Victim == session then
				dropCarry(c, "Besitzer hat das Spiel verlassen")
			end
		end
		lastManagerSteal[session] = nil
		lastManagerRobbed[session] = nil
		pushNotified[session.Player] = nil
	end)
	task.spawn(function()
		while true do
			task.wait(Config.Combat.PushOutInterval)
			local ok, err = pcall(function()
				carryTick()
				pushOutTick()
			end)
			if not ok then
				warn("[StealService]", err)
			end
		end
	end)
	NetService.register("LockBase", {}, function(session)
		if not CFG.Enabled then
			return false, "Stehlen ist deaktiviert"
		end
		return StealService.lock(session)
	end)
end

return StealService

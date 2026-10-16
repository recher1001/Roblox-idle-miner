--!strict
--[[
	AdminService
	============
	Admin-System mit Owner, Admins und einzelnen Rechten - ALLES serverseitig geprüft.

	  * Owner (Config.Admin.OwnerName / OwnerUserId): hat immer alle Rechte,
	    kann nicht entfernt werden, Admins können ihm nichts wegnehmen,
	    ihn nicht kicken und nicht zurücksetzen.
	  * Admins: vergibt nur der Owner. Pro Admin einzeln einstellbar, welche
	    Rechte er hat (Geld, Gems, Fortschritt, Kräfte, Events, Kick, Reset).
	    Die Liste wird in einem eigenen DataStore gespeichert (gilt in allen Servern).
	  * Kräfte (OP-Sachen): Fliegender Teppich, Super-Speed, Mega-Sprung,
	    Unbestehlbar, Turbo-Mine, Goldener Händler - werden im Spielstand gespeichert.
	  * In Studio ist jeder Tester Owner (Config.Admin.StudioEveryoneOwner).
]]

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local BigNum = require(Shared.BigNum)
local Config = require(Shared.Config)
local Formulas = require(Shared.Formulas)
local Types = require(Shared.Types)

local DataTemplate = require(script.Parent.Parent.Modules.DataTemplate)
local EventService = require(script.Parent.EventService)
local ManagerService = require(script.Parent.ManagerService)
local MineService = require(script.Parent.MineService)
local NetService = require(script.Parent.NetService)
local CombatService = require(script.Parent.CombatService)
local OfflineService = require(script.Parent.OfflineService)
local PetService = require(script.Parent.PetService)
local PlotService = require(script.Parent.PlotService)
local SessionService = require(script.Parent.SessionService)

type Session = SessionService.Session
type AdminRecord = { Name: string, Permissions: { [string]: boolean } }

local AdminService = {}

local CFG = Config.Admin
local ADMIN_KEY = "Admins"

local ownerUserId: number = CFG.OwnerUserId
local admins: { [number]: AdminRecord } = {}
local store: DataStore? = nil
local syncTools: (Session) -> () -- weiter unten definiert

----------------------------------------------------------------------
-- Rollen & Rechte
----------------------------------------------------------------------
local function validPermission(perm: string): boolean
	for _, p in CFG.Permissions do
		if p.Id == perm then
			return true
		end
	end
	return false
end

local function validPower(powerId: string): boolean
	for _, p in CFG.Powers do
		if p.Id == powerId then
			return true
		end
	end
	return false
end

--- Ist das der ECHTE Owner? (unabhängig vom Studio-Testmodus)
function AdminService.isRealOwner(player: Player): boolean
	if ownerUserId ~= 0 then
		return player.UserId == ownerUserId
	end
	return string.lower(player.Name) == string.lower(CFG.OwnerName)
end

function AdminService.isOwner(player: Player): boolean
	if RunService:IsStudio() and CFG.StudioEveryoneOwner then
		return true
	end
	return AdminService.isRealOwner(player)
end

function AdminService.permissions(player: Player): { [string]: boolean }
	local perms: { [string]: boolean } = {}
	if AdminService.isOwner(player) then
		for _, p in CFG.Permissions do
			perms[p.Id] = true
		end
		return perms
	end
	local record = admins[player.UserId]
	if record then
		for perm, on in record.Permissions do
			if on and validPermission(perm) then
				perms[perm] = true
			end
		end
	end
	return perms
end

function AdminService.isAdmin(player: Player): boolean
	return AdminService.isOwner(player) or admins[player.UserId] ~= nil
end

function AdminService.can(player: Player, perm: string): boolean
	return AdminService.permissions(player)[perm] == true
end

--- Aktualisiert die Admin-Infos im Snapshot eines Spielers
local function refreshInfo(session: Session)
	local player = session.Player
	task.defer(syncTools, session)
	if not AdminService.isAdmin(player) then
		session.Admin = nil
		session.Dirty = true
		return
	end
	local isOwner = AdminService.isOwner(player)
	local list: { Types.AdminEntry }? = nil
	if isOwner then
		local entries: { Types.AdminEntry } = {}
		for userId, record in admins do
			table.insert(entries, { UserId = userId, Name = record.Name, Permissions = record.Permissions })
		end
		table.sort(entries, function(a, b)
			return a.Name < b.Name
		end)
		list = entries
	end
	session.Admin = {
		IsOwner = isOwner,
		Permissions = AdminService.permissions(player),
		Admins = list,
	}
	session.Dirty = true
end

local function refreshAll()
	for _, s in SessionService.all() do
		refreshInfo(s)
	end
end

----------------------------------------------------------------------
-- Speicherung der Admin-Liste
----------------------------------------------------------------------
local function encode(): { [string]: any }
	local out: { [string]: any } = {}
	for userId, record in admins do
		out[tostring(userId)] = { Name = record.Name, Permissions = record.Permissions }
	end
	return out
end

local function decode(raw: any)
	table.clear(admins)
	if type(raw) ~= "table" then
		return
	end
	for key, record in raw do
		local userId = tonumber(key)
		if userId and type(record) == "table" then
			local perms: { [string]: boolean } = {}
			if type(record.Permissions) == "table" then
				for perm, on in record.Permissions do
					if type(perm) == "string" and on == true and validPermission(perm) then
						perms[perm] = true
					end
				end
			end
			admins[userId] = {
				Name = if type(record.Name) == "string" then string.sub(record.Name, 1, 32) else tostring(userId),
				Permissions = perms,
			}
		end
	end
end

local function saveAdmins()
	local activeStore = store
	if not activeStore then
		return
	end
	local payload = encode()
	task.spawn(function()
		for attempt = 1, 3 do
			local ok, err = pcall(function()
				activeStore:SetAsync(ADMIN_KEY, payload)
			end)
			if ok then
				return
			end
			warn("[AdminService] Admin-Liste speichern fehlgeschlagen:", err)
			task.wait(2 ^ attempt)
		end
	end)
end

local function loadAdmins()
	local activeStore = store
	if not activeStore then
		return
	end
	local ok, result = pcall(function()
		return activeStore:GetAsync(ADMIN_KEY)
	end)
	if ok then
		decode(result)
		refreshAll()
	else
		warn("[AdminService] Admin-Liste laden fehlgeschlagen:", result)
	end
end

----------------------------------------------------------------------
-- Kräfte
----------------------------------------------------------------------
local function buildCarpet(root: BasePart): Model
	local m = Instance.new("Model")
	m.Name = "MagicCarpet"
	local function part(name: string, size: Vector3, offset: CFrame, color: Color3, material: Enum.Material): Part
		local p = Instance.new("Part")
		p.Name = name
		p.Size = size
		p.CFrame = root.CFrame * CFrame.new(0, -3.15, 0) * offset
		p.Color = color
		p.Material = material
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.Massless = true
		p.Anchored = false
		p.TopSurface = Enum.SurfaceType.Smooth
		p.BottomSurface = Enum.SurfaceType.Smooth
		p.Parent = m
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = root
		weld.Part1 = p
		weld.Parent = p
		return p
	end
	local red = Color3.fromRGB(190, 30, 70)
	local gold = Color3.fromRGB(255, 200, 60)
	local base = part("Carpet", Vector3.new(6, 0.3, 8.5), CFrame.new(), red, Enum.Material.Fabric)
	part("Pattern", Vector3.new(3.6, 0.32, 6), CFrame.new(), Color3.fromRGB(60, 40, 140), Enum.Material.Fabric)
	part("Diamond", Vector3.new(1.6, 0.34, 1.6), CFrame.Angles(0, math.rad(45), 0), gold, Enum.Material.Fabric)
	for _, side in { -1, 1 } do
		part("Border", Vector3.new(0.35, 0.34, 8.5), CFrame.new(side * 2.85, 0, 0), gold, Enum.Material.Fabric)
		for n = -2, 2 do
			part(
				"Tassel",
				Vector3.new(0.25, 0.25, 0.8),
				CFrame.new(n * 1.2, 0, side * 4.55),
				gold,
				Enum.Material.Fabric
			)
		end
	end
	local sparkle = Instance.new("Sparkles")
	sparkle.SparkleColor = gold
	sparkle.Parent = base
	m.PrimaryPart = base
	return m
end

local function setCarpet(player: Player, on: boolean)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not character or not root or not root:IsA("BasePart") then
		return
	end
	local existing = character:FindFirstChild("MagicCarpet")
	if existing then
		existing:Destroy()
	end
	if on then
		buildCarpet(root).Parent = character
	end
	character:SetAttribute("CarpetActive", on)
end

--- Wendet Speed/Sprung/Teppich auf den aktuellen Charakter an
--- Gibt es ein ausgerüstetes Item mit dieser Kraft?
local function equipped(character: Model, powerId: string): boolean
	for _, child in character:GetChildren() do
		if child:IsA("Tool") and child:GetAttribute("PowerTool") == powerId then
			return true
		end
	end
	return false
end

--- Wendet Speed/Sprung/Teppich auf den aktuellen Charakter an.
--- Die Kräfte wirken, solange das passende Item ausgerüstet ist.
local function applyPowers(session: Session)
	local character = session.Player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not character or not humanoid then
		return
	end
	local data = session.Data
	local speed = Formulas.hasPower(data, "Speed") and equipped(character, "Speed")
	local jump = Formulas.hasPower(data, "Jump") and equipped(character, "Jump")
	local carpet = Formulas.hasPower(data, "Carpet") and equipped(character, "Carpet")
	local mult = character:GetAttribute("SpeedMult")
	humanoid.WalkSpeed = (if speed then CFG.WalkSpeed else 16) * (if type(mult) == "number" then mult else 1)
	humanoid.UseJumpPower = true
	humanoid.JumpPower = if jump then CFG.JumpPower else 50
	local carpetActive = character:GetAttribute("CarpetActive") == true
	if carpet ~= carpetActive then
		setCarpet(session.Player, carpet)
	end
end

----------------------------------------------------------------------
-- Items im Inventar (Backpack)
----------------------------------------------------------------------
type ToolDef = { Id: string, Name: string, Tip: string }
local POWER_TOOLS: { ToolDef } = {
	{ Id = "Carpet", Name = "🧞 Teppich", Tip = "Ausrüsten = fliegen! Leertaste/▲ hoch, Q/▼ runter" },
	{ Id = "Speed", Name = "⚡ Speed-Spule", Tip = "Ausrüsten = super schnell rennen" },
	{ Id = "Jump", Name = "🦘 Sprung-Spule", Tip = "Ausrüsten = riesig hoch springen" },
	{ Id = "Hammer", Name = "🔨 Admin-Hammer", Tip = "Klicken = alle Gegner im Umkreis 15 s einfrieren" },
}
local WAND: ToolDef =
	{ Id = "AdminWand", Name = "🪄 Admin-Stab", Tip = "Auf einen Spieler klicken = Admin-Menü für ihn" }

local function makeTool(def: ToolDef): Tool
	local tool = Instance.new("Tool")
	tool.Name = def.Name
	tool.ToolTip = def.Tip
	tool.RequiresHandle = false
	tool.CanBeDropped = false
	tool:SetAttribute("PowerTool", def.Id)
	return tool
end

local function wantedTools(session: Session): { ToolDef }
	local list = {}
	for _, def in POWER_TOOLS do
		if Formulas.hasPower(session.Data, def.Id) then
			table.insert(list, def)
		end
	end
	if AdminService.isAdmin(session.Player) then
		table.insert(list, WAND)
	end
	return list
end

--- Gleicht die Items in Backpack/Charakter mit den Kräften ab (auch nach dem Respawn)
syncTools = function(session: Session)
	local player = session.Player
	if not player.Parent then
		return
	end
	local wanted: { [string]: ToolDef } = {}
	for _, def in wantedTools(session) do
		wanted[def.Id] = def
	end
	local containers: { Instance } = {}
	for _, name in { "Backpack" } do
		local c = player:FindFirstChild(name)
		if c then
			table.insert(containers, c)
		end
	end
	if player.Character then
		table.insert(containers, player.Character)
	end
	local present: { [string]: { [Instance]: boolean } } = {}
	for _, container in containers do
		for _, child in container:GetChildren() do
			local id = child:GetAttribute("PowerTool")
			if child:IsA("Tool") and type(id) == "string" then
				if wanted[id] then
					present[id] = present[id] or {}
					present[id][container] = true
				else
					child:Destroy()
				end
			end
		end
	end
	local backpack = player:FindFirstChild("Backpack")
	local character = player.Character
	for id, def in wanted do
		local where = present[id] or {}
		local inHand = character ~= nil and where[character] == true
		if backpack and not inHand and not where[backpack] then
			local tool = makeTool(def)
			if def.Id == "Hammer" then
				CombatService.bindHammer(tool, player)
			end
			tool.Parent = backpack
		end
	end
	applyPowers(session)
end

----------------------------------------------------------------------
-- Aktionen
----------------------------------------------------------------------
type ActionDef = { Perm: string, Negative: boolean?, Global: boolean? }

local ACTIONS: { [string]: ActionDef } = {
	cash = { Perm = "Cash" },
	multcash = { Perm = "Cash" },
	halfcash = { Perm = "Cash", Negative = true },
	zerocash = { Perm = "Cash", Negative = true },
	gems = { Perm = "Gems" },
	zerogems = { Perm = "Gems", Negative = true },
	unlockall = { Perm = "Progress" },
	managers = { Perm = "Progress" },
	cooldowns = { Perm = "Progress" },
	daily = { Perm = "Progress" },
	offline = { Perm = "Progress" },
	powergive = { Perm = "Powers" },
	powertake = { Perm = "Powers", Negative = true },
	petgive = { Perm = "Pets" },
	pettake = { Perm = "Pets", Negative = true },
	tickets = { Perm = "Pets" },
	petslots = { Perm = "Pets" },
	event = { Perm = "Events", Global = true },
	kick = { Perm = "Kick", Negative = true },
	reset = { Perm = "Reset", Negative = true },
}

local function apply(target: Session, action: string, value: string): string?
	local data = target.Data
	local n = tonumber(value)
	if action == "cash" then
		local amount = BigNum.new(math.max(0, n or 1e6))
		SessionService.addCash(target, amount)
		return "+" .. BigNum.formatMoney(amount, Config.CurrencySymbol)
	elseif action == "multcash" then
		local factor = math.clamp(n or 1000, 1, 1e6)
		SessionService.addCash(target, BigNum.mulNum(data.Cash, factor - 1))
		return "Geld x" .. tostring(factor)
	elseif action == "halfcash" then
		data.Cash = BigNum.mulNum(data.Cash, 0.5)
		return "Geld halbiert"
	elseif action == "zerocash" then
		data.Cash = BigNum.zero()
		return "Geld auf 0"
	elseif action == "gems" then
		local amount = math.floor(math.max(0, n or 100))
		SessionService.addGems(target, amount)
		return "+" .. amount .. " Gems"
	elseif action == "zerogems" then
		data.Gems = 0
		return "Gems auf 0"
	elseif action == "unlockall" then
		while #data.Shafts < Formulas.shaftCount() do
			table.insert(data.Shafts, DataTemplate.newStation("Shaft"))
		end
		MineService.ensureCycles(target)
		PlotService.refreshLevels(target)
		return "Alle Ebenen freigeschaltet"
	elseif action == "managers" then
		for _, key in Formulas.allStationKeys(data) do
			if not Formulas.managerFor(data, key) and #data.Managers < Config.Managers.MaxOwned then
				local area = Formulas.parseKey(key) or "Shaft"
				SessionService.addCash(target, Formulas.managerHireCost(data, area))
				ManagerService.hire(target, area)
			end
		end
		return "Manager überall"
	elseif action == "cooldowns" then
		for _, m in data.Managers do
			m.CooldownUntil = 0
			m.ActiveUntil = 0
		end
		data.LockCooldownUntil = 0
		target.LockedUntil = 0
		target.LastStealAt = 0
		target.JoinTime = 0
		return "Cooldowns zurückgesetzt"
	elseif action == "daily" then
		data.LastDailyClaim = 0
		return "Tägliche Belohnung wieder verfügbar"
	elseif action == "offline" then
		OfflineService.simulate(target, n or 7200)
		return "Offline-Einnahmen simuliert"
	elseif action == "powergive" or action == "powertake" then
		if not validPower(value) then
			return nil
		end
		if action == "powergive" then
			data.Powers[value] = true
		else
			data.Powers[value] = nil
		end
		syncTools(target)
		return (if action == "powergive" then "Kraft erhalten: " else "Kraft entfernt: ") .. value
	elseif action == "petgive" then
		local def = Formulas.petDef(value)
		if not def then
			return nil
		end
		local amount = math.clamp(math.floor(n or 1), 1, 10)
		local given = 0
		for _ = 1, amount do
			if PetService.add(target, value, true) then
				given += 1
			end
		end
		PetService.refresh(target)
		if given == 0 then
			return "Pet-Inventar ist voll"
		end
		return string.format("Pet erhalten: %s %s", def.Icon, def.Name)
	elseif action == "pettake" then
		local def = Formulas.petDef(value)
		if not def then
			return nil
		end
		-- zuerst ein nicht ausgerüstetes Exemplar nehmen
		local victim: string? = nil
		for _, pet in data.Pets do
			if pet.Pet == value and (victim == nil or not pet.Equipped) then
				victim = pet.Id
			end
		end
		if not victim then
			return "Hat dieses Pet nicht"
		end
		PetService.remove(target, victim)
		PetService.refresh(target)
		return string.format("Pet entfernt: %s %s", def.Icon, def.Name)
	elseif action == "tickets" then
		local amount = math.clamp(math.floor(n or 5), 1, Config.Trading.MaxTickets)
		data.TradeTickets = math.min(Config.Trading.MaxTickets, data.TradeTickets + amount)
		return "+" .. amount .. " Trading-Tickets"
	elseif action == "petslots" then
		data.PetSlotsBought = #Config.Pets.CashSlotCosts
		data.PetSlotsRobux = Config.Pets.RobuxSlots
		PetService.refresh(target)
		return "Alle Pet-Slots freigeschaltet"
	elseif action == "event" then
		EventService.trigger(if value ~= "" then value else nil)
		return "Event gestartet"
	elseif action == "kick" then
		task.defer(function()
			target.Player:Kick("Du wurdest von einem Admin gekickt.")
		end)
		return "gekickt"
	elseif action == "reset" then
		local fresh = DataTemplate.new()
		fresh.Powers = data.Powers -- Kräfte bleiben (eigene Admin-Aktion)
		for k, v in fresh :: any do
			(data :: any)[k] = v
		end
		MineService.resetCycles(target)
		PlotService.refreshLevels(target)
		PetService.refresh(target)
		return "Spielstand zurückgesetzt"
	end
	return nil
end

function AdminService.action(actor: Session, action: string, targetUserId: number?, value: string): (boolean, string?)
	local def = ACTIONS[action]
	if not def then
		return false, "Unbekannte Admin-Aktion"
	end
	local player = actor.Player
	if not AdminService.can(player, def.Perm) then
		return false, "Dafür hast du keine Berechtigung"
	end
	local target = actor
	if not def.Global and targetUserId and targetUserId ~= player.UserId then
		local targetPlayer = Players:GetPlayerByUserId(targetUserId)
		local targetSession = if targetPlayer then SessionService.get(targetPlayer) else nil
		if not targetSession then
			return false, "Spieler nicht gefunden"
		end
		target = targetSession
	end
	-- Der Owner ist geschützt: Admins können ihm nichts wegnehmen
	if
		def.Negative
		and target.Player ~= player
		and AdminService.isRealOwner(target.Player)
		and not AdminService.isRealOwner(player)
	then
		return false, "Der Owner ist geschützt 👑"
	end
	local result = apply(target, action, value)
	if not result then
		return false, "Ungültiger Wert"
	end
	SessionService.shaftsChanged(target)
	SessionService.managersChanged(target)
	PlotService.updateVisuals(target)
	print(string.format("[Admin] %s -> %s: %s (%s)", player.Name, target.Player.Name, action, value))
	if target.Player ~= player and action ~= "kick" then
		SessionService.notify(target.Player, string.format("👑 Admin %s: %s", player.DisplayName, result), "gold")
	end
	SessionService.notify(
		player,
		"🛠 " .. result .. (if target.Player ~= player then " → " .. target.Player.DisplayName else ""),
		"success"
	)
	return true, nil
end

----------------------------------------------------------------------
-- Admins verwalten (nur Owner)
----------------------------------------------------------------------
function AdminService.setAdmin(actor: Session, userId: number, name: string?, on: boolean): (boolean, string?)
	if not AdminService.isOwner(actor.Player) then
		return false, "Nur der Owner kann Admins vergeben"
	end
	local targetPlayer = Players:GetPlayerByUserId(userId)
	if targetPlayer and AdminService.isRealOwner(targetPlayer) then
		return false, "Der Owner ist immer Admin 👑"
	end
	if ownerUserId ~= 0 and userId == ownerUserId then
		return false, "Der Owner ist immer Admin 👑"
	end
	if on then
		if not admins[userId] then
			local perms: { [string]: boolean } = {}
			for _, p in CFG.Permissions do
				if p.Default then
					perms[p.Id] = true
				end
			end
			admins[userId] = {
				Name = if targetPlayer then targetPlayer.Name else string.sub(name or tostring(userId), 1, 32),
				Permissions = perms,
			}
		end
	else
		admins[userId] = nil
	end
	saveAdmins()
	refreshAll()
	if targetPlayer then
		SessionService.notify(
			targetPlayer,
			if on then "👑 Du bist jetzt Admin! Öffne das 🛠 Admin-Menü." else "Du bist kein Admin mehr.",
			"gold"
		)
	end
	return true, nil
end

function AdminService.setPermission(actor: Session, userId: number, perm: string, on: boolean): (boolean, string?)
	if not AdminService.isOwner(actor.Player) then
		return false, "Nur der Owner kann Rechte vergeben"
	end
	local record = admins[userId]
	if not record then
		return false, "Dieser Spieler ist kein Admin"
	end
	if not validPermission(perm) then
		return false, "Unbekanntes Recht"
	end
	if on then
		record.Permissions[perm] = true
	else
		record.Permissions[perm] = nil
	end
	saveAdmins()
	refreshAll()
	return true, nil
end

--- Infos über einen Spieler für das Admin-Menü
local function petCounts(session: Session): { [string]: number }
	local counts: { [string]: number } = {}
	for _, pet in session.Data.Pets do
		counts[pet.Pet] = (counts[pet.Pet] or 0) + 1
	end
	return counts
end

function AdminService.info(actor: Session, userId: number): (boolean, string?, any?)
	if not AdminService.isAdmin(actor.Player) then
		return false, "Kein Admin"
	end
	local targetPlayer = Players:GetPlayerByUserId(userId)
	local target = if targetPlayer then SessionService.get(targetPlayer) else nil
	if not target or not targetPlayer then
		return false, "Spieler nicht gefunden"
	end
	return true,
		nil,
		{
			Name = targetPlayer.DisplayName,
			Cash = target.Data.Cash,
			Gems = target.Data.Gems,
			Rebirths = target.Data.Rebirths,
			Shafts = #target.Data.Shafts,
			Powers = target.Data.Powers,
			PetCounts = petCounts(target),
			Tickets = target.Data.TradeTickets,
			IsOwner = AdminService.isRealOwner(targetPlayer),
			IsAdmin = AdminService.isAdmin(targetPlayer),
		}
end

----------------------------------------------------------------------
-- Start
----------------------------------------------------------------------
function AdminService.start()
	-- Der echte Owner kann vom Admin-Hammer nicht eingefroren werden
	CombatService.isProtected = function(player: Player): boolean
		return AdminService.isRealOwner(player)
	end
	CombatService.onSpeedChanged = function(player: Player)
		local session = SessionService.get(player)
		if session then
			applyPowers(session)
		end
	end
	-- Owner-ID über den Namen ermitteln (falls nicht in der Config eingetragen)
	if ownerUserId == 0 then
		task.spawn(function()
			local ok, id = pcall(function()
				return Players:GetUserIdFromNameAsync(CFG.OwnerName)
			end)
			if ok and type(id) == "number" then
				ownerUserId = id
				print("[AdminService] Owner", CFG.OwnerName, "hat die UserId", id)
				refreshAll()
			end
		end)
	end

	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(CFG.StoreName)
	end)
	if ok then
		store = result
		task.spawn(loadAdmins)
		-- regelmäßig neu laden (Änderungen aus anderen Servern)
		task.spawn(function()
			while true do
				task.wait(120)
				loadAdmins()
			end
		end)
	end

	SessionService.onStart(15, function(session)
		refreshInfo(session)
		local function watchCharacter(character: Model)
			character:WaitForChild("Humanoid", 10)
			-- Item ausgerüstet / abgelegt -> Kräfte an/aus
			-- (Connections am Charakter enden automatisch, wenn er entfernt wird)
			character.ChildAdded:Connect(function(child)
				if child:IsA("Tool") and child:GetAttribute("PowerTool") then
					applyPowers(session)
				end
			end)
			character.ChildRemoved:Connect(function(child)
				if child:IsA("Tool") and child:GetAttribute("PowerTool") then
					applyPowers(session)
				end
			end)
			task.wait(0.5) -- Backpack wird beim Spawnen neu aufgebaut
			syncTools(session)
		end
		session.Maid:Give(session.Player.CharacterAdded:Connect(watchCharacter))
		if session.Player.Character then
			task.spawn(watchCharacter, session.Player.Character)
		end
	end)

	NetService.register(
		"AdminAction",
		{ Action = "string", Target = "integer?", Value = "string?" },
		function(session, payload)
			return AdminService.action(session, payload.Action, payload.Target, payload.Value or "")
		end
	)
	NetService.register("AdminInfo", { Target = "integer" }, function(session, payload)
		return AdminService.info(session, payload.Target)
	end)
	NetService.register(
		"AdminSetAdmin",
		{ UserId = "integer", Name = "string?", On = "boolean" },
		function(session, payload)
			return AdminService.setAdmin(session, payload.UserId, payload.Name, payload.On)
		end
	)
	NetService.register(
		"AdminSetPerm",
		{ UserId = "integer", Perm = "string", On = "boolean" },
		function(session, payload)
			return AdminService.setPermission(session, payload.UserId, payload.Perm, payload.On)
		end
	)
	NetService.register("ToggleCarpet", {}, function(session)
		if not Formulas.hasPower(session.Data, "Carpet") then
			return false, "Du hast keinen fliegenden Teppich"
		end
		return false, "Rüste den 🧞 Teppich in deinem Inventar aus!"
	end)

	-- Chat-Befehle für Admins (z. B. "/cash 1e9", "/gems 100")
	local function hook(player: Player)
		player.Chatted:Connect(function(message)
			local session = SessionService.get(player)
			local cmd, arg = string.match(message, "^/(%a+)%s*(%S*)")
			if session and cmd and ACTIONS[cmd] then
				local success, msg = AdminService.action(session, cmd, nil, arg or "")
				if not success and msg then
					SessionService.notify(player, msg, "warn")
				end
			end
		end)
	end
	Players.PlayerAdded:Connect(hook)
	for _, p in Players:GetPlayers() do
		hook(p)
	end
end

return AdminService

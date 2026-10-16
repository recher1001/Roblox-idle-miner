--!strict
--[[
	PlotService
	===========
	Verteilt die Plots (eigene Mine pro Spieler), baut die Mine, verbindet
	Klicks/Prompts und aktualisiert die sichtbaren Infos (Schilder, Füllstände,
	Manager-Figuren, Kumpel-Anzahl, Schutzkuppel).

	Zyklus-Zeiten werden als Attribute an die Stations-Models geschrieben
	(CycleStart, CycleEnd, CycleId, Running). Die Clients animieren daraus
	Aufzug, Kumpel und Wagen - auch für fremde Plots.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local BigNum = require(Shared.BigNum)
local Clock = require(Shared.Clock)
local Config = require(Shared.Config)
local Formulas = require(Shared.Formulas)
local Maid = require(Shared.Maid)
local Types = require(Shared.Types)

local AvatarService = require(script.Parent.AvatarService)
local SessionService = require(script.Parent.SessionService)
local MineBuilder = require(script.Parent.Parent.World.MineBuilder)
local WorldSetup = require(script.Parent.Parent.World.WorldSetup)

type Session = SessionService.Session

export type PlotInfo = {
	Index: number,
	Model: Model,
	Origin: CFrame,
	Owner: Player?,
	Maid: Maid.Maid,
}

local PlotService = {}

local plots: { PlotInfo } = {}
local plotsFolder: Folder? = nil

-- Callbacks (werden von anderen Services gesetzt, vermeidet zyklische requires)
local stationClickHandler: ((Session, string) -> ())? = nil
local depotPromptHandler: ((Player, Session, string) -> ())? = nil
local managerPromptHandler: ((Player, Session, string, string) -> ())? = nil
local lockPromptHandler: ((Player, Session) -> ())? = nil

--- Manager klauen: (Dieb, Opfer, StationKey, phase "begin"/"trigger")
function PlotService.setManagerPromptHandler(fn: (Player, Session, string, string) -> ())
	managerPromptHandler = fn
end

--- Schutz-Knopf in der Basis gedrückt
function PlotService.setLockPromptHandler(fn: (Player, Session) -> ())
	lockPromptHandler = fn
end

function PlotService.setStationClickHandler(fn: (Session, string) -> ())
	stationClickHandler = fn
end

--- phase = "begin" (Halten gestartet) oder "trigger" (Halten beendet)
function PlotService.setDepotPromptHandler(fn: (Player, Session, string) -> ())
	depotPromptHandler = fn
end

----------------------------------------------------------------------
-- Zugriff
----------------------------------------------------------------------
function PlotService.getPlot(session: Session): PlotInfo?
	return plots[session.PlotIndex]
end

function PlotService.getStation(session: Session, key: string): Model?
	local plot = plots[session.PlotIndex]
	if not plot then
		return nil
	end
	local mine = plot.Model:FindFirstChild("Mine")
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

--- Weltposition des Aufzugslagers eines Spielers
function PlotService.getDepotPosition(session: Session): Vector3?
	local plot = plots[session.PlotIndex]
	if not plot then
		return nil
	end
	return (plot.Origin * CFrame.new(MineBuilder.Layout.DepotPos)).Position
end

--- Index des Plots, auf dem eine Weltposition liegt (oder nil)
function PlotService.plotIndexAt(position: Vector3): number?
	local L = MineBuilder.Layout
	for _, plot in plots do
		local localPos = plot.Origin:PointToObjectSpace(position)
		if
			math.abs(localPos.X) <= L.PlotHalf
			and localPos.Z >= L.PlotBack
			and localPos.Z <= L.PlotFront
			and localPos.Y > -200
			and localPos.Y < 60
		then
			return plot.Index
		end
	end
	return nil
end

--- Steht die Position oben in der eigenen Basis (nicht in der Grube)?
function PlotService.isOnSurfaceOf(session: Session, position: Vector3): boolean
	local plot = plots[session.PlotIndex]
	if not plot or PlotService.plotIndexAt(position) ~= plot.Index then
		return false
	end
	return plot.Origin:PointToObjectSpace(position).Y > -6
end

--- Punkt knapp vor der Basis (zum Hinausschieben von Eindringlingen)
function PlotService.outsideCFrame(index: number, position: Vector3): CFrame?
	local plot = plots[index]
	if not plot then
		return nil
	end
	local localPos = plot.Origin:PointToObjectSpace(position)
	local x = math.clamp(localPos.X, -MineBuilder.Layout.PlotHalf + 4, MineBuilder.Layout.PlotHalf - 4)
	return plot.Origin * CFrame.new(x, 4, MineBuilder.Layout.PlotFront + 6)
end

function PlotService.getSpawnCFrame(session: Session): CFrame?
	local plot = plots[session.PlotIndex]
	if not plot then
		return nil
	end
	return plot.Origin * CFrame.new(MineBuilder.Layout.SpawnPos + Vector3.new(0, 4, 0))
end

----------------------------------------------------------------------
-- Zyklus-Attribute für Client-Animationen
----------------------------------------------------------------------
function PlotService.setCycle(session: Session, key: string, cycle: Types.CycleState)
	local station = PlotService.getStation(session, key)
	if not station then
		return
	end
	station:SetAttribute("CycleStart", cycle.Start)
	station:SetAttribute("CycleEnd", cycle.End)
	station:SetAttribute("CycleId", cycle.Id)
	station:SetAttribute("Running", cycle.Running)
end

----------------------------------------------------------------------
-- Klicks & Prompts
----------------------------------------------------------------------
local function connectStation(session: Session, plot: PlotInfo, station: Model)
	local key = station:GetAttribute("Key")
	if type(key) ~= "string" then
		return
	end
	local hitbox = station:FindFirstChild("Hitbox")
	if not hitbox or not hitbox:IsA("BasePart") or hitbox:FindFirstChildOfClass("ClickDetector") then
		return
	end
	local click = Instance.new("ClickDetector")
	click.MaxActivationDistance = 2000
	click.Parent = hitbox
	plot.Maid:Give(click.MouseClick:Connect(function(clicker: Player)
		-- Nur der Besitzer darf seine Stationen bedienen
		if clicker ~= session.Player or session.Ending then
			return
		end
		if stationClickHandler then
			stationClickHandler(session, key)
		end
	end))
end

local function connectDepotPrompt(session: Session, plot: PlotInfo)
	local mine = plot.Model:FindFirstChild("Mine")
	local prompt = mine and mine:FindFirstChild("StealPrompt", true)
	if not prompt or not prompt:IsA("ProximityPrompt") then
		return
	end
	plot.Maid:Give(prompt.PromptButtonHoldBegan:Connect(function(thief: Player)
		if depotPromptHandler and not session.Ending then
			depotPromptHandler(thief, session, "begin")
		end
	end))
	plot.Maid:Give(prompt.Triggered:Connect(function(thief: Player)
		if depotPromptHandler and not session.Ending then
			depotPromptHandler(thief, session, "trigger")
		end
	end))
end

local function connectLockPrompt(session: Session, plot: PlotInfo)
	local base = plot.Model:FindFirstChild("Base")
	local prompt = base and base:FindFirstChild("LockPrompt", true)
	if not prompt or not prompt:IsA("ProximityPrompt") then
		return
	end
	prompt:SetAttribute("OwnerOnly", session.Player.UserId)
	plot.Maid:Give(prompt.Triggered:Connect(function(player: Player)
		if lockPromptHandler and not session.Ending then
			lockPromptHandler(player, session)
		end
	end))
end

local function connectAllStations(session: Session, plot: PlotInfo)
	local mine = plot.Model:FindFirstChild("Mine")
	if not mine then
		return
	end
	for _, child in mine:GetChildren() do
		if child:IsA("Model") and child:GetAttribute("Key") then
			connectStation(session, plot, child)
		end
	end
end

----------------------------------------------------------------------
-- Zuweisung
----------------------------------------------------------------------
local function setSign(plot: PlotInfo, text: string)
	local sign = plot.Model:FindFirstChild("Sign", true)
	local label = sign and sign:FindFirstChild("Owner", true)
	if label and label:IsA("TextLabel") then
		label.Text = text
	end
end

local function teleportToPlot(session: Session, character: Model)
	local cf = PlotService.getSpawnCFrame(session)
	if not cf then
		return
	end
	-- kurz warten, bis der Charakter vollständig aufgebaut ist
	task.defer(function()
		local root = character:WaitForChild("HumanoidRootPart", 5)
		if root and character.Parent then
			character:PivotTo(cf)
		end
	end)
end

local function assign(session: Session)
	local plot: PlotInfo? = nil
	for _, p in plots do
		if p.Owner == nil then
			plot = p
			break
		end
	end
	if not plot then
		session.Player:Kick("Dieser Server ist voll. Bitte tritt einem anderen Server bei.")
		return
	end
	plot.Owner = session.Player
	session.PlotIndex = plot.Index
	plot.Model:SetAttribute("OwnerUserId", session.Player.UserId)
	plot.Model:SetAttribute("OwnerName", session.Player.DisplayName)
	setSign(plot, "⛏ Mine von " .. session.Player.DisplayName)

	MineBuilder.buildMine(plot.Model, plot.Origin, #session.Data.Shafts, SessionService.currentSection(session))
	connectAllStations(session, plot)
	connectDepotPrompt(session, plot)
	connectLockPrompt(session, plot)

	local player = session.Player
	session.Maid:Give(player.CharacterAdded:Connect(function(character)
		teleportToPlot(session, character)
	end))
	if player.Character then
		teleportToPlot(session, player.Character)
	end
	PlotService.updateVisuals(session)
end

local function release(session: Session)
	local plot = plots[session.PlotIndex]
	if not plot or plot.Owner ~= session.Player then
		return
	end
	plot.Maid:Clean()
	MineBuilder.clearMine(plot.Model)
	plot.Owner = nil
	plot.Model:SetAttribute("OwnerUserId", 0)
	plot.Model:SetAttribute("OwnerName", "")
	setSign(plot, "Freie Mine")
end

--- Nach Freischalten / Rebirth: Ebenen neu abgleichen
function PlotService.refreshLevels(session: Session)
	local plot = plots[session.PlotIndex]
	if not plot then
		return
	end
	MineBuilder.syncLevels(plot.Model, plot.Origin, #session.Data.Shafts, SessionService.currentSection(session))
	connectAllStations(session, plot)
	-- laufende Zyklen auf die (neu gebauten) Stationen übertragen
	for key, cycle in session.Cycles do
		PlotService.setCycle(session, key, cycle)
	end
	PlotService.updateVisuals(session)
	session.Dirty = true
end

--- Anderen Abschnitt der Grube anzeigen (0 = automatisch der tiefste)
function PlotService.setSection(session: Session, section: number)
	local maxSection = Formulas.sectionOf(math.max(#session.Data.Shafts, 1))
	session.ViewSection = if section <= 0 then 0 else math.clamp(section, 1, maxSection)
	PlotService.refreshLevels(session)
end

----------------------------------------------------------------------
-- Sichtbare Infos aktualisieren
----------------------------------------------------------------------
local function setInfo(station: Instance, guiName: string, title: string, sub: string)
	local gui = station:FindFirstChild(guiName, true)
	if not gui then
		return
	end
	local title_ = gui:FindFirstChild("Title", true)
	local sub_ = gui:FindFirstChild("Sub", true)
	if title_ and title_:IsA("TextLabel") and title_.Text ~= title then
		title_.Text = title
	end
	if sub_ and sub_:IsA("TextLabel") and sub_.Text ~= sub then
		sub_.Text = sub
	end
end

--- Halte-Dauer zum Klauen: tiefere Ebenen dauern länger
local function stealHoldDuration(key: string): number
	local cfg = Config.ManagerSteal
	local area, index = Formulas.parseKey(key)
	local depth = if area == "Shaft" and index then index - 1 else 0
	return math.min(cfg.HoldMax, cfg.HoldBase + cfg.HoldPerLevel * depth)
end

--- Prompt "Manager klauen" an der Station (nur wenn ein Manager dort steht)
local function stealSpot(session: Session, station: Model, key: string, manager: Types.ManagerData?)
	local existing = station:FindFirstChild("StealSpot")
	if not manager or not Config.ManagerSteal.Enabled then
		if existing then
			existing:Destroy()
		end
		return
	end
	if existing then
		local prompt = existing:FindFirstChildOfClass("ProximityPrompt")
		if prompt then
			prompt.ObjectText = string.format("%s (%s)", manager.Name, Formulas.rarityDef(manager.Rarity).Name)
		end
		return
	end
	local spot = station:GetAttribute("ManagerSpot")
	if typeof(spot) ~= "CFrame" then
		return
	end
	local part = Instance.new("Part")
	part.Name = "StealSpot"
	part.Size = Vector3.new(2, 2, 2)
	part.CFrame = spot * CFrame.new(0, 3, 0)
	part.Transparency = 1
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Parent = station
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Manager klauen 👔"
	prompt.ObjectText = string.format("%s (%s)", manager.Name, Formulas.rarityDef(manager.Rarity).Name)
	prompt.HoldDuration = stealHoldDuration(key)
	prompt.MaxActivationDistance = Config.ManagerSteal.MaxActivationDistance
	prompt.RequiresLineOfSight = false
	prompt.KeyboardKeyCode = Enum.KeyCode.F
	prompt:SetAttribute("StealOwner", session.Player.UserId)
	prompt.Parent = part
	prompt.PromptButtonHoldBegan:Connect(function(thief: Player)
		if managerPromptHandler and not session.Ending then
			managerPromptHandler(thief, session, key, "begin")
		end
	end)
	prompt.Triggered:Connect(function(thief: Player)
		if managerPromptHandler and not session.Ending then
			managerPromptHandler(thief, session, key, "trigger")
		end
	end)
end

local function managerVisual(session: Session, station: Model, key: string, now: number)
	local manager = Formulas.managerFor(session.Data, key)
	stealSpot(session, station, key, manager)
	local color = if manager then Formulas.rarityDef(manager.Rarity).Color else nil
	local signature = if manager
		then string.format("%s:%s:%d", manager.Id, manager.Rarity, manager.FriendUserId or 0)
		else ""
	local created = MineBuilder.setManagerFigure(station, color, Formulas.isAbilityActive(manager, now), signature)
	if created and manager and manager.FriendUserId and color then
		AvatarService.dress(created, manager.FriendUserId, color, false)
	end
	station:SetAttribute("HasManager", manager ~= nil)
end

local function minerCount(station: Types.StationData): number
	local total = 0
	for _, l in station.Levels do
		total += l
	end
	return math.clamp(1 + math.floor((total - 3) / 25), 1, 5)
end

function PlotService.updateVisuals(session: Session)
	local plot = plots[session.PlotIndex]
	if not plot then
		return
	end
	local data = session.Data
	local now = Clock.now()
	local symbol = Config.CurrencySymbol

	-- nur die Ebenen des angezeigten Abschnitts haben ein Model
	local size = Config.ShaftGen.SectionSize
	local first = (SessionService.currentSection(session) - 1) * size + 1
	for i = first, math.min(first + size - 1, #data.Shafts) do
		local key = Formulas.shaftKey(i)
		local station = PlotService.getStation(session, key)
		if station then
			local def = Formulas.shaftDef(i)
			local stock = data.Shafts[i].Stock
			local cap = Formulas.shaftCapacity(data, i)
			local full = BigNum.gte(stock, cap)
			setInfo(
				station,
				"Info",
				string.format("Ebene %d • %s  Lv %d", i, def.Ore, Formulas.level(data.Shafts[i], "Value")),
				string.format(
					"📦 %s / %s%s",
					BigNum.format(stock),
					BigNum.format(cap),
					if full then "  VOLL!" else ""
				)
			)
			local crate = station:FindFirstChild("Crate")
			if crate and crate:IsA("Model") then
				local ratio = if BigNum.isZero(cap) then 0 else BigNum.toNumber(BigNum.div(stock, cap))
				MineBuilder.setCrateFill(crate, ratio, def.OreColor)
			end
			local count = minerCount(data.Shafts[i])
			local ids = AvatarService.minerIds(session, i, count)
			local signature = tostring(count) .. ":" .. table.concat(ids, ",")
			local created = MineBuilder.setMinerCount(station, plot.Origin, i, count, signature)
			if created then
				for n, figure in created do
					if ids[n] then
						AvatarService.dress(figure, ids[n], Config.Avatars.MinerHatColor, true)
					end
				end
			end
			managerVisual(session, station, key, now)
			station:SetAttribute("Full", full)
		end
	end

	local ctx = SessionService.context(session)
	local elevator = PlotService.getStation(session, "Elevator")
	if elevator then
		setInfo(
			elevator,
			"Info",
			string.format("Aufzug  Lv %d", Formulas.level(data.Elevator, "Capacity")),
			"Ladung " .. BigNum.format(Formulas.elevatorLoad(data, ctx))
		)
		local stock = data.Elevator.Stock
		local locked = session.LockedUntil > now
		local protected = session.JoinTime + Config.Steal.NewPlayerProtection > now
			or Formulas.isBoostActive(data, "Shield", now)
			or Formulas.hasPower(data, "Shield")
		setInfo(
			elevator,
			"DepotInfo",
			if locked then "🔒 Abgeschlossen" elseif protected then "🛡️ Aufzugslager" else "💰 Aufzugslager",
			BigNum.formatMoney(stock, symbol)
		)
		local depot = elevator:FindFirstChild("Depot")
		if depot and depot:IsA("Model") then
			local load = Formulas.elevatorLoad(data, ctx)
			local ratio = BigNum.toNumber(BigNum.div(stock, BigNum.mulNum(load, 4)))
			MineBuilder.setCrateFill(depot, ratio, MineBuilder.Colors.Gold)
			local prompt = depot:FindFirstChild("StealPrompt", true)
			if prompt and prompt:IsA("ProximityPrompt") then
				prompt:SetAttribute("StealOwner", session.Player.UserId)
				prompt.Enabled = Config.Steal.Enabled and not locked
				prompt.ObjectText = if protected
					then "🛡️ Geschützt"
					else "Aufzugslager von " .. session.Player.DisplayName
			end
		end
		local base = plot.Model:FindFirstChild("Base")
		local barrier = base and base:FindFirstChild("LockBarrier")
		if barrier then
			for _, wall in barrier:GetChildren() do
				if wall:IsA("BasePart") then
					wall.Transparency = if locked then 0.55 else 1
				end
			end
		end
		local dome = elevator:FindFirstChild("LockDome")
		if dome and dome:IsA("BasePart") then
			dome.Transparency = if locked then 0.2 else 1
			dome.CanCollide = locked
		end
		managerVisual(session, elevator, "Elevator", now)
	end

	local warehouse = PlotService.getStation(session, "Warehouse")
	if warehouse then
		setInfo(
			warehouse,
			"Info",
			string.format("Händler  x%.2f", Formulas.sellPriceMultiplier(data)),
			"Transport " .. BigNum.format(Formulas.warehouseLoad(data, ctx))
		)
		managerVisual(session, warehouse, "Warehouse", now)
	end
end

----------------------------------------------------------------------
-- Start
----------------------------------------------------------------------
function PlotService.start()
	local existing = workspace:FindFirstChild("Plots")
	if existing then
		existing:Destroy()
	end
	local f = Instance.new("Folder")
	f.Name = "Plots"
	f.Parent = workspace
	plotsFolder = f

	local count = Config.World.MaxPlots
	local centers: { Vector3 } = {}
	for i = 1, count do
		local x = (i - (count + 1) / 2) * Config.World.PlotSpacing
		local origin = CFrame.new(x, 0, 0)
		local m = Instance.new("Model")
		m.Name = "Plot_" .. i
		m:SetAttribute("Index", i)
		m:SetAttribute("OwnerUserId", 0)
		m:SetAttribute("OwnerName", "")
		m:SetAttribute("Origin", origin)
		MineBuilder.buildBase(m, origin)
		m.Parent = f
		table.insert(plots, { Index = i, Model = m, Origin = origin, Owner = nil, Maid = Maid.new() })
		table.insert(centers, origin.Position)
	end
	WorldSetup.buildWorld(centers)

	if Players.MaxPlayers > count then
		warn(
			string.format(
				"[PlotService] Players.MaxPlayers (%d) ist größer als die Anzahl Plots (%d). Stelle Max Players in den Game Settings auf %d.",
				Players.MaxPlayers,
				count,
				count
			)
		)
	end

	SessionService.onStart(10, assign)
	SessionService.onEnd(90, release)
end

function PlotService.getPlotsFolder(): Folder?
	return plotsFolder
end

return PlotService

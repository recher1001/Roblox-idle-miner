--!strict
--[[
	CombatService
	=============
	Kampf-Items und Stehl-Gadgets (Steal-a-Brainrot-Stil), alles serverseitig:

	  Waffen (Config.Combat.Items): Schläger gratis beim Spawnen, Slaps im Shop.
	    Treffer = Rückstoß (beim Getroffenen per Effekt), optional Einfrieren.
	    Wer getroffen wird, verliert einen gerade geklauten Manager.
	  Gadgets (Config.Gadgets): erst ab X Rebirths kaufbar.
	    🧥 Unsichtbar, 👟 Tempo, 🕸️ Netz (Fern-Einfrieren), 🔓 Laser-Brecher
	  Admin-Hammer: friert alle Gegner im großen Umkreis ein (Owner geschützt).

	Treffer werden auf dem Server gesucht (Reichweite + Blickrichtung), der
	Client meldet nur, dass er geklickt hat (Tool.Activated).
]]

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local BigNum = require(Shared.BigNum)
local Clock = require(Shared.Clock)
local Config = require(Shared.Config)
local Formulas = require(Shared.Formulas)

local NetService = require(script.Parent.NetService)
local SessionService = require(script.Parent.SessionService)
local StealService = require(script.Parent.StealService)

type Session = SessionService.Session

local CombatService = {}

-- Vom AdminService gesetzt (vermeidet zyklische requires)
CombatService.isProtected = function(_player: Player): boolean
	return false
end
CombatService.onSpeedChanged = function(_player: Player) end

local cooldowns: { [Player]: { [string]: number } } = {}
local cooldownNotified: { [Player]: number } = {}
local invisibleToken: { [Player]: number } = {}

----------------------------------------------------------------------
-- Hilfen
----------------------------------------------------------------------
local function rootOf(player: Player): BasePart?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

local function alive(player: Player): boolean
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	return humanoid ~= nil and humanoid.Health > 0
end

local function isFrozen(player: Player): boolean
	local root = rootOf(player)
	return root ~= nil and root.Anchored
end

local function playSound(parent: Instance, soundId: string, speed: number?)
	local sound = Instance.new("Sound")
	sound.SoundId = soundId
	sound.Volume = 0.8
	sound.PlaybackSpeed = speed or 1
	sound.RollOffMaxDistance = 120
	sound.Parent = parent
	sound:Play()
	Debris:AddItem(sound, 4)
end

--- Prüft + setzt die Abklingzeit. false = noch nicht bereit.
local function useCooldown(player: Player, id: string, seconds: number): boolean
	local now = Clock.now()
	local list = cooldowns[player]
	if not list then
		list = {}
		cooldowns[player] = list
	end
	local readyAt = list[id] or 0
	if readyAt > now then
		if (cooldownNotified[player] or 0) + 1 < now then
			cooldownNotified[player] = now
			SessionService.notify(player, string.format("⏳ Noch %.1fs", readyAt - now), "info")
		end
		return false
	end
	list[id] = now + seconds
	return true
end

--- Nächster lebender Gegner vor dem Spieler (Reichweite + Blickkegel)
local function findTarget(attacker: Player, range: number, minDot: number): Player?
	local root = rootOf(attacker)
	if not root then
		return nil
	end
	local look = Vector3.new(root.CFrame.LookVector.X, 0, root.CFrame.LookVector.Z)
	look = if look.Magnitude > 0.01 then look.Unit else Vector3.new(0, 0, -1)
	local best: Player? = nil
	local bestDist = math.huge
	for _, other in Players:GetPlayers() do
		local otherRoot = rootOf(other)
		if other ~= attacker and otherRoot and alive(other) then
			local offset = otherRoot.Position - root.Position
			local dist = offset.Magnitude
			if dist <= range and dist < bestDist then
				local flat = Vector3.new(offset.X, 0, offset.Z)
				local dot = if flat.Magnitude > 0.5 then flat.Unit:Dot(look) else 1
				if dot >= minDot then
					best = other
					bestDist = dist
				end
			end
		end
	end
	return best
end

----------------------------------------------------------------------
-- Einfrieren
----------------------------------------------------------------------
function CombatService.freeze(player: Player, seconds: number)
	local character = player.Character
	local root = rootOf(player)
	if not character or not root or seconds <= 0 then
		return
	end
	StealService.dropCarried(player, "eingefroren")
	local untilTime = Clock.now() + seconds
	local current = character:GetAttribute("FrozenUntil")
	if type(current) == "number" and current > untilTime then
		untilTime = current
	end
	character:SetAttribute("FrozenUntil", untilTime)
	root.Anchored = true
	if not character:FindFirstChild("IceBlock") then
		local ice = Instance.new("Part")
		ice.Name = "IceBlock"
		ice.Size = Vector3.new(5, 7, 5)
		ice.CFrame = root.CFrame * CFrame.new(0, -0.4, 0)
		ice.Color = Color3.fromRGB(150, 225, 255)
		ice.Material = Enum.Material.Ice
		ice.Transparency = 0.35
		ice.Anchored = true
		ice.CanCollide = false
		ice.CanQuery = false
		ice.CanTouch = false
		ice.Parent = character
	end
	SessionService.effect(player, "Frozen", { Seconds = seconds })
	task.delay(seconds + 0.05, function()
		local now = Clock.now()
		local frozenUntil = character:GetAttribute("FrozenUntil")
		if character.Parent and (type(frozenUntil) ~= "number" or frozenUntil <= now) then
			root.Anchored = false
			character:SetAttribute("FrozenUntil", nil)
			local ice = character:FindFirstChild("IceBlock")
			if ice then
				ice:Destroy()
			end
		end
	end)
end

----------------------------------------------------------------------
-- Unsichtbarkeit (Mantel)
----------------------------------------------------------------------
local function setInvisible(player: Player, on: boolean)
	local character = player.Character
	if not character then
		return
	end
	local containers: { Instance } = { character }
	local backpack = player:FindFirstChild("Backpack")
	if backpack then
		table.insert(containers, backpack)
	end
	for _, container in containers do
		for _, d in container:GetDescendants() do
			if d:IsA("BasePart") and d.Name ~= "HumanoidRootPart" or d:IsA("Decal") then
				local v = d :: any
				if on then
					if d:GetAttribute("OrigT") == nil then
						d:SetAttribute("OrigT", v.Transparency)
					end
					v.Transparency = 1
				else
					local orig = d:GetAttribute("OrigT")
					if type(orig) == "number" then
						v.Transparency = orig
						d:SetAttribute("OrigT", nil)
					end
				end
			elseif d:IsA("BillboardGui") or d:IsA("Sparkles") or d:IsA("ParticleEmitter") then
				local v = d :: any
				if on then
					if d:GetAttribute("OrigEnabled") == nil then
						d:SetAttribute("OrigEnabled", v.Enabled)
					end
					v.Enabled = false
				else
					local orig = d:GetAttribute("OrigEnabled")
					if type(orig) == "boolean" then
						v.Enabled = orig
						d:SetAttribute("OrigEnabled", nil)
					end
				end
			end
		end
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.DisplayDistanceType = if on
			then Enum.HumanoidDisplayDistanceType.None
			else Enum.HumanoidDisplayDistanceType.Viewer
	end
	character:SetAttribute("Invisible", on)
end

local function endInvisible(player: Player)
	local character = player.Character
	if character and character:GetAttribute("Invisible") == true then
		invisibleToken[player] = (invisibleToken[player] or 0) + 1
		setInvisible(player, false)
	end
end

----------------------------------------------------------------------
-- Treffer
----------------------------------------------------------------------
local function hit(attacker: Player, target: Player, knockback: number, freeze: number)
	local attackerRoot = rootOf(attacker)
	local targetRoot = rootOf(target)
	if not attackerRoot or not targetRoot then
		return
	end
	StealService.dropCarried(target, "getroffen von " .. attacker.DisplayName)
	endInvisible(target)
	if knockback > 0 then
		local flat = targetRoot.Position - attackerRoot.Position
		flat = Vector3.new(flat.X, 0, flat.Z)
		local dir = if flat.Magnitude > 0.1 then flat.Unit else attackerRoot.CFrame.LookVector
		local velocity = dir * knockback + Vector3.new(0, knockback * 0.45 + 12, 0)
		SessionService.effect(target, "Knockback", { Velocity = velocity })
	end
	if freeze > 0 then
		CombatService.freeze(target, freeze)
	end
	playSound(targetRoot, Config.Sounds.Hit, 1 + math.random() * 0.2)
end

local function swing(player: Player, def: Config.CombatItemDef, tool: Tool)
	if not Config.Combat.Enabled or isFrozen(player) or not alive(player) then
		return
	end
	if not useCooldown(player, def.Id, def.Cooldown) then
		return
	end
	local anim = Instance.new("StringValue")
	anim.Name = "toolanim"
	anim.Value = "Slash"
	anim.Parent = tool
	Debris:AddItem(anim, 1)
	local handle = tool:FindFirstChild("Handle")
	playSound(handle or tool, Config.Sounds.Swing)
	endInvisible(player) -- angreifen macht sichtbar
	local target = findTarget(player, def.Range, 0.15)
	if target then
		hit(player, target, def.Knockback, def.Freeze)
	end
end

----------------------------------------------------------------------
-- Gadgets
----------------------------------------------------------------------
local function webLine(from: Vector3, to: Vector3)
	local part = Instance.new("Part")
	part.Name = "Web"
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Material = Enum.Material.Neon
	part.Color = Color3.new(1, 1, 1)
	part.Size = Vector3.new(0.3, 0.3, (to - from).Magnitude)
	part.CFrame = CFrame.lookAt((from + to) / 2, to)
	part.Parent = workspace
	TweenService:Create(part, TweenInfo.new(0.4), { Transparency = 1 }):Play()
	Debris:AddItem(part, 0.5)
end

local function useGadget(player: Player, def: Config.GadgetDef)
	local character = player.Character
	local root = rootOf(player)
	if not character or not root or isFrozen(player) or not alive(player) then
		return
	end
	if def.Id == "Web" then
		local target = findTarget(player, Config.GadgetSettings.WebRange, 0.6)
		if not target then
			SessionService.notify(player, "🕸️ Kein Gegner vor dir", "info")
			return
		end
		if not useCooldown(player, def.Id, def.Cooldown) then
			return
		end
		local targetRoot = rootOf(target)
		if targetRoot then
			webLine(root.Position, targetRoot.Position)
		end
		StealService.dropCarried(target, "im Netz gefangen")
		CombatService.freeze(target, def.Duration)
		playSound(root, Config.Sounds.Swing, 1.4)
		return
	end
	if not useCooldown(player, def.Id, def.Cooldown) then
		return
	end
	if def.Id == "Cloak" then
		local token = (invisibleToken[player] or 0) + 1
		invisibleToken[player] = token
		setInvisible(player, true)
		SessionService.notify(player, string.format("🧥 %ds unsichtbar!", def.Duration), "success")
		task.delay(def.Duration, function()
			if invisibleToken[player] == token then
				setInvisible(player, false)
			end
		end)
	elseif def.Id == "Boots" then
		character:SetAttribute("SpeedMult", Config.GadgetSettings.BootsMultiplier)
		CombatService.onSpeedChanged(player)
		SessionService.notify(player, "👟 Turbo!", "success")
		task.delay(def.Duration, function()
			if character.Parent then
				character:SetAttribute("SpeedMult", nil)
				CombatService.onSpeedChanged(player)
			end
		end)
	elseif def.Id == "LaserBreaker" then
		character:SetAttribute("LaserBreakUntil", Clock.now() + def.Duration)
		local sparkle = Instance.new("Sparkles")
		sparkle.SparkleColor = def.Color
		sparkle.Parent = root
		Debris:AddItem(sparkle, def.Duration)
		SessionService.notify(
			player,
			string.format("🔓 %ds lang kommst du durch Laserwände!", def.Duration),
			"success"
		)
	end
end

----------------------------------------------------------------------
-- Admin-Hammer
----------------------------------------------------------------------
local function shockwave(position: Vector3, radius: number)
	local ring = Instance.new("Part")
	ring.Name = "Shockwave"
	ring.Shape = Enum.PartType.Cylinder
	ring.Anchored = true
	ring.CanCollide = false
	ring.CanQuery = false
	ring.CanTouch = false
	ring.Material = Enum.Material.Neon
	ring.Color = Color3.fromRGB(120, 220, 255)
	ring.Transparency = 0.2
	ring.Size = Vector3.new(0.6, 2, 2)
	ring.CFrame = CFrame.new(position - Vector3.new(0, 2.6, 0)) * CFrame.Angles(0, 0, math.pi / 2)
	ring.Parent = workspace
	TweenService:Create(
		ring,
		TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Size = Vector3.new(0.6, radius * 2, radius * 2), Transparency = 1 }
	):Play()
	Debris:AddItem(ring, 0.7)
end

local function hammerSmash(player: Player, tool: Tool)
	local root = rootOf(player)
	if not root or not alive(player) then
		return
	end
	local session = SessionService.get(player)
	if not session or not Formulas.hasPower(session.Data, "Hammer") then
		return
	end
	if not useCooldown(player, "Hammer", Config.Admin.HammerCooldown) then
		return
	end
	local anim = Instance.new("StringValue")
	anim.Name = "toolanim"
	anim.Value = "Slash"
	anim.Parent = tool
	Debris:AddItem(anim, 1)
	shockwave(root.Position, Config.Admin.HammerRadius)
	playSound(root, Config.Sounds.Hit, 0.6)
	local frozen = 0
	for _, other in Players:GetPlayers() do
		local otherRoot = rootOf(other)
		if
			other ~= player
			and otherRoot
			and alive(other)
			and not CombatService.isProtected(other)
			and (otherRoot.Position - root.Position).Magnitude <= Config.Admin.HammerRadius
		then
			frozen += 1
			CombatService.freeze(other, Config.Admin.HammerFreeze)
			SessionService.notify(other, "🔨 " .. player.DisplayName .. " hat dich eingefroren!", "warn")
		end
	end
	SessionService.notify(player, string.format("🔨 %d Gegner eingefroren!", frozen), "success")
end

--- Wird vom AdminService für das Hammer-Item aufgerufen
function CombatService.bindHammer(tool: Tool, player: Player)
	local handle = Instance.new("Part")
	handle.Name = "Handle"
	handle.Size = Vector3.new(0.5, 0.5, 4)
	handle.Color = Color3.fromRGB(110, 70, 40)
	handle.Material = Enum.Material.Wood
	handle.CanCollide = false
	handle.Massless = true
	local head = Instance.new("Part")
	head.Name = "HammerHead"
	head.Size = Vector3.new(2.2, 1.4, 1.4)
	head.Color = Color3.fromRGB(255, 200, 40)
	head.Material = Enum.Material.Neon
	head.CanCollide = false
	head.Massless = true
	head.CFrame = handle.CFrame * CFrame.new(0, 0, -2.2)
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = handle
	weld.Part1 = head
	weld.Parent = head
	head.Parent = handle
	handle.Parent = tool
	tool.RequiresHandle = true
	tool.Grip = CFrame.new(0, 0, 1.4)
	tool.Activated:Connect(function()
		hammerSmash(player, tool)
	end)
end

----------------------------------------------------------------------
-- Items im Inventar
----------------------------------------------------------------------
local function makeHandle(tool: Tool, color: Color3, shape: string)
	local handle = Instance.new("Part")
	handle.Name = "Handle"
	handle.CanCollide = false
	handle.Massless = true
	handle.Color = color
	if shape == "Bat" then
		handle.Size = Vector3.new(0.6, 0.6, 4)
		handle.Material = Enum.Material.Wood
		tool.Grip = CFrame.new(0, 0, 1.5)
	elseif shape == "Glove" then
		handle.Shape = Enum.PartType.Ball
		handle.Size = Vector3.new(1.6, 1.6, 1.6)
		handle.Material = Enum.Material.SmoothPlastic
		tool.Grip = CFrame.new(0, 0, 0)
	else
		handle.Size = Vector3.new(1, 1, 1)
		handle.Material = Enum.Material.Neon
		tool.Grip = CFrame.new(0, 0, 0)
	end
	handle.Parent = tool
end

local function makeWeapon(player: Player, def: Config.CombatItemDef): Tool
	local tool = Instance.new("Tool")
	tool.Name = def.Icon .. " " .. def.Name
	tool.ToolTip = def.Description
	tool.CanBeDropped = false
	tool.RequiresHandle = true
	tool:SetAttribute("CombatTool", def.Id)
	makeHandle(tool, def.Color, if def.Id == "Bat" then "Bat" else "Glove")
	tool.Activated:Connect(function()
		swing(player, def, tool)
	end)
	return tool
end

local function makeGadget(player: Player, def: Config.GadgetDef): Tool
	local tool = Instance.new("Tool")
	tool.Name = def.Icon .. " " .. def.Name
	tool.ToolTip = def.Description
	tool.CanBeDropped = false
	tool.RequiresHandle = true
	tool:SetAttribute("CombatTool", def.Id)
	makeHandle(tool, def.Color, "Gadget")
	tool.Activated:Connect(function()
		useGadget(player, def)
	end)
	return tool
end

--- Gleicht die Kampf-Items in Backpack/Charakter mit dem Besitz ab
function CombatService.syncTools(session: Session)
	local player = session.Player
	local backpack = player:FindFirstChild("Backpack")
	if not player.Parent or not backpack then
		return
	end
	local wanted: { [string]: () -> Tool } = {}
	if Config.Combat.Enabled then
		for _, def in Config.Combat.Items do
			if def.Currency == nil or session.Data.Items[def.Id] then
				wanted[def.Id] = function()
					return makeWeapon(player, def)
				end
			end
		end
	end
	for _, def in Config.Gadgets do
		if session.Data.Items[def.Id] then
			wanted[def.Id] = function()
				return makeGadget(player, def)
			end
		end
	end
	local present: { [string]: boolean } = {}
	local containers: { Instance } = { backpack }
	if player.Character then
		table.insert(containers, player.Character)
	end
	for _, container in containers do
		for _, child in container:GetChildren() do
			local id = child:GetAttribute("CombatTool")
			if child:IsA("Tool") and type(id) == "string" then
				if wanted[id] and not present[id] then
					present[id] = true
				else
					child:Destroy()
				end
			end
		end
	end
	for id, create in wanted do
		if not present[id] then
			create().Parent = backpack
		end
	end
end

----------------------------------------------------------------------
-- Kaufen
----------------------------------------------------------------------
function CombatService.buy(session: Session, itemId: string): (boolean, string?)
	local data = session.Data
	if data.Items[itemId] then
		return false, "Besitzt du schon"
	end
	for _, def in Config.Combat.Items do
		if def.Id == itemId then
			if def.Currency == nil then
				return false, "Das bekommst du gratis"
			elseif def.Currency == "Gems" then
				if not SessionService.spendGems(session, def.Cost) then
					return false, "Nicht genug Gems"
				end
			elseif not SessionService.spendCash(session, BigNum.new(def.Cost)) then
				return false, "Nicht genug Geld"
			end
			data.Items[itemId] = true
			session.Dirty = true
			CombatService.syncTools(session)
			SessionService.notify(session.Player, def.Icon .. " " .. def.Name .. " ist in deinem Inventar!", "success")
			return true, nil
		end
	end
	for _, def in Config.Gadgets do
		if def.Id == itemId then
			if data.Rebirths < def.Rebirths then
				return false, string.format("Erst ab %d Rebirths!", def.Rebirths)
			end
			if not SessionService.spendCash(session, BigNum.new(def.Cost)) then
				return false, "Nicht genug Geld"
			end
			data.Items[itemId] = true
			session.Dirty = true
			CombatService.syncTools(session)
			SessionService.notify(session.Player, def.Icon .. " " .. def.Name .. " ist in deinem Inventar!", "success")
			return true, nil
		end
	end
	return false, "Unbekanntes Item"
end

function CombatService.start()
	SessionService.onStart(35, function(session)
		local player = session.Player
		session.Maid:Give(player.CharacterAdded:Connect(function()
			task.delay(0.5, function()
				if SessionService.get(player) == session then
					CombatService.syncTools(session)
				end
			end)
		end))
		CombatService.syncTools(session)
	end)
	SessionService.onEnd(5, function(session)
		cooldowns[session.Player] = nil
		cooldownNotified[session.Player] = nil
		invisibleToken[session.Player] = nil
	end)
	NetService.register("BuyCombatItem", { ItemId = "string" }, function(session, payload)
		return CombatService.buy(session, payload.ItemId)
	end)
end

return CombatService

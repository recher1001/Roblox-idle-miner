--!strict
--[[
	Effects
	=======
	Reagiert auf Server-Ereignisse mit Feedback:
	Sounds, Floating-Text ("+$250"), Partikel, Banner, Popups.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local BigNum = require(Shared.BigNum)
local Config = require(Shared.Config)
local Net = require(Shared.Net)
local Types = require(Shared.Types)

local PlotLocator = require(script.Parent.Parent.PlotLocator)
local Remote = require(script.Parent.Parent.Remote)
local FloatingText = require(script.Parent.Parent.UI.FloatingText)
local HUD = require(script.Parent.Parent.UI.HUD)
local Popups = require(script.Parent.Parent.UI.Popups)
local Theme = require(script.Parent.Parent.UI.Theme)
local Toasts = require(script.Parent.Parent.UI.Toasts)
local Sounds = require(script.Parent.Sounds)

local Effects = {}

local lastCoinSound = 0

--- Partikel-Explosion an einer Weltposition
function Effects.burst(position: Vector3, color: Color3, count: number?)
	local part = Instance.new("Part")
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.Transparency = 1
	part.Size = Vector3.new(1, 1, 1)
	part.Position = position
	part.Parent = workspace
	local emitter = Instance.new("ParticleEmitter")
	emitter.Color = ColorSequence.new(color, Theme.lighten(color, 0.6))
	emitter.LightEmission = 0.6
	emitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.6), NumberSequenceKeypoint.new(1, 0) })
	emitter.Transparency = NumberSequence.new(0, 1)
	emitter.Lifetime = NumberRange.new(0.5, 0.9)
	emitter.Speed = NumberRange.new(10, 18)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Acceleration = Vector3.new(0, -30, 0)
	emitter.Rate = 0
	emitter.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	emitter.Parent = part
	emitter:Emit(count or 24)
	task.delay(1.2, function()
		part:Destroy()
	end)
end

local function onEffect(kind: string, payload: { [string]: any })
	local plot = PlotLocator.ownPlot()
	if kind == "Sale" then
		local amount = BigNum.from(payload.Amount)
		HUD.onSale(amount)
		local now = os.clock()
		if now - lastCoinSound > 0.25 then
			lastCoinSound = now
			Sounds.play("Coin", 1.1 + math.random() * 0.2)
		end
		local pos = PlotLocator.stationPosition(plot, "Warehouse")
		if pos then
			FloatingText.world("+" .. BigNum.formatMoney(amount, Config.CurrencySymbol), Theme.Colors.Money, pos)
			Effects.burst(pos - Vector3.new(0, 8, 0), Theme.Colors.Gold, 14)
		end
	elseif kind == "Purchase" then
		HUD.onSpend(BigNum.from(payload.Cost))
		local key = payload.Key
		if type(key) == "string" then
			local pos = PlotLocator.stationPosition(plot, key)
			if pos then
				FloatingText.world(
					string.format("⬆ +%d LEVEL", tonumber(payload.Levels) or 1),
					Theme.Colors.Gold,
					pos,
					30
				)
				Effects.burst(pos, Theme.Colors.Gold, 30)
			end
		end
	elseif kind == "Work" then
		Sounds.play("Click", 0.8)
	elseif kind == "Unlock" then
		Sounds.play("Rebirth", 1.2)
		Popups.banner("NEUE EBENE!", Theme.Colors.Gold, tostring(payload.Name or ""))
		local key = "Shaft:" .. tostring(payload.Index)
		task.delay(0.3, function()
			local pos = PlotLocator.stationPosition(PlotLocator.ownPlot(), key)
			if pos then
				Effects.burst(pos, Theme.Colors.Gold, 60)
			end
		end)
	elseif kind == "Ability" then
		local def = Config.Managers.Abilities[tostring(payload.Ability)]
		local key = payload.Key
		if def and type(key) == "string" then
			local pos = PlotLocator.stationPosition(plot, key)
			if pos then
				FloatingText.world(def.Icon .. " " .. string.upper(def.Name) .. "!", Theme.Colors.Gold, pos, 36)
				Effects.burst(pos, Theme.Colors.Gold, 40)
			end
		end
	elseif kind == "Rebirth" then
		Sounds.play("Rebirth")
		Popups.banner(
			"⭐ REBIRTH! ⭐",
			Theme.Colors.Purple,
			"Neuer Multiplikator: x" .. tostring(payload.Multiplier or "")
		)
	elseif kind == "Gems" then
		Sounds.play("Reveal", 1.3)
		FloatingText.screen(
			string.format("+%d 💎", tonumber(payload.Amount) or 0),
			Theme.Colors.Gem,
			HUD.cashPosition() + UDim2.fromOffset(240, 0),
			30
		)
	elseif kind == "Cash" then
		local amount = BigNum.from(payload.Amount)
		HUD.onSale(amount)
		Sounds.play("Coin")
	elseif kind == "Stolen" then
		-- Dieb: erfolgreich gestohlen
		Sounds.play("Coin", 0.9)
		Popups.banner(
			"💰 GESTOHLEN!",
			Theme.Colors.Gold,
			BigNum.formatMoney(BigNum.from(payload.Amount), Config.CurrencySymbol)
		)
	elseif kind == "Robbed" then
		Sounds.play("Alarm", 0.7)
		Popups.banner("🚨 AUSGERAUBT!", Theme.Colors.Red, tostring(payload.Thief or "") .. " hat dich bestohlen!")
	elseif kind == "Trade" then
		Sounds.play("Rebirth", 1.3)
		Popups.banner("🤝 HANDEL ERFOLGREICH!", Theme.Colors.Cyan, "Deine neuen Pets sind im Inventar")
	elseif kind == "AfkReward" then
		Sounds.play("Coin", 1.2)
		local cash = BigNum.from(payload.Cash)
		local text = string.format("💤 +%d 💎", tonumber(payload.Gems) or 0)
		if not BigNum.isZero(cash) then
			text ..= "  +" .. BigNum.formatMoney(cash, Config.CurrencySymbol)
			HUD.onSale(cash)
		end
		FloatingText.screen(text, Theme.Colors.Gem, HUD.cashPosition() + UDim2.fromOffset(0, 60), 28)
	elseif kind == "StealAttempt" then
		Sounds.play("Alarm", 1.2)
		Toasts.show(
			"🚨 " .. tostring(payload.Thief or "Jemand") .. " versucht dein Aufzugslager zu plündern! Lauf hin!",
			"alarm",
			4
		)
	end
end

function Effects.start()
	Net.event("Effect").OnClientEvent:Connect(function(kind: string, payload: { [string]: any })
		local ok, err = pcall(function()
			onEffect(kind, payload or {})
		end)
		if not ok then
			warn("[Effects] Fehler:", err)
		end
	end)
	Net.event("Notify").OnClientEvent:Connect(function(text: string, kind: string?)
		Toasts.show(text, kind)
		if kind == "warn" or kind == "error" then
			Sounds.play("Error", 0.8)
		end
	end)
	Net.event("OfflineEarnings").OnClientEvent:Connect(function(info: { [string]: any })
		Popups.offline(BigNum.from(info.Amount), tonumber(info.Seconds) or 0, info.Capped == true)
	end)
	Net.event("ManagerReveal").OnClientEvent:Connect(function(manager: Types.ManagerData)
		Popups.managerReveal(manager)
	end)
	Net.event("EggHatch").OnClientEvent:Connect(function(info: any)
		if type(info) == "table" and type(info.Pets) == "table" then
			Popups.eggHatch(info)
		end
	end)
	Net.event("TradeInvite").OnClientEvent:Connect(function(info: any)
		if type(info) == "table" then
			Popups.tradeInvite(tonumber(info.FromUserId) or 0, tostring(info.FromName), tonumber(info.ExpiresAt) or 0)
		end
	end)
	Net.event("ServerEvent").OnClientEvent:Connect(function(info: { [string]: any })
		if info.Started then
			Sounds.play("Rebirth", 1.4)
			Popups.banner("🔥 " .. tostring(info.Name), Theme.Colors.Orange, tostring(info.Description or ""))
		else
			Toasts.show("Event vorbei: " .. tostring(info.Name), "info")
		end
	end)
	Remote.Failed:Connect(function(msg: string)
		Toasts.show(msg, "warn")
		Sounds.play("Error", 0.8)
	end)
end

return Effects

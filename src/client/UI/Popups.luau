--!strict
--[[
	Popups
	======
	  confirm()        - Ja/Nein-Dialog
	  offline()        - "Willkommen zurück" mit Offline-Einnahmen (x2 für Gems)
	  managerReveal()  - Reveal-Animation beim Einstellen (wie Ei-Öffnen)
	  eggHatch()       - Ei-Schlüpf-Animation (1 oder 3 Eier gleichzeitig)
	  tradeInvite()    - Handelsanfrage mit Annehmen/Ablehnen
	  banner()         - großer Text in der Bildschirmmitte (Events, Freischaltungen)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local BigNum = require(Shared.BigNum)
local Clock = require(Shared.Clock)
local Config = require(Shared.Config)
local Formulas = require(Shared.Formulas)
local Types = require(Shared.Types)

local Remote = require(script.Parent.Parent.Remote)
local Sounds = require(script.Parent.Parent.Controllers.Sounds)
local Components = require(script.Parent.Components)
local PetVisuals = require(script.Parent.PetVisuals)
local Root = require(script.Parent.Root)
local Theme = require(script.Parent.Theme)
local Util = require(script.Parent.Util)

local Popups = {}

----------------------------------------------------------------------
-- Gemeinsames Grundgerüst
----------------------------------------------------------------------
type Shell = { Dim: Frame, Card: Frame, Scale: UIScale, Close: () -> () }

local function shell(size: Vector2, accent: Color3): Shell
	local dim: Frame = Util.new("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Theme.Colors.Overlay,
		BackgroundTransparency = 1,
		Active = true,
		Parent = Root.layer("Popup"),
	})
	local scale: UIScale = Util.new("UIScale", { Scale = 0.7 })
	local card: Frame = Util.new("Frame", {
		Size = UDim2.fromOffset(size.X, size.Y),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = Color3.new(1, 1, 1),
		Parent = dim,
	}, {
		Util.corner(Theme.Radius.Large),
		Util.gradient(Theme.Colors.PanelTop, Theme.Colors.Panel),
		Util.stroke(accent, 3),
		scale,
	})
	Util.tween(dim, 0.2, { BackgroundTransparency = 0.55 })
	Util.tween(scale, 0.35, { Scale = 1 }, Enum.EasingStyle.Back)
	local closed = false
	return {
		Dim = dim,
		Card = card,
		Scale = scale,
		Close = function()
			if closed then
				return
			end
			closed = true
			Util.tween(dim, 0.2, { BackgroundTransparency = 1 })
			Util.tween(scale, 0.2, { Scale = 0.6 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
			task.delay(0.22, function()
				dim:Destroy()
			end)
		end,
	}
end

local function title(parent: Instance, text: string, y: number, color: Color3?)
	local l = Util.label({
		Size = UDim2.new(1, -20, 0, 44),
		Position = UDim2.new(0.5, 0, 0, y),
		AnchorPoint = Vector2.new(0.5, 0),
		Text = text,
		Font = Theme.Fonts.Title,
		TextSize = 34,
		TextColor3 = color or Theme.Colors.Text,
		Parent = parent,
	})
	Util.textStroke(2).Parent = l
	return l
end

----------------------------------------------------------------------
-- Bestätigung
----------------------------------------------------------------------
function Popups.confirm(text: string, onYes: () -> (), yesText: string?)
	local s = shell(Vector2.new(480, 250), Theme.Colors.Orange)
	Util.label({
		Size = UDim2.new(1, -40, 0, 120),
		Position = UDim2.fromOffset(20, 20),
		Text = text,
		TextSize = 21,
		TextWrapped = true,
		Parent = s.Card,
	})
	Components.button({
		Text = yesText or "Ja",
		Color = Theme.Colors.Green,
		Size = UDim2.fromOffset(190, 62),
		Position = UDim2.new(0.5, -10, 1, -20),
		AnchorPoint = Vector2.new(1, 1),
		Parent = s.Card,
		OnClick = function()
			s.Close()
			onYes()
		end,
	})
	Components.button({
		Text = "Abbrechen",
		Color = Theme.Colors.Red,
		Size = UDim2.fromOffset(190, 62),
		Position = UDim2.new(0.5, 10, 1, -20),
		AnchorPoint = Vector2.new(0, 1),
		Parent = s.Card,
		OnClick = s.Close,
	})
end

----------------------------------------------------------------------
-- Offline-Einnahmen
----------------------------------------------------------------------
function Popups.offline(amount: BigNum.BigNum, seconds: number, capped: boolean)
	local s = shell(Vector2.new(540, 400), Theme.Colors.Gold)
	title(s.Card, "Willkommen zurück! ⛏️", 22, Theme.Colors.Gold)
	Util.label({
		Size = UDim2.new(1, -40, 0, 50),
		Position = UDim2.fromOffset(20, 76),
		Text = string.format(
			"Du warst %s weg.%s\nDeine Manager haben für dich gearbeitet:",
			Formulas.formatDuration(seconds),
			if capped then string.format(" (max. %dh)", math.floor(seconds / 3600 + 0.5)) else ""
		),
		TextSize = 18,
		TextColor3 = Theme.Colors.SubText,
		TextWrapped = true,
		Parent = s.Card,
	})
	local amountScale: UIScale = Util.new("UIScale")
	local amountLabel = Util.label({
		Size = UDim2.new(1, -40, 0, 80),
		Position = UDim2.fromOffset(20, 140),
		Text = BigNum.formatMoney(amount, Config.CurrencySymbol),
		Font = Theme.Fonts.Number,
		TextSize = 60,
		TextColor3 = Theme.Colors.Money,
		Parent = s.Card,
	})
	amountScale.Parent = amountLabel
	Util.textStroke(3).Parent = amountLabel
	task.delay(0.3, function()
		Util.pop(amountScale, 0.2)
	end)

	local busy = false
	local function claim(double: boolean)
		if busy then
			return
		end
		busy = true
		local r = Remote.request("ClaimOffline", { Double = double })
		busy = false
		if r.ok then
			Sounds.play("Coin")
			s.Close()
		end
	end
	Components.button({
		Text = "Einsammeln",
		Color = Theme.Colors.Green,
		Size = UDim2.fromOffset(230, 72),
		Position = UDim2.new(0.5, -10, 1, -26),
		AnchorPoint = Vector2.new(1, 1),
		Sound = "Coin",
		Parent = s.Card,
		OnClick = function()
			claim(false)
		end,
	})
	Components.button({
		Text = string.format("x2  (%d 💎)", Config.Offline.DoubleGemCost),
		Color = Theme.Colors.Purple,
		Size = UDim2.fromOffset(230, 72),
		Position = UDim2.new(0.5, 10, 1, -26),
		AnchorPoint = Vector2.new(0, 1),
		Sound = "Purchase",
		Parent = s.Card,
		OnClick = function()
			claim(true)
		end,
	})
end

----------------------------------------------------------------------
-- Manager-Reveal (Spannung -> Enthüllung)
----------------------------------------------------------------------
local revealQueue: { Types.ManagerData } = {}
local revealing = false

local function playReveal(m: Types.ManagerData)
	local rarity = Formulas.rarityDef(m.Rarity)
	local rarityIndex = Formulas.rarityIndex(m.Rarity)
	local ability = Config.Managers.Abilities[m.Ability]

	local dim: Frame = Util.new("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Theme.Colors.Overlay,
		BackgroundTransparency = 1,
		Active = true,
		Parent = Root.layer("Popup"),
	})
	Util.tween(dim, 0.25, { BackgroundTransparency = 0.4 })

	-- Strahlen hinter der Karte
	local rays: Frame = Util.new("Frame", {
		Size = UDim2.fromOffset(700, 700),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
		Visible = false,
		Parent = dim,
	})
	for n = 0, 7 do
		Util.new("Frame", {
			Size = UDim2.fromOffset(46, 700),
			Position = UDim2.fromScale(0.5, 0.5),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Rotation = n * 22.5,
			BackgroundColor3 = rarity.Color,
			BackgroundTransparency = 0.55,
			BorderSizePixel = 0,
			Parent = rays,
		}, {
			Util.new("UIGradient", {
				Transparency = NumberSequence.new({
					NumberSequenceKeypoint.new(0, 1),
					NumberSequenceKeypoint.new(0.5, 0),
					NumberSequenceKeypoint.new(1, 1),
				}),
				Rotation = 90,
			}),
		})
	end

	local cardScale: UIScale = Util.new("UIScale", { Scale = 0.5 })
	local card: Frame = Util.new("Frame", {
		Size = UDim2.fromOffset(280, 380),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = Color3.new(1, 1, 1),
		Parent = dim,
	}, {
		Util.corner(Theme.Radius.Large),
		Util.gradient(Theme.Colors.PanelTop, Theme.Colors.Panel),
		Util.stroke(Color3.new(1, 1, 1), 4, 0.3),
		cardScale,
	})
	local question = Util.label({
		Size = UDim2.fromScale(1, 1),
		Text = "?",
		Font = Theme.Fonts.Title,
		TextSize = 140,
		TextColor3 = Theme.Colors.SubText,
		Parent = card,
	})
	Util.tween(cardScale, 0.4, { Scale = 1 }, Enum.EasingStyle.Back)
	task.wait(0.4)

	-- Schütteln mit steigender Intensität
	local shakeTime = 1.2 + rarityIndex * 0.15
	local start = os.clock()
	while os.clock() - start < shakeTime do
		local t = (os.clock() - start) / shakeTime
		card.Rotation = math.sin(os.clock() * 40) * (4 + t * 10)
		card.Position = UDim2.new(0.5, math.random(-1, 1) * t * 6, 0.5, math.random(-1, 1) * t * 6)
		RunService.RenderStepped:Wait()
	end
	card.Rotation = 0
	card.Position = UDim2.fromScale(0.5, 0.5)

	-- Umdrehen
	Util.tween(card, 0.15, { Size = UDim2.fromOffset(0, 380) }, Enum.EasingStyle.Quad, Enum.EasingDirection.In).Completed
		:Wait()
	question:Destroy()
	local gradient = card:FindFirstChildOfClass("UIGradient")
	if gradient then
		gradient.Color = ColorSequence.new(Theme.lighten(rarity.Color, 0.3), Theme.darken(rarity.Color, 0.45))
	end
	local stroke = card:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Color = Theme.lighten(rarity.Color, 0.5)
		stroke.Transparency = 0
	end
	if m.FriendUserId then
		Util.new("ImageLabel", {
			Size = UDim2.fromOffset(130, 130),
			Position = UDim2.new(0.5, 0, 0, 16),
			AnchorPoint = Vector2.new(0.5, 0),
			BackgroundColor3 = Theme.darken(rarity.Color, 0.5),
			Image = string.format("rbxthumb://type=AvatarHeadShot&id=%d&w=420&h=420", m.FriendUserId),
			Parent = card,
		}, { Util.round(), Util.stroke(Color3.new(1, 1, 1), 3, 0.2) })
	else
		Util.label({
			Size = UDim2.new(1, 0, 0, 120),
			Position = UDim2.fromOffset(0, 24),
			Text = "👔",
			TextSize = 96,
			Parent = card,
		})
	end
	local rarityLabel = Util.label({
		Size = UDim2.new(1, -20, 0, 40),
		Position = UDim2.fromOffset(10, 150),
		Text = string.upper(rarity.Name),
		Font = Theme.Fonts.Title,
		TextSize = 34,
		Parent = card,
	})
	Util.textStroke(2.5).Parent = rarityLabel
	local nameLabel = Util.label({
		Size = UDim2.new(1, -20, 0, 34),
		Position = UDim2.fromOffset(10, 196),
		Text = m.Name,
		Font = Theme.Fonts.Title,
		TextSize = 28,
		Parent = card,
	})
	Util.textStroke(2).Parent = nameLabel
	local abilityLabel = Util.label({
		Size = UDim2.new(1, -24, 0, 80),
		Position = UDim2.fromOffset(12, 236),
		Text = string.format(
			"%s %s\n%s\nTempo dauerhaft x%.2f",
			ability and ability.Icon or "",
			ability and ability.Name or "",
			Formulas.abilityDescription(m),
			rarity.PassiveSpeed
		),
		TextSize = 17,
		TextWrapped = true,
		Parent = card,
	})
	Util.textStroke(1.5).Parent = abilityLabel
	Util.label({
		Size = UDim2.new(1, 0, 0, 30),
		Position = UDim2.new(0, 0, 1, -40),
		Text = if m.AssignedTo then "✅ Automatisch zugewiesen" else "In die Reserve",
		TextSize = 15,
		TextColor3 = Color3.new(1, 1, 1),
		TextTransparency = 0.2,
		Parent = card,
	})
	Util.tween(card, 0.25, { Size = UDim2.fromOffset(280, 380) }, Enum.EasingStyle.Back)
	Sounds.play("Reveal", 0.9 + rarityIndex * 0.1)
	cardScale.Scale = 1.25
	Util.tween(cardScale, 0.5, { Scale = 1 }, Enum.EasingStyle.Elastic)

	if rarityIndex >= 3 then
		rays.Visible = true
		task.spawn(function()
			while rays.Parent do
				rays.Rotation += 0.4
				RunService.RenderStepped:Wait()
			end
		end)
	end
	if rarityIndex >= 4 then
		Popups.banner(
			string.format("%s %s!", rarity.Name == "Mythisch" and "🌟" or "✨", string.upper(rarity.Name)),
			rarity.Color
		)
	end

	-- Tippen zum Schließen (nach kurzer Zeit)
	task.wait(0.8)
	local hint = Util.label({
		Size = UDim2.fromOffset(400, 30),
		Position = UDim2.new(0.5, 0, 0.5, 220),
		AnchorPoint = Vector2.new(0.5, 0),
		Text = "Tippen zum Fortfahren",
		TextSize = 18,
		TextColor3 = Theme.Colors.SubText,
		Parent = dim,
	})
	local _ = hint
	local done = false
	local button: TextButton = Util.new("TextButton", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Text = "",
		ZIndex = 50,
		Parent = dim,
	})
	button.Activated:Connect(function()
		done = true
	end)
	local waited = 0
	while not done and waited < 6 do
		waited += task.wait(0.1)
	end
	Util.tween(cardScale, 0.2, { Scale = 0.4 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	Util.tween(dim, 0.2, { BackgroundTransparency = 1 })
	task.wait(0.22)
	dim:Destroy()
end

function Popups.managerReveal(m: Types.ManagerData)
	table.insert(revealQueue, m)
	if revealing then
		return
	end
	revealing = true
	task.spawn(function()
		while #revealQueue > 0 do
			local nextManager = table.remove(revealQueue, 1)
			if nextManager then
				local ok, err = pcall(function()
					playReveal(nextManager)
				end)
				if not ok then
					warn("[Popups] Reveal-Fehler:", err)
				end
			end
		end
		revealing = false
	end)
end

----------------------------------------------------------------------
-- Ei-Schlüpfen (wie bei den großen Pet-Spielen)
----------------------------------------------------------------------
export type HatchResult = { Id: string, Pet: string, Chance: number, Equipped: boolean }
type HatchInfo = { EggId: string, Pets: { HatchResult } }

local hatchQueue: { HatchInfo } = {}
local hatching = false

local function playHatch(info: HatchInfo)
	local egg = Formulas.eggDef(info.EggId)
	local eggColor = if egg then egg.Color else Theme.Colors.Gold
	local count = #info.Pets
	if count == 0 then
		return
	end
	-- seltenstes Ergebnis bestimmt die Spannung
	local rarest = 100
	for _, r in info.Pets do
		rarest = math.min(rarest, r.Chance)
	end

	local dim: Frame = Util.new("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Theme.Colors.Overlay,
		BackgroundTransparency = 1,
		Active = true,
		Parent = Root.layer("Popup"),
	})
	Util.tween(dim, 0.25, { BackgroundTransparency = 0.35 })

	local spacing = 300
	local slots: { { Holder: Frame, Scale: UIScale, Egg: Frame } } = {}
	for i = 1, count do
		local x = (i - (count + 1) / 2) * spacing
		local scale: UIScale = Util.new("UIScale", { Scale = 0.2 })
		local holder: Frame = Util.new("Frame", {
			Size = UDim2.fromOffset(280, 400),
			Position = UDim2.new(0.5, x, 0.5, 0),
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundTransparency = 1,
			Parent = dim,
		}, { scale })
		local eggFrame = PetVisuals.egg({
			Position = UDim2.fromScale(0.5, 0.45),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Parent = holder,
		}, eggColor, 190)
		Util.tween(scale, 0.45, { Scale = 1 }, Enum.EasingStyle.Back)
		table.insert(slots, { Holder = holder, Scale = scale, Egg = eggFrame })
	end
	Sounds.play("Click", 0.8)
	task.wait(0.45)

	-- Wackeln, immer stärker (länger bei seltenen Pets)
	local shakeTime = 1.4 + (if rarest <= 1 then 0.9 elseif rarest <= 5 then 0.4 else 0)
	local start = os.clock()
	local nextTick = 0
	while os.clock() - start < shakeTime do
		local t = (os.clock() - start) / shakeTime
		for i, s in slots do
			s.Egg.Rotation = math.sin(os.clock() * (10 + t * 30) + i) * (6 + t * 22)
		end
		if os.clock() - start > nextTick then
			nextTick += 0.35 - t * 0.2
			Sounds.play("Click", 1 + t * 0.6)
		end
		RunService.RenderStepped:Wait()
	end

	-- Weißer Blitz
	local flash: Frame = Util.new("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BackgroundTransparency = 0,
		ZIndex = 40,
		Parent = dim,
	})
	Util.tween(flash, 0.5, { BackgroundTransparency = 1 })
	task.delay(0.55, function()
		flash:Destroy()
	end)

	local bestIndex = 1
	for i, result in info.Pets do
		local s = slots[i]
		s.Egg:Destroy()
		local def = Formulas.petDef(result.Pet)
		local rarity = Formulas.petRarity(if def then def.Rarity else "Common")
		local rarityIndex = Formulas.petRarityIndex(rarity.Id)
		if rarityIndex >= 4 then
			-- drehende Strahlen hinter seltenen Pets
			local rays: Frame = Util.new("Frame", {
				Size = UDim2.fromOffset(420, 420),
				Position = UDim2.fromScale(0.5, 0.36),
				AnchorPoint = Vector2.new(0.5, 0.5),
				BackgroundTransparency = 1,
				Parent = s.Holder,
			})
			for n = 0, 5 do
				Util.new("Frame", {
					Size = UDim2.fromOffset(40, 420),
					Position = UDim2.fromScale(0.5, 0.5),
					AnchorPoint = Vector2.new(0.5, 0.5),
					Rotation = n * 30,
					BackgroundColor3 = rarity.Color,
					BackgroundTransparency = 0.45,
					BorderSizePixel = 0,
					Parent = rays,
				}, {
					Util.new("UIGradient", {
						Transparency = NumberSequence.new({
							NumberSequenceKeypoint.new(0, 1),
							NumberSequenceKeypoint.new(0.5, 0),
							NumberSequenceKeypoint.new(1, 1),
						}),
						Rotation = 90,
					}),
				})
			end
			task.spawn(function()
				while rays.Parent do
					rays.Rotation += 0.6
					RunService.RenderStepped:Wait()
				end
			end)
		end
		local glow: Frame = Util.new("Frame", {
			Size = UDim2.fromOffset(190, 190),
			Position = UDim2.fromScale(0.5, 0.36),
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundColor3 = rarity.Color,
			BackgroundTransparency = 0.25,
			Parent = s.Holder,
		}, {
			Util.round(),
			Util.new("UIGradient", {
				Transparency = NumberSequence.new({
					NumberSequenceKeypoint.new(0, 0.1),
					NumberSequenceKeypoint.new(1, 0.9),
				}),
				Rotation = 90,
			}),
			Util.stroke(Theme.lighten(rarity.Color, 0.5), 4),
		})
		Util.label({
			Size = UDim2.fromScale(1, 1),
			Text = if def then def.Icon else "❓",
			TextSize = 110,
			Parent = glow,
		})
		local rarityLabel = Util.label({
			Size = UDim2.new(1, 0, 0, 36),
			Position = UDim2.new(0, 0, 0.36, 104),
			Text = string.upper(rarity.Name),
			Font = Theme.Fonts.Title,
			TextSize = 30,
			TextColor3 = rarity.Color,
			Parent = s.Holder,
		})
		Util.textStroke(3).Parent = rarityLabel
		local nameLabel = Util.label({
			Size = UDim2.new(1, 0, 0, 34),
			Position = UDim2.new(0, 0, 0.36, 140),
			Text = if def then def.Name else result.Pet,
			Font = Theme.Fonts.Title,
			TextSize = 28,
			Parent = s.Holder,
		})
		Util.textStroke(2.5).Parent = nameLabel
		local infoLabel = Util.label({
			Size = UDim2.new(1, 0, 0, 52),
			Position = UDim2.new(0, 0, 0.36, 176),
			Text = string.format(
				"💰 %s Einkommen\n🍀 %s%s",
				if def then Formulas.formatPetMultiplier(def.Multiplier) else "x1",
				Formulas.formatChance(result.Chance),
				if result.Equipped then "   ✅ Ausgerüstet" else ""
			),
			TextSize = 19,
			Parent = s.Holder,
		})
		Util.textStroke(2).Parent = infoLabel
		s.Scale.Scale = 1.35
		Util.tween(s.Scale, 0.55, { Scale = 1 }, Enum.EasingStyle.Elastic)
		if result.Chance < info.Pets[bestIndex].Chance then
			bestIndex = i
		end
	end

	local best = info.Pets[bestIndex]
	local bestDef = Formulas.petDef(best.Pet)
	local bestRarity = Formulas.petRarity(if bestDef then bestDef.Rarity else "Common")
	local bestIndexRarity = Formulas.petRarityIndex(bestRarity.Id)
	Sounds.play("Reveal", 0.9 + bestIndexRarity * 0.08)
	if bestIndexRarity >= 5 then
		Sounds.play("Rebirth", 1.2)
		Popups.banner(
			string.format("%s %s!", if bestIndexRarity >= 6 then "🌟" else "✨", string.upper(bestRarity.Name)),
			bestRarity.Color,
			string.format("Nur %s Chance!", Formulas.formatChance(best.Chance))
		)
	end

	task.wait(0.7)
	Util.label({
		Size = UDim2.fromOffset(400, 30),
		Position = UDim2.new(0.5, 0, 1, -60),
		AnchorPoint = Vector2.new(0.5, 0),
		Text = "Tippen zum Fortfahren",
		TextSize = 18,
		TextColor3 = Theme.Colors.SubText,
		Parent = dim,
	})
	local done = false
	local button: TextButton = Util.new("TextButton", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Text = "",
		ZIndex = 50,
		Parent = dim,
	})
	button.Activated:Connect(function()
		done = true
	end)
	local waited = 0
	while not done and waited < 5 do
		waited += task.wait(0.1)
	end
	for _, s in slots do
		Util.tween(s.Scale, 0.2, { Scale = 0.3 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	end
	Util.tween(dim, 0.2, { BackgroundTransparency = 1 })
	task.wait(0.22)
	dim:Destroy()
end

function Popups.eggHatch(info: HatchInfo)
	table.insert(hatchQueue, info)
	if hatching then
		return
	end
	hatching = true
	task.spawn(function()
		while #hatchQueue > 0 do
			local nextInfo = table.remove(hatchQueue, 1)
			if nextInfo then
				local ok, err = pcall(function()
					playHatch(nextInfo)
				end)
				if not ok then
					warn("[Popups] Schlüpf-Fehler:", err)
				end
			end
		end
		hatching = false
	end)
end

function Popups.isHatching(): boolean
	return hatching
end

----------------------------------------------------------------------
-- Handelsanfrage (oben in der Mitte, mit Annehmen/Ablehnen)
----------------------------------------------------------------------
function Popups.tradeInvite(fromUserId: number, fromName: string, expiresAt: number)
	local scale: UIScale = Util.new("UIScale", { Scale = 0.4 })
	local card: Frame = Util.new("Frame", {
		Size = UDim2.fromOffset(520, 150),
		Position = UDim2.new(0.5, 0, 0, 96),
		AnchorPoint = Vector2.new(0.5, 0),
		BackgroundColor3 = Color3.new(1, 1, 1),
		Parent = Root.layer("Popup"),
	}, {
		Util.corner(Theme.Radius.Large),
		Util.gradient(Theme.Colors.PanelTop, Theme.Colors.Panel),
		Util.stroke(Theme.Colors.Cyan, 3),
		scale,
	})
	Util.new("ImageLabel", {
		Size = UDim2.fromOffset(84, 84),
		Position = UDim2.fromOffset(16, 14),
		BackgroundColor3 = Theme.Colors.Card,
		Image = string.format("rbxthumb://type=AvatarHeadShot&id=%d&w=150&h=150", fromUserId),
		Parent = card,
	}, { Util.round(), Util.stroke(Color3.new(1, 1, 1), 2) })
	local text = Util.label({
		Size = UDim2.new(1, -130, 0, 60),
		Position = UDim2.fromOffset(114, 10),
		Text = "🤝 " .. fromName .. "\nmöchte mit dir Pets handeln!",
		Font = Theme.Fonts.Title,
		TextSize = 21,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = card,
	})
	Util.textStroke(1.5).Parent = text
	local timer = Util.label({
		Size = UDim2.fromOffset(100, 20),
		Position = UDim2.fromOffset(16, 104),
		Text = "",
		TextSize = 15,
		TextColor3 = Theme.Colors.SubText,
		Parent = card,
	})
	Util.tween(scale, 0.35, { Scale = 1 }, Enum.EasingStyle.Back)
	Sounds.play("Reveal", 1.4)

	local closed = false
	local function close()
		if closed then
			return
		end
		closed = true
		Util.tween(scale, 0.2, { Scale = 0.3 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		task.delay(0.22, function()
			card:Destroy()
		end)
	end
	local function respond(accept: boolean)
		close()
		Remote.send("TradeRespond", { From = fromUserId, Accept = accept })
	end
	Components.button({
		Text = "✅ Annehmen",
		Color = Theme.Colors.Green,
		Size = UDim2.fromOffset(170, 54),
		Position = UDim2.new(1, -196, 1, -12),
		AnchorPoint = Vector2.new(1, 1),
		TextSize = 19,
		Parent = card,
		OnClick = function()
			respond(true)
		end,
	})
	Components.button({
		Text = "❌",
		Color = Theme.Colors.Red,
		Size = UDim2.fromOffset(70, 54),
		Position = UDim2.new(1, -112, 1, -12),
		AnchorPoint = Vector2.new(1, 1),
		TextSize = 22,
		Parent = card,
		OnClick = function()
			respond(false)
		end,
	})
	task.spawn(function()
		while not closed do
			local left = expiresAt - Clock.now()
			if left <= 0 then
				close()
				break
			end
			timer.Text = string.format("⏳ %ds", math.ceil(left))
			task.wait(0.25)
		end
	end)
end

----------------------------------------------------------------------
-- Banner
----------------------------------------------------------------------
function Popups.banner(text: string, color: Color3, sub: string?)
	local scale: UIScale = Util.new("UIScale", { Scale = 0.3 })
	local frame: Frame = Util.new("Frame", {
		Size = UDim2.fromOffset(900, 130),
		Position = UDim2.fromScale(0.5, 0.32),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
		Parent = Root.layer("Toast"),
	}, { scale })
	local label = Util.label({
		Size = UDim2.new(1, 0, 0, 80),
		Text = text,
		Font = Theme.Fonts.Title,
		TextSize = 64,
		TextColor3 = color,
		Parent = frame,
	})
	Util.textStroke(4).Parent = label
	if sub then
		local subLabel = Util.label({
			Size = UDim2.new(1, 0, 0, 36),
			Position = UDim2.fromOffset(0, 82),
			Text = sub,
			TextSize = 24,
			Parent = frame,
		})
		Util.textStroke(2).Parent = subLabel
	end
	Util.tween(scale, 0.45, { Scale = 1 }, Enum.EasingStyle.Back)
	task.delay(2.4, function()
		Util.tween(scale, 0.3, { Scale = 0.2 }, Enum.EasingStyle.Back, Enum.EasingDirection.In)
		task.wait(0.32)
		frame:Destroy()
	end)
end

return Popups

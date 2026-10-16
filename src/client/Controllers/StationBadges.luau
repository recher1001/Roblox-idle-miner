--!strict
--[[
	StationBadges
	=============
	Für die EIGENE Mine:
	  * "⬆️"-Button neben jeder Station -> öffnet Upgrades für genau diese Station
	  * Fortschrittsbalken des laufenden Zyklus
	  * "👆 TIPPEN!" hüpft über Stationen ohne Manager, die gerade stillstehen
	    (Tippen startet den Zyklus - ohne Manager musst du selbst arbeiten!)
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local BigNum = require(Shared.BigNum)
local Clock = require(Shared.Clock)
local Formulas = require(Shared.Formulas)

local ClientState = require(script.Parent.Parent.ClientState)
local PlotLocator = require(script.Parent.Parent.PlotLocator)
local Remote = require(script.Parent.Parent.Remote)
local PanelManager = require(script.Parent.Parent.UI.PanelManager)
local Theme = require(script.Parent.Parent.UI.Theme)
local Util = require(script.Parent.Parent.UI.Util)
local Sounds = require(script.Parent.Sounds)

local StationBadges = {}

type Badge = {
	Key: string,
	Station: Model,
	Gui: BillboardGui,
	Hint: BillboardGui,
	Fill: Frame,
	HintLabel: TextButton,
}

local badges: { [string]: Badge } = {}
local container: Folder

local function makeBadge(key: string, station: Model): Badge?
	local anchor = station:FindFirstChild("InfoAnchor")
	local hitbox = station:FindFirstChild("Hitbox")
	if not anchor or not anchor:IsA("BasePart") or not hitbox or not hitbox:IsA("BasePart") then
		return nil
	end
	-- Upgrade-Button + Fortschritt (rechts neben dem Info-Schild)
	local gui: BillboardGui = Util.new("BillboardGui", {
		Name = "Badge_" .. key,
		Adornee = anchor,
		Size = UDim2.fromScale(15, 6),
		StudsOffset = Vector3.new(0, -3.2, 0),
		LightInfluence = 0,
		MaxDistance = 160,
		Active = true,
		ResetOnSpawn = false,
		Parent = container,
	})
	local barBack: Frame = Util.new("Frame", {
		Size = UDim2.fromScale(0.62, 0.16),
		Position = UDim2.fromScale(0.05, 0.12),
		BackgroundColor3 = Theme.Colors.Track,
		BackgroundTransparency = 0.05,
		Parent = gui,
	}, { Util.round(), Util.stroke(Color3.new(0, 0, 0), 1.5, 0.3) })
	local fill: Frame = Util.new("Frame", {
		Size = UDim2.fromScale(0, 1),
		BackgroundColor3 = Color3.new(1, 1, 1),
		Parent = barBack,
	}, { Util.round(), Util.gradient(Theme.Colors.Money, Theme.darken(Theme.Colors.Green, 0.2)) })

	local upgrade: TextButton = Util.new("TextButton", {
		Size = UDim2.fromScale(0.24, 0.6),
		Position = UDim2.fromScale(0.72, 0),
		BackgroundColor3 = Color3.new(1, 1, 1),
		Text = "⬆️",
		Font = Theme.Fonts.Title,
		TextScaled = true,
		TextColor3 = Color3.new(1, 1, 1),
		AutoButtonColor = true,
		Parent = gui,
	}, {
		Util.round(),
		Util.gradient(Theme.lighten(Theme.Colors.Gold, 0.2), Theme.darken(Theme.Colors.Gold, 0.2)),
		Util.stroke(Theme.darken(Theme.Colors.Gold, 0.5), 2),
		Util.new("UIAspectRatioConstraint", { AspectRatio = 1 }),
	})
	upgrade.Activated:Connect(function()
		Sounds.play("Click")
		PanelManager.open("Upgrades", key)
	end)

	-- "Tippen!"-Hinweis über der Station
	local hint: BillboardGui = Util.new("BillboardGui", {
		Name = "Hint_" .. key,
		Adornee = hitbox,
		Size = UDim2.fromScale(9, 3.4),
		StudsOffset = Vector3.new(0, 1, 0),
		LightInfluence = 0,
		MaxDistance = 200,
		AlwaysOnTop = true,
		Active = true,
		Enabled = false,
		ResetOnSpawn = false,
		Parent = container,
	})
	local hintButton: TextButton = Util.new("TextButton", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(1, 1, 1),
		Text = "👆 TIPPEN!",
		Font = Theme.Fonts.Title,
		TextScaled = true,
		TextColor3 = Color3.new(1, 1, 1),
		Parent = hint,
	}, {
		Util.round(),
		Util.gradient(Theme.lighten(Theme.Colors.Green, 0.2), Theme.darken(Theme.Colors.Green, 0.2)),
		Util.stroke(Color3.new(1, 1, 1), 2),
		Util.textStroke(2),
		Util.padding(4, 10),
	})
	hintButton.Activated:Connect(function()
		Remote.send("Work", { Key = key })
	end)

	return { Key = key, Station = station, Gui = gui, Hint = hint, Fill = fill, HintLabel = hintButton }
end

local function needsTap(key: string, station: Model): boolean
	if station:GetAttribute("Running") == true or station:GetAttribute("HasManager") == true then
		return false
	end
	local snap = ClientState.Snapshot
	if not snap then
		return false
	end
	local data = snap.Data
	local area = Formulas.parseKey(key)
	if area == "Shaft" then
		return station:GetAttribute("Full") ~= true
	elseif area == "Elevator" then
		return snap.ShaftStockAny
	elseif area == "Warehouse" then
		return not BigNum.isZero(BigNum.from(data.Elevator.Stock))
	end
	return false
end

--- Den "Stehlen"-Prompt am eigenen Aufzugslager lokal ausblenden
local function hideOwnStealPrompt(plot: Model?)
	if not plot then
		return
	end
	local prompt = plot:FindFirstChild("StealPrompt", true)
	if prompt and prompt:IsA("ProximityPrompt") and prompt.Enabled then
		prompt.Enabled = false
	end
end

-- Klick auf das "🔒 Ebene X"-Schild öffnet das Freischalten
local connectedUnlock: { [Instance]: boolean } = {}
local function connectUnlockSign(plot: Model?)
	if not plot then
		return
	end
	local click = plot:FindFirstChild("UnlockClick", true)
	if click and click:IsA("ClickDetector") and not connectedUnlock[click] then
		connectedUnlock[click] = true
		click.MouseClick:Connect(function()
			PanelManager.open("Upgrades", "Unlock")
		end)
		click.Destroying:Once(function()
			connectedUnlock[click] = nil
		end)
	end
end

local function sync()
	local plot = PlotLocator.ownPlot()
	hideOwnStealPrompt(plot)
	connectUnlockSign(plot)
	local snap = ClientState.Snapshot
	local wanted: { [string]: boolean } = {}
	if plot and snap then
		for _, key in Formulas.allStationKeys(snap.Data) do
			local station = PlotLocator.station(plot, key)
			if station then
				wanted[key] = true
				local existing = badges[key]
				if existing and existing.Station ~= station then
					existing.Gui:Destroy()
					existing.Hint:Destroy()
					badges[key] = nil
				end
				if not badges[key] then
					local created = makeBadge(key, station)
					if created then
						badges[key] = created
					end
				end
			end
		end
	end
	for key, b in badges do
		if not wanted[key] or not b.Station.Parent then
			b.Gui:Destroy()
			b.Hint:Destroy()
			badges[key] = nil
		end
	end
end

function StationBadges.start()
	container = Instance.new("Folder")
	container.Name = "StationBadges"
	container.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

	ClientState.Changed:Connect(sync)
	task.spawn(function()
		while true do
			task.wait(1)
			sync()
		end
	end)

	RunService.RenderStepped:Connect(function()
		local now = Clock.now()
		local bounce = math.abs(math.sin(os.clock() * 5))
		for key, b in badges do
			local station = b.Station
			local running = station:GetAttribute("Running") == true
			local s = station:GetAttribute("CycleStart")
			local e = station:GetAttribute("CycleEnd")
			if running and type(s) == "number" and type(e) == "number" and e > s then
				b.Fill.Size = UDim2.fromScale(math.clamp((now - s) / (e - s), 0, 1), 1)
			else
				b.Fill.Size = UDim2.fromScale(0, 1)
			end
			local tap = needsTap(key, station)
			b.Hint.Enabled = tap
			if tap then
				b.Hint.StudsOffset = Vector3.new(0, 1 + bounce * 1.2, 0)
			end
		end
	end)
end

return StationBadges

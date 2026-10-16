--!strict
--[[
	PetFollowController
	===================
	Lässt die ausgerüsteten Pets ALLER Spieler hinter ihnen herschweben
	(wie in den großen Pet-Spielen). Rein visuell und nur lokal: der Server
	schreibt die Pet-Ids als Attribut "Pets" an den Spieler.

	Jedes Pet ist eine unsichtbare Part mit BillboardGui: farbige Blase in
	Seltenheitsfarbe + Emoji. Ab Legendär leuchtet das Pet.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Formulas = require(Shared.Formulas)

local Util = require(script.Parent.Parent.UI.Util)

local PetFollowController = {}

local MAX_DISTANCE = 220 -- weiter weg werden Pets nicht bewegt
local SPACING = 3.4

type Follower = { Part: Part, Phase: number }
type Entry = { Signature: string, Followers: { Follower } }

local entries: { [Player]: Entry } = {}
local folder: Folder

local function makeFollower(petId: string, index: number): Follower?
	local def = Formulas.petDef(petId)
	if not def then
		return nil
	end
	local rarity = Formulas.petRarity(def.Rarity)
	local rarityIndex = Formulas.petRarityIndex(def.Rarity)
	local part = Instance.new("Part")
	part.Name = def.Id
	part.Size = Vector3.new(1, 1, 1)
	part.Transparency = 1
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Parent = folder
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromScale(2.8, 2.8)
	gui.LightInfluence = 0
	gui.MaxDistance = 160
	gui.Adornee = part
	gui.Parent = part
	local bubble: Frame = Util.new("Frame", {
		Size = UDim2.fromScale(0.86, 0.86),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = rarity.Color,
		BackgroundTransparency = 0.45,
		Parent = gui,
	}, {
		Util.round(),
		Util.new("UIStroke", { Color = Color3.new(1, 1, 1), Thickness = 2, Transparency = 0.3 }),
	})
	local _ = bubble
	Util.label({
		Size = UDim2.fromScale(1, 1),
		Text = def.Icon,
		TextScaled = true,
		TextSize = 40,
		Parent = gui,
	})
	if rarityIndex >= 5 then
		local light = Instance.new("PointLight")
		light.Color = rarity.Color
		light.Range = 10
		light.Brightness = 1.5
		light.Parent = part
		local sparkle = Instance.new("Sparkles")
		sparkle.SparkleColor = rarity.Color
		sparkle.Parent = part
	end
	return { Part = part, Phase = index * 1.3 }
end

local function clear(entry: Entry)
	for _, f in entry.Followers do
		f.Part:Destroy()
	end
	entry.Followers = {}
end

local function refresh(player: Player)
	local raw = player:GetAttribute("Pets")
	local signature = if type(raw) == "string" then raw else ""
	local entry = entries[player]
	if not entry then
		entry = { Signature = "", Followers = {} }
		entries[player] = entry
	end
	if entry.Signature == signature and #entry.Followers > 0 then
		return
	end
	entry.Signature = signature
	clear(entry)
	local index = 0
	for petId in string.gmatch(signature, "[^,]+") do
		index += 1
		local f = makeFollower(petId, index)
		if f then
			table.insert(entry.Followers, f)
		end
	end
end

--- Platz hinter dem Spieler: Reihen zu je 3 Pets, leicht versetzt
local function slotOffset(i: number, count: number): Vector3
	local row = (i - 1) // 3
	local col = (i - 1) % 3
	local inRow = math.min(3, count - row * 3)
	local x = (col - (inRow - 1) / 2) * SPACING
	return Vector3.new(x, 0, 4.5 + row * SPACING)
end

local function step(dt: number)
	local camera = workspace.CurrentCamera
	local camPos = if camera then camera.CFrame.Position else Vector3.zero
	local t = os.clock()
	local alpha = 1 - math.exp(-dt * 9)
	for player, entry in entries do
		local character = player.Character
		local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
		if root and root:IsA("BasePart") and (root.Position - camPos).Magnitude < MAX_DISTANCE then
			local flat = CFrame.new(root.Position) * CFrame.Angles(0, select(2, root.CFrame:ToEulerAnglesYXZ()), 0)
			for i, f in entry.Followers do
				local offset = slotOffset(i, #entry.Followers)
				local bob = math.sin(t * 3 + f.Phase) * 0.45
				local target = (flat * CFrame.new(offset.X, 0.6 + bob, offset.Z)).Position
				local current = f.Part.Position
				if (current - target).Magnitude > 40 then
					f.Part.CFrame = CFrame.new(target)
				else
					f.Part.CFrame = CFrame.new(current:Lerp(target, alpha))
				end
			end
		end
	end
end

local function watch(player: Player)
	refresh(player)
	player:GetAttributeChangedSignal("Pets"):Connect(function()
		refresh(player)
	end)
end

function PetFollowController.start()
	folder = Instance.new("Folder")
	folder.Name = "PetFollowers"
	folder.Parent = workspace
	Players.PlayerAdded:Connect(watch)
	for _, p in Players:GetPlayers() do
		watch(p)
	end
	Players.PlayerRemoving:Connect(function(player)
		local entry = entries[player]
		if entry then
			clear(entry)
			entries[player] = nil
		end
	end)
	RunService.RenderStepped:Connect(step)
end

return PetFollowController

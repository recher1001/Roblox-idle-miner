--!strict
--[[
	AvatarService
	=============
	Lädt die Freundesliste jedes Spielers und kleidet Kumpel und Manager mit
	den echten Roblox-Avataren der Freunde ein (plus Bauarbeiterhelm).

	  * Freunde werden beim Beitreten im Hintergrund geladen
	  * HumanoidDescriptions/Modelle werden pro UserId gecacht (wenige Web-Calls)
	  * Avatare werden erst als Block-Figur gebaut und dann asynchron ersetzt,
	    die Mine ist also sofort spielbar
	  * Ohne Freunde: eigener Avatar (Config.Avatars.OwnAvatarFallback)
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)

local SessionService = require(script.Parent.SessionService)
local MineBuilder = require(script.Parent.Parent.World.MineBuilder)

type Session = SessionService.Session

export type Friend = { UserId: number, Name: string }

local AvatarService = {}

local CFG = Config.Avatars
local friendsBySession: { [Session]: { Friend } } = {}
local templates: { [number]: Model } = {}
local failed: { [number]: boolean } = {}
local loading: { [number]: boolean } = {}
local activeAvatars = 0

----------------------------------------------------------------------
-- Freunde
----------------------------------------------------------------------
local function loadFriends(session: Session)
	local player = session.Player
	local list: { Friend } = {}
	if CFG.UseFriends then
		local ok, err = pcall(function()
			local pages = Players:GetFriendsAsync(player.UserId)
			while #list < CFG.MaxFriends do
				for _, item in pages:GetCurrentPage() do
					local entry = item :: any
					if type(entry.Id) == "number" then
						table.insert(list, {
							UserId = entry.Id,
							Name = if type(entry.DisplayName) == "string"
								then entry.DisplayName
								else tostring(entry.Username),
						})
					end
					if #list >= CFG.MaxFriends then
						break
					end
				end
				if pages.IsFinished or #list >= CFG.MaxFriends then
					break
				end
				pages:AdvanceToNextPageAsync()
			end
		end)
		if not ok then
			warn("[AvatarService] Freunde konnten nicht geladen werden:", err)
		end
	end
	-- mischen, damit nicht immer dieselben Freunde vorne stehen
	local rng = Random.new(player.UserId)
	for i = #list, 2, -1 do
		local j = rng:NextInteger(1, i)
		list[i], list[j] = list[j], list[i]
	end
	if #list == 0 and CFG.OwnAvatarFallback then
		table.insert(list, { UserId = player.UserId, Name = player.DisplayName })
	end
	friendsBySession[session] = list
end

function AvatarService.friends(session: Session): { Friend }
	return friendsBySession[session] or {}
end

--- Zufälliger Freund, bevorzugt einer, der noch nicht als Manager arbeitet
function AvatarService.pickFriend(session: Session): Friend?
	local list = AvatarService.friends(session)
	if #list == 0 then
		return nil
	end
	local used: { [number]: boolean } = {}
	for _, m in session.Data.Managers do
		if m.FriendUserId then
			used[m.FriendUserId] = true
		end
	end
	local free = {}
	for _, f in list do
		if not used[f.UserId] then
			table.insert(free, f)
		end
	end
	local pool = if #free > 0 then free else list
	return pool[math.random(1, #pool)]
end

--- UserIds für die Kumpel einer Ebene (deterministisch, damit sie nicht wechseln)
function AvatarService.minerIds(session: Session, levelIndex: number, count: number): { number }
	local ids = {}
	if not CFG.Enabled then
		return ids
	end
	local list = AvatarService.friends(session)
	if #list == 0 then
		return ids
	end
	for n = 1, count do
		local idx = ((levelIndex - 1) * 5 + (n - 1)) % #list + 1
		table.insert(ids, list[idx].UserId)
	end
	return ids
end

----------------------------------------------------------------------
-- Avatar-Modelle
----------------------------------------------------------------------
local function buildTemplate(userId: number): Model?
	local ok, result = pcall(function()
		local desc = Players:GetHumanoidDescriptionFromUserId(userId)
		return Players:CreateHumanoidModelFromDescription(desc, Enum.HumanoidRigType.R15)
	end)
	if not ok or not result then
		warn("[AvatarService] Avatar konnte nicht geladen werden:", userId, result)
		return nil
	end
	local model = result :: Model
	for _, d in model:GetDescendants() do
		if d:IsA("LocalScript") or d:IsA("Script") then
			d:Destroy()
		elseif d:IsA("BasePart") then
			d.CanCollide = false
			d.CanTouch = false
			d.CanQuery = false
			d.Massless = true
			d.Anchored = false
		end
	end
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
		humanoid.RequiresNeck = false
		humanoid.BreakJointsOnDeath = false
		pcall(function()
			humanoid.EvaluateStateMachine = false
		end)
	end
	local root = model:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		root.Anchored = true
		root.Transparency = 1
	end
	return model
end

--- Liefert (und cacht) das Avatar-Template einer UserId. Kann warten (Web-Call).
function AvatarService.getTemplate(userId: number): Model?
	if templates[userId] or failed[userId] then
		return templates[userId]
	end
	if loading[userId] then
		local waited = 0
		while loading[userId] and waited < 15 do
			waited += task.wait(0.2)
		end
		return templates[userId]
	end
	loading[userId] = true
	local template = buildTemplate(userId)
	if template then
		templates[userId] = template
	else
		failed[userId] = true
	end
	loading[userId] = nil
	return template
end

--- Ersetzt eine Platzhalter-Figur asynchron durch den Avatar
function AvatarService.dress(figure: Model, userId: number, hatColor: Color3, withPickaxe: boolean)
	if not CFG.Enabled or activeAvatars >= CFG.MaxAvatarsPerServer then
		return
	end
	task.spawn(function()
		local template = AvatarService.getTemplate(userId)
		if not template or not figure.Parent then
			return
		end
		local avatar = MineBuilder.replaceWithAvatar(figure, template, hatColor, withPickaxe)
		if avatar then
			activeAvatars += 1
			avatar.Destroying:Once(function()
				activeAvatars -= 1
			end)
		end
	end)
end

function AvatarService.start()
	SessionService.onStart(5, function(session)
		friendsBySession[session] = {}
		task.spawn(loadFriends, session)
	end)
	SessionService.onEnd(95, function(session)
		friendsBySession[session] = nil
	end)
end

return AvatarService

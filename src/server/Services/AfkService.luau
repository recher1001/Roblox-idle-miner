--!strict
--[[
	AfkService
	==========
	AFK-Zone hinter dem Brunnen: wer mit seinem Charakter in der Zone steht,
	bekommt alle Config.Afk.Interval Sekunden
	  * Config.Afk.Gems Gems
	  * das Offline-Einkommen seiner Minen (wie beim Wiederkommen, also nur
	    Stationen mit Manager) für Config.Afk.IncomeSeconds Sekunden
	Die Position prüft der Server selbst. Für die Anzeige stehen am Spieler
	die Attribute "AfkZone" (boolean), "AfkProgress" (Sekunden) und
	"AfkGems" (in dieser Sitzung verdient).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local BigNum = require(Shared.BigNum)
local Config = require(Shared.Config)

local OfflineService = require(script.Parent.OfflineService)
local SessionService = require(script.Parent.SessionService)
local WorldSetup = require(script.Parent.Parent.World.WorldSetup)

type Session = SessionService.Session

local AfkService = {}

local progress: { [Session]: number } = {}
local earned: { [Session]: number } = {}
local hintShown: { [Session]: boolean } = {}

local function inZone(session: Session): boolean
	local zone = WorldSetup.AfkZone
	local character = session.Player.Character
	if not zone or not character then
		return false
	end
	local root = character:FindFirstChild("HumanoidRootPart")
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not root or not root:IsA("BasePart") or not humanoid or humanoid.Health <= 0 then
		return false
	end
	local offset = root.Position - zone.Center
	return Vector2.new(offset.X, offset.Z).Magnitude <= zone.Radius and offset.Y < 12
end

local function reward(session: Session)
	SessionService.addGems(session, Config.Afk.Gems)
	local amount = OfflineService.compute(session, Config.Afk.IncomeSeconds)
	if not BigNum.isZero(amount) then
		SessionService.addCash(session, amount)
	elseif not hintShown[session] then
		hintShown[session] = true
		SessionService.notify(session.Player, "💤 Tipp: Mit Managern verdienen deine Minen hier auch Geld!", "info")
	end
	earned[session] = (earned[session] or 0) + Config.Afk.Gems
	session.Player:SetAttribute("AfkGems", earned[session])
	SessionService.effect(session.Player, "AfkReward", { Gems = Config.Afk.Gems, Cash = amount })
end

local function tick()
	for _, session in SessionService.all() do
		local player = session.Player
		if inZone(session) then
			local p = (progress[session] or 0) + 1
			if p >= Config.Afk.Interval then
				p = 0
				reward(session)
			end
			progress[session] = p
			player:SetAttribute("AfkZone", true)
			player:SetAttribute("AfkProgress", p)
		elseif progress[session] ~= nil then
			progress[session] = nil
			player:SetAttribute("AfkZone", false)
			player:SetAttribute("AfkProgress", 0)
		end
	end
end

function AfkService.start()
	SessionService.onEnd(10, function(session)
		progress[session] = nil
		earned[session] = nil
		hintShown[session] = nil
	end)
	task.spawn(function()
		while true do
			task.wait(1)
			local ok, err = pcall(function()
				tick()
			end)
			if not ok then
				warn("[AfkService]", err)
			end
		end
	end)
end

return AfkService

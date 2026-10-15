--!strict
--[[
	Net
	===
	Definiert alle Remotes an einer Stelle. Der Server erstellt sie beim Start
	(Net.setupServer), der Client wartet darauf (Net.event / Net.func).

	Client -> Server:
	  Request (RemoteFunction): (action: string, payload: table) -> { ok, msg, ... }
	Server -> Client:
	  Sync             : vollständiger Zustand (Snapshot)
	  Notify           : Toast-Nachricht (text, kind)
	  Effect           : visuelles Feedback (z. B. "+$250" beim Verkauf)
	  OfflineEarnings  : Popup-Daten nach dem Beitreten
	  ManagerReveal    : Ergebnis einer Manager-Einstellung (Reveal-Animation)
	  ServerEvent      : globales Event (Goldrausch) gestartet / beendet
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Net = {}

Net.FolderName = "Remotes"

Net.Events = {
	"Sync",
	"Notify",
	"Effect",
	"OfflineEarnings",
	"ManagerReveal",
	"ServerEvent",
}

Net.Functions = {
	"Request",
}

local folder: Folder? = nil

function Net.setupServer()
	assert(RunService:IsServer(), "Net.setupServer nur auf dem Server")
	local existing = ReplicatedStorage:FindFirstChild(Net.FolderName)
	if existing then
		existing:Destroy()
	end
	local f = Instance.new("Folder")
	f.Name = Net.FolderName
	for _, name in Net.Events do
		local r = Instance.new("RemoteEvent")
		r.Name = name
		r.Parent = f
	end
	for _, name in Net.Functions do
		local r = Instance.new("RemoteFunction")
		r.Name = name
		r.Parent = f
	end
	f.Parent = ReplicatedStorage
	folder = f
end

local function getFolder(): Folder
	if folder then
		return folder
	end
	local f = ReplicatedStorage:WaitForChild(Net.FolderName) :: Folder
	folder = f
	return f
end

function Net.event(name: string): RemoteEvent
	return getFolder():WaitForChild(name) :: RemoteEvent
end

function Net.func(name: string): RemoteFunction
	return getFolder():WaitForChild(name) :: RemoteFunction
end

return Net

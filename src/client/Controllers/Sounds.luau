--!strict
--[[
	Sounds
	======
	Sound-Hooks für die ganze UI. Alle Sounds sind in Config.Sounds definiert
	(eigene IDs dort eintragen). Zusätzlich feuert Sounds.Played, damit eigene
	Systeme (z. B. Musik, Haptik) an jedes Ereignis andocken können.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Signal = require(Shared.Signal)

local Sounds = {}

Sounds.Played = Signal.new() :: Signal.Signal<string>
Sounds.Enabled = true

local cache: { [string]: Sound } = {}

local function getSound(name: string): Sound?
	local id = Config.Sounds[name]
	if not id or id == "" then
		return nil
	end
	local s = cache[name]
	if not s then
		local newSound = Instance.new("Sound")
		newSound.Name = "UI_" .. name
		newSound.SoundId = id
		newSound.Volume = 0.5
		newSound.Parent = SoundService
		cache[name] = newSound
		s = newSound
	end
	return s
end

--- Spielt einen Sound aus Config.Sounds (z. B. "Click", "Purchase", "Coin")
function Sounds.play(name: string, pitch: number?)
	Sounds.Played:Fire(name)
	if not Sounds.Enabled then
		return
	end
	local s = getSound(name)
	if s then
		s.PlaybackSpeed = pitch or 1
		SoundService:PlayLocalSound(s)
	end
end

return Sounds

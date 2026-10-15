--!strict
--[[
	RateLimiter
	===========
	Token-Bucket pro Spieler und Aktion. Jede Aktion verbraucht ein Token;
	Tokens füllen sich mit "Rate" pro Sekunde bis "Burst" wieder auf.
	Schützt vor Remote-Spam (Exploits, Autoclicker-Makros).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared").Config)

type Bucket = { Tokens: number, Last: number }

local RateLimiter = {}

local buckets: { [Player]: { [string]: Bucket } } = {}

--- true = erlaubt, false = zu schnell
function RateLimiter.allow(player: Player, action: string): boolean
	local limits = Config.RateLimits[action] or Config.RateLimits.Default
	local perPlayer = buckets[player]
	if not perPlayer then
		perPlayer = {}
		buckets[player] = perPlayer
	end
	local now = os.clock()
	local bucket = perPlayer[action]
	if not bucket then
		bucket = { Tokens = limits.Burst, Last = now }
		perPlayer[action] = bucket
	end
	bucket.Tokens = math.min(limits.Burst, bucket.Tokens + (now - bucket.Last) * limits.Rate)
	bucket.Last = now
	if bucket.Tokens >= 1 then
		bucket.Tokens -= 1
		return true
	end
	return false
end

function RateLimiter.clear(player: Player)
	buckets[player] = nil
end

return RateLimiter

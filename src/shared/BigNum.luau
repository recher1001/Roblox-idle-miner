--!strict
--[[
	BigNum
	======
	Große Zahlen als Mantisse + Exponent:  wert = m * 10^e   (1 <= |m| < 10, e ganzzahlig)
	Damit sind Werte weit über 1e308 möglich (Exponent ist ein normaler double).

	Alle Funktionen sind "pure": Sie verändern die Eingaben nie und geben neue
	Tabellen zurück. BigNums sind einfache Tabellen {m=..., e=...} und können
	direkt im DataStore gespeichert und über Remotes gesendet werden.

	Beispiel:
		local a = BigNum.new(1500)
		local b = BigNum.mulNum(a, 2.5)
		print(BigNum.format(b)) --> "3.75K"
]]

export type BigNum = { m: number, e: number }

local BigNum = {}

-- Ab diesem Exponent-Unterschied ist die kleinere Zahl bei Addition irrelevant
local PRECISION_DIGITS = 17

local function make(m: number, e: number): BigNum
	return { m = m, e = e }
end

local function isFinite(n: number): boolean
	return n == n and n ~= math.huge and n ~= -math.huge
end

--- Normalisiert Mantisse/Exponent. Ungültige Werte (NaN/Inf) werden zu 0.
function BigNum.normalize(m: number, e: number): BigNum
	if m == 0 or not isFinite(m) or not isFinite(e) then
		return make(0, 0)
	end
	-- Nachkommaanteil des Exponenten in die Mantisse verschieben
	local eInt = math.floor(e)
	if eInt ~= e then
		m *= 10 ^ (e - eInt)
		e = eInt
	end
	local absM = math.abs(m)
	local shift = math.floor(math.log10(absM))
	if shift ~= 0 then
		m /= 10 ^ shift
		e += shift
	end
	-- Rundungsfehler von log10 korrigieren
	absM = math.abs(m)
	if absM >= 10 then
		m /= 10
		e += 1
	elseif absM < 1 then
		m *= 10
		e -= 1
	end
	return make(m, e)
end

function BigNum.new(n: number): BigNum
	return BigNum.normalize(n, 0)
end

function BigNum.fromParts(m: number, e: number): BigNum
	return BigNum.normalize(m, e)
end

function BigNum.zero(): BigNum
	return make(0, 0)
end

function BigNum.one(): BigNum
	return make(1, 0)
end

--- Liest einen beliebigen Wert (z. B. aus dem DataStore) sicher als BigNum.
function BigNum.from(value: any): BigNum
	if type(value) == "number" then
		return BigNum.new(value)
	elseif type(value) == "table" then
		local m = value.m
		local e = value.e
		if type(m) == "number" and type(e) == "number" then
			return BigNum.normalize(m, e)
		end
	end
	return make(0, 0)
end

--- Kopie für die Speicherung (nur m/e, keine fremden Felder)
function BigNum.serialize(a: BigNum): BigNum
	return make(a.m, a.e)
end

function BigNum.isZero(a: BigNum): boolean
	return a.m == 0
end

function BigNum.isNegative(a: BigNum): boolean
	return a.m < 0
end

function BigNum.neg(a: BigNum): BigNum
	return make(-a.m, a.e)
end

function BigNum.abs(a: BigNum): BigNum
	return make(math.abs(a.m), a.e)
end

function BigNum.add(a: BigNum, b: BigNum): BigNum
	if a.m == 0 then
		return b
	elseif b.m == 0 then
		return a
	end
	local diff = a.e - b.e
	if diff > PRECISION_DIGITS then
		return a
	elseif diff < -PRECISION_DIGITS then
		return b
	end
	if diff >= 0 then
		return BigNum.normalize(a.m + b.m / 10 ^ diff, a.e)
	else
		return BigNum.normalize(a.m / 10 ^ -diff + b.m, b.e)
	end
end

function BigNum.sub(a: BigNum, b: BigNum): BigNum
	return BigNum.add(a, make(-b.m, b.e))
end

function BigNum.mul(a: BigNum, b: BigNum): BigNum
	if a.m == 0 or b.m == 0 then
		return make(0, 0)
	end
	return BigNum.normalize(a.m * b.m, a.e + b.e)
end

function BigNum.mulNum(a: BigNum, n: number): BigNum
	return BigNum.mul(a, BigNum.new(n))
end

function BigNum.div(a: BigNum, b: BigNum): BigNum
	if b.m == 0 then
		return make(0, 0)
	end
	return BigNum.normalize(a.m / b.m, a.e - b.e)
end

function BigNum.divNum(a: BigNum, n: number): BigNum
	return BigNum.div(a, BigNum.new(n))
end

--- log10 einer positiven Zahl (für 0 oder negative: -inf)
function BigNum.log10(a: BigNum): number
	if a.m <= 0 then
		return -math.huge
	end
	return math.log10(a.m) + a.e
end

function BigNum.fromLog10(l: number): BigNum
	if not isFinite(l) then
		return make(0, 0)
	end
	local e = math.floor(l)
	return BigNum.normalize(10 ^ (l - e), e)
end

--- a ^ p (nur für positive a sinnvoll)
function BigNum.pow(a: BigNum, p: number): BigNum
	if p == 0 then
		return make(1, 0)
	end
	if a.m <= 0 then
		return make(0, 0)
	end
	return BigNum.fromLog10(BigNum.log10(a) * p)
end

--- base ^ p für normale Zahlen, ohne Overflow
function BigNum.powNum(base: number, p: number): BigNum
	if p == 0 then
		return make(1, 0)
	end
	if base <= 0 then
		return make(0, 0)
	end
	return BigNum.fromLog10(math.log10(base) * p)
end

--- -1 wenn a < b, 0 wenn gleich, 1 wenn a > b
function BigNum.compare(a: BigNum, b: BigNum): number
	if a.m == 0 and b.m == 0 then
		return 0
	end
	local signA = if a.m > 0 then 1 elseif a.m < 0 then -1 else 0
	local signB = if b.m > 0 then 1 elseif b.m < 0 then -1 else 0
	if signA ~= signB then
		return if signA > signB then 1 else -1
	end
	-- gleiches Vorzeichen (nicht 0)
	local result: number
	if a.e ~= b.e then
		result = if a.e > b.e then 1 else -1
	elseif a.m ~= b.m then
		result = if math.abs(a.m) > math.abs(b.m) then 1 else -1
	else
		return 0
	end
	return result * signA
end

function BigNum.lt(a: BigNum, b: BigNum): boolean
	return BigNum.compare(a, b) < 0
end

function BigNum.lte(a: BigNum, b: BigNum): boolean
	return BigNum.compare(a, b) <= 0
end

function BigNum.gt(a: BigNum, b: BigNum): boolean
	return BigNum.compare(a, b) > 0
end

function BigNum.gte(a: BigNum, b: BigNum): boolean
	return BigNum.compare(a, b) >= 0
end

function BigNum.eq(a: BigNum, b: BigNum): boolean
	return BigNum.compare(a, b) == 0
end

function BigNum.max(a: BigNum, b: BigNum): BigNum
	return if BigNum.compare(a, b) >= 0 then a else b
end

function BigNum.min(a: BigNum, b: BigNum): BigNum
	return if BigNum.compare(a, b) <= 0 then a else b
end

--- Begrenzt auf >= 0
function BigNum.clampPositive(a: BigNum): BigNum
	if a.m < 0 then
		return make(0, 0)
	end
	return a
end

--- Abrunden auf ganze Zahlen (nur relevant für kleine Werte)
function BigNum.floor(a: BigNum): BigNum
	if a.e >= 15 then
		return a
	end
	return BigNum.new(math.floor(a.m * 10 ^ a.e))
end

--- In normale Zahl umwandeln (kann math.huge ergeben)
function BigNum.toNumber(a: BigNum): number
	if a.m == 0 then
		return 0
	end
	if a.e > 308 then
		return if a.m > 0 then math.huge else -math.huge
	end
	return a.m * 10 ^ a.e
end

--- Lineare Interpolation (für hochzählende Animationen)
function BigNum.lerp(a: BigNum, b: BigNum, t: number): BigNum
	if t <= 0 then
		return a
	elseif t >= 1 then
		return b
	end
	return BigNum.add(a, BigNum.mulNum(BigNum.sub(b, a), t))
end

----------------------------------------------------------------------
-- Formatierung
----------------------------------------------------------------------
local SUFFIXES = {
	"",
	"K",
	"M",
	"B",
	"T",
	"Qa",
	"Qi",
	"Sx",
	"Sp",
	"Oc",
	"No",
	"Dc",
	"Ud",
	"Dd",
	"Td",
	"Qad",
	"Qid",
	"Sxd",
	"Spd",
	"Ocd",
	"Nod",
	"Vg",
}
local ALPHABET = "abcdefghijklmnopqrstuvwxyz"

local function suffixFor(group: number): string?
	if group < #SUFFIXES then
		return SUFFIXES[group + 1]
	end
	-- danach: aa, ab, ac ... zz
	local idx = group - #SUFFIXES
	if idx >= 26 * 26 then
		return nil
	end
	local first = idx // 26 + 1
	local second = idx % 26 + 1
	return string.sub(ALPHABET, first, first) .. string.sub(ALPHABET, second, second)
end

local function trimZeros(s: string): string
	if string.find(s, "%.") then
		s = string.gsub(s, "0+$", "")
		s = string.gsub(s, "%.$", "")
	end
	return s
end

local function truncTo(value: number, decimals: number): number
	local f = 10 ^ decimals
	-- kleines Epsilon gegen 2.9999999 -> 2.99
	return math.floor(value * f + 1e-6) / f
end

--- Formatiert wie 1.5K, 23.4M, 412B, 1.2aa
function BigNum.format(a: BigNum): string
	if a.m == 0 then
		return "0"
	end
	local sign = if a.m < 0 then "-" else ""
	local m = math.abs(a.m)
	local e = a.e
	if e < 3 then
		local value = m * 10 ^ e
		if value < 10 and math.floor(value) ~= value then
			return sign .. trimZeros(string.format("%.2f", truncTo(value, 2)))
		elseif value < 100 and math.floor(value) ~= value then
			return sign .. trimZeros(string.format("%.1f", truncTo(value, 1)))
		end
		return sign .. tostring(math.floor(value + 1e-6))
	end
	local group = e // 3
	local suffix = suffixFor(group)
	if suffix == nil then
		return sign .. string.format("%.2fe%d", truncTo(m, 2), e)
	end
	local display = m * 10 ^ (e % 3)
	local decimals = if display < 10 then 2 elseif display < 100 then 1 else 0
	local text = string.format("%." .. decimals .. "f", truncTo(display, decimals))
	return sign .. trimZeros(text) .. suffix
end

--- Wie format, aber mit Währungssymbol
function BigNum.formatMoney(a: BigNum, symbol: string?): string
	local s = symbol or "$"
	if a.m < 0 then
		return "-" .. s .. BigNum.format(BigNum.abs(a))
	end
	return s .. BigNum.format(a)
end

return BigNum

--!strict
--[[
	Anim
	====
	Dauer-Animationen für den bunten Look - alle in EINER RenderStepped-Schleife
	(performant, auch bei vielen Elementen):
	  rotate(gradient, speed)  - Farbverlauf dreht sich (z. B. Regenbogen-Rand)
	  shine(gui)               - heller Glanzstreifen läuft regelmäßig über ein Element
	  pulse(scale, amount)     - sanftes Pulsieren (Aufmerksamkeit)
]]

local RunService = game:GetService("RunService")

local Util = require(script.Parent.Util)

local Anim = {}

local rotators: { [UIGradient]: number } = {}
type Shine = { Gradient: UIGradient, Period: number, Phase: number }
local shines: { [UIGradient]: Shine } = {}
type Pulse = { Scale: UIScale, Amount: number, Speed: number, Phase: number }
local pulses: { [UIScale]: Pulse } = {}

local started = false
local function ensureLoop()
	if started then
		return
	end
	started = true
	RunService.RenderStepped:Connect(function(dt)
		local t = os.clock()
		for g, speed in rotators do
			if g.Parent then
				g.Rotation = (g.Rotation + speed * dt) % 360
			else
				rotators[g] = nil
			end
		end
		for g, s in shines do
			if g.Parent then
				-- Streifen läuft in 0.7s durch, dann Pause bis zum nächsten Durchlauf
				local cycle = ((t + s.Phase) % s.Period) / 0.7
				g.Offset = Vector2.new(if cycle <= 1 then -1.2 + cycle * 2.4 else 1.5, 0)
			else
				shines[g] = nil
			end
		end
		for sc, p in pulses do
			if sc.Parent then
				sc.Scale = 1 + p.Amount * (0.5 + 0.5 * math.sin((t + p.Phase) * p.Speed))
			else
				pulses[sc] = nil
			end
		end
	end)
end

function Anim.rotate(gradient: UIGradient, speed: number)
	ensureLoop()
	rotators[gradient] = speed
end

--- Legt einen Glanzstreifen über ein GUI-Element (gleiche Eckenrundung)
function Anim.shine(gui: GuiObject, cornerRadius: number?, period: number?): Frame
	ensureLoop()
	local gradient: UIGradient = Util.new("UIGradient", {
		Rotation = 20,
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.42, 1),
			NumberSequenceKeypoint.new(0.5, 0.45),
			NumberSequenceKeypoint.new(0.58, 1),
			NumberSequenceKeypoint.new(1, 1),
		}),
		Offset = Vector2.new(-1.5, 0),
	})
	local frame: Frame = Util.new("Frame", {
		Name = "ShineSweep",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BackgroundTransparency = 0,
		ZIndex = gui.ZIndex + 1,
		Active = false,
		Parent = gui,
	}, {
		Util.new("UICorner", { CornerRadius = UDim.new(0, cornerRadius or 14) }),
		gradient,
	})
	shines[gradient] = { Gradient = gradient, Period = period or 3.2, Phase = math.random() * 3 }
	return frame
end

function Anim.pulse(scale: UIScale, amount: number?, speed: number?)
	ensureLoop()
	pulses[scale] = { Scale = scale, Amount = amount or 0.05, Speed = speed or 4, Phase = math.random() * 3 }
end

function Anim.stopPulse(scale: UIScale)
	pulses[scale] = nil
	scale.Scale = 1
end

return Anim

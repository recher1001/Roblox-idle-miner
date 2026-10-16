--!strict
--[[
	PetVisuals
	==========
	Gemeinsame Bausteine für Pets und Eier (Eier-Menü, Schlüpf-Animation,
	Handel, Admin-Menü):
	  egg()      - gezeichnetes Ei in der Farbe des Eis (mit Punkten + Glanz)
	  petTile()  - Pet-Kachel mit Seltenheits-Verlauf, Emoji und Rand
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Formulas = require(Shared.Formulas)

local Theme = require(script.Parent.Theme)
local Util = require(script.Parent.Util)

local PetVisuals = {}

--- Gezeichnetes Ei. size = Höhe, Breite ist 78 % davon.
function PetVisuals.egg(props: { [string]: any }, color: Color3, height: number): Frame
	local defaults: { [string]: any } = {
		Size = UDim2.fromOffset(math.floor(height * 0.78), height),
		BackgroundColor3 = Color3.new(1, 1, 1),
	}
	for k, v in props do
		defaults[k] = v
	end
	local egg: Frame = Util.new("Frame", defaults, {
		Util.new("UICorner", { CornerRadius = UDim.new(0.5, 0) }),
		Util.gradient(Theme.lighten(color, 0.35), Theme.darken(color, 0.3)),
		Util.stroke(Color3.new(1, 1, 1), math.max(2, height / 30)),
	})
	-- Punkte
	local spots = {
		{ 0.3, 0.42, 0.16 },
		{ 0.66, 0.55, 0.12 },
		{ 0.42, 0.72, 0.1 },
	}
	for _, s in spots do
		Util.new("Frame", {
			Size = UDim2.fromScale(s[3], s[3] * 0.78),
			Position = UDim2.fromScale(s[1], s[2]),
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundColor3 = Theme.lighten(color, 0.65),
			BackgroundTransparency = 0.15,
			Parent = egg,
		}, { Util.round() })
	end
	-- Glanzpunkt oben links
	Util.new("Frame", {
		Size = UDim2.fromScale(0.18, 0.1),
		Position = UDim2.fromScale(0.3, 0.18),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Rotation = -30,
		BackgroundColor3 = Color3.new(1, 1, 1),
		BackgroundTransparency = 0.35,
		Parent = egg,
	}, { Util.round() })
	return egg
end

--- Kachel mit Pet-Emoji in Seltenheitsfarbe
function PetVisuals.petTile(props: { [string]: any }, petId: string, iconSize: number): Frame
	local def = Formulas.petDef(petId)
	local rarity = Formulas.petRarity(if def then def.Rarity else "Common")
	local defaults: { [string]: any } = {
		BackgroundColor3 = Color3.new(1, 1, 1),
	}
	for k, v in props do
		defaults[k] = v
	end
	local tile: Frame = Util.new("Frame", defaults, {
		Util.corner(Theme.Radius.Medium),
		Util.gradient(Theme.lighten(rarity.Color, 0.25), Theme.darken(rarity.Color, 0.45)),
		Util.stroke(Theme.lighten(rarity.Color, 0.5), 2.5),
	})
	Util.label({
		Name = "Icon",
		Size = UDim2.new(1, 0, 0, iconSize + 8),
		Position = UDim2.fromOffset(0, 4),
		Text = if def then def.Icon else "❓",
		TextSize = iconSize,
		Parent = tile,
	})
	return tile
end

return PetVisuals

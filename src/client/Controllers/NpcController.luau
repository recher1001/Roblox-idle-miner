--!strict
--[[
	NpcController
	=============
	ProximityPrompts mit dem Attribut "OpenPanel" öffnen auf dem Client das
	passende Menü (z. B. der Händler am Shop-Stand -> Shop).
]]

local ProximityPromptService = game:GetService("ProximityPromptService")

local PanelManager = require(script.Parent.Parent.UI.PanelManager)
local Sounds = require(script.Parent.Sounds)

local NpcController = {}

function NpcController.start()
	ProximityPromptService.PromptTriggered:Connect(function(prompt: ProximityPrompt)
		local panel = prompt:GetAttribute("OpenPanel")
		if type(panel) == "string" then
			Sounds.play("Click")
			PanelManager.open(panel)
		end
	end)
end

return NpcController

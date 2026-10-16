--!strict
--[[
	PromptController
	================
	Blendet ProximityPrompts lokal aus, die für diesen Spieler keinen Sinn
	ergeben:
	  * "StealOwner" = eigene UserId -> eigene Manager/Lager kann man nicht klauen
	  * "OwnerOnly"  = fremde UserId -> Schutz-Knopf einer fremden Basis
	Der Server prüft trotzdem alles - das hier ist nur für die Übersicht.
]]

local Players = game:GetService("Players")

local PromptController = {}

local hooked: { [ProximityPrompt]: boolean } = {}

local function shouldHide(prompt: ProximityPrompt): boolean
	local me = Players.LocalPlayer.UserId
	local stealOwner = prompt:GetAttribute("StealOwner")
	if stealOwner == me then
		return true
	end
	local ownerOnly = prompt:GetAttribute("OwnerOnly")
	return type(ownerOnly) == "number" and ownerOnly ~= me
end

local function apply(prompt: ProximityPrompt)
	if shouldHide(prompt) and prompt.Enabled then
		prompt.Enabled = false
	end
end

local function hook(inst: Instance)
	if not inst:IsA("ProximityPrompt") or hooked[inst] then
		return
	end
	local prompt = inst :: ProximityPrompt
	hooked[prompt] = true
	apply(prompt)
	-- der Server kann Enabled wieder einschalten (z. B. nach dem Abschließen)
	prompt:GetPropertyChangedSignal("Enabled"):Connect(function()
		apply(prompt)
	end)
	prompt.AttributeChanged:Connect(function()
		apply(prompt)
	end)
	prompt.Destroying:Connect(function()
		hooked[prompt] = nil
	end)
end

function PromptController.start()
	task.spawn(function()
		local plots = workspace:WaitForChild("Plots", 30)
		if not plots then
			return
		end
		for _, d in plots:GetDescendants() do
			hook(d)
		end
		plots.DescendantAdded:Connect(hook)
	end)
end

return PromptController

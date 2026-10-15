--!strict
--[[
	CarpetController
	================
	Fliegender Teppich (Admin-Kraft "Carpet"):
	  * Button "🧞 Teppich" erscheint, wenn du die Kraft hast
	  * Der Server baut den Teppich (für alle sichtbar), der Client fliegt:
	    Laufen = Richtung, Leertaste/E bzw. ▲ = hoch, Q/Strg bzw. ▼ = runter
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage:WaitForChild("Shared").Config)

local ClientState = require(script.Parent.Parent.ClientState)
local Remote = require(script.Parent.Parent.Remote)
local Components = require(script.Parent.Parent.UI.Components)
local Root = require(script.Parent.Parent.UI.Root)
local Theme = require(script.Parent.Parent.UI.Theme)
local Util = require(script.Parent.Parent.UI.Util)

local CarpetController = {}

local player = Players.LocalPlayer
local controls: any = nil
local toggleButton: Components.Button
local flyButtons: Frame
local upHeld = false
local downHeld = false

type Movers = { Attachment: Attachment, Velocity: LinearVelocity, Align: AlignOrientation }
local movers: Movers? = nil

local function getControls(): any
	if controls then
		return controls
	end
	local ok, result = pcall(function()
		local playerModule = player:WaitForChild("PlayerScripts"):WaitForChild("PlayerModule", 5)
		return (require :: any)(playerModule):GetControls()
	end)
	if ok then
		controls = result
	end
	return controls
end

local function stopFlying()
	if movers then
		movers.Velocity:Destroy()
		movers.Align:Destroy()
		movers.Attachment:Destroy()
		movers = nil
	end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.PlatformStand = false
	end
	flyButtons.Visible = false
end

local function startFlying()
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not root or not root:IsA("BasePart") or not humanoid or movers then
		return
	end
	local attachment = Instance.new("Attachment")
	attachment.Name = "CarpetAttachment"
	attachment.Parent = root
	local velocity = Instance.new("LinearVelocity")
	velocity.Attachment0 = attachment
	velocity.MaxForce = math.huge
	velocity.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector
	velocity.RelativeTo = Enum.ActuatorRelativeTo.World
	velocity.VectorVelocity = Vector3.zero
	velocity.Parent = root
	local align = Instance.new("AlignOrientation")
	align.Mode = Enum.OrientationAlignmentMode.OneAttachment
	align.Attachment0 = attachment
	align.MaxTorque = math.huge
	align.Responsiveness = 25
	align.CFrame = root.CFrame.Rotation
	align.Parent = root
	movers = { Attachment = attachment, Velocity = velocity, Align = align }
	humanoid.PlatformStand = true
	flyButtons.Visible = true
end

local function holdButton(text: string, order: number, setter: (boolean) -> ())
	local b = Components.button({
		Text = text,
		Color = Theme.Colors.Purple,
		Size = UDim2.fromOffset(84, 74),
		TextSize = 32,
		LayoutOrder = order,
		Parent = flyButtons,
	})
	b.Instance.MouseButton1Down:Connect(function()
		setter(true)
	end)
	b.Instance.MouseButton1Up:Connect(function()
		setter(false)
	end)
	b.Instance.MouseLeave:Connect(function()
		setter(false)
	end)
end

function CarpetController.start()
	toggleButton = Components.button({
		Text = "🧞 Teppich",
		Color = Theme.Colors.Purple,
		Size = UDim2.fromOffset(186, 62),
		Position = UDim2.new(1, -14, 0.5, 120),
		AnchorPoint = Vector2.new(1, 0),
		TextSize = 20,
		Parent = Root.layer("Hud"),
		OnClick = function()
			Remote.send("ToggleCarpet")
		end,
	})
	toggleButton.Instance.Visible = false

	flyButtons = Util.new("Frame", {
		Name = "FlyButtons",
		Size = UDim2.fromOffset(90, 160),
		Position = UDim2.new(1, -214, 0.5, 120),
		AnchorPoint = Vector2.new(1, 0),
		BackgroundTransparency = 1,
		Visible = false,
		Parent = Root.layer("Hud"),
	}, { Util.list(Enum.FillDirection.Vertical, 10) })
	holdButton("▲", 1, function(v)
		upHeld = v
	end)
	holdButton("▼", 2, function(v)
		downHeld = v
	end)

	ClientState.Changed:Connect(function(snap)
		local has = snap.Data.Powers ~= nil and snap.Data.Powers.Carpet == true
		toggleButton.Instance.Visible = has
	end)
	player.CharacterAdded:Connect(function()
		stopFlying()
	end)

	RunService.RenderStepped:Connect(function()
		local character = player.Character
		local active = character ~= nil and character:GetAttribute("CarpetActive") == true
		if active and not movers then
			startFlying()
		elseif not active and movers then
			stopFlying()
		end
		toggleButton.SetText(if active then "🧞 Landen" else "🧞 Teppich")
		local m = movers
		local camera = workspace.CurrentCamera
		if not m or not camera then
			return
		end
		local move = Vector3.zero
		local c = getControls()
		if c then
			local ok, vec = pcall(function()
				return c:GetMoveVector()
			end)
			if ok and typeof(vec) == "Vector3" then
				move = vec
			end
		end
		local look = camera.CFrame.LookVector * Vector3.new(1, 0, 1)
		local right = camera.CFrame.RightVector * Vector3.new(1, 0, 1)
		if look.Magnitude < 0.01 then
			look = Vector3.new(0, 0, -1)
		end
		look = look.Unit
		right = if right.Magnitude > 0.01 then right.Unit else Vector3.new(1, 0, 0)
		local dir = right * move.X + look * -move.Z
		local vertical = 0
		if upHeld or UserInputService:IsKeyDown(Enum.KeyCode.Space) or UserInputService:IsKeyDown(Enum.KeyCode.E) then
			vertical += 1
		end
		if
			downHeld
			or UserInputService:IsKeyDown(Enum.KeyCode.Q)
			or UserInputService:IsKeyDown(Enum.KeyCode.LeftControl)
		then
			vertical -= 1
		end
		local speed = Config.Admin.CarpetSpeed
		m.Velocity.VectorVelocity = dir * speed + Vector3.new(0, vertical * speed * 0.7, 0)
		local facing = if dir.Magnitude > 0.1 then dir.Unit else look
		m.Align.CFrame = CFrame.lookAt(Vector3.zero, facing)
	end)
end

return CarpetController

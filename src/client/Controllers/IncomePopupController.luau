--!strict
-- Server income ticks drive these transient world labels. Never extrapolate
-- payments locally, replay old ticks on stream-in, or change the economy.
local CollectionService = game:GetService("CollectionService")
local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Format = require(Shared.Util.Format)
local Theme = require(Shared.Theme)
local player = Players.LocalPlayer

local Controller = {}
local connections: { [Instance]: RBXScriptConnection } = {}
local LIFETIME = 1.15
local MAX_DISTANCE = 85

local function popup(pedestal: BasePart, amount: number, rarity: string)
	local camera = workspace.CurrentCamera
	if not camera or player:GetAttribute("ArenaActive") or player:GetAttribute("MenuOpen") then
		return
	end
	if (camera.CFrame.Position - pedestal.Position).Magnitude > MAX_DISTANCE then
		return
	end
	local slot = (pedestal:GetAttribute("Slot") :: number?) or 1
	local side = if slot % 2 == 0 then 1 else -1
	local gui = Instance.new("BillboardGui")
	gui.Name, gui.Adornee, gui.ResetOnSpawn = "StardustPopup", pedestal, false
	gui.Size = UDim2.fromOffset(126, 32)
	gui.StudsOffsetWorldSpace = Vector3.new(side * 0.15, 9.45, 0)
	gui.MaxDistance, gui.LightInfluence, gui.AlwaysOnTop = MAX_DISTANCE, 0, false
	local colors = Theme.RARITY_COLORS :: { [string]: Color3 }
	local icon = Instance.new("Frame")
	icon.Name, icon.Size, icon.BackgroundTransparency = "Star", UDim2.fromScale(0.22, 1), 1
	icon.Parent = gui
	local dust: { Frame } = {}
	for _, spec in
		{
			{ size = 13, pos = Vector2.new(0.45, 0.55) },
			{ size = 4, pos = Vector2.new(0.85, 0.22) },
			{ size = 3, pos = Vector2.new(0.08, 0.15) },
		}
	do
		local crystal = Instance.new("Frame")
		crystal.AnchorPoint, crystal.Position =
			Vector2.new(0.5, 0.5), UDim2.fromScale(spec.pos.X, spec.pos.Y)
		crystal.Size, crystal.Rotation = UDim2.fromOffset(spec.size, spec.size), 45
		crystal.BackgroundColor3 = colors[rarity] or Color3.fromRGB(255, 220, 95)
		crystal.BackgroundTransparency, crystal.BorderSizePixel = 1, 0
		crystal.Parent = icon
		table.insert(dust, crystal)
	end
	local label = Instance.new("TextLabel")
	label.Name, label.Position, label.Size =
		"Amount", UDim2.fromScale(0.22, 0), UDim2.fromScale(0.78, 1)
	label.BackgroundTransparency, label.TextScaled, label.AutoLocalize = 1, true, false
	label.Font, label.TextColor3 = Enum.Font.GothamBold, Color3.fromRGB(255, 232, 145)
	label.TextStrokeTransparency, label.TextTransparency = 0.35, 1
	label.Text = `+{Format.amount(amount)}`
	label.Parent = gui
	gui:SetAttribute("Amount", amount)
	gui.Parent = player:WaitForChild("PlayerGui")
	TweenService
		:Create(gui, TweenInfo.new(LIFETIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			StudsOffsetWorldSpace = Vector3.new(side * 0.5, 11.65, 0),
		})
		:Play()
	TweenService:Create(label, TweenInfo.new(0.12), { TextTransparency = 0 }):Play()
	for _, crystal in dust do
		TweenService:Create(crystal, TweenInfo.new(0.12), { BackgroundTransparency = 0 }):Play()
	end
	task.delay(0.65, function()
		if not gui.Parent then
			return
		end
		TweenService
			:Create(label, TweenInfo.new(0.4), { TextTransparency = 1, TextStrokeTransparency = 1 })
			:Play()
		for _, crystal in dust do
			TweenService:Create(crystal, TweenInfo.new(0.4), { BackgroundTransparency = 1 }):Play()
		end
	end)
	Debris:AddItem(gui, LIFETIME)
end

local function watch(instance: Instance)
	if not instance:IsA("BasePart") or connections[instance] then
		return
	end
	connections[instance] = instance:GetAttributeChangedSignal("IncomePulseAt"):Connect(function()
		local at = instance:GetAttribute("IncomePulseAt") :: number?
		local amount = instance:GetAttribute("IncomePulseAmount") :: number?
		local rarity = instance:GetAttribute("IncomePulseRarity") :: string?
		if not at or not amount or amount <= 0 or not rarity then
			return
		end
		if workspace:GetServerTimeNow() - at > 0.8 then
			return
		end
		local slot = (instance:GetAttribute("Slot") :: number?) or 1
		-- Stagger the capsules slightly so their income doesn't blink in unison.
		local delay = ((slot - 1) % 5) * 0.065 + ((slot - 1) // 5) * 0.05
		task.delay(delay, function()
			if not instance:IsDescendantOf(workspace) then
				return
			end
			if
				instance:GetAttribute("IncomePulseAt") ~= at
				or not instance:GetAttribute("Occupied")
			then
				return
			end
			popup(instance, amount, rarity)
		end)
	end)
end

function Controller.start()
	CollectionService:GetInstanceAddedSignal("CryoCapsule"):Connect(watch)
	CollectionService:GetInstanceRemovedSignal("CryoCapsule"):Connect(function(instance)
		local connection = connections[instance]
		if connection then
			connection:Disconnect()
			connections[instance] = nil
		end
	end)
	for _, instance in CollectionService:GetTagged("CryoCapsule") do
		watch(instance)
	end
end

return Controller

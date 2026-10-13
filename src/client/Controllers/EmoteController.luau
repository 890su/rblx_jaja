--!strict
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Locale = require(Shared.Locale)
local Remotes = require(Shared.Remotes)
local UiKit = require(script.Parent.Parent.Lib.UiKit)
local player = Players.LocalPlayer
local EmoteController = {}

local function request()
	Remotes.event("RequestEmote")
		:FireServer(if player:GetAttribute("EmoteKey") then "stop" else "wave")
end

function EmoteController.init()
	local button = UiKit.button(UiKit.gui(), Locale.t("emote_wave"), {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -12),
		Size = UDim2.new(0.18, 0, 0, 44),
		BackgroundColor3 = Color3.fromRGB(60, 150, 170),
	})
	local size = Instance.new("UISizeConstraint")
	size.MinSize, size.MaxSize = Vector2.new(112, 44), Vector2.new(180, 44)
	size.Parent = button
	local textSize = Instance.new("UITextSizeConstraint")
	textSize.MinTextSize, textSize.MaxTextSize = 12, 20
	textSize.Parent = button
	button.Activated:Connect(request)
	button.Name = "EmoteWave"
	local function refresh()
		button.Text = Locale.t(
			if player:GetAttribute("EmoteKey")
				then "emote_stop"
				elseif
					UserInputService.KeyboardEnabled and not UserInputService.TouchEnabled
				then "emote_wave_keyboard"
				else "emote_wave"
		)
		local unavailable = player:GetAttribute("Carrying") ~= nil
			or player:GetAttribute("OnTreadmill") == true
			or player:GetAttribute("ArenaActive") == true
			or player:GetAttribute("ArenaPrep") == true
		button.Active = not unavailable
		button.AutoButtonColor = not unavailable
		button.BackgroundColor3 = if unavailable
			then UiKit.DISABLED_COLOR
			else Color3.fromRGB(60, 150, 170)
	end
	for _, attribute in { "EmoteKey", "Carrying", "OnTreadmill", "ArenaActive", "ArenaPrep" } do
		player:GetAttributeChangedSignal(attribute):Connect(refresh)
	end
	refresh()
	UserInputService:GetPropertyChangedSignal("TouchEnabled"):Connect(refresh)
	UserInputService:GetPropertyChangedSignal("KeyboardEnabled"):Connect(refresh)
	UserInputService.InputBegan:Connect(function(input, processed)
		if
			not processed
			and input.KeyCode == Enum.KeyCode.G
			and not UserInputService:GetFocusedTextBox()
		then
			request()
		end
	end)
	local cancelledStart: number? = nil
	RunService.PreSimulation:Connect(function()
		local at = player:GetAttribute("EmoteStartedAt")
		if player:GetAttribute("EmoteKey") ~= "wave" or typeof(at) ~= "number" then
			cancelledStart = nil
			return
		end
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if humanoid and humanoid.MoveDirection.Magnitude > 0.05 and cancelledStart ~= at then
			cancelledStart = at
			Remotes.event("RequestEmote"):FireServer("stop")
		end
	end)
end

return EmoteController

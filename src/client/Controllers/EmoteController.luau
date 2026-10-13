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
	local button =
		UiKit.sideButton(Locale.t("emote_wave"), Color3.fromRGB(60, 150, 170), 8, request)
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
		UiKit.setEnabled(button, not unavailable)
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

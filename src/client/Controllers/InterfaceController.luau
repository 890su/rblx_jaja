--!strict
-- Remove optional Roblox widgets; leave system menu and movement controls.
local StarterGui = game:GetService("StarterGui")
local TextChatService = game:GetService("TextChatService")
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Locale = require(Shared.Locale)
local UiKit = require(script.Parent.Parent.Lib.UiKit)
local Controller = {}
local chatEnabled = false
local function applyChat()
	for _, name in
		{
			"ChatWindowConfiguration",
			"ChatInputBarConfiguration",
			"BubbleChatConfiguration",
		}
	do
		local config = TextChatService:FindFirstChild(name)
		if config then
			(config :: any).Enabled = chatEnabled
		end
	end
	local tabs = TextChatService:FindFirstChild("ChannelTabsConfiguration")
	if tabs then
		(tabs :: any).Enabled = false
	end
	StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Chat, chatEnabled)
end
function Controller.init()
	local button: TextButton
	button = UiKit.sideButton(Locale.term("Chat"), Color3.fromRGB(65, 85, 125), 9, function()
		chatEnabled = not chatEnabled
		local ok = pcall(applyChat)
		if not ok then
			chatEnabled = false
			pcall(applyChat)
		end
		button.Text = Locale.term(if chatEnabled then "Hide chat" else "Chat")
	end)
end
function Controller.start()
	for attempt = 1, 5 do
		local ok = pcall(function()
			applyChat()
			for _, kind in
				{
					Enum.CoreGuiType.PlayerList,
					Enum.CoreGuiType.Backpack,
					Enum.CoreGuiType.EmotesMenu,
					Enum.CoreGuiType.Health,
				}
			do
				StarterGui:SetCoreGuiEnabled(kind, false)
			end
		end)
		if ok then
			return
		end
		task.wait(0.25 * attempt)
	end
	warn("[Interface] optional CoreGui widgets could not be hidden")
end
return Controller

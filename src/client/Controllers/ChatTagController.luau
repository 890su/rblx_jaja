--!strict
local TextChatService = game:GetService("TextChatService")
local Players = game:GetService("Players")
local Controller = {}

function Controller.start()
	TextChatService.OnIncomingMessage = function(
		message: TextChatMessage
	): TextChatMessageProperties
		local properties = Instance.new("TextChatMessageProperties")
		local source = message.TextSource
		local sender = source and Players:GetPlayerByUserId(source.UserId)
		if sender and sender:GetAttribute("Pass_VIP") == true then
			properties.PrefixText = `<font color="#FFD56A">[VIP]</font> {message.PrefixText}`
		end
		return properties
	end
end

return Controller

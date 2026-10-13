--!strict
-- "How to play" card shown on a player's first visits (until the tutorial is
-- finished): the whole loop in four lines before they touch anything.

local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Locale = require(Shared.Locale)

local UiKit = require(script.Parent.Parent.Lib.UiKit)

local player = Players.LocalPlayer

local STEPS = {
	{ icon = "⚡", text = "Run! Every second you get faster" },
	{ icon = "☄", text = "Grab meteors on the track and carry them home" },
	{ icon = "✨", text = "They hatch into creatures that earn Stardust" },
	{ icon = "⚠", text = "Watch out for Void Snatchers — and other players!" },
}

local IntroController = {}

function IntroController.start()
	-- Wait for the server to publish tutorial state.
	while player:GetAttribute("TutorialDone") == nil do
		task.wait(0.2)
	end
	if player:GetAttribute("TutorialDone") then
		return
	end
	local panel = UiKit.panel("Intro", Locale.term("How to play"))
	local list = UiKit.list(UiKit.body(panel, 56), UDim2.new(), UDim2.fromScale(1, 1))
	for i, step in STEPS do
		local row = Instance.new("Frame")
		row.BackgroundColor3 = UiKit.CARD_COLOR
		row.LayoutOrder = i
		row.Size = UDim2.new(1, -8, 0, 72)
		UiKit.corner(row)
		row.Parent = list
		UiKit.text(row, {
			Text = tostring(i),
			Size = UDim2.fromScale(0.12, 0.9),
			Position = UDim2.fromScale(0.01, 0.05),
			AutoLocalize = false,
		})
		UiKit.text(row, {
			Text = Locale.term(step.text),
			Size = UDim2.fromScale(0.84, 0.8),
			Position = UDim2.fromScale(0.14, 0.1),
			TextXAlignment = Enum.TextXAlignment.Left,
		})
	end
	local ok = UiKit.footer(panel, Locale.term("Got it!"))
	ok.Activated:Connect(function()
		UiKit.close()
	end)
	UiKit.show("Intro")
	player:GetAttributeChangedSignal("TutorialDone"):Connect(function()
		if player:GetAttribute("TutorialDone") then
			if UiKit.isOpen("Intro") then
				UiKit.close()
			end
		end
	end)
end

return IntroController

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
	for i, step in STEPS do
		local row = Instance.new("Frame")
		row.BackgroundColor3 = UiKit.CARD_COLOR
		row.Position = UDim2.fromScale(0.05, 0.15 + (i - 1) * 0.17)
		row.Size = UDim2.fromScale(0.9, 0.14)
		UiKit.corner(row)
		row.Parent = panel
		UiKit.text(row, {
			Text = step.icon,
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
	local ok = UiKit.button(panel, Locale.term("Got it!"), {
		Size = UDim2.fromScale(0.4, 0.11),
		Position = UDim2.fromScale(0.3, 0.84),
	})
	ok.Activated:Connect(function()
		panel.Visible = false
	end)
	UiKit.show("Intro")
	player:GetAttributeChangedSignal("TutorialDone"):Connect(function()
		if player:GetAttribute("TutorialDone") then
			panel.Visible = false
		end
	end)
end

return IntroController

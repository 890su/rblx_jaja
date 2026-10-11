--!strict
-- Daily streak panel (7 days) and promo-code entry. State comes from player
-- attributes published by RewardService.

local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Daily = require(Shared.Config.Daily)
local Remotes = require(Shared.Remotes)

local UiKit = require(script.Parent.Parent.Lib.UiKit)

local player = Players.LocalPlayer

local RewardsController = {}

local dayCards: { Frame } = {}
local claimButton: TextButton
local sideDaily: TextButton

local function refresh()
	local available = player:GetAttribute("DailyAvailable") == true
	local streak = (player:GetAttribute("DailyStreak") :: number?) or 0
	local nextDay = (player:GetAttribute("DailyNext") :: number?) or (streak % #Daily.REWARDS + 1)
	for day, frame in dayCards do
		local claimed = if available then day < nextDay else day <= streak
		frame.BackgroundColor3 = if day == nextDay and available
			then Color3.fromRGB(70, 140, 90)
			elseif claimed then Color3.fromRGB(60, 60, 75)
			else UiKit.CARD_COLOR
	end
	claimButton.Text = if available then `Claim day {nextDay}` else "Come back tomorrow!"
	claimButton.BackgroundColor3 = if available then UiKit.BUTTON_COLOR else UiKit.DISABLED_COLOR
	sideDaily.Text = if available then "Daily (!)" else "Daily"
end

function RewardsController.init()
	local panel = UiKit.panel("Daily", "Daily Rewards")
	local row = Instance.new("Frame")
	row.BackgroundTransparency = 1
	row.Position = UDim2.fromScale(0.04, 0.16)
	row.Size = UDim2.fromScale(0.92, 0.42)
	local layout = Instance.new("UIGridLayout")
	layout.CellSize = UDim2.fromScale(0.13, 1)
	layout.CellPadding = UDim2.fromScale(0.012, 0)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = row
	row.Parent = panel
	for day, reward in Daily.REWARDS do
		local frame = Instance.new("Frame")
		frame.LayoutOrder = day
		frame.BackgroundColor3 = UiKit.CARD_COLOR
		UiKit.corner(frame)
		UiKit.text(frame, {
			Text = `Day {day}`,
			Size = UDim2.fromScale(0.9, 0.22),
			Position = UDim2.fromScale(0.05, 0.04),
		})
		UiKit.text(frame, {
			Text = reward.label,
			Size = UDim2.fromScale(0.9, 0.6),
			Position = UDim2.fromScale(0.05, 0.32),
			TextColor3 = Color3.fromRGB(255, 220, 120),
			TextWrapped = true,
		})
		frame.Parent = row
		dayCards[day] = frame
	end
	claimButton = UiKit.button(
		panel,
		"",
		{ Size = UDim2.fromScale(0.4, 0.1), Position = UDim2.fromScale(0.3, 0.62) }
	)
	claimButton.Activated:Connect(function()
		Remotes.event("ClaimDaily"):FireServer()
	end)

	-- Promo codes
	local box = Instance.new("TextBox")
	box.PlaceholderText = "Enter code"
	box.Text = ""
	box.ClearTextOnFocus = false
	box.Font = UiKit.FONT
	box.TextScaled = true
	box.TextColor3 = Color3.new(1, 1, 1)
	box.BackgroundColor3 = UiKit.CARD_COLOR
	box.Size = UDim2.fromScale(0.45, 0.1)
	box.Position = UDim2.fromScale(0.1, 0.82)
	UiKit.corner(box, 8)
	box.Parent = panel
	local redeem = UiKit.button(panel, "Redeem", {
		Size = UDim2.fromScale(0.25, 0.1),
		Position = UDim2.fromScale(0.6, 0.82),
		BackgroundColor3 = Color3.fromRGB(80, 110, 200),
	})
	redeem.Activated:Connect(function()
		if #box.Text > 0 then
			Remotes.event("RedeemCode"):FireServer(box.Text)
			box.Text = ""
		end
	end)

	sideDaily = UiKit.sideButton("Daily", Color3.fromRGB(220, 90, 120), 4, function()
		UiKit.toggle("Daily")
		refresh()
	end)
end

function RewardsController.start()
	for _, attribute in { "DailyAvailable", "DailyStreak", "DailyNext" } do
		player:GetAttributeChangedSignal(attribute):Connect(refresh)
	end
	refresh()
end

return RewardsController

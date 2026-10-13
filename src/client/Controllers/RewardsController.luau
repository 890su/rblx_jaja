--!strict
-- Daily streak panel (7 days) and promo-code entry. State comes from player
-- attributes published by RewardService.

local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Daily = require(Shared.Config.Daily)
local Remotes = require(Shared.Remotes)
local Locale = require(Shared.Locale)

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
	claimButton.Text = if available
		then Locale.t("daily_claim", { day = nextDay })
		else Locale.term("Come back tomorrow!")
	claimButton.BackgroundColor3 = if available then UiKit.BUTTON_COLOR else UiKit.DISABLED_COLOR
	UiKit.setEnabled(claimButton, available)
	sideDaily.Text = Locale.term(if available then "Daily (!)" else "Daily")
end

function RewardsController.init()
	local panel = UiKit.panel("Daily", Locale.term("Daily Rewards"))
	local row = UiKit.list(UiKit.body(panel, 112), UDim2.new(), UDim2.fromScale(1, 1))
	assert(row:FindFirstChildOfClass("UIListLayout")):Destroy()
	local layout = Instance.new("UIGridLayout")
	layout.CellSize = UDim2.new(0.13, 0, 0, 120)
	layout.CellPadding = UDim2.fromOffset(8, 8)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = row
	local function resize()
		local columns = if row.AbsoluteSize.X < 620 then 3 else 7
		layout.CellSize =
			UDim2.fromOffset(math.max(72, (row.AbsoluteSize.X - 8 * columns) / columns), 120)
	end
	row:GetPropertyChangedSignal("AbsoluteSize"):Connect(resize)
	resize()
	for day, reward in Daily.REWARDS do
		local frame = Instance.new("Frame")
		frame.LayoutOrder = day
		frame.BackgroundColor3 = UiKit.CARD_COLOR
		UiKit.corner(frame)
		UiKit.text(frame, {
			Text = Locale.t("daily_day", { day = day }),
			Size = UDim2.fromScale(0.9, 0.22),
			Position = UDim2.fromScale(0.05, 0.04),
		})
		UiKit.text(frame, {
			Text = Locale.term(reward.label),
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
		{ Name = "Claim", Size = UDim2.new(1, -32, 0, 48), Position = UDim2.new(0, 16, 1, -120) }
	)
	claimButton.Activated:Connect(function()
		Remotes.event("ClaimDaily"):FireServer()
	end)

	-- Promo codes
	local box = Instance.new("TextBox")
	box.PlaceholderText = Locale.term("Enter code")
	box.Text = ""
	box.ClearTextOnFocus = false
	box.Font = UiKit.FONT
	box.AutoLocalize = false
	box.TextScaled = true
	box.TextColor3 = Color3.new(1, 1, 1)
	box.BackgroundColor3 = UiKit.CARD_COLOR
	box.Name = "Code"
	box.Size = UDim2.new(0.67, -24, 0, 48)
	box.Position = UDim2.new(0, 16, 1, -64)
	UiKit.corner(box, 8)
	box.Parent = panel
	local textLimit = Instance.new("UITextSizeConstraint")
	textLimit.MinTextSize, textLimit.MaxTextSize = 12, 22
	textLimit.Parent = box
	local redeem = UiKit.button(panel, Locale.term("Redeem"), {
		Name = "Redeem",
		Size = UDim2.new(0.33, -16, 0, 48),
		Position = UDim2.new(0.67, 0, 1, -64),
		BackgroundColor3 = Color3.fromRGB(80, 110, 200),
	})
	redeem.Activated:Connect(function()
		if #box.Text > 0 then
			Remotes.event("RedeemCode"):FireServer(box.Text)
			box.Text = ""
		end
	end)

	sideDaily = UiKit.sideButton(Locale.term("Daily"), Color3.fromRGB(220, 90, 120), 4, function()
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

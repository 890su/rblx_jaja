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
			then UiKit.BUTTON_COLOR
			elseif claimed then UiKit.DISABLED_COLOR
			else UiKit.CARD_COLOR
		local dayLabel = frame:FindFirstChild("Day") :: TextLabel
		dayLabel.Text = if claimed
			then Locale.term("Claimed")
			else Locale.t("daily_day", { day = day })
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
	local row = UiKit.list(UiKit.body(panel, 56), UDim2.new(), UDim2.fromScale(1, 1))
	row.Name = "Rewards"
	local grid = Instance.new("Frame")
	grid.Name, grid.BackgroundTransparency, grid.LayoutOrder = "Days", 1, 1
	grid.Size, grid.Parent = UDim2.new(1, -8, 0, 0), row
	local layout = Instance.new("UIGridLayout")
	layout.CellSize = UDim2.new(0.13, 0, 0, 120)
	layout.CellPadding = UDim2.fromOffset(8, 8)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = grid
	local function resize()
		local columns = if row.AbsoluteSize.X < 620 then 3 else 7
		layout.CellSize = UDim2.fromOffset(
			math.max(72, (row.AbsoluteSize.X - 8 * columns) / columns),
			if UiKit.compact() then 96 else 120
		)
		grid.Size = UDim2.new(1, -8, 0, layout.AbsoluteContentSize.Y)
	end
	row:GetPropertyChangedSignal("AbsoluteSize"):Connect(resize)
	layout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(resize)
	resize()
	for day, reward in Daily.REWARDS do
		local frame = Instance.new("Frame")
		frame.LayoutOrder = day
		frame.BackgroundColor3 = UiKit.CARD_COLOR
		UiKit.surface(frame)
		UiKit.text(frame, {
			Name = "Day",
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
		frame.Parent = grid
		dayCards[day] = frame
	end
	claimButton = UiKit.footer(panel, "", "Claim")
	claimButton.Activated:Connect(function()
		Remotes.event("ClaimDaily"):FireServer()
	end)

	-- Promo codes
	local codes = Instance.new("Frame")
	codes.Name, codes.BackgroundTransparency, codes.LayoutOrder = "Codes", 1, 2
	codes.Size, codes.Parent = UDim2.new(1, -8, 0, 48), row
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
	box.Size = UDim2.new(0.67, -8, 0, 48)
	box.Position = UDim2.new()
	UiKit.corner(box, 8)
	box.Parent = codes
	local textLimit = Instance.new("UITextSizeConstraint")
	textLimit.MinTextSize, textLimit.MaxTextSize = 12, 22
	textLimit.Parent = box
	local redeem = UiKit.button(codes, Locale.term("Redeem"), {
		Name = "Redeem",
		Size = UDim2.new(0.33, 0, 0, 48),
		Position = UDim2.new(0.67, 0, 0, 0),
		BackgroundColor3 = UiKit.BUTTON_COLOR,
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

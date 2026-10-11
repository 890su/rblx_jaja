--!strict
-- Greybox menus: side buttons (Shop / Rebirth / Invite), the Meteor Shop panel
-- (restock timer, 6 offers, pedestal upgrade), the Rebirth panel, and the
-- Meteor Shower timer. Everything shown comes from the server (ShopState,
-- player/workspace attributes); buttons only send requests.

local Players = game:GetService("Players")
local SocialService = game:GetService("SocialService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Types = require(Shared.Types)
local Theme = require(Shared.Theme)
local Speed = require(Shared.Config.Speed)
local Economy = require(Shared.Config.Economy)
local Format = require(Shared.Util.Format)
local RebirthMath = require(Shared.Util.RebirthMath)
local Remotes = require(Shared.Remotes)

local player = Players.LocalPlayer

local UiKit = require(script.Parent.Parent.Lib.UiKit)

local MenuController = {}

local shopState: Types.ShopState? = nil
local restockLabel: TextLabel
local pedestalButton: TextButton
local cards: {
	{
		frame: Frame,
		name: TextLabel,
		rarity: TextLabel,
		price: TextLabel,
		stock: TextLabel,
		buy: TextButton,
	}
} =
	{}
local rebirthInfo: TextLabel
local rebirthButton: TextButton
local showerLabel: TextLabel

local corner = UiKit.corner
local text = UiKit.text
local button = UiKit.button
local CARD_COLOR = UiKit.CARD_COLOR
local BUTTON_COLOR = UiKit.BUTTON_COLOR

local function buildShop()
	local frame = UiKit.panel("Shop", `{Theme.ITEM} Shop`)
	restockLabel = text(frame, {
		Size = UDim2.fromScale(0.4, 0.07),
		Position = UDim2.fromScale(0.48, 0.04),
		TextColor3 = Color3.fromRGB(150, 200, 255),
		TextXAlignment = Enum.TextXAlignment.Right,
	})
	local grid = Instance.new("Frame")
	grid.BackgroundTransparency = 1
	grid.Position = UDim2.fromScale(0.04, 0.15)
	grid.Size = UDim2.fromScale(0.92, 0.66)
	grid.Parent = frame
	local layout = Instance.new("UIGridLayout")
	layout.CellSize = UDim2.fromScale(0.315, 0.47)
	layout.CellPadding = UDim2.fromScale(0.025, 0.05)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = grid
	for slot = 1, 6 do
		local card = Instance.new("Frame")
		card.LayoutOrder = slot
		card.BackgroundColor3 = CARD_COLOR
		corner(card)
		local stroke = Instance.new("UIStroke")
		stroke.Thickness = 2
		stroke.Parent = card
		card.Parent = grid
		local entry = {
			frame = card,
			name = text(
				card,
				{ Size = UDim2.fromScale(0.9, 0.22), Position = UDim2.fromScale(0.05, 0.04) }
			),
			rarity = text(
				card,
				{ Size = UDim2.fromScale(0.9, 0.16), Position = UDim2.fromScale(0.05, 0.27) }
			),
			price = text(card, {
				Size = UDim2.fromScale(0.9, 0.16),
				Position = UDim2.fromScale(0.05, 0.45),
				TextColor3 = Color3.fromRGB(255, 220, 90),
			}),
			stock = text(card, {
				Size = UDim2.fromScale(0.9, 0.12),
				Position = UDim2.fromScale(0.05, 0.62),
				TextColor3 = Color3.fromRGB(180, 180, 200),
			}),
			buy = button(
				card,
				"Buy",
				{ Size = UDim2.fromScale(0.8, 0.18), Position = UDim2.fromScale(0.1, 0.78) }
			),
		}
		entry.buy.Activated:Connect(function()
			Remotes.event("ShopBuy"):FireServer(slot)
		end)
		cards[slot] = entry
	end
	pedestalButton = button(frame, "", {
		Size = UDim2.fromScale(0.6, 0.1),
		Position = UDim2.fromScale(0.2, 0.86),
		BackgroundColor3 = Color3.fromRGB(80, 110, 200),
	})
	pedestalButton.Activated:Connect(function()
		Remotes.event("BuyPedestal"):FireServer()
	end)
end

local function refreshShop()
	local state = shopState
	if not state then
		return
	end
	local coins = (player:GetAttribute("Coins") :: number?) or 0
	for slot, entry in cards do
		local offer = state.offers[slot]
		local left = state.remaining[slot] or 0
		if offer then
			local color = (Theme.RARITY_COLORS :: any)[offer.rarity] or Color3.new(1, 1, 1)
			entry.name.Text = Theme.CREATURE_NAMES[offer.creatureId] or offer.rarity
			entry.rarity.Text = offer.rarity
			entry.rarity.TextColor3 = color;
			(entry.frame:FindFirstChildOfClass("UIStroke") :: UIStroke).Color = color
			entry.price.Text = `{Format.short(offer.price)} {Theme.CURRENCY}`
			entry.stock.Text = if left > 0 then `{left} left` else "Sold out"
			entry.buy.Text = if left <= 0
				then "Sold out"
				elseif coins < offer.price then "Too pricey"
				else "Buy"
			entry.buy.BackgroundColor3 = if left > 0 and coins >= offer.price
				then BUTTON_COLOR
				else Color3.fromRGB(90, 90, 100)
		end
	end
	local nextCost = player:GetAttribute("NextPedestalCost") :: number?
	local count = (player:GetAttribute("PedestalCount") :: number?) or Economy.PEDESTALS_START
	pedestalButton.Text = if nextCost
		then `Unlock pedestal {count + 1} · {Format.short(nextCost)} {Theme.CURRENCY}`
		else "All pedestals unlocked"
end

local function buildRebirth()
	local frame = UiKit.panel("Rebirth", "Rebirth")
	rebirthInfo = text(frame, {
		Size = UDim2.fromScale(0.9, 0.6),
		Position = UDim2.fromScale(0.05, 0.15),
		TextScaled = false,
		TextSize = 22,
		TextWrapped = true,
		TextYAlignment = Enum.TextYAlignment.Top,
		TextXAlignment = Enum.TextXAlignment.Left,
	})
	rebirthButton = button(
		frame,
		"Rebirth!",
		{ Size = UDim2.fromScale(0.5, 0.12), Position = UDim2.fromScale(0.25, 0.82) }
	)
	rebirthButton.Activated:Connect(function()
		Remotes.event("Rebirth"):FireServer()
	end)
end

local function refreshRebirth()
	local rebirths = (player:GetAttribute("Rebirths") :: number?) or 0
	local speed = (player:GetAttribute("Speed") :: number?) or 0
	local coins = (player:GetAttribute("Coins") :: number?) or 0
	local needSpeed = RebirthMath.speedRequired(rebirths)
	local needCoins = RebirthMath.cost(rebirths)
	local ok = speed >= needSpeed and coins >= needCoins
	local nextZone = if rebirths == 0 then `\nUnlocks {Theme.ZONE_NAMES[5]}` else ""
	rebirthInfo.Text = table.concat({
		`Rebirths: {rebirths}`,
		`Speed: {Format.short(speed)} / {Format.short(needSpeed)}`,
		`{Theme.CURRENCY}: {Format.short(coins)} / {Format.short(needCoins)}`,
		"",
		`Reward: +{math.floor(Economy.REBIRTH_INCOME_BONUS * 100)}% income, +{math.floor(
			Speed.REBIRTH_GAIN_BONUS * 100
		)}% speed gain{nextZone}`,
		`Resets Speed and {Theme.CURRENCY}. Creatures stay.`,
	}, "\n")
	rebirthButton.BackgroundColor3 = if ok then BUTTON_COLOR else Color3.fromRGB(90, 90, 100)
end

local function refreshShower()
	local now = workspace:GetServerTimeNow()
	local endsAt = (workspace:GetAttribute("ShowerEndsAt") :: number?) or 0
	local nextAt = (workspace:GetAttribute("NextShowerAt") :: number?) or 0
	if now < endsAt then
		showerLabel.Text = `☄ {Theme.SHOWER_EVENT} NOW · {Format.duration(endsAt - now)}`
		showerLabel.TextColor3 = Color3.fromRGB(255, 170, 80)
	elseif nextAt > 0 then
		showerLabel.Text = `☄ {Theme.SHOWER_EVENT} in {Format.duration(nextAt - now)}`
		showerLabel.TextColor3 = Color3.fromRGB(200, 210, 255)
	end
	local state = shopState
	if state and UiKit.isOpen("Shop") then
		restockLabel.Text = `Restock in {Format.duration(state.endsAt - now)}`
	end
end

local function invite()
	local ok, canInvite = pcall(function()
		return SocialService:CanSendGameInviteAsync(player)
	end)
	if ok and canInvite then
		pcall(function()
			SocialService:PromptGameInvite(player)
		end)
	end
end

function MenuController.init()
	local gui = UiKit.gui()
	UiKit.sideButton("Shop", Color3.fromRGB(230, 150, 40), 1, function()
		UiKit.toggle("Shop")
		refreshShop()
	end)
	UiKit.sideButton("Rebirth", Color3.fromRGB(160, 80, 220), 2, function()
		UiKit.toggle("Rebirth")
		refreshRebirth()
	end)
	UiKit.sideButton("Invite +10%", Color3.fromRGB(60, 150, 230), 5, invite)

	showerLabel = text(gui, {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -12, 0, 8),
		Size = UDim2.fromScale(0.3, 0.045),
		TextXAlignment = Enum.TextXAlignment.Right,
		TextStrokeTransparency = 0.3,
	})

	buildShop()
	buildRebirth()
end

function MenuController.start()
	Remotes.event("ShopState").OnClientEvent:Connect(function(state: Types.ShopState)
		shopState = state
		refreshShop()
	end)
	for _, attribute in { "Coins", "Speed", "Rebirths", "NextPedestalCost", "PedestalCount" } do
		player:GetAttributeChangedSignal(attribute):Connect(function()
			if UiKit.isOpen("Shop") then
				refreshShop()
			end
			if UiKit.isOpen("Rebirth") then
				refreshRebirth()
			end
		end)
	end
	while true do
		refreshShower()
		task.wait(0.5)
	end
end

return MenuController

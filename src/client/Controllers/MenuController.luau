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
local Locale = require(Shared.Locale)

local player = Players.LocalPlayer

local UiKit = require(script.Parent.Parent.Lib.UiKit)
local Preview = require(script.Parent.Parent.Lib.ItemPreview)

local MenuController = {}

local shopState: Types.ShopState? = nil
local restockLabel: TextLabel
local cards: {
	{
		frame: Frame,
		name: TextLabel,
		rarity: TextLabel,
		price: TextLabel,
		stock: TextLabel,
		buy: TextButton,
		view: ViewportFrame,
	}
} =
	{}
local rebirthInfo: TextLabel
local rebirthButton: TextButton
local showerLabel: TextLabel
local showerMenuLabel: TextLabel
local shopGrid: ScrollingFrame
local shopLoading: TextLabel

local text = UiKit.text
local button = UiKit.button
local CARD_COLOR = UiKit.CARD_COLOR
local BUTTON_COLOR = UiKit.BUTTON_COLOR

local function buildShop()
	local frame = UiKit.panel("Shop", Locale.term("Meteor Shop"))
	assert(frame:FindFirstChildOfClass("UISizeConstraint"), "missing shop bounds").MaxSize =
		Vector2.new(920, 536)
	local title = frame:FindFirstChild("Title") :: TextLabel
	local body = UiKit.body(frame, 56)
	restockLabel = text(frame, {
		Size = UDim2.new(1, -32, 0, 24),
		Position = UDim2.fromOffset(16, 64),
		TextColor3 = Color3.fromRGB(150, 200, 255),
		TextXAlignment = Enum.TextXAlignment.Right,
		TextWrapped = true,
	})
	title.Size = UDim2.new(1, -156, 0, 48)
	body.Position = UDim2.fromOffset(16, 96)
	body.Size = UDim2.new(1, -32, 1, -168)
	local function headerResize()
		local header = UiKit.headerHeight()
		if frame.AbsoluteSize.X < 520 then
			title.Size = UDim2.new(1, -156, 0, 48)
			restockLabel.Position, restockLabel.Size =
				UDim2.fromOffset(16, header), UDim2.new(1, -32, 0, 24)
			body.Position, body.Size =
				UDim2.fromOffset(16, header + 32), UDim2.new(1, -32, 1, -header - 104)
		else
			local width = (frame.AbsoluteSize.X - 164) / 2
			title.Size = UDim2.fromOffset(width, 48)
			restockLabel.Position, restockLabel.Size =
				UDim2.fromOffset(24 + width, 8), UDim2.fromOffset(width, 48)
			body.Position, body.Size =
				UDim2.fromOffset(16, header), UDim2.new(1, -32, 1, -header - 72)
		end
	end
	frame:GetPropertyChangedSignal("AbsoluteSize"):Connect(headerResize)
	headerResize()
	local grid = Instance.new("ScrollingFrame")
	shopGrid = grid
	grid.Visible = false
	shopLoading = text(
		body,
		{ Name = "Loading", Text = Locale.t("purchase_loading"), Size = UDim2.fromScale(1, 1) }
	)
	grid.BackgroundTransparency = 1
	grid.BorderSizePixel, grid.ScrollBarThickness = 0, 6
	grid.AutomaticCanvasSize, grid.CanvasSize = Enum.AutomaticSize.Y, UDim2.new()
	grid.Name = "Offers"
	grid.Position = UDim2.new()
	grid.Size = UDim2.fromScale(1, 1)
	grid.Parent = body
	local layout = Instance.new("UIGridLayout")
	layout.CellSize = UDim2.new(0.315, 0, 0, 220)
	layout.CellPadding = UDim2.new(0.025, 0, 0, 10)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = grid
	local function resize()
		local short = grid.AbsoluteSize.Y < 150
		local columns = if grid.AbsoluteSize.X < 420 or short
			then 1
			elseif grid.AbsoluteSize.X < 700 then 2
			else 3
		layout.CellSize = UDim2.new(
			if columns == 1 then 0.98 elseif columns == 2 then 0.48 else 0.315,
			0,
			0,
			if short then math.max(104, grid.AbsoluteSize.Y - 4) else 160
		)
		for _, entry in cards do
			entry.view.Size = UDim2.new(0.32, 0, 0, if short then 44 else 92)
			entry.view.Position = UDim2.new(0.02, 0, 0, if short then 4 else 8)
			entry.name.Position = UDim2.new(0.36, 0, 0, if short then 4 else 10)
			entry.name.Size = UDim2.new(0.60, 0, 0, if short then 20 else 24)
			entry.rarity.Visible = not short
			entry.price.Position = UDim2.new(0.36, 0, 0, if short then 28 else 60)
			entry.price.Size = UDim2.new(if short then 0.36 else 0.60, 0, 0, 18)
			entry.stock.Position =
				UDim2.new(if short then 0.74 else 0.36, 0, 0, if short then 28 else 84)
			entry.stock.Size = UDim2.new(if short then 0.22 else 0.60, 0, 0, 18)
		end
	end
	grid:GetPropertyChangedSignal("AbsoluteSize"):Connect(resize)
	resize()
	for slot = 1, 6 do
		local card = Instance.new("Frame")
		card.LayoutOrder = slot
		card.BackgroundColor3 = CARD_COLOR
		UiKit.surface(card)
		card.Parent = grid
		local entry = {
			frame = card,
			view = Preview.new(card, UDim2.new(0.02, 0, 0, 8), UDim2.new(0.32, 0, 0, 92)),
			name = text(card, {
				Size = UDim2.new(0.60, 0, 0, 24),
				Position = UDim2.new(0.36, 0, 0, 10),
				TextXAlignment = Enum.TextXAlignment.Left,
			}),
			rarity = text(card, {
				Size = UDim2.new(0.60, 0, 0, 18),
				Position = UDim2.new(0.36, 0, 0, 38),
				TextXAlignment = Enum.TextXAlignment.Left,
			}),
			price = text(card, {
				Size = UDim2.new(0.60, 0, 0, 20),
				Position = UDim2.new(0.36, 0, 0, 60),
				TextXAlignment = Enum.TextXAlignment.Left,
				TextColor3 = Color3.fromRGB(255, 220, 90),
			}),
			stock = text(card, {
				Size = UDim2.new(0.60, 0, 0, 18),
				Position = UDim2.new(0.36, 0, 0, 84),
				TextXAlignment = Enum.TextXAlignment.Left,
				TextColor3 = Color3.fromRGB(180, 180, 200),
			}),
			buy = button(card, "Buy", {
				Name = `Buy{slot}`,
				Size = UDim2.new(1, -16, 0, 48),
				Position = UDim2.new(0, 8, 1, -56),
			}),
		}
		entry.buy.Activated:Connect(function()
			if not entry.buy.Interactable then
				return
			end
			Remotes.event("ShopBuy"):FireServer(slot)
		end)
		UiKit.setEnabled(entry.buy, false)
		cards[slot] = entry
	end
	resize()
	local upgrades =
		UiKit.footer(frame, Locale.term("Upgrades · Treadmill · Carry speed"), "UpgradesButton")
	upgrades.BackgroundColor3 = UiKit.CARD_COLOR
	upgrades.Activated:Connect(function()
		UiKit.show("Upgrades")
		Remotes.event("RequestShopState"):FireServer()
	end)
end

local function refreshShop()
	local state = shopState
	showerMenuLabel.Text = showerLabel.Text
	showerMenuLabel.TextColor3 = showerLabel.TextColor3
	if not state then
		return
	end
	local coins = (player:GetAttribute("Coins") :: number?) or 0
	shopGrid.Visible, shopLoading.Visible = true, false
	local full = ((player:GetAttribute("StationOccupied") :: number?) or 0)
		>= ((player:GetAttribute("StationCapacity") :: number?) or math.huge)
	for slot, entry in cards do
		local offer = state.offers[slot]
		local left = state.remaining[slot] or 0
		if offer then
			Preview.set(entry.view, offer.creatureId)
			local color = (Theme.RARITY_COLORS :: any)[offer.rarity] or Color3.new(1, 1, 1)
			entry.name.Text = Locale.term(Theme.CREATURE_NAMES[offer.creatureId] or offer.rarity)
			entry.rarity.Text = Locale.term(offer.rarity)
			entry.rarity.TextColor3 = color;
			(entry.frame:FindFirstChildOfClass("UIStroke") :: UIStroke).Color = color
			entry.price.Text = Locale.t("amount_coins", { amount = Format.short(offer.price) })
			entry.stock.Text = if left > 0
				then Locale.t("shop_left", { count = left })
				else Locale.term("Sold out")
			entry.buy.Text = Locale.term(
				if left <= 0
					then "Sold out"
					elseif coins < offer.price then "Too pricey"
					elseif full then "Buy to storage"
					else "Buy"
			)
			entry.buy.BackgroundColor3 = if left > 0 and coins >= offer.price
				then BUTTON_COLOR
				else UiKit.DISABLED_COLOR
			UiKit.setEnabled(entry.buy, left > 0 and coins >= offer.price)
		else
			entry.buy.Text = Locale.term("Sold out")
			UiKit.setEnabled(entry.buy, false)
		end
	end
end

local function buildRebirth()
	local frame = UiKit.panel("Rebirth", Locale.term("Rebirth"))
	local info = UiKit.list(UiKit.body(frame, 56), UDim2.new(), UDim2.fromScale(1, 1))
	rebirthInfo = text(info, {
		Size = UDim2.new(1, -10, 0, 220),
		AutomaticSize = Enum.AutomaticSize.Y,
		TextScaled = false,
		TextSize = 18,
		TextWrapped = true,
		TextYAlignment = Enum.TextYAlignment.Top,
		TextXAlignment = Enum.TextXAlignment.Left,
	})
	rebirthButton = UiKit.footer(frame, Locale.term("Rebirth!"), "RebirthButton")
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
	local lines = {
		Locale.t("rebirth_count", { count = rebirths }),
		Locale.t("rebirth_speed", { have = Format.short(speed), need = Format.short(needSpeed) }),
		Locale.t("rebirth_coins", { have = Format.short(coins), need = Format.short(needCoins) }),
		"",
		Locale.t("rebirth_reward", {
			income = math.floor(Economy.REBIRTH_INCOME_BONUS * 100),
			speed = math.floor(Speed.REBIRTH_GAIN_BONUS * 100),
		}),
	}
	if rebirths == 0 then
		table.insert(lines, Locale.t("rebirth_unlocks", { zone = Locale.ref(Theme.ZONE_NAMES[5]) }))
	end
	table.insert(lines, Locale.term("Resets Speed and Stardust. Creatures stay."))
	rebirthInfo.Text = table.concat(lines, "\n")
	rebirthButton.BackgroundColor3 = if ok then BUTTON_COLOR else UiKit.DISABLED_COLOR
	UiKit.setEnabled(rebirthButton, ok)
end

local function refreshShower()
	local now = workspace:GetServerTimeNow()
	local endsAt = (workspace:GetAttribute("ShowerEndsAt") :: number?) or 0
	local nextAt = (workspace:GetAttribute("NextShowerAt") :: number?) or 0
	if now < endsAt then
		showerLabel.Text = Locale.t("shower_now", { time = Format.duration(endsAt - now) })
		showerLabel.TextColor3 = Color3.fromRGB(255, 170, 80)
	elseif nextAt > 0 then
		showerLabel.Text = Locale.t("shower_in", { time = Format.duration(nextAt - now) })
		showerLabel.TextColor3 = Color3.fromRGB(200, 210, 255)
	end
	local state = shopState
	if state and UiKit.isOpen("Shop") then
		restockLabel.Text =
			Locale.t("shop_restock_in", { time = Format.duration(state.endsAt - now) })
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
	UiKit.sideButton(Locale.term("Shop"), Color3.fromRGB(230, 150, 40), 1, function()
		UiKit.toggle("Shop")
		Remotes.event("RequestShopState"):FireServer()
		refreshShop()
	end)
	UiKit.sideButton(Locale.term("Rebirth"), Color3.fromRGB(160, 80, 220), 2, function()
		UiKit.toggle("Rebirth")
		refreshRebirth()
	end)
	UiKit.sideButton(Locale.term("Invite +10%"), Color3.fromRGB(60, 150, 230), 5, invite)
	showerMenuLabel = UiKit.menuInfo("ShowerStatus")

	showerLabel = text(gui, {
		Name = "ShowerTimer",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -12, 0, 8),
		Size = UDim2.new(0.3, 0, 0, 24),
		TextXAlignment = Enum.TextXAlignment.Right,
		TextStrokeTransparency = 0.3,
	})
	local function timerVisibility()
		showerLabel.Visible = player:GetAttribute("MenuOpen") ~= true and not UiKit.compact()
	end
	player:GetAttributeChangedSignal("MenuOpen"):Connect(timerVisibility)
	if workspace.CurrentCamera then
		workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(timerVisibility)
	end
	timerVisibility()

	buildShop()
	buildRebirth()
end

function MenuController.start()
	Remotes.event("ShopState").OnClientEvent:Connect(function(state: Types.ShopState)
		shopState = state
		refreshShop()
	end)
	Remotes.event("RequestShopState"):FireServer()
	for _, attribute in
		{
			"Coins",
			"Speed",
			"Rebirths",
			"NextPedestalCost",
			"PedestalCount",
			"NextTrainingCost",
			"StationOccupied",
			"StationCapacity",
		}
	do
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

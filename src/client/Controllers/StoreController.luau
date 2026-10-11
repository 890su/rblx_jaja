--!strict
-- Robux store: game passes and developer products. Paid random items (crates)
-- and probability modifiers (Server Luck) always open an odds window first,
-- listing every outcome with its percentage (Roblox paid random items policy).
-- Items whose id is still 0 show "Coming soon".

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Products = require(Shared.Config.Products)
local Creatures = require(Shared.Config.Creatures)
local Rarity = require(Shared.Config.Rarity)
local Zones = require(Shared.Config.Zones)
local Theme = require(Shared.Theme)
local Odds = require(Shared.Util.Odds)
local Locale = require(Shared.Locale)

local UiKit = require(script.Parent.Parent.Lib.UiKit)

local player = Players.LocalPlayer

local StoreController = {}

local ODDS_PRODUCTS: { [string]: boolean } =
	{ Crate1 = true, Crate3 = true, Crate10 = true, ServerLuck = true }

local oddsList: ScrollingFrame
local oddsBuy: TextButton
local oddsTitle: TextLabel
local pendingProduct: Products.Product? = nil
local passButtons: { [string]: TextButton } = {}

local function fmtPercent(value: number): string
	if value >= 1 then
		return string.format("%.1f%%", value)
	end
	return string.format("%.2f%%", value)
end

local function row(parent: Instance, textValue: string, color: Color3?, order: number)
	UiKit.text(parent, {
		Text = textValue,
		Size = UDim2.new(1, -10, 0, 26),
		TextScaled = false,
		TextSize = 20,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = color or Color3.new(1, 1, 1),
		LayoutOrder = order,
	})
end

local function fillCrateOdds()
	local order = 0
	local total = 0
	for _, rarity in Rarity.ORDER do
		local rarityPct = Products.CRATE_ODDS[rarity]
		if rarityPct then
			local pool = {}
			for _, creature in Creatures.LIST do
				if creature.rarity == rarity then
					table.insert(pool, creature.id)
				end
			end
			order += 1
			row(
				oddsList,
				`{Locale.term(rarity)}: {fmtPercent(rarityPct)}`,
				Theme.RARITY_COLORS[rarity],
				order
			)
			for _, id in pool do
				order += 1
				local pct = rarityPct / #pool
				total += pct
				row(
					oddsList,
					`    {Locale.term(Theme.CREATURE_NAMES[id] or id)} — {fmtPercent(pct)}`,
					nil,
					order
				)
			end
		end
	end
	order += 1
	row(
		oddsList,
		Locale.t("odds_total", { pct = fmtPercent(total) }),
		Color3.fromRGB(180, 180, 200),
		order
	)
end

local function fillLuckOdds()
	local boost = Products.SERVER_LUCK.boost
	local order = 1
	row(
		oddsList,
		Locale.t("luck_effect", { boost = boost, minutes = Products.SERVER_LUCK.seconds // 60 }),
		Color3.fromRGB(180, 200, 255),
		order
	)
	for index, zone in Zones.ZONES do
		order += 1
		row(
			oddsList,
			Locale.term(Theme.ZONE_NAMES[index] or `Zone {index}`),
			Color3.fromRGB(255, 220, 120),
			order
		)
		for _, rarity in Rarity.ORDER do
			if zone.weights[rarity] then
				order += 1
				local before = Odds.percent(zone.weights, rarity)
				local boosted = {}
				for r, w in zone.weights do
					boosted[r] = if r ~= "Common" then w * boost else w
				end
				local after = Odds.percent(boosted, rarity)
				row(
					oddsList,
					`    {Locale.term(rarity)}: {fmtPercent(before)} → {fmtPercent(after)}`,
					Theme.RARITY_COLORS[rarity],
					order
				)
			end
		end
	end
end

local function openOdds(product: Products.Product)
	pendingProduct = product
	for _, child in oddsList:GetChildren() do
		if child:IsA("TextLabel") then
			child:Destroy()
		end
	end
	oddsTitle.Text = Locale.t("odds_title", { name = Locale.ref(product.name) })
	if product.key == "ServerLuck" then
		fillLuckOdds()
	else
		fillCrateOdds()
	end
	oddsBuy.Text = if product.id ~= 0
		then Locale.t("odds_buy", { price = product.price })
		else Locale.term("Coming soon")
	oddsBuy.BackgroundColor3 = if product.id ~= 0 then UiKit.BUTTON_COLOR else UiKit.DISABLED_COLOR
	UiKit.show("Odds")
end

local function buy(item: Products.Product | Products.Pass, isPass: boolean)
	if item.id == 0 then
		return
	end
	if isPass then
		MarketplaceService:PromptGamePassPurchase(player, item.id)
	else
		MarketplaceService:PromptProductPurchase(player, item.id)
	end
end

local function card(
	parent: Instance,
	item: Products.Product | Products.Pass,
	isPass: boolean,
	order: number
)
	local frame = Instance.new("Frame")
	frame.Size = UDim2.new(1, -10, 0, 64)
	frame.BackgroundColor3 = UiKit.CARD_COLOR
	frame.LayoutOrder = order
	UiKit.corner(frame)
	frame.Parent = parent
	UiKit.text(frame, {
		Text = Locale.term(item.name),
		Size = UDim2.fromScale(0.62, 0.5),
		Position = UDim2.fromScale(0.03, 0.04),
		TextXAlignment = Enum.TextXAlignment.Left,
	})
	UiKit.text(frame, {
		Text = Locale.term(item.description),
		Size = UDim2.fromScale(0.62, 0.4),
		Position = UDim2.fromScale(0.03, 0.54),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Color3.fromRGB(180, 180, 200),
	})
	local hasOdds = not isPass and ODDS_PRODUCTS[item.key] == true
	local label = if item.id == 0
		then Locale.term("Coming soon")
		elseif hasOdds then Locale.t("odds_button", { price = item.price })
		else Locale.t("price_robux", { price = item.price })
	local b = UiKit.button(frame, label, {
		Size = UDim2.fromScale(0.3, 0.7),
		Position = UDim2.fromScale(0.68, 0.15),
		BackgroundColor3 = if item.id == 0
			then UiKit.DISABLED_COLOR
			else Color3.fromRGB(40, 170, 110),
	})
	b.Activated:Connect(function()
		if hasOdds then
			openOdds(item :: Products.Product)
		else
			buy(item, isPass)
		end
	end)
	if isPass then
		passButtons[item.key] = b
	end
end

local function refreshOwned()
	for key, b in passButtons do
		if player:GetAttribute(`Pass_{key}`) then
			b.Text = Locale.term("Owned")
			b.BackgroundColor3 = UiKit.DISABLED_COLOR
			b.Active = false
		end
	end
end

function StoreController.init()
	local store = UiKit.panel("Store", Locale.term("Store"))
	local list = UiKit.list(store, UDim2.fromScale(0.04, 0.14), UDim2.fromScale(0.92, 0.82))
	local order = 0
	for _, pass in Products.PASSES do
		order += 1
		card(list, pass, true, order)
	end
	for _, product in Products.PRODUCTS do
		order += 1
		card(list, product, false, order)
	end

	local odds = UiKit.panel("Odds", Locale.term("Odds"))
	oddsTitle = odds:FindFirstChild("Title") :: TextLabel
	oddsList = UiKit.list(odds, UDim2.fromScale(0.04, 0.14), UDim2.fromScale(0.92, 0.66))
	oddsBuy = UiKit.button(
		odds,
		"",
		{ Size = UDim2.fromScale(0.4, 0.1), Position = UDim2.fromScale(0.3, 0.85) }
	)
	oddsBuy.Activated:Connect(function()
		local product = pendingProduct
		if product then
			buy(product, false)
		end
	end)

	UiKit.sideButton(Locale.term("Store"), Color3.fromRGB(40, 170, 110), 3, function()
		UiKit.toggle("Store")
		refreshOwned()
	end)
end

function StoreController.start()
	for _, pass in Products.PASSES do
		player:GetAttributeChangedSignal(`Pass_{pass.key}`):Connect(refreshOwned)
	end
	refreshOwned()
end

return StoreController

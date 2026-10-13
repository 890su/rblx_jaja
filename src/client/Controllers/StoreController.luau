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
local Canyons = require(Shared.Config.Canyons)
local Events = require(Shared.Config.Events)
local Theme = require(Shared.Theme)
local Odds = require(Shared.Util.Odds)
local Locale = require(Shared.Locale)
local Remotes = require(Shared.Remotes)

local UiKit = require(script.Parent.Parent.Lib.UiKit)
local Preview = require(script.Parent.Parent.Lib.ItemPreview)
local Availability = require(Shared.Util.PurchaseAvailability)

local player = Players.LocalPlayer

local StoreController = {}

local ODDS_PRODUCTS: { [string]: boolean } =
	{ Crate1 = true, Crate3 = true, Crate10 = true, ServerLuck = true }

local oddsList: ScrollingFrame
local oddsBuy: TextButton
local oddsTitle: TextLabel
local oddsContext: TextButton
local contextIndex = 1
local contexts: { { zone: number, canyon: boolean, shower: boolean, boost: number } } = {}
for index in Zones.ZONES do
	for _, canyon in { false, true } do
		for _, shower in { false, true } do
			if canyon and index < Canyons.FROM_ZONE then
				continue
			end
			if shower and not table.find(Events.SHOWER_ZONES, index) then
				continue
			end
			table.insert(contexts, {
				zone = index,
				canyon = canyon :: boolean,
				shower = shower :: boolean,
				boost = (if canyon then Canyons.RARITY_BOOST else 1)
					* (if shower then Events.SHOWER_RARITY_BOOST else 1),
			})
		end
	end
end
local pendingProduct: Products.Product? = nil
local passButtons: { [string]: TextButton } = {}
local productButtons: { [string]: TextButton } = {}
local prices: { [string]: number } = {}
local failedPrices: { [string]: boolean } = {}
local items: { [string]: { item: Products.Product | Products.Pass, pass: boolean } } = {}
local requestPendingUntil = 0
local refreshOwned: () -> ()
local function status(item: Products.Product | Products.Pass, isPass: boolean): string
	local credit = ((player:GetAttribute(`PurchaseCredit_{item.key}`) :: number?) or 0) > 0
	return Availability.status({
		configured = credit or item.id ~= 0,
		loaded = credit or prices[item.key] ~= nil,
		failed = not credit and failedPrices[item.key] == true,
		owned = if isPass
			then player:GetAttribute(`Pass_{item.key}`) == true
			else item.key == "StarterPack" and player:GetAttribute("StarterPackOwned") == true,
		policyReady = player:GetAttribute("PolicyReady") == true,
		restricted = not isPass and ODDS_PRODUCTS[item.key] == true and player:GetAttribute(
			"PaidRandomItemsAllowed"
		) ~= true,
		applicable = (
			item.key ~= "InstantHatch"
			or ((player:GetAttribute("HatchingCount") :: number?) or 0) > 0
		) and (item.key ~= "Restock" or player:GetAttribute("ShopHasPurchases") == true),
		prompting = player:GetAttribute("PurchasePromptOpen") == true or player:GetAttribute(
			"PurchaseReceiptPending"
		) == true or os.clock() < requestPendingUntil,
	})
end
local function applyButton(
	b: TextButton,
	item: Products.Product | Products.Pass,
	isPass: boolean,
	odds: boolean
)
	local result = status(item, isPass)
	local credits = (player:GetAttribute(`PurchaseCredit_{item.key}`) :: number?) or 0
	b.Text = if result == "owned"
		then Locale.term("Owned")
		elseif result == "loading" then Locale.t("purchase_loading")
		elseif result == "restricted" then Locale.t("purchase_restricted")
		elseif result == "unavailable" then Locale.t("purchase_unavailable")
		elseif result == "pending" then "…"
		elseif credits > 0 then Locale.t("purchase_use_credit", { count = credits })
		else Locale.t(
			if odds then "odds_button" else "price_robux",
			{ price = prices[item.key] }
		)
	UiKit.setEnabled(b, result == "ready")
	b.BackgroundColor3 = if result == "ready" then UiKit.BUTTON_COLOR else UiKit.DISABLED_COLOR
end

local function fmtPercent(value: number): string
	if value >= 1 then
		return string.format("%.1f%%", value)
	end
	local digits = if value > 0 then math.max(2, 2 - math.floor(math.log10(value))) else 2
	return string.format(`%.{digits}f%%`, value)
end

local function row(parent: Instance, textValue: string, color: Color3?, order: number)
	UiKit.text(parent, {
		Text = textValue,
		Size = UDim2.new(1, -10, 0, 26),
		TextScaled = false,
		TextSize = 20,
		TextWrapped = true,
		AutomaticSize = Enum.AutomaticSize.Y,
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
	for _, child in oddsList:GetChildren() do
		if child:IsA("TextLabel") then
			child:Destroy()
		end
	end
	local context = contexts[contextIndex]
	local zone = Zones.ZONES[context.zone]
	oddsContext.Text = Locale.t("odds_context", {
		zone = Locale.term(Theme.ZONE_NAMES[context.zone]),
		canyon = if context.canyon then Locale.term("Canyon") else Locale.term("Field"),
		event = if context.shower then Locale.term("Meteor Shower") else Locale.term("Normal"),
		index = contextIndex,
		count = #contexts,
	})
	local boost = Products.SERVER_LUCK.boost
	local current = if ((workspace:GetAttribute("ServerLuckUntil") :: number?) or 0)
			> workspace:GetServerTimeNow()
		then boost
		else 1
	local order = 1
	row(
		oddsList,
		Locale.t("luck_effect", { boost = boost, minutes = Products.SERVER_LUCK.seconds // 60 }),
		nil,
		order
	)
	order += 1
	row(oddsList, Locale.t("luck_odds_legend"), nil, order)
	for _, rarity in Rarity.ORDER do
		if not zone.weights[rarity] then
			continue
		end
		local total = 0
		for _, creature in Creatures.LIST do
			if creature.rarity == rarity then
				total += Creatures.weightOf(creature, context.zone)
			end
		end
		for _, creature in Creatures.LIST do
			if creature.rarity ~= rarity then
				continue
			end
			local share = Creatures.weightOf(creature, context.zone) / total
			for _, golden in { false, true } do
				local mutationShare = if golden
					then Rarity.MUTATIONS.Golden.chance
					else 1 - Rarity.MUTATIONS.Golden.chance
				local before = Odds.percent(zone.weights, rarity, context.boost * current)
					* share
					* mutationShare
				local after = Odds.percent(zone.weights, rarity, context.boost * boost)
					* share
					* mutationShare
				order += 1
				row(
					oddsList,
					Locale.t("luck_odds_row", {
						name = Locale.term(Theme.CREATURE_NAMES[creature.id] or creature.id),
						mutation = if golden then Locale.term("Golden") else "",
						before = fmtPercent(before),
						after = fmtPercent(after),
					}),
					Theme.RARITY_COLORS[rarity],
					order
				)
			end
		end
	end
	order += 1
	row(oddsList, Locale.t("luck_first_visit"), nil, order)
end

local function openOdds(product: Products.Product)
	pendingProduct = product
	for _, child in oddsList:GetChildren() do
		if child:IsA("TextLabel") then
			child:Destroy()
		end
	end
	oddsTitle.Text = Locale.t("odds_title", { name = Locale.ref(product.name) })
	oddsContext.Visible = product.key == "ServerLuck"
	oddsList.Position = if product.key == "ServerLuck"
		then UDim2.fromOffset(16, 120)
		else UDim2.fromOffset(16, 64)
	oddsList.Size = if product.key == "ServerLuck"
		then UDim2.new(1, -32, 1, -192)
		else UDim2.new(1, -32, 1, -136)
	if product.key == "ServerLuck" then
		fillLuckOdds()
	else
		fillCrateOdds()
	end
	oddsBuy.Text = if product.id ~= 0
		then (if prices[product.key]
			then Locale.t("odds_buy", { price = prices[product.key] })
			else "…")
		else Locale.term("Coming soon")
	oddsBuy.BackgroundColor3 = if product.id ~= 0 then UiKit.BUTTON_COLOR else UiKit.DISABLED_COLOR
	UiKit.show("Odds")
	applyButton(oddsBuy, product, false, false)
end

local function buy(item: Products.Product | Products.Pass, isPass: boolean)
	if status(item, isPass) ~= "ready" then
		return
	end
	if not isPass and ((player:GetAttribute(`PurchaseCredit_{item.key}`) :: number?) or 0) > 0 then
		Remotes.event("UsePurchaseCredit"):FireServer(item.key)
		return
	end
	if not isPass then
		if item.key == "StarterPack" and player:GetAttribute("StarterPackOwned") then
			return
		end
		if ODDS_PRODUCTS[item.key] and player:GetAttribute("PaidRandomItemsAllowed") ~= true then
			return
		end
	elseif player:GetAttribute(`Pass_{item.key}`) then
		return
	end
	Remotes.event("RequestPurchase"):FireServer(if isPass then "pass" else "product", item.key)
	requestPendingUntil = os.clock() + 2
	UiKit.close()
	refreshOwned()
	task.delay(2, refreshOwned)
end

local function card(
	parent: Instance,
	item: Products.Product | Products.Pass,
	isPass: boolean,
	order: number
)
	local frame = Instance.new("Frame")
	frame.Size = UDim2.new(1, -10, 0, 132)
	frame.Name = item.key
	frame.BackgroundColor3 = UiKit.CARD_COLOR
	frame.LayoutOrder = order
	UiKit.corner(frame)
	frame.Parent = parent
	local function resize()
		frame.Size = UDim2.new(1, -10, 0, if frame.AbsoluteSize.X < 420 then 184 else 132)
	end
	frame:GetPropertyChangedSignal("AbsoluteSize"):Connect(resize)
	resize()
	items[item.key] = { item = item, pass = isPass }
	local preview = Preview.new(frame, UDim2.fromScale(0.01, 0.02), UDim2.fromScale(0.20, 0.96))
	Preview.set(preview, if item.key == "StarterPack" then "comet_cat" else item.key)
	UiKit.text(frame, {
		Text = Locale.term(item.name),
		Size = UDim2.fromScale(0.44, 0.42),
		Position = UDim2.fromScale(0.23, 0.04),
		TextXAlignment = Enum.TextXAlignment.Left,
	})
	UiKit.text(frame, {
		Text = Locale.term(item.description),
		Size = UDim2.fromScale(0.44, 0.46),
		Position = UDim2.fromScale(0.23, 0.50),
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Color3.fromRGB(180, 180, 200),
	})
	local hasOdds = not isPass and ODDS_PRODUCTS[item.key] == true
	local label = if item.id == 0 then Locale.term("Coming soon") else "…"
	local b = UiKit.button(frame, label, {
		Name = "Buy",
		Size = UDim2.new(0.3, 0, 0, 48),
		Position = UDim2.new(0.68, 0, 0.5, -24),
		BackgroundColor3 = if item.id == 0
			then UiKit.DISABLED_COLOR
			else Color3.fromRGB(40, 170, 110),
	})
	b.Activated:Connect(function()
		if status(item, isPass) ~= "ready" then
			return
		end
		if hasOdds then
			if player:GetAttribute("PaidRandomItemsAllowed") ~= true then
				return
			end
			openOdds(item :: Products.Product)
		else
			buy(item, isPass)
		end
	end)
	if isPass then
		passButtons[item.key] = b
	else
		productButtons[item.key] = b
	end
	applyButton(b, item, isPass, hasOdds)
	if item.id ~= 0 then
		task.spawn(function()
			for attempt = 1, 3 do
				local ok, info = pcall(function()
					return MarketplaceService:GetProductInfoAsync(
						item.id,
						if isPass then Enum.InfoType.GamePass else Enum.InfoType.Product
					)
				end)
				if ok and info.PriceInRobux then
					if info.IsForSale == false then
						failedPrices[item.key] = true
					else
						prices[item.key] = info.PriceInRobux
					end
					refreshOwned()
					return
				end
				task.wait(attempt)
			end
			failedPrices[item.key] = true
			refreshOwned()
		end)
	end
end

refreshOwned = function()
	for key, entry in items do
		local b = if entry.pass then passButtons[key] else productButtons[key]
		if b then
			applyButton(b, entry.item, entry.pass, not entry.pass and ODDS_PRODUCTS[key] == true)
		end
	end
	if pendingProduct and oddsBuy then
		applyButton(oddsBuy, pendingProduct, false, false)
	end
end

function StoreController.init()
	local store = UiKit.panel("Store", Locale.term("Store"))
	local list = UiKit.list(UiKit.body(store), UDim2.new(), UDim2.fromScale(1, 1))
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
	oddsContext = UiKit.button(
		odds,
		"",
		{ Size = UDim2.new(1, -32, 0, 48), Position = UDim2.fromOffset(16, 64) }
	)
	oddsContext.Visible = false
	oddsContext.Activated:Connect(function()
		contextIndex = contextIndex % #contexts + 1
		fillLuckOdds()
	end)
	oddsList = UiKit.list(odds, UDim2.fromOffset(16, 64), UDim2.new(1, -32, 1, -136))
	oddsBuy = UiKit.footer(odds, "", "Buy")
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

-- Read-only odds navigation, also used by the isolated client UI checks.
function StoreController.showOdds(key: string): boolean
	for _, product in Products.PRODUCTS do
		if product.key == key and ODDS_PRODUCTS[key] then
			openOdds(product)
			return true
		end
	end
	return false
end

function StoreController.start()
	player:GetAttributeChangedSignal("StarterPackOwned"):Connect(refreshOwned)
	player:GetAttributeChangedSignal("PaidRandomItemsAllowed"):Connect(refreshOwned)
	for _, key in { "InstantHatch", "Restock" } do
		player:GetAttributeChangedSignal(`PurchaseCredit_{key}`):Connect(refreshOwned)
	end
	for _, attribute in
		{
			"PolicyReady",
			"PurchasePromptOpen",
			"PurchaseReceiptPending",
			"HatchingCount",
			"ShopHasPurchases",
		}
	do
		player:GetAttributeChangedSignal(attribute):Connect(refreshOwned)
	end
	MarketplaceService.PromptProductPurchaseFinished:Connect(function(userId)
		if userId == player.UserId then
			requestPendingUntil = 0
			UiKit.show("Store")
			refreshOwned()
		end
	end)
	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(who)
		if who == player then
			requestPendingUntil = 0
			UiKit.show("Store")
			refreshOwned()
		end
	end)
	for _, pass in Products.PASSES do
		player:GetAttributeChangedSignal(`Pass_{pass.key}`):Connect(refreshOwned)
	end
	refreshOwned()
end

return StoreController

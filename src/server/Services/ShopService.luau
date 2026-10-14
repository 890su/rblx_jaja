--!strict
-- Meteor Shop (coins) and pedestal upgrades. Offers come from the global clock
-- (ShopOffers.forCycle), stock is tracked per player per cycle in the profile
-- so rejoining can't refill it. Bought meteors use a free pedestal or storage.

local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Types = require(Shared.Types)
local Economy = require(Shared.Config.Economy)
local Events = require(Shared.Config.Events)
local Shop = require(Shared.Config.Shop)
local Rarity = require(Shared.Config.Rarity)
local Theme = require(Shared.Theme)
local Clock = require(Shared.Clock)
local Format = require(Shared.Util.Format)
local ShopOffers = require(Shared.Util.ShopOffers)
local Remotes = require(Shared.Remotes)
local Locale = require(Shared.Locale)
local UpgradeMath = require(Shared.Util.UpgradeMath)
local Upgrades = require(Shared.Config.Upgrades)
local BaseLayout = require(Shared.Config.BaseLayout)

local Notifier = require(script.Parent.Parent.Util.Notifier)
local RateLimit = require(script.Parent.Parent.Util.RateLimit)
local DataService = require(script.Parent.DataService)
local StationService = require(script.Parent.StationService)
local WorldService = require(script.Parent.WorldService)
local TelemetryService = require(script.Parent.TelemetryService)
local SpeedService = require(script.Parent.SpeedService)

local ShopService = {}

local shopState: RemoteEvent
local currentCycle = -1
local currentOffers: { Types.ShopOffer } = {}
local buyLimit = RateLimit.new(6, 2)
local stateLimit = RateLimit.new(4, 1)

local function refreshCycle(): boolean
	local cycle = Clock.cycleIndex(Events.SHOP_RESTOCK_PERIOD)
	if cycle == currentCycle then
		return false
	end
	currentCycle = cycle
	currentOffers = ShopOffers.forCycle(cycle)
	return true
end

local function purchasesOf(profile: Types.PlayerProfile): { [string]: number }
	if profile.shop.cycle ~= currentCycle then
		profile.shop.cycle = currentCycle
		profile.shop.bought = {}
	end
	return profile.shop.bought
end

local function nextPedestalCost(profile: Types.PlayerProfile): number?
	if profile.pedestalCount >= Economy.PEDESTALS_MAX_COINS then
		return nil
	end
	return Economy.PEDESTAL_COSTS[profile.pedestalCount - Economy.PEDESTALS_START + 1]
end

local function pushState(player: Player)
	local profile = DataService.get(player)
	if not profile then
		return
	end
	local bought = purchasesOf(profile)
	player:SetAttribute("ShopHasPurchases", next(bought) ~= nil)
	local remaining = {}
	for slot, offer in currentOffers do
		remaining[slot] = math.max(0, offer.stock - (bought[tostring(slot)] or 0))
	end
	local state: Types.ShopState = {
		cycle = currentCycle,
		endsAt = (currentCycle + 1) * Events.SHOP_RESTOCK_PERIOD,
		offers = currentOffers,
		remaining = remaining,
	}
	shopState:FireClient(player, state)
	player:SetAttribute("PedestalCount", profile.pedestalCount)
	player:SetAttribute("NextPedestalCost", nextPedestalCost(profile))
	player:SetAttribute("Training", profile.training)
	player:SetAttribute("NextTrainingCost", UpgradeMath.cost("training", profile.training))
	for _, spec in Upgrades do
		player:SetAttribute(`Upgrade_{spec.key}`, UpgradeMath.level(profile, spec.key))
		player:SetAttribute(
			`UpgradeCost_{spec.key}`,
			UpgradeMath.cost(spec.key, UpgradeMath.level(profile, spec.key))
		)
	end
end

local function onBuy(player: Player, slot: unknown)
	if not buyLimit:allow(player) then
		return
	end
	if typeof(slot) ~= "number" or slot ~= math.floor(slot) or slot < 1 or slot > #Shop.SLOTS then
		return
	end
	local profile = DataService.get(player)
	if not profile then
		return
	end
	refreshCycle()
	local offer = currentOffers[slot]
	local bought = purchasesOf(profile)
	local key = tostring(slot)
	if (bought[key] or 0) >= offer.stock then
		Notifier.send(player, "shop_sold_out", nil, "warning")
	elseif not StationService.hasFreePedestal(player) and profile.flags.warehouseOwned ~= true then
		Notifier.send(player, "warehouse_required", nil, "warning")
	elseif profile.coins < offer.price then
		Notifier.send(player, "not_enough_coins", nil, "warning")
	else
		local outcome = StationService.give(player, {
			creatureId = offer.creatureId,
			rarity = offer.rarity,
			hatchAt = os.time() + Rarity.INFO[offer.rarity].hatchSeconds,
		})
		if outcome == "failed" then
			return
		end
		DataService.addCoins(player, -offer.price)
		bought[key] = (bought[key] or 0) + 1
		TelemetryService.economy(player, "sink", offer.price, "Shop", offer.creatureId)
		TelemetryService.funnel(player, "FirstShopBuy")
		local name = Theme.CREATURE_NAMES[offer.creatureId] or offer.rarity
		Notifier.send(
			player,
			if outcome == "stored" then "shop_bought_storage" else "shop_bought",
			{ rarity = Locale.ref(offer.rarity), creature = Locale.ref(name) },
			"success"
		)
	end
	pushState(player)
end

local function onBuyPedestal(player: Player)
	if not buyLimit:allow(player) then
		return
	end
	local profile = DataService.get(player)
	if not profile then
		return
	end
	local cost = nextPedestalCost(profile)
	if not cost then
		Notifier.send(player, "pedestals_all_unlocked", nil, "warning")
	elseif profile.coins < cost then
		Notifier.send(player, "need_coins", { amount = Format.short(cost) }, "warning")
	else
		DataService.addCoins(player, -cost)
		profile.pedestalCount += 1
		TelemetryService.economy(player, "sink", cost, "Upgrade", `pedestal{profile.pedestalCount}`)
		StationService.refresh(player)
		Notifier.send(player, "pedestal_unlocked", { number = profile.pedestalCount }, "success")
	end
	pushState(player)
end

local function onBuyUpgrade(player: Player, key: unknown, expectedLevel: unknown)
	if not buyLimit:allow(player) then
		return
	end
	if typeof(key) ~= "string" or not UpgradeMath.spec(key) then
		return
	end
	local profile = DataService.get(player)
	if not profile then
		return
	end
	if
		expectedLevel ~= nil
		and (typeof(expectedLevel) ~= "number" or expectedLevel ~= UpgradeMath.level(profile, key))
	then
		pushState(player)
		return
	end
	local outcome, cost = UpgradeMath.buy(profile, key)
	if outcome == "max" then
		Notifier.send(player, "upgrade_max", nil, "warning")
	elseif outcome == "funds" then
		Notifier.send(player, "need_coins", { amount = Format.short(cost) }, "warning")
	else
		DataService.sync(player)
		StationService.refresh(player)
		SpeedService.apply(player)
		TelemetryService.economy(
			player,
			"sink",
			cost,
			"Upgrade",
			`{key}{UpgradeMath.level(profile, key)}`
		)
		Notifier.send(player, "upgrade_bought", {
			name = Locale.ref(assert(UpgradeMath.spec(key)).title),
			level = UpgradeMath.level(profile, key),
		}, "success")
	end
	pushState(player)
end

function ShopService.pushState(player: Player)
	pushState(player)
end

function ShopService.debugOffers(): { Types.ShopOffer }
	require(script.Parent.Parent.Util.CommerceQA)()
	refreshCycle()
	return currentOffers
end

-- The physical prompt only opens a priced card; the buy button performs payment.
function ShopService.openFacility(player: Player, plot: WorldService.Plot, key: string): boolean
	local site = plot.buildSites[key]
	local profile = DataService.get(player)
	local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	local position = SpeedService.validatePosition(player)
	if
		not site
		or not profile
		or StationService.ownerOf(plot) ~= player
		or not humanoid
		or humanoid.Health <= 0
		or player:GetAttribute("Carrying") ~= nil
		or player:GetAttribute("ArenaActive") == true
		or player:GetAttribute("ArenaPrep") == true
		or not position
		or not WorldService.isInPlot(plot, position)
		or (position - site.Position).Magnitude > BaseLayout.purchaseDistance
		or UpgradeMath.level(profile, key) ~= 0
		or not stateLimit:allow(player)
	then
		return false
	end
	pushState(player)
	Remotes.event("OpenUpgrade"):FireClient(player, key)
	return true
end

function ShopService.init()
	shopState = Remotes.event("ShopState")
	refreshCycle()
	Remotes.event("ShopBuy").OnServerEvent:Connect(onBuy)
	Remotes.event("RequestShopState").OnServerEvent:Connect(function(player)
		if stateLimit:allow(player) then
			refreshCycle()
			pushState(player)
		end
	end)
	Remotes.event("BuyPedestal").OnServerEvent:Connect(onBuyPedestal)
	for _, plot in WorldService.getPlots() do
		for key, site in plot.buildSites do
			local prompt = site:FindFirstChildOfClass("ProximityPrompt")
			assert(prompt, "missing facility prompt").Triggered:Connect(function(player)
				ShopService.openFacility(player, plot, key)
			end)
		end
	end
	-- Unlock button on the next locked pedestal of your own station.
	for _, plot in WorldService.getPlots() do
		for _, pedestal in plot.pedestals do
			local prompt = pedestal:FindFirstChild("UnlockPrompt") :: ProximityPrompt?
			if prompt then
				prompt.Triggered:Connect(function(player)
					local character = player.Character
					local root = character
						and character:FindFirstChild("HumanoidRootPart") :: BasePart?
					if
						StationService.ownerOf(plot) == player
						and pedestal:GetAttribute("UnlockCost")
						and root
						and (root.Position - pedestal.Position).Magnitude <= 14
					then
						onBuyPedestal(player)
					end
				end)
			end
		end
	end
	Remotes.event("BuyTraining").OnServerEvent:Connect(function(player)
		onBuyUpgrade(player, "training", nil)
	end)
	Remotes.event("BuyUpgrade").OnServerEvent:Connect(onBuyUpgrade)
	DataService.onLoaded(function(player)
		pushState(player)
	end)
end

function ShopService.start()
	while true do
		task.wait(1)
		if refreshCycle() then
			for _, player in Players:GetPlayers() do
				pushState(player)
			end
			Notifier.all("shop_restocked", nil, "pickup")
		end
	end
end

return ShopService

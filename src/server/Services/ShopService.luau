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

local Notifier = require(script.Parent.Parent.Util.Notifier)
local RateLimit = require(script.Parent.Parent.Util.RateLimit)
local DataService = require(script.Parent.DataService)
local StationService = require(script.Parent.StationService)
local WorldService = require(script.Parent.WorldService)
local TelemetryService = require(script.Parent.TelemetryService)

local ShopService = {}

local shopState: RemoteEvent
local currentCycle = -1
local currentOffers: { Types.ShopOffer } = {}
local buyLimit = RateLimit.new(6, 2)

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

local function trainingCost(level: number): number?
	if level >= Economy.TRAINING_MAX then
		return nil
	end
	return math.floor(Economy.TRAINING_BASE_COST * Economy.TRAINING_COST_GROWTH ^ level)
end

local function pushState(player: Player)
	local profile = DataService.get(player)
	if not profile then
		return
	end
	local bought = purchasesOf(profile)
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
	player:SetAttribute("NextTrainingCost", trainingCost(profile.training))
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

local function onBuyTraining(player: Player)
	if not buyLimit:allow(player) then
		return
	end
	local profile = DataService.get(player)
	if not profile then
		return
	end
	local cost = trainingCost(profile.training)
	if not cost then
		return
	elseif profile.coins < cost then
		Notifier.send(player, "need_coins", { amount = Format.short(cost) }, "warning")
	else
		DataService.addCoins(player, -cost)
		profile.training += 1
		TelemetryService.economy(player, "sink", cost, "Upgrade", `training{profile.training}`)
		Notifier.send(player, "training_up", {
			level = profile.training,
			bonus = math.floor(profile.training * Economy.TRAINING_BONUS * 100),
		}, "success")
	end
	pushState(player)
end

function ShopService.pushState(player: Player)
	pushState(player)
end

function ShopService.init()
	shopState = Remotes.event("ShopState")
	refreshCycle()
	Remotes.event("ShopBuy").OnServerEvent:Connect(onBuy)
	Remotes.event("RequestShopState").OnServerEvent:Connect(function(player)
		if buyLimit:allow(player) then
			pushState(player)
		end
	end)
	Remotes.event("BuyPedestal").OnServerEvent:Connect(onBuyPedestal)
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
	Remotes.event("BuyTraining").OnServerEvent:Connect(onBuyTraining)
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

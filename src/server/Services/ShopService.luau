--!strict
-- Meteor Shop (coins) and pedestal upgrades. Offers come from the global clock
-- (ShopOffers.forCycle), stock is tracked per player per cycle in the profile
-- so rejoining can't refill it. Bought meteors go straight onto a pedestal.

local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Types = require(Shared.Types)
local Economy = require(Shared.Config.Economy)
local Events = require(Shared.Config.Events)
local Shop = require(Shared.Config.Shop)
local Theme = require(Shared.Theme)
local Clock = require(Shared.Clock)
local Format = require(Shared.Util.Format)
local ShopOffers = require(Shared.Util.ShopOffers)
local Remotes = require(Shared.Remotes)

local RateLimit = require(script.Parent.Parent.Util.RateLimit)
local DataService = require(script.Parent.DataService)
local StationService = require(script.Parent.StationService)

local ShopService = {}

local notify: RemoteEvent
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
		notify:FireClient(player, "Sold out — wait for the restock", "warning")
	elseif profile.coins < offer.price then
		notify:FireClient(player, `Not enough {Theme.CURRENCY}`, "warning")
	elseif not StationService.hasFreePedestal(profile) then
		notify:FireClient(player, "All pedestals are full!", "warning")
	elseif StationService.placeNew(player, offer.creatureId, nil) then
		DataService.addCoins(player, -offer.price)
		bought[key] = (bought[key] or 0) + 1
		local name = Theme.CREATURE_NAMES[offer.creatureId] or offer.rarity
		notify:FireClient(
			player,
			`Bought {offer.rarity} {Theme.ITEM} ({name}) — hatching!`,
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
		notify:FireClient(player, "All pedestals unlocked", "warning")
	elseif profile.coins < cost then
		notify:FireClient(player, `Need {Format.short(cost)} {Theme.CURRENCY}`, "warning")
	else
		DataService.addCoins(player, -cost)
		profile.pedestalCount += 1
		StationService.refresh(player)
		notify:FireClient(player, `Pedestal {profile.pedestalCount} unlocked!`, "success")
	end
	pushState(player)
end

function ShopService.pushState(player: Player)
	pushState(player)
end

function ShopService.init()
	notify = Remotes.event("Notify")
	shopState = Remotes.event("ShopState")
	refreshCycle()
	Remotes.event("ShopBuy").OnServerEvent:Connect(onBuy)
	Remotes.event("BuyPedestal").OnServerEvent:Connect(onBuyPedestal)
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
			notify:FireAllClients("The Meteor Shop restocked!", "pickup")
		end
	end
end

return ShopService

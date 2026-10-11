--!strict
-- Game passes and developer products (GDD §6).
-- * Passes: ownership checked before other systems load (DataService preload)
--   and on in-game purchase; exposed as server-set Player attributes
--   Pass_<key> that other services read.
-- * Products: ProcessReceipt is idempotent (PurchaseId stored in the profile)
--   and grants before returning PurchaseGranted; the profile is saved at once.
-- Items with id 0 (not yet created in Creator Dashboard) are ignored.

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Types = require(Shared.Types)
local Products = require(Shared.Config.Products)
local Creatures = require(Shared.Config.Creatures)
local Rarity = require(Shared.Config.Rarity)
local Theme = require(Shared.Theme)
local Odds = require(Shared.Util.Odds)
local Remotes = require(Shared.Remotes)

local DataService = require(script.Parent.DataService)
local StationService = require(script.Parent.StationService)
local ShopService = require(script.Parent.ShopService)

local MAX_RECEIPTS = 100

local MonetizationService = {}

local rng = Random.new()
local passByKey: { [string]: Products.Pass } = {}
local passById: { [number]: Products.Pass } = {}
local productById: { [number]: Products.Product } = {}

local function notify(player: Player, message: string, kind: string?)
	Remotes.event("Notify"):FireClient(player, message, kind)
end

local function setPass(player: Player, key: string)
	player:SetAttribute(`Pass_{key}`, true)
end

function MonetizationService.owns(player: Player, key: string): boolean
	return player:GetAttribute(`Pass_{key}`) == true
end

local function checkPasses(player: Player)
	for _, pass in Products.PASSES do
		if pass.id ~= 0 then
			local ok, owned = pcall(function()
				return MarketplaceService:UserOwnsGamePassAsync(player.UserId, pass.id)
			end)
			if ok and owned then
				setPass(player, pass.key)
			end
		end
	end
end

-- Rolls a crate creature: rarity by CRATE_ODDS, then uniform within rarity.
-- Exactly the odds shown in the odds window (OddsController).
function MonetizationService.rollCrate(random: Random): string
	local rarity = Odds.roll(Products.CRATE_ODDS, Rarity.ORDER, random)
	local pool = {}
	for _, creature in Creatures.LIST do
		if creature.rarity == rarity then
			table.insert(pool, creature.id)
		end
	end
	return pool[random:NextInteger(1, #pool)]
end

local function giveCreature(player: Player, creatureId: string, hatched: boolean): string
	local creature = Creatures.BY_ID[creatureId]
	local state: Types.PedestalState = {
		creatureId = creatureId,
		rarity = creature.rarity,
		hatchAt = if hatched then nil else os.time() + Rarity.INFO[creature.rarity].hatchSeconds,
	}
	return StationService.give(player, state)
end

-- Product handlers return true when the grant fully succeeded.
local GRANTS: { [string]: (player: Player, profile: Types.PlayerProfile) -> boolean } = {
	StarterPack = function(player, profile)
		if profile.flags.starterPack then
			return true -- already granted once; consume without double-granting
		end
		profile.flags.starterPack = true
		for _, id in Products.STARTER_CREATURES do
			giveCreature(player, id, true)
		end
		profile.shieldUntil = math.max(profile.shieldUntil, os.time())
			+ Products.STARTER_SHIELD_SECONDS
		notify(player, "Starter Pack unlocked! Enjoy your new creatures", "success")
		return true
	end,
	Shield15 = function(player, profile)
		profile.shieldUntil = math.max(profile.shieldUntil, os.time()) + Products.SHIELD_SECONDS
		notify(player, `{Theme.BASE} shielded for 15 minutes`, "success")
		return true
	end,
	InstantHatch = function(player, profile)
		local now = os.time()
		for _, state in profile.pedestals do
			if state.hatchAt and state.hatchAt > now then
				state.hatchAt = now
			end
		end
		StationService.refresh(player)
		notify(player, "Everything hatched!", "success")
		return true
	end,
	Restock = function(player, profile)
		profile.shop.bought = {}
		ShopService.pushState(player)
		notify(player, "Your Meteor Shop stock is refilled", "success")
		return true
	end,
	ServerLuck = function(player)
		local now = workspace:GetServerTimeNow()
		local current = (workspace:GetAttribute("ServerLuckUntil") :: number?) or 0
		workspace:SetAttribute(
			"ServerLuckUntil",
			math.max(current, now) + Products.SERVER_LUCK.seconds
		)
		workspace:SetAttribute("ServerLuckBoost", Products.SERVER_LUCK.boost)
		Remotes.event("Notify")
			:FireAllClients(`{player.DisplayName} activated Server Luck! x2 rare meteors`, "pickup")
		return true
	end,
}

local function crateGrant(count: number): (player: Player, profile: Types.PlayerProfile) -> boolean
	return function(player)
		local names = {}
		for _ = 1, count do
			local id = MonetizationService.rollCrate(rng)
			giveCreature(player, id, true)
			table.insert(names, Theme.CREATURE_NAMES[id] or id)
			Remotes.event("Fx")
				:FireClient(player, "crate", Vector3.zero, Creatures.BY_ID[id].rarity)
		end
		notify(player, `Crate: {table.concat(names, ", ")}`, "success")
		return true
	end
end
GRANTS.Crate1 = crateGrant(1)
GRANTS.Crate3 = crateGrant(3)
GRANTS.Crate10 = crateGrant(10)

local function processReceipt(receipt: { [string]: any }): Enum.ProductPurchaseDecision
	local player = Players:GetPlayerByUserId(receipt.PlayerId)
	local profile = player and DataService.get(player)
	if not player or not profile then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local purchaseId = tostring(receipt.PurchaseId)
	if profile.purchases[purchaseId] then
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end
	local product = productById[receipt.ProductId]
	local grant = product and GRANTS[product.key]
	if not grant then
		warn(`[Monetization] unknown product {receipt.ProductId}`)
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local ok, granted = pcall(grant, player, profile)
	if not ok or not granted then
		warn(`[Monetization] grant failed for {product.key}: {granted}`)
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	profile.purchases[purchaseId] = os.time()
	-- Keep only the newest receipts.
	local count = 0
	local oldestId, oldestTime = nil, math.huge
	for id, time in profile.purchases do
		count += 1
		if time < oldestTime then
			oldestId, oldestTime = id, time
		end
	end
	if count > MAX_RECEIPTS and oldestId then
		profile.purchases[oldestId] = nil
	end
	DataService.saveNow(player)
	return Enum.ProductPurchaseDecision.PurchaseGranted
end

-- Studio QA only (DebugService): run a product grant / fake a pass.
function MonetizationService.debugGrant(player: Player, key: string): boolean
	local profile = DataService.get(player)
	local grant = GRANTS[key]
	return profile ~= nil and grant ~= nil and grant(player, profile)
end

function MonetizationService.debugPass(player: Player, key: string)
	setPass(player, key)
	StationService.refresh(player)
end

function MonetizationService.init()
	for _, pass in Products.PASSES do
		passByKey[pass.key] = pass
		if pass.id ~= 0 then
			passById[pass.id] = pass
		end
	end
	for _, product in Products.PRODUCTS do
		if product.id ~= 0 then
			productById[product.id] = product
		end
	end
	DataService.onPreload(function(player)
		checkPasses(player)
	end)
	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, passId, purchased)
		local pass = passById[passId]
		if purchased and pass then
			setPass(player, pass.key)
			StationService.refresh(player)
			notify(player, `{pass.name} unlocked!`, "success")
		end
	end)
	MarketplaceService.ProcessReceipt = processReceipt
end

return MonetizationService

--!strict
-- Game passes and developer products (GDD §6).
-- * Passes: ownership checked before other systems load (DataService preload)
--   and on in-game purchase; exposed as server-set Player attributes
--   Pass_<key> that other services read.
-- * Products: ProcessReceipt is idempotent (PurchaseId stored in the profile)
--   and acknowledges only after the receipt is in LastSavedData.
-- Items with id 0 (not yet created in Creator Dashboard) are ignored.

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local PolicyService = game:GetService("PolicyService")
local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Types = require(Shared.Types)
local Products = require(Shared.Config.Products)
local Creatures = require(Shared.Config.Creatures)
local Rarity = require(Shared.Config.Rarity)
local Odds = require(Shared.Util.Odds)
local Remotes = require(Shared.Remotes)
local Locale = require(Shared.Locale)

local Notifier = require(script.Parent.Parent.Util.Notifier)
local DataService = require(script.Parent.DataService)
local StationService = require(script.Parent.StationService)
local ShopService = require(script.Parent.ShopService)

local PurchaseGrants = require(script.Parent.Parent.Data.PurchaseGrants)
local RateLimit = require(script.Parent.Parent.Util.RateLimit)
local purchaseLimit = RateLimit.new(2, 0.5)
local busy: { [Player]: boolean } = {}
local productByKey: { [string]: Products.Product } = {}
local RANDOM_PRODUCTS: { [string]: boolean } =
	{ Crate1 = true, Crate3 = true, Crate10 = true, ServerLuck = true }

local MonetizationService = {}

local rng = Random.new()
local passByKey: { [string]: Products.Pass } = {}
local passById: { [number]: Products.Pass } = {}
local productById: { [number]: Products.Product } = {}

local function notify(player: Player, key: string, kind: string?, args: Locale.Args?)
	Notifier.send(player, key, args, kind)
end

local function setPass(player: Player, key: string)
	player:SetAttribute(`Pass_{key}`, true)
end

function MonetizationService.owns(player: Player, key: string): boolean
	return player:GetAttribute(`Pass_{key}`) == true
end

local function retry(query: () -> any): any
	for attempt = 1, 3 do
		local ok, result = pcall(query)
		if ok then
			return result
		end
		if attempt < 3 then
			task.wait(attempt)
		end
	end
	error("Purchase entitlement/policy check unavailable")
end

local function checkPasses(player: Player)
	-- Simulated Studio clients have negative IDs and cannot query account APIs.
	-- This never affects real accounts or live servers.
	if RunService:IsStudio() and player.UserId < 0 then
		player:SetAttribute("PaidRandomItemsAllowed", true)
		player:SetAttribute("PaidItemTradingAllowed", true)
		player:SetAttribute("PolicyReady", true)
		return
	end
	local policy = retry(function()
		return PolicyService:GetPolicyInfoForPlayerAsync(player)
	end)
	player:SetAttribute("PaidRandomItemsAllowed", policy.ArePaidRandomItemsRestricted == false)
	player:SetAttribute("PaidItemTradingAllowed", policy.IsPaidItemTradingAllowed == true)
	player:SetAttribute("PolicyReady", true)
	for _, pass in Products.PASSES do
		if pass.id ~= 0 then
			local owned = retry(function()
				return MarketplaceService:UserOwnsGamePassAsync(player.UserId, pass.id)
			end)
			if owned then
				setPass(player, pass.key)
			end
		end
	end
end

-- Rolls a crate creature: rarity by CRATE_ODDS, then uniform within rarity.
-- Exactly the odds shown in the odds window (StoreController).
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

local function restoreLuck(profile: Types.PlayerProfile)
	local remaining = profile.serverLuckUntil - os.time()
	if remaining > 0 then
		local current = (workspace:GetAttribute("ServerLuckUntil") :: number?) or 0
		workspace:SetAttribute(
			"ServerLuckUntil",
			math.max(current, workspace:GetServerTimeNow() + remaining)
		)
		workspace:SetAttribute("ServerLuckBoost", Products.SERVER_LUCK.boost)
	end
end

local function grant(
	player: Player,
	profile: Types.PlayerProfile,
	key: string,
	purchaseId: string
): boolean
	local ids: { string } = {}
	local restricted = player:GetAttribute("PaidRandomItemsAllowed") ~= true
	local count = ({ Crate1 = 1, Crate3 = 3, Crate10 = 10 } :: { [string]: number })[key]
	if key == "StarterPack" then
		ids = table.clone(Products.STARTER_CREATURES) -- a second charged receipt still gets its full reward
	elseif count then
		for _ = 1, count do
			table.insert(
				ids,
				if restricted
					then Products.RESTRICTED_REWARD
					else MonetizationService.rollCrate(rng)
			)
		end
	elseif key == "ServerLuck" and restricted then
		ids = { Products.RESTRICTED_REWARD }
	elseif not table.find({ "Shield15", "InstantHatch", "Restock", "ServerLuck" }, key) then
		return false
	end
	local globalUntil = (workspace:GetAttribute("ServerLuckUntil") :: number?) or 0
	local luckUntil = math.max(
		os.time(),
		profile.serverLuckUntil,
		os.time() + math.max(0, globalUntil - workspace:GetServerTimeNow())
	) + Products.SERVER_LUCK.seconds
	PurchaseGrants.apply(profile, key, purchaseId, ids, os.time(), luckUntil, function()
		return HttpService:GenerateGUID(false)
	end)
	-- Reserve the absolute expiry so concurrent purchases stack. The persisted
	-- expiry restores the purchased benefit when the buyer rejoins.
	restoreLuck(profile)
	return true
end

local function afterGrant(player: Player, profile: Types.PlayerProfile, key: string)
	player:SetAttribute("StarterPackOwned", profile.flags.starterPack == true)
	StationService.refresh(player)
	if key == "Restock" then
		ShopService.pushState(player)
	end
	local message = ({
		StarterPack = "starter_pack",
		Shield15 = "shielded",
		InstantHatch = "all_hatched",
		Restock = "shop_refilled",
	} :: { [string]: string })[key]
	if player:GetAttribute("PaidRandomItemsAllowed") ~= true and RANDOM_PRODUCTS[key] then
		message = "purchase_fixed_reward"
	end
	if key:sub(1, 5) == "Crate" then
		message = message or "purchase_delivered"
	end
	if key == "ServerLuck" and not message then
		Notifier.all("server_luck", { player = player.DisplayName }, "pickup")
	elseif message then
		notify(player, message, "success")
	end
end

local function receiptForPlayer(
	player: Player,
	receipt: { [string]: any }
): Enum.ProductPurchaseDecision
	local profile = DataService.awaitReady(player)
	if not profile then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	while busy[player] and player.Parent == Players and DataService.get(player) == profile do
		task.wait(0.1)
	end
	if busy[player] or DataService.get(player) ~= profile then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	busy[player] = true
	local purchaseId = tostring(receipt.PurchaseId)
	local product = productById[receipt.ProductId]
	local ok, confirmed = pcall(function()
		if not profile.purchases[purchaseId] then
			if not product or not grant(player, profile, product.key, purchaseId) then
				return false
			end
		end
		-- Roblox does not retry NotProcessedYet on a timer. Keep this callback
		-- yielding during a transient outage; release it only on save/session loss.
		while player.Parent == Players and DataService.get(player) == profile do
			if
				DataService.saveConfirmed(player, function(saved)
					return saved.purchases[purchaseId] ~= nil
				end)
			then
				return true
			end
		end
		return false
	end)
	busy[player] = nil
	if not ok or not confirmed then
		warn(`[Monetization] receipt {purchaseId} pending: {confirmed}`)
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	if product then
		local effectOk, effectErr = pcall(function()
			afterGrant(player, profile, product.key)
			return true
		end)
		if not effectOk then
			warn(`[Monetization] display failed: {effectErr}`)
		end
	end
	return Enum.ProductPurchaseDecision.PurchaseGranted
end

local function processReceipt(receipt: { [string]: any }): Enum.ProductPurchaseDecision
	local player = Players:GetPlayerByUserId(receipt.PlayerId)
	if not player then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	return receiptForPlayer(player, receipt)
end

function MonetizationService.debugReceipt(player: Player, key: string, purchaseId: string): string
	assert(
		RunService:IsStudio() and player.UserId < 0,
		"receipt QA requires a simulated Studio client"
	)
	local product = assert(productByKey[key], "unknown QA product")
	return processReceipt({
		PlayerId = player.UserId,
		ProductId = product.id,
		PurchaseId = purchaseId,
	}).Name
end

-- Called only through the Studio-gated DebugService.
function MonetizationService.debugGrant(player: Player, key: string): boolean
	local profile = DataService.get(player)
	if not profile then
		return false
	end
	local result = grant(player, profile, key, `debug_{HttpService:GenerateGUID(false)}`)
	if result then
		afterGrant(player, profile, key)
	end
	return result
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
		productByKey[product.key] = product
		if product.id ~= 0 then
			productById[product.id] = product
		end
	end
	DataService.onPreload(function(player, profile)
		checkPasses(player)
		player:SetAttribute("StarterPackOwned", profile.flags.starterPack == true)
		restoreLuck(profile)
	end)
	Remotes.event("RequestPurchase").OnServerEvent:Connect(function(player, kind: any, key: any)
		if
			not purchaseLimit:allow(player)
			or typeof(key) ~= "string"
			or typeof(kind) ~= "string"
		then
			return
		end
		local profile = DataService.get(player)
		if not profile or player:GetAttribute("PolicyReady") ~= true then
			return
		end
		if kind == "pass" then
			local pass = passByKey[key]
			if pass and pass.id ~= 0 and not MonetizationService.owns(player, key) then
				local ok, err = pcall(function()
					MarketplaceService:PromptGamePassPurchase(player, pass.id)
				end)
				if not ok then
					warn(err)
				end
			end
		elseif kind == "product" then
			local product = productByKey[key]
			if
				not product
				or product.id == 0
				or (key == "StarterPack" and profile.flags.starterPack)
			then
				return
			end
			if RANDOM_PRODUCTS[key] and player:GetAttribute("PaidRandomItemsAllowed") ~= true then
				notify(player, "purchase_restricted", "warning")
				return
			end
			local ok, err = pcall(function()
				MarketplaceService:PromptProductPurchase(player, product.id)
			end)
			if not ok then
				warn(err)
			end
		end
	end)
	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, passId, purchased)
		local pass = passById[passId]
		if purchased and pass then
			setPass(player, pass.key)
			StationService.refresh(player)
			notify(player, "pass_unlocked", "success", { pass = Locale.ref(pass.name) })
		end
	end)
	MarketplaceService.ProcessReceipt = processReceipt
end

return MonetizationService

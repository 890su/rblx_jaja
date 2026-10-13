--!strict
-- Real service mutations and client controller observations, isolated saves.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")
local Services = script.Parent.Parent.Services
local Data = require(Services.DataService)
local Station = require(Services.StationService)
local Shop = require(Services.ShopService)
local Speed = require(Services.SpeedService)
local Steal = require(Services.StealService)
local Carry = require(Services.CarryService)
local Book = require(Services.CollectionService)
local Monetization = require(Services.MonetizationService)
local Shared = ReplicatedStorage.Shared
local Specs = require(Shared.Config.Upgrades)
local Products = require(Shared.Config.Products)
local UpgradeMath = require(Shared.Util.UpgradeMath)
local Checks = {}
function Checks.run(): any
	require(script.Parent.Parent.Util.CommerceQA)()
	local remote = Instance.new("RemoteEvent")
	remote.Name, remote.Parent = "CommerceQA", ReplicatedStorage
	local nonce = 0
	local replies: { [Player]: any } = {}
	local ready: { [Player]: boolean } = {}
	local stages: { [Player]: string } = {}
	local checks: { string } = {}
	local connection = remote.OnServerEvent:Connect(function(player, token: any, result: any)
		if token == "stage" and typeof(result) == "string" then
			stages[player] = string.sub(result, 1, 100)
			return
		end
		if token == "ready" then
			ready[player] = true
			return
		end
		if token == nonce and typeof(result) == "table" then
			replies[player] = result
		end
	end)
	local function check(name: string, ok: boolean)
		assert(ok, name)
		table.insert(checks, name)
	end
	local function waitFor(test: () -> boolean, seconds: number): boolean
		local deadline = os.clock() + seconds
		repeat
			if test() then
				return true
			end
			task.wait(0.1)
		until os.clock() > deadline
		return false
	end
	local joined: { Player } = {}
	local ok, result = pcall(function(): any
		check(
			"two clients loaded",
			waitFor(function()
				joined = Players:GetPlayers()
				if #joined ~= 2 then
					return false
				end
				for _, p in joined do
					if
						not Data.get(p)
						or not Station.getPlot(p)
						or not p.Character
						or not p.Character:FindFirstChild("HumanoidRootPart")
					then
						return false
					end
				end
				return true
			end, 120)
		)
		task.wait(1)
		local owner, buyer = joined[1], joined[2]
		check(
			"both client UI probes subscribed",
			waitFor(function()
				return ready[owner] == true and ready[buyer] == true
			end, 60)
		)
		local ownerData = assert(Data.get(owner), "owner data")
		local buyerData = assert(Data.get(buyer), "buyer data")
		local ownerPlot = assert(Station.getPlot(owner), "owner plot")
		local buyerPlot = assert(Station.getPlot(buyer), "buyer plot")
		local function at(player: Player, position: Vector3)
			Speed.markTeleport(player, position)
			local character = assert(player.Character, "QA character")
			local root = character:FindFirstChild("HumanoidRootPart") :: BasePart
			root.Anchored = true
			character:PivotTo(CFrame.new(position))
		end
		local function client(player: Player, op: string, key: any): any
			nonce += 1
			replies[player] = nil
			remote:FireClient(player, nonce, op, key)
			local replied = waitFor(function()
				return replies[player] ~= nil
			end, 40)
			check(op .. " client replied; last stage: " .. (stages[player] or "none"), replied)
			check(
				op
					.. " client executed"
					.. (if replies[player].ok then "" else ": " .. tostring(replies[player].result)),
				replies[player].ok == true
			)
			return replies[player].result
		end
		at(owner, ownerPlot.center + Vector3.new(0, 4, 55))
		at(buyer, buyerPlot.center + Vector3.new(0, 4, 55))
		Data.setSpeed(buyer, 10000)
		ownerData.index = {}
		buyerData.index = {}
		local menus = client(buyer, "menus", nil)
		check("seven menus toggle exclusively and odds navigate", menus.menus == 7 and menus.odds)
		Data.addCoins(buyer, 1e7)
		Shop.pushState(buyer)
		local offer = Shop.debugOffers()[1]
		buyerData.shop.bought["1"] = offer.stock - 1
		Shop.pushState(buyer)
		local before = buyerData.coins
		client(buyer, "buy", 1)
		check(
			"coin purchase charges exact price",
			buyerData.coins == before - offer.price and buyerData.shop.bought["1"] == offer.stock
		)
		local view = client(buyer, "shop", nil)
		check(
			"sold out is disabled and close retains free mouse: " .. HttpService:JSONEncode(view),
			not view.enabled and view.soldOut and view.modal and view.mouseReleased
		)
		check("shop shows six model portraits", view.previews == 6)
		before = buyerData.coins
		client(buyer, "buy", 1)
		check("sold out cannot charge again", buyerData.coins == before)
		client(buyer, "buy", 0 / 0)
		check("invalid slot cannot charge", buyerData.coins == before)
		task.wait(1)
		for _, spec in Specs do
			before = buyerData.coins
			local cost = assert(UpgradeMath.cost(spec.key, 0), "upgrade cost")
			client(buyer, "upgrade", spec.key)
			check(
				spec.key .. " purchase applies exactly once",
				UpgradeMath.level(buyerData, spec.key) == 1 and buyerData.coins == before - cost
			)
		end
		buyerData.treadmill = 10
		Shop.pushState(buyer)
		task.wait(0.6)
		before = buyerData.coins
		client(buyer, "upgrade", "treadmill")
		check("max upgrade cannot charge", buyerData.coins == before and buyerData.treadmill == 10)
		local function fillOwner()
			ownerData.pedestals = {}
			for slot = 1, 3 do
				ownerData.pedestals[tostring(slot)] = {
					id = `qa-owner-{slot}`,
					creatureId = "pebblit",
					rarity = "Common",
					paid = false,
				}
			end
			ownerData.playtimeTotal = 1000
			ownerData.rebirths = 1
			ownerData.shieldUntil = 0
			buyerData.pedestals = {}
			buyerData.storage = {}
			Station.refresh(owner)
			Station.refresh(buyer)
			at(owner, ownerPlot.center + Vector3.new(0, 4, 55))
			at(buyer, ownerPlot.pedestals[1].Position + Vector3.new(8, 4, 0))
			task.wait(0.3)
			Steal.debugReset(owner)
			Steal.debugReset(buyer)
		end
		-- Collection includes hatch-complete storage even with a full base.
		buyerData.pedestals = {}
		for slot = 1, 3 do
			buyerData.pedestals[tostring(slot)] =
				{ id = `qa-buyer-{slot}`, creatureId = "pebblit", rarity = "Common", paid = false }
		end
		buyerData.storage = {
			{ id = "qa-book", creatureId = "comet_cat", rarity = "Rare", paid = false },
			{
				id = "qa-unhatched",
				creatureId = "emberfox",
				rarity = "Uncommon",
				hatchAt = os.time() + 600,
			},
		}
		Station.refresh(buyer)
		Book.push(buyer)
		Book.push(owner)
		local bookView = client(buyer, "index", nil)
		check(
			"book shows known creature and black unknown model",
			bookView.known == 1
				and bookView.dark > 0
				and buyerData.index.comet_cat == true
				and buyerData.index.emberfox ~= true
		)
		check("book snapshot does not leak between players", not ownerData.index.comet_cat)
		buyerData.storage = {}
		Book.push(buyer)
		check("collection survives loss of owned creature", buyerData.index.comet_cat == true)
		-- All configured developer-product receipts, with real saved markers.
		for _, product in Products.PRODUCTS do
			local receipt = "QA_commerce_" .. HttpService:GenerateGUID(false)
			check(
				product.key .. " receipt saved",
				Monetization.debugReceipt(buyer, product.key, receipt) == "PurchaseGranted"
					and buyerData.purchases[receipt] ~= nil
			)
			local count = #buyerData.storage
			check(
				product.key .. " duplicate receipt idempotent",
				Monetization.debugReceipt(buyer, product.key, receipt) == "PurchaseGranted"
					and #buyerData.storage == count
			)
		end
		check("late hatch checkout leaves credit", buyerData.hatchCredits == 1)
		buyerData.storage = {
			{
				id = "qa-credit",
				creatureId = "comet_cat",
				rarity = "Rare",
				hatchAt = os.time() + 600,
			},
		}
		task.wait(2.1)
		client(buyer, "credit", "InstantHatch")
		check(
			"hatch credit applies and is consumed once",
			buyerData.hatchCredits == 0 and (buyerData.storage[1].hatchAt or 0) <= os.time()
		)
		for _, pass in Products.PASSES do
			Monetization.debugPass(buyer, pass.key)
			check(pass.key .. " entitlement applied", buyer:GetAttribute(`Pass_{pass.key}`) == true)
		end
		-- Restore neutral paid entitlements for stealing fixtures.
		buyer:SetAttribute("Pass_Expansion", nil)
		fillOwner()
		check("short hold rejected", not Steal.debugAttempt(buyer, owner, 1, 0))
		ownerData.playtimeTotal = 0
		check("new-player protection enforced", not Steal.debugAttempt(buyer, owner, 1, 2))
		ownerData.playtimeTotal = 1000
		ownerData.shieldUntil = os.time() + 60
		check("shield enforced", not Steal.debugAttempt(buyer, owner, 1, 2))
		ownerData.shieldUntil = 0
		ownerData.pedestals["1"].paid = true
		buyer:SetAttribute("PaidItemTradingAllowed", false)
		check("paid transfer restriction enforced", not Steal.debugAttempt(buyer, owner, 1, 2))
		buyer:SetAttribute("PaidItemTradingAllowed", true)
		ownerData.pedestals["1"].paid = false
		ownerData.pedestals["1"].rarity = "Mythic"
		ownerData.pedestals["1"].creatureId = "big_bang_bunny"
		check(
			"Mythic minimum owner population enforced",
			not Steal.debugAttempt(buyer, owner, 1, 2)
		)
		ownerData.pedestals["1"].rarity = "Common"
		ownerData.pedestals["1"].creatureId = "pebblit"
		for slot = 1, 3 do
			buyerData.pedestals[tostring(slot)] =
				{ id = `qa-full-{slot}`, creatureId = "pebblit", rarity = "Common" }
		end
		check("full thief base rejected", not Steal.debugAttempt(buyer, owner, 1, 2))
		buyerData.pedestals = {}
		at(buyer, ownerPlot.center + Vector3.new(0, 4, 55))
		check("far-away steal rejected", not Steal.debugAttempt(buyer, owner, 1, 2))
		at(buyer, ownerPlot.pedestals[1].Position + Vector3.new(8, 4, 0))
		check("valid neighboring-base theft starts", Steal.debugAttempt(buyer, owner, 1, 2))
		check(
			"stolen creature is in escrow and owner gets chase",
			ownerData.pedestals["1"] == nil
				and Carry.get(buyer) ~= nil
				and owner:GetAttribute("ChaseUntil") ~= nil
		)
		local root =
			assert(buyer.Character, "buyer character"):FindFirstChild("HumanoidRootPart") :: BasePart
		at(owner, root.Position + Vector3.new(2, 0, 0))
		check("owner catch returns same item", waitFor(function()
			return Carry.get(buyer) == nil and ownerData.pedestals["1"] ~= nil
		end, 30) and ownerData.pedestals["1"].id == "qa-owner-1")
		fillOwner()
		check("second valid theft starts", Steal.debugAttempt(buyer, owner, 1, 2))
		at(buyer, buyerPlot.center + Vector3.new(0, 4, 0))
		check("delivery commits exactly one stolen creature", waitFor(function()
			return Carry.get(buyer) == nil and Station.creatureCount(buyerData) == 1
		end, 30) and ownerData.pedestals["1"] == nil and next(ownerData.outgoingTransfers) == nil)
		at(buyer, ownerPlot.pedestals[2].Position + Vector3.new(8, 4, 0))
		check("thief cooldown enforced", not Steal.debugAttempt(buyer, owner, 2, 2))
		fillOwner()
		check("third valid theft starts", Steal.debugAttempt(buyer, owner, 1, 2))
		local humanoid =
			assert(buyer.Character, "buyer character"):FindFirstChildOfClass("Humanoid")
		assert(humanoid, "QA humanoid").Health = 0
		check(
			"thief death returns escrowed creature",
			waitFor(function()
				return Carry.get(buyer) == nil and ownerData.pedestals["1"] ~= nil
			end, 30)
		)
		return { ok = true, checks = checks, players = 2, ui = menus.layout }
	end)
	for _, player in joined do
		local carry = Carry.get(player)
		if carry then
			Carry.drop(player, Vector3.zero)
		end
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		if root and root:IsA("BasePart") then
			root.Anchored = false
		end
	end
	connection:Disconnect()
	remote:Destroy()
	return if ok then result else { ok = false, error = tostring(result), checks = checks }
end
return Checks

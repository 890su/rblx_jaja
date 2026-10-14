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
local Inventory = require(Shared.Util.StationInventory)
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
		require(script.Parent.ZoneProgressionChecks).run(buyer, at, check)
		at(buyer, buyerPlot.center + Vector3.new(0, 4, 55))
		check(
			"fresh plot starts with neither facility",
			buyerData.treadmill == 0
				and buyerData.flags.warehouseOwned ~= true
				and not buyerPlot.treadmill:IsDescendantOf(workspace)
				and not buyerPlot.warehouse:IsDescendantOf(workspace)
		)
		at(buyer, buyerPlot.treadmill.Position + Vector3.new(0, 3, 0))
		task.wait(1.2)
		check("unbuilt treadmill cannot train", buyer:GetAttribute("OnTreadmill") ~= true)
		local initialCoins = buyerData.coins
		check("owner opens facility purchase", Shop.openFacility(buyer, buyerPlot, "treadmill"))
		local facilityView = client(buyer, "facility", "treadmill")
		check(
			"purchase card shows install price without charging",
			facilityView.open
				and string.find(facilityView.label, "250", 1, true) ~= nil
				and buyerData.coins == initialCoins
		)
		check("foreign facility offers hidden", facilityView.foreign == 0)
		check("foreign build site rejected", not Shop.openFacility(buyer, ownerPlot, "treadmill"))
		client(buyer, "upgrade", { key = "treadmill", expected = 0 })
		check(
			"poor install cannot charge or create geometry",
			buyerData.coins == initialCoins
				and buyerData.treadmill == 0
				and not buyerPlot.treadmill:IsDescendantOf(workspace)
		)
		at(buyer, buyerPlot.center + Vector3.new(0, 4, 55))
		check("distant build site rejected", not Shop.openFacility(buyer, buyerPlot, "warehouse"))
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
		local priorPedestals = buyerData.pedestals
		local priorStock = buyerData.shop.bought["1"]
		buyerData.pedestals = {}
		for slot = 1, Station.capacity(buyer, buyerData) do
			buyerData.pedestals[tostring(slot)] =
				{ id = `full-{slot}`, creatureId = "pebblit", rarity = "Common" }
		end
		Station.refresh(buyer)
		client(buyer, "buy", 1)
		check(
			"full base without warehouse cannot buy overflow",
			buyerData.coins == before
				and buyerData.shop.bought["1"] == priorStock
				and #buyerData.storage == 0
		)
		buyerData.pedestals = priorPedestals
		Station.refresh(buyer)
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
		local unbuiltItem = buyerData.pedestals["1"]
		if unbuiltItem then
			at(buyer, buyerPlot.warehouse.Position + Vector3.new(0, -2.2, -5))
			client(
				buyer,
				"stationAction",
				{ action = "store", slot = 1, expectedSlot = Inventory.key(unbuiltItem) }
			)
			check(
				"unbought warehouse cannot store",
				buyerData.pedestals["1"] == unbuiltItem and #buyerData.storage == 0
			)
			check("unbought warehouse cannot open", not Station.openWarehouse(buyer, buyerPlot))
		end
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
		check(
			"purchases create real facilities",
			buyerPlot.treadmill:IsDescendantOf(workspace)
				and buyerPlot.warehouse:IsDescendantOf(workspace)
		)
		before = buyerData.coins
		client(buyer, "upgrade", { key = "treadmill", expected = 0 })
		check(
			"stale install cannot buy next upgrade",
			buyerData.treadmill == 1 and buyerData.coins == before
		)
		client(buyer, "upgrade", "warehouse")
		check(
			"warehouse cannot charge twice",
			buyerData.coins == before and buyerData.flags.warehouseOwned == true
		)
		at(buyer, buyerPlot.treadmill.Position + Vector3.new(0, 3, 0))
		task.wait(1.2)
		check("installed treadmill trains", buyer:GetAttribute("OnTreadmill") == true)
		at(buyer, buyerPlot.center + Vector3.new(0, 4, 55))
		check(
			"facility ownership saved",
			Data.saveConfirmed(buyer, function(saved)
				return saved.treadmill == 1
					and saved.flags.warehouseOwned == true
					and saved.schema == 4
			end)
		)
		buyerData.treadmill = 11
		Shop.pushState(buyer)
		task.wait(0.6)
		before = buyerData.coins
		client(buyer, "upgrade", "treadmill")
		check("max upgrade cannot charge", buyerData.coins == before and buyerData.treadmill == 11)
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
		-- Physical locker access and real remote actions, with isolated saves.
		local storedOriginal = {
			id = "warehouse-original",
			creatureId = "pebblit",
			rarity = "Common",
			paid = true,
			mutation = "Golden",
			hatchAt = os.time() + 3600,
		}
		local storedIncoming =
			{ id = "warehouse-incoming", creatureId = "comet_cat", rarity = "Rare", paid = false }
		buyerData.pedestals = { ["1"] = storedOriginal }
		buyerData.storage = { storedIncoming }
		Station.refresh(buyer)
		local warehouseAt = buyerPlot.warehouse.Position + Vector3.new(5, -2.2, 0)
		at(buyer, warehouseAt)
		task.wait(0.3)
		check("owner can open physical locker", Station.openWarehouse(buyer, buyerPlot))
		local warehouseView = client(buyer, "warehouse", nil)
		check(
			"locker opens inventory with full touch targets",
			warehouseView.open and warehouseView.storeHeight >= 48
		)
		check("foreign locker prompts hidden", warehouseView.foreignPrompts == 0)
		check("foreign storage previews stay private", warehouseView.foreignPreviews == 0)
		check(
			"local previews never replicate to server",
			not assert(buyerPlot.model:FindFirstChild("Warehouse"), "missing locker"):FindFirstChild(
				"PrivateStoragePreviews"
			)
		)
		check("foreign locker ownership rejected", not Station.openWarehouse(buyer, ownerPlot))
		local originalKey = Inventory.key(storedOriginal)
		client(buyer, "stationAction", { action = "store", slot = 1, expectedSlot = originalKey })
		check(
			"store removes pedestal and keeps exact item",
			buyerData.pedestals["1"] == nil and buyerData.storage[2] == storedOriginal
		)
		task.wait(1.2)
		check(
			"stored creature stays off free pedestal",
			buyerData.pedestals["1"] == nil and #buyerData.storage == 2
		)
		check(
			"storage does not earn passive income",
			Station.incomePerSecond(buyer, buyerData) == 0
		)
		check(
			"stored metadata saved intact",
			Data.saveConfirmed(buyer, function(saved)
				local item = saved.storage[2]
				return item ~= nil
					and item.id == storedOriginal.id
					and item.paid == true
					and item.mutation == "Golden"
					and item.hatchAt == storedOriginal.hatchAt
			end)
		)
		client(buyer, "stationAction", { action = "store", slot = 1, expectedSlot = originalKey })
		check(
			"replayed store cannot duplicate",
			#buyerData.storage == 2 and buyerData.pedestals["1"] == nil
		)
		at(buyer, buyerPlot.center + Vector3.new(20, 4, -20))
		client(buyer, "stationAction", {
			action = "swap",
			slot = 2,
			index = 1,
			expectedSlot = "",
			expectedStored = Inventory.key(storedIncoming),
		})
		check(
			"distant deployment rejected",
			buyerData.pedestals["2"] == nil and #buyerData.storage == 2
		)
		check("distant locker opening rejected", not Station.openWarehouse(buyer, buyerPlot))
		at(buyer, warehouseAt)
		client(buyer, "stationAction", {
			action = "swap",
			slot = 2,
			index = 1,
			expectedSlot = "",
			expectedStored = Inventory.key(storedIncoming),
		})
		check(
			"stored creature deployed to exact empty slot",
			buyerData.pedestals["2"] == storedIncoming and #buyerData.storage == 1
		)
		client(buyer, "stationAction", {
			action = "swap",
			slot = 2,
			index = 1,
			expectedSlot = Inventory.key(storedIncoming),
			expectedStored = originalKey,
		})
		check(
			"occupied swap keeps both identities",
			buyerData.pedestals["2"] == storedOriginal and buyerData.storage[1] == storedIncoming
		)
		client(buyer, "stationAction", {
			action = "swap",
			slot = 2,
			index = 1,
			expectedSlot = Inventory.key(storedIncoming),
			expectedStored = originalKey,
		})
		check(
			"stale swap cannot change new occupants",
			buyerData.pedestals["2"] == storedOriginal and buyerData.storage[1] == storedIncoming
		)
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

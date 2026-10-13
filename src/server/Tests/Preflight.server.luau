--!strict
-- Opt-in integration checks, running in the real server script context. Uses
-- an isolated PreflightData_dev store selected by the test arguments.
local RunService = game:GetService("RunService")
if not RunService:IsStudio() then
	return
end
local StudioTestService = game:GetService("StudioTestService")
local args = StudioTestService:GetTestArgs()
if typeof(args) ~= "table" or args.suite ~= "preprod" then
	return
end

local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local Services = script.Parent.Parent.Services
local Data = require(Services.DataService)
local Station = require(Services.StationService)
local Transfer = require(Services.TransferService)
local Monetization = require(Services.MonetizationService)
local completed: { string } = {}
local errors: { string } = {}
game:GetService("LogService").MessageOut:Connect(function(message, kind)
	if kind == Enum.MessageType.MessageError and #errors < 12 then
		table.insert(errors, string.sub(message, 1, 400))
	end
end)

local function check(name: string, success: boolean)
	assert(success, name)
	table.insert(completed, name)
end
local function readyPlayers(count: number): { Player }
	local deadline = os.clock() + 180
	while os.clock() < deadline do
		local players = Players:GetPlayers()
		local loaded = #players == count
		for _, player in players do
			if not Data.get(player) or not Station.getPlot(player) then
				loaded = false
			end
		end
		if loaded then
			return players
		end
		task.wait(0.2)
	end
	local details = {}
	for _, player in Players:GetPlayers() do
		table.insert(details, {
			userId = player.UserId,
			profile = Data.get(player) ~= nil,
			plot = Station.getPlot(player) ~= nil,
			policy = player:GetAttribute("PolicyReady"),
		})
	end
	error(`{count} clients failed to load: {HttpService:JSONEncode({
		players = details,
		events = Data.debugPreflightEvents(),
	})}`)
end

local function run()
	if args.mode == "commerce" then
		return require(script.Parent.CommerceChecks).run()
	end
	if args.mode == "arena" then
		return require(script.Parent.ArenaChecks).run()
	end
	if args.mode == "chase" then
		return require(script.Parent.ChaseChecks).run()
	end
	if args.mode == "biomes" then
		return require(script.Parent.BiomeChecks).run()
	end
	if args.mode == "emotes" then
		return require(script.Parent.EmoteChecks).run()
	end
	if args.mode == "capacity" then
		local full = readyPlayers(8)
		local slots: { [number]: boolean } = {}
		for _, player in full do
			local plot = assert(Station.getPlot(player), "missing plot")
			check("unique station under full capacity", not slots[plot.index])
			slots[plot.index] = true
		end
		return { ok = true, checks = completed, players = #full }
	end
	local players = readyPlayers(2)
	local owner, buyer = players[1], players[2]
	local ownerData = assert(Data.get(owner), "owner profile")
	local buyerData = assert(Data.get(buyer), "buyer profile")
	check("distinct plots", Station.getPlot(owner) ~= Station.getPlot(buyer))
	local before = #buyerData.storage + Station.creatureCount(buyerData)
	local receipt = `QA_{HttpService:GenerateGUID(false)}`
	check(
		"receipt confirmed",
		Monetization.debugReceipt(buyer, "StarterPack", receipt) == "PurchaseGranted"
	)
	check("complete pack", #buyerData.storage + Station.creatureCount(buyerData) == before + 2)
	check(
		"duplicate receipt acknowledged",
		Monetization.debugReceipt(buyer, "StarterPack", receipt) == "PurchaseGranted"
	)
	check(
		"no duplicate reward",
		#buyerData.storage + Station.creatureCount(buyerData) == before + 2
	)
	check(
		"second charged pack delivered",
		Monetization.debugReceipt(buyer, "StarterPack", receipt .. "_two") == "PurchaseGranted"
	)
	check(
		"repurchase has full reward",
		#buyerData.storage + Station.creatureCount(buyerData) == before + 4
	)

	local itemId = HttpService:GenerateGUID(false)
	-- The tutorial already occupies slot 1; isolate the transfer fixture.
	ownerData.pedestals["1"] = nil
	check(
		"owner fixture placed",
		Station.placeState(
			owner,
			{ id = itemId, creatureId = "comet_cat", rarity = "Rare", paid = false },
			"1"
		)
	)
	local tx, state = Transfer.reserve(owner, buyer, "1")
	check(
		"durable reservation",
		tx ~= nil and state ~= nil and state.id == itemId and ownerData.pedestals["1"] == nil
	)
	local id = assert(tx, "missing tx")
	check("durable delivery", Transfer.complete(owner, buyer, id))
	check("owner escrow cleared", ownerData.outgoingTransfers[id] == nil)
	local count = 0
	for _, item in buyerData.pedestals do
		if item.id == itemId then
			count += 1
		end
	end
	for _, item in buyerData.storage do
		if item.id == itemId then
			count += 1
		end
	end
	check("one received item", count == 1)
	check("completed transfer cannot replay", not Transfer.complete(owner, buyer, id))

	check(
		"paid fixture placed",
		Station.placeState(
			owner,
			{ id = "paid-fixture", creatureId = "comet_cat", rarity = "Rare", paid = true },
			"1"
		)
	)
	buyer:SetAttribute("PaidItemTradingAllowed", false)
	check(
		"paid trade denied by policy",
		Transfer.reserve(owner, buyer, "1") == nil and ownerData.pedestals["1"] ~= nil
	)
	buyer:SetAttribute("PaidItemTradingAllowed", true)
	local cancelled = assert(Transfer.reserve(owner, buyer, "1"), "cancel reservation")
	check(
		"cancel restores owner",
		Transfer.cancel(owner, cancelled) and ownerData.pedestals["1"] ~= nil
	)
	check("cancel cannot duplicate", not Transfer.cancel(owner, cancelled))

	local leaveTx = assert(Transfer.reserve(owner, buyer, "1"), "leave reservation")
	local ownerId = owner.UserId
	owner:Kick("Preflight: owner leaves with escrow")
	local deadline = os.clock() + 35
	while os.clock() < deadline do
		if owner.Parent ~= Players then
			break
		end
		task.wait(0.2)
	end
	local saved = Data.debugReadSaved(ownerId)
	while os.clock() < deadline and (not saved or saved.outgoingTransfers[leaveTx] ~= nil) do
		task.wait(3)
		saved = Data.debugReadSaved(ownerId)
	end
	check(
		"owner exit persists return",
		saved ~= nil and saved.outgoingTransfers[leaveTx] == nil and saved.pedestals["1"] ~= nil
	)

	StudioTestService:AddPlayers(1)
	local joined = readyPlayers(2)
	check("late join distinct plot", Station.getPlot(joined[1]) ~= Station.getPlot(joined[2]))
	if args.mode == "transactions" then
		local luckReceipt = `QA_luck_{HttpService:GenerateGUID(false)}`
		check(
			"luck receipt confirmed",
			Monetization.debugReceipt(buyer, "ServerLuck", luckReceipt) == "PurchaseGranted"
		)
		local expiry = buyerData.serverLuckUntil
		check("luck persisted expiry", expiry > os.time())
		check(
			"luck duplicate acknowledged",
			Monetization.debugReceipt(buyer, "ServerLuck", luckReceipt) == "PurchaseGranted"
		)
		check("luck duplicate cannot extend", buyerData.serverLuckUntil == expiry)
		buyer:SetAttribute("PaidRandomItemsAllowed", false)
		local total = #buyerData.storage + Station.creatureCount(buyerData)
		check(
			"restricted charged receipt resolved",
			Monetization.debugReceipt(buyer, "Crate3", `QA_fixed_{HttpService:GenerateGUID(false)}`)
				== "PurchaseGranted"
		)
		check(
			"restricted receipt full fixed reward",
			#buyerData.storage + Station.creatureCount(buyerData) == total + 3
		)
		buyer:SetAttribute("PaidRandomItemsAllowed", true)
		local security = game:GetService("ServerStorage").DebugCommand
			:Invoke("securityCheck", buyer.Name)
		check("deep route bypass blocked", security.deepDeliveryBlocked)
		check(
			"invalid height rejected",
			security.rejected and security.carryCleared and security.returnedHome
		)
		return { ok = true, checks = completed, players = #joined }
	end
	StudioTestService:AddPlayers(6)
	local full = readyPlayers(8)
	local slots: { [number]: boolean } = {}
	for _, player in full do
		local plot = assert(Station.getPlot(player), "missing plot")
		check("unique station under full capacity", not slots[plot.index])
		slots[plot.index] = true
	end
	return { ok = true, checks = completed, players = #full }
end

task.delay(360, function()
	StudioTestService:EndTest({ ok = false, error = "preflight timeout", checks = completed })
end)
local ok, result = pcall(function(): any
	return run()
end)
if not ok then
	result = { ok = false, error = tostring(result), checks = completed, errors = errors }
end
print("[Preflight] " .. HttpService:JSONEncode(result))
StudioTestService:EndTest(result)

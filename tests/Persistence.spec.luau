--!strict
local Data = game:GetService("ServerScriptService").Server.Data
local Migrations = require(Data.Migrations)
local Confirmation = require(Data.SaveConfirmation)
local Grants = require(Data.PurchaseGrants)
local Transfers = require(Data.Transfers)
local Environment = require(game:GetService("ReplicatedStorage").Shared.Config.Environment)
local passed = 0
local function check(name: string, value: boolean)
	assert(value, name)
	passed += 1
end
check(
	"live profile namespace retained",
	Environment.storeName(
		"PlayerData",
		false,
		Environment.PRODUCTION_UNIVERSE_ID,
		Environment.PRODUCTION_PLACE_ID
	) == "PlayerData"
)
check(
	"live journal namespace retained",
	Environment.storeName(
		"Transfers",
		false,
		Environment.PRODUCTION_UNIVERSE_ID,
		Environment.PRODUCTION_PLACE_ID
	) == "Transfers"
)
check(
	"Studio isolated",
	Environment.storeName(
		"PlayerData",
		true,
		Environment.PRODUCTION_UNIVERSE_ID,
		Environment.PRODUCTION_PLACE_ID
	) == "PlayerData_dev"
)
check(
	"published DEV isolated",
	Environment.storeName("PlayerData", false, Environment.PRODUCTION_UNIVERSE_ID, 123)
		== "PlayerData_dev_123"
)
check(
	"foreign universe isolated",
	Environment.storeName("Transfers", false, 123, Environment.PRODUCTION_PLACE_ID) ~= "Transfers"
)
local function copy(value: any): any
	if type(value) ~= "table" then
		return value
	end
	local result = {}
	for key, item in value do
		result[key] = copy(item)
	end
	return result
end
local function profile(): any
	return {
		schema = 1,
		pedestals = {},
		pedestalCount = 3,
		storage = {},
		purchases = {},
		flags = {},
		shieldUntil = 0,
		shop = { bought = {} },
		coins = 12,
	}
end
local old = profile()
old.pedestals["1"] = { creatureId = "comet_cat", rarity = "Rare" }
local migrated, changed = Migrations.run(old)
check(
	"migration keeps items/coins",
	changed and migrated.coins == 12 and migrated.pedestals["1"].creatureId == "comet_cat"
)
check("legacy provenance protected", migrated.pedestals["1"].paid == true)
check("v2 defaults", migrated.uncollectedCoins == 0 and next(migrated.outgoingTransfers) == nil)
local _, again = Migrations.run(migrated)
check("migration idempotent", not again)
check("future schema rejected", not pcall(Migrations.run, { schema = 999 }))

local time = 0
local session: any =
	{ Data = { purchases = { r = 1 } }, LastSavedData = { purchases = {} }, saves = 0 }
function session:IsActive(): boolean
	return self.active ~= false
end
function session:Save()
	self.saves += 1
end
local function acknowledged(data: any): boolean
	return data.purchases.r ~= nil
end
local result = Confirmation.wait(session, acknowledged, function()
	return true
end, function()
	return time
end, function(dt)
	time += dt
	if time >= 2 then
		session.LastSavedData = copy(session.Data)
	end
end, 3)
check("waits for persisted snapshot", result and time >= 2 and session.saves == 1)
time = 0
session.LastSavedData = { purchases = {} }
check(
	"in-memory receipt cannot acknowledge",
	not Confirmation.wait(session, acknowledged, function()
		return true
	end, function()
		return time
	end, function(dt)
		time += dt
	end, 1)
)
session.active = false
check("session loss cannot acknowledge", not Confirmation.wait(session, acknowledged, function()
	return true
end, function()
	return time
end, function(_dt) end, 1))

local buyer: any = Migrations.run(profile())
local sequence = 0
local function newId(): string
	sequence += 1
	return tostring(sequence)
end
check(
	"pack delivered",
	Grants.apply(buyer, "StarterPack", "one", { "comet_cat", "solar_stag" }, 100, 0, newId)
)
check(
	"receipt replay no duplicate",
	not Grants.apply(buyer, "StarterPack", "one", { "comet_cat" }, 200, 0, newId)
		and #buyer.storage == 2
)
check(
	"second charged pack not lost",
	Grants.apply(buyer, "StarterPack", "two", { "comet_cat", "solar_stag" }, 200, 0, newId)
		and #buyer.storage == 4
)
check(
	"purchase states carry provenance",
	buyer.storage[1].paid and buyer.storage[1].id ~= buyer.storage[2].id
)
local before = copy(buyer)
check(
	"partial crate construction rejected",
	not pcall(Grants.apply, buyer, "Crate3", "bad", { "comet_cat", "missing" }, 300, 0, newId)
)
check(
	"failed grant does not mutate data/receipt",
	#buyer.storage == #before.storage and buyer.purchases.bad == nil
)
buyer.pedestals["1"] = { creatureId = "comet_cat", rarity = "Rare", hatchAt = 999 }
buyer.storage[1].hatchAt = 999
Grants.apply(buyer, "InstantHatch", "hatch", {}, 500, 0, newId)
check(
	"hatch includes overflow",
	buyer.pedestals["1"].hatchAt == 500 and buyer.storage[1].hatchAt == 500
)

local intent: any = {
	ownerUserId = 1,
	recipientUserId = 2,
	slot = "1",
	state = { id = "unique-item", creatureId = "comet_cat", rarity = "Rare", paid = false },
}
local pending = Transfers.decide(nil, intent, "pending")
local committed = Transfers.decide(pending, intent, "committed")
check(
	"commit cannot roll back",
	Transfers.decide(committed, intent, "cancelled").phase == "committed"
)
local cancelled = Transfers.decide(pending, intent, "cancelled")
check("cancel cannot commit", Transfers.decide(cancelled, intent, "committed").phase == "cancelled")
check("missing journal cannot commit", not pcall(Transfers.decide, nil, intent, "committed"))
local wrong = copy(intent)
wrong.recipientUserId = 3
check("identity substitution rejected", not pcall(Transfers.decide, pending, wrong, "committed"))

-- Crash after each persistence boundary, recover in both player join orders.
for boundary = 0, 8 do
	for _, ownerFirst in { true, false } do
		local owner: any = Migrations.run(profile())
		local recipient: any = Migrations.run(profile())
		owner.pedestals["1"] = copy(intent.state)
		local savedOwner, savedRecipient = copy(owner), copy(recipient)
		local record: Transfers.Record? = nil
		if boundary >= 1 then
			owner.pedestals["1"] = nil
			owner.outgoingTransfers.tx = copy(intent)
		end
		if boundary >= 2 then
			savedOwner = copy(owner)
		end
		if boundary >= 3 then
			record = Transfers.decide(nil, intent, "pending")
		end
		if boundary >= 4 then
			recipient.incomingTransfers.tx = copy(intent)
		end
		if boundary >= 5 then
			savedRecipient = copy(recipient)
		end
		if boundary >= 6 then
			record = Transfers.decide(record, intent, "committed")
		end
		if boundary >= 7 then
			Transfers.apply(recipient, "tx", 3)
		end
		if boundary >= 8 then
			savedRecipient = copy(recipient)
		end
		owner, recipient = savedOwner, savedRecipient
		local function recoverOwner()
			if owner.outgoingTransfers.tx then
				record = Transfers.decide(record, intent, "cancelled")
				if record and record.phase == "cancelled" then
					Transfers.restore(owner, "tx")
				else
					owner.outgoingTransfers.tx = nil
				end
			end
		end
		local function recoverRecipient()
			if recipient.incomingTransfers.tx then
				record = Transfers.decide(record, intent, "cancelled")
				if record and record.phase == "committed" then
					Transfers.apply(recipient, "tx", 3)
				end
				recipient.incomingTransfers.tx = nil
			end
		end
		if ownerFirst then
			recoverOwner()
			recoverRecipient()
		else
			recoverRecipient()
			recoverOwner()
		end
		local count = 0
		for _, data in { owner, recipient } do
			for _, item in data.pedestals do
				if item.id == intent.state.id then
					count += 1
				end
			end
			for _, item in data.storage do
				if item.id == intent.state.id then
					count += 1
				end
			end
		end
		check(`crash {boundary}, join order {tostring(ownerFirst)}: one item`, count == 1)
		check(
			`crash {boundary}: no unresolved profile intents`,
			next(owner.outgoingTransfers) == nil and next(recipient.incomingTransfers) == nil
		)
	end
end
local full: any = Migrations.run(profile())
full.pedestals["1"] = { id = "old", creatureId = "solar_stag", rarity = "Epic" }
full.incomingTransfers.tx = copy(intent)
Transfers.apply(full, "tx", 1, 1)
check(
	"replacement preserves previous item",
	full.storage[1].id == "old" and full.pedestals["1"].id == "unique-item"
)
Transfers.apply(full, "tx", 1, 1)
check("applied intent cannot grant twice", #full.storage == 1)
full.pedestals["1"] = nil -- sold after grant but before intent cleanup
Transfers.apply(full, "tx", 1, 1)
check("sold item never resurrected", full.pedestals["1"] == nil)
return `PASS {passed}`

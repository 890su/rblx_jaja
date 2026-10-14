--!strict
local Shared = game:GetService("ReplicatedStorage").Shared
local Server = game:GetService("ServerScriptService").Server
local Math = require(Shared.Util.UpgradeMath)
local Specs = require(Shared.Config.Upgrades)
local Book = require(Shared.Util.CollectionBook)
local Availability = require(Shared.Util.PurchaseAvailability)
local Migrations = require(Server.Data.Migrations)
local Grants = require(Server.Data.PurchaseGrants)
local Credits = require(Server.Data.PurchaseCredits)
local Clock = require(Shared.Clock)
local Events = require(Shared.Config.Events)
local passed = 0
local function check(name: string, ok: boolean)
	assert(ok, name)
	passed += 1
end
local function profile(): any
	return {
		schema = 2,
		coins = 1e12,
		training = 0,
		pedestals = {},
		storage = {},
		index = {},
		purchases = {},
		flags = {},
		shieldUntil = 0,
		shop = { cycle = Clock.cycleIndex(Events.SHOP_RESTOCK_PERIOD), bought = {} },
	}
end
local p = Migrations.run(profile())
check(
	"migration preserves currency and adds all defaults",
	p.coins == 1e12
		and p.treadmill == 1
		and p.carryTraining == 0
		and p.hatchCredits == 0
		and p.restockCredits == 0
		and p.flags.warehouseOwned == true
		and p.schema == 4
)
p.treadmill, p.flags.warehouseOwned = 0, nil
for _, spec in Specs do
	for level = 0, spec.max - 1 do
		local before = p.coins
		local cost = assert(Math.cost(spec.key, level), "missing cost")
		local outcome, paid = Math.buy(p, spec.key)
		check(
			"each upgrade charges its server cost exactly once",
			outcome == "bought"
				and paid == cost
				and p.coins == before - cost
				and Math.level(p, spec.key) == level + 1
		)
	end
	local before = p.coins
	check("max upgrade cannot charge", Math.buy(p, spec.key) == "max" and p.coins == before)
	check(
		"invalid levels rejected",
		Math.cost(spec.key, 0 / 0) == nil
			and Math.cost(spec.key, -1) == nil
			and Math.cost(spec.key, 0.5) == nil
	)
end
check("unknown upgrade cannot charge", Math.buy(p, "coins") == "max")
check("carry speed bounded", Math.carryMultiplier(999) == 0.8 and Math.carryMultiplier(0) == 0.6)
check(
	"treadmill upgrades multiply base rate",
	Math.treadmillRate(0) == 0 and Math.treadmillRate(1) == 0.5 and Math.treadmillRate(11) == 1.5
)
local poor = Migrations.run(profile())
poor.treadmill = 0
poor.coins = 0
check(
	"insufficient funds preserve progression",
	Math.buy(poor, "treadmill") == "funds" and poor.treadmill == 0 and poor.coins == 0
)
check(
	"installation and upgrade prices are distinct",
	Math.cost("treadmill", 0) == 250 and Math.cost("treadmill", 1) == 1500
)
local fresh = profile()
fresh.schema, fresh.treadmill, fresh.carryTraining, fresh.hatchCredits, fresh.restockCredits =
	4, 0, 0, 0, 0
local _, freshChanged = Migrations.run(fresh)
check(
	"new profiles have no facilities",
	not freshChanged and Math.level(fresh, "warehouse") == 0 and fresh.treadmill == 0
)
local beforeFacility = fresh.coins
check(
	"warehouse buys once",
	Math.buy(fresh, "warehouse") == "bought" and fresh.coins == beforeFacility - 1000
)
beforeFacility = fresh.coins
check(
	"warehouse duplicate cannot charge",
	Math.buy(fresh, "warehouse") == "max" and fresh.coins == beforeFacility
)
for oldLevel = 0, 10 do
	local legacy = profile()
	legacy.schema, legacy.treadmill = 3, oldLevel
	local oldItems = {
		id = "kept",
		creatureId = "comet_cat",
		rarity = "Rare",
		paid = true,
		mutation = "Golden",
		hatchAt = 999,
	}
	legacy.storage = { oldItems }
	Migrations.run(legacy)
	check(
		"legacy treadmill effect retained",
		math.abs(Math.treadmillRate(legacy.treadmill) - (0.5 * (1 + oldLevel * 0.2))) < 1e-9
	)
	check(
		"legacy locker and contents retained",
		legacy.flags.warehouseOwned == true and legacy.storage[1] == oldItems
	)
	local level = legacy.treadmill
	local _, againMigration = Migrations.run(legacy)
	check("facility migration idempotent", not againMigration and legacy.treadmill == level)
end
p.pedestals = {
	a = { creatureId = "pebblit", rarity = "Common" },
	b = { creatureId = "emberfox", rarity = "Uncommon", hatchAt = 101 },
}
p.storage = { { creatureId = "comet_cat", rarity = "Rare" } }
local changed, found = Book.discover(p, 100)
check(
	"book includes hatched storage and pedestals",
	changed and #found == 2 and p.index.pebblit and p.index.comet_cat and not p.index.emberfox
)
check("book emits discoveries once", not Book.discover(p, 100))
p.pedestals = {}
p.storage = {}
check(
	"selling and stealing do not erase discovery",
	not Book.discover(p, 200) and p.index.pebblit and p.index.comet_cat
)
for bits = 0, 255 do
	local state = {
		configured = bit32.band(bits, 1) > 0,
		loaded = bit32.band(bits, 2) > 0,
		failed = bit32.band(bits, 4) > 0,
		owned = bit32.band(bits, 8) > 0,
		policyReady = bit32.band(bits, 16) > 0,
		restricted = bit32.band(bits, 32) > 0,
		applicable = bit32.band(bits, 64) > 0,
		prompting = bit32.band(bits, 128) > 0,
	}
	local ready = Availability.status(state) == "ready"
	check(
		"purchase availability matrix",
		ready
			== (
				state.configured
				and state.loaded
				and not state.failed
				and not state.owned
				and state.policyReady
				and not state.restricted
				and state.applicable
				and not state.prompting
			)
	)
end
local n = 0
local function newId(): string
	n += 1
	return tostring(n)
end
local reserve = profile()
reserve.schema, reserve.treadmill, reserve.carryTraining, reserve.hatchCredits, reserve.restockCredits =
	4, 0, 0, 0, 0
reserve.pedestals = { ["1"] = { id = "existing", creatureId = "pebblit", rarity = "Common" } }
check(
	"paid rewards stay safe before locker purchase",
	Grants.apply(reserve, "Crate3", "reserve", { "comet_cat", "pebblit", "pebblit" }, 100, 0, newId)
		and #reserve.storage == 3
		and reserve.flags.warehouseOwned ~= true
		and reserve.storage[1].paid == true
		and reserve.pedestals["1"].id == "existing"
)
check(
	"reserved paid reward stays idempotent",
	not Grants.apply(reserve, "Crate3", "reserve", { "comet_cat" }, 100, 0, newId)
		and #reserve.storage == 3
)
for _, key in { "InstantHatch", "Restock" } do
	local buyer = Migrations.run(profile())
	check(
		"empty checkout still grants durable receipt",
		Grants.apply(buyer, key, key, {}, 100, 0, newId)
	)
	local count = if key == "InstantHatch" then buyer.hatchCredits else buyer.restockCredits
	check("no-op checkout becomes credit", count == 1)
	check(
		"duplicate receipt cannot add credit",
		not Grants.apply(buyer, key, key, {}, 100, 0, newId)
	)
	check("inapplicable credit is kept", not Credits.use(buyer, key, 100, buyer.shop.cycle))
	if key == "InstantHatch" then
		buyer.storage = { { creatureId = "pebblit", rarity = "Common", hatchAt = 200 } }
	else
		buyer.shop.bought = { ["1"] = 1 }
	end
	check("eligible credit consumed once", Credits.use(buyer, key, 100, buyer.shop.cycle))
	check("credit cannot be used twice", not Credits.use(buyer, key, 100, buyer.shop.cycle))
end
local changedCycle = Migrations.run(profile())
changedCycle.shop.cycle -= 1
changedCycle.shop.bought = { ["1"] = 20 }
check(
	"old-cycle restock becomes credit",
	Grants.apply(changedCycle, "Restock", "cycle", {}, 100, 0, newId)
		and changedCycle.restockCredits == 1
)
return `PASS Commerce {passed}`

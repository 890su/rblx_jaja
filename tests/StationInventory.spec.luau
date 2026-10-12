--!strict
local Inventory = require(game:GetService("ReplicatedStorage").Shared.Util.StationInventory)
local passed = 0
local function check(name: string, ok: boolean)
	assert(ok, `FAIL {name}`)
	passed += 1
end
local old = { creatureId = "pebblit", rarity = "Common", hatchAt = 123 }
local incoming = { creatureId = "comet_cat", rarity = "Rare", mutation = "Golden", hatchAt = 456 }
local profile: any = { pedestals = { ["1"] = old }, storage = { incoming } }
local a, b = Inventory.key(old :: any), Inventory.key(incoming :: any)
check("occupied exchange", Inventory.exchange(profile, 1, 1, a, b, 3))
check("incoming exact state", profile.pedestals["1"] == incoming)
check("old exact state retained", profile.storage[1] == old)
check(
	"mutation and timer kept",
	profile.pedestals["1"].mutation == "Golden" and profile.pedestals["1"].hatchAt == 456
)
check("no duplicate item on replay", not Inventory.exchange(profile, 1, 1, a, b, 3))
check("stale target rejected", not Inventory.exchange(profile, 1, 1, "stale", a, 3))
check("stale storage rejected", not Inventory.exchange(profile, 1, 1, b, "stale", 3))
check("locked slot rejected", not Inventory.exchange(profile, 4, 1, "", a, 3))
check("fractional slot rejected", not Inventory.exchange(profile, 1.5, 1, "", a, 3))
check("invalid index rejected", not Inventory.exchange(profile, 2, 9, "", a, 3))
check("NaN rejected", not Inventory.exchange(profile, 0 / 0, 1, "", a, 3))
check("empty slot exchange", Inventory.exchange(profile, 2, 1, "", a, 3))
check("empty slot consumes storage once", #profile.storage == 0 and profile.pedestals["2"] == old)
check(
	"two distinct occupants",
	profile.pedestals["1"] == incoming and profile.pedestals["2"] == old
)
return `PASS {passed}`

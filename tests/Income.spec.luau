--!strict
-- Pure-logic checks for income math. Run in Studio (Edit) via MCP execute_luau:
--   require(game.ServerScriptService.Server.Data.Income) is loaded by this file.
-- Returns "PASS n" or errors with the first failure.

local Income = require(game:GetService("ServerScriptService").Server.Data.Income)

local passed = 0
local function check(name: string, actual: number, expected: number)
	if math.abs(actual - expected) > 1e-6 then
		error(`{name}: expected {expected}, got {actual}`)
	end
	passed += 1
end

local function profile(lastOnline: number, rebirths: number, pedestals: { [string]: any }): any
	return { lastOnline = lastOnline, rebirths = rebirths, pedestals = pedestals }
end

local NOW = 1_000_000
-- Uncommon = 4/s, offline rate 0.25, cap 12 h
check("never played", Income.offline(profile(0, 0, { ["1"] = { rarity = "Uncommon" } }), NOW), 0)
check(
	"1h away",
	Income.offline(profile(NOW - 3600, 0, { ["1"] = { rarity = "Uncommon" } }), NOW),
	3600 * 4 * 0.25
)
check(
	"cap 12h",
	Income.offline(profile(NOW - 48 * 3600, 0, { ["1"] = { rarity = "Uncommon" } }), NOW),
	12 * 3600 * 4 * 0.25
)
check(
	"hatched mid-absence",
	Income.offline(
		profile(NOW - 3600, 0, { ["1"] = { rarity = "Uncommon", hatchAt = NOW - 600 } }),
		NOW
	),
	600 * 4 * 0.25
)
check(
	"not hatched yet",
	Income.offline(
		profile(NOW - 3600, 0, { ["1"] = { rarity = "Uncommon", hatchAt = NOW + 5 } }),
		NOW
	),
	0
)
check(
	"rebirth bonus",
	Income.offline(profile(NOW - 100, 2, { ["1"] = { rarity = "Common" } }), NOW),
	math.floor(100 * 1 * 0.25 * 2)
)
check("golden x2", Income.ofPedestal({ rarity = "Rare", mutation = "Golden" } :: any), 30)
check(
	"pass rate",
	Income.offline(profile(NOW - 3600, 0, { ["1"] = { rarity = "Uncommon" } }), NOW, true),
	3600 * 4 * 0.5
)
check(
	"per second hatched only",
	Income.perSecond(
		profile(0, 0, {
			["1"] = { rarity = "Epic" },
			["2"] = { rarity = "Mythic", hatchAt = NOW + 10 },
		}),
		NOW
	),
	60
)

return `PASS {passed}`

--!strict
-- Promo codes (server-only). Keys are upper-case. `expires` = os.time() UTC.
-- Add codes for update notes / creators here; never reuse a retired code.

export type Code = { coins: number?, creatureId: string?, expires: number }

local function utc(year: number, month: number, day: number): number
	return os.time({ year = year, month = month, day = day, hour = 0 })
end

local CODES: { [string]: Code } = {
	LAUNCH = { coins = 1000, expires = utc(2027, 1, 31) },
	METEOR = { creatureId = "frostfin", expires = utc(2027, 1, 31) },
}

return table.freeze(CODES)

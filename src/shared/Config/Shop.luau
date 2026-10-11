--!strict
-- Meteor Shop (GDD §4.7): offers rotate on the global clock (same on every
-- server); stock is per player per cycle. Paid with coins only.

local deepFreeze = require(script.Parent.Parent.Util.deepFreeze)

export type SlotConfig = { weights: { [string]: number }, stock: number }

local SLOTS: { SlotConfig } = {
	{ weights = { Common = 100 }, stock = 5 },
	{ weights = { Common = 60, Uncommon = 40 }, stock = 4 },
	{ weights = { Uncommon = 80, Rare = 20 }, stock = 3 },
	{ weights = { Uncommon = 50, Rare = 50 }, stock = 2 },
	{ weights = { Rare = 85, Epic = 15 }, stock = 1 },
	{ weights = { Rare = 70, Epic = 25, Legendary = 5 }, stock = 1 },
}

-- Coin price per rarity (~payback time of the creature's income).
local PRICES: { [string]: number } = {
	Common = 60,
	Uncommon = 400,
	Rare = 2500,
	Epic = 15000,
	Legendary = 90000,
	Mythic = 600000,
}

export type Config = { SLOTS: { SlotConfig }, PRICES: { [string]: number } }

local config: Config = { SLOTS = SLOTS, PRICES = PRICES }
return deepFreeze(config)

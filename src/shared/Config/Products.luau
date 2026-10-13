--!strict
-- Game passes and developer products (GDD §6). IDs from Creator Dashboard
-- (created 2026-10-11, managed pricing on). An item with id 0 is shown as
-- "Coming soon" and ignored by the server.

local deepFreeze = require(script.Parent.Parent.Util.deepFreeze)

export type Pass = { key: string, id: number, price: number, name: string, description: string }
export type Product = { key: string, id: number, price: number, name: string, description: string }

local PASSES: { Pass } = {
	{
		key = "Coins2x",
		id = 2027180921,
		price = 199,
		name = "2x Stardust",
		description = "Double all creature income forever",
	},
	{
		key = "Speed2x",
		id = 2025872922,
		price = 149,
		name = "2x Speed",
		description = "Gain Speed twice as fast",
	},
	{
		key = "VIP",
		id = 2026214948,
		price = 299,
		name = "VIP",
		description = "+50% income, VIP chat tag, +10 s station lock, gold pedestals",
	},
	{
		key = "OfflinePlus",
		id = 2026688944,
		price = 249,
		name = "Offline x2 + Auto-collect",
		description = "Earn 50% offline for up to 24 h and collect automatically",
	},
	{
		key = "Expansion",
		id = 2027144916,
		price = 399,
		name = "Station Expansion",
		description = "+2 pedestals",
	},
}

local PRODUCTS: { Product } = {
	{
		key = "StarterPack",
		id = 3717974127,
		price = 49,
		name = "Starter Pack",
		description = "Comet Cat (Rare) + Solar Stag (Epic) + 30 min shield. Once per account",
	},
	{
		key = "Shield15",
		id = 3717974200,
		price = 39,
		name = "Shield 15 min",
		description = "Nobody can raid your station",
	},
	{
		key = "InstantHatch",
		id = 3717974249,
		price = 49,
		name = "Instant Hatch",
		description = "Hatch every meteor on your pedestals now",
	},
	{
		key = "Restock",
		id = 3717974272,
		price = 49,
		name = "Restock Shop",
		description = "Refill your Meteor Shop stock now",
	},
	{
		key = "Crate1",
		id = 3717974333,
		price = 99,
		name = "Meteor Crate",
		description = "1 random Rare+ creature",
	},
	{
		key = "Crate3",
		id = 3717974355,
		price = 249,
		name = "Meteor Crate x3",
		description = "3 random Rare+ creatures",
	},
	{
		key = "Crate10",
		id = 3717974403,
		price = 699,
		name = "Meteor Crate x10",
		description = "10 random Rare+ creatures",
	},
	{
		key = "ServerLuck",
		id = 3717974429,
		price = 249,
		name = "Server Luck 15 min",
		description = "x2 chance for Uncommon+ meteors for everyone on the server",
	},
}

-- Paid random item: rarity odds for crates (must sum to 100). The creature
-- within a rarity is uniform over Creatures of that rarity. Shown before
-- purchase in the odds window (Roblox paid-random-items policy).
local CRATE_ODDS: { [string]: number } = {
	Rare = 70,
	Epic = 24,
	Legendary = 5.5,
	Mythic = 0.5,
}

local SERVER_LUCK = { seconds = 15 * 60, boost = 2 }
local SHIELD_SECONDS = 15 * 60
local STARTER_SHIELD_SECONDS = 30 * 60
local STARTER_CREATURES = { "comet_cat", "solar_stag" }

export type Config = {
	PASSES: { Pass },
	PRODUCTS: { Product },
	CRATE_ODDS: { [string]: number },
	SERVER_LUCK: { seconds: number, boost: number },
	SHIELD_SECONDS: number,
	STARTER_SHIELD_SECONDS: number,
	STARTER_CREATURES: { string },
	RESTRICTED_REWARD: string,
}

local config: Config = {
	PASSES = PASSES,
	PRODUCTS = PRODUCTS,
	CRATE_ODDS = CRATE_ODDS,
	SERVER_LUCK = SERVER_LUCK,
	SHIELD_SECONDS = SHIELD_SECONDS,
	STARTER_SHIELD_SECONDS = STARTER_SHIELD_SECONDS,
	STARTER_CREATURES = STARTER_CREATURES,
	-- Fixed compensation for an already-charged receipt after policy changes.
	RESTRICTED_REWARD = "cosmic_leviathan",
}

return deepFreeze(config)

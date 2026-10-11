--!strict
-- Shared type definitions. Anything crossing the client/server boundary
-- (remote payloads, profile schema, config shapes) lives here.

-- One of Config.Rarity.ORDER: "Common" | "Uncommon" | "Rare" | "Epic" | "Legendary" | "Mythic".
-- Kept as string: the type checker widens singleton unions across module
-- boundaries. Validate unknown values with Config.Rarity.INFO[rarity].
export type Rarity = string

export type RarityWeights = { [string]: number }

export type RarityInfo = {
	order: number,
	incomePerSecond: number,
	hatchSeconds: number,
}

export type ZoneInfo = {
	index: number,
	speedGate: number,
	rebirthGate: number,
	lengthStuds: number,
	maxMeteors: number,
	spawnIntervalSeconds: number,
	weights: RarityWeights,
}

export type PedestalState = {
	creatureId: string,
	rarity: Rarity,
	mutation: string?,
	hatchAt: number?,
}

export type PlayerProfile = {
	schema: number,
	coins: number,
	speed: number,
	rebirths: number,
	pedestalCount: number,
	pedestals: { [string]: PedestalState }, -- key = pedestal slot index as string
	lastOnline: number,
	playtimeTotal: number,
	flags: { [string]: boolean }, -- one-time FTUE beats, rewards claimed
	index: { [string]: boolean }, -- creature ids ever hatched (collection book)
	shieldUntil: number, -- os.time() until which the station can't be raided
	stats: PlayerStats,
	shop: { cycle: number, bought: { [string]: number } }, -- per-cycle purchases by slot
	storage: { PedestalState }, -- creatures waiting for a free pedestal (crates, packs)
	purchases: { [string]: number }, -- receipt PurchaseId -> os.time() (idempotency)
	daily: { streak: number, lastClaimDay: number },
	codes: { [string]: boolean },
}

export type ShopOffer = {
	slot: number,
	creatureId: string,
	rarity: Rarity,
	price: number,
	stock: number,
}

export type ShopState = {
	cycle: number,
	endsAt: number, -- server time (workspace:GetServerTimeNow) of next restock
	offers: { ShopOffer },
	remaining: { number }, -- per slot, for this player
}

export type PlayerStats = {
	steals: number,
	defends: number, -- thieves caught during a chase
	timesRobbed: number,
}

return nil

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
}

return nil

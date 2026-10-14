--!strict
local Economy = require(script.Parent.Economy)
export type Spec = {
	key: string,
	title: string,
	description: string,
	base: number,
	growth: number,
	max: number,
	bonus: number,
	installCost: number?,
}
local specs: { Spec } = {
	{
		key = "training",
		title = "Run Training",
		description = "Training improves all Speed gains",
		base = Economy.TRAINING_BASE_COST,
		growth = Economy.TRAINING_COST_GROWTH,
		max = Economy.TRAINING_MAX,
		bonus = Economy.TRAINING_BONUS,
	},
	{
		key = "treadmill",
		title = "Treadmill",
		description = "Build a treadmill, then improve its idle Speed gain",
		base = 1500,
		installCost = 250,
		growth = 2,
		max = 11, -- installation + ten upgrades
		bonus = 0.20,
	},
	{
		key = "warehouse",
		title = "Storage",
		description = "Build a locker to store and exchange your creatures",
		base = 1000,
		growth = 1,
		max = 1,
		bonus = 0,
	},
	{
		key = "carryTraining",
		title = "Carry speed",
		description = "Move faster while carrying an egg or stolen creature",
		base = 3000,
		growth = 2.2,
		max = 5,
		bonus = 0.04,
	},
}
return require(script.Parent.Parent.Util.deepFreeze)(specs)

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
		description = "Upgrade the treadmill already installed at your base",
		base = 1500,
		growth = 2,
		max = 10,
		bonus = 0.20,
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

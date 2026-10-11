--!strict
-- Reskin layer (GDD §11). Every player-facing theme string lives here; game
-- logic never references these names. Swap this module to change the theme.

local deepFreeze = require(script.Parent.Util.deepFreeze)

return deepFreeze({
	GAME_TITLE = "Meteor Rush",
	CURRENCY = "Stardust",
	ITEM = "Meteor",
	CREATURE = "Star Creature",
	BASE = "Station",
	SHOWER_EVENT = "Meteor Shower",
	WEEKLY_EVENT = "Starfall",

	ZONE_NAMES = { "Dust Flats", "Ember Ridge", "Frost Rim", "Void Basin", "Nova Core" },

	RARITY_COLORS = {
		Common = Color3.fromRGB(200, 200, 200),
		Uncommon = Color3.fromRGB(90, 220, 110),
		Rare = Color3.fromRGB(70, 150, 255),
		Epic = Color3.fromRGB(180, 90, 255),
		Legendary = Color3.fromRGB(255, 190, 40),
		Mythic = Color3.fromRGB(255, 70, 120),
	},
})

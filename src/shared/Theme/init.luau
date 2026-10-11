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

	CREATURE_NAMES = {
		pebblit = "Pebblit",
		dustbun = "Dustbun",
		cindermite = "Cindermite",
		glowgrub = "Glowgrub",
		rockroo = "Rockroo",
		emberfox = "Emberfox",
		sparkle_snail = "Sparkle Snail",
		crater_crab = "Crater Crab",
		moon_moth = "Moon Moth",
		pulsar_pup = "Pulsar Pup",
		frostfin = "Frostfin",
		comet_cat = "Comet Cat",
		nebula_newt = "Nebula Newt",
		orbit_owl = "Orbit Owl",
		quartz_quokka = "Quartz Quokka",
		void_viper = "Void Viper",
		solar_stag = "Solar Stag",
		plasma_panda = "Plasma Panda",
		aurora_axolotl = "Aurora Axolotl",
		ion_ibex = "Ion Ibex",
		nova_drake = "Nova Drake",
		galaxy_griffin = "Galaxy Griffin",
		eclipse_lynx = "Eclipse Lynx",
		starlight_seraph = "Starlight Seraph",
		meteor_mammoth = "Meteor Mammoth",
		cosmic_leviathan = "Cosmic Leviathan",
		quasar_phoenix = "Quasar Phoenix",
		singularity_sprite = "Singularity Sprite",
		celestial_kirin = "Celestial Kirin",
		big_bang_bunny = "Big Bang Bunny",
	} :: { [string]: string },

	RARITY_COLORS = {
		Common = Color3.fromRGB(200, 200, 200),
		Uncommon = Color3.fromRGB(90, 220, 110),
		Rare = Color3.fromRGB(70, 150, 255),
		Epic = Color3.fromRGB(180, 90, 255),
		Legendary = Color3.fromRGB(255, 190, 40),
		Mythic = Color3.fromRGB(255, 70, 120),
	},
})

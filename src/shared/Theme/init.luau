--!strict
-- Reskin layer (GDD §11). Every player-facing theme string lives here; game
-- logic never references these names. Swap this module to change the theme.

local deepFreeze = require(script.Parent.Util.deepFreeze)

return deepFreeze({
	GAME_TITLE = "Meteor Heist",
	CURRENCY = "Stardust",
	ITEM = "Meteor",
	CREATURE = "Star Creature",
	BASE = "Station",
	SHOWER_EVENT = "Meteor Shower",
	WEEKLY_EVENT = "Starfall",
	WAREHOUSE = {
		body = Color3.fromRGB(31, 45, 62),
		door = Color3.fromRGB(49, 67, 85),
		screen = Color3.fromRGB(9, 25, 35),
		accent = Color3.fromRGB(88, 231, 201),
		muted = Color3.fromRGB(89, 115, 133),
	},

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

	-- AI-generated MaterialVariants stored in the place (MaterialService).
	MATERIALS = {
		canyonWall = { base = Enum.Material.Basalt, variant = "MH_CanyonRock", studsPerTile = 16 },
		trackGround = { base = Enum.Material.Ground, variant = "MH_CraterGround", studsPerTile = 6 },
		stationFloor = {
			base = Enum.Material.Metal,
			variant = "MH_StationFloor",
			studsPerTile = 24,
		},
	},

	RARITY_COLORS = {
		Common = Color3.fromRGB(200, 200, 200),
		Uncommon = Color3.fromRGB(90, 220, 110),
		Rare = Color3.fromRGB(70, 150, 255),
		Epic = Color3.fromRGB(180, 90, 255),
		Legendary = Color3.fromRGB(255, 190, 40),
		Mythic = Color3.fromRGB(255, 70, 120),
	},
})

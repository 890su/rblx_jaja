--!strict
-- Sound effects and music (licensed libraries only: Roblox, ProSoundEffects,
-- APM, DistroKid official uploads on the Creator Store).

local deepFreeze = require(script.Parent.Parent.Util.deepFreeze)

export type Sound = { id: number, volume: number }

local SFX: { [string]: Sound } = {
	pickup = { id = 9126073001, volume = 0.5 }, -- Synth Sparkle Tone Ding (ProSoundEffects)
	hatch = { id = 9116395089, volume = 0.6 }, -- Magic Glows Chiming Hits 4 (ProSoundEffects)
	success = { id = 9116394545, volume = 0.4 }, -- Magic Glows Chiming Hits 1 (ProSoundEffects)
	coins = { id = 127645268874265, volume = 0.5 }, -- CoinTransfer_01 (Roblox)
	purchase = { id = 9113728049, volume = 0.5 }, -- Cash Register 2 (ProSoundEffects)
	crate = { id = 9119447936, volume = 0.6 }, -- Sparkle Bell Tree Wind Chimes (ProSoundEffects)
	warning = { id = 17208361335, volume = 0.5 }, -- Roblox GUI Notification High (Roblox)
	whoosh = { id = 12222095, volume = 0.5 }, -- Rocket whoosh 01 (Roblox)
	impact = { id = 9118612665, volume = 0.5 }, -- Rock Impact 7 (ProSoundEffects)
}

local MUSIC: { Sound } = {
	{ id = 140533822783920, volume = 0.18 }, -- Space Ambient (DistrokidOfficial)
	{ id = 102039057339088, volume = 0.18 }, -- Zero Gravity (DistrokidOfficial)
}

export type Config = { SFX: { [string]: Sound }, MUSIC: { Sound } }
local config: Config = { SFX = SFX, MUSIC = MUSIC }
return deepFreeze(config)

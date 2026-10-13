--!strict
-- Visual identity only. Materials must not change gameplay friction.
local deepFreeze = require(script.Parent.Parent.Util.deepFreeze)

export type Look = {
	lighting: { [string]: any },
	atmosphere: { [string]: any },
	grade: { [string]: any },
}
export type Biome = {
	ground: Color3,
	rock: Color3,
	accent: Color3,
	groundMaterial: Enum.Material,
	wallMaterial: Enum.Material,
	groundVariant: string,
	wallVariant: string,
	look: Look,
}

local function look(
	ambient: Color3,
	sky: Color3,
	decay: Color3,
	tint: Color3,
	time: number,
	density: number
): Look
	return {
		lighting = {
			Ambient = ambient,
			OutdoorAmbient = ambient:Lerp(Color3.new(1, 1, 1), 0.16),
			Brightness = 2.4,
			ClockTime = time,
		},
		atmosphere = {
			Color = sky,
			Decay = decay,
			Density = density,
			Haze = 0.8,
			Glare = 0.05,
			Offset = 0.1,
		},
		grade = { TintColor = tint, Saturation = 0.1, Contrast = 0.05 },
	}
end

local dust: Biome = {
	ground = Color3.fromRGB(163, 132, 110),
	rock = Color3.fromRGB(136, 107, 88),
	accent = Color3.fromRGB(222, 187, 126),
	groundMaterial = Enum.Material.Sand,
	wallMaterial = Enum.Material.Rock,
	groundVariant = "",
	wallVariant = "",
	look = look(
		Color3.fromRGB(112, 103, 119),
		Color3.fromRGB(250, 211, 176),
		Color3.fromRGB(140, 114, 130),
		Color3.fromRGB(255, 249, 240),
		16.0,
		0.22
	),
}
local ember: Biome = {
	ground = Color3.fromRGB(79, 69, 67),
	rock = Color3.fromRGB(80, 66, 65),
	accent = Color3.fromRGB(255, 165, 67),
	groundMaterial = Enum.Material.Basalt,
	wallMaterial = Enum.Material.Basalt,
	groundVariant = "",
	wallVariant = "MH_CanyonRock",
	look = look(
		Color3.fromRGB(124, 100, 98),
		Color3.fromRGB(255, 199, 146),
		Color3.fromRGB(149, 93, 88),
		Color3.fromRGB(255, 238, 218),
		16.8,
		0.25
	),
}
local frost: Biome = {
	ground = Color3.fromRGB(164, 196, 210),
	rock = Color3.fromRGB(154, 187, 205),
	accent = Color3.fromRGB(164, 233, 255),
	groundMaterial = Enum.Material.Glacier,
	wallMaterial = Enum.Material.Glacier,
	groundVariant = "",
	wallVariant = "",
	look = look(
		Color3.fromRGB(114, 136, 156),
		Color3.fromRGB(204, 233, 248),
		Color3.fromRGB(128, 161, 189),
		Color3.fromRGB(237, 249, 255),
		14.4,
		0.21
	),
}
local void: Biome = {
	ground = Color3.fromRGB(77, 72, 106),
	rock = Color3.fromRGB(102, 91, 137),
	accent = Color3.fromRGB(192, 167, 241),
	groundMaterial = Enum.Material.Slate,
	wallMaterial = Enum.Material.Slate,
	groundVariant = "",
	wallVariant = "",
	look = look(
		Color3.fromRGB(116, 106, 151),
		Color3.fromRGB(209, 192, 241),
		Color3.fromRGB(106, 88, 148),
		Color3.fromRGB(244, 237, 255),
		18.2,
		0.23
	),
}
local nova: Biome = {
	ground = Color3.fromRGB(73, 104, 112),
	rock = Color3.fromRGB(87, 124, 134),
	accent = Color3.fromRGB(134, 255, 224),
	groundMaterial = Enum.Material.Metal,
	wallMaterial = Enum.Material.Metal,
	groundVariant = "",
	wallVariant = "",
	look = look(
		Color3.fromRGB(104, 137, 147),
		Color3.fromRGB(188, 239, 230),
		Color3.fromRGB(76, 132, 151),
		Color3.fromRGB(234, 255, 250),
		16.2,
		0.2
	),
}

return deepFreeze({
	BLOOM = { Intensity = 0.25, Threshold = 2.5, Size = 16 },
	STATION = look(
		Color3.fromRGB(108, 117, 139),
		Color3.fromRGB(240, 221, 203),
		Color3.fromRGB(126, 124, 149),
		Color3.fromRGB(255, 250, 250),
		16.0,
		0.2
	),
	ZONES = { dust, ember, frost, void, nova },
})

--!strict
-- Non-interactive scenery: no collisions, touch events, or gameplay ray hits.
local CollectionService = game:GetService("CollectionService")
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Biomes = require(Shared.Theme.Biomes)
local Config = require(Shared.Config.BiomeAtmosphere)
type Biome = Biomes.Biome
local Scenery = {}

local function block(
	parent: Instance,
	name: string,
	size: Vector3,
	cf: CFrame,
	color: Color3,
	material: Enum.Material,
	wedge: boolean?
): BasePart
	local p = Instance.new(if wedge then "WedgePart" else "Part") :: BasePart
	p.Name, p.Size, p.CFrame = name, size, cf
	p.Color, p.Material = color, material
	p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch = true, false, false, false
	p.CastShadow = material ~= Enum.Material.Neon
	p.TopSurface, p.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

local function line(
	parent: Instance,
	name: string,
	a: Vector3,
	b: Vector3,
	width: number,
	color: Color3,
	material: Enum.Material
)
	block(
		parent,
		name,
		Vector3.new(width, width, (b - a).Magnitude),
		CFrame.lookAt((a + b) / 2, b),
		color,
		material
	)
end

local function ring(
	parent: Instance,
	name: string,
	cf: CFrame,
	radius: number,
	color: Color3,
	material: Enum.Material
)
	for i = 1, 18 do
		local a, b = (i - 1) * math.pi / 9, i * math.pi / 9
		line(
			parent,
			name,
			cf * Vector3.new(math.cos(a) * radius, math.sin(a) * radius, 0),
			cf * Vector3.new(math.cos(b) * radius, math.sin(b) * radius, 0),
			2,
			color,
			material
		)
	end
end

local function motes(parent: BasePart, color: Color3, steam: boolean)
	local e = Instance.new("ParticleEmitter")
	e.Name = "BiomeMotes"
	e.Enabled = false -- each client enables only nearby emitters
	e.Texture = "rbxasset://textures/particles/smoke_main.dds"
	e.Color = ColorSequence.new(color)
	e.Rate = Config.PARTICLE_RATE
	e.Lifetime = NumberRange.new(Config.PARTICLE_LIFETIME)
	e.Speed = NumberRange.new(if steam then 3 else 0.5, if steam then 6 else 1.5)
	e.SpreadAngle = Vector2.new(35, 35)
	e.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 2),
		NumberSequenceKeypoint.new(1, if steam then 12 else 5),
	})
	e.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.3, 0.8),
		NumberSequenceKeypoint.new(1, 1),
	})
	e.LightEmission = 0.15
	e.Parent = parent
	CollectionService:AddTag(e, "BiomeMotes")
end

local function landmark(
	parent: Instance,
	index: number,
	side: number,
	halfWidth: number,
	z: number,
	spec: Biome
)
	local origin = Vector3.new(side * (halfWidth + 105), 0, z)
	local cf = CFrame.new(origin) * CFrame.Angles(0, side * 0.2, 0)
	if index == 1 then
		-- Broken survey craft, with a readable wing and a tilted antenna.
		block(
			parent,
			"SurveyHull",
			Vector3.new(38, 14, 72),
			cf * CFrame.new(0, 9, 0) * CFrame.Angles(0.08, 0, -side * 0.14),
			Color3.fromRGB(157, 165, 172),
			Enum.Material.Metal,
			true
		)
		local cockpit = block(
			parent,
			"SurveyCockpit",
			Vector3.new(14, 6, 17),
			cf * CFrame.new(0, 15, -13) * CFrame.Angles(0.08, 0, -side * 0.14),
			Color3.fromRGB(88, 145, 169),
			Enum.Material.Glass,
			true
		)
		cockpit.Transparency = 0.2
		for engineSide = -1, 1, 2 do
			local engine = block(
				parent,
				"SurveyEngine",
				Vector3.new(13, 9, 9),
				cf * CFrame.new(engineSide * 13, 8, 24) * CFrame.Angles(0, math.pi / 2, 0),
				Color3.fromRGB(72, 84, 95),
				Enum.Material.Metal
			) :: Part
			engine.Shape = Enum.PartType.Cylinder
		end
		block(
			parent,
			"BrokenWing",
			Vector3.new(70, 3, 25),
			cf * CFrame.new(side * 6, 5, 8) * CFrame.Angles(0, 0.4, 0.1),
			spec.rock,
			Enum.Material.Metal,
			true
		)
		line(
			parent,
			"SurveyAntenna",
			origin + Vector3.new(0, 9, -12),
			origin + Vector3.new(side * 18, 57, -18),
			2,
			spec.accent,
			Enum.Material.Metal
		)
		motes(
			block(
				parent,
				"DustVent",
				Vector3.new(10, 1, 10),
				cf * CFrame.new(20, 0, 20),
				spec.rock,
				Enum.Material.Ground
			),
			spec.accent,
			false
		)
	elseif index == 2 then
		block(
			parent,
			"Caldera",
			Vector3.new(104, 32, 20),
			cf * CFrame.new(0, 12, -73),
			spec.rock,
			Enum.Material.Basalt,
			true
		)
		block(
			parent,
			"LavaBasin",
			Vector3.new(74, 0.3, 86),
			cf * CFrame.new(0, 0.3, -18),
			spec.accent,
			Enum.Material.Neon
		)
		for bankSide = -1, 1, 2 do
			block(
				parent,
				"CalderaBank",
				Vector3.new(12, 12, 104),
				cf * CFrame.new(bankSide * 44, 4, -18),
				spec.rock,
				Enum.Material.Basalt,
				true
			)
		end
		block(
			parent,
			"CalderaBank",
			Vector3.new(98, 8, 10),
			cf * CFrame.new(0, 2, 34),
			spec.rock,
			Enum.Material.Basalt,
			true
		)
		for i = 1, 5 do
			local h = 40 + i * 8
			block(
				parent,
				"BasaltChimney",
				Vector3.new(17, h, 19),
				cf * CFrame.new((i - 3) * 22, h / 2, -35),
				spec.rock:Lerp(Color3.new(0, 0, 0), i * 0.06),
				Enum.Material.Basalt
			)
		end
		motes(
			block(
				parent,
				"SteamVent",
				Vector3.new(10, 2, 10),
				cf * CFrame.new(0, 2, 25),
				spec.rock,
				Enum.Material.Basalt
			),
			Color3.fromRGB(224, 205, 183),
			true
		)
	elseif index == 3 then
		for i = 1, 5 do
			local h = 55 + i * 12
			block(
				parent,
				"GlacierSpire",
				Vector3.new(24, h, 33),
				cf
					* CFrame.new((i - 3) * 22, h / 2 - 2, -math.abs(i - 3) * 13)
					* CFrame.Angles(0, i * 0.6, side * 0.12),
				spec.rock:Lerp(Color3.new(1, 1, 1), i * 0.09),
				Enum.Material.Glacier,
				true
			)
		end
		ring(
			parent,
			"IceSurveyRing",
			cf * CFrame.new(0, 46, 40) * CFrame.Angles(0, side * math.pi / 2, 0),
			23,
			spec.accent,
			Enum.Material.Metal
		)
		motes(
			block(
				parent,
				"ColdMist",
				Vector3.new(12, 1, 12),
				cf * CFrame.new(-25, 1, 25),
				spec.rock,
				Enum.Material.Glacier
			),
			Color3.fromRGB(221, 245, 255),
			false
		)
	elseif index == 4 then
		ring(
			parent,
			"OrbitalRing",
			cf * CFrame.new(0, 88, 0) * CFrame.Angles(0.25, 0.3, 0.2),
			44,
			spec.accent,
			Enum.Material.Neon
		)
		ring(
			parent,
			"BrokenOrbit",
			cf * CFrame.new(0, 88, 0) * CFrame.Angles(0.9, -0.5, 0.3),
			53,
			spec.rock,
			Enum.Material.Metal
		)
		block(
			parent,
			"SuspendedMonolith",
			Vector3.new(29, 57, 34),
			cf * CFrame.new(0, 88, 0) * CFrame.Angles(0.4, 0.4, 0.2),
			spec.rock,
			Enum.Material.Slate,
			true
		)
	else
		block(
			parent,
			"ReactorPlinth",
			Vector3.new(96, 12, 96),
			cf * CFrame.new(0, 6, 0),
			spec.rock,
			Enum.Material.Metal
		)
		for i = 1, 3 do
			ring(
				parent,
				"ContainmentRing",
				cf * CFrame.new(0, 35 + i * 15, 0) * CFrame.Angles(math.pi / 2, 0, 0),
				31 + i * 4,
				if i == 2 then spec.accent else spec.rock,
				if i == 2 then Enum.Material.Neon else Enum.Material.Metal
			)
		end
		local core = block(
			parent,
			"NovaCore",
			Vector3.new(34, 34, 34),
			cf * CFrame.new(0, 65, 0),
			spec.accent,
			Enum.Material.Neon
		) :: Part
		core.Shape = Enum.PartType.Ball
		core.Transparency = 0.08
		CollectionService:AddTag(core, "BiomePulse")
		for i = 1, 4 do
			local a = i * math.pi / 2
			block(
				parent,
				"ReactorPylon",
				Vector3.new(9, 94, 9),
				cf * CFrame.new(math.cos(a) * 43, 47, math.sin(a) * 43),
				spec.rock,
				Enum.Material.Metal
			)
		end
	end
end

function Scenery.build(
	parent: Instance,
	index: number,
	halfWidth: number,
	startZ: number,
	length: number
)
	local spec = Biomes.ZONES[index]
	local rng = Random.new(81011 + index)
	for side = -1, 1, 2 do
		local landmarkZ = startZ - length * (if side < 0 then 0.42 else 0.68)
		for step = 1, math.floor(length / 140) do
			local z = startZ - 80 - (step - 1) * 140
			for layer = 1, 2 do
				-- Leave a clearing so the hero silhouette is not buried in ridges.
				if math.abs(z - landmarkZ) < 115 then
					continue
				end
				local h = rng:NextNumber(24, 45) + layer * 14
				local x = side * (halfWidth + 80 + layer * 62)
				local pos = Vector3.new(x, h / 2 - 5, z)
				local size = Vector3.new(60, h, 128)
				if index == 2 then
					size = Vector3.new(32, h * 1.5, 50)
					pos = Vector3.new(x, size.Y / 2 - 2, z)
				elseif index == 3 then
					size = Vector3.new(35, h * 1.8, 58)
					pos = Vector3.new(x, size.Y / 2 - 2, z)
				elseif index == 4 then
					pos += Vector3.new(0, 45 + step % 3 * 18, 0)
					size = Vector3.new(32, h * 0.7, 42)
				elseif index == 5 then
					size = Vector3.new(35, h * 1.4, 35)
				end
				block(
					parent,
					"BiomeRidge",
					size,
					CFrame.new(pos) * CFrame.Angles(0, rng:NextNumber(-0.4, 0.4), side * 0.13),
					spec.rock:Lerp(Color3.fromRGB(45, 49, 66), layer * 0.2),
					spec.wallMaterial,
					index ~= 2 and index ~= 5
				)
			end
			if index == 2 then
				local a = Vector3.new(side * (halfWidth + 25), 0.35, z + 45)
				local b = a + Vector3.new(side * 110, 0, -50)
				line(parent, "LavaFissure", a, b, 1.4, spec.accent, Enum.Material.Neon)
			elseif index == 3 then
				block(
					parent,
					"SnowShelf",
					Vector3.new(70, 6, 90),
					CFrame.new(side * (halfWidth + 60), 1, z),
					Color3.fromRGB(224, 239, 245),
					Enum.Material.Snow,
					true
				)
			elseif index == 4 then
				line(
					parent,
					"MonolithVein",
					Vector3.new(side * (halfWidth + 142), 75, z),
					Vector3.new(side * (halfWidth + 142), 95, z),
					1.4,
					spec.accent,
					Enum.Material.Neon
				)
			elseif index == 5 then
				block(
					parent,
					"PowerConduit",
					Vector3.new(7, 14, 60),
					CFrame.new(side * (halfWidth + 45), 7, z),
					spec.rock,
					Enum.Material.Metal
				)
				line(
					parent,
					"PowerSpine",
					Vector3.new(side * (halfWidth + 45), 14.2, z + 28),
					Vector3.new(side * (halfWidth + 45), 14.2, z - 28),
					1,
					spec.accent,
					Enum.Material.Neon
				)
			end
		end
		landmark(parent, index, side, halfWidth, landmarkZ, spec)
	end
end
return Scenery

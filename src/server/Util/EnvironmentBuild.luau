--!strict
-- Deterministic scenery and readable routes, with clear space for gameplay.
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Zones = require(Shared.Config.Zones)
local Theme = require(Shared.Theme)
local Economy = require(Shared.Config.Economy)
local Arena = require(Shared.Config.Arena)
local Biomes = require(Shared.Theme.Biomes)
local BiomeScenery = require(script.Parent.BiomeScenery)

local EnvironmentBuild = {}

local function part(
	parent: Instance,
	name: string,
	size: Vector3,
	position: Vector3,
	color: Color3,
	material: Enum.Material,
	collision: boolean?
): Part
	local p = Instance.new(if name == "CraterRidge" then "WedgePart" else "Part") :: Part
	p.Name, p.Size, p.Position = name, size, position
	p.Color, p.Material = color, material
	p.Anchored = true
	p.CanCollide = collision == true
	p.CanQuery = collision == true
	p.CanTouch = false
	p.TopSurface, p.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

local function sign(parent: BasePart, word: string, value: string)
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Back
	gui.LightInfluence = 0
	gui.PixelsPerStud = 35
	for i, text in { word, value } do
		local label = Instance.new("TextLabel")
		label.BackgroundTransparency = 1
		label.Position = UDim2.fromScale(0.04, if i == 1 then 0.06 else 0.55)
		label.Size = UDim2.fromScale(0.92, 0.38)
		label.TextScaled = true
		label.Font = Enum.Font.FredokaOne
		label.TextColor3 = if i == 1
			then Color3.fromRGB(210, 240, 255)
			else Color3.fromRGB(255, 220, 115)
		label.Text = text
		label.AutoLocalize = i == 1
		label.Parent = gui
	end
	gui.Parent = parent
end

function EnvironmentBuild.build(world: Instance, halfWidth: number, boundaries: { number })
	local root = Instance.new("Folder")
	root.Name = "Environment"
	root.Parent = world
	for index, zone in Zones.ZONES do
		local region = Instance.new("Folder")
		region.Name = `Biome{index}`
		local color = Biomes.ZONES[index].accent
		local startZ = boundaries[index]
		-- Ground continues under all five zones, rather than ending at -1024.
		part(
			region,
			"CraterBed",
			Vector3.new(1800, 5, zone.lengthStuds),
			Vector3.new(0, -2.5, startZ - zone.lengthStuds / 2),
			Biomes.ZONES[index].ground:Lerp(Color3.fromRGB(45, 42, 58), 0.3),
			Enum.Material.Slate,
			true
		)
		for side = -1, 1, 2 do
			-- Thin route edges, visible from both directions; no lane obstacles.
			-- Not in the Void Run zone: there they read as a laser across a lane.
			if index ~= Arena.FIELD_ZONE then
				part(
					region,
					"LaneEdge",
					Vector3.new(0.6, 0.12, zone.lengthStuds - 12),
					Vector3.new(side * 40, 0.27, startZ - zone.lengthStuds / 2),
					color,
					Enum.Material.Neon
				)
			end
			for step = 1, math.max(1, math.floor((zone.lengthStuds - 80) / 200) + 1) do
				local z = startZ - 60 - (step - 1) * 200
				-- Beacon lights would read as hazards from the Void Run camera.
				if index ~= Arena.FIELD_ZONE then
					local post = part(
						region,
						"RouteBeacon",
						Vector3.new(1.4, 5, 1.4),
						Vector3.new(side * 42, 2.7, z),
						Color3.fromRGB(35, 42, 56),
						Enum.Material.Metal
					)
					part(
						region,
						"BeaconLight",
						Vector3.new(1.8, 0.8, 1.8),
						post.Position + Vector3.new(0, 2.5, 0),
						color,
						Enum.Material.Neon
					)
				end
				if step == 1 then
					local board = part(
						region,
						"ZoneBoard",
						Vector3.new(20, 7, 0.7),
						Vector3.new(side * 54, 8, z),
						Color3.fromRGB(28, 34, 48),
						Enum.Material.Metal
					)
					sign(
						board,
						Theme.ZONE_NAMES[index] or "Station",
						`⚡ {zone.speedGate}`
							.. (if zone.rebirthGate > 0 then `  ♻ {zone.rebirthGate}` else "")
					)
				end
			end
		end
		BiomeScenery.build(region, index, halfWidth, startZ, zone.lengthStuds)
		region.Parent = root
		task.wait()
	end
	local hub = Instance.new("Folder")
	hub.Name = "StationHub"
	for index = 1, Economy.SERVER_SIZE do
		local x = (index - (Economy.SERVER_SIZE + 1) / 2) * 70
		part(
			hub,
			"HomePath",
			Vector3.new(4, 0.1, 24),
			Vector3.new(x, 0.27, 8),
			Color3.fromRGB(100, 220, 170),
			Enum.Material.Neon
		)
	end
	for side = -1, 1, 2 do
		part(
			hub,
			"DeckTrim",
			Vector3.new(halfWidth * 2 + 20, 0.14, 0.7),
			Vector3.new(0, 0.26, if side < 0 then 3 else 88),
			Color3.fromRGB(100, 175, 210),
			Enum.Material.Neon
		)
	end
	local home = part(
		hub,
		"HomeBoard",
		Vector3.new(28, 6, 0.7),
		Vector3.new(0, 6, 14),
		Color3.fromRGB(28, 34, 48),
		Enum.Material.Metal
	)
	-- Faces the field to make the return destination readable.
	home.CFrame *= CFrame.Angles(0, math.pi, 0)
	sign(home, "Safe station area", "⌂")
	hub.Parent = root
end

return EnvironmentBuild

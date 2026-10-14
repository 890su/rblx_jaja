--!strict
-- Builds the greybox world at runtime from Config: a row of station plots and a
-- long straight track split into zones, with speed gates between zones.
-- Layout: plots sit at +Z, the track runs from Z = 0 toward -Z.
-- Gates are non-colliding on the server; GateController makes locked gates
-- solid locally and SpeedService enforces gates server-side.

local CollectionService = game:GetService("CollectionService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Economy = require(Shared.Config.Economy)
local Zones = require(Shared.Config.Zones)
local Canyons = require(Shared.Config.Canyons)
local Maze = require(Shared.Util.Maze)
local Notifier = require(script.Parent.Parent.Util.Notifier)
local Theme = require(Shared.Theme)
local EnvironmentBuild = require(script.Parent.Parent.Util.EnvironmentBuild)
local Biomes = require(Shared.Theme.Biomes)
local ArenaWorldBuild = require(script.Parent.Parent.Util.ArenaWorldBuild)
local CryoCapsuleBuild = require(script.Parent.Parent.Util.CryoCapsuleBuild)

export type Plot = {
	index: number,
	model: Model,
	spawn: CFrame,
	pedestals: { BasePart },
	collector: BasePart,
	treadmill: BasePart,
	center: Vector3,
}

local PLOT_SIZE = 60
local PLOT_GAP = 10
local PLOT_PITCH = PLOT_SIZE + PLOT_GAP
local PLOT_Z = 45 -- plot center Z
local FLOOR_TOP = 0.2 -- slightly above the default Baseplate to avoid z-fighting
local WALL_HEIGHT = 80
-- Invisible walls around the whole playable area: tall enough that no jump,
-- knockback or fling clears them (SpeedService also pulls strays back in).
local BOUNDARY_HEIGHT = 300
local DECK_BACK_Z = PLOT_Z + (PLOT_SIZE + 30) / 2 -- far edge of the station deck
local PEDESTAL_SLOTS = Economy.PEDESTALS_MAX_COINS + Economy.PEDESTALS_EXPANSION_PASS

local WorldService = {}

local plots: { Plot } = {}
local world: Folder
local canyonFolder: Folder?
local canyonCells: { [number]: { Vector3 } } = {} -- zone -> open cell centers
local canyonDay = -1
local zoneStartZ: { number } = {} -- zone i spans (zoneStartZ[i+1], zoneStartZ[i]]
local trackHalfWidth = 0

local function part(props: { [string]: any }, parent: Instance): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	for key, value in props do
		(p :: any)[key] = value
	end
	p.Parent = parent
	return p
end

-- Billboard sign with one localized term (auto-translated per viewer).
local function billboard(
	adornee: BasePart,
	text: string,
	offset: Vector3,
	size: Vector2,
	color: Color3,
	maxDistance: number
)
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(size.X, size.Y)
	gui.StudsOffset = offset
	gui.MaxDistance = maxDistance
	gui.LightInfluence = 0
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.TextScaled = true
	label.Font = Enum.Font.FredokaOne
	label.TextColor3 = color
	label.TextStrokeTransparency = 0.2
	label.Text = text
	label.Parent = gui
	gui.Parent = adornee
	return gui
end

local function buildPlot(index: number, count: number, parent: Instance): Plot
	local x = (index - (count + 1) / 2) * PLOT_PITCH
	local center = Vector3.new(x, FLOOR_TOP, PLOT_Z)

	local model = Instance.new("Model")
	model.Name = `Plot{index}`

	local floor = part({
		Name = "Floor",
		Size = Vector3.new(PLOT_SIZE, 1, PLOT_SIZE),
		Position = center - Vector3.new(0, 0.5, 0),
		Color = Color3.fromRGB(80, 86, 105),
		Material = Theme.MATERIALS.stationFloor.base,
		MaterialVariant = Theme.MATERIALS.stationFloor.variant,
	}, model)
	model.PrimaryPart = floor

	local pedestals: { BasePart } = {}
	for slot = 1, PEDESTAL_SLOTS do
		local row = (slot - 1) // 5
		local col = (slot - 1) % 5
		local pedestal = CryoCapsuleBuild.create(
			model,
			center + Vector3.new((col - 2) * 11, 1, 8 + row * 12),
			slot
		)
		-- Owner-only unlock button (visibility handled by StationController).
		local unlock = Instance.new("ProximityPrompt")
		unlock.Name = "UnlockPrompt"
		unlock.ActionText = "Unlock"
		unlock.HoldDuration = 0.3
		unlock.MaxActivationDistance = 10
		unlock.RequiresLineOfSight = false
		unlock.KeyboardKeyCode = Enum.KeyCode.E
		unlock.Enabled = false
		unlock.Parent = pedestal
		CollectionService:AddTag(unlock, "UnlockPrompt")
		pedestals[slot] = pedestal
	end

	local collector = part({
		Name = "Collector",
		Size = Vector3.new(10, 0.4, 6),
		Position = center + Vector3.new(0, 0.2, -12),
		Color = Color3.fromRGB(255, 200, 60),
		Material = Enum.Material.Neon,
		CanCollide = false,
	}, model)
	local collectorGui = Instance.new("BillboardGui")
	collectorGui.Name = "Info"
	collectorGui.Size = UDim2.fromOffset(180, 40)
	collectorGui.StudsOffset = Vector3.new(0, 3, 0)
	collectorGui.MaxDistance = 80
	collectorGui.Enabled = false
	for _, spec in
		{
			{ name = "Label", text = "Collect", y = 0, h = 0.5 },
			{ name = "Value", text = "", y = 0.5, h = 0.5 },
		}
	do
		local collectorLabel = Instance.new("TextLabel")
		collectorLabel.Name = spec.name
		collectorLabel.Position = UDim2.fromScale(0, spec.y)
		collectorLabel.Size = UDim2.fromScale(1, spec.h)
		collectorLabel.BackgroundTransparency = 1
		collectorLabel.TextScaled = true
		collectorLabel.Font = Enum.Font.FredokaOne
		collectorLabel.TextColor3 = Color3.fromRGB(255, 220, 90)
		collectorLabel.TextStrokeTransparency = 0.3
		collectorLabel.Text = spec.text
		collectorLabel.AutoLocalize = spec.name == "Label"
		collectorLabel.Parent = collectorGui
	end
	collectorGui.Parent = collector

	billboard(
		collector,
		"Collect Stardust",
		Vector3.new(0, 6, 0),
		Vector2.new(170, 34),
		Color3.fromRGB(255, 225, 110),
		70
	)
	local creaturesSign = part({
		Name = "CreaturesSign",
		Size = Vector3.new(0.5, 0.5, 0.5),
		Position = center + Vector3.new(0, 9, 14),
		Transparency = 1,
		CanCollide = false,
		CanQuery = false,
	}, model)
	billboard(
		creaturesSign,
		"Your creatures earn Stardust",
		Vector3.zero,
		Vector2.new(260, 34),
		Color3.fromRGB(190, 240, 255),
		70
	)

	-- Treadmill: rubber belt (detection part "Treadmill") with frame, rollers,
	-- handrails and a console screen. Arrows on the belt scroll client-side.
	local treadCenter = center + Vector3.new(20, 0, -12)
	local treadmill = part({
		Name = "Treadmill",
		Size = Vector3.new(6, 0.7, 14),
		Position = treadCenter + Vector3.new(0, 0.35, 0),
		Color = Color3.fromRGB(28, 28, 34),
		Material = Enum.Material.SmoothPlastic,
	}, model)
	for side = -1, 1, 2 do
		part({
			Name = "TreadFrame",
			Size = Vector3.new(1, 1.1, 15),
			Position = treadCenter + Vector3.new(side * 3.5, 0.55, 0),
			Color = Color3.fromRGB(150, 160, 180),
			Material = Enum.Material.Metal,
		}, model)
		-- Handrail post + rail along each side at the front half.
		part({
			Name = "TreadPost",
			Size = Vector3.new(0.4, 4, 0.4),
			Position = treadCenter + Vector3.new(side * 3.5, 3, -6.5),
			Color = Color3.fromRGB(150, 160, 180),
			Material = Enum.Material.Metal,
		}, model)
		part({
			Name = "TreadRail",
			Size = Vector3.new(0.35, 0.35, 6),
			Position = treadCenter + Vector3.new(side * 3.5, 4.8, -3.7),
			Color = Color3.fromRGB(80, 220, 255),
			Material = Enum.Material.Neon,
		}, model)
	end
	for _, z in { -7, 7 } do
		local roller = part({
			Name = "TreadRoller",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(6.4, 1.2, 1.2),
			Color = Color3.fromRGB(60, 60, 70),
			Material = Enum.Material.Metal,
		}, model)
		roller.CFrame = CFrame.new(treadCenter + Vector3.new(0, 0.6, z))
	end
	local console = part({
		Name = "TreadConsole",
		Size = Vector3.new(7, 2.6, 0.5),
		Color = Color3.fromRGB(30, 34, 48),
		Material = Enum.Material.Metal,
	}, model)
	console.CFrame = CFrame.new(treadCenter + Vector3.new(0, 5.4, -6.8))
		* CFrame.Angles(math.rad(-25), 0, 0)
	local screen = Instance.new("SurfaceGui")
	screen.Face = Enum.NormalId.Back -- faces the runner (+Z side)
	screen.LightInfluence = 0
	screen.Parent = console
	for _, spec in
		{
			{ text = "TREADMILL", y = 0.05, h = 0.45, color = Color3.fromRGB(120, 230, 255) },
			{
				text = "+Speed while you stand here",
				y = 0.52,
				h = 0.4,
				color = Color3.fromRGB(255, 230, 120),
			},
		}
	do
		local label = Instance.new("TextLabel")
		label.BackgroundTransparency = 1
		label.Position = UDim2.fromScale(0.04, spec.y)
		label.Size = UDim2.fromScale(0.92, spec.h)
		label.TextScaled = true
		label.Font = Enum.Font.FredokaOne
		label.TextColor3 = spec.color
		label.Text = spec.text
		label.Parent = screen
	end
	-- Neon chevrons on the belt; FeedbackController slides them from the back
	-- of the belt toward the console so it reads as a running treadmill.
	local chevrons = Instance.new("Folder")
	chevrons.Name = "BeltChevrons"
	chevrons:SetAttribute("BeltCFrame", CFrame.new(treadCenter + Vector3.new(0, 0.72, 0)))
	chevrons:SetAttribute("BeltLength", 12)
	for i = 0, 4 do
		for side = -1, 1, 2 do
			local arm = part({
				Name = "BeltChevron",
				Size = Vector3.new(0.5, 0.06, 2.4),
				Color = Color3.fromRGB(90, 210, 255),
				Material = Enum.Material.Neon,
				CanCollide = false,
				CanQuery = false,
				CanTouch = false,
			}, chevrons)
			arm:SetAttribute("Phase", i / 5)
			arm:SetAttribute("Side", side)
			arm.CFrame = CFrame.new(treadCenter + Vector3.new(0, -5, 0)) -- placed client-side
		end
	end
	chevrons.Parent = model
	CollectionService:AddTag(chevrons, "TreadmillBelt")

	local sign = part({
		Name = "Sign",
		Size = Vector3.new(10, 6, 1),
		Position = center + Vector3.new(-23, 6, -23),
		Color = Color3.fromRGB(30, 30, 45),
	}, model)
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	-- Owner name (never translated) above the localized "Station" term.
	for _, spec in
		{
			{ name = "Owner", text = "", y = 0, h = 0.55 },
			{ name = "Title", text = Theme.BASE, y = 0.55, h = 0.45 },
		}
	do
		local label = Instance.new("TextLabel")
		label.Name = spec.name
		label.Position = UDim2.fromScale(0, spec.y)
		label.Size = UDim2.fromScale(1, spec.h)
		label.BackgroundTransparency = 1
		label.TextScaled = true
		label.Font = Enum.Font.FredokaOne
		label.TextColor3 = Color3.new(1, 1, 1)
		label.Text = spec.text
		label.AutoLocalize = spec.name == "Title"
		label.Parent = gui
	end
	gui.Parent = sign

	model.Parent = parent
	return {
		index = index,
		model = model,
		spawn = CFrame.new(center + Vector3.new(0, 3, -2)),
		pedestals = pedestals,
		collector = collector,
		treadmill = treadmill,
		center = center,
	}
end

local function buildTrack(parent: Instance)
	local folder = Instance.new("Folder")
	folder.Name = "Track"
	trackHalfWidth = Economy.SERVER_SIZE * PLOT_PITCH / 2

	local z = 0
	for i, zone in Zones.ZONES do
		zoneStartZ[i] = z
		local biome = Biomes.ZONES[i]
		part({
			Name = `Zone{i}`,
			Size = Vector3.new(trackHalfWidth * 2, 1, zone.lengthStuds),
			Position = Vector3.new(0, FLOOR_TOP - 0.5, z - zone.lengthStuds / 2),
			Color = biome.ground,
			Material = biome.groundMaterial,
			MaterialVariant = biome.groundVariant,
			CustomPhysicalProperties = PhysicalProperties.new(Theme.MATERIALS.trackGround.base),
		}, folder)

		if zone.speedGate > 0 or zone.rebirthGate > 0 then
			local gate = part({
				Name = `Gate{i}`,
				Size = Vector3.new(trackHalfWidth * 2, WALL_HEIGHT, 2),
				Position = Vector3.new(0, WALL_HEIGHT / 2, z),
				Color = Color3.fromRGB(80, 160, 255),
				Material = Enum.Material.ForceField,
				Transparency = 0.3,
				CanCollide = false,
			}, folder)
			gate:SetAttribute("ZoneIndex", i)
			-- Zone names arrive through the responsive HUD. A fixed 320 px
			-- floating sign filled the phone view long before reaching this gate.
			gate:SetAttribute("SpeedGate", zone.speedGate)
			gate:SetAttribute("RebirthGate", zone.rebirthGate)
			CollectionService:AddTag(gate, "SpeedGate")

			local gui = Instance.new("SurfaceGui")
			gui.Face = Enum.NormalId.Back -- faces the station side (+Z)
			-- Zone name (localized term) on the left, numeric requirement on the right.
			local requirement = `⚡ {zone.speedGate}`
			if zone.rebirthGate > 0 then
				requirement ..= `  ♻ {zone.rebirthGate}`
			end
			for _, spec in
				{
					{ text = Theme.ZONE_NAMES[i] or `Zone {i}`, x = 0, w = 0.6, localize = true },
					{ text = requirement, x = 0.6, w = 0.4, localize = false },
				}
			do
				local label = Instance.new("TextLabel")
				label.Position = UDim2.fromScale(spec.x, 0)
				label.Size = UDim2.fromScale(spec.w, 1)
				label.BackgroundTransparency = 1
				label.TextScaled = true
				label.Font = Enum.Font.FredokaOne
				label.TextColor3 = Color3.new(1, 1, 1)
				label.Text = spec.text
				label.AutoLocalize = spec.localize
				label.Parent = gui
			end
			gui.Parent = gate
		end
		z -= zone.lengthStuds
	end
	zoneStartZ[#Zones.ZONES + 1] = z

	-- Entrance arch over the speed lane + glowing chevrons pointing into the crater.
	for side = -1, 1, 2 do
		part({
			Name = "ArchPillar",
			Size = Vector3.new(6, 34, 6),
			Position = Vector3.new(side * 46, 17, -6),
			Color = Color3.fromRGB(70, 75, 100),
			Material = Enum.Material.Metal,
		}, folder)
	end
	local beam = part({
		Name = "ArchBeam",
		Size = Vector3.new(98, 7, 5),
		Position = Vector3.new(0, 36, -6),
		Color = Color3.fromRGB(40, 44, 66),
		Material = Enum.Material.Metal,
	}, folder)
	local archGui = Instance.new("SurfaceGui")
	archGui.Face = Enum.NormalId.Back -- faces the stations (+Z)
	archGui.LightInfluence = 0
	archGui.Parent = beam
	local archLabel = Instance.new("TextLabel")
	archLabel.BackgroundTransparency = 1
	archLabel.Size = UDim2.fromScale(1, 1)
	archLabel.TextScaled = true
	archLabel.Font = Enum.Font.FredokaOne
	archLabel.TextColor3 = Color3.fromRGB(255, 200, 110)
	archLabel.Text = "CRATER FIELD"
	archLabel.Parent = archGui
	billboard(
		beam,
		"Meteors this way",
		Vector3.new(0, -9, 0),
		Vector2.new(220, 40),
		Color3.fromRGB(150, 230, 255),
		160
	)
	for i = 1, 9 do
		local chevronZ = -14 - (i - 1) * 16
		for side = -1, 1, 2 do
			local arm = part({
				Name = "Chevron",
				Size = Vector3.new(0.8, 0.2, 9),
				Color = Color3.fromRGB(90, 210, 255),
				Material = Enum.Material.Neon,
				CanCollide = false,
				CanQuery = false,
			}, folder)
			-- Two arms meeting at the front form a ^ pointing toward -Z.
			arm.CFrame = CFrame.new(side * 3.1, FLOOR_TOP + 0.12, chevronZ)
				* CFrame.Angles(0, math.rad(35) * side, 0)
		end
	end

	for side = -1, 1, 2 do
		for i, zone in Zones.ZONES do
			part({
				Name = "SideWall",
				Size = Vector3.new(2, BOUNDARY_HEIGHT, zone.lengthStuds),
				Position = Vector3.new(
					side * (trackHalfWidth + 1),
					BOUNDARY_HEIGHT / 2,
					zoneStartZ[i] - zone.lengthStuds / 2
				),
				Transparency = 1,
			}, folder)
		end
		-- The station deck is closed off too (it used to be open at the sides
		-- and back, so players could walk around the outside of the track).
		part({
			Name = "StationWall",
			Size = Vector3.new(2, BOUNDARY_HEIGHT, DECK_BACK_Z + 2),
			Position = Vector3.new(
				side * (trackHalfWidth + 1),
				BOUNDARY_HEIGHT / 2,
				(DECK_BACK_Z + 2) / 2
			),
			Transparency = 1,
		}, folder)
	end
	part({
		Name = "StationBackWall",
		Size = Vector3.new(trackHalfWidth * 2 + 4, BOUNDARY_HEIGHT, 2),
		Position = Vector3.new(0, BOUNDARY_HEIGHT / 2, DECK_BACK_Z + 1),
		Transparency = 1,
	}, folder)
	part({
		Name = "EndWall",
		Size = Vector3.new(trackHalfWidth * 2, BOUNDARY_HEIGHT, 2),
		Position = Vector3.new(0, BOUNDARY_HEIGHT / 2, z - 1),
		Transparency = 1,
	}, folder)

	folder.Parent = parent
end

local function canyonWall(cframe: CFrame, size: Vector3, parent: Instance, zoneIndex: number)
	local biome = Biomes.ZONES[zoneIndex]
	part({
		Name = "CanyonWall",
		Size = size,
		CFrame = cframe,
		Color = biome.rock,
		Material = biome.wallMaterial,
		MaterialVariant = biome.wallVariant,
		CustomPhysicalProperties = PhysicalProperties.new(Theme.MATERIALS.canyonWall.base),
	}, parent)
end

-- One maze pocket on `side` (-1 left, 1 right) of the speed lane in a zone.
-- Walls are merged into runs to keep the part count low.
local function buildCanyonSide(zoneIndex: number, side: number, rng: Random, parent: Instance)
	local cell = Canyons.CELL
	local laneHalf = Canyons.LANE_WIDTH / 2
	local cols = math.floor((trackHalfWidth - laneHalf) / cell)
	local zoneLength = Zones.ZONES[zoneIndex].lengthStuds
	local rows = math.floor(zoneLength / cell)
	local top = zoneStartZ[zoneIndex] - (zoneLength - rows * cell) / 2 -- maze edge nearest the station
	local h, t = Canyons.WALL_HEIGHT, Canyons.WALL_THICKNESS
	local y = FLOOR_TOP + h / 2

	local grid = Maze.generate(cols, rows, rng, Canyons.BRAID)
	local function xAt(edge: number): number -- edge 0..cols, 0 = lane side
		return side * (laneHalf + edge * cell)
	end
	local function zAt(edge: number): number -- edge 0..rows, 0 = station side
		return top - edge * cell
	end

	-- Vertical runs (constant x): lane boundary (edge 0) and east walls between columns.
	local offset = rng:NextInteger(0, Canyons.LANE_OPENING_EVERY - 1)
	for edge = 0, cols - 1 do
		local runStart: number? = nil
		for row = 1, rows + 1 do
			local walled = false
			if row <= rows then
				if edge == 0 then
					walled = (row + offset) % Canyons.LANE_OPENING_EVERY ~= 0
				else
					walled = grid.cells[edge][row].east
				end
			end
			if walled and not runStart then
				runStart = row
			elseif not walled and runStart then
				local z1, z2 = zAt(runStart - 1), zAt(row - 1)
				canyonWall(
					CFrame.new(xAt(edge), y, (z1 + z2) / 2),
					Vector3.new(t, h, math.abs(z1 - z2) + t),
					parent,
					zoneIndex
				)
				runStart = nil
			end
		end
	end
	-- Horizontal runs (constant z): maze top/bottom boundary and south walls.
	for edge = 0, rows do
		local runStart: number? = nil
		for col = 1, cols + 1 do
			local walled = false
			if col <= cols then
				walled = edge == 0 or edge == rows or grid.cells[col][edge].south
			end
			if walled and not runStart then
				runStart = col
			elseif not walled and runStart then
				local x1, x2 = xAt(runStart - 1), xAt(col - 1)
				canyonWall(
					CFrame.new((x1 + x2) / 2, y, zAt(edge)),
					Vector3.new(math.abs(x1 - x2) + t, h, t),
					parent,
					zoneIndex
				)
				runStart = nil
			end
		end
	end

	local cells = canyonCells[zoneIndex]
	for col = 1, cols do
		for row = 1, rows do
			table.insert(cells, Vector3.new(xAt(col - 0.5), FLOOR_TOP + 2, zAt(row - 0.5)))
		end
	end
end

-- (Re)builds every canyon from the UTC-day seed: identical on all servers.
local function buildCanyons(day: number)
	if canyonFolder then
		canyonFolder:Destroy()
	end
	local folder = Instance.new("Folder")
	folder.Name = "Canyons"
	for zoneIndex = Canyons.FROM_ZONE, #Zones.ZONES do
		canyonCells[zoneIndex] = {}
		for side = -1, 1, 2 do
			local rng = Random.new(day * 1000 + zoneIndex * 10 + side + 1)
			buildCanyonSide(zoneIndex, side, rng, folder)
		end
	end
	folder.Parent = world
	canyonFolder = folder
	canyonDay = day
	world:SetAttribute("CanyonDay", day)
end

local function currentDay(): number
	return math.floor(os.time() / Canyons.RESEED_PERIOD)
end

-- Dusk-over-a-crater look: warm low sun, light haze, punchy colors.
-- Texture scale of the AI MaterialVariants (stored in the place).
local function setupMaterials()
	local MaterialService = game:GetService("MaterialService")
	local M = Theme.MATERIALS
	for _, spec in { M.canyonWall, M.trackGround, M.stationFloor } do
		local variant = MaterialService:FindFirstChild(spec.variant, true)
		if variant and variant:IsA("MaterialVariant") then
			variant.StudsPerTile = spec.studsPerTile
		end
	end
end

local function setupLighting()
	local Lighting = game:GetService("Lighting")
	Lighting.ClockTime = 17.4
	Lighting.Brightness = 2.4
	Lighting.Ambient = Color3.fromRGB(90, 95, 120)
	Lighting.OutdoorAmbient = Color3.fromRGB(120, 110, 150)
	Lighting.EnvironmentDiffuseScale = 0.6
	Lighting.EnvironmentSpecularScale = 0.6
	local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere") or Instance.new("Atmosphere")
	atmosphere.Name = "MeteorAtmosphere"
	atmosphere.Density = 0.28
	atmosphere.Haze = 1.2
	atmosphere.Color = Color3.fromRGB(255, 190, 160)
	atmosphere.Decay = Color3.fromRGB(110, 80, 150)
	atmosphere.Parent = Lighting
	local grade = Lighting:FindFirstChild("MeteorGrade") :: ColorCorrectionEffect?
	if not grade then
		local newGrade = Instance.new("ColorCorrectionEffect")
		newGrade.Name = "MeteorGrade"
		newGrade.Parent = Lighting
		grade = newGrade
	end
	local g = grade :: ColorCorrectionEffect
	g.Saturation = 0.18
	g.Contrast = 0.08
	g.TintColor = Color3.fromRGB(255, 245, 250)
	-- Neutral station look; biome variations are applied independently per client.
	local look = Biomes.STATION
	for target, properties in
		{ [Lighting] = look.lighting, [atmosphere] = look.atmosphere, [g] = look.grade }
	do
		for property, value in properties do
			(target :: any)[property] = value
		end
	end
	local bloom = Lighting:FindFirstChildOfClass("BloomEffect") or Instance.new("BloomEffect")
	for property, value in Biomes.BLOOM do
		(bloom :: any)[property] = value
	end
	bloom.Parent = Lighting
end

-- Replaces the template Baseplate with a wide crater plain under everything.
local function setupGround(parent: Instance)
	local baseplate = workspace:FindFirstChild("Baseplate")
	if baseplate then
		baseplate:Destroy()
	end
	local m = Theme.MATERIALS.trackGround
	part({
		Name = "CraterPlain",
		Size = Vector3.new(2048, 1, 2048),
		Position = Vector3.new(0, FLOOR_TOP - 0.55, 0),
		Color = Color3.fromRGB(105, 90, 100),
		Material = m.base,
		MaterialVariant = m.variant,
	}, parent)
	-- Deck that joins all stations (covers the gaps between plots).
	local deckWidth = Economy.SERVER_SIZE * PLOT_PITCH + 20
	part({
		Name = "StationDeck",
		Size = Vector3.new(deckWidth, 1, PLOT_SIZE + 30),
		Position = Vector3.new(0, FLOOR_TOP - 0.52, PLOT_Z),
		Color = Color3.fromRGB(55, 58, 75),
		Material = Enum.Material.Metal,
	}, parent)
end

-- Crater decor: crystal clusters (ReplicatedStorage.Assets.Decor.Crystal) on
-- the plain beside the track. Same layout on every server.
local function scatterDecor(parent: Instance)
	local assets = game:GetService("ReplicatedStorage"):FindFirstChild("Assets")
	local decor = assets and assets:FindFirstChild("Decor")
	local crystal = decor and decor:FindFirstChild("Crystal")
	if not crystal or not crystal:IsA("Model") then
		return
	end
	local folder = Instance.new("Folder")
	folder.Name = "Decor"
	local rng = Random.new(20261011)
	for _ = 1, 18 do
		local side = if rng:NextNumber() < 0.5 then -1 else 1
		local x = side * rng:NextNumber(trackHalfWidth + 25, trackHalfWidth + 420)
		local z = rng:NextNumber(zoneStartZ[4] + 50, zoneStartZ[3] - 50)
		local clone = crystal:Clone()
		for _, descendant in clone:GetDescendants() do
			if descendant:IsA("BasePart") then
				descendant.Anchored = true
				descendant.CanCollide, descendant.CanQuery, descendant.CanTouch =
					false, false, false
			end
		end
		clone:ScaleTo(clone:GetScale() * rng:NextNumber(0.8, 2.2))
		local _, size = clone:GetBoundingBox()
		-- Keep the entire rotated crystal outside the playable boundary.
		x = side
			* math.max(math.abs(x), trackHalfWidth + 25 + Vector2.new(size.X, size.Z).Magnitude / 2)
		clone:PivotTo(
			CFrame.new(x, FLOOR_TOP + size.Y / 2 - 0.3, z)
				* CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0)
		)
		clone.Parent = folder
	end
	folder.Parent = parent
end

function WorldService.init()
	setupLighting()
	setupMaterials()
	world = Instance.new("Folder")
	world.Name = "World"
	world.Parent = workspace
	setupGround(world)
	local plotFolder = Instance.new("Folder")
	plotFolder.Name = "Plots"
	plotFolder.Parent = world
	for i = 1, Economy.SERVER_SIZE do
		plots[i] = buildPlot(i, Economy.SERVER_SIZE, plotFolder)
		task.wait() -- flush one station at a time instead of one large subtree
	end
	buildTrack(world)
	ArenaWorldBuild.build(world, zoneStartZ)
	EnvironmentBuild.build(world, trackHalfWidth, zoneStartZ)
	buildCanyons(currentDay())
	scatterDecor(world)
end

function WorldService.start()
	while true do
		task.wait(30)
		local day = currentDay()
		if day ~= canyonDay then
			buildCanyons(day)
			Notifier.all("craters_shifted", nil, "pickup")
		end
	end
end

function WorldService.getPlots(): { Plot }
	return plots
end

-- Zone index at a world position; 0 = station side (not on the track).
function WorldService.zoneIndexAt(position: Vector3): number
	if position.Z > zoneStartZ[1] then
		return 0
	end
	for i = 1, #Zones.ZONES do
		if position.Z > zoneStartZ[i + 1] then
			return i
		end
	end
	return #Zones.ZONES
end

-- The walled playable area (XZ): stations deck + the whole track.
function WorldService.playBounds(): (number, number, number, number)
	return -trackHalfWidth, trackHalfWidth, zoneStartZ[#Zones.ZONES + 1], DECK_BACK_Z
end

-- Z of the gate at the start of zone i (the boundary with zone i-1).
function WorldService.gateZ(index: number): number
	return zoneStartZ[index]
end

-- Random spawn point in a zone. Returns the point and whether it is inside a
-- canyon (canyon spawns get a rarity boost).
function WorldService.randomPointInZone(index: number, rng: Random): (Vector3, boolean)
	local cells = canyonCells[index]
	if cells and #cells > 0 and rng:NextNumber() < Canyons.SPAWN_SHARE then
		local jitter = Canyons.CELL / 2 - 8
		local center = cells[rng:NextInteger(1, #cells)]
		return center + Vector3.new(
			rng:NextNumber(-jitter, jitter),
			0,
			rng:NextNumber(-jitter, jitter)
		),
			true
	end
	local halfWidth = if cells then Canyons.LANE_WIDTH / 2 - 8 else trackHalfWidth - 10
	local zMax = zoneStartZ[index] - 15
	local zMin = zoneStartZ[index + 1] + 15
	return Vector3.new(
		rng:NextNumber(-halfWidth, halfWidth),
		FLOOR_TOP + 2,
		rng:NextNumber(zMin, zMax)
	),
		false
end

function WorldService.isInPlot(plot: Plot, position: Vector3): boolean
	local offset = position - plot.center
	return math.abs(offset.X) <= PLOT_SIZE / 2
		and math.abs(offset.Z) <= PLOT_SIZE / 2
		and offset.Y >= -2
		and offset.Y <= 16
end

return WorldService

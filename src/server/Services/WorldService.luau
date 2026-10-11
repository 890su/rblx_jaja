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
local Remotes = require(Shared.Remotes)
local Theme = require(Shared.Theme)

export type Plot = {
	index: number,
	model: Model,
	spawn: CFrame,
	pedestals: { BasePart },
	collector: BasePart,
	center: Vector3,
}

local PLOT_SIZE = 60
local PLOT_GAP = 10
local PLOT_PITCH = PLOT_SIZE + PLOT_GAP
local PLOT_Z = 45 -- plot center Z
local FLOOR_TOP = 0.2 -- slightly above the default Baseplate to avoid z-fighting
local WALL_HEIGHT = 80
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

local function buildPlot(index: number, count: number, parent: Instance): Plot
	local x = (index - (count + 1) / 2) * PLOT_PITCH
	local center = Vector3.new(x, FLOOR_TOP, PLOT_Z)

	local model = Instance.new("Model")
	model.Name = `Plot{index}`

	local floor = part({
		Name = "Floor",
		Size = Vector3.new(PLOT_SIZE, 1, PLOT_SIZE),
		Position = center - Vector3.new(0, 0.5, 0),
		Color = Color3.fromRGB(45, 50, 70),
		Material = Enum.Material.Metal,
	}, model)
	model.PrimaryPart = floor

	local pedestals: { BasePart } = {}
	for slot = 1, PEDESTAL_SLOTS do
		local row = (slot - 1) // 4
		local col = (slot - 1) % 4
		local pedestal = part({
			Name = `Pedestal{slot}`,
			Size = Vector3.new(6, 2, 6),
			Position = center + Vector3.new((col - 1.5) * 12, 1, 8 + row * 12),
			Color = Color3.fromRGB(90, 95, 120),
			Material = Enum.Material.SmoothPlastic,
		}, model)
		pedestal:SetAttribute("Slot", slot)
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
	local collectorLabel = Instance.new("TextLabel")
	collectorLabel.Name = "Label"
	collectorLabel.Size = UDim2.fromScale(1, 1)
	collectorLabel.BackgroundTransparency = 1
	collectorLabel.TextScaled = true
	collectorLabel.Font = Enum.Font.FredokaOne
	collectorLabel.TextColor3 = Color3.fromRGB(255, 220, 90)
	collectorLabel.TextStrokeTransparency = 0.3
	collectorLabel.Text = ""
	collectorLabel.Parent = collectorGui
	collectorGui.Parent = collector

	local sign = part({
		Name = "Sign",
		Size = Vector3.new(16, 6, 1),
		Position = center + Vector3.new(0, 6, PLOT_SIZE / 2 - 2),
		Color = Color3.fromRGB(30, 30, 45),
	}, model)
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	local label = Instance.new("TextLabel")
	label.Name = "Owner"
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.TextScaled = true
	label.Font = Enum.Font.FredokaOne
	label.TextColor3 = Color3.new(1, 1, 1)
	label.Text = `Empty {Theme.BASE}`
	label.Parent = gui
	gui.Parent = sign

	model.Parent = parent
	return {
		index = index,
		model = model,
		spawn = CFrame.new(center + Vector3.new(0, 3, 20)) * CFrame.Angles(0, 0, 0),
		pedestals = pedestals,
		collector = collector,
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
		local shade = 1 - (i - 1) * 0.12
		part({
			Name = `Zone{i}`,
			Size = Vector3.new(trackHalfWidth * 2, 1, zone.lengthStuds),
			Position = Vector3.new(0, FLOOR_TOP - 0.5, z - zone.lengthStuds / 2),
			Color = Color3.fromRGB(120 * shade, 90 * shade, 70 * shade),
			Material = Enum.Material.Slate,
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
			gate:SetAttribute("SpeedGate", zone.speedGate)
			gate:SetAttribute("RebirthGate", zone.rebirthGate)
			CollectionService:AddTag(gate, "SpeedGate")

			local gui = Instance.new("SurfaceGui")
			gui.Face = Enum.NormalId.Back -- faces the station side (+Z)
			local label = Instance.new("TextLabel")
			label.Size = UDim2.fromScale(1, 1)
			label.BackgroundTransparency = 1
			label.TextScaled = true
			label.Font = Enum.Font.FredokaOne
			label.TextColor3 = Color3.new(1, 1, 1)
			local requirement = `{zone.speedGate} Speed`
			if zone.rebirthGate > 0 then
				requirement ..= ` + Rebirth {zone.rebirthGate}`
			end
			label.Text = `{Theme.ZONE_NAMES[i] or `Zone {i}`}  ·  {requirement}`
			label.Parent = gui
			gui.Parent = gate
		end
		z -= zone.lengthStuds
	end
	zoneStartZ[#Zones.ZONES + 1] = z

	for side = -1, 1, 2 do
		part({
			Name = "SideWall",
			Size = Vector3.new(2, WALL_HEIGHT, -z),
			Position = Vector3.new(side * (trackHalfWidth + 1), WALL_HEIGHT / 2, z / 2),
			Transparency = 1,
		}, folder)
	end
	part({
		Name = "EndWall",
		Size = Vector3.new(trackHalfWidth * 2, WALL_HEIGHT, 2),
		Position = Vector3.new(0, WALL_HEIGHT / 2, z - 1),
		Transparency = 1,
	}, folder)

	folder.Parent = parent
end

local function canyonWall(cframe: CFrame, size: Vector3, parent: Instance)
	part({
		Name = "CanyonWall",
		Size = size,
		CFrame = cframe,
		Color = Color3.fromRGB(70, 55, 50),
		Material = Enum.Material.Basalt,
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
					parent
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
					parent
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
end

local function currentDay(): number
	return math.floor(os.time() / Canyons.RESEED_PERIOD)
end

function WorldService.init()
	world = Instance.new("Folder")
	world.Name = "World"
	local plotFolder = Instance.new("Folder")
	plotFolder.Name = "Plots"
	for i = 1, Economy.SERVER_SIZE do
		plots[i] = buildPlot(i, Economy.SERVER_SIZE, plotFolder)
	end
	plotFolder.Parent = world
	buildTrack(world)
	buildCanyons(currentDay())
	world.Parent = workspace
end

function WorldService.start()
	while true do
		task.wait(30)
		local day = currentDay()
		if day ~= canyonDay then
			buildCanyons(day)
			Remotes.event("Notify")
				:FireAllClients("The craters shifted! New canyon paths today", "pickup")
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
	return math.abs(offset.X) <= PLOT_SIZE / 2 and math.abs(offset.Z) <= PLOT_SIZE / 2
end

return WorldService

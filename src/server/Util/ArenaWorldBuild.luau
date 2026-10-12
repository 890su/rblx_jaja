--!strict
-- Void Run corridor markings across the whole field zone: eight lanes (one
-- in front of each station) separated by faint neon lines, an orange start
-- line at the crater end and a green finish line at the station end.
-- Purely visual and non-colliding; ArenaService enforces the lane bounds.
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Arena = require(Shared.Config.Arena)
local Economy = require(Shared.Config.Economy)
local Build = {}

local function part(
	parent: Instance,
	name: string,
	position: Vector3,
	size: Vector3,
	color: Color3,
	transparency: number?
): Part
	local p = Instance.new("Part")
	p.Name, p.Position, p.Size = name, position, size
	p.Anchored, p.CanCollide, p.CanTouch, p.CanQuery = true, false, false, false
	p.Material = Enum.Material.Neon
	p.Color = color
	p.Transparency = transparency or 0
	p.CastShadow = false
	p.Parent = parent
	return p
end

local function sign(parent: Instance, position: Vector3, text: string, color: Color3)
	local board =
		part(parent, "Sign", position, Vector3.new(30, 6, 0.5), Color3.fromRGB(25, 28, 40))
	board.Material = Enum.Material.Metal
	local gui = Instance.new("SurfaceGui")
	gui.Face, gui.LightInfluence = Enum.NormalId.Front, 0
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency, label.Size = 1, UDim2.fromScale(1, 1)
	label.Text, label.TextColor3, label.TextScaled, label.Font =
		text, color, true, Enum.Font.FredokaOne
	label.Parent, gui.Parent = gui, board -- Front (-Z) faces runners coming from the crater
end

function Build.build(world: Instance, zoneStartZ: { number })
	local folder = Instance.new("Folder")
	folder.Name = "VoidRun"
	local zMax = zoneStartZ[Arena.FIELD_ZONE]
	local zMin = zoneStartZ[Arena.FIELD_ZONE + 1]
	local length = zMax - zMin
	local middle = (zMax + zMin) / 2
	local count = Economy.SERVER_SIZE
	local halfTrack = count * Arena.LANE_WIDTH / 2
	for index = 1, count - 1 do
		part(
			folder,
			"LaneLine",
			Vector3.new(-halfTrack + index * Arena.LANE_WIDTH, 0.3, middle),
			Vector3.new(0.3, 0.08, length),
			Color3.fromRGB(150, 120, 255),
			0.55
		)
	end
	part(
		folder,
		"StartLine",
		Vector3.new(0, 0.32, zMin + 1),
		Vector3.new(halfTrack * 2, 0.1, 1.2),
		Color3.fromRGB(255, 135, 60)
	)
	part(
		folder,
		"FinishLine",
		Vector3.new(0, 0.32, zMax - 1),
		Vector3.new(halfTrack * 2, 0.1, 1.2),
		Color3.fromRGB(90, 255, 150)
	)
	for index = 1, count do
		local x = (index - (count + 1) / 2) * Arena.LANE_WIDTH
		sign(folder, Vector3.new(x, 16, zMin + 2), "VOID RUN", Color3.fromRGB(255, 160, 100))
	end
	folder.Parent = world
end

return Build

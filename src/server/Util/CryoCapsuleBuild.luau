--!strict
-- The original PedestalN part stays the interaction/data anchor. Geometry is
-- a child model, so all existing slot, replacement and stealing code keeps
-- addressing the same part directly under its plot.
local CollectionService = game:GetService("CollectionService")
local Build = {}
local STEEL = Color3.fromRGB(49, 61, 78)
local DARK = Color3.fromRGB(18, 25, 36)
local CYAN = Color3.fromRGB(95, 225, 255)
local DIM = Color3.fromRGB(47, 65, 82)

local function part(
	parent: Instance,
	name: string,
	cf: CFrame,
	size: Vector3,
	color: Color3,
	material: Enum.Material
): Part
	local p = Instance.new("Part")
	p.Name, p.CFrame, p.Size, p.Color, p.Material = name, cf, size, color, material
	p.Anchored, p.CanCollide, p.CanTouch, p.CanQuery = true, false, false, false
	p.TopSurface, p.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

local function cylinder(
	parent: Instance,
	name: string,
	pos: Vector3,
	diameter: number,
	height: number,
	color: Color3,
	material: Enum.Material
): Part
	local p = part(
		parent,
		name,
		CFrame.new(pos) * CFrame.Angles(0, 0, math.pi / 2),
		Vector3.new(height, diameter, diameter),
		color,
		material
	)
	p.Shape = Enum.PartType.Cylinder
	return p
end

local function ring(parent: Instance, center: Vector3)
	local radius, segments = 3.14, 16
	for index = 1, segments do
		local angle = (index - 0.5) * math.pi * 2 / segments
		local pos = center + Vector3.new(math.cos(angle), 0, math.sin(angle)) * radius
		local p = part(
			parent,
			"LightRing",
			CFrame.new(pos) * CFrame.Angles(0, -angle, 0),
			Vector3.new(0.16, 0.12, 2 * radius * math.tan(math.pi / segments) - 0.03),
			CYAN,
			Enum.Material.Neon
		)
		p:SetAttribute("CapsuleGlow", true)
		p.CastShadow = false
	end
end

local function text(
	gui: SurfaceGui,
	name: string,
	value: string,
	y: number,
	height: number,
	color: Color3,
	autoLocalize: boolean
): TextLabel
	local label = Instance.new("TextLabel")
	label.Name, label.Text = name, value
	label.Position, label.Size = UDim2.fromScale(0.06, y), UDim2.fromScale(0.88, height)
	label.BackgroundTransparency, label.TextScaled = 1, true
	label.TextColor3, label.Font = color, Enum.Font.GothamMedium
	label.AutoLocalize = autoLocalize
	label.Parent = gui
	return label
end

local function screen(parent: Part, name: string, pixels: Vector2): SurfaceGui
	local gui = Instance.new("SurfaceGui")
	gui.Name, gui.Face, gui.LightInfluence = name, Enum.NormalId.Front, 0
	gui.SizingMode, gui.CanvasSize = Enum.SurfaceGuiSizingMode.FixedSize, pixels
	gui.Parent = parent
	return gui
end

function Build.create(parent: Instance, position: Vector3, slot: number): BasePart
	local pedestal = part(
		parent,
		`Pedestal{slot}`,
		CFrame.new(position),
		Vector3.new(6, 2, 6),
		DARK,
		Enum.Material.SmoothPlastic
	)
	pedestal.Transparency = 1
	pedestal:SetAttribute("Slot", slot)
	pedestal:SetAttribute("DisplayFloorOffset", 0.72)
	pedestal:SetAttribute("CryoCapsule", true)
	local model = Instance.new("Model")
	model.Name = "CryoCapsule"
	local floor = position - Vector3.new(0, 1, 0)
	local foot =
		cylinder(model, "Foot", floor + Vector3.new(0, 0.3, 0), 7, 0.6, DARK, Enum.Material.Metal)
	foot.CanCollide, foot.CanQuery = true, true
	cylinder(model, "Base", floor + Vector3.new(0, 1.0, 0), 6.6, 0.8, STEEL, Enum.Material.Metal)
	cylinder(
		model,
		"DisplayDeck",
		floor + Vector3.new(0, 1.57, 0),
		5.9,
		0.16,
		DARK,
		Enum.Material.Metal
	)
	local deck = cylinder(
		model,
		"InteriorGlow",
		floor + Vector3.new(0, 1.67, 0),
		5.4,
		0.05,
		CYAN,
		Enum.Material.Neon
	)
	deck.Transparency = 0.7
	deck:SetAttribute("CapsuleGlow", true)
	local light = Instance.new("PointLight")
	light.Name, light.Color, light.Range, light.Brightness = "InteriorLight", CYAN, 8, 0.6
	light.Enabled, light.Shadows = false, false
	light.Parent = deck
	local glass = cylinder(
		model,
		"Glass",
		floor + Vector3.new(0, 4.86, 0),
		6.12,
		6.36,
		Color3.fromRGB(155, 225, 244),
		Enum.Material.Glass
	)
	glass.Transparency, glass.Reflectance = 0.86, 0.08
	glass.CanCollide, glass.CanQuery, glass.CastShadow = true, true, false
	local dome = part(
		model,
		"GlassDome",
		CFrame.new(floor + Vector3.new(0, 8.15, 0)),
		Vector3.new(6.12, 2.5, 6.12),
		glass.Color,
		Enum.Material.Glass
	)
	dome.Shape, dome.Transparency, dome.Reflectance, dome.CastShadow =
		Enum.PartType.Ball, 0.86, 0.08, false
	cylinder(
		model,
		"UpperCollar",
		floor + Vector3.new(0, 8.1, 0),
		6.65,
		0.3,
		STEEL,
		Enum.Material.Metal
	)
	cylinder(model, "Crown", floor + Vector3.new(0, 9.25, 0), 4.55, 0.3, DARK, Enum.Material.Metal)
	ring(model, floor + Vector3.new(0, 1.43, 0))
	ring(model, floor + Vector3.new(0, 8.25, 0))
	for side = -1, 1, 2 do
		part(
			model,
			"Support",
			CFrame.new(floor + Vector3.new(side * 3.16, 4.85, 0)),
			Vector3.new(0.38, 6.4, 0.65),
			STEEL,
			Enum.Material.Metal
		)
		local strip = part(
			model,
			"CoolingStrip",
			CFrame.new(floor + Vector3.new(side * 3.18, 4.85, -0.36)),
			Vector3.new(0.12, 5.5, 0.08),
			CYAN,
			Enum.Material.Neon
		)
		strip:SetAttribute("CapsuleGlow", true)
		part(
			model,
			"Vent",
			CFrame.new(floor + Vector3.new(side * 2.55, 0.96, -2.02))
				* CFrame.Angles(0, side * math.rad(35), 0),
			Vector3.new(0.6, 0.4, 0.14),
			DARK,
			Enum.Material.Metal
		)
	end
	part(
		model,
		"BackSpine",
		CFrame.new(floor + Vector3.new(0, 4.9, 3.02)),
		Vector3.new(0.5, 6.45, 0.25),
		STEEL,
		Enum.Material.Metal
	)
	-- Rear liner separates the specimen from the next row of glass capsules.
	part(
		model,
		"RearLiner",
		CFrame.new(floor + Vector3.new(0, 4.85, 2.7)),
		Vector3.new(4.2, 6.05, 0.12),
		DARK,
		Enum.Material.Metal
	)
	for side = -1, 1, 2 do
		part(
			model,
			"CoolingChannel",
			CFrame.new(floor + Vector3.new(side * 0.85, 4.8, 2.59)),
			Vector3.new(0.08, 5.5, 0.05),
			STEEL,
			Enum.Material.Metal
		)
	end
	local panel = part(
		model,
		"ControlPanel",
		CFrame.new(floor + Vector3.new(0, 1.01, -3.23)),
		Vector3.new(4.55, 1.5, 0.25),
		DARK,
		Enum.Material.Metal
	)
	local gui = screen(panel, "Info", Vector2.new(480, 160))
	text(gui, "Status", "OFFLINE", 0.03, 0.2, CYAN, true)
	text(gui, "Label", "", 0.3, 0.45, Color3.fromRGB(230, 242, 255), true)
	local track = Instance.new("Frame")
	track.Name, track.Position, track.Size =
		"ProgressTrack", UDim2.fromScale(0.07, 0.92), UDim2.fromScale(0.86, 0.035)
	track.BackgroundColor3, track.BorderSizePixel = Color3.fromRGB(45, 60, 76), 0
	track.Parent = gui
	local progress = Instance.new("Frame")
	progress.Name, progress.Size, progress.BackgroundColor3, progress.BorderSizePixel =
		"Progress", UDim2.fromScale(0, 1), CYAN, 0
	progress.Parent = track
	local plate = part(
		model,
		"SlotPlate",
		CFrame.new(floor + Vector3.new(0, 8.52, -3.36)),
		Vector3.new(4.8, 0.95, 0.22),
		DARK,
		Enum.Material.Metal
	)
	local topValue =
		text(screen(plate, "Slot", Vector2.new(480, 90)), "Value", "", 0.08, 0.82, CYAN, false)
	topValue.Font = Enum.Font.GothamBold
	model.PrimaryPart = foot
	model.Parent = pedestal
	CollectionService:AddTag(pedestal, "CryoCapsule")
	return pedestal
end

function Build.info(pedestal: BasePart): SurfaceGui?
	local model = pedestal:FindFirstChild("CryoCapsule")
	local panel = model and model:FindFirstChild("ControlPanel")
	return panel and panel:FindFirstChild("Info") :: SurfaceGui?
end

function Build.topValue(pedestal: BasePart): TextLabel?
	local model = pedestal:FindFirstChild("CryoCapsule")
	local plate = model and model:FindFirstChild("SlotPlate")
	local gui = plate and plate:FindFirstChild("Slot")
	return gui and gui:FindFirstChild("Value") :: TextLabel?
end

function Build.update(
	pedestal: BasePart,
	unlocked: boolean,
	color: Color3,
	status: string,
	vip: boolean,
	progressAmount: number
)
	local gui = Build.info(pedestal)
	local model = pedestal:FindFirstChild("CryoCapsule")
	if not gui or not model then
		return
	end
	local statusLabel = gui:FindFirstChild("Status") :: TextLabel
	statusLabel.Text = status
	local track = gui:FindFirstChild("ProgressTrack") :: Frame
	local progress = track:FindFirstChild("Progress") :: Frame
	progress.Size = UDim2.fromScale(math.clamp(progressAmount, 0, 1), 1)
	local key = `{unlocked}|{color}|{status}|{vip}`
	if pedestal:GetAttribute("CapsuleViewKey") == key then
		return
	end
	pedestal:SetAttribute("CapsuleViewKey", key)
	local glow = if unlocked then color else DIM
	statusLabel.TextColor3, progress.BackgroundColor3 = glow, glow
	local topValue = Build.topValue(pedestal)
	if topValue then
		topValue.TextColor3 = if status == "ACTIVE" then Color3.fromRGB(255, 232, 145) else glow
	end
	for _, p in model:GetDescendants() do
		if p:IsA("PointLight") then
			p.Color = glow
			p.Enabled = unlocked and (status == "ACTIVE" or status == "Hatching")
		elseif p:IsA("BasePart") then
			if p:GetAttribute("CapsuleGlow") then
				p.Color = glow
			elseif p.Name == "Glass" or p.Name == "GlassDome" then
				p.Transparency = if unlocked then 0.86 else 0.93
			elseif p.Name == "UpperCollar" then
				p.Color = if vip then Color3.fromRGB(153, 132, 82) else STEEL
			end
		end
	end
end

return Build

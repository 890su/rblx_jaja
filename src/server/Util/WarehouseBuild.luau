--!strict
-- A parcel locker in the left corner by the station sign. The server
-- owns the interaction anchor; private creature previews are client-only.
local Shared = game:GetService("ReplicatedStorage").Shared
local Config = require(Shared.Config.Warehouse)
local Look = require(Shared.Theme).WAREHOUSE
local CollectionService = game:GetService("CollectionService")
local Build = {}

function Build.create(parent: Model, center: Vector3): BasePart
	local model = Instance.new("Model")
	model.Name = "Warehouse"
	local origin = CFrame.new(center + Config.offset) * CFrame.Angles(0, math.rad(Config.yaw), 0)
	local function part(
		name: string,
		at: Vector3,
		size: Vector3,
		color: Color3,
		neon: boolean?
	): Part
		local p = Instance.new("Part")
		p.Name, p.CFrame, p.Size, p.Color = name, origin * CFrame.new(at), size, color
		p.Material = if neon then Enum.Material.Neon else Enum.Material.Metal
		p.Anchored, p.CanTouch, p.CanQuery, p.CanCollide = true, false, false, false
		p.TopSurface, p.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
		p.Parent = model
		return p
	end
	local body = part("Body", Vector3.new(0, 4.7, 0), Vector3.new(14, 9, 5), Look.body)
	body.CanCollide, body.CanQuery = true, true
	model.PrimaryPart = body
	part("Plinth", Vector3.new(0, 0.35, 0), Vector3.new(14.6, 0.7, 5.6), Look.screen)
	part("Roof", Vector3.new(0, 9.3, 0), Vector3.new(14.6, 0.3, 5.6), Look.door)
	part(
		"HeaderLight",
		Vector3.new(0, 8.7, -2.57),
		Vector3.new(13.1, 0.12, 0.12),
		Look.accent,
		true
	)
	for index = 1, 6 do
		local column = (index - 1) % 2
		local row = (index - 1) // 2
		local x, y = -4.9 + column * 3.3, 2 + row * 2.35
		part(`Door{index}`, Vector3.new(x, y, -2.55), Vector3.new(3.05, 2.14, 0.18), Look.door)
		part(
			`Handle{index}`,
			Vector3.new(x + 1.08, y, -2.69),
			Vector3.new(0.12, 0.65, 0.12),
			Look.muted
		)
		part(
			`Status{index}`,
			Vector3.new(x - 1.11, y + 0.76, -2.69),
			Vector3.new(0.35, 0.1, 0.1),
			Look.muted,
			true
		)
		if column == 0 then
			local window = part(
				`Window{row + 1}`,
				Vector3.new(x, y, -2.69),
				Vector3.new(2.25, 1.45, 0.06),
				Look.screen
			)
			window.Transparency = 0.35
			local anchor = Instance.new("Attachment")
			anchor.Name = `Preview{row + 1}`
			anchor.CFrame = body.CFrame:ToObjectSpace(origin * CFrame.new(x, y, -3.5))
			anchor.Parent = body
		end
	end
	local screen =
		part("Screen", Vector3.new(4.1, 5.8, -2.64), Vector3.new(3.6, 4.7, 0.2), Look.screen)
	local gui = Instance.new("SurfaceGui")
	gui.Name, gui.Face, gui.LightInfluence = "Display", Enum.NormalId.Front, 0
	gui.SizingMode, gui.PixelsPerStud = Enum.SurfaceGuiSizingMode.PixelsPerStud, 60
	gui.Parent = screen
	for _, spec in
		{
			{ name = "Title", text = "Storage", y = 0.08, h = 0.2 },
			{ name = "Count", text = "0", y = 0.32, h = 0.3 },
			{ name = "Action", text = "Manage creatures", y = 0.72, h = 0.16 },
		}
	do
		local label = Instance.new("TextLabel")
		label.Name, label.Text = spec.name, spec.text
		label.Position, label.Size = UDim2.fromScale(0.08, spec.y), UDim2.fromScale(0.84, spec.h)
		label.BackgroundTransparency, label.TextScaled = 1, true
		label.Font, label.TextColor3 = Enum.Font.GothamBold, Look.accent
		label.AutoLocalize = spec.name ~= "Count"
		label.Parent = gui
	end
	part("PickupBay", Vector3.new(4.1, 1.7, -2.6), Vector3.new(3.6, 1.8, 0.2), Look.screen)
	part(
		"PickupLight",
		Vector3.new(4.1, 2.6, -2.75),
		Vector3.new(3.4, 0.08, 0.1),
		Look.accent,
		true
	)
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name, prompt.ActionText, prompt.ObjectText =
		"WarehousePrompt", "Manage creatures", "Storage"
	prompt.MaxActivationDistance, prompt.HoldDuration = Config.promptDistance, 0.15
	prompt.RequiresLineOfSight, prompt.Enabled = false, true
	prompt.Parent = screen
	CollectionService:AddTag(prompt, "WarehousePrompt")
	model.Parent = parent
	return screen
end

function Build.refresh(screen: BasePart, count: number, occupied: boolean)
	local display = screen:FindFirstChild("Display")
	local label = display and display:FindFirstChild("Count")
	if label and label:IsA("TextLabel") then
		label.Text = tostring(count)
	end
	local prompt = screen:FindFirstChild("WarehousePrompt")
	if prompt and prompt:IsA("ProximityPrompt") then
		prompt:SetAttribute("OccupiedPlot", occupied)
	end
end

return Build

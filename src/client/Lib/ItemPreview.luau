--!strict
-- Static portraits of the real roster. No render loops, scripts or physics.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ItemPreview = {}
local function frameCamera(view: ViewportFrame)
	local camera = view.CurrentCamera
	local radius = view:GetAttribute("SubjectRadius")
	if not camera or typeof(radius) ~= "number" then
		return
	end
	local aspect = view.AbsoluteSize.X / math.max(1, view.AbsoluteSize.Y)
	local vertical = math.rad(camera.FieldOfView / 2)
	local halfFov = math.min(vertical, math.atan(math.tan(vertical) * math.max(0.1, aspect)))
	local distance = math.max(2, radius / math.sin(halfFov))
	camera.CFrame = CFrame.lookAt(Vector3.new(0.8, 0.45, 1).Unit * distance, Vector3.zero)
end
function ItemPreview.new(parent: Instance, position: UDim2, size: UDim2): ViewportFrame
	local view = Instance.new("ViewportFrame")
	view.Name, view.BackgroundTransparency = "Preview", 1
	view.Position, view.Size = position, size
	view.Ambient, view.LightColor = Color3.new(0.8, 0.8, 0.8), Color3.new(1, 1, 1)
	view.LightDirection = Vector3.new(-1, -1, -1)
	view.Parent = parent
	view:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		frameCamera(view)
	end)
	return view
end
local function icon(key: string): Model
	local model = Instance.new("Model")
	local function part(
		name: string,
		size: Vector3,
		position: Vector3,
		color: Color3,
		shape: Enum.PartType?
	)
		local p = Instance.new("Part")
		p.Name, p.Size, p.Position, p.Color = name, size, position, color
		p.Shape, p.Material, p.Anchored =
			shape or Enum.PartType.Block, Enum.Material.SmoothPlastic, true
		p.Parent = model
		return p
	end
	local cyan, gold = Color3.fromRGB(75, 210, 255), Color3.fromRGB(255, 195, 50)
	if key == "treadmill" or key == "training" or key == "Speed2x" then
		part("Belt", Vector3.new(5, 0.4, 8), Vector3.zero, Color3.fromRGB(25, 30, 45))
		for _, x in { -3, 3 } do
			part("Rail", Vector3.new(0.4, 0.7, 8), Vector3.new(x, 0, 0), cyan)
			part("Post", Vector3.new(0.4, 4, 0.4), Vector3.new(x, 2, -3), cyan)
		end
		part("Console", Vector3.new(5, 1, 1), Vector3.new(0, 4, -3), cyan)
		for z = -2, 2, 2 do
			part("Stripe", Vector3.new(4.4, 0.1, 0.35), Vector3.new(0, 0.3, z), gold)
		end
	elseif key == "warehouse" then
		part("Locker", Vector3.new(6, 5, 2), Vector3.zero, Color3.fromRGB(31, 45, 62))
		for y = -1, 1 do
			for x = -1, 0 do
				part("Door", Vector3.new(1.5, 1.35, 0.2), Vector3.new(x * 1.8, y * 1.55, 1.1), cyan)
			end
		end
		part("Screen", Vector3.new(1.1, 2.8, 0.2), Vector3.new(2, 0, 1.1), gold)
	elseif key == "pedestal" or key == "Expansion" then
		part("Base", Vector3.new(5, 1, 5), Vector3.zero, cyan)
		part("Capsule", Vector3.new(3, 4, 3), Vector3.new(0, 2.5, 0), gold, Enum.PartType.Ball)
	elseif key == "VIP" then
		part("Crown", Vector3.new(5, 1, 3), Vector3.zero, gold)
		for x = -2, 2, 2 do
			part("Point", Vector3.new(0.8, 2, 0.8), Vector3.new(x, 1.4, 0), gold)
		end
	elseif key == "Coins2x" or key == "OfflinePlus" then
		for y = 0, 3 do
			part("Coin", Vector3.new(4, 0.5, 4), Vector3.new(0, y * 0.6, 0), gold)
		end
	elseif key == "Shield15" then
		part("Shield", Vector3.new(4, 5, 1), Vector3.zero, cyan, Enum.PartType.Ball)
		part("Core", Vector3.new(1, 2.6, 1.3), Vector3.zero, gold)
	else
		part("Crate", Vector3.new(4, 3.5, 4), Vector3.zero, Color3.fromRGB(125, 75, 200))
		part("Ribbon", Vector3.new(4.2, 0.5, 4.2), Vector3.new(0, 1, 0), cyan)
		part("Meteor", Vector3.new(2.5, 2.5, 2.5), Vector3.new(0, 2.5, 0), gold, Enum.PartType.Ball)
	end
	return model
end
function ItemPreview.set(view: ViewportFrame, key: string, silhouette: boolean?)
	local stamp = key .. (if silhouette then ":locked" else ":known")
	if view:GetAttribute("PreviewKey") == stamp then
		return
	end
	view:SetAttribute("PreviewKey", stamp)
	view:ClearAllChildren()
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local creatures = assets and assets:FindFirstChild("Creatures")
	local source = creatures and creatures:FindFirstChild(key)
	local model = if source and source:IsA("Model") then source:Clone() else icon(key)
	model.Name = "Subject"
	for _, node in model:GetDescendants() do
		if
			node:IsA("BaseScript")
			or node:IsA("ModuleScript")
			or node:IsA("ParticleEmitter")
			or node:IsA("Light")
			or node:IsA("Trail")
			or node:IsA("Beam")
		then
			node:Destroy()
		elseif node:IsA("BasePart") then
			node.Anchored, node.CanCollide, node.CanTouch, node.CanQuery = true, false, false, false
			if silhouette then
				node.Color, node.Material, node.MaterialVariant =
					Color3.new(0.025, 0.035, 0.055), Enum.Material.SmoothPlastic, ""
				if node:IsA("MeshPart") then
					node.TextureID = ""
				end
			end
		elseif silhouette then
			if node:IsA("SurfaceAppearance") or node:IsA("Decal") then
				node:Destroy()
			elseif node:IsA("SpecialMesh") then
				node.TextureId, node.VertexColor = "", Vector3.new(0.025, 0.035, 0.055)
			end
		end
	end
	local box, size = model:GetBoundingBox()
	model:PivotTo(model:GetPivot() - box.Position)
	local radius = size.Magnitude / 2
	local camera = Instance.new("Camera")
	camera.FieldOfView = 35
	view:SetAttribute("SubjectRadius", radius)
	camera.Parent, view.CurrentCamera = view, camera
	model.Parent = view
	frameCamera(view)
end
return ItemPreview

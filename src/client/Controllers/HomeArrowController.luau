--!strict
-- While carrying something, a 3D arrow above the character points to the
-- player's own station so canyon routes are a choice, never a way to get lost.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer

local HEIGHT = 9.5 -- above the carried meteor
local ARM_ANGLE = math.rad(35)
local COLOR = Color3.fromRGB(120, 255, 160)

local HomeArrowController = {}

local arrow: Model

local function build(): Model
	local model = Instance.new("Model")
	model.Name = "HomeArrow"
	local shaft = Instance.new("Part")
	shaft.Name = "Shaft"
	shaft.Size = Vector3.new(0.6, 0.3, 3)
	local left = Instance.new("Part")
	left.Name = "Left"
	left.Size = Vector3.new(0.6, 0.3, 1.8)
	local right = left:Clone()
	right.Name = "Right"
	for _, p in { shaft, left, right } :: { BasePart } do
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.CastShadow = false
		p.Material = Enum.Material.Neon
		p.Color = COLOR
		p.Parent = model
	end
	model.PrimaryPart = shaft
	return model
end

local function findHome(): Vector3?
	-- Set by StationService; plot parts may be streamed out when far away.
	return player:GetAttribute("HomePosition") :: Vector3?
end

local function update()
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local carrying = player:GetAttribute("Carrying") ~= nil
	local homePosition = findHome()
	if not root or not carrying or not homePosition then
		arrow.Parent = nil
		return
	end
	local flat = Vector3.new(homePosition.X - root.Position.X, 0, homePosition.Z - root.Position.Z)
	if flat.Magnitude < 1 then
		arrow.Parent = nil
		return
	end
	local origin = root.Position + Vector3.new(0, HEIGHT, 0)
	local look = CFrame.lookAt(origin, origin + flat.Unit)
	local shaft = arrow:FindFirstChild("Shaft") :: BasePart
	local left = arrow:FindFirstChild("Left") :: BasePart
	local right = arrow:FindFirstChild("Right") :: BasePart
	shaft.CFrame = look
	-- Chevron: two arms meeting at the tip, angled back from it.
	local tipPoint = look * CFrame.new(0, 0, -1.8)
	left.CFrame = tipPoint * CFrame.Angles(0, ARM_ANGLE, 0) * CFrame.new(0, 0, 0.8)
	right.CFrame = tipPoint * CFrame.Angles(0, -ARM_ANGLE, 0) * CFrame.new(0, 0, 0.8)
	arrow.Parent = workspace
end

function HomeArrowController.init()
	arrow = build()
end

function HomeArrowController.start()
	RunService.RenderStepped:Connect(update)
end

return HomeArrowController

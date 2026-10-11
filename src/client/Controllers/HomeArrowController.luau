--!strict
-- While carrying something, a 3D arrow above the character points to the
-- player's own station so canyon routes are a choice, never a way to get lost.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer

local HEIGHT = 7
local COLOR = Color3.fromRGB(120, 255, 160)

local HomeArrowController = {}

local arrow: Model
local homePosition: Vector3?

local function build(): Model
	local model = Instance.new("Model")
	model.Name = "HomeArrow"
	local shaft = Instance.new("Part")
	shaft.Name = "Shaft"
	shaft.Size = Vector3.new(0.6, 0.3, 3)
	local tip = Instance.new("WedgePart")
	tip.Name = "Tip"
	tip.Size = Vector3.new(1.8, 0.3, 1.6)
	for _, p in { shaft, tip } :: { BasePart } do
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
	local plots = workspace:FindFirstChild("World") and workspace.World:FindFirstChild("Plots")
	if not plots then
		return nil
	end
	for _, plot in plots:GetChildren() do
		if plot:GetAttribute("OwnerUserId") == player.UserId then
			local floor = plot:FindFirstChild("Floor") :: BasePart?
			return floor and floor.Position
		end
	end
	return nil
end

local function update()
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local carrying = player:GetAttribute("Carrying") ~= nil
	homePosition = homePosition or findHome()
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
	local tip = arrow:FindFirstChild("Tip") :: BasePart
	shaft.CFrame = look
	-- WedgePart slopes toward -Z; rotate so the point faces forward.
	tip.CFrame = look
		* CFrame.new(0, 0, -2.3)
		* CFrame.Angles(0, math.pi, 0)
		* CFrame.Angles(0, 0, math.pi / 2)
	arrow.Parent = workspace
end

function HomeArrowController.init()
	arrow = build()
end

function HomeArrowController.start()
	RunService.RenderStepped:Connect(update)
end

return HomeArrowController

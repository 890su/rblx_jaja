--!strict
-- Guards' vision drawn on the ground, locally, from each guard's pivot (the
-- server only replicates the drone's CFrame and State/Spotting attributes):
-- a sector in front (VISION_RANGE, ±VISION_HALF_ANGLE) and a faint hearing
-- circle around it. Blue while patrolling, red while a carrier is seen,
-- yellow while the guard is searching; hidden during a chase and the Void Run.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config.Snatchers)

local player = Players.LocalPlayer

local DRAW_DISTANCE = 260
local SLICES = 6
local GROUND_Y = 0.3
local THICKNESS = 0.06
local COLORS = {
	patrol = Color3.fromRGB(80, 180, 255),
	spotting = Color3.fromRGB(255, 55, 75),
	search = Color3.fromRGB(255, 205, 65),
}

type View = { wedges: { WedgePart }, ring: Part }

local GuardVisionController = {}

local views: { [Model]: View } = {}
local folder: Folder

local function newWedge(): WedgePart
	local wedge = Instance.new("WedgePart")
	wedge.Anchored, wedge.CanCollide, wedge.CanQuery, wedge.CanTouch = true, false, false, false
	wedge.Material = Enum.Material.Neon
	wedge.CastShadow = false
	wedge.Transparency = 0.62
	wedge.Parent = folder
	return wedge
end

local function newView(): View
	local wedges = {}
	for _ = 1, SLICES * 2 do
		table.insert(wedges, newWedge())
	end
	local ring = Instance.new("Part")
	ring.Shape = Enum.PartType.Cylinder
	ring.Anchored, ring.CanCollide, ring.CanQuery, ring.CanTouch = true, false, false, false
	ring.Material = Enum.Material.Neon
	ring.CastShadow = false
	ring.Transparency = 0.82
	ring.Size = Vector3.new(THICKNESS, Config.HEARING_RADIUS * 2, Config.HEARING_RADIUS * 2)
	ring.Parent = folder
	return { wedges = wedges, ring = ring }
end

-- Flat triangle a-b-c from two wedges (the classic two-WedgePart method).
local function triangle(a: Vector3, b: Vector3, c: Vector3, w1: WedgePart, w2: WedgePart)
	local ab, ac, bc = b - a, c - a, c - b
	local abd, acd, bcd = ab:Dot(ab), ac:Dot(ac), bc:Dot(bc)
	if abd > acd and abd > bcd then
		c, a = a, c
	elseif acd > bcd and acd > abd then
		a, b = b, a
	end
	ab, ac, bc = b - a, c - a, c - b
	local right = ac:Cross(ab).Unit
	local up = bc:Cross(right).Unit
	local back = bc.Unit
	local height = math.abs(ab:Dot(up))
	w1.Size = Vector3.new(THICKNESS, height, math.abs(ab:Dot(back)))
	w1.CFrame = CFrame.fromMatrix((a + b) / 2, right, up, back)
	w2.Size = Vector3.new(THICKNESS, height, math.abs(ac:Dot(back)))
	w2.CFrame = CFrame.fromMatrix((a + c) / 2, -right, up, -back)
end

local function draw(view: View, pivot: CFrame, color: Color3)
	local look = Vector3.new(pivot.LookVector.X, 0, pivot.LookVector.Z).Unit
	local origin = Vector3.new(pivot.Position.X, GROUND_Y, pivot.Position.Z)
	local yaw = math.atan2(look.Z, look.X)
	local half = Config.VISION_HALF_ANGLE
	local range = Config.VISION_RANGE
	local function edge(angle: number): Vector3
		return origin + Vector3.new(math.cos(angle), 0, math.sin(angle)) * range
	end
	for i = 1, SLICES do
		local a0 = yaw - half + (i - 1) * 2 * half / SLICES
		local a1 = yaw - half + i * 2 * half / SLICES
		local w1, w2 = view.wedges[i * 2 - 1], view.wedges[i * 2]
		triangle(origin, edge(a0), edge(a1), w1, w2)
		w1.Color, w2.Color = color, color
	end
	view.ring.CFrame = CFrame.new(origin) * CFrame.Angles(0, 0, math.rad(90))
	view.ring.Color = color
end

local function destroy(view: View)
	for _, wedge in view.wedges do
		wedge:Destroy()
	end
	view.ring:Destroy()
end

local function update()
	local camera = workspace.CurrentCamera
	local snatchers = workspace:FindFirstChild("Snatchers")
	local seen: { [Model]: boolean } = {}
	local inRun = player:GetAttribute("ArenaActive") == true
	if snatchers and camera and not inRun then
		local eye = camera.CFrame.Position
		for _, model in snatchers:GetChildren() do
			if not model:IsA("Model") or model:GetAttribute("Kind") ~= "drone" then
				continue
			end
			local phase = model:GetAttribute("State")
			if phase ~= "guard" and phase ~= "alert" then
				continue
			end
			local pivot = model:GetPivot()
			if (pivot.Position - eye).Magnitude > DRAW_DISTANCE then
				continue
			end
			local look = Vector3.new(pivot.LookVector.X, 0, pivot.LookVector.Z)
			if look.Magnitude < 1e-3 then
				continue
			end
			seen[model] = true
			local view = views[model]
			if not view then
				view = newView()
				views[model] = view
			end
			draw(
				view,
				pivot,
				if model:GetAttribute("Spotting") == true
					then COLORS.spotting
					elseif phase == "alert" then COLORS.search
					else COLORS.patrol
			)
		end
	end
	for model, view in views do
		if not seen[model] then
			destroy(view)
			views[model] = nil
		end
	end
end

function GuardVisionController.start()
	folder = Instance.new("Folder")
	folder.Name = "LocalGuardVision"
	folder.Parent = workspace
	RunService.RenderStepped:Connect(update)
end

return GuardVisionController

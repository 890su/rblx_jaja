--!strict
-- On spawn the character stands in front of the cryo capsule rows facing the
-- field, so the default camera (behind the back) lands inside a capsule.
-- Lift it above the capsules and pull it back a little, looking at the field.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer

local HEIGHT = 16 -- above the root: the view line clears capsule tops (~10.5)
local BACK = 9 -- behind the root (toward the capsules, which start ~6 back)
local ZOOM = math.sqrt(HEIGHT * HEIGHT + BACK * BACK)

local SpawnCameraController = {}

local function place(character: Model)
	local root = character:WaitForChild("HumanoidRootPart", 10) :: BasePart?
	if not root then
		return
	end
	-- Wait for the server to move the character onto its station.
	local t0 = os.clock()
	while os.clock() - t0 < 3 do
		local home = player:GetAttribute("HomePosition") :: Vector3?
		if home and (root.Position - home).Magnitude < 30 then
			break
		end
		task.wait(0.1)
	end
	if player:GetAttribute("ArenaActive") then
		return
	end
	local camera = workspace.CurrentCamera
	if not camera or camera.CameraType ~= Enum.CameraType.Custom then
		return
	end
	-- Facing the field means "behind" is the root's back (+LookVector reversed).
	local look = Vector3.new(root.CFrame.LookVector.X, 0, root.CFrame.LookVector.Z)
	look = if look.Magnitude > 0.01 then look.Unit else Vector3.new(0, 0, -1)
	local eye = root.Position - look * BACK + Vector3.new(0, HEIGHT, 0)
	camera.CFrame = CFrame.lookAt(eye, root.Position + look * 6 + Vector3.new(0, 2, 0))
	-- The camera module keeps its own zoom; nudge it out to match for a frame.
	local minZoom = player.CameraMinZoomDistance
	player.CameraMinZoomDistance = math.min(ZOOM, player.CameraMaxZoomDistance)
	RunService.RenderStepped:Wait()
	RunService.RenderStepped:Wait()
	player.CameraMinZoomDistance = minZoom
end

function SpawnCameraController.start()
	player.CharacterAdded:Connect(function(character)
		task.spawn(place, character)
	end)
	if player.Character then
		task.spawn(place, player.Character)
	end
end

return SpawnCameraController

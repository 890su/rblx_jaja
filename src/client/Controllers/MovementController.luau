--!strict
-- Smooth acceleration and braking. The server publishes the full speed as the
-- humanoid's TargetWalkSpeed attribute (its WalkSpeed stays authoritative for
-- anti-cheat); locally we ramp WalkSpeed up while the player holds a direction
-- and let them coast to a stop after release, instead of instant start/stop.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer

local START_SPEED = 12 -- studs/s the moment input begins
local ACCEL_TIME = 0.9 -- seconds from standstill to full speed
local MIN_ACCEL = 30 -- studs/s² floor so slow characters still feel snappy
local BRAKE_TIME = 0.5 -- seconds from full speed to standstill
local MIN_BRAKE = 60
local REVERSE_DOT = -0.3 -- sharper turns than this bleed speed
local REVERSE_KEEP = 0.4

local MovementController = {}

local speed = 0
local lastDirection = Vector3.zero
local coastUntil = 0 -- our own coast Move shows up in MoveDirection; ignore it
local controls: any = nil -- legacy PlayerModule, including touch/gamepad input

local function flat(v: Vector3): Vector3
	local f = Vector3.new(v.X, 0, v.Z)
	return if f.Magnitude > 1e-3 then f.Unit else Vector3.zero
end

-- The default PlayerModule (input-action edition) exposes movement as the
-- "MoveAction" InputAction: a Direction2D state, +Y = forward.
local function findMoveAction(): InputAction?
	for _, root in { player:FindFirstChild("PlayerScripts"), game:GetService("StarterPlayer") } do
		local action = root and root:FindFirstChild("MoveAction", true)
		if action and action:IsA("InputAction") then
			return action
		end
	end
	return nil
end

local function step(moveAction: InputAction?, dt: number)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		speed = 0
		return
	end
	local target = humanoid:GetAttribute("TargetWalkSpeed") :: number?
	if not target then
		return -- server hasn't applied a speed yet; leave WalkSpeed alone
	end

	-- Player input in world space (same mapping the default ControlModule uses).
	local moveVector = if moveAction then moveAction:GetState() :: any else nil
	local raw = Vector3.zero
	if typeof(moveVector) == "Vector2" then
		raw = Vector3.new(moveVector.X, 0, -moveVector.Y)
	elseif controls then
		raw = controls:GetMoveVector()
	end
	local input = Vector3.zero
	if raw.Magnitude > 0.05 then
		local camera = workspace.CurrentCamera
		-- Screen-relative. Looking straight down (Void Run), "forward" is the
		-- camera's up vector, which points toward home.
		local forward = flat(camera.CFrame.LookVector)
		if math.abs(camera.CFrame.LookVector.Y) > 0.9 then
			forward = flat(camera.CFrame.UpVector)
		end
		input = flat(camera.CFrame.RightVector) * raw.X - forward * raw.Z
	end
	if player:GetAttribute("ArenaActive") then
		-- In the dodge arena there is no coasting or turn penalty.
		coastUntil, speed, lastDirection = 0, 0, Vector3.zero
		humanoid.WalkSpeed = target
		if moveAction or controls then
			humanoid:Move(input, false)
		end
		return
	end

	if input.Magnitude > 0.05 then
		local direction = input.Unit
		if lastDirection ~= Vector3.zero and direction:Dot(lastDirection) < REVERSE_DOT then
			speed *= REVERSE_KEEP
		end
		lastDirection = direction
		speed = math.max(speed, math.min(START_SPEED, target))
		local accel = math.max(MIN_ACCEL, target / ACCEL_TIME)
		speed = math.min(target, speed + accel * dt)
		humanoid.WalkSpeed = speed
	else
		local brake = math.max(MIN_BRAKE, target / BRAKE_TIME)
		speed = math.max(0, speed - brake * dt)
		if speed > 1 and lastDirection ~= Vector3.zero and moveAction then
			-- Coast: overrides the ControlModule's zero move for this frame.
			humanoid.WalkSpeed = speed
			humanoid:Move(lastDirection, false)
			coastUntil = os.clock() + 0.2
		else
			if os.clock() <= coastUntil then
				humanoid:Move(Vector3.zero, false) -- end our coast override
				coastUntil = 0
			end
			speed = 0
			lastDirection = Vector3.zero
			-- Idle: full speed so MoveTo / click-to-move (which bypass the
			-- move action) aren't throttled; input restarts the ramp anyway.
			humanoid.WalkSpeed = target
		end
	end
	-- A carry/buff change may lower the cap mid-run.
	if speed > target then
		speed = target
		humanoid.WalkSpeed = target
	end
end

function MovementController.start()
	local moveAction = findMoveAction()
	task.spawn(function()
		local playerScripts = player:WaitForChild("PlayerScripts")
		local module = playerScripts:WaitForChild("PlayerModule", 10)
		if module and module:IsA("ModuleScript") then
			local ok, result = pcall(require, module)
			if ok and typeof(result) == "table" and typeof(result.GetControls) == "function" then
				controls = result:GetControls()
			end
		end
	end)
	player.CharacterAdded:Connect(function()
		speed = 0
		lastDirection = Vector3.zero
	end)
	-- After the ControlModule (Input priority) so the coast Move wins.
	RunService:BindToRenderStep(
		"MovementSmoothing",
		Enum.RenderPriority.Character.Value,
		function(dt: number)
			if not moveAction then
				moveAction = findMoveAction()
			end
			step(moveAction, dt)
		end
	)
end

return MovementController

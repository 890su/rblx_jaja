--!strict
-- Smooth acceleration and braking. The server publishes the full speed as the
-- humanoid's TargetWalkSpeed attribute (its WalkSpeed stays authoritative for
-- anti-cheat); locally we ramp WalkSpeed up while the player holds a direction
-- and let them coast to a stop after release, instead of instant start/stop.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Physics = require(Shared.Config.Speed).PHYSICS

local player = Players.LocalPlayer

local START_SPEED = 12 -- studs/s the moment input begins
local ACCEL_TIME = 0.9 -- seconds from standstill to full speed
local MIN_ACCEL = 30 -- studs/s² floor so slow characters still feel snappy
local BRAKE_TIME = Physics.brakeSeconds -- seconds from full speed to standstill
local MIN_BRAKE = 60
local REVERSE_DOT = -0.3 -- sharper turns than this bleed speed
local REVERSE_KEEP = 0.4

local MovementController = {}

local speed = 0
local lastDirection = Vector3.zero
local coastUntil = 0 -- our own coast Move shows up in MoveDirection; ignore it
local controls: any = nil -- legacy PlayerModule, including touch/gamepad input
local probeRoot: BasePart? = nil
local probeParams = RaycastParams.new()
probeParams.FilterType = Enum.RaycastFilterType.Exclude
probeParams.RespectCanCollide, probeParams.IgnoreWater = true, true
local footOffset = 0

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
	if player:GetAttribute("ArenaActive") or player:GetAttribute("ArenaPrep") then
		-- Void Run (and its staging strip): no coasting or turn penalty. A
		-- faster runner eases down to corridor pace instead of snapping to it.
		coastUntil, lastDirection = 0, Vector3.zero
		speed = math.max(target, speed - math.max(MIN_BRAKE, speed / BRAKE_TIME) * dt)
		humanoid.WalkSpeed = speed
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

local function protectRun(dt: number)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if
		not character
		or not humanoid
		or not root
		or not root:IsA("BasePart")
		or humanoid.Health <= 0
	then
		return
	end
	if root ~= probeRoot then
		probeRoot = root
		probeParams.FilterDescendantsInstances = { character }
		local leg = character:FindFirstChild("Left Leg")
		footOffset = if humanoid.RigType == Enum.HumanoidRigType.R6
				and leg
				and leg:IsA("BasePart")
			then leg.Size.Y
			else 0
	end
	local target = (humanoid:GetAttribute("TargetWalkSpeed") :: number?) or humanoid.WalkSpeed
	humanoid.AutoJumpEnabled = player.AutoJumpEnabled and target < Physics.highSpeed
	local state = humanoid:GetState()
	-- Server combat shoves and arena movement keep their existing behavior.
	if
		player:GetAttribute("ArenaActive")
		or player:GetAttribute("ArenaPrep")
		or state == Enum.HumanoidStateType.FallingDown
		or state == Enum.HumanoidStateType.Ragdoll
		or state == Enum.HumanoidStateType.GettingUp
		or humanoid.PlatformStand
	then
		return
	end
	local velocity = root.AssemblyLinearVelocity
	local horizontal = Vector3.new(velocity.X, 0, velocity.Z)
	if target < Physics.highSpeed and horizontal.Magnitude < Physics.highSpeed then
		return
	end
	local jumpSpeed = if humanoid.UseJumpPower
		then humanoid.JumpPower
		else math.sqrt(2 * workspace.Gravity * humanoid.JumpHeight)
	local launchLimit = if state == Enum.HumanoidStateType.Running
			and humanoid.FloorMaterial == Enum.Material.Air
		then math.min(jumpSpeed, Physics.maxClimbRiseSpeed)
		else jumpSpeed
	if velocity.Y > launchLimit + Physics.launchSlack then
		-- Keep the ordinary jump impulse; discard only an excessive upward kick.
		root.AssemblyLinearVelocity = horizontal + Vector3.new(0, launchLimit, 0)
	end
	if humanoid.FloorMaterial == Enum.Material.Air or horizontal.Magnitude < 1 then
		return
	end
	probeParams.CollisionGroup = root.CollisionGroup
	local frame = math.clamp(dt, 1 / 240, Physics.maxStep)
	local travel = horizontal.Magnitude * frame + Physics.wallSkin
	local floorY = root.Position.Y - humanoid.HipHeight - root.Size.Y / 2 - footOffset
	local center = Vector3.new(
		root.Position.X,
		floorY + Physics.probeLift + Physics.probeHeight / 2,
		root.Position.Z
	)
	local hit = workspace:Blockcast(
		CFrame.new(center),
		Vector3.new(root.Size.X * 0.8, Physics.probeHeight, root.Size.Z * 0.8),
		horizontal.Unit * travel,
		probeParams
	)
	-- Blockcast does not report surfaces already overlapping its initial box.
	-- Keep the climbing pace bounded while our feet are already on a ramp.
	if not hit then
		hit = workspace:Raycast(
			root.Position,
			Vector3.new(0, -(root.Position.Y - floorY + Physics.probeHeight), 0),
			probeParams
		)
	end
	if not hit then
		return
	end
	local normal = Vector3.new(hit.Normal.X, 0, hit.Normal.Z)
	if normal.Magnitude < 0.1 then
		return
	end
	normal = normal.Unit
	local intoWall = -horizontal:Dot(normal)
	local allowed = math.max(0, hit.Distance - Physics.wallSkin) / frame
	if hit.Normal.Y >= math.cos(math.rad(Physics.maxSlopeAngle)) then
		-- A walkable ramp still converts horizontal momentum into an upward
		-- impulse. Limit the climbing component before contact, then let the
		-- humanoid climb it normally. Manual jumps keep their normal impulse.
		local slope = Vector3.new(hit.Normal.X, 0, hit.Normal.Z).Magnitude / hit.Normal.Y
		allowed = math.min(jumpSpeed, Physics.maxClimbRiseSpeed) / slope
	end
	if intoWall > allowed then
		local safeVelocity = horizontal + normal * (intoWall - allowed)
		root.AssemblyLinearVelocity = safeVelocity
			+ Vector3.new(0, math.min(velocity.Y, jumpSpeed), 0)
		humanoid.WalkSpeed = math.min(humanoid.WalkSpeed, safeVelocity.Magnitude)
		speed = math.min(speed, humanoid.WalkSpeed)
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
			protectRun(dt)
		end
	)
	-- Contact impulses arrive during physics; remove a launch in that same
	-- simulation step rather than waiting for the next rendered frame.
	RunService.PostSimulation:Connect(function(dt: number)
		protectRun(dt)
	end)
end

return MovementController

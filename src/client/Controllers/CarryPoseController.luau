--!strict
-- Procedural overlays after the Animator: carry arms and running in place.
-- Supports modern R15 AnimationConstraints as well as R15/R6 Motor6Ds.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local WavePose = require(Shared.Util.WavePose)
local Emotes = require(Shared.Config.Emotes)

type Joint = Motor6D | AnimationConstraint | Bone
type Rig = {
	character: Model,
	joints: { [string]: Joint },
	controlled: { [Joint]: boolean },
	added: RBXScriptConnection?,
}

local CarryPoseController = {}
local rigs: { [Player]: Rig } = {}
local phase = 0

local function unregister(player: Player)
	local rig = rigs[player]
	if rig and rig.added then
		rig.added:Disconnect()
	end
	rigs[player] = nil
end

local function setTransform(joint: Joint, transform: CFrame)
	if joint:IsA("Motor6D") then
		local motor = joint :: Motor6D
		motor.Transform = transform
	elseif joint:IsA("AnimationConstraint") then
		local constraint = joint :: AnimationConstraint
		constraint.Transform = transform
	else
		local bone = joint :: Bone
		bone.Transform = transform
	end
end

local function addJoint(rig: Rig, instance: Instance)
	if instance:IsA("Motor6D") or instance:IsA("AnimationConstraint") or instance:IsA("Bone") then
		rig.joints[instance.Name:gsub(" ", "")] = instance :: Joint
	end
end

local function register(player: Player, character: Model)
	unregister(player)
	local rig: Rig = { character = character, joints = {}, controlled = {} }
	rigs[player] = rig
	for _, instance in character:GetDescendants() do
		addJoint(rig, instance)
	end
	rig.added = character.DescendantAdded:Connect(function(instance)
		addJoint(rig, instance)
	end)
end

local function pose(rig: Rig, role: string, transform: CFrame, used: { [Joint]: boolean })
	local joint = rig.joints[role]
	if joint and joint.Parent then
		setTransform(joint, transform)
		used[joint] = true
	end
end

local function step(dt: number)
	phase += dt * 11
	for player, rig in rigs do
		if not rig.character.Parent then
			continue
		end
		local humanoid = rig.character:FindFirstChildOfClass("Humanoid")
		local carrying = player:GetAttribute("Carrying") ~= nil
		local treadmill = player:GetAttribute("OnTreadmill") == true
		local used: { [Joint]: boolean } = {}
		if humanoid and humanoid.Health > 0 then
			local r6 = humanoid.RigType == Enum.HumanoidRigType.R6
			if treadmill then
				local swing = math.sin(phase)
				for _, side in { { name = "Right", sign = 1 }, { name = "Left", sign = -1 } } do
					local leg = swing * side.sign
					pose(
						rig,
						side.name .. "Hip",
						if r6
							then CFrame.Angles(0, 0, leg * 0.75 * side.sign)
							else CFrame.Angles(leg * 0.8, 0, 0),
						used
					)
					pose(
						rig,
						side.name .. "Knee",
						CFrame.Angles(-math.max(0, -leg) * 1.15, 0, 0),
						used
					)
					pose(rig, side.name .. "Ankle", CFrame.Angles(leg * -0.22, 0, 0), used)
					if not carrying then
						pose(
							rig,
							side.name .. "Shoulder",
							if r6
								then CFrame.Angles(0, 0, -leg * 0.65 * side.sign)
								else CFrame.Angles(-leg * 0.65, 0, 0),
							used
						)
						pose(
							rig,
							side.name .. "Elbow",
							CFrame.Angles(0.35 + math.max(0, leg) * 0.25, 0, 0),
							used
						)
					end
				end
				pose(rig, "Waist", CFrame.Angles(-0.1, 0, swing * 0.025), used)
			end
			if carrying then
				for _, side in { { name = "Right", sign = 1 }, { name = "Left", sign = -1 } } do
					pose(
						rig,
						side.name .. "Shoulder",
						if r6
							then CFrame.Angles(0, 0, math.rad(80) * side.sign)
							else CFrame.Angles(math.rad(55), 0, math.rad(-16) * side.sign),
						used
					)
					pose(rig, side.name .. "Elbow", CFrame.Angles(math.rad(40), 0, 0), used)
					pose(rig, side.name .. "Wrist", CFrame.Angles(math.rad(-15), 0, 0), used)
				end
			end
			local startedAt = player:GetAttribute("EmoteStartedAt")
			local root = rig.character:FindFirstChild("HumanoidRootPart")
			if
				not carrying
				and not treadmill
				and player:GetAttribute("EmoteKey") == "wave"
				and typeof(startedAt) == "number"
				and root
				and root:IsA("BasePart")
				and humanoid.MoveDirection.Magnitude < 0.05
				and humanoid.FloorMaterial ~= Enum.Material.Air
				and Vector3.new(root.AssemblyLinearVelocity.X, 0, root.AssemblyLinearVelocity.Z).Magnitude
					<= Emotes.MAX_HORIZONTAL_SPEED
			then
				local shoulder, elbow, wrist, neck, waist =
					WavePose.sample(workspace:GetServerTimeNow() - startedAt, r6)
				pose(rig, "RightShoulder", shoulder, used)
				pose(rig, "Neck", neck, used)
				if not r6 then
					pose(rig, "RightElbow", elbow, used)
					pose(rig, "RightWrist", wrist, used)
					pose(rig, "Waist", waist, used)
				end
			end
		end
		for joint in rig.controlled do
			if not used[joint] and joint.Parent then
				setTransform(joint, CFrame.identity)
			end
		end
		rig.controlled = used
	end
end

function CarryPoseController.start()
	local function watch(player: Player)
		player.CharacterRemoving:Connect(function(character)
			if rigs[player] and rigs[player].character == character then
				unregister(player)
			end
		end)
		player.CharacterAdded:Connect(function(character)
			register(player, character)
		end)
		if player.Character then
			register(player, player.Character)
		end
	end
	Players.PlayerAdded:Connect(watch)
	Players.PlayerRemoving:Connect(unregister)
	for _, player in Players:GetPlayers() do
		watch(player)
	end
	RunService.PreSimulation:Connect(step)
end

return CarryPoseController

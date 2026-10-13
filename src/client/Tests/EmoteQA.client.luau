--!strict
-- Test-only client observations of the actual live pose controller.
if not game:GetService("RunService"):IsStudio() then
	return
end
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local remote = ReplicatedStorage:WaitForChild("EmoteQA", 15)
if not remote or not remote:IsA("RemoteEvent") then
	return
end
local Players = game:GetService("Players")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local WavePose = require(Shared.Util.WavePose)
remote.OnClientEvent:Connect(function(nonce: number, userId: number, rig: string)
	-- Read after Animator and the live overlay have evaluated this frame.
	game:GetService("RunService").PostSimulation:Wait()
	local target = Players:GetPlayerByUserId(userId)
	local character = target and target.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local startedAt = target and target:GetAttribute("EmoteStartedAt")
	local joint = character
		and (
			character:FindFirstChild("RightShoulder", true)
			or character:FindFirstChild("Right Shoulder", true)
		)
	local success = false
	local errorAngle = math.huge
	if
		target
		and humanoid
		and humanoid.RigType.Name == rig
		and typeof(startedAt) == "number"
		and joint
	then
		local actual: CFrame? = nil
		if joint:IsA("Motor6D") or joint:IsA("AnimationConstraint") or joint:IsA("Bone") then
			actual = (joint :: Motor6D | AnimationConstraint | Bone).Transform
		end
		if actual then
			local expected = WavePose.sample(workspace:GetServerTimeNow() - startedAt, rig == "R6")
			local _, angle = expected:ToObjectSpace(actual):ToAxisAngle()
			errorAngle = math.abs(angle)
			success = target:GetAttribute("EmoteKey") == "wave" and errorAngle < 0.15
		end
	end
	remote:FireServer(nonce, success, {
		rig = humanoid and humanoid.RigType.Name,
		angle = errorAngle,
		joint = joint and joint.ClassName,
	})
end)

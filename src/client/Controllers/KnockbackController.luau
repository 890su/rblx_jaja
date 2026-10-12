--!strict
-- Applies a server-requested knockback to our own character: a shove away
-- from the hit, a short tumble, and a quick camera shake.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Remotes = require(Shared.Remotes)

local player = Players.LocalPlayer

local TUMBLE_SECONDS = 0.8
local SHAKE_SECONDS = 0.35

local KnockbackController = {}

local function shake(humanoid: Humanoid)
	local t0 = os.clock()
	local connection: RBXScriptConnection
	connection = RunService.RenderStepped:Connect(function()
		local t = os.clock() - t0
		if t >= SHAKE_SECONDS or not humanoid.Parent then
			humanoid.CameraOffset = Vector3.zero
			connection:Disconnect()
			return
		end
		local strength = 0.6 * (1 - t / SHAKE_SECONDS)
		humanoid.CameraOffset =
			Vector3.new((math.random() - 0.5) * strength, (math.random() - 0.5) * strength, 0)
	end)
end

function KnockbackController.start()
	Remotes.event("Knockback").OnClientEvent:Connect(function(direction: Vector3, power: number)
		if typeof(direction) ~= "Vector3" or typeof(power) ~= "number" then
			return
		end
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if not root or not humanoid or humanoid.Health <= 0 then
			return
		end
		power = math.clamp(power, 0, 120)
		humanoid:ChangeState(Enum.HumanoidStateType.FallingDown)
		root.AssemblyLinearVelocity = direction.Unit * power + Vector3.new(0, power * 0.55, 0)
		shake(humanoid)
		task.delay(TUMBLE_SECONDS, function()
			if humanoid.Parent and humanoid.Health > 0 then
				humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
			end
		end)
	end)
end

return KnockbackController

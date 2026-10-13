--!strict
-- Read-only observations; the remote only exists in the isolated Studio suite.
if not game:GetService("RunService"):IsStudio() then
	return
end
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local remote = ReplicatedStorage:WaitForChild("ArenaQA", 15)
if not remote or not remote:IsA("RemoteEvent") then
	return
end
local player = game:GetService("Players").LocalPlayer
local waveCount = 0
local waveConnection = ReplicatedStorage:WaitForChild("Remotes")
	:WaitForChild("ArenaWave").OnClientEvent
	:Connect(function()
		waveCount += 1
	end)
local probeConnection: RBXScriptConnection
probeConnection = remote.OnClientEvent:Connect(function(nonce: number, _actorId: number)
	game:GetService("RunService").PreRender:Wait()
	local gui = player.PlayerGui:FindFirstChild("ArenaUi") :: ScreenGui?
	local world = workspace:FindFirstChild("LocalVoidRun")
	local hazards = 0
	if world then
		for _, item in world:GetChildren() do
			if
				item:IsA("BasePart")
				and string.match(item.Name, "^%d+")
				and item.Transparency < 1
			then
				hazards += 1
			end
		end
	end
	remote:FireServer(nonce, {
		enabled = gui ~= nil and gui.Enabled,
		camera = if workspace.CurrentCamera.CameraType == Enum.CameraType.Scriptable
			then "Scriptable"
			elseif workspace.CurrentCamera.CameraType == Enum.CameraType.Custom then "Custom"
			else "Other",
		hazards = hazards,
		waves = waveCount,
	})
end)
remote.Destroying:Connect(function()
	waveConnection:Disconnect()
	probeConnection:Disconnect()
end)

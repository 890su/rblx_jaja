--!strict
-- Throws a hit player away from the attack. The character's physics belong to
-- its client, so the server asks that client to apply the impulse and gives
-- the anti-cheat a grace period for the sudden movement.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Remotes = require(ReplicatedStorage:WaitForChild("Shared").Remotes)
local SpeedService = require(script.Parent.Parent.Services.SpeedService)

local POWER = 70

local Knockback = {}

-- `from`: where the hit came from (world position); nil = straight back.
function Knockback.apply(player: Player, from: Vector3?)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return
	end
	local away = if from then root.Position - from else -root.CFrame.LookVector
	away = Vector3.new(away.X, 0, away.Z)
	if away.Magnitude < 1e-3 then
		away = -root.CFrame.LookVector
		away = Vector3.new(away.X, 0, away.Z)
	end
	SpeedService.markTeleport(player)
	Remotes.event("Knockback"):FireClient(player, away.Unit, POWER)
end

return Knockback

--!strict
-- Cosmetic state only. No movement locking, hitbox changes or invulnerability.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config.Emotes)
local Remotes = require(Shared.Remotes)
local RateLimit = require(script.Parent.Parent.Util.RateLimit)
local DataService = require(script.Parent.DataService)
local Types = require(Shared.Types)

type Active = { character: Model, root: BasePart, origin: Vector3, startedAt: number }
local active: { [Player]: Active } = {}
local lastStart: { [Player]: number } = {}
local limit = RateLimit.new(2, 1)
local EmoteService = {}

local function allowed(player: Player, humanoid: Humanoid, root: BasePart): boolean
	local velocity = root.AssemblyLinearVelocity
	return humanoid.Health > 0
		and humanoid.Sit == false
		and humanoid.FloorMaterial ~= Enum.Material.Air
		and Vector3.new(velocity.X, 0, velocity.Z).Magnitude <= Config.MAX_HORIZONTAL_SPEED
		and player:GetAttribute("Carrying") == nil
		and player:GetAttribute("OnTreadmill") ~= true
		and player:GetAttribute("ArenaActive") ~= true
		and player:GetAttribute("ArenaPrep") ~= true
end

function EmoteService.stop(player: Player)
	active[player] = nil
	player:SetAttribute("EmoteKey", nil)
	player:SetAttribute("EmoteStartedAt", nil)
end

function EmoteService.play(player: Player, key: Types.EmoteKey): boolean
	if key ~= "wave" or player.Parent ~= Players or not DataService.get(player) then
		return false
	end
	local now = workspace:GetServerTimeNow()
	if active[player] or now - (lastStart[player] or -math.huge) < Config.COOLDOWN_SECONDS then
		return false
	end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if
		not character
		or not humanoid
		or not root
		or not root:IsA("BasePart")
		or not allowed(player, humanoid, root)
	then
		return false
	end
	lastStart[player] = now
	active[player] = { character = character, root = root, origin = root.Position, startedAt = now }
	player:SetAttribute("EmoteStartedAt", now)
	player:SetAttribute("EmoteKey", key)
	return true
end

function EmoteService.init()
	Remotes.event("RequestEmote").OnServerEvent:Connect(function(player, key: any)
		if not limit:allow(player) or typeof(key) ~= "string" then
			return
		end
		if key == "stop" then
			EmoteService.stop(player)
		elseif key == "wave" then
			EmoteService.play(player, key)
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		active[player], lastStart[player] = nil, nil
	end)
end

function EmoteService.start()
	local elapsed = 0
	RunService.Heartbeat:Connect(function(dt)
		elapsed += dt
		if elapsed < Config.SERVER_PERIOD then
			return
		end
		elapsed = 0
		local now = workspace:GetServerTimeNow()
		for player, state in active do
			local humanoid = state.character:FindFirstChildOfClass("Humanoid")
			local delta = state.root.Position - state.origin
			if
				player.Character ~= state.character
				or not state.root.Parent
				or not humanoid
				or not allowed(player, humanoid, state.root)
				or Vector3.new(delta.X, 0, delta.Z).Magnitude > Config.MAX_DRIFT
				or now - state.startedAt >= Config.WAVE_DURATION
			then
				EmoteService.stop(player)
			end
		end
	end)
end

return EmoteService

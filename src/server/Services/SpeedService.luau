--!strict
-- +1 Speed per second while moving (GDD §4.1). Server measures movement from
-- root-part position deltas, so a client can't claim speed it didn't earn.
-- Also enforces zone gates and flags impossible movement (teleports).

local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Speed = require(Shared.Config.Speed)
local Zones = require(Shared.Config.Zones)
local Theme = require(Shared.Theme)
local Remotes = require(Shared.Remotes)

local DataService = require(script.Parent.DataService)
local WorldService = require(script.Parent.WorldService)

local TICK = 1
local TELEPORT_SLACK = 1.6 -- allowed multiple of WalkSpeed * dt before flagging
local TELEPORT_FLAT = 25 -- studs of slack for physics/latency

local SpeedService = {}

local lastPosition: { [Player]: Vector3 } = {}
local notify: RemoteEvent

local function rootOf(player: Player): (BasePart?, Humanoid?)
	local character = player.Character
	if not character then
		return nil, nil
	end
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid and humanoid.Health <= 0 then
		return nil, nil
	end
	return root, humanoid
end

function SpeedService.walkSpeedFor(speed: number, carrying: boolean): number
	local walk = Speed.BASE_WALKSPEED + Speed.WALKSPEED_COEFFICIENT * math.sqrt(speed)
	walk = math.min(walk, Speed.WALKSPEED_CAP)
	return if carrying then walk * Speed.CARRY_MULTIPLIER else walk
end

function SpeedService.gainMultiplier(player: Player): number
	local profile = DataService.get(player)
	local rebirths = if profile then profile.rebirths else 0
	-- Friend bonus (week 4) and 2x Speed pass (week 5) plug in here.
	return 1 + rebirths * Speed.REBIRTH_GAIN_BONUS
end

function SpeedService.isZoneUnlocked(player: Player, zoneIndex: number): boolean
	local zone = Zones.ZONES[zoneIndex]
	local profile = DataService.get(player)
	if not zone or not profile then
		return zoneIndex <= 1
	end
	return profile.speed >= zone.speedGate and profile.rebirths >= zone.rebirthGate
end

-- Re-applies WalkSpeed from authoritative state (call after carry changes).
function SpeedService.apply(player: Player)
	local profile = DataService.get(player)
	local _, humanoid = rootOf(player)
	if profile and humanoid then
		local carrying = player:GetAttribute("Carrying") ~= nil
		humanoid.WalkSpeed = SpeedService.walkSpeedFor(profile.speed, carrying)
	end
end

local function pushBehindGate(player: Player, root: BasePart, zoneIndex: number)
	local gateZ = WorldService.gateZ(zoneIndex)
	local character = player.Character :: Model
	character:PivotTo(CFrame.new(root.Position.X, root.Position.Y + 2, gateZ + 8))
	local zone = Zones.ZONES[zoneIndex]
	local name = Theme.ZONE_NAMES[zoneIndex] or `Zone {zoneIndex}`
	notify:FireClient(player, `{name} needs {zone.speedGate} Speed`, "warning")
end

local function tickPlayer(player: Player)
	local profile = DataService.get(player)
	local root, humanoid = rootOf(player)
	if not profile or not root or not humanoid then
		lastPosition[player] = nil
		return
	end
	local position = root.Position
	local previous = lastPosition[player]
	lastPosition[player] = position
	if not previous then
		return
	end

	local delta = Vector3.new(position.X - previous.X, 0, position.Z - previous.Z).Magnitude
	local maxDistance = humanoid.WalkSpeed * TICK * TELEPORT_SLACK + TELEPORT_FLAT
	if delta > maxDistance then
		-- Our own spawns/pivots can land here once; only log for now.
		-- Week 3 turns this into rubber-banding + strike count.
		warn(`[SpeedService] {player.Name} moved {math.floor(delta)} studs in {TICK}s`)
	elseif delta >= Speed.MIN_MOVE_STUDS_PER_TICK then
		local gain = Speed.GAIN_PER_SECOND * SpeedService.gainMultiplier(player)
		DataService.setSpeed(player, profile.speed + gain)
	end

	local zoneIndex = WorldService.zoneIndexAt(position)
	if zoneIndex > 1 and not SpeedService.isZoneUnlocked(player, zoneIndex) then
		-- Push the player behind the first locked gate they are past.
		for i = 2, zoneIndex do
			if not SpeedService.isZoneUnlocked(player, i) then
				pushBehindGate(player, root, i)
				lastPosition[player] = nil
				break
			end
		end
	end

	SpeedService.apply(player)
end

function SpeedService.init()
	notify = Remotes.event("Notify")
	Players.PlayerRemoving:Connect(function(player)
		lastPosition[player] = nil
	end)
end

function SpeedService.start()
	while true do
		task.wait(TICK)
		for _, player in Players:GetPlayers() do
			tickPlayer(player)
		end
	end
end

return SpeedService

--!strict
-- +1 Speed per second while moving (GDD §4.1). Server measures movement from
-- root-part position deltas, so a client can't claim speed it didn't earn.
-- Also enforces zone gates, rubber-bands impossible movement (teleports) and
-- applies temporary buffs (owner chase bonus).

local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Speed = require(Shared.Config.Speed)
local Economy = require(Shared.Config.Economy)
local Steal = require(Shared.Config.Steal)
local Zones = require(Shared.Config.Zones)
local Theme = require(Shared.Theme)
local Locale = require(Shared.Locale)

local Notifier = require(script.Parent.Parent.Util.Notifier)
local DataService = require(script.Parent.DataService)
local WorldService = require(script.Parent.WorldService)
local TelemetryService = require(script.Parent.TelemetryService)

local TICK = 1
local TELEPORT_SLACK = 1.6 -- allowed multiple of WalkSpeed * dt before flagging
local TELEPORT_FLAT = 25 -- studs of slack for physics/latency
local STRIKE_WINDOW = 60
local STRIKES_TO_KICK = 10
-- After a server teleport the client may still report its old position for a
-- moment; skip movement checks during this window.
local TELEPORT_GRACE = 2

local SpeedService = {}

type Track = { root: BasePart, position: Vector3 }

local tracked: { [Player]: Track } = {}
local strikes: { [Player]: { number } } = {}
local graceUntil: { [Player]: number } = {}

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

function SpeedService.walkSpeedFor(speed: number, carrying: boolean, chasing: boolean?): number
	local walk = Speed.BASE_WALKSPEED + Speed.WALKSPEED_COEFFICIENT * math.sqrt(speed)
	walk = math.min(walk, Speed.WALKSPEED_CAP)
	if carrying then
		walk *= Speed.CARRY_MULTIPLIER
	end
	if chasing then
		walk *= 1 + Steal.OWNER_CHASE_SPEED_BONUS
	end
	return walk
end

function SpeedService.gainMultiplier(player: Player): number
	local profile = DataService.get(player)
	local rebirths = if profile then profile.rebirths else 0
	local friends = (player:GetAttribute("FriendsInServer") :: number?) or 0 -- set by FriendService
	local friendBonus = math.min(friends * Speed.FRIEND_GAIN_BONUS, Speed.FRIEND_GAIN_BONUS_CAP)
	local pass = if player:GetAttribute("Pass_Speed2x") then Speed.PASS_MULTIPLIER else 1 -- set by MonetizationService
	local training = if profile then profile.training * Economy.TRAINING_BONUS else 0
	return (1 + rebirths * Speed.REBIRTH_GAIN_BONUS) * (1 + friendBonus) * (1 + training) * pass
end

function SpeedService.isZoneUnlocked(player: Player, zoneIndex: number): boolean
	local zone = Zones.ZONES[zoneIndex]
	local profile = DataService.get(player)
	if not zone or not profile then
		return zoneIndex <= 1
	end
	return profile.speed >= zone.speedGate and profile.rebirths >= zone.rebirthGate
end

-- Call before any server-initiated teleport so it isn't flagged as cheating.
function SpeedService.markTeleport(player: Player)
	tracked[player] = nil
	graceUntil[player] = os.clock() + TELEPORT_GRACE
end

-- Re-applies WalkSpeed from authoritative state (call after carry/buff changes).
function SpeedService.apply(player: Player)
	local profile = DataService.get(player)
	local _, humanoid = rootOf(player)
	if profile and humanoid then
		local carrying = player:GetAttribute("Carrying") ~= nil
		local chaseUntil = (player:GetAttribute("ChaseUntil") :: number?) or 0
		local chasing = chaseUntil > workspace:GetServerTimeNow()
		humanoid.WalkSpeed = SpeedService.walkSpeedFor(profile.speed, carrying, chasing)
	end
end

local function addStrike(player: Player): number
	local now = os.clock()
	local list = strikes[player] or {}
	strikes[player] = list
	table.insert(list, now)
	while list[1] and now - list[1] > STRIKE_WINDOW do
		table.remove(list, 1)
	end
	return #list
end

local function pushBehindGate(player: Player, root: BasePart, zoneIndex: number)
	local gateZ = WorldService.gateZ(zoneIndex)
	SpeedService.markTeleport(player)
	local character = player.Character :: Model
	character:PivotTo(CFrame.new(root.Position.X, root.Position.Y + 2, gateZ + 8))
	local zone = Zones.ZONES[zoneIndex]
	local name = Theme.ZONE_NAMES[zoneIndex] or `Zone {zoneIndex}`
	Notifier.send(
		player,
		"zone_locked",
		{ zone = Locale.ref(name), speed = zone.speedGate },
		"warning"
	)
end

local function tickPlayer(player: Player)
	local profile = DataService.get(player)
	local root, humanoid = rootOf(player)
	if not profile or not root or not humanoid then
		tracked[player] = nil
		return
	end
	local position = root.Position
	local previous = tracked[player]
	-- New character (respawn) or after a server teleport: start fresh.
	if not previous or previous.root ~= root or (graceUntil[player] or 0) > os.clock() then
		tracked[player] = { root = root, position = position }
		SpeedService.apply(player)
		return
	end

	local delta =
		Vector3.new(position.X - previous.position.X, 0, position.Z - previous.position.Z).Magnitude
	local maxDistance = humanoid.WalkSpeed * TICK * TELEPORT_SLACK + TELEPORT_FLAT
	if delta > maxDistance then
		-- Rubber-band to the last trusted position.
		local count = addStrike(player)
		warn(
			`[SpeedService] {player.Name} moved {math.floor(delta)} studs in {TICK}s (strike {count})`
		)
		if count >= STRIKES_TO_KICK then
			player:Kick("Unusual movement detected.")
			return
		end
		local character = player.Character :: Model
		root.AssemblyLinearVelocity = Vector3.zero
		character:PivotTo(CFrame.new(previous.position))
		return
	end
	previous.position = position
	if delta >= Speed.MIN_MOVE_STUDS_PER_TICK then
		local gain = Speed.GAIN_PER_SECOND * SpeedService.gainMultiplier(player)
		DataService.setSpeed(player, profile.speed + gain)
	end

	local zoneIndex = WorldService.zoneIndexAt(position)
	if zoneIndex >= 2 and SpeedService.isZoneUnlocked(player, 2) then
		TelemetryService.funnel(player, "ReachedZone2")
	end
	if zoneIndex > 1 and not SpeedService.isZoneUnlocked(player, zoneIndex) then
		-- Push the player behind the first locked gate they are past.
		for i = 2, zoneIndex do
			if not SpeedService.isZoneUnlocked(player, i) then
				pushBehindGate(player, root, i)
				break
			end
		end
	end

	SpeedService.apply(player)
end

function SpeedService.init()
	Players.PlayerRemoving:Connect(function(player)
		tracked[player] = nil
		strikes[player] = nil
		graceUntil[player] = nil
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

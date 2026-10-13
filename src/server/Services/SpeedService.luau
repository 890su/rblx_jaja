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
local Canyons = require(Shared.Config.Canyons)
local ArenaPatterns = require(Shared.Util.ArenaPatterns)
local MovementBudget = require(Shared.Util.MovementBudget)
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

type Track = { root: BasePart, position: Vector3, at: number }

local tracked: { [Player]: Track } = {}
local strikes: { [Player]: { number } } = {}
local graceUntil: { [Player]: number } = {}
local trainingMoving: { [Player]: boolean } = {}
local movement: { [Player]: { root: BasePart, state: MovementBudget.State } } = {}
local invalidCallbacks: { (player: Player, position: Vector3?) -> () } = {}

function SpeedService.onInvalidMovement(callback: (player: Player, position: Vector3?) -> ())
	table.insert(invalidCallbacks, callback)
end

local function discardCarry(player: Player, position: Vector3?)
	for _, callback in invalidCallbacks do
		-- Invalid movement must never yield and leave a deliverable carry alive.
		callback(player, position)
	end
end

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
function SpeedService.markTeleport(player: Player, destination: Vector3?)
	tracked[player] = nil
	trainingMoving[player] = false
	graceUntil[player] = os.clock() + TELEPORT_GRACE
	local root = rootOf(player)
	if root then
		local previous = movement[player]
		movement[player] = {
			root = root,
			state = {
				position = destination or (previous and previous.state.position) or root.Position,
				at = os.clock(),
				budget = TELEPORT_FLAT,
			},
		}
	end
end

-- Re-applies WalkSpeed from authoritative state (call after carry/buff changes).
function SpeedService.apply(player: Player)
	local profile = DataService.get(player)
	local _, humanoid = rootOf(player)
	if profile and humanoid then
		local carrying = player:GetAttribute("Carrying") ~= nil
		local chaseUntil = (player:GetAttribute("ChaseUntil") :: number?) or 0
		local chasing = chaseUntil > workspace:GetServerTimeNow()
		local walkSpeed = SpeedService.walkSpeedFor(profile.speed, carrying, chasing)
		if player:GetAttribute("ArenaActive") or player:GetAttribute("ArenaPrep") then
			-- Void Run: a fixed corridor pace derived from the normal speed.
			walkSpeed =
				ArenaPatterns.runSpeed(SpeedService.walkSpeedFor(profile.speed, false, false))
		end
		humanoid.WalkSpeed = walkSpeed
		-- MovementController ramps the local WalkSpeed toward this target.
		humanoid:SetAttribute("TargetWalkSpeed", walkSpeed)
		local treadmill = player:GetAttribute("OnTreadmill") == true
		local source = if treadmill
			then "Treadmill"
			elseif trainingMoving[player] then "Running"
			else "Idle"
		local rate = if treadmill
			then Speed.TREADMILL_RATE_NO_PASS
			elseif trainingMoving[player] then 1
			else 0
		player:SetAttribute("SpeedGainSource", source)
		player:SetAttribute(
			"SpeedGainPerSecond",
			rate * Speed.GAIN_PER_SECOND * SpeedService.gainMultiplier(player)
		)
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
	discardCarry(player, nil)
	SpeedService.markTeleport(player, Vector3.new(root.Position.X, root.Position.Y + 2, gateZ + 8))
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

-- Safety net behind the boundary walls: anyone outside the playable area or
-- fallen through the floor is put back (home if they fell or flew off).
local function keepInBounds(player: Player, root: BasePart): boolean
	local minX, maxX, minZ, maxZ = WorldService.playBounds()
	local p = root.Position
	local margin = 3
	local outside = p.X < minX - margin
		or p.X > maxX + margin
		or p.Z < minZ - margin
		or p.Z > maxZ + margin
	local lost = p.Y < -15 or p.Y > 350
	if not outside and not lost then
		return false
	end
	local target: Vector3
	local home = player:GetAttribute("HomePosition") :: Vector3?
	if lost and home then
		target = home + Vector3.new(0, 4, 0)
	else
		target = Vector3.new(
			math.clamp(p.X, minX + 4, maxX - 4),
			math.max(p.Y, 4),
			math.clamp(p.Z, minZ + 4, maxZ - 4)
		)
	end
	discardCarry(player, nil)
	SpeedService.markTeleport(player, target)
	root.AssemblyLinearVelocity = Vector3.zero;
	(player.Character :: Model):PivotTo(CFrame.new(target) * root.CFrame.Rotation)
	return true
end

-- Every valuable proximity action calls this before changing the economy.
function SpeedService.validatePosition(player: Player): Vector3?
	local root, humanoid = rootOf(player)
	if not root or not humanoid or not DataService.get(player) then
		return nil
	end
	if not MovementBudget.isFinite(root.Position) then
		discardCarry(player, nil)
		player:Kick("Invalid movement detected.")
		return nil
	end
	if keepInBounds(player, root) then
		return nil
	end
	local previous = movement[player]
	if not previous or previous.root ~= root then
		local home = player:GetAttribute("HomePosition") :: Vector3?
		if not home or (root.Position - home).Magnitude > 80 then
			return nil
		end
		previous = {
			root = root,
			state = { position = root.Position, at = os.clock(), budget = TELEPORT_FLAT },
		}
		movement[player] = assert(previous, "movement seed missing")
	end
	if not MovementBudget.accept(previous.state, root.Position, os.clock(), humanoid.WalkSpeed) then
		discardCarry(player, nil)
		root.AssemblyLinearVelocity = Vector3.zero;
		(player.Character :: Model):PivotTo(CFrame.new(previous.state.position))
		if addStrike(player) >= STRIKES_TO_KICK then
			player:Kick("Unusual movement detected.")
		end
		return nil
	end
	local zone = WorldService.zoneIndexAt(root.Position)
	for i = 2, zone do
		if not SpeedService.isZoneUnlocked(player, i) then
			pushBehindGate(player, root, i)
			return nil
		end
	end
	return root.Position
end

local function tickPlayer(player: Player)
	local profile = DataService.get(player)
	local root, humanoid = rootOf(player)
	if not profile or not root or not humanoid then
		tracked[player] = nil
		trainingMoving[player] = false
		player:SetAttribute("SpeedGainSource", "Idle")
		player:SetAttribute("SpeedGainPerSecond", 0)
		return
	end
	if not SpeedService.validatePosition(player) then
		return
	end
	local position = root.Position
	local previous = tracked[player]
	-- New character (respawn) or after a server teleport: start fresh.
	if not previous or previous.root ~= root or (graceUntil[player] or 0) > os.clock() then
		tracked[player] = { root = root, position = position, at = os.clock() }
		trainingMoving[player] = false
		SpeedService.apply(player)
		return
	end

	local delta =
		Vector3.new(position.X - previous.position.X, 0, position.Z - previous.position.Z).Magnitude
	local elapsed = math.max(0.01, os.clock() - previous.at)
	local maxDistance = humanoid.WalkSpeed * elapsed * TELEPORT_SLACK + TELEPORT_FLAT
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
		discardCarry(player, nil)
		root.AssemblyLinearVelocity = Vector3.zero
		character:PivotTo(CFrame.new(previous.position))
		return
	end
	previous.position = position
	previous.at = os.clock()
	-- Treadmill training is awarded by StationService, never twice per tick.
	trainingMoving[player] = delta >= Speed.MIN_MOVE_STUDS_PER_TICK
		and player:GetAttribute("OnTreadmill") ~= true
	if trainingMoving[player] then
		local gain = Speed.GAIN_PER_SECOND * SpeedService.gainMultiplier(player) * elapsed
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
	-- Keep carriers out of the new walls after the daily maze reshuffle.
	workspace.World:GetAttributeChangedSignal("CanyonDay"):Connect(function()
		for _, player in Players:GetPlayers() do
			local root = rootOf(player)
			local character = player.Character
			if
				root
				and character
				and WorldService.zoneIndexAt(root.Position) >= Canyons.FROM_ZONE
				and math.abs(root.Position.X) > Canyons.LANE_WIDTH / 2
			then
				SpeedService.markTeleport(player, Vector3.new(0, 3.2, root.Position.Z))
				character:PivotTo(CFrame.new(0, 3.2, root.Position.Z))
			end
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		tracked[player] = nil
		movement[player] = nil
		strikes[player] = nil
		graceUntil[player] = nil
		trainingMoving[player] = nil
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

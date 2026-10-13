--!strict
-- Void Run: carrying an egg from a deep zone home through zone 1 turns into a
-- top-down dodge corridor. The server schedules attack waves, sends each one
-- to the runner and checks hits with the same pure pattern math the client
-- renders. No client request can claim a dodge or a finish.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Arena = require(Shared.Config.Arena)
local Economy = require(Shared.Config.Economy)
local Rarity = require(Shared.Config.Rarity)
local Remotes = require(Shared.Remotes)
local Patterns = require(Shared.Util.ArenaPatterns)
local CarryService = require(script.Parent.CarryService)
local DataService = require(script.Parent.DataService)
local SpeedService = require(script.Parent.SpeedService)
local WorldService = require(script.Parent.WorldService)
local Notifier = require(script.Parent.Parent.Util.Notifier)
local Knockback = require(script.Parent.Parent.Util.Knockback)
local Telemetry = require(script.Parent.TelemetryService)

type Run = {
	carry: CarryService.Carry,
	character: Model,
	humanoid: Humanoid,
	laneX: number,
	zMin: number, -- far end of the corridor (zone boundary toward the crater)
	zMax: number, -- finish line (station side)
	level: number,
	runSpeed: number,
	lives: number,
	immuneUntil: number,
	previous: Vector2,
	nextWaveAt: number,
	waves: { Patterns.Wave },
	lastKind: string?,
	nextId: number,
	jumpPower: number,
	jumpHeight: number,
}

local HALF = Arena.LANE_WIDTH / 2 - Arena.EDGE_MARGIN
local FINAL_STRETCH = 25 -- no new waves this close to the finish
-- The client's soft wall stops the body at about HALF; the server only steps
-- in beyond this tolerance so it never fights ordinary wall sliding.
local CLAMP_TOLERANCE = 2

type Prep = { carry: CarryService.Carry, laneX: number, jumpPower: number, jumpHeight: number }

local ArenaService = {}
local active: { [Player]: Run } = {}
local preps: { [Player]: Prep } = {}
local completed: { [Player]: CarryService.Carry } = {}
local retryUntil: { [Player]: number } = {}
local rng = Random.new()
local waveEvent: RemoteEvent

local function body(player: Player): (Model?, BasePart?, Humanoid?)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not character or not root or not humanoid or humanoid.Health <= 0 then
		return nil, nil, nil
	end
	return character, root, humanoid
end

local function laneCenter(x: number): number
	local count = Economy.SERVER_SIZE
	local index =
		math.clamp(math.floor((x + count * Arena.LANE_WIDTH / 2) / Arena.LANE_WIDTH) + 1, 1, count)
	return (index - (count + 1) / 2) * Arena.LANE_WIDTH
end

local function qualifies(carry: CarryService.Carry?): boolean
	return carry ~= nil and (carry.originZone or 0) >= Arena.FROM_ORIGIN_ZONE
end

local function canStage(position: Vector3): boolean
	return math.abs(position.X) <= Economy.SERVER_SIZE * Arena.LANE_WIDTH / 2
		and position.Y >= 1
		and position.Y < 12
		and position.Z > WorldService.gateZ(Arena.FIELD_ZONE + 1) - Arena.PREP_DEPTH
		and position.Z < WorldService.gateZ(Arena.FIELD_ZONE) - FINAL_STRETCH
end

local function finish(player: Player, reason: string)
	local run = active[player]
	if not run then
		return
	end
	active[player] = nil
	if reason == "backtrack" then
		-- Ran back into the staging strip: stay staged (camera stays up) and
		-- start a fresh run on crossing again.
		preps[player] = {
			carry = run.carry,
			laneX = run.laneX,
			jumpPower = run.jumpPower,
			jumpHeight = run.jumpHeight,
		}
		player:SetAttribute("ArenaPrep", true)
		player:SetAttribute("ArenaLives", Arena.LIVES)
	end
	player:SetAttribute("ArenaActive", false)
	player:SetAttribute("ArenaIFramesUntil", nil)
	if reason ~= "backtrack" and run.humanoid.Parent then
		run.humanoid.JumpPower, run.humanoid.JumpHeight = run.jumpPower, run.jumpHeight
	end
	SpeedService.apply(player)
	if reason == "win" then
		completed[player] = run.carry
		Notifier.send(player, "arena_cleared", nil, "success")
		Telemetry.custom(player, "ArenaCleared")
	elseif reason == "hit" then
		local _, root = body(player)
		retryUntil[player] = workspace:GetServerTimeNow() + Arena.RETRY_GRACE
		-- The egg drops where the runner fell; grab it again to retry.
		CarryService.drop(player, if root then root.Position else run.character:GetPivot().Position)
		Knockback.apply(player, nil)
		Notifier.send(player, "arena_failed", nil, "warning")
		Telemetry.custom(player, "ArenaFailed")
	end
end

-- Staging: lock the lane, stop jumping, ease to corridor pace; the client
-- raises the camera. Attacks only start once the run begins.
local function startPrep(
	player: Player,
	carry: CarryService.Carry,
	root: BasePart,
	humanoid: Humanoid
): Prep
	local prep: Prep = {
		carry = carry,
		laneX = laneCenter(root.Position.X),
		jumpPower = humanoid.JumpPower,
		jumpHeight = humanoid.JumpHeight,
	}
	preps[player] = prep
	humanoid.JumpPower, humanoid.JumpHeight = 0, 0
	player:SetAttribute("ArenaLaneX", prep.laneX)
	player:SetAttribute("ArenaZMin", WorldService.gateZ(Arena.FIELD_ZONE + 1))
	player:SetAttribute("ArenaZMax", WorldService.gateZ(Arena.FIELD_ZONE))
	player:SetAttribute("ArenaLives", Arena.LIVES)
	player:SetAttribute("ArenaPrep", true)
	SpeedService.markTeleport(player) -- the pace drop must not look like cheating
	SpeedService.apply(player)
	return prep
end

local function endPrep(player: Player)
	local prep = preps[player]
	if not prep then
		return
	end
	preps[player] = nil
	local _, _, humanoid = body(player)
	if humanoid then
		humanoid.JumpPower, humanoid.JumpHeight = prep.jumpPower, prep.jumpHeight
	end
	player:SetAttribute("ArenaPrep", false)
	SpeedService.apply(player)
end

-- Keep a staged / running player inside their lane (beyond a tolerance; the
-- client's soft walls normally stop them first).
local function clampLane(player: Player, character: Model, root: BasePart, laneX: number)
	local position = root.Position
	local limit = HALF + CLAMP_TOLERANCE
	if math.abs(position.X - laneX) > limit or position.Y < 1 then
		SpeedService.markTeleport(
			player,
			Vector3.new(math.clamp(position.X, laneX - HALF, laneX + HALF), 3.5, position.Z)
		)
		root.AssemblyLinearVelocity = Vector3.zero
		local x = math.clamp(position.X, laneX - HALF, laneX + HALF)
		character:PivotTo(CFrame.new(x, 3.5, position.Z) * root.CFrame.Rotation)
	end
end

local function begin(
	player: Player,
	carry: CarryService.Carry,
	character: Model,
	root: BasePart,
	humanoid: Humanoid,
	prep: Prep
)
	local profile = DataService.get(player)
	local now = workspace:GetServerTimeNow()
	local level = Patterns.level(
		Rarity.INFO[carry.state.rarity].order,
		carry.originZone or Arena.FROM_ORIGIN_ZONE,
		if profile then profile.rebirths else 0
	)
	local normal = SpeedService.walkSpeedFor(if profile then profile.speed else 0, false, false)
	local laneX = prep.laneX
	preps[player] = nil
	active[player] = {
		carry = carry,
		character = character,
		humanoid = humanoid,
		laneX = laneX,
		zMin = WorldService.gateZ(Arena.FIELD_ZONE + 1),
		zMax = WorldService.gateZ(Arena.FIELD_ZONE),
		level = level,
		runSpeed = Patterns.runSpeed(normal),
		lives = Arena.LIVES,
		immuneUntil = 0,
		previous = Vector2.new(root.Position.X, root.Position.Z),
		nextWaveAt = now + Arena.FIRST_WAVE_DELAY,
		waves = {},
		lastKind = nil,
		nextId = 1,
		jumpPower = prep.jumpPower,
		jumpHeight = prep.jumpHeight,
	}
	humanoid.JumpPower, humanoid.JumpHeight = 0, 0
	player:SetAttribute("ArenaLaneX", laneX)
	player:SetAttribute("ArenaZMin", WorldService.gateZ(Arena.FIELD_ZONE + 1))
	player:SetAttribute("ArenaZMax", WorldService.gateZ(Arena.FIELD_ZONE))
	player:SetAttribute("ArenaStartedAt", now)
	player:SetAttribute("ArenaLives", Arena.LIVES)
	player:SetAttribute("ArenaLevel", level)
	player:SetAttribute("ArenaActive", true)
	player:SetAttribute("ArenaPrep", false)
	SpeedService.apply(player)
	Telemetry.custom(player, "ArenaStarted")
end

local function spawnWave(player: Player, run: Run, root: BasePart, now: number)
	local position = root.Position
	local progress = (position.Z - run.zMin) / (run.zMax - run.zMin)
	local effective = Patterns.effective(run.level, progress)
	local kind = Patterns.pickKind(effective, rng:NextNumber(), run.lastKind)
	run.lastKind = kind
	-- Aim where the runner will be once the telegraph ends, so running
	-- straight never leaves an attack behind. Lane-wide patterns stay on the
	-- lane centre line; targeted ones (ring, spears) follow the predicted spot.
	local velocity = root.AssemblyLinearVelocity
	local lead = Arena.LEAD_TIME + Patterns.warnTimeFor(effective) + 0.1
	local ahead = Vector2.new(velocity.X, velocity.Z) * lead
	if ahead.Magnitude > Arena.MAX_LEAD then
		ahead = ahead.Unit * Arena.MAX_LEAD
	end
	local predicted = Vector2.new(position.X, position.Z) + ahead
	local anchor = Patterns.anchor(kind)
	local x, z = run.laneX, predicted.Y
	if anchor == "player" or anchor == "predict" then
		x = math.clamp(predicted.X, run.laneX - HALF, run.laneX + HALF)
	end
	local wave: Patterns.Wave = {
		id = run.nextId,
		kind = kind,
		t0 = now + Arena.LEAD_TIME,
		x = x,
		z = math.min(z, run.zMax - 4),
		laneX = run.laneX,
		seed = rng:NextInteger(1, 1_000_000),
		level = effective,
		speed = Patterns.attackSpeed(effective, run.runSpeed),
	}
	run.nextId += 1
	table.insert(run.waves, wave)
	waveEvent:FireClient(player, wave)
	run.nextWaveAt = now + Patterns.interval(effective)
end

local function hitBy(run: Run, now: number, point: Vector2, moving: boolean): boolean
	local middle = (point + run.previous) / 2
	for _, wave in run.waves do
		for _, hazard in Patterns.sample(wave, now) do
			if Patterns.hits(hazard, point, moving) or Patterns.hits(hazard, middle, moving) then
				return true
			end
		end
	end
	return false
end

local function stepRun(player: Player, run: Run, root: BasePart, dt: number, now: number)
	local position = root.Position
	if position.Z > run.zMax then
		finish(player, "win")
		return
	end
	if position.Z < run.zMin - 4 then
		finish(player, "backtrack") -- back into the staging strip; re-crossing restarts
		return
	end
	clampLane(player, run.character, root, run.laneX)
	local point = Vector2.new(root.Position.X, root.Position.Z)
	local moving = (point - run.previous).Magnitude / math.max(dt, 1e-3) > Arena.STILL_SPEED

	for index = #run.waves, 1, -1 do
		local wave = run.waves[index]
		if now > wave.t0 + Patterns.duration(wave) then
			table.remove(run.waves, index)
		end
	end
	if now >= run.nextWaveAt and position.Z < run.zMax - FINAL_STRETCH then
		local progress = (position.Z - run.zMin) / (run.zMax - run.zMin)
		if #run.waves < Patterns.maxActive(Patterns.effective(run.level, progress)) then
			spawnWave(player, run, root, now)
		end
	end

	if now >= run.immuneUntil and hitBy(run, now, point, moving) then
		run.lives -= 1
		run.immuneUntil = now + Arena.INVULNERABLE_SECONDS
		player:SetAttribute("ArenaLives", run.lives)
		player:SetAttribute("ArenaIFramesUntil", run.immuneUntil)
		if run.lives <= 0 then
			finish(player, "hit")
			return
		end
	end
	run.previous = point
end

local function tick(dt: number)
	local now = workspace:GetServerTimeNow()
	for _, player in Players:GetPlayers() do
		if not SpeedService.validatePosition(player) then
			continue
		end
		local character, root, humanoid = body(player)
		local carry = CarryService.get(player)
		local run = active[player]
		if run then
			if not character or not root or character ~= run.character or carry ~= run.carry then
				finish(player, "cancel")
			else
				stepRun(player, run, root, dt, now)
			end
		elseif
			root
			and humanoid
			and character
			and carry
			and qualifies(carry)
			and completed[player] ~= carry
			and now >= (retryUntil[player] or 0)
		then
			local position = root.Position
			local zMax = WorldService.gateZ(Arena.FIELD_ZONE)
			local zMin = WorldService.gateZ(Arena.FIELD_ZONE + 1)
			local onTrack = math.abs(position.X) <= Economy.SERVER_SIZE * Arena.LANE_WIDTH / 2
				and position.Y >= 1
				and position.Y < 12
			local prep: Prep? = preps[player]
			if prep and prep.carry ~= carry then
				endPrep(player)
				prep = nil
			end
			if canStage(position) then
				-- Staging strip (or already in the corridor, e.g. a re-grabbed egg).
				local staged = prep or startPrep(player, carry, root, humanoid)
				if position.Z > zMin then
					begin(player, carry, character, root, humanoid, staged)
				else
					clampLane(player, character, root, staged.laneX)
				end
			elseif
				prep
				and (
					position.Z <= zMin - Arena.PREP_DEPTH - 6 -- turned back toward the crater
					or position.Z >= zMax - FINAL_STRETCH
					or not onTrack
				)
			then
				endPrep(player)
			end
		elseif preps[player] then
			endPrep(player) -- egg lost / delivered / not a deep egg any more
		end
		if not carry then
			completed[player] = nil
		end
	end
end

function ArenaService.isActive(player: Player): boolean
	return active[player] ~= nil
end

-- Pursuit runs every frame; staging is sampled at 30 Hz. Protect the valid
-- entry position immediately, before that heartbeat publishes ArenaPrep.
-- Use server-owned cargo/state so replicated flags cannot grant immunity.
function ArenaService.isProtected(player: Player): boolean
	if active[player] or preps[player] then
		return true
	end
	local carry = CarryService.get(player)
	local _, root = body(player)
	return carry ~= nil
		and qualifies(carry)
		and completed[player] ~= carry
		and workspace:GetServerTimeNow() >= (retryUntil[player] or 0)
		and root ~= nil
		and canStage(root.Position)
end

function ArenaService.init()
	CarryService.setDeliveryGuard(function(player, carry)
		return not qualifies(carry) or completed[player] == carry
	end)
	waveEvent = Remotes.event("ArenaWave")
	Players.PlayerRemoving:Connect(function(player)
		finish(player, "cancel")
		preps[player] = nil
		completed[player], retryUntil[player] = nil, nil
	end)
end

function ArenaService.start()
	local elapsed = 0
	RunService.Heartbeat:Connect(function(dt)
		elapsed += dt
		if elapsed >= Arena.SERVER_TICK then
			local stepTime = math.min(elapsed, 0.15)
			elapsed = 0
			tick(stepTime)
		end
	end)
end

return ArenaService

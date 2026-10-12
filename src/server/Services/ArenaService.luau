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

local ArenaService = {}
local active: { [Player]: Run } = {}
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

local function finish(player: Player, reason: string)
	local run = active[player]
	if not run then
		return
	end
	active[player] = nil
	player:SetAttribute("ArenaActive", false)
	player:SetAttribute("ArenaIFramesUntil", nil)
	if run.humanoid.Parent then
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

local function begin(
	player: Player,
	carry: CarryService.Carry,
	character: Model,
	root: BasePart,
	humanoid: Humanoid
)
	local profile = DataService.get(player)
	local now = workspace:GetServerTimeNow()
	local level = Patterns.level(
		Rarity.INFO[carry.state.rarity].order,
		carry.originZone or Arena.FROM_ORIGIN_ZONE,
		if profile then profile.rebirths else 0
	)
	local normal = SpeedService.walkSpeedFor(if profile then profile.speed else 0, false, false)
	local laneX = laneCenter(root.Position.X)
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
		jumpPower = humanoid.JumpPower,
		jumpHeight = humanoid.JumpHeight,
	}
	humanoid.JumpPower, humanoid.JumpHeight = 0, 0
	player:SetAttribute("ArenaLaneX", laneX)
	player:SetAttribute("ArenaZMin", WorldService.gateZ(Arena.FIELD_ZONE + 1))
	player:SetAttribute("ArenaZMax", WorldService.gateZ(Arena.FIELD_ZONE))
	player:SetAttribute("ArenaStartedAt", now)
	player:SetAttribute("ArenaLives", Arena.LIVES)
	player:SetAttribute("ArenaLevel", level)
	player:SetAttribute("ArenaActive", true)
	SpeedService.apply(player)
	Telemetry.custom(player, "ArenaStarted")
end

local function spawnWave(player: Player, run: Run, root: BasePart, now: number)
	local position = root.Position
	local progress = (position.Z - run.zMin) / (run.zMax - run.zMin)
	local effective = Patterns.effective(run.level, progress)
	local kind = Patterns.pickKind(effective, rng:NextNumber(), run.lastKind)
	run.lastKind = kind
	local anchor = Patterns.anchor(kind)
	local x, z = run.laneX, position.Z + Arena.AHEAD
	if anchor == "player" then
		x, z = position.X, position.Z
	elseif anchor == "predict" then
		local velocity = root.AssemblyLinearVelocity
		x = math.clamp(position.X + velocity.X * 0.7, run.laneX - HALF, run.laneX + HALF)
		z = position.Z + math.max(0, velocity.Z) * 0.7
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
		finish(player, "cancel") -- ran back into the crater; re-entering restarts
		return
	end
	-- Stay inside the lane (the client also has soft walls).
	local limit = HALF + CLAMP_TOLERANCE
	local x = math.clamp(position.X, run.laneX - limit, run.laneX + limit)
	if math.abs(position.X - x) > 0.1 or position.Y < 1 then
		x = math.clamp(position.X, run.laneX - HALF, run.laneX + HALF)
		SpeedService.markTeleport(player)
		root.AssemblyLinearVelocity = Vector3.zero
		run.character:PivotTo(CFrame.new(x, 3.5, position.Z) * root.CFrame.Rotation)
	end
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
			if
				position.Z <= zMax
				and position.Z > zMin
				and position.Z < zMax - FINAL_STRETCH
				and math.abs(position.X) <= Economy.SERVER_SIZE * Arena.LANE_WIDTH / 2
				and position.Y >= 1
				and position.Y < 12
			then
				begin(player, carry, character, root, humanoid)
			end
		end
		if not carry then
			completed[player] = nil
		end
	end
end

function ArenaService.isActive(player: Player): boolean
	return active[player] ~= nil
end

function ArenaService.init()
	waveEvent = Remotes.event("ArenaWave")
	Players.PlayerRemoving:Connect(function(player)
		finish(player, "cancel")
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

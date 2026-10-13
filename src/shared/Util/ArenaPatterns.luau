--!strict
-- Void Run attacks, inspired by Undertale's bullet boards (bone walls, blue /
-- orange attacks, Gaster Blasters, Undyne's spears, Flowey's pellet ring,
-- Muffet's crossfire, Asgore's sweeping bar, Toriel's fire streams), plus the
-- drone attacks of an open-field chase (bombs, spiral bursts, laser sweeps),
-- fired from the casting drone itself.
-- Pure functions of (wave, server time): the server checks hits and clients
-- render the same hazards, so no client can claim a dodge. All coordinates
-- are world X/Z packed into Vector2 (Y = world Z).
local Arena = require(script.Parent.Parent.Config.Arena)

export type Wave = {
	id: number,
	kind: string,
	t0: number, -- server time the wave begins (its telegraph starts here)
	x: number, -- anchor point (lane centre or target, depending on kind)
	z: number,
	laneX: number,
	seed: number, -- integer 1..1e6
	level: number, -- effective difficulty when spawned
	speed: number, -- attack speed multiplier
	-- Open-field waves: the pattern's "forward" (+Z, toward which the player
	-- runs) is turned to this axis-aligned world direction around (x, z).
	-- nil in the Void Run, where forward is always +Z.
	heading: Vector2?,
	-- Drone attacks: the casting drone's position, and the runner's direction
	-- of travel (unit). nil elsewhere.
	ox: number?,
	oz: number?,
	dx: number?,
	dz: number?,
}

export type Hazard = {
	id: string,
	shape: string, -- "circle" | "rect" | "capsule"
	position: Vector2, -- circle / rect centre; capsule start
	finish: Vector2?, -- capsule end
	radius: number, -- circle / capsule radius
	size: Vector2?, -- rect size (X, Z)
	warning: boolean, -- telegraph: never damages
	color: string, -- "white" | "blue" | "orange" | "red" | "amber"
	style: string?, -- render hint: "disc" | "bomb" | "blast" | "beam"
	y: number?, -- render height (a bomb in flight)
}

local Patterns = {}

local HALF = Arena.LANE_WIDTH / 2 - Arena.EDGE_MARGIN -- playable half width

-- Exact integer hash (doubles stay below 2^53), identical on every platform.
local function rand(seed: number, i: number): number
	local h = (seed * 7919 + i * 104729 + 12345) % 2147483647
	h = (h * 48271) % 2147483647
	h = (h * 48271) % 2147483647
	return h / 2147483647
end
Patterns.rand = rand

local function warnTime(wave: Wave): number
	return math.max(0.45, 0.9 - 0.3 * wave.level)
end

-- Telegraph length for a wave of this level (servers aim attacks where the
-- runner will be once it ends).
function Patterns.warnTimeFor(level: number): number
	return math.max(0.45, 0.9 - 0.3 * level)
end

-- Snap a horizontal direction to the nearest world axis (Vector2 = X, Z).
function Patterns.axisHeading(direction: Vector2): Vector2
	if direction.Magnitude < 1e-3 then
		return Vector2.new(0, 1)
	end
	if math.abs(direction.X) > math.abs(direction.Y) then
		return Vector2.new(if direction.X > 0 then 1 else -1, 0)
	end
	return Vector2.new(0, if direction.Y > 0 then 1 else -1)
end

-- Turn hazards built around (wave.x, wave.z) so local +Z points along
-- `heading` (axis-aligned, so rectangles stay axis-aligned for hit checks).
local function orient(out: { Hazard }, wave: Wave)
	local f = wave.heading :: Vector2
	if f.X == 0 and f.Y == 1 then
		return
	end
	local r = Vector2.new(f.Y, -f.X)
	local pivot = Vector2.new(wave.x, wave.z)
	local function turn(p: Vector2): Vector2
		local d = p - pivot
		return pivot + r * d.X + f * d.Y
	end
	local sideways = math.abs(f.X) > 0.5
	for _, hazard in out do
		hazard.position = turn(hazard.position)
		if hazard.finish then
			hazard.finish = turn(hazard.finish :: Vector2)
		end
		if hazard.size and sideways then
			local size = hazard.size :: Vector2
			hazard.size = Vector2.new(size.Y, size.X)
		end
	end
end

local function circle(
	out: { Hazard },
	id: string,
	position: Vector2,
	radius: number,
	warning: boolean,
	color: string?,
	style: string?,
	y: number?
)
	table.insert(out, {
		id = id,
		shape = "circle",
		position = position,
		radius = radius,
		warning = warning,
		color = color or "white",
		style = style,
		y = y,
	})
end

local function beam(
	out: { Hazard },
	id: string,
	from: Vector2,
	to: Vector2,
	radius: number,
	warning: boolean,
	color: string
)
	table.insert(out, {
		id = id,
		shape = "capsule",
		position = from,
		finish = to,
		radius = radius,
		warning = warning,
		color = color,
		style = "beam",
	})
end

local function rect(
	out: { Hazard },
	id: string,
	position: Vector2,
	size: Vector2,
	warning: boolean,
	color: string?
)
	table.insert(out, {
		id = id,
		shape = "rect",
		position = position,
		radius = 0,
		size = size,
		warning = warning,
		color = color or "white",
	})
end

-- Kinds, unlocked as the effective level rises. Weights favour the basics.
local POOL: { { kind: string, from: number, weight: number } } = {
	{ kind = "wall", from = 0, weight = 3 },
	{ kind = "crossfire", from = 0, weight = 3 },
	{ kind = "spears", from = 0, weight = 2 },
	{ kind = "ring", from = 0.15, weight = 2 },
	{ kind = "stream", from = 0.3, weight = 2 },
	{ kind = "blaster", from = 0.3, weight = 2 },
	{ kind = "blue", from = 0.55, weight = 1.5 },
	{ kind = "orange", from = 0.55, weight = 1 },
	{ kind = "sweeper", from = 0.6, weight = 1.5 },
}
Patterns.KINDS = table.freeze((function()
	local list = {}
	for _, entry in POOL do
		table.insert(list, entry.kind)
	end
	return list
end)())

-- Where the server anchors a wave: "lane" = ahead on the lane centre line,
-- "player" = the player's position, "predict" = where the player will be.
local ANCHOR: { [string]: string } = {
	wall = "lane",
	crossfire = "lane",
	stream = "lane",
	blaster = "lane",
	blue = "lane",
	orange = "lane",
	sweeper = "lane",
	ring = "player",
	spears = "predict",
}
function Patterns.anchor(kind: string): string
	return ANCHOR[kind] or "lane"
end

-- Base difficulty of a run: rarer eggs, deeper zones and rebirths are harder.
function Patterns.level(rarityOrder: number, originZone: number, rebirths: number): number
	local level = 0.12 * (rarityOrder - 1)
		+ 0.15 * math.max(0, originZone - Arena.FROM_ORIGIN_ZONE)
		+ 0.04 * math.min(rebirths, 10)
	return math.clamp(level, 0, Arena.MAX_LEVEL)
end

-- Attacks intensify the closer the player gets to home.
function Patterns.effective(level: number, progress: number): number
	return math.clamp(level + 0.5 * math.clamp(progress, 0, 1), 0, Arena.MAX_LEVEL)
end

function Patterns.interval(effective: number): number
	return math.max(0.85, 2.3 - 0.9 * effective)
end

function Patterns.maxActive(effective: number): number
	return 2 + math.floor(effective * 1.5)
end

-- Faster runners face faster attacks (reaction time stays fair).
function Patterns.attackSpeed(effective: number, runSpeed: number): number
	return (1 + 0.35 * effective) * math.sqrt(math.clamp(runSpeed / 24, 1, 1.6))
end

function Patterns.runSpeed(normalWalkSpeed: number): number
	return math.clamp(
		normalWalkSpeed * Arena.WALK_SPEED_SHARE,
		Arena.WALK_SPEED_MIN,
		Arena.WALK_SPEED_MAX
	)
end

-- Weighted pick among unlocked kinds, never the same kind twice in a row.
function Patterns.pickKind(effective: number, roll: number, last: string?): string
	local total = 0
	for _, entry in POOL do
		if effective >= entry.from and entry.kind ~= last then
			total += entry.weight
		end
	end
	local target = roll * total
	for _, entry in POOL do
		if effective >= entry.from and entry.kind ~= last then
			target -= entry.weight
			if target <= 0 then
				return entry.kind
			end
		end
	end
	return if last == "wall" then "crossfire" else "wall"
end

local function blasterCount(wave: Wave): number
	return math.min(3, 1 + math.floor(wave.level * 1.6))
end

local function crossfireCount(wave: Wave): number
	return 6 + math.floor(4 * wave.level)
end

-- Drone attacks -------------------------------------------------------------

local BOMB_BLAST = 5.5 -- burst radius
local BOMB_SPACING = 9 -- along the runner's path
local BOMB_FLY = 0.45 -- throw to landing
local BOMB_STAGGER = 0.12 -- between consecutive throws
local SHRAPNEL_TIME = 0.7
local SPIRAL_EMIT = 1.6 -- seconds of firing
local SPIRAL_EVERY = 0.08
local SPIRAL_RANGE = 70
local SPIRAL_SPREAD = math.rad(45) -- either side of the aim
local LASER_LENGTH = 48
local LASER_SWEEP = math.rad(110)
local LASER_TIME = 1.1

local function droneOrigin(wave: Wave): Vector2
	return Vector2.new(wave.ox or wave.x, wave.oz or wave.z)
end

local function pathDirection(wave: Wave): Vector2
	local d = Vector2.new(wave.dx or 0, wave.dz or 1)
	return if d.Magnitude > 1e-3 then d.Unit else Vector2.new(0, 1)
end

-- From the drone toward the target (the runner's predicted spot).
local function aimOf(wave: Wave): Vector2
	local d = Vector2.new(wave.x, wave.z) - droneOrigin(wave)
	return if d.Magnitude > 1e-3 then d.Unit else pathDirection(wave)
end

local function bombCount(wave: Wave): number
	return 3 + math.floor(2 * wave.level)
end

local function bombBurst(i: number, warn: number): number
	return (i - 1) * BOMB_STAGGER + BOMB_FLY + warn
end

local function spiralArms(wave: Wave): number
	return 2 + math.floor(2.5 * wave.level)
end

-- Seconds from t0 the casting drone holds still while its attack pours out.
function Patterns.castTime(wave: Wave): number
	local warn = warnTime(wave)
	if wave.kind == "bombs" then
		return (bombCount(wave) - 1) * BOMB_STAGGER + 0.25
	elseif wave.kind == "spiral" then
		return warn + SPIRAL_EMIT
	elseif wave.kind == "laser" then
		return warn + LASER_TIME / wave.speed
	end
	return 0
end

-- Seconds from t0 until a drone attack bites (servers aim it where the runner
-- will be by then).
function Patterns.leadFor(kind: string, level: number): number
	local warn = Patterns.warnTimeFor(level)
	if kind == "bombs" then
		local middle = (2 + math.floor(2 * level)) / 2
		return middle * BOMB_STAGGER + BOMB_FLY + warn
	elseif kind == "spiral" or kind == "laser" then
		return warn + 0.3
	end
	return warn + 0.1
end

-- Seconds from t0 until the wave has fully played out.
function Patterns.duration(wave: Wave): number
	local warn, s = warnTime(wave), wave.speed
	local kind = wave.kind
	if kind == "wall" or kind == "blue" or kind == "orange" then
		return warn + 6 / s
	elseif kind == "blaster" then
		return (blasterCount(wave) - 1) * 0.45 + warn + 0.25 + 0.45
	elseif kind == "spears" then
		return warn + 0.15 + 0.35 + (if wave.level > 0.5 then 0.5 else 0)
	elseif kind == "ring" then
		return warn + 20 / (8 * s)
	elseif kind == "crossfire" then
		return (crossfireCount(wave) - 1) * 0.22 / s + warn + (2 * HALF + 4) / (22 * s)
	elseif kind == "sweeper" then
		return warn + 3.2
	elseif kind == "stream" then
		return warn + 2.6 + 110 / (16 * s)
	elseif kind == "bombs" then
		return bombBurst(bombCount(wave), warn) + SHRAPNEL_TIME
	elseif kind == "spiral" then
		return warn + SPIRAL_EMIT + SPIRAL_RANGE / (30 * s)
	elseif kind == "laser" then
		return warn + LASER_TIME / s
	end
	return 0
end

local function walls(out: { Hazard }, wave: Wave, age: number, warn: number)
	local s = wave.speed
	local count = if wave.level > 0.6 then 2 else 1
	for w = 1, count do
		local gapWidth = math.max(9, 14 - 4 * wave.level)
		local gap = (rand(wave.seed, w) * 2 - 1) * (HALF - gapWidth / 2 - 1)
		local z = wave.z + 20 + (w - 1) * 16 - math.max(0, age - warn) * 14 * s
		local warning = age < warn
		local left, right = -HALF - 2, HALF + 2
		local a, b = gap - gapWidth / 2, gap + gapWidth / 2
		rect(
			out,
			`{wave.id}:w{w}L`,
			Vector2.new(wave.laneX + (left + a) / 2, z),
			Vector2.new(a - left, 1.6),
			warning
		)
		rect(
			out,
			`{wave.id}:w{w}R`,
			Vector2.new(wave.laneX + (b + right) / 2, z),
			Vector2.new(right - b, 1.6),
			warning
		)
	end
end

local function colored(out: { Hazard }, wave: Wave, age: number, warn: number, color: string)
	local z = wave.z + 20 - math.max(0, age - warn) * 13 * wave.speed
	rect(
		out,
		`{wave.id}:{color}`,
		Vector2.new(wave.laneX, z),
		Vector2.new(2 * HALF + 4, 2.2),
		age < warn,
		color
	)
end

local function blasters(out: { Hazard }, wave: Wave, age: number, warn: number)
	for b = 1, blasterCount(wave) do
		local since = age - (b - 1) * 0.45
		local charge = warn + 0.25
		if since >= 0 and since <= charge + 0.45 then
			local warning = since < charge
			if rand(wave.seed, b) < 0.5 then
				-- Across the lane, ahead of the player.
				local z = wave.z + (rand(wave.seed, b + 10) * 2 - 1) * 12
				rect(
					out,
					`{wave.id}:b{b}`,
					Vector2.new(wave.laneX, z),
					Vector2.new(2 * HALF + 4, 6),
					warning
				)
			else
				-- Down a column toward the player.
				local x = wave.laneX + (rand(wave.seed, b + 10) * 2 - 1) * (HALF - 4)
				rect(
					out,
					`{wave.id}:b{b}`,
					Vector2.new(x, wave.z - 10),
					Vector2.new(6, 80),
					warning
				)
			end
		end
	end
end

local function spears(out: { Hazard }, wave: Wave, age: number, warn: number)
	local rounds = if wave.level > 0.5 then 2 else 1
	local count = 5 + math.floor(3 * wave.level)
	for round = 1, rounds do
		local since = age - (round - 1) * 0.5
		local charge = warn + 0.15
		if since >= 0 and since <= charge + 0.35 then
			local radius = if round == 1 then 7 else 12
			local spin = rand(wave.seed, round) * math.pi * 2
			for i = 0, count - 1 do
				local position = if round == 1 and i == 0
					then Vector2.new(wave.x, wave.z)
					else Vector2.new(wave.x, wave.z) + Vector2.new(
						math.cos(spin + i * 2 * math.pi / count),
						math.sin(spin + i * 2 * math.pi / count)
					) * radius
				if math.abs(position.X - wave.laneX) <= HALF + 2 then
					circle(out, `{wave.id}:s{round}_{i}`, position, 2.4, since < charge)
				end
			end
		end
	end
end

local function ring(out: { Hazard }, wave: Wave, age: number, warn: number)
	local count = 14 + math.floor(6 * wave.level)
	local radius = 20 - math.max(0, age - warn) * 8 * wave.speed
	if radius < 1 then
		return
	end
	-- The gap faces the lane centre, so it is never behind a lane wall.
	local dx = wave.laneX - wave.x
	local gapAngle = if math.abs(dx) < 6
		then rand(wave.seed, 1) * math.pi * 2
		else (if dx > 0 then 0 else math.pi) + (rand(wave.seed, 1) - 0.5) * 0.6
	for i = 2, count - 2 do
		local angle = gapAngle + i * 2 * math.pi / count
		circle(
			out,
			`{wave.id}:r{i}`,
			Vector2.new(wave.x + math.cos(angle) * radius, wave.z + math.sin(angle) * radius),
			1.1,
			age < warn
		)
	end
end

local function crossfire(out: { Hazard }, wave: Wave, age: number, warn: number)
	local s = wave.speed
	for b = 1, crossfireCount(wave) do
		local since = age - (b - 1) * 0.22 / s
		if since >= 0 then
			local side = if b % 2 == 0 then 1 else -1
			local travel = math.max(0, since - warn) * 22 * s
			if travel <= 2 * HALF + 4 then
				local z = wave.z - 6 + (rand(wave.seed, b) * 2 - 1) * 16
				local x = wave.laneX + side * (HALF + 2) - side * travel
				circle(out, `{wave.id}:c{b}`, Vector2.new(x, z), 1.2, since < warn)
			end
		end
	end
end

local function sweeper(out: { Hazard }, wave: Wave, age: number, warn: number)
	local pivot = Vector2.new(wave.laneX + (rand(wave.seed, 1) * 2 - 1) * 10, wave.z + 6)
	local arms = if wave.level > 0.8 then 2 else 1
	local direction = if rand(wave.seed, 2) < 0.5 then -1 else 1
	local omega = (1.2 + 0.5 * wave.level) * wave.speed * direction
	local base = rand(wave.seed, 3) * math.pi + math.max(0, age - warn) * omega
	for arm = 1, arms do
		local angle = base + (arm - 1) * math.pi / 2
		local reach = Vector2.new(math.cos(angle), math.sin(angle)) * 18
		table.insert(out, {
			id = `{wave.id}:sw{arm}`,
			shape = "capsule",
			position = pivot - reach,
			finish = pivot + reach,
			radius = 1,
			warning = age < warn,
			color = "white",
		})
	end
end

local function stream(out: { Hazard }, wave: Wave, age: number, warn: number)
	local s = wave.speed
	local streams = if wave.level > 0.7 then 2 else 1
	local amplitude = HALF * 0.75
	local emitZ = wave.z + 40
	for st = 1, streams do
		local phase = rand(wave.seed, 1) * math.pi * 2 + (st - 1) * math.pi
		if age < warn then
			circle(
				out,
				`{wave.id}:e{st}`,
				Vector2.new(wave.laneX + amplitude * math.sin(phase), emitZ),
				2,
				true
			)
		end
		for k = 0, 23 do
			local emitted = warn + k * 0.11
			if age >= emitted then
				local z = emitZ - (age - emitted) * 16 * s
				if z > wave.z - 70 then
					circle(
						out,
						`{wave.id}:t{st}_{k}`,
						Vector2.new(wave.laneX + amplitude * math.sin(phase + k * 0.28), z),
						1,
						false
					)
				end
			end
		end
	end
end

-- Bombs: the drone lobs a row of bombs along the runner's path; each lands on
-- a marked spot, bursts, and throws a ring of shrapnel outward.
local function bombs(out: { Hazard }, wave: Wave, age: number, warn: number)
	local from = droneOrigin(wave)
	local along = pathDirection(wave)
	local side = Vector2.new(along.Y, -along.X)
	local count = bombCount(wave)
	local shards = 8 + math.floor(4 * wave.level)
	for i = 1, count do
		local launch = (i - 1) * BOMB_STAGGER
		local burst = bombBurst(i, warn)
		if age < launch then
			continue
		end
		local spot = Vector2.new(wave.x, wave.z)
			+ along * ((i - (count + 1) / 2) * BOMB_SPACING)
			+ side * ((rand(wave.seed, i) * 2 - 1) * 6)
		if age < burst then
			circle(out, `{wave.id}:m{i}`, spot, BOMB_BLAST, true, "amber", "disc")
			local f = math.clamp((age - launch) / BOMB_FLY, 0, 1)
			local height = 4 * (1 - f) + 7 * math.sin(math.pi * f) + 0.8
			circle(out, `{wave.id}:o{i}`, from:Lerp(spot, f), 1.2, true, "amber", "bomb", height)
		elseif age < burst + 0.18 then
			circle(out, `{wave.id}:x{i}`, spot, BOMB_BLAST, false, "amber", "blast")
		end
		local flight = age - burst
		if flight >= 0 and flight <= SHRAPNEL_TIME then
			local spin = rand(wave.seed, i + 50) * math.pi * 2
			for k = 0, shards - 1 do
				local a = spin + k * 2 * math.pi / shards
				local reach = BOMB_BLAST * 0.5 + flight * 26 * wave.speed
				circle(
					out,
					`{wave.id}:p{i}_{k}`,
					spot + Vector2.new(math.cos(a), math.sin(a)) * reach,
					0.9,
					false,
					"amber"
				)
			end
		end
	end
end

-- Spiral: the drone charges, then sprays weaving arms of pellets in a cone
-- toward where the runner is heading.
local function spiral(out: { Hazard }, wave: Wave, age: number, warn: number)
	local from = droneOrigin(wave)
	local aim = aimOf(wave)
	if age < warn then
		circle(out, `{wave.id}:c`, from, 2.5, true, "red", "disc")
		beam(out, `{wave.id}:aim`, from, from + aim * 30, 0.4, true, "red")
	end
	local base = math.atan2(aim.Y, aim.X)
	local turn = if rand(wave.seed, 1) < 0.5 then -1 else 1
	local arms = spiralArms(wave)
	local speed = 30 * wave.speed
	for k = 0, math.floor(SPIRAL_EMIT / SPIRAL_EVERY) do
		local distance = (age - warn - k * SPIRAL_EVERY) * speed
		if distance >= 0 and distance <= SPIRAL_RANGE then
			for arm = 1, arms do
				local a = base
					+ turn * SPIRAL_SPREAD * math.sin(k * 0.45 + arm * 2 * math.pi / arms)
				circle(
					out,
					`{wave.id}:{k}_{arm}`,
					from + Vector2.new(math.cos(a), math.sin(a)) * (1.5 + distance),
					0.9,
					false,
					"red"
				)
			end
		end
	end
end

-- Laser: the drone sweeps a beam across the runner's path; both ends of the
-- sweep are marked first.
local function laser(out: { Hazard }, wave: Wave, age: number, warn: number)
	local from = droneOrigin(wave)
	local aim = aimOf(wave)
	local base = math.atan2(aim.Y, aim.X)
	local turn = if rand(wave.seed, 1) < 0.5 then -1 else 1
	local start = base - turn * LASER_SWEEP / 2
	local function tip(a: number): Vector2
		return from + Vector2.new(math.cos(a), math.sin(a)) * LASER_LENGTH
	end
	if age < warn then
		beam(out, `{wave.id}:a`, from, tip(start), 0.35, true, "red")
		beam(out, `{wave.id}:b`, from, tip(start + turn * LASER_SWEEP), 0.35, true, "red")
		return
	end
	local f = math.clamp((age - warn) * wave.speed / LASER_TIME, 0, 1)
	beam(out, `{wave.id}:l`, from, tip(start + turn * LASER_SWEEP * f), 1.1, false, "red")
end

local BUILDERS: { [string]: (out: { Hazard }, wave: Wave, age: number, warn: number) -> () } = {
	bombs = bombs,
	spiral = spiral,
	laser = laser,
	wall = walls,
	blaster = blasters,
	spears = spears,
	ring = ring,
	crossfire = crossfire,
	sweeper = sweeper,
	stream = stream,
	blue = function(out, wave, age, warn)
		colored(out, wave, age, warn, "blue")
	end,
	orange = function(out, wave, age, warn)
		colored(out, wave, age, warn, "orange")
	end,
}

function Patterns.sample(wave: Wave, now: number): { Hazard }
	local out: { Hazard } = {}
	local age = now - wave.t0
	if age < 0 or age > Patterns.duration(wave) then
		return out
	end
	local builder = BUILDERS[wave.kind]
	if builder then
		builder(out, wave, age, warnTime(wave))
	end
	if wave.heading then
		orient(out, wave)
	end
	return out
end

-- Blue attacks only hurt a moving player, orange only a still one.
function Patterns.hits(hazard: Hazard, point: Vector2, moving: boolean): boolean
	if hazard.warning then
		return false
	end
	if hazard.color == "blue" and not moving then
		return false
	end
	if hazard.color == "orange" and moving then
		return false
	end
	local reach = Arena.PLAYER_RADIUS
	if hazard.shape == "circle" then
		return (point - hazard.position).Magnitude <= hazard.radius + reach
	elseif hazard.shape == "rect" then
		local size = hazard.size :: Vector2
		local d = point - hazard.position
		return math.abs(d.X) <= size.X / 2 + reach and math.abs(d.Y) <= size.Y / 2 + reach
	end
	local a, b = hazard.position, hazard.finish :: Vector2
	local ab = b - a
	local t = math.clamp((point - a):Dot(ab) / math.max(ab:Dot(ab), 1e-6), 0, 1)
	return (a + ab * t - point).Magnitude <= hazard.radius + reach
end

return table.freeze(Patterns)

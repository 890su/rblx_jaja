--!strict
-- Geometry and steering only. The server owns membership, slot order, attack
-- admission and collision checks; no drone teleports to the targets below.
local ChasePlan = {}

export type Role = "pressure" | "flank" | "intercept"
export type Formation = {
	trailDistance: number,
	flankDistance: number,
	flankAhead: number,
	interceptSeconds: number,
	minLead: number,
	maxLead: number,
}
export type Steering = {
	acceleration: number,
	turnRate: number,
	arrivalSeconds: number,
}

local EPSILON = 1e-5
local FORWARD = Vector3.new(0, 0, -1)

local function flat(value: Vector3): Vector3
	return Vector3.new(value.X, 0, value.Z)
end

local function unit(value: Vector3, fallback: Vector3): Vector3
	local horizontal = flat(value)
	if horizontal.Magnitude > EPSILON then
		return horizontal.Unit
	end
	local backup = flat(fallback)
	return if backup.Magnitude > EPSILON then backup.Unit else FORWARD
end

local function rotateToward(previous: Vector3, desired: Vector3, maxAngle: number): Vector3
	local angle = math.atan2(previous.X * desired.Z - previous.Z * desired.X, previous:Dot(desired))
	local step = math.clamp(angle, -maxAngle, maxAngle)
	local cosine, sine = math.cos(step), math.sin(step)
	return Vector3.new(
		previous.X * cosine - previous.Z * sine,
		0,
		previous.X * sine + previous.Z * cosine
	)
end

function ChasePlan.role(slot: number, count: number): Role
	if slot <= 1 then
		return "pressure"
	end
	if count >= 3 and slot == count then
		return "intercept"
	end
	return "flank"
end

-- Keep a stable heading at a stop and during jitter below minSpeed. A sharp
-- turn changes formation over time instead of instantly flipping its targets.
function ChasePlan.heading(
	previous: Vector3,
	velocity: Vector3,
	fallback: Vector3,
	dt: number,
	turnRate: number,
	minSpeed: number
): Vector3
	local before = unit(previous, fallback)
	local movement = flat(velocity)
	if movement.Magnitude <= math.max(EPSILON, minSpeed) then
		return before
	end
	return rotateToward(before, movement.Unit, math.max(0, turnRate) * math.max(0, dt))
end

function ChasePlan.target(
	playerPosition: Vector3,
	heading: Vector3,
	carrierSpeed: number,
	slot: number,
	count: number,
	formation: Formation
): Vector3
	local forward = unit(heading, FORWARD)
	local right = Vector3.new(-forward.Z, 0, forward.X)
	local role = ChasePlan.role(slot, count)
	if role == "pressure" then
		return playerPosition - forward * math.max(0, formation.trailDistance)
	elseif role == "intercept" then
		local minLead = math.max(0, formation.minLead)
		local lead = math.clamp(
			math.max(0, carrierSpeed) * math.max(0, formation.interceptSeconds),
			minLead,
			math.max(minLead, formation.maxLead)
		)
		return playerPosition + forward * lead
	end
	local side = if slot % 2 == 0 then -1 else 1
	return playerPosition
		+ forward * formation.flankAhead
		+ right * (side * math.max(0, formation.flankDistance))
end

-- Pairwise soft repulsion, capped at separationDistance. The caller supplies
-- an opposite direction per stable pair when two guards occupy the same spot.
function ChasePlan.separation(
	position: Vector3,
	neighborPosition: Vector3,
	separationDistance: number,
	overlapDirection: Vector3
): Vector3
	local distanceLimit = math.max(0, separationDistance)
	local delta = flat(position - neighborPosition)
	local distance = delta.Magnitude
	if distance >= distanceLimit then
		return Vector3.zero
	end
	return unit(delta, overlapDirection) * (distanceLimit - distance)
end

-- Acceleration bounds apply to the full velocity change, including turning.
-- Deceleration is gradual when desiredSpeed drops; callers never snap a drone
-- to its role target. Collision avoidance can alter deltaToTarget beforehand.
function ChasePlan.steer(
	velocity: Vector3,
	deltaToTarget: Vector3,
	desiredSpeed: number,
	dt: number,
	steering: Steering
): Vector3
	local before = flat(velocity)
	local step = math.max(0, dt)
	local acceleration = math.max(0, steering.acceleration) * step
	if acceleration <= 0 then
		return before
	end
	local delta = flat(deltaToTarget)
	local targetSpeed = math.max(0, desiredSpeed)
	-- Arrival-time easing alone starts braking too late at high chase speeds.
	-- Respect stopping distance v^2/(2a) while retaining acceleration limits.
	targetSpeed =
		math.min(targetSpeed, math.sqrt(2 * math.max(0, steering.acceleration) * delta.Magnitude))
	if steering.arrivalSeconds > EPSILON then
		targetSpeed = math.min(targetSpeed, delta.Magnitude / steering.arrivalSeconds)
	elseif delta.Magnitude <= EPSILON then
		targetSpeed = 0
	end
	local direction = unit(delta, before)
	if before.Magnitude > EPSILON then
		-- Brake before an about-face. Accelerating along a bounded turn while
		-- the target is behind makes an arrival overshoot grow into an orbit.
		targetSpeed *= math.max(0, before.Unit:Dot(direction))
		direction = rotateToward(before.Unit, direction, math.max(0, steering.turnRate) * step)
	end
	local desired = direction * targetSpeed
	local difference = desired - before
	if difference.Magnitude > acceleration then
		return before + difference.Unit * acceleration
	end
	return desired
end

return table.freeze(ChasePlan)

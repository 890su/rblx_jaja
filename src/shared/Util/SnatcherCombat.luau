--!strict
local Config = require(script.Parent.Parent.Config.Snatchers)
local Combat = {}

function Combat.chaseSpeed(carrierSpeed: number, factor: number): number
	return math.clamp(carrierSpeed * factor, Config.MIN_SPEED, Config.MAX_CHASE_SPEED)
end

function Combat.plan(origin: Vector3, target: Vector3, distance: number?): (Vector3, Vector3)
	local delta = Vector3.new(target.X - origin.X, 0, target.Z - origin.Z)
	local direction = if delta.Magnitude > 0.01 then delta.Unit else Vector3.new(0, 0, 1)
	-- Lock the line at the beginning of the warning. Never home during a dash.
	return direction, origin + direction * (distance or Config.DASH_DISTANCE)
end

function Combat.hits(
	from: Vector3,
	to: Vector3,
	playerBefore: Vector3,
	playerNow: Vector3,
	radius: number?
): boolean
	local a = Vector2.new(from.X - playerBefore.X, from.Z - playerBefore.Z)
	local b = Vector2.new(to.X - playerNow.X, to.Z - playerNow.Z)
	local line = b - a
	local t = if line:Dot(line) > 1e-6 then math.clamp(-a:Dot(line) / line:Dot(line), 0, 1) else 0
	return (a + line * t).Magnitude <= (radius or Config.HIT_RADIUS)
end

-- Can a guard at `origin` facing `facing` (horizontal) see `point`? Inside
-- the vision sector, or anywhere within the hearing circle.
function Combat.inVision(origin: Vector3, facing: Vector3, point: Vector3): boolean
	local d = Vector2.new(point.X - origin.X, point.Z - origin.Z)
	local distance = d.Magnitude
	if distance <= Config.HEARING_RADIUS then
		return true
	end
	if distance > Config.VISION_RANGE + 1 then
		return false
	end
	local flat = Vector2.new(facing.X, facing.Z)
	if flat.Magnitude < 1e-3 then
		return false
	end
	local cos = d:Dot(flat.Unit) / distance
	-- Widen by the body radius at this distance so edges are not pixel-exact.
	local slack = math.asin(math.min(1, 1 / distance))
	return cos >= math.cos(Config.VISION_HALF_ANGLE + slack)
end

-- Alert meter fill per second for a carrier inside a beam.
function Combat.alertRate(moving: boolean, zone: number): number
	local rate = if moving then Config.ALERT_FILL_MOVING else Config.ALERT_FILL_STILL
	return if zone <= 1 then rate * Config.ALERT_FIRST_ZONE_SCALE else rate
end

return table.freeze(Combat)

--!strict
local Config = require(script.Parent.Parent.Config.Snatchers)
local Combat = {}

function Combat.chaseSpeed(carrierSpeed: number, factor: number): number
	return math.clamp(carrierSpeed * factor, Config.MIN_SPEED, Config.MAX_CHASE_SPEED)
end

function Combat.plan(origin: Vector3, target: Vector3): (Vector3, Vector3)
	local delta = Vector3.new(target.X - origin.X, 0, target.Z - origin.Z)
	local direction = if delta.Magnitude > 0.01 then delta.Unit else Vector3.new(0, 0, 1)
	-- Lock the line at the beginning of the warning. Never home during a dash.
	return direction, origin + direction * Config.DASH_DISTANCE
end

function Combat.hits(from: Vector3, to: Vector3, playerBefore: Vector3, playerNow: Vector3): boolean
	local a = Vector2.new(from.X - playerBefore.X, from.Z - playerBefore.Z)
	local b = Vector2.new(to.X - playerNow.X, to.Z - playerNow.Z)
	local line = b - a
	local t = if line:Dot(line) > 1e-6 then math.clamp(-a:Dot(line) / line:Dot(line), 0, 1) else 0
	return (a + line * t).Magnitude <= Config.HIT_RADIUS
end

return table.freeze(Combat)

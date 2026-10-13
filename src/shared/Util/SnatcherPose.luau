--!strict
-- Presentation only. Server simulation and swept collision checks remain authoritative.
export type Snapshot = {
	id: number,
	cf: CFrame,
	time: number,
	phase: string,
	dashOrigin: Vector3?,
	dashEnd: Vector3?,
	dashStart: number?,
	dashSpeed: number?,
}

local Pose = {}
local Config = require(script.Parent.Parent.Config.Snatchers)
Pose.INTERPOLATION_SECONDS = Config.MOTION_INTERPOLATION_SECONDS
Pose.EXTRAPOLATION_SECONDS = Config.MOTION_EXTRAPOLATION_SECONDS
Pose.PHASE_BLEND_SECONDS = Config.MOTION_PHASE_BLEND_SECONDS

function Pose.transition(from: CFrame, target: CFrame, elapsed: number): CFrame
	if elapsed <= 0 then
		return from
	elseif elapsed >= Pose.PHASE_BLEND_SECONDS then
		return target
	end
	local fraction = elapsed / Pose.PHASE_BLEND_SECONDS
	return from:Lerp(target, fraction * fraction * (3 - 2 * fraction))
end

function Pose.isNewer(current: Snapshot?, incoming: Snapshot): boolean
	return current == nil or incoming.time > current.time
end

local function positionAt(cf: CFrame, at: Vector3): CFrame
	return CFrame.new(at) * cf.Rotation
end

function Pose.sample(previous: Snapshot?, current: Snapshot, now: number): CFrame
	local origin, endpoint = current.dashOrigin, current.dashEnd
	local start, speed = current.dashStart, current.dashSpeed
	if
		(current.phase == "lock" or current.phase == "dash")
		and origin ~= nil
		and endpoint ~= nil
		and start ~= nil
		and speed ~= nil
		and speed > 0
	then
		-- Lock announces the entire segment before it starts. Network snapshots
		-- never restart this motion, and a missed end packet cannot overshoot it.
		local delta = endpoint - origin
		local length = delta.Magnitude
		local distance = math.clamp((now - start) * speed, 0, length)
		local at = if length > 0.001 then origin + delta * (distance / length) else endpoint
		-- Preserve the last server bob height; X/Z follow the collision segment.
		at = Vector3.new(at.X, current.cf.Position.Y, at.Z)
		return positionAt(current.cf, at)
	end
	if current.phase == "cast" or current.phase == "warning" then
		return current.cf
	end
	if previous == nil or previous.phase ~= current.phase then
		return current.cf
	end
	local interval = current.time - previous.time
	if
		interval <= 0
		or interval > 0.5
		or (current.cf.Position - previous.cf.Position).Magnitude > 100
	then
		return current.cf -- reacquisition, teleport or a long network stall
	end
	local renderTime = now - Pose.INTERPOLATION_SECONDS
	if renderTime <= current.time then
		return previous.cf:Lerp(
			current.cf,
			math.clamp((renderTime - previous.time) / interval, 0, 1)
		)
	end
	local ahead = math.clamp(renderTime - current.time, 0, Pose.EXTRAPOLATION_SECONDS)
	local velocity = (current.cf.Position - previous.cf.Position) / interval
	return positionAt(current.cf, current.cf.Position + velocity * ahead)
end

return table.freeze(Pose)

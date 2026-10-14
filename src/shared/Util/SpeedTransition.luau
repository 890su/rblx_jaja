--!strict
-- An approved server speed reduction has a short replication delay followed
-- by the same braking duration used by the client. It never resets position
-- trust or adds a fresh movement allowance per remote/validation call.
local Speed = require(script.Parent.Parent.Config.Speed)
local SpeedTransition = {}
export type State = { from: number, to: number, at: number }

function SpeedTransition.rate(state: State?, target: number, now: number): number
	if not state then
		return target
	end
	local elapsed = math.max(0, now - state.at - Speed.PHYSICS.replicationGrace)
	local fraction = math.clamp(elapsed / Speed.PHYSICS.brakeSeconds, 0, 1)
	return math.max(target, state.from + (state.to - state.from) * fraction)
end

function SpeedTransition.needsFreshSample(state: State?, sampledAt: number): boolean
	return state ~= nil
		and sampledAt < state.at + Speed.PHYSICS.replicationGrace + Speed.PHYSICS.brakeSeconds
end

return table.freeze(SpeedTransition)

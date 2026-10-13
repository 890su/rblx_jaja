--!strict
-- Latency slack is a bounded pool, not a fresh allowance per interaction.
local MovementBudget = {}
export type State = { position: Vector3, at: number, budget: number }

function MovementBudget.isFinite(position: Vector3): boolean
	return position.X == position.X
		and position.Y == position.Y
		and position.Z == position.Z
		and math.abs(position.X) < math.huge
		and math.abs(position.Y) < math.huge
		and math.abs(position.Z) < math.huge
end

function MovementBudget.accept(state: State, position: Vector3, now: number, speed: number): boolean
	if not MovementBudget.isFinite(position) then
		return false
	end
	local elapsed = math.max(0, now - state.at)
	local allowance = math.min(25 + speed * 1.6, state.budget + speed * elapsed * 1.6)
	local delta =
		Vector3.new(position.X - state.position.X, 0, position.Z - state.position.Z).Magnitude
	if delta > allowance then
		return false
	end
	state.position, state.at, state.budget = position, now, allowance - delta
	return true
end

return table.freeze(MovementBudget)

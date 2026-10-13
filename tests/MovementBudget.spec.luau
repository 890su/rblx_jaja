--!strict
local Budget = require(game:GetService("ReplicatedStorage").Shared.Util.MovementBudget)
local passed = 0
local function check(name: string, value: boolean)
	assert(value, name)
	passed += 1
end
local state = { position = Vector3.zero, at = 0, budget = 25 }
check("ordinary movement", Budget.accept(state, Vector3.new(16, 0, 0), 1, 16))
check("instant long teleport rejected", not Budget.accept(state, Vector3.new(500, 0, 0), 1, 16))
check("rejected position not trusted", state.position.X == 16)
for i = 1, 100 do
	check(
		"normal running with variable tick",
		Budget.accept(state, state.position + Vector3.new(16, 0, 0), 1 + i, 16)
	)
end
local spam = { position = Vector3.zero, at = 0, budget = 25 }
check("first latency allowance", Budget.accept(spam, Vector3.new(20, 0, 0), 0, 16))
check(
	"interaction spam cannot replenish slack",
	not Budget.accept(spam, Vector3.new(40, 0, 0), 0, 16)
)
check("NaN rejected", not Budget.accept(spam, Vector3.new(0 / 0, 0, 0), 1, 16))
check("infinity rejected", not Budget.accept(spam, Vector3.new(math.huge, 0, 0), 1, 16))
check(
	"lag pause does not fund arbitrary teleport",
	not Budget.accept(spam, Vector3.new(500, 0, 0), 100, 16)
)
return `PASS {passed}`

--!strict
local Shared = game:GetService("ReplicatedStorage").Shared
local Transition = require(Shared.Util.SpeedTransition)
local Budget = require(Shared.Util.MovementBudget)
local passed = 0
local function check(name: string, value: boolean)
	assert(value, name)
	passed += 1
end
local transition = { from = 320, to = 38, at = 10 }
check("ordinary target unchanged", Transition.rate(nil, 240, 10) == 240)
check("replication window keeps approved old pace", Transition.rate(transition, 38, 10.2) == 320)
check("braking decays", math.abs(Transition.rate(transition, 38, 10.55) - 179) < 0.001)
check("transition expires", Transition.rate(transition, 38, 10.81) == 38)
check("later validation cannot renew transition", Transition.rate(transition, 38, 20) == 38)
check("new higher target never throttled", Transition.rate(transition, 400, 10.5) == 400)
check("sample from before reduction must be reseeded", Transition.needsFreshSample(transition, 9.9))
check(
	"sample seeded during braking must be reseeded even after expiry",
	Transition.needsFreshSample(transition, 10.01)
)
check("steady pace sample remains valid", not Transition.needsFreshSample(transition, 10.81))
local oldState = { position = Vector3.zero, at = 10, budget = 25 }
local newState = { position = Vector3.zero, at = 10, budget = 25 }
local rejectedBefore = false
for i = 1, 6 do
	local at = 10 + i * 0.033
	local position = Vector3.new(0, 0, 320 * (at - 10))
	if not Budget.accept(oldState, position, at, 38) then
		rejectedBefore = true
	end
	check(
		"approved coasting keeps bounded budget",
		Budget.accept(newState, position, at, Transition.rate(transition, 38, at))
	)
end
check("regression reproduces without transition", rejectedBefore)
check(
	"instant teleport still rejected",
	not Budget.accept(
		newState,
		Vector3.new(1000, 0, 0),
		10.2,
		Transition.rate(transition, 38, 10.2)
	)
)
check(
	"same-frame spam adds no budget",
	not Budget.accept(newState, Vector3.new(300, 0, 0), 10.2, Transition.rate(transition, 38, 10.2))
)
check(
	"expired window cannot fund continued overspeed",
	not Budget.accept(newState, Vector3.new(0, 0, 250), 11, Transition.rate(transition, 38, 11))
)
return `PASS {passed}`

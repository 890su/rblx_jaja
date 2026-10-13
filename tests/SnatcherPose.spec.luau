--!strict
local Shared = game:GetService("ReplicatedStorage").Shared
local Pose = require(Shared.Util.SnatcherPose)
type Snapshot = Pose.Snapshot
local passed = 0
local function check(value: boolean)
	assert(value, `snatcher presentation contract {passed + 1}`)
	passed += 1
end
local function snapshot(x: number, time: number, phase: string?): Snapshot
	return { id = 1, cf = CFrame.new(x, 3.5, 0), time = time, phase = phase or "chase" }
end
local a, b = snapshot(0, 0), snapshot(10, 0.1)
check(Pose.isNewer(nil, a))
check(not Pose.isNewer(b, a))
check(not Pose.isNewer(b, b))
check(Pose.isNewer(a, b))
check(Pose.sample(a, b, 0.15).Position:FuzzyEq(Vector3.new(5, 3.5, 0), 0.001))
check(Pose.sample(a, b, 100).Position:FuzzyEq(Vector3.new(22, 3.5, 0), 0.001))
check(Pose.sample(nil, b, 1) == b.cf)
check(Pose.sample(a, snapshot(1_000, 0.1), 0.15).Position.X == 1_000)
check(Pose.sample(a, snapshot(10, 1), 1).Position.X == 10)
local dash = snapshot(0, 1, "lock")
dash.dashOrigin, dash.dashEnd, dash.dashStart, dash.dashSpeed =
	Vector3.new(0, 3.5, 0), Vector3.new(46, 3.5, 0), 2, 115
check(Pose.sample(nil, dash, 1.9).Position.X == 0)
check(math.abs(Pose.sample(nil, dash, 2.2).Position.X - 23) < 0.001)
check(Pose.sample(nil, dash, 3).Position.X == 46)
dash.phase = "dash"
check(math.abs(Pose.sample(nil, dash, 2.2).Position.X - 23) < 0.001)
dash.dashEnd = dash.dashOrigin
check(Pose.sample(nil, dash, 2.2).Position.X == 0)
for _, phase in { "cast", "warning" } do
	local held = snapshot(46, 2.4, phase)
	check(Pose.sample(dash, held, 10) == held.cf)
end
local recovered = snapshot(46, 2.4, "recover")
check(Pose.sample(dash, recovered, 2.4) == recovered.cf)
local repositioned = snapshot(48, 2.5, "recover")
check(math.abs(Pose.sample(recovered, repositioned, 2.55).Position.X - 47) < 0.001)
check(Pose.sample(recovered, repositioned, 100).Position.X <= 50.401)
check(Pose.sample(a, snapshot(20, 0.1, "guard"), 0.15).Position.X == 20)
local from, target = CFrame.new(0, 3.5, 0), CFrame.new(20, 3.5, 0)
check(Pose.transition(from, target, -1) == from)
check(Pose.transition(from, target, 0) == from)
check(Pose.transition(from, target, Pose.PHASE_BLEND_SECONDS) == target)
check(Pose.transition(from, target, Pose.PHASE_BLEND_SECONDS + 1) == target)
local middle = Pose.transition(from, target, Pose.PHASE_BLEND_SECONDS / 2).Position.X
check(math.abs(middle - 10) < 0.001)
local before = Pose.transition(from, target, Pose.PHASE_BLEND_SECONDS / 2 - 0.001).Position.X
local after = Pose.transition(from, target, Pose.PHASE_BLEND_SECONDS / 2 + 0.001).Position.X
check(before < middle and after > middle and after - before < 1)
check(Pose.transition(from, target, 0.001).Position.X < 0.01)
check(Pose.transition(from, target, Pose.PHASE_BLEND_SECONDS - 0.001).Position.X > 19.99)
return `PASS {passed}`

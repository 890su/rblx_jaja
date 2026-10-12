--!strict
local Shared = game:GetService("ReplicatedStorage").Shared
local Combat = require(Shared.Util.SnatcherCombat)
local Config = require(Shared.Config.Snatchers)
local passed = 0
local function check(name: string, ok: boolean)
	assert(ok, `FAIL {name}`)
	passed += 1
end
check("first zone is guarded", Config.FROM_ZONE == 1 and Config.COUNT_BY_ZONE[1] == 1)
check(
	"gentle first zone",
	Config.FIRST_ZONE_WARNING_SECONDS > Config.WARNING_SECONDS
		and Config.FIRST_ZONE_DASH_SPEED < Config.DASH_SPEED
)
check("pickup gives reaction time", Config.PICKUP_GRACE >= 1)
check("ordinary chase has a floor", Combat.chaseSpeed(0, 0.7) == Config.MIN_SPEED)
check(
	"high training cannot accelerate chase forever",
	Combat.chaseSpeed(400, 0.7) == Config.MAX_CHASE_SPEED
)
check("chase preserves ordinary scaling", Combat.chaseSpeed(30, 0.7) == 21)
local origin = Vector3.new(0, 3.5, 0)
local direction, endpoint = Combat.plan(origin, Vector3.new(10, 50, 0))
check("aim ignores target jump", direction == Vector3.new(1, 0, 0))
check("dash endpoint has fixed length", (endpoint - origin).Magnitude == Config.DASH_DISTANCE)
check("endpoint retains hover plane", endpoint.Y == origin.Y)
local fallback, finish = Combat.plan(origin, origin)
check(
	"coincident target has valid aim",
	fallback.Magnitude == 1 and finish == origin + fallback * Config.DASH_DISTANCE
)
check(
	"fast dash cannot tunnel",
	Combat.hits(Vector3.new(-10, 3.5, 0), Vector3.new(10, 3.5, 0), origin, origin)
)
check(
	"sideways dodge misses",
	not Combat.hits(
		Vector3.new(-10, 3.5, 0),
		Vector3.new(10, 3.5, 0),
		Vector3.new(0, 3.5, 5),
		Vector3.new(0, 3.5, 5)
	)
)
check(
	"moving target crossing is swept",
	Combat.hits(origin, origin, Vector3.new(-10, 3.5, 0), Vector3.new(10, 3.5, 0))
)
check("stationary overlap hits", Combat.hits(origin, origin, origin, origin))
check(
	"stationary separation misses",
	not Combat.hits(origin, origin, Vector3.new(0, 3.5, 4), Vector3.new(0, 3.5, 4))
)
for angle = 0, 350, 10 do
	local aim = Vector3.new(math.cos(math.rad(angle)), 0, math.sin(math.rad(angle)))
	local d, e = Combat.plan(origin, origin + aim * 15)
	check("finite locked aim", math.abs(d.Magnitude - 1) < 1e-5 and d:Dot(aim) > 0.9999)
	check("fixed endpoint", math.abs((e - origin).Magnitude - Config.DASH_DISTANCE) < 1e-4)
	local near = origin + d * 15
	check("line hits", Combat.hits(origin, e, near, near))
	local dodge = near + Vector3.new(-d.Z, 0, d.X) * (Config.HIT_RADIUS + 1)
	check("perpendicular dodge safe", not Combat.hits(origin, e, dodge, dodge))
end
return `PASS {passed}`

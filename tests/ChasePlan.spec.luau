--!strict
local Plan = require(game:GetService("ReplicatedStorage").Shared.Util.ChasePlan)
local passed = 0
local function check(name: string, condition: boolean)
	assert(condition, name)
	passed += 1
end
local function close(a: Vector3, b: Vector3): boolean
	return (a - b).Magnitude < 1e-4
end
local function angle(a: Vector3, b: Vector3): number
	return math.acos(math.clamp(a.Unit:Dot(b.Unit), -1, 1))
end

local forward = Vector3.new(0, 0, -1)
local formation = {
	trailDistance = 18,
	flankDistance = 24,
	flankAhead = 8,
	interceptSeconds = 0.45,
	minLead = 22,
	maxLead = 90,
}
local steering = { acceleration = 100, turnRate = math.rad(120), arrivalSeconds = 0.25 }
local playerPosition = Vector3.new(5, 7, -100)
check("one guard pressures", Plan.role(1, 1) == "pressure")
check("two guards use flank instead of front trap", Plan.role(2, 2) == "flank")
check("three guards unlock interceptor", Plan.role(3, 3) == "intercept")
check(
	"four guards retain two flanks",
	Plan.role(3, 4) == "flank" and Plan.role(4, 4) == "intercept"
)
check(
	"stationary heading preserved",
	close(Plan.heading(forward, Vector3.zero, Vector3.xAxis, 1, 2, 2), forward)
)
check(
	"zero heading uses look direction",
	close(Plan.heading(Vector3.zero, Vector3.zero, Vector3.xAxis, 1, 2, 2), Vector3.xAxis)
)
check(
	"all zero inputs give finite heading",
	close(Plan.heading(Vector3.zero, Vector3.zero, Vector3.zero, 0, 0, 0), forward)
)
check(
	"vertical movement ignored",
	close(Plan.heading(forward, Vector3.new(0, 100, 0), Vector3.xAxis, 1, 2, 2), forward)
)
check(
	"slow jitter does not reorient",
	close(Plan.heading(forward, Vector3.new(0.1, 0, 0), Vector3.xAxis, 1, 2, 2), forward)
)
check(
	"zero time keeps heading",
	close(Plan.heading(forward, -forward * 240, forward, 0, 2, 2), forward)
)
local sharp = Plan.heading(forward, -forward * 240, forward, 1 / 30, 2, 2)
check("sharp turn bounded", angle(forward, sharp) <= 2 / 30 + 1e-4)
check("sharp turn normalized and horizontal", math.abs(sharp.Magnitude - 1) < 1e-4 and sharp.Y == 0)

for _, speed in { 9.6, 16, 40, 120, 240 } do
	for count = 1, 4 do
		local targets: { Vector3 } = {}
		for slot = 1, count do
			local target = Plan.target(playerPosition, forward, speed, slot, count, formation)
			check("formation keeps player elevation", target.Y == playerPosition.Y)
			for _, previous in targets do
				check(
					"role targets retain clear separation at every carrier speed",
					(target - previous).Magnitude >= 22
				)
			end
			table.insert(targets, target)
		end
		if count >= 3 then
			local lead = (targets[count] - playerPosition):Dot(forward)
			check(
				"intercept lead stays in configured range",
				lead >= formation.minLead and lead <= formation.maxLead
			)
		end
	end
	local velocity = Vector3.zero
	for _ = 1, 120 do
		local before = velocity
		velocity = Plan.steer(velocity, forward * 1000, speed, 1 / 30, steering)
		check(
			"acceleration bounded while catching runner",
			(velocity - before).Magnitude <= steering.acceleration / 30 + 1e-4
		)
		check("chase speed does not exceed desired speed", velocity.Magnitude <= speed + 1e-4)
	end
	check(
		"guard reaches configured speed without teleporting",
		math.abs(velocity.Magnitude - speed) < 1e-3
	)
	local turned = Plan.steer(velocity, -forward * 1000, speed, 1 / 30, steering)
	check(
		"velocity reversal acceleration bounded",
		(turned - velocity).Magnitude <= steering.acceleration / 30 + 1e-4
	)
	check(
		"velocity reversal turn bounded",
		angle(velocity, turned) <= steering.turnRate / 30 + 1e-4
	)
	local slowing = Plan.steer(velocity, forward * 1000, 0, 1 / 30, steering)
	check(
		"abrupt target stop brakes gradually",
		(slowing - velocity).Magnitude <= steering.acceleration / 30 + 1e-4
	)
end
local moving = forward * 40
check(
	"zero time does not alter velocity",
	close(Plan.steer(moving, -forward * 100, 100, 0, steering), moving)
)
check(
	"negative time does not reverse physics",
	close(Plan.steer(moving, -forward * 100, 100, -1, steering), moving)
)
check(
	"negative speed brakes to zero",
	close(Plan.steer(Vector3.zero, forward * 100, -1, 1, steering), Vector3.zero)
)
check(
	"arrival decelerates at role target",
	Plan.steer(moving, Vector3.zero, 40, 1, steering).Magnitude == 0
)
check(
	"near target does not overshoot at constant speed",
	Plan.steer(Vector3.zero, forward, 40, 1, steering).Magnitude <= 4
)
check(
	"separation inactive beyond radius",
	Plan.separation(Vector3.zero, Vector3.xAxis * 20, 10, forward).Magnitude == 0
)
local repel = Plan.separation(Vector3.zero, Vector3.xAxis * 5, 10, forward)
check("separation pushes away", repel.X == -5 and repel.Y == 0)
local overlapA = Plan.separation(Vector3.zero, Vector3.zero, 10, Vector3.xAxis)
local overlapB = Plan.separation(Vector3.zero, Vector3.zero, 10, -Vector3.xAxis)
check(
	"overlap handled with opposite stable directions",
	close(overlapA, -overlapB) and overlapA.Magnitude == 10
)
check(
	"disabled separation stays zero",
	Plan.separation(Vector3.zero, Vector3.zero, 0, forward).Magnitude == 0
)
local arrivalSteering = { acceleration = 180, turnRate = math.rad(170), arrivalSeconds = 0.3 }
local function stoppedRun(
	initialSpeed: number,
	desiredSpeed: number,
	distance: number
): (number, number)
	local position = Vector3.zero
	local velocity = forward * initialSpeed
	local target = forward * distance
	local overshoot = 0
	for _ = 1, 600 do
		local before = velocity
		velocity = Plan.steer(velocity, target - position, desiredSpeed, 1 / 60, arrivalSteering)
		check(
			"high-speed arrival retains full acceleration bound",
			(velocity - before).Magnitude <= 3.001
		)
		position += velocity / 60
		overshoot = math.max(overshoot, (position - target):Dot(forward))
	end
	return overshoot, (position - target).Magnitude
end
local mediumOvershoot, mediumFinal = stoppedRun(180, 180, 100)
check("180 speed brakes before stationary target", mediumOvershoot < 5 and mediumFinal < 0.1)
local highOvershoot, highFinal = stoppedRun(240, 240, 200)
check("240 speed brakes with physically sufficient distance", highOvershoot < 5 and highFinal < 0.1)
local freshOvershoot, freshFinal = stoppedRun(0, 240, 95)
check(
	"new fast interceptor does not fly past stationary target",
	freshOvershoot < 5 and freshFinal < 0.1
)
local unavoidableOvershoot, unavoidableFinal = stoppedRun(240, 240, 100)
check(
	"short-distance stop respects physical braking instead of teleporting",
	unavoidableOvershoot >= 55 and unavoidableOvershoot < 70 and unavoidableFinal < 0.1
)
return `PASS {passed}`

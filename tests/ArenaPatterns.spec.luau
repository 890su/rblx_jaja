--!strict
local Shared = game:GetService("ReplicatedStorage").Shared
local Arena = require(Shared.Config.Arena)
local Patterns = require(Shared.Util.ArenaPatterns)
local passed = 0
local function check(name: string, ok: boolean)
	assert(ok, `FAIL {name}`)
	passed += 1
end

local HALF = Arena.LANE_WIDTH / 2 - Arena.EDGE_MARGIN

local function wave(kind: string, seed: number, level: number): Patterns.Wave
	return {
		id = seed,
		kind = kind,
		t0 = 100,
		x = 0,
		z = 0,
		laneX = 0,
		seed = seed,
		level = level,
		speed = Patterns.attackSpeed(level, 30),
	}
end

-- Hash is deterministic and in range.
for i = 1, 200 do
	local r = Patterns.rand(i * 37, i)
	check("rand range", r >= 0 and r < 1)
	check("rand stable", r == Patterns.rand(i * 37, i))
end

-- Shapes.
local dot: Patterns.Hazard = {
	id = "d",
	shape = "circle",
	position = Vector2.new(2, 0),
	radius = 1,
	warning = false,
	color = "white",
}
check("circle hit", Patterns.hits(dot, Vector2.zero, true))
check("circle miss", not Patterns.hits(dot, Vector2.new(-3, 0), true))
dot.warning = true
check("telegraph never damages", not Patterns.hits(dot, Vector2.new(2, 0), true))
local bar: Patterns.Hazard = {
	id = "b",
	shape = "capsule",
	position = Vector2.new(-10, 0),
	finish = Vector2.new(10, 0),
	radius = 1,
	warning = false,
	color = "white",
}
check("capsule hit", Patterns.hits(bar, Vector2.new(4, 1.5), true))
check("capsule miss", not Patterns.hits(bar, Vector2.new(4, 4), true))
local blue: Patterns.Hazard = {
	id = "u",
	shape = "rect",
	position = Vector2.zero,
	size = Vector2.new(60, 2),
	radius = 0,
	warning = false,
	color = "blue",
}
check("blue hurts when moving", Patterns.hits(blue, Vector2.zero, true))
check("blue safe when still", not Patterns.hits(blue, Vector2.zero, false))
blue.color = "orange"
check("orange hurts when still", Patterns.hits(blue, Vector2.zero, false))
check("orange safe when moving", not Patterns.hits(blue, Vector2.zero, true))

-- Every kind: produces hazards, ends, starts with a telegraph, stays near the lane.
for _, kind in Patterns.KINDS do
	for seed = 1, 40 do
		for _, level in { 0, 0.5, 1, Arena.MAX_LEVEL } do
			local w = wave(kind, seed * 977, level)
			local duration = Patterns.duration(w)
			check(`{kind} duration`, duration > 0.5 and duration < 12)
			check(`{kind} empty before start`, #Patterns.sample(w, w.t0 - 0.01) == 0)
			check(`{kind} empty after end`, #Patterns.sample(w, w.t0 + duration + 0.01) == 0)
			local first = Patterns.sample(w, w.t0 + 0.01)
			check(`{kind} visible at start`, #first > 0)
			for _, hazard in first do
				check(`{kind} opens with telegraph`, hazard.warning)
			end
			local ids: { [string]: boolean } = {}
			local active = false
			for step = 0, math.floor(duration * 20) do
				for _, hazard in Patterns.sample(w, w.t0 + step / 20) do
					active = active or not hazard.warning
					check(`{kind} lateral bound`, math.abs(hazard.position.X) <= HALF + 40)
					ids[hazard.id] = true
				end
			end
			check(`{kind} turns dangerous`, active)
			check(`{kind} has ids`, next(ids) ~= nil)
		end
	end
end

-- Bone walls always leave a gap wide enough for the player.
for seed = 1, 300 do
	for _, level in { 0, 0.8, Arena.MAX_LEVEL } do
		local w = wave("wall", seed, level)
		local hazards = Patterns.sample(w, w.t0 + 1.5)
		local found = false
		for x = -HALF, HALF, 0.5 do
			local blocked = false
			for _, hazard in hazards do
				if
					hazard.id:find(":w1")
					and Patterns.hits(hazard, Vector2.new(x, hazard.position.Y), true)
				then
					blocked = true
				end
			end
			found = found or not blocked
		end
		check("wall leaves a gap", found)
	end
end

-- The pellet ring always has an exit inside the lane.
for seed = 1, 200 do
	for _, offset in { -28, -10, 0, 10, 28 } do
		local w = wave("ring", seed, 1)
		w.x = offset
		local hazards = Patterns.sample(w, w.t0 + 0.5)
		local exit = false
		for angle = 0, 359, 3 do
			local point = Vector2.new(offset, 0)
				+ Vector2.new(math.cos(math.rad(angle)), math.sin(math.rad(angle))) * 20
			if math.abs(point.X) <= HALF then
				local blocked = false
				for _, hazard in hazards do
					local h = table.clone(hazard)
					h.warning = false
					if Patterns.hits(h, point, true) then
						blocked = true
					end
				end
				exit = exit or not blocked
			end
		end
		check("ring exit inside lane", exit)
	end
end

-- Difficulty grows with rarity, zone, rebirths and progress; pacing tightens.
check("level rises with rarity", Patterns.level(6, 3, 0) > Patterns.level(1, 3, 0))
check("level rises with zone", Patterns.level(1, 5, 0) > Patterns.level(1, 3, 0))
check("level rises with rebirths", Patterns.level(1, 3, 5) > Patterns.level(1, 3, 0))
check("progress ramps", Patterns.effective(0.2, 1) > Patterns.effective(0.2, 0))
check("level capped", Patterns.effective(5, 1) <= Arena.MAX_LEVEL)
check("interval shrinks", Patterns.interval(1.5) < Patterns.interval(0))
check("interval floor", Patterns.interval(10) >= 0.85)
check("more simultaneous waves", Patterns.maxActive(1.5) > Patterns.maxActive(0))
check("faster runners, faster attacks", Patterns.attackSpeed(0, 38) > Patterns.attackSpeed(0, 24))
check("run speed clamp low", Patterns.runSpeed(16) == Arena.WALK_SPEED_MIN)
check("run speed clamp high", Patterns.runSpeed(400) == Arena.WALK_SPEED_MAX)

-- Kind picker: never repeats, unlocks advanced kinds only at higher levels.
local seenLow: { [string]: boolean } = {}
local seenHigh: { [string]: boolean } = {}
for i = 1, 400 do
	local roll = Patterns.rand(i, 7)
	local kind = Patterns.pickKind(0, roll, "wall")
	check("no repeat", kind ~= "wall")
	seenLow[kind] = true
	seenHigh[Patterns.pickKind(1.2, roll, nil)] = true
end
check("low level has no blue", not seenLow.blue and not seenLow.sweeper)
for _, kind in Patterns.KINDS do
	check(`high level reaches {kind}`, seenHigh[kind] == true)
end

-- Field waves can be turned toward the runner's heading.
check("axis heading snaps", Patterns.axisHeading(Vector2.new(3, 1)) == Vector2.new(1, 0))
check("axis heading default", Patterns.axisHeading(Vector2.zero) == Vector2.new(0, 1))
check("warn time matches level", Patterns.warnTimeFor(0) == 0.9 and Patterns.warnTimeFor(5) == 0.45)
for seed = 1, 50 do
	local plain = wave("wall", seed, 0.3)
	local same = wave("wall", seed, 0.3)
	same.heading = Vector2.new(0, 1)
	local a, b = Patterns.sample(plain, plain.t0 + 1), Patterns.sample(same, same.t0 + 1)
	check("+Z heading is identity", #a == #b and a[1].position == b[1].position)
	local turned = wave("wall", seed, 0.3)
	turned.heading = Vector2.new(1, 0)
	for _, hazard in Patterns.sample(turned, turned.t0 + 1) do
		local size = hazard.size :: Vector2
		-- A wall ahead along +X spans Z (thin along X) and sits at x > pivot.
		check("turned wall is across the path", size.X < size.Y and hazard.position.X > turned.x)
	end
end
return `PASS {passed}`

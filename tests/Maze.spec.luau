--!strict
-- Maze generator checks. Run in Studio (Edit) via MCP execute_luau.

local Maze = require(game:GetService("ReplicatedStorage").Shared.Util.Maze)

local passed = 0
local function check(name: string, ok: boolean)
	if not ok then
		error(`FAIL {name}`)
	end
	passed += 1
end

for seed = 1, 25 do
	local grid = Maze.generate(5, 20, Random.new(seed), 0.35)
	check(`seed {seed}: fully connected`, Maze.reachable(grid) == 5 * 20)
end
-- Same seed -> same layout (all servers agree on the daily canyon).
local a = Maze.generate(5, 20, Random.new(42), 0.35)
local b = Maze.generate(5, 20, Random.new(42), 0.35)
local same = true
for x = 1, 5 do
	for y = 1, 20 do
		if
			a.cells[x][y].east ~= b.cells[x][y].east
			or a.cells[x][y].south ~= b.cells[x][y].south
		then
			same = false
		end
	end
end
check("deterministic", same)
-- Braid produces loops: more open walls than a perfect maze (cells - 1).
local open = 0
for x = 1, 5 do
	for y = 1, 20 do
		local c = a.cells[x][y]
		if x < 5 and not c.east then
			open += 1
		end
		if y < 20 and not c.south then
			open += 1
		end
	end
end
check("braided has loops", open > 5 * 20 - 1)

return `PASS {passed}`

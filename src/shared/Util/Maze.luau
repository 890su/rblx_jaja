--!strict
-- Pure braided-maze generator (no Instances). Grid of width x height cells;
-- each cell stores whether its east and south walls exist. Outer boundary is
-- implicit (always walled) and handled by the caller.
--   1. Recursive backtracker (iterative DFS) -> perfect maze (one route).
--   2. Braid: remove extra walls with probability `braid` -> loops, so there
--      are several routes and few dead ends.

export type Cell = { east: boolean, south: boolean }
export type Grid = { width: number, height: number, cells: { { Cell } } } -- cells[x][y]

local Maze = {}

local DIRS = {
	{ dx = 1, dy = 0 },
	{ dx = -1, dy = 0 },
	{ dx = 0, dy = 1 },
	{ dx = 0, dy = -1 },
}

local function removeWall(grid: Grid, x: number, y: number, dx: number, dy: number)
	if dx == 1 then
		grid.cells[x][y].east = false
	elseif dx == -1 then
		grid.cells[x - 1][y].east = false
	elseif dy == 1 then
		grid.cells[x][y].south = false
	else
		grid.cells[x][y - 1].south = false
	end
end

function Maze.generate(width: number, height: number, rng: Random, braid: number): Grid
	local cells: { { Cell } } = {}
	local visited: { { boolean } } = {}
	for x = 1, width do
		cells[x] = {}
		visited[x] = {}
		for y = 1, height do
			cells[x][y] = { east = true, south = true }
			visited[x][y] = false
		end
	end
	local grid: Grid = { width = width, height = height, cells = cells }

	local stack = { { x = rng:NextInteger(1, width), y = rng:NextInteger(1, height) } }
	visited[stack[1].x][stack[1].y] = true
	while #stack > 0 do
		local top = stack[#stack]
		local options = {}
		for _, d in DIRS do
			local nx, ny = top.x + d.dx, top.y + d.dy
			if nx >= 1 and nx <= width and ny >= 1 and ny <= height and not visited[nx][ny] then
				table.insert(options, d)
			end
		end
		if #options == 0 then
			table.remove(stack)
		else
			local d = options[rng:NextInteger(1, #options)]
			removeWall(grid, top.x, top.y, d.dx, d.dy)
			visited[top.x + d.dx][top.y + d.dy] = true
			table.insert(stack, { x = top.x + d.dx, y = top.y + d.dy })
		end
	end

	for x = 1, width do
		for y = 1, height do
			local cell = cells[x][y]
			if x < width and cell.east and rng:NextNumber() < braid then
				cell.east = false
			end
			if y < height and cell.south and rng:NextNumber() < braid then
				cell.south = false
			end
		end
	end
	return grid
end

-- Number of cells reachable from (1,1); equals width*height for a valid maze.
function Maze.reachable(grid: Grid): number
	local seen: { [number]: boolean } = {}
	local count = 0
	local queue = { { x = 1, y = 1 } }
	seen[1 * 10000 + 1] = true
	while #queue > 0 do
		local cur = table.remove(queue, 1) :: { x: number, y: number }
		count += 1
		local x, y = cur.x, cur.y
		local neighbours = {}
		if x < grid.width and not grid.cells[x][y].east then
			table.insert(neighbours, { x = x + 1, y = y })
		end
		if x > 1 and not grid.cells[x - 1][y].east then
			table.insert(neighbours, { x = x - 1, y = y })
		end
		if y < grid.height and not grid.cells[x][y].south then
			table.insert(neighbours, { x = x, y = y + 1 })
		end
		if y > 1 and not grid.cells[x][y - 1].south then
			table.insert(neighbours, { x = x, y = y - 1 })
		end
		for _, n in neighbours do
			local key = n.x * 10000 + n.y
			if not seen[key] then
				seen[key] = true
				table.insert(queue, n)
			end
		end
	end
	return count
end

return table.freeze(Maze)

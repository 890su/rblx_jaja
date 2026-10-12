--!strict
-- Meteor Rush server entry point. Two-phase bootstrap: init() every Service
-- (wire-up only, must not yield), then start() each in its own thread.

local Services = script:WaitForChild("Services")

local loaded: { [string]: any } = {}
local modules = Services:GetChildren()
local priority: { [string]: number } = { WorldService = 0, DataService = 1, StationService = 2 }
table.sort(modules, function(a, b)
	local pa, pb = priority[a.Name] or 3, priority[b.Name] or 3
	return if pa == pb then a.Name < b.Name else pa < pb
end)
for _, child in modules do
	if child:IsA("ModuleScript") then
		loaded[child.Name] = require(child) :: any
	end
end

for _, child in modules do
	local name = child.Name
	local service = loaded[name]
	if not service then
		continue
	end
	if typeof(service.init) == "function" then
		local ok, err = pcall(service.init)
		if not ok then
			error(`[MeteorRush] {name}.init failed: {err}`)
		end
	end
end

for _, child in modules do
	local service = loaded[child.Name]
	if not service then
		continue
	end
	if typeof(service.start) == "function" then
		task.spawn(service.start)
	end
end

print("[MeteorRush] server started")

--!strict
-- Meteor Rush server entry point. Two-phase bootstrap: init() every Service
-- (wire-up only, must not yield), then start() each in its own thread.

local Services = script:WaitForChild("Services")

local loaded: { [string]: any } = {}
for _, child in Services:GetChildren() do
	if child:IsA("ModuleScript") then
		loaded[child.Name] = require(child) :: any
	end
end

for name, service in loaded do
	if typeof(service.init) == "function" then
		local ok, err = pcall(service.init)
		if not ok then
			warn(`[MeteorRush] {name}.init failed: {err}`)
		end
	end
end

for _, service in loaded do
	if typeof(service.start) == "function" then
		task.spawn(service.start)
	end
end

print("[MeteorRush] server started")

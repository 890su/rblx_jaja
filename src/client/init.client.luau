--!strict
-- Meteor Rush client entry point. Same two-phase bootstrap as the server,
-- over Controllers.

local Controllers = script:WaitForChild("Controllers")

local loaded: { [string]: any } = {}
for _, child in Controllers:GetChildren() do
	if child:IsA("ModuleScript") then
		loaded[child.Name] = require(child) :: any
	end
end

for name, controller in loaded do
	if typeof(controller.init) == "function" then
		local ok, err = pcall(controller.init)
		if not ok then
			warn(`[MeteorRush] {name}.init failed: {err}`)
		end
	end
end

for _, controller in loaded do
	if typeof(controller.start) == "function" then
		task.spawn(controller.start)
	end
end

print("[MeteorRush] client started")

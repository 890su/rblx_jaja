--!strict
return function()
	assert(game:GetService("RunService"):IsStudio(), "Studio only")
	local args = game:GetService("StudioTestService"):GetTestArgs()
	assert(
		typeof(args) == "table" and args.suite == "preprod" and args.mode == "commerce",
		"isolated commerce test only"
	)
end

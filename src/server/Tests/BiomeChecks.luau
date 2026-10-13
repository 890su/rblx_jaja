--!strict
-- Opt-in two-client checks; Preflight selects isolated test profiles.
local Players = game:GetService("Players")
local Data = require(script.Parent.Parent.Services.DataService)
local Station = require(script.Parent.Parent.Services.StationService)
local Biomes = require(game:GetService("ReplicatedStorage").Shared.Theme.Biomes)
local Checks = {}
function Checks.run(): any
	local remote = Instance.new("RemoteEvent")
	remote.Name = "BiomeQA"
	remote.Parent = game:GetService("ReplicatedStorage")
	local replies: { [Player]: any } = {}
	local nonce = 0
	local completed: { string } = {}
	local connection = remote.OnServerEvent:Connect(function(player, token: any, result: any)
		if token == nonce and typeof(result) == "table" then
			replies[player] = result
		end
	end)
	local function check(name: string, success: boolean)
		assert(success, name)
		table.insert(completed, name)
	end
	local ok, result = pcall(function(): any
		local deadline = os.clock() + 90
		local all = Players:GetPlayers()
		local reachedReady = false
		while os.clock() < deadline do
			all = Players:GetPlayers()
			local loaded = #all == 2
			for _, player in all do
				local character = player.Character
				local humanoid = character and character:FindFirstChildOfClass("Humanoid")
				if
					not Data.get(player)
					or not Station.getPlot(player)
					or not humanoid
					or humanoid.FloorMaterial == Enum.Material.Air
				then
					loaded = false
				end
			end
			if loaded then
				reachedReady = true
				break
			end
			task.wait(0.2)
		end
		assert(reachedReady, "two biome clients did not finish initial station spawn")
		task.wait(1) -- let initial station teleport/character controllers settle
		assert(
			#all == 2 and Data.get(all[1]) and Data.get(all[2]),
			"two biome clients did not load"
		)
		local actor, observer = all[1], all[2]
		local profile = assert(Data.get(actor))
		profile.rebirths = 1
		Data.setSpeed(actor, 9000)
		local debugCommand = game:GetService("ServerStorage").DebugCommand
		local serverTime = game:GetService("Lighting").ClockTime
		local function observe(expectedActor: number, expectedObserver: number)
			nonce += 1
			table.clear(replies)
			remote:FireClient(actor, nonce, expectedActor)
			remote:FireClient(observer, nonce, expectedObserver)
			local limit = os.clock() + 8
			while os.clock() < limit and (not replies[actor] or not replies[observer]) do
				task.wait(0.1)
			end
			check(
				`local biome {expectedActor}, independent observer {expectedObserver}: {game
					:GetService("HttpService")
					:JSONEncode({ actor = replies[actor], observer = replies[observer] })}`,
				replies[actor] ~= nil
					and replies[actor].ok == true
					and replies[observer] ~= nil
					and replies[observer].ok == true
			)
		end
		debugCommand:Invoke("teleport", observer.Name, 0, 3, 12)
		for index, z in { -200, -950, -1950, -2950, -3950 } do
			debugCommand:Invoke("teleport", actor.Name, 0, 3, z)
			observe(index, 0)
		end
		debugCommand:Invoke("teleport", actor.Name, 0, 3, 12)
		observe(0, 0)
		check("server lighting unaffected", game:GetService("Lighting").ClockTime == serverTime)
		local world = workspace:FindFirstChild("World") :: Folder
		local environment = world:FindFirstChild("Environment") :: Folder
		local sceneryParts = 0
		for _, p in environment:GetDescendants() do
			if p:IsA("BasePart") and p.Name ~= "CraterBed" then
				assert(
					p.Anchored and not p.CanCollide and not p.CanQuery and not p.CanTouch,
					"scenery participates in gameplay"
				)
				sceneryParts += 1
			end
		end
		check("decorative geometry never blocks gameplay", sceneryParts > 0)
		for i, biome in Biomes.ZONES do
			local floor = (world:FindFirstChild("Track") :: Folder):FindFirstChild(
					`Zone{i}`
				) :: BasePart
			check(
				`biome {i} surface and unchanged friction`,
				floor.Material == biome.groundMaterial
					and typeof(floor.CustomPhysicalProperties) == "PhysicalProperties"
					and floor.CustomPhysicalProperties.Friction
						== PhysicalProperties.new(Enum.Material.Ground).Friction
			)
		end
		return { ok = true, checks = completed, players = 2, environmentParts = sceneryParts }
	end)
	connection:Disconnect()
	remote:Destroy()
	if not ok then
		error(result)
	end
	return result
end
return Checks

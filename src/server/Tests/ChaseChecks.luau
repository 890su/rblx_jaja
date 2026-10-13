--!strict
-- Real service/controller observations, with the opt-in runner's isolated profiles.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")
local Services = script.Parent.Parent.Services
local Data = require(Services.DataService)
local Station = require(Services.StationService)
local Carry = require(Services.CarryService)
local Snatchers = require(Services.SnatcherService)
local Checks = {}

function Checks.run(): any
	local remote = Instance.new("RemoteEvent")
	remote.Name = "ChaseQA"
	remote.Parent = ReplicatedStorage
	local nonce = 0
	local replies: { [Player]: any } = {}
	local completed: { string } = {}
	local metrics: { [string]: any } = {}
	local visualComplete = true
	local all: { Player } = {}
	local connection = remote.OnServerEvent:Connect(
		function(player: Player, token: any, result: any)
			if token == nonce and typeof(result) == "table" then
				replies[player] = result
			end
		end
	)
	local function check(name: string, success: boolean)
		assert(success, name)
		table.insert(completed, name)
	end
	local ok, result = pcall(function(): any
		local deadline = os.clock() + 120
		local loaded = false
		while os.clock() < deadline do
			all = Players:GetPlayers()
			loaded = #all == 2
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
				break
			end
			task.wait(0.2)
		end
		check("two clients have profiles, stations and grounded characters", loaded)
		task.wait(1)
		local actor, other = all[1], all[2]
		local idsA = Snatchers.debugBegin(actor, 3, 40)
		local idsB = Snatchers.debugBegin(other, 4, 40)
		check("first carrier has three fixtures", #idsA == 3)
		check("second carrier has four fixtures", #idsB == 4)
		local began = os.clock()
		local function captureRoles(label: string)
			local captured = {}
			for _, player in all do
				local character = player.Character
				local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
				local humanoid = character and character:FindFirstChildOfClass("Humanoid")
				local snapshot = Snatchers.debugSnapshot(player)
				local serialized = {}
				for _, drone in snapshot do
					table.insert(serialized, {
						id = drone.id,
						slot = drone.slot,
						role = drone.role,
						phase = drone.phase,
						position = tostring(drone.position),
						velocity = tostring(drone.velocity),
						attackUntil = drone.attackUntil,
					})
				end
				captured[player.Name] = {
					hasCarry = Carry.get(player) ~= nil,
					carrying = player:GetAttribute("Carrying"),
					position = root and tostring(root.Position),
					anchored = root and root.Anchored,
					health = humanoid and humanoid.Health,
					arenaPrep = player:GetAttribute("ArenaPrep"),
					arenaActive = player:GetAttribute("ArenaActive"),
					snapshot = serialized,
				}
			end
			metrics[label] = { elapsed = os.clock() - began, players = captured }
		end
		captureRoles("rolesAtStart")
		local ids: { number } = {}
		local unique: { [number]: boolean } = {}
		for _, group in { idsA, idsB } do
			for _, id in group do
				check("two carriers do not share a drone", not unique[id])
				unique[id] = true
				table.insert(ids, id)
			end
		end
		local function startProbe(mode: string, duration: number)
			nonce += 1
			table.clear(replies)
			remote:FireAllClients(nonce, { mode = mode, ids = ids, duration = duration })
		end
		local function finishProbe(mode: string)
			local limit = os.clock() + 8
			while os.clock() < limit and (not replies[actor] or not replies[other]) do
				task.wait(0.05)
			end
			metrics[mode] = { actor = replies[actor], observer = replies[other] }
			for _, player in all do
				local reply = replies[player]
				check(`{mode} client probe replied: {player.Name}`, reply ~= nil)
				if reply.status == "inconclusive_render_throttled" then
					visualComplete = false
				else
					check(
						`{mode} actual root/body continuity: {player.Name}; {HttpService:JSONEncode(
							reply
						)}`,
						reply.status == "pass" and reply.ok == true
					)
				end
			end
		end
		startProbe("motion", 2)
		task.wait(1)
		captureRoles("rolesAfterOneSecond")
		task.wait(1.2)
		finishProbe("motion")
		captureRoles("rolesAfterMotion")
		for _, player in all do
			local snapshot = Snatchers.debugSnapshot(player)
			local roles: { [string]: boolean } = {}
			for _, drone in snapshot do
				roles[drone.role] = true
			end
			check(
				`each group retains pressure, flank and intercept roles: {player.Name}; {HttpService:JSONEncode(
					metrics.rolesAfterMotion
				)}`,
				roles.pressure and roles.flank and roles.intercept
			)
			for index, drone in snapshot do
				for previous = 1, index - 1 do
					check(
						"role movement keeps drones physically separated",
						(drone.position - snapshot[previous].position).Magnitude > 3
					)
				end
			end
		end
		-- Restart to remove naturally scheduled attacks before the controlled dash.
		Snatchers.debugEnd(actor)
		Snatchers.debugEnd(other)
		idsA = Snatchers.debugBegin(actor, 3, 40)
		idsB = Snatchers.debugBegin(other, 4, 40)
		table.clear(ids)
		for _, group in { idsA, idsB } do
			for _, id in group do
				table.insert(ids, id)
			end
		end
		startProbe("dash", 1.6)
		task.wait(0.3)
		check("first carrier dash admitted", Snatchers.debugDash(actor))
		check("second carrier dash has independent attack budget", Snatchers.debugDash(other))
		check("overlapping attack denied for first group", not Snatchers.debugDash(actor))
		check("overlapping attack denied for second group", not Snatchers.debugDash(other))
		local maximum = 0
		local activePhases: { [string]: boolean } =
			{ warning = true, lock = true, dash = true, cast = true }
		-- Cover lock, dash and early recovery, then drop/death before the real
		-- next attack can correctly catch these intentionally immobile carriers.
		local untilAt = os.clock() + 1.8
		while os.clock() < untilAt do
			for _, player in all do
				local active = 0
				for _, drone in Snatchers.debugSnapshot(player) do
					if activePhases[drone.phase] then
						active += 1
					end
				end
				maximum = math.max(maximum, active)
				assert(active <= 1, "coordinated group overlaps dangerous attacks")
			end
			task.wait(1 / 60)
		end
		metrics.maximumConcurrentAttacks = maximum
		metrics.server = Snatchers.debugMetrics()
		check("coordinated groups admit exactly one dangerous attack", maximum == 1)
		finishProbe("dash")
		local otherBefore = #Snatchers.debugSnapshot(other)
		local otherCarry = Carry.get(other)
		local actorRoot = assert(actor.Character, "missing first character"):FindFirstChild(
			"HumanoidRootPart"
		) :: BasePart
		Carry.drop(actor, actorRoot.Position)
		task.wait(0.2)
		check(
			"dropping cargo clears carrier state",
			Carry.get(actor) == nil and actor:GetAttribute("Carrying") == nil
		)
		check("cargo loss releases pursuit", #Snatchers.debugSnapshot(actor) == 0)
		check(
			"one carrier losing cargo preserves other group",
			#Snatchers.debugSnapshot(other) == otherBefore
				and otherBefore > 0
				and Carry.get(other) == otherCarry
				and otherCarry ~= nil
		)
		metrics.otherGroupBeforeDrop = otherBefore
		metrics.otherGroupAfterDrop = #Snatchers.debugSnapshot(other)
		local humanoid =
			assert(other.Character, "missing second character"):FindFirstChildOfClass("Humanoid")
		assert(humanoid, "missing second humanoid")
		humanoid.Health = 0
		task.wait(0.3)
		check(
			"death clears cargo and pursuit",
			Carry.get(other) == nil and #Snatchers.debugSnapshot(other) == 0
		)
		return {
			ok = true,
			players = 2,
			checks = completed,
			metrics = metrics,
			visualComplete = visualComplete,
		}
	end)
	for _, player in all do
		Snatchers.debugEnd(player)
	end
	connection:Disconnect()
	remote:Destroy()
	if not ok then
		error(
			`{result}; checks={HttpService:JSONEncode(completed)}; metrics={HttpService:JSONEncode(
				metrics
			)}`
		)
	end
	return result
end

return Checks

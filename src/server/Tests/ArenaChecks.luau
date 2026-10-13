--!strict
-- Isolated two-client regression for the pursuit -> Void Run handoff.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Services = script.Parent.Parent.Services
local Data = require(Services.DataService)
local Station = require(Services.StationService)
local Carry = require(Services.CarryService)
local Snatchers = require(Services.SnatcherService)
local Speed = require(Services.SpeedService)
local Checks = {}

function Checks.run(): any
	local remote = Instance.new("RemoteEvent")
	remote.Name, remote.Parent = "ArenaQA", ReplicatedStorage
	local nonce = 0
	local replies: { [Player]: any } = {}
	local completed: { string } = {}
	local all: { Player } = {}
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
		repeat
			all = Players:GetPlayers()
			local ready = #all == 2
			for _, player in all do
				local humanoid = player.Character
					and player.Character:FindFirstChildOfClass("Humanoid")
				if
					not Data.get(player)
					or not Station.getPlot(player)
					or not humanoid
					or humanoid.FloorMaterial == Enum.Material.Air
				then
					ready = false
				end
			end
			if ready then
				break
			end
			task.wait(0.2)
		until os.clock() > deadline
		check(
			"two isolated players loaded",
			#all == 2 and Data.get(all[1]) ~= nil and Data.get(all[2]) ~= nil
		)
		task.wait(1)
		local actor, other = all[1], all[2]
		local function at(position: Vector3)
			Speed.markTeleport(actor, position)
			assert(actor.Character, "missing arena character"):PivotTo(CFrame.new(position))
		end
		local function probe(label: string, active: boolean, hazards: boolean)
			nonce += 1
			table.clear(replies)
			remote:FireAllClients(nonce, actor.UserId)
			local untilAt = os.clock() + 8
			while os.clock() < untilAt and (not replies[actor] or not replies[other]) do
				task.wait(0.05)
			end
			local localView = replies[actor]
			local observer = replies[other]
			check(label .. " runner replied", localView ~= nil)
			check(label .. " observer replied", observer ~= nil)
			check(
				label .. " runner camera/UI",
				localView.enabled == active
					and localView.camera == (if active then "Scriptable" else "Custom")
			)
			check(
				label .. " observer unaffected",
				not observer.enabled and observer.camera == "Custom"
			)
			if hazards then
				check(
					label .. " visible attacks received and drawn",
					localView.waves > 0 and localView.hazards > 0
				)
			end
		end
		Snatchers.debugBegin(actor, 3, 240)
		at(Vector3.new(-35, 4, -569.9))
		check(
			"handoff starts before arena flags",
			actor:GetAttribute("ArenaPrep") ~= true and actor:GetAttribute("ArenaActive") ~= true
		)
		check(
			"incoming chase hit cannot remove cargo at arena entrance",
			Snatchers.debugIncomingHit(actor)
		)
		check("cargo survives handoff", Carry.get(actor) ~= nil)
		task.wait(0.5)
		check(
			"staging starts with three lives",
			actor:GetAttribute("ArenaPrep") == true and actor:GetAttribute("ArenaLives") == 3
		)
		check("chase despawns during staging", #Snatchers.debugSnapshot(actor) == 0)
		probe("staging", true, false)
		at(Vector3.new(-35, 4, -499))
		task.wait(2.6)
		check(
			"arena starts and cargo stays held",
			actor:GetAttribute("ArenaActive") == true and Carry.get(actor) ~= nil
		)
		probe("run", true, true)
		at(Vector3.new(-35, 4, 1))
		task.wait(1.2)
		check(
			"finish preserves cargo and opens delivery",
			Carry.get(actor) ~= nil and Carry.passedDeliveryRoute(actor)
		)
		probe("finish", false, false)
		check(
			"second player has no arena/cargo state",
			Carry.get(other) == nil and other:GetAttribute("ArenaActive") ~= true
		)
		Snatchers.debugBegin(actor, 1, 240)
		check(
			"real chase hits still drop cargo outside arena",
			not Snatchers.debugIncomingHit(actor) and Carry.get(actor) == nil
		)
		return { ok = true, checks = completed }
	end)
	for _, player in all do
		Snatchers.debugEnd(player)
	end
	connection:Disconnect()
	remote:Destroy()
	if not ok then
		return { ok = false, error = tostring(result), checks = completed }
	end
	return result
end

return Checks

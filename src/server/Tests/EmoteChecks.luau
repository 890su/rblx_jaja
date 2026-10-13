--!strict
-- Called only by the opt-in Studio preflight runner, with isolated profiles.
local Players = game:GetService("Players")
local Services = script.Parent.Parent.Services
local Data = require(Services.DataService)
local Emote = require(Services.EmoteService)
local Checks = {}

function Checks.run(): any
	local remote = Instance.new("RemoteEvent")
	remote.Name = "EmoteQA"
	remote.Parent = game:GetService("ReplicatedStorage")
	local nonce = 0
	local seen: { [Player]: boolean } = {}
	local details: { [string]: any } = {}
	local completed: { string } = {}
	remote.OnServerEvent:Connect(function(player, token: any, success: any, info: any)
		if token == nonce and typeof(success) == "boolean" and typeof(info) == "table" then
			seen[player] = success
			details[player.Name] = info
		end
	end)
	local function check(name: string, value: boolean)
		assert(value, name)
		table.insert(completed, name)
	end
	local function ready(): { Player }
		local deadline = os.clock() + 90
		while os.clock() < deadline do
			local all = Players:GetPlayers()
			local loaded = #all == 2
			for _, player in all do
				local c = player.Character
				local h = c and c:FindFirstChildOfClass("Humanoid")
				if not Data.get(player) or not h or h.FloorMaterial == Enum.Material.Air then
					loaded = false
				end
			end
			if loaded then
				return all
			end
			task.wait(0.2)
		end
		error("emote clients did not load")
	end
	local all = ready()
	local actor = all[1]
	local function observe(rig: string)
		nonce += 1
		table.clear(seen)
		table.clear(details)
		task.wait(0.75)
		remote:FireAllClients(nonce, actor.UserId, rig)
		local deadline = os.clock() + 2
		while os.clock() < deadline and (seen[all[1]] == nil or seen[all[2]] == nil) do
			task.wait(0.05)
		end
		check(
			`{rig} wave rendered on both clients: {game.HttpService:JSONEncode(details)}`,
			seen[all[1]] == true and seen[all[2]] == true
		)
	end
	check("invalid emote denied", not Emote.play(actor, "unknown" :: any))
	check("R15 wave started", Emote.play(actor, "wave"))
	check("overlapping request denied", not Emote.play(actor, "wave"))
	observe("R15")
	Emote.stop(actor)
	check("stop clears replicated state", actor:GetAttribute("EmoteKey") == nil)
	check("cooldown enforced", not Emote.play(actor, "wave"))
	game:GetService("ServerStorage").DebugCommand:Invoke("emoteRig", actor.Name, "R6")
	task.wait(3.1)
	check("R6 wave started", Emote.play(actor, "wave"))
	observe("R6")
	task.wait(2.1)
	check("duration ends wave", actor:GetAttribute("EmoteKey") == nil)
	actor:SetAttribute("Carrying", "Rare")
	check("carry takes priority", not Emote.play(actor, "wave"))
	actor:SetAttribute("Carrying", nil)
	actor:SetAttribute("ArenaPrep", true)
	check("arena takes priority", not Emote.play(actor, "wave"))
	actor:SetAttribute("ArenaPrep", false)
	remote:Destroy()
	return { ok = true, checks = completed }
end

return Checks

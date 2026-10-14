--!strict
-- Studio-only QA commands (never active in live servers). Exposed as a
-- BindableFunction at ServerStorage.DebugCommand so MCP execute_luau (Server)
-- can drive state:  ServerStorage.DebugCommand:Invoke("give", "Player1", "comet_cat")

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Creatures = require(Shared.Config.Creatures)
local Steal = require(Shared.Config.Steal)

local DataService = require(script.Parent.DataService)
local StationService = require(script.Parent.StationService)
local StealService = require(script.Parent.StealService)
local EventService = require(script.Parent.EventService)
local SpeedService = require(script.Parent.SpeedService)
local MonetizationService = require(script.Parent.MonetizationService)
local CarryService = require(script.Parent.CarryService)
local EmoteService = require(script.Parent.EmoteService)

local DebugService = {}

local function find(who: any): Player?
	for _, player in Players:GetPlayers() do
		if player.Name == who or player.UserId == tonumber(who) then
			return player
		end
	end
	return nil
end

local COMMANDS: { [string]: (player: Player?, ...any) -> any } = {
	emoteRig = function(player, which)
		assert(player and (which == "R6" or which == "R15"), "use R6 or R15")
		EmoteService.stop(player)
		local old = player.Character
		local description = Instance.new("HumanoidDescription")
		local rig = Players:CreateHumanoidModelFromDescriptionAsync(
			description,
			if which == "R6" then Enum.HumanoidRigType.R6 else Enum.HumanoidRigType.R15
		)
		description:Destroy()
		rig.Name = player.Name
		if old then
			local animate = old:FindFirstChild("Animate")
			if animate then
				animate:Clone().Parent = rig
			end
		end
		rig.Parent = workspace
		player.Character = rig
		if old then
			old:Destroy()
		end
		return which
	end,
	emote = function(player)
		assert(player, "no player")
		return EmoteService.play(player, "wave")
	end,
	securityCheck = function(player)
		assert(player and player.Character, "no character")
		assert(not CarryService.get(player), "finish carrying before QA")
		local root = player.Character:FindFirstChild("HumanoidRootPart") :: BasePart
		local before = root.Position
		local began = CarryService.begin(player, {
			state = { creatureId = "comet_cat", rarity = "Rare", paid = false },
			fresh = true,
			originZone = 3,
			onLost = function(_by, _carry, _position) end,
		})
		assert(began, "QA carry failed")
		local deepDeliveryBlocked = not CarryService.passedDeliveryRoute(player)
		-- Same entry point as real proximity actions; no client-supplied grant.
		player.Character:PivotTo(CFrame.new(before.X, 400, before.Z))
		local accepted = SpeedService.validatePosition(player)
		return {
			deepDeliveryBlocked = deepDeliveryBlocked,
			rejected = accepted == nil,
			carryCleared = CarryService.get(player) == nil,
			returnedHome = root.Position.Y < 350,
		}
	end,
	persistence = function(player)
		assert(player, "no player")
		local profile = assert(DataService.get(player), "no profile")
		local confirmed = DataService.saveConfirmed(player, function(saved)
			return saved.schema == profile.schema and saved.uncollectedCoins ~= nil
		end)
		return {
			confirmed = confirmed,
			schema = profile.schema,
			uncollectedCoins = profile.uncollectedCoins,
			outgoing = HttpService:JSONEncode(profile.outgoingTransfers),
			incoming = HttpService:JSONEncode(profile.incomingTransfers),
		}
	end,
	-- teleport <player> <x> <y> <z>: a server teleport with anti-cheat grace.
	teleport = function(player, x, y, z)
		assert(player and player.Character, "no character")
		local before = player.Character:GetPivot().Position
		local destination = Vector3.new(tonumber(x) or 0, tonumber(y) or 3, tonumber(z) or 0)
		SpeedService.markTeleport(player, destination)
		player.Character:PivotTo(CFrame.new(destination))
		return { before.X, before.Y, before.Z }
	end,
	-- give <player> <creatureId> : hatched creature on a free pedestal
	give = function(player, creatureId)
		local creature = Creatures.BY_ID[creatureId]
		assert(player and creature, "usage: give <player> <creatureId>")
		return StationService.placeState(player, {
			creatureId = creature.id,
			rarity = creature.rarity,
		})
	end,
	-- Isolated visual QA: long name, mutation and a pending hatch timer.
	warehouseItem = function(player)
		assert(player, "no player")
		local args = game:GetService("StudioTestService"):GetTestArgs()
		assert(
			typeof(args) == "table" and args.suite == "preprod" and args.mode == "visual",
			"isolated visual QA only"
		)
		return StationService.give(player, {
			creatureId = "singularity_sprite",
			rarity = "Mythic",
			mutation = "Golden",
			paid = false,
			hatchAt = os.time() + 300,
		})
	end,
	-- Isolated manual movement QA: cargo without an attacking drone, so a
	-- movement rejection can be distinguished from legitimate combat damage.
	carry = function(player, origin)
		assert(player, "no player")
		local args = game:GetService("StudioTestService"):GetTestArgs()
		assert(
			typeof(args) == "table" and args.suite == "preprod" and args.mode == "visual",
			"isolated visual QA only"
		)
		player:SetAttribute("QACarryLost", nil)
		player:SetAttribute("QACarryDelivered", nil)
		return CarryService.begin(player, {
			state = { creatureId = "comet_cat", rarity = "Rare", paid = false },
			fresh = true,
			originZone = tonumber(origin) or 3,
			onLost = function(actor, _carry, _position)
				actor:SetAttribute("QACarryLost", true)
			end,
			onDelivered = function(actor, _carry)
				actor:SetAttribute("QACarryDelivered", true)
			end,
		})
	end,
	unprotect = function(player)
		local profile = assert(player and DataService.get(player), "no profile")
		profile.playtimeTotal =
			math.max(profile.playtimeTotal, Steal.NEW_PLAYER_PROTECTION_SECONDS + 1)
		return true
	end,
	-- reset <player> : clear steal cooldowns and station lock
	reset = function(player)
		assert(player, "no player")
		StealService.debugReset(player)
		return true
	end,
	coins = function(player, value)
		local profile = assert(player and DataService.get(player), "no profile")
		DataService.addCoins(player, (tonumber(value) or 0) - profile.coins)
		return true
	end,
	grant = function(player, key)
		assert(player, "no player")
		return MonetizationService.debugGrant(player, key)
	end,
	pass = function(player, key)
		assert(player, "no player")
		MonetizationService.debugPass(player, key)
		return true
	end,
	shower = function()
		EventService.debugShower()
		return true
	end,
	speed = function(player, value)
		assert(player, "no player")
		DataService.setSpeed(player, tonumber(value) or 0)
		return true
	end,
	-- state <player> : JSON summary of the profile
	state = function(player)
		local profile = assert(player and DataService.get(player), "no profile")
		local pedestals = {}
		for slot, state in profile.pedestals do
			pedestals[slot] = state.creatureId
		end
		return HttpService:JSONEncode({
			coins = profile.coins,
			speed = profile.speed,
			pedestals = pedestals,
			stats = profile.stats,
			rebirths = profile.rebirths,
			pedestalCount = profile.pedestalCount,
			shop = profile.shop,
			storage = #profile.storage,
			shieldUntil = profile.shieldUntil,
			daily = profile.daily,
			flags = profile.flags,
			carrying = player:GetAttribute("Carrying"),
			chaseUntil = player:GetAttribute("ChaseUntil"),
		})
	end,
	players = function()
		local names = {}
		for _, p in Players:GetPlayers() do
			table.insert(names, `{p.Name}({p.UserId})`)
		end
		return table.concat(names, ", ")
	end,
}

function DebugService.init()
	if not RunService:IsStudio() then
		return
	end
	local bindable = Instance.new("BindableFunction")
	bindable.Name = "DebugCommand"
	bindable.OnInvoke = function(command: string, who: any, ...: any): any
		local handler = COMMANDS[command]
		assert(handler, `unknown command {command}`)
		return handler(find(who), ...)
	end
	bindable.Parent = ServerStorage
end

return DebugService

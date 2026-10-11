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
	-- give <player> <creatureId> : hatched creature on a free pedestal
	give = function(player, creatureId)
		local creature = Creatures.BY_ID[creatureId]
		assert(player and creature, "usage: give <player> <creatureId>")
		return StationService.placeState(player, {
			creatureId = creature.id,
			rarity = creature.rarity,
		})
	end,
	-- unprotect <player> : skip new-player protection
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

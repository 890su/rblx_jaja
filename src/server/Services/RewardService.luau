--!strict
-- Daily login streak and promo codes (GDD §4.10). Status is published as
-- player attributes (DailyAvailable, DailyStreak, DailyNext) for the UI.

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Types = require(Shared.Types)
local Daily = require(Shared.Config.Daily)
local Creatures = require(Shared.Config.Creatures)
local Theme = require(Shared.Theme)
local Format = require(Shared.Util.Format)
local Remotes = require(Shared.Remotes)

local Codes = require(script.Parent.Parent.Data.Codes)
local RateLimit = require(script.Parent.Parent.Util.RateLimit)
local DataService = require(script.Parent.DataService)
local StationService = require(script.Parent.StationService)
local TelemetryService = require(script.Parent.TelemetryService)

local DAY = 24 * 60 * 60
local MAX_CODE_LENGTH = 24

local RewardService = {}

local claimLimit = RateLimit.new(2, 0.5)
local codeLimit = RateLimit.new(3, 0.2)

local function today(): number
	return math.floor(os.time() / DAY)
end

-- Streak day (1..7) the player would claim now.
local function nextStreak(profile: Types.PlayerProfile): number
	if profile.daily.lastClaimDay == today() - 1 then
		return profile.daily.streak % #Daily.REWARDS + 1
	end
	return 1
end

local function publish(player: Player, profile: Types.PlayerProfile)
	local available = profile.daily.lastClaimDay < today()
	player:SetAttribute("DailyAvailable", available)
	player:SetAttribute("DailyStreak", profile.daily.streak)
	player:SetAttribute("DailyNext", if available then nextStreak(profile) else nil)
end

local function giveCreature(player: Player, creatureId: string)
	local creature = Creatures.BY_ID[creatureId]
	if creature then
		StationService.give(player, { creatureId = creatureId, rarity = creature.rarity })
	end
end

local function onClaim(player: Player)
	if not claimLimit:allow(player) then
		return
	end
	local profile = DataService.get(player)
	if not profile or profile.daily.lastClaimDay >= today() then
		return
	end
	local streak = nextStreak(profile)
	local reward = Daily.REWARDS[streak]
	profile.daily.streak = streak
	profile.daily.lastClaimDay = today()
	if reward.coins then
		DataService.addCoins(player, reward.coins)
		TelemetryService.economy(player, "source", reward.coins, "Daily", `day{streak}`)
	end
	if reward.creatureId then
		giveCreature(player, reward.creatureId)
	end
	if reward.shieldMinutes then
		profile.shieldUntil = math.max(profile.shieldUntil, os.time()) + reward.shieldMinutes * 60
	end
	publish(player, profile)
	Remotes.event("Notify"):FireClient(player, `Day {streak} reward: {reward.label}!`, "success")
end

local function onRedeem(player: Player, raw: unknown)
	if not codeLimit:allow(player) then
		return
	end
	if typeof(raw) ~= "string" or #raw == 0 or #raw > MAX_CODE_LENGTH then
		return
	end
	local notify = Remotes.event("Notify")
	local profile = DataService.get(player)
	if not profile then
		return
	end
	local key = string.upper((raw:gsub("%s", "")))
	local code = Codes[key]
	if not code or os.time() > code.expires then
		notify:FireClient(player, "That code doesn't work", "warning")
		return
	end
	if profile.codes[key] then
		notify:FireClient(player, "You already used this code", "warning")
		return
	end
	profile.codes[key] = true
	local parts = {}
	if code.coins then
		DataService.addCoins(player, code.coins)
		TelemetryService.economy(player, "source", code.coins, "Code", key)
		table.insert(parts, `{Format.short(code.coins)} {Theme.CURRENCY}`)
	end
	if code.creatureId then
		giveCreature(player, code.creatureId)
		table.insert(parts, Theme.CREATURE_NAMES[code.creatureId] or code.creatureId)
	end
	notify:FireClient(player, `Code redeemed: {table.concat(parts, " + ")}`, "success")
end

function RewardService.init()
	Remotes.event("ClaimDaily").OnServerEvent:Connect(onClaim)
	Remotes.event("RedeemCode").OnServerEvent:Connect(onRedeem)
	DataService.onLoaded(publish)
end

function RewardService.start()
	-- Day rollover while playing.
	local lastDay = today()
	while true do
		task.wait(30)
		if today() ~= lastDay then
			lastDay = today()
			for _, player in game:GetService("Players"):GetPlayers() do
				local profile = DataService.get(player)
				if profile then
					publish(player, profile)
				end
			end
		end
	end
end

return RewardService

--!strict
-- Pure income math (no Instances, no services) so it can be unit-tested.

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Types = require(Shared.Types)
local Economy = require(Shared.Config.Economy)
local Rarity = require(Shared.Config.Rarity)

local Income = {}

function Income.isHatched(state: Types.PedestalState, now: number): boolean
	return state.hatchAt == nil or now >= (state.hatchAt :: number)
end

function Income.ofPedestal(state: Types.PedestalState): number
	local base = Rarity.INFO[state.rarity].incomePerSecond
	local mutation = state.mutation and (Rarity.MUTATIONS :: any)[state.mutation]
	return base * (if mutation then mutation.incomeMultiplier else 1)
end

function Income.multiplier(profile: Types.PlayerProfile): number
	-- 2x Coins / VIP passes (week 5) multiply in here.
	return 1 + profile.rebirths * Economy.REBIRTH_INCOME_BONUS
end

function Income.perSecond(profile: Types.PlayerProfile, now: number): number
	local sum = 0
	for _, state in profile.pedestals do
		if Income.isHatched(state, now) then
			sum += Income.ofPedestal(state)
		end
	end
	return sum * Income.multiplier(profile)
end

-- Coins earned while away: each creature earns from max(lastOnline, hatchAt)
-- until min(now, lastOnline + cap), at the reduced offline rate.
function Income.offline(profile: Types.PlayerProfile, now: number, hasOfflinePass: boolean?): number
	if profile.lastOnline <= 0 or now <= profile.lastOnline then
		return 0
	end
	local rate = if hasOfflinePass then Economy.OFFLINE_RATE_PASS else Economy.OFFLINE_RATE
	local capHours = if hasOfflinePass
		then Economy.OFFLINE_CAP_HOURS_PASS
		else Economy.OFFLINE_CAP_HOURS
	local stop = math.min(now, profile.lastOnline + capHours * 3600)
	local sum = 0
	for _, state in profile.pedestals do
		local start = math.max(profile.lastOnline, state.hatchAt or 0)
		if stop > start then
			sum += Income.ofPedestal(state) * (stop - start)
		end
	end
	return math.floor(sum * rate * Income.multiplier(profile))
end

return table.freeze(Income)

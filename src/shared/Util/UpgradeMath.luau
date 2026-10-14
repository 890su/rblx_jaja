--!strict
local Shared = script.Parent.Parent
local Types = require(Shared.Types)
local Specs = require(Shared.Config.Upgrades)
local Speed = require(Shared.Config.Speed)
local UpgradeMath = {}
function UpgradeMath.spec(key: string): Specs.Spec?
	for _, spec in Specs do
		if spec.key == key then
			return spec
		end
	end
	return nil
end
function UpgradeMath.level(profile: Types.PlayerProfile, key: string): number
	if key == "training" then
		return profile.training
	end
	if key == "treadmill" then
		return profile.treadmill
	end
	if key == "warehouse" then
		return if profile.flags.warehouseOwned == true then 1 else 0
	end
	if key == "carryTraining" then
		return profile.carryTraining
	end
	return 0
end
function UpgradeMath.cost(key: string, level: number): number?
	local spec = UpgradeMath.spec(key)
	if not spec or level < 0 or level % 1 ~= 0 or level >= spec.max then
		return nil
	end
	if spec.installCost and level == 0 then
		return spec.installCost
	end
	return math.floor(spec.base * spec.growth ^ (level - (if spec.installCost then 1 else 0)))
end
function UpgradeMath.buy(profile: Types.PlayerProfile, key: string): (string, number)
	local level = UpgradeMath.level(profile, key)
	local cost = UpgradeMath.cost(key, level)
	if not cost then
		return "max", 0
	end
	if profile.coins < cost then
		return "funds", cost
	end
	profile.coins -= cost
	if key == "training" then
		profile.training += 1
	elseif key == "treadmill" then
		profile.treadmill += 1
	elseif key == "warehouse" then
		profile.flags.warehouseOwned = true
	elseif key == "carryTraining" then
		profile.carryTraining += 1
	end
	return "bought", cost
end
function UpgradeMath.treadmillRate(level: number): number
	local spec = assert(UpgradeMath.spec("treadmill"))
	return if level <= 0
		then 0
		else Speed.TREADMILL_RATE_NO_PASS
			* (1 + math.clamp(level - 1, 0, spec.max - 1) * spec.bonus)
end
function UpgradeMath.carryMultiplier(level: number): number
	local spec = assert(UpgradeMath.spec("carryTraining"))
	return Speed.CARRY_MULTIPLIER + math.clamp(level, 0, spec.max) * spec.bonus
end
return table.freeze(UpgradeMath)

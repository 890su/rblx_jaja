--!strict
-- Rebirth (GDD §4.6): spend the coin cost and meet the speed requirement to
-- reset Speed and coins for a permanent income/speed-gain multiplier and
-- access to deeper zones. Creatures and pedestals are kept.

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Format = require(Shared.Util.Format)
local RebirthMath = require(Shared.Util.RebirthMath)
local Remotes = require(Shared.Remotes)

local Notifier = require(script.Parent.Parent.Util.Notifier)
local RateLimit = require(script.Parent.Parent.Util.RateLimit)
local DataService = require(script.Parent.DataService)
local SpeedService = require(script.Parent.SpeedService)
local TelemetryService = require(script.Parent.TelemetryService)

local RebirthService = {}

local limit = RateLimit.new(2, 0.5)

local function onRebirth(player: Player)
	if not limit:allow(player) then
		return
	end
	local profile = DataService.get(player)
	if not profile then
		return
	end
	local cost = RebirthMath.cost(profile.rebirths)
	local speedNeeded = RebirthMath.speedRequired(profile.rebirths)
	if profile.speed < speedNeeded then
		Notifier.send(
			player,
			"rebirth_need_speed",
			{ amount = Format.short(speedNeeded) },
			"warning"
		)
		return
	end
	if profile.coins < cost then
		Notifier.send(player, "rebirth_need_coins", { amount = Format.short(cost) }, "warning")
		return
	end
	TelemetryService.economy(
		player,
		"sink",
		profile.coins,
		"Rebirth",
		`rebirth{profile.rebirths + 1}`
	)
	profile.rebirths += 1
	profile.coins = 0
	profile.speed = 0
	DataService.sync(player)
	SpeedService.apply(player)
	TelemetryService.funnel(player, "FirstRebirth")
	Notifier.send(player, "rebirth_done", { count = profile.rebirths }, "success")
end

function RebirthService.init()
	Remotes.event("Rebirth").OnServerEvent:Connect(onRebirth)
end

return RebirthService

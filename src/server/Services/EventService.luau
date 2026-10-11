--!strict
-- Meteor Shower (GDD §4.8): every SHOWER_PERIOD on the global clock, a burst
-- of boosted meteors lands in the deep zones for SHOWER_DURATION seconds.
-- Times are published as workspace attributes (server time) for the HUD.

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Events = require(Shared.Config.Events)
local Theme = require(Shared.Theme)
local Clock = require(Shared.Clock)
local Remotes = require(Shared.Remotes)

local MeteorService = require(script.Parent.MeteorService)

local TICK = 0.5

local EventService = {}

local warnedCycle = -1
local startedCycle = -1

local function startShower(remaining: number)
	local rng = Random.new()
	local zones = Events.SHOWER_ZONES
	for i = 1, Events.SHOWER_METEORS do
		local zone = zones[(i - 1) % #zones + 1]
		MeteorService.spawnEvent(zone, Events.SHOWER_RARITY_BOOST, remaining, rng)
	end
	Remotes.event("Notify")
		:FireAllClients(`{Theme.SHOWER_EVENT}! Boosted meteors in the deep zones`, "pickup")
	Remotes.event("Fx"):FireAllClients("shower", Vector3.zero, remaining)
end

-- Studio QA only (DebugService): start a shower right now.
function EventService.debugShower()
	startShower(Events.SHOWER_DURATION)
end

function EventService.start()
	while true do
		local now = Clock.now()
		local period = Events.SHOWER_PERIOD
		local cycle = math.floor(now / period)
		local phase = now - cycle * period
		workspace:SetAttribute("ShowerEndsAt", cycle * period + Events.SHOWER_DURATION)
		workspace:SetAttribute("NextShowerAt", (cycle + 1) * period)

		if phase < Events.SHOWER_DURATION and startedCycle ~= cycle then
			startedCycle = cycle
			startShower(Events.SHOWER_DURATION - phase)
		end
		if period - phase <= Events.SHOWER_WARNING and warnedCycle ~= cycle then
			warnedCycle = cycle
			Remotes.event("Notify")
				:FireAllClients(
					`{Theme.SHOWER_EVENT} in {Events.SHOWER_WARNING} seconds!`,
					"warning"
				)
		end
		task.wait(TICK)
	end
end

return EventService

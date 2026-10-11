--!strict
-- Thin wrapper over Roblox AnalyticsService (GDD §9). Funnel steps are logged
-- once per player (flags persisted in the profile).

local AnalyticsService = game:GetService("AnalyticsService")

local DataService = require(script.Parent.DataService)

local TelemetryService = {}

TelemetryService.FUNNEL = {
	"Loaded",
	"FirstPickup",
	"FirstPlace",
	"FirstHatch",
	"FirstCollect",
	"ReachedZone2",
	"FirstShopBuy",
	"FirstRebirth",
}

local STEP_INDEX: { [string]: number } = {}
for index, name in TelemetryService.FUNNEL do
	STEP_INDEX[name] = index
end

function TelemetryService.funnel(player: Player, step: string)
	local index = STEP_INDEX[step]
	local profile = DataService.get(player)
	if not index or not profile then
		return
	end
	local flag = `funnel_{step}`
	if profile.flags[flag] then
		return
	end
	profile.flags[flag] = true
	pcall(function()
		AnalyticsService:LogOnboardingFunnelStepEvent(player, index, step)
	end)
end

-- Economy flow for the soft currency. `source` = earned, `sink` = spent.
function TelemetryService.economy(
	player: Player,
	flow: "source" | "sink",
	amount: number,
	transaction: string,
	sku: string?
)
	local profile = DataService.get(player)
	if not profile or amount <= 0 then
		return
	end
	pcall(function()
		AnalyticsService:LogEconomyEvent(
			player,
			if flow == "source"
				then Enum.AnalyticsEconomyFlowType.Source
				else Enum.AnalyticsEconomyFlowType.Sink,
			"Stardust",
			amount,
			profile.coins,
			transaction,
			sku
		)
	end)
end

function TelemetryService.custom(player: Player, name: string, value: number?)
	pcall(function()
		AnalyticsService:LogCustomEvent(player, name, value or 1)
	end)
end

return TelemetryService

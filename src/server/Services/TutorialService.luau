--!strict
-- First-time experience (GDD §5). New players start with a Common meteor
-- already on pedestal 1 (hatches in 10 s = first reward < 30 s). The tutorial
-- ends when they have collected coins and reached the Ember Ridge gate speed;
-- TutorialDone is published for the client guide.

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Zones = require(Shared.Config.Zones)

local DataService = require(script.Parent.DataService)
local StationService = require(script.Parent.StationService)
local TelemetryService = require(script.Parent.TelemetryService)

local STARTER_CREATURE = "pebblit"

local TutorialService = {}

local function onLoaded(player: Player)
	TelemetryService.funnel(player, "Loaded")
	local profile = DataService.get(player)
	if not profile then
		return
	end
	player:SetAttribute("TutorialDone", profile.flags.tutorialDone == true)
	if profile.flags.ftueStarted then
		return
	end
	-- Wait for the station to be assigned (StationService.onLoaded runs in parallel).
	for _ = 1, 50 do
		if StationService.getPlot(player) then
			break
		end
		task.wait(0.1)
	end
	if StationService.placeNew(player, STARTER_CREATURE, nil) then
		profile.flags.ftueStarted = true
	end
end

function TutorialService.init()
	DataService.onLoaded(onLoaded)
end

function TutorialService.start()
	local gate = Zones.ZONES[2].speedGate
	while true do
		task.wait(1)
		for _, player in game:GetService("Players"):GetPlayers() do
			local profile = DataService.get(player)
			if
				profile
				and not profile.flags.tutorialDone
				and profile.coins > 0
				and profile.speed >= gate
			then
				profile.flags.tutorialDone = true
				player:SetAttribute("TutorialDone", true)
			end
		end
	end
end

return TutorialService

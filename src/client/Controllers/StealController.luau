--!strict
-- Hides Steal prompts that the server would reject anyway (own station, locked,
-- protected, empty pedestal, hands full). Purely cosmetic: StealService
-- re-validates every attempt.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")

local player = Players.LocalPlayer

local REFRESH_PERIOD = 0.3

local StealController = {}

local function shouldShow(prompt: ProximityPrompt): boolean
	local pedestal = prompt.Parent
	local plot = pedestal and pedestal.Parent
	if not pedestal or not plot then
		return false
	end
	local owner = plot:GetAttribute("OwnerUserId") :: number?
	if owner == nil or owner == player.UserId then
		return false
	end
	if ((plot:GetAttribute("LockedFor") :: number?) or 0) > 0 or plot:GetAttribute("Protected") then
		return false
	end
	if not pedestal:GetAttribute("Occupied") or player:GetAttribute("Carrying") ~= nil then
		return false
	end
	local victim = Players:GetPlayerByUserId(owner)
	if not victim then
		return false
	end
	if
		pedestal:GetAttribute("PaidCreature")
		and (
			player:GetAttribute("PaidItemTradingAllowed") ~= true
			or victim:GetAttribute("PaidItemTradingAllowed") ~= true
		)
	then
		return false
	end
	if
		((player:GetAttribute("StationOccupied") :: number?) or 0)
		>= ((player:GetAttribute("StationCapacity") :: number?) or 0)
	then
		return false
	end
	if
		pedestal:GetAttribute("Rarity") == "Mythic"
		and ((victim:GetAttribute("StationOccupied") :: number?) or 0) < 4
	then
		return false
	end
	return true
end

function StealController.start()
	while true do
		for _, instance in CollectionService:GetTagged("StealPrompt") do
			if instance:IsA("ProximityPrompt") then
				local show = shouldShow(instance)
				if instance.Enabled ~= show then
					instance.Enabled = show
				end
			end
		end
		task.wait(REFRESH_PERIOD)
	end
end

return StealController

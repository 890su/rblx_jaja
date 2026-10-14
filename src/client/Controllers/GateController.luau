--!strict
-- Makes zone gates solid for this player only while locked. Gates are
-- non-colliding on the server; local CanCollide applies to the locally simulated
-- character. Server-side enforcement lives in SpeedService.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")

local player = Players.LocalPlayer

local GateController = {}

local function isUnlocked(gate: BasePart): boolean
	local speed = (player:GetAttribute("Speed") :: number?) or 0
	local rebirths = (player:GetAttribute("Rebirths") :: number?) or 0
	local speedGate = (gate:GetAttribute("SpeedGate") :: number?) or 0
	local rebirthGate = (gate:GetAttribute("RebirthGate") :: number?) or 0
	return speed >= speedGate and rebirths >= rebirthGate
end

local function refreshGate(gate: Instance)
	if gate:IsA("BasePart") then
		local unlocked = isUnlocked(gate)
		gate.CanCollide = not unlocked
		gate.Transparency = if unlocked then 0.85 else 0.3
		for _, child in gate:GetChildren() do
			if child:IsA("SurfaceGui") then
				child.Enabled = not unlocked
			end
		end
	end
end

local function refreshAll()
	for _, gate in CollectionService:GetTagged("SpeedGate") do
		refreshGate(gate)
	end
end

function GateController.start()
	-- Gates stream in and out with StreamingEnabled; refresh on arrival.
	CollectionService:GetInstanceAddedSignal("SpeedGate"):Connect(refreshGate)
	player:GetAttributeChangedSignal("Speed"):Connect(refreshAll)
	player:GetAttributeChangedSignal("Rebirths"):Connect(refreshAll)
	refreshAll()
end

return GateController

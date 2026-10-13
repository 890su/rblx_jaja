--!strict
-- Visibility only; eligibility is independently enforced by MeteorService.
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local player = Players.LocalPlayer
local Controller = {}

local function refresh(instance: Instance)
	if not instance:IsA("BasePart") then
		return
	end
	local allowed = player:GetAttribute("PaidRandomItemsAllowed") == true
	local hidden = (instance:GetAttribute("Paid") == true and not allowed)
		or (instance:GetAttribute("RestrictedOnly") == true and allowed)
	instance.LocalTransparencyModifier = if hidden then 1 else 0
	for _, child in instance:GetDescendants() do
		if child:IsA("ProximityPrompt") then
			child.Enabled = not hidden
		end
		if child:IsA("BillboardGui") then
			child.Enabled = not hidden
		end
		if child:IsA("ParticleEmitter") then
			child.Enabled = not hidden
		end
		if child:IsA("BasePart") then
			child.LocalTransparencyModifier = if hidden then 1 else 0
		end
	end
end

function Controller.start()
	CollectionService:GetInstanceAddedSignal("FieldMeteor"):Connect(function(instance)
		task.defer(refresh, instance)
	end)
	player:GetAttributeChangedSignal("PaidRandomItemsAllowed"):Connect(function()
		for _, instance in CollectionService:GetTagged("FieldMeteor") do
			refresh(instance)
		end
	end)
	for _, instance in CollectionService:GetTagged("FieldMeteor") do
		refresh(instance)
	end
end

return Controller

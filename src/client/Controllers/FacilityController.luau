--!strict
local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")
local Shared = game.ReplicatedStorage.Shared
local Math = require(Shared.Util.UpgradeMath)
local Format = require(Shared.Util.Format)
local Locale = require(Shared.Locale)
local player = Players.LocalPlayer
local Controller = {}
local watched: { [ProximityPrompt]: { RBXScriptConnection } } = {}

local function refresh()
	for prompt in watched do
		local site = prompt.Parent
		local plot = site and site.Parent
		local key = prompt:GetAttribute("UpgradeKey")
		local spec = if typeof(key) == "string" then Math.spec(key) else nil
		local show = plot ~= nil
			and plot:GetAttribute("OwnerUserId") == player.UserId
			and plot:GetAttribute(`FacilityOwned_{key}`) ~= true
		if site and site:IsA("BasePart") then
			site.LocalTransparencyModifier = if show then 0 else 1
			local gui = site:FindFirstChild("Offer")
			if gui and gui:IsA("BillboardGui") then
				gui.Enabled = show and player:GetAttribute("MenuOpen") ~= true
			end
		end
		prompt.Enabled = show
			and player:GetAttribute("MenuOpen") ~= true
			and player:GetAttribute("Carrying") == nil
			and player:GetAttribute("ArenaActive") ~= true
			and player:GetAttribute("ArenaPrep") ~= true
		if spec and typeof(key) == "string" then
			prompt.ActionText = Locale.term("Build")
			prompt.ObjectText = Locale.t(
				"facility_offer",
				{ name = Locale.term(spec.title), amount = Format.short(assert(Math.cost(key, 0))) }
			)
		end
	end
end

local function watch(instance: Instance)
	if not instance:IsA("ProximityPrompt") or watched[instance] then
		return
	end
	local plot = instance.Parent and instance.Parent.Parent
	if not plot then
		return
	end
	watched[instance] = {
		plot:GetAttributeChangedSignal("OwnerUserId"):Connect(refresh),
		plot:GetAttributeChangedSignal(`FacilityOwned_{instance:GetAttribute("UpgradeKey")}`)
			:Connect(refresh),
	}
	refresh()
end

function Controller.start()
	CollectionService:GetInstanceAddedSignal("FacilityPrompt"):Connect(watch)
	CollectionService:GetInstanceRemovedSignal("FacilityPrompt"):Connect(function(instance)
		if instance:IsA("ProximityPrompt") and watched[instance] then
			for _, connection in watched[instance] do
				connection:Disconnect()
			end
			watched[instance] = nil
		end
	end)
	for _, prompt in CollectionService:GetTagged("FacilityPrompt") do
		watch(prompt)
	end
	for _, attribute in { "MenuOpen", "Carrying", "ArenaActive", "ArenaPrep" } do
		player:GetAttributeChangedSignal(attribute):Connect(refresh)
	end
end

return Controller

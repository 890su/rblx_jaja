--!strict
-- Station guidance for the owner:
-- * Unlock button on the next locked pedestal (price) and a Station Expansion
--   offer on pass-only pedestals (opens the game pass purchase).
-- * While carrying into a full station: suggests an income upgrade and shows
--   explicit replacement prompts. The owner chooses the occupied pedestal.
-- * HUD badge for creatures waiting in storage.

local CollectionService = game:GetService("CollectionService")
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Products = require(Shared.Config.Products)
local Format = require(Shared.Util.Format)
local Locale = require(Shared.Locale)

local UiKit = require(script.Parent.Parent.Lib.UiKit)

local player = Players.LocalPlayer

local REFRESH = 0.3

local StationController = {}

local replaceHighlight: Highlight
local replaceTag: BillboardGui
local storageLabel: TextLabel

local function myPlot(): Instance?
	local plots = workspace:FindFirstChild("World") and workspace.World:FindFirstChild("Plots")
	if not plots then
		return nil
	end
	for _, plot in plots:GetChildren() do
		if plot:GetAttribute("OwnerUserId") == player.UserId then
			return plot
		end
	end
	return nil
end

local function expansionPassId(): number
	for _, pass in Products.PASSES do
		if pass.key == "Expansion" then
			return pass.id
		end
	end
	return 0
end

local function refreshUnlockPrompts(plot: Instance?)
	for _, instance in CollectionService:GetTagged("UnlockPrompt") do
		if instance:IsA("ProximityPrompt") then
			local pedestal = instance.Parent
			local mine = plot ~= nil and pedestal ~= nil and pedestal.Parent == plot
			local cost = pedestal and pedestal:GetAttribute("UnlockCost") :: number?
			local offer = pedestal and pedestal:GetAttribute("ExpansionOffer") == true
			local show = mine and (cost ~= nil or offer)
			instance.Enabled = show
			if show then
				instance.ActionText = Locale.term("Unlock")
				instance.ObjectText = if cost
					then Locale.t("amount_coins", { amount = Format.short(cost) })
					else Locale.term("Station Expansion")
			end
		end
	end
end

local function refreshReplaceHint(plot: Instance?)
	local carrying = player:GetAttribute("Carrying") :: string?
	local carryIncome = (player:GetAttribute("CarryIncome") :: number?) or 0
	local target: BasePart? = nil
	if plot and carrying then
		local hasFree = false
		local weakest: BasePart? = nil
		local weakestIncome = math.huge
		for _, child in plot:GetChildren() do
			if child:IsA("BasePart") and child:GetAttribute("Unlocked") then
				local income = child:GetAttribute("Income") :: number?
				if not income then
					hasFree = true
				elseif income < weakestIncome then
					weakest, weakestIncome = child, income
				end
			end
		end
		if not hasFree and weakest and carryIncome > weakestIncome then
			target = weakest
		end
	end
	if target then
		local creature = target:FindFirstChild("Creature")
		replaceHighlight.Adornee = creature or target:FindFirstChild("CryoCapsule") or target
		replaceHighlight.Enabled = true
		replaceTag.Adornee = target
		replaceTag.Enabled = true
	else
		replaceHighlight.Enabled = false
		replaceTag.Enabled = false
	end
end

local function refreshReplacePrompts(plot: Instance?)
	local carrying = player:GetAttribute("Carrying") ~= nil
	for _, instance in CollectionService:GetTagged("ReplacePrompt") do
		if instance:IsA("ProximityPrompt") then
			local pedestal = instance.Parent
			instance.Enabled = carrying
				and player:GetAttribute("FacilityOwned_warehouse") == true
				and plot ~= nil
				and pedestal ~= nil
				and pedestal.Parent == plot
				and pedestal:GetAttribute("Unlocked") == true
				and pedestal:GetAttribute("Occupied") == true
			if instance.Enabled then
				instance.ActionText = Locale.term("Replace (keep old in storage)")
				instance.ObjectText = Locale.t("station_slot_income", {
					slot = pedestal:GetAttribute("Slot"),
					amount = Format.short((pedestal:GetAttribute("Income") :: number?) or 0),
				})
			end
		end
	end
end

local function refreshStorage()
	local count = (player:GetAttribute("StorageCount") :: number?) or 0
	storageLabel.Visible = count > 0 and player:GetAttribute("MenuOpen") ~= true
	if count > 0 then
		storageLabel.Text = Format.short(count)
	end
end

function StationController.init()
	replaceHighlight = Instance.new("Highlight")
	replaceHighlight.FillColor = Color3.fromRGB(255, 90, 90)
	replaceHighlight.FillTransparency = 0.6
	replaceHighlight.OutlineColor = Color3.fromRGB(255, 220, 120)
	replaceHighlight.Enabled = false
	replaceHighlight.Parent = workspace

	replaceTag = Instance.new("BillboardGui")
	replaceTag.Size = UDim2.fromOffset(140, 32)
	replaceTag.StudsOffset = Vector3.new(0, 9, 0)
	replaceTag.AlwaysOnTop = true
	replaceTag.Enabled = false
	UiKit.text(replaceTag, {
		Size = UDim2.fromScale(1, 1),
		Text = Locale.term("Suggested replacement"),
		TextColor3 = Color3.fromRGB(255, 220, 120),
		TextStrokeTransparency = 0.2,
	})
	replaceTag.Parent = player:WaitForChild("PlayerGui")

	storageLabel = UiKit.text(UiKit.gui(), {
		Name = "StorageBadge",
		Position = UDim2.fromOffset(52, 2),
		Size = UDim2.fromOffset(22, 22),
		BackgroundTransparency = 0,
		BackgroundColor3 = UiKit.BUTTON_COLOR,
		TextColor3 = Color3.new(1, 1, 1),
		Visible = false,
	})
	UiKit.corner(storageLabel, 11)
end

function StationController.start()
	ProximityPromptService.PromptTriggered:Connect(function(prompt, triggeredBy)
		if triggeredBy ~= player or prompt.Name ~= "UnlockPrompt" then
			return
		end
		local pedestal = prompt.Parent
		local id = expansionPassId()
		if pedestal and pedestal:GetAttribute("ExpansionOffer") and id ~= 0 then
			MarketplaceService:PromptGamePassPurchase(player, id)
		end
	end)
	player:GetAttributeChangedSignal("StorageCount"):Connect(refreshStorage)
	player:GetAttributeChangedSignal("MenuOpen"):Connect(refreshStorage)
	refreshStorage()
	while true do
		local plot = myPlot()
		refreshUnlockPrompts(plot)
		refreshReplaceHint(plot)
		refreshReplacePrompts(plot)
		task.wait(REFRESH)
	end
end

return StationController

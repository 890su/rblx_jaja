--!strict
local Players = game:GetService("Players")
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Specs = require(Shared.Config.Upgrades)
local Locale = require(Shared.Locale)
local Format = require(Shared.Util.Format)
local Math = require(Shared.Util.UpgradeMath)
local Remotes = require(Shared.Remotes)
local UiKit = require(script.Parent.Parent.Lib.UiKit)
local Preview = require(script.Parent.Parent.Lib.ItemPreview)
local player = Players.LocalPlayer
local Controller = {}
local cards: { [string]: { detail: TextLabel, buy: TextButton } } = {}
local function refresh()
	local coins = (player:GetAttribute("Coins") :: number?) or 0
	for key, card in cards do
		local pedestal = key == "pedestal"
		local level = player:GetAttribute(
				if pedestal then "PedestalCount" else `Upgrade_{key}`
			) :: number? or 0
		local cost = player:GetAttribute(
			if pedestal then "NextPedestalCost" else `UpgradeCost_{key}`
		) :: number?
		local spec = Math.spec(key)
		local effect = if key == "treadmill"
			then Locale.t(
				"upgrade_treadmill_effect",
				{ rate = string.format("%.2f", Math.treadmillRate(level)) }
			)
			elseif key == "carryTraining" then Locale.t(
				"upgrade_carry_effect",
				{ rate = math.floor(Math.carryMultiplier(level) * 100 + 0.5) }
			)
			elseif key == "training" then Locale.t(
				"upgrade_training_effect",
				{ bonus = math.floor(level * assert(spec).bonus * 100 + 0.5) }
			)
			else Locale.t("upgrade_pedestal_effect", { count = level })
		card.detail.Text = Locale.t("upgrade_level", { level = level }) .. " · " .. effect
		card.buy.Text = if not cost
			then Locale.term("Max level")
			else Locale.t("upgrade_buy", { amount = Format.short(cost) })
		UiKit.setEnabled(card.buy, cost ~= nil and coins >= cost)
		card.buy.BackgroundColor3 = if card.buy.Interactable
			then UiKit.BUTTON_COLOR
			else UiKit.DISABLED_COLOR
	end
end
function Controller.init()
	local panel = UiKit.panel("Upgrades", Locale.term("Upgrades"))
	local list = UiKit.list(panel, UDim2.fromScale(0.04, 0.15), UDim2.fromScale(0.92, 0.67))
	local entries = {
		{
			key = "pedestal",
			title = "Pedestals",
			description = "Unlock another slot for creature income",
		},
	}
	for _, spec in Specs do
		table.insert(
			entries,
			{ key = spec.key, title = spec.title, description = spec.description }
		)
	end
	for order, entry in entries do
		local frame = Instance.new("Frame")
		frame.Name, frame.Size, frame.LayoutOrder, frame.BackgroundColor3, frame.Parent =
			entry.key, UDim2.new(1, -10, 0, 126), order, UiKit.CARD_COLOR, list
		UiKit.corner(frame)
		local view = Preview.new(frame, UDim2.fromScale(0.01, 0.05), UDim2.fromScale(0.20, 0.90))
		Preview.set(view, entry.key)
		UiKit.text(frame, {
			Text = Locale.term(entry.title),
			Position = UDim2.fromScale(0.23, 0.04),
			Size = UDim2.fromScale(0.73, 0.22),
			TextXAlignment = Enum.TextXAlignment.Left,
		})
		UiKit.text(frame, {
			Text = Locale.term(entry.description),
			Position = UDim2.fromScale(0.23, 0.29),
			Size = UDim2.fromScale(0.73, 0.20),
			TextWrapped = true,
			TextXAlignment = Enum.TextXAlignment.Left,
		})
		local detail = UiKit.text(frame, {
			Position = UDim2.fromScale(0.23, 0.52),
			Size = UDim2.fromScale(0.73, 0.18),
			TextXAlignment = Enum.TextXAlignment.Left,
		})
		local buy = UiKit.button(frame, "…", {
			Name = "Buy",
			Position = UDim2.fromScale(0.23, 0.73),
			Size = UDim2.fromScale(0.73, 0.23),
		})
		buy.Activated:Connect(function()
			if not buy.Interactable then
				return
			end
			if entry.key == "pedestal" then
				Remotes.event("BuyPedestal"):FireServer()
			else
				Remotes.event("BuyUpgrade"):FireServer(entry.key)
			end
		end)
		cards[entry.key] = { detail = detail, buy = buy }
	end
	local back = UiKit.button(
		panel,
		Locale.term("Back to Shop"),
		{ Position = UDim2.fromScale(0.04, 0.86), Size = UDim2.fromScale(0.92, 0.10) }
	)
	back.Activated:Connect(function()
		UiKit.show("Shop")
		Remotes.event("RequestShopState"):FireServer()
	end)
	panel:GetPropertyChangedSignal("Visible"):Connect(refresh)
end
function Controller.start()
	for _, attribute in
		{
			"Coins",
			"PedestalCount",
			"NextPedestalCost",
			"Upgrade_training",
			"UpgradeCost_training",
			"Upgrade_treadmill",
			"UpgradeCost_treadmill",
			"Upgrade_carryTraining",
			"UpgradeCost_carryTraining",
		}
	do
		player:GetAttributeChangedSignal(attribute):Connect(refresh)
	end
	refresh()
end
return Controller

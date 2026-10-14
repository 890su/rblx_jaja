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
local cards: { [string]: { frame: Frame, detail: TextLabel, buy: TextButton } } = {}
local list: ScrollingFrame
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
			elseif key == "warehouse" then Locale.term(
				"Build a locker to store and exchange your creatures"
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
		local facility = key == "warehouse" or key == "treadmill"
		card.detail.Text = if facility and level == 0
			then Locale.t("facility_unbuilt")
			elseif key == "warehouse" then Locale.t("facility_ready")
			elseif key == "treadmill" and level == 1 then Locale.t("facility_ready")
				.. " · "
				.. effect
			else Locale.t(
				"upgrade_level",
				{ level = if key == "treadmill" then level - 1 else level }
			) .. " · " .. effect
		card.buy:SetAttribute("ExpectedLevel", level)
		card.buy.Text = if not cost
			then (if key == "warehouse"
				then Locale.t("facility_ready")
				else Locale.term("Max level"))
			else Locale.t(
				if facility and level == 0 then "facility_build" else "upgrade_buy",
				{ amount = Format.short(cost) }
			)
		UiKit.setEnabled(card.buy, cost ~= nil and coins >= cost)
		card.buy.BackgroundColor3 = if card.buy.Interactable
			then UiKit.BUTTON_COLOR
			else UiKit.DISABLED_COLOR
	end
end
function Controller.init()
	local panel = UiKit.panel("Upgrades", Locale.term("Upgrades"))
	list = UiKit.list(UiKit.body(panel, 56), UDim2.new(), UDim2.fromScale(1, 1))
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
			entry.key, UDim2.new(1, -10, 0, 156), order, UiKit.CARD_COLOR, list
		UiKit.surface(frame)
		local view = Preview.new(frame, UDim2.fromScale(0.01, 0.05), UDim2.fromScale(0.20, 0.90))
		Preview.set(view, entry.key)
		UiKit.text(frame, {
			Text = Locale.term(entry.title),
			Position = UDim2.new(0.23, 0, 0, 8),
			Size = UDim2.new(0.73, 0, 0, 26),
			TextXAlignment = Enum.TextXAlignment.Left,
		})
		local description = UiKit.text(frame, {
			Text = Locale.term(entry.description),
			Position = UDim2.new(0.23, 0, 0, 40),
			Size = UDim2.new(0.73, 0, 0, 28),
			TextWrapped = true,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextColor3 = UiKit.MUTED_COLOR,
		})
		local detail = UiKit.text(frame, {
			TextWrapped = true,
			Position = UDim2.new(0.23, 0, 0, 74),
			Size = UDim2.new(0.73, 0, 0, 20),
			TextXAlignment = Enum.TextXAlignment.Left,
		})
		local buy = UiKit.button(frame, "…", {
			Name = "Buy",
			Position = UDim2.new(0.23, 0, 1, -56),
			Size = UDim2.new(0.73, 0, 0, 48),
		})
		buy.Activated:Connect(function()
			if not buy.Interactable then
				return
			end
			if entry.key == "pedestal" then
				Remotes.event("BuyPedestal"):FireServer()
			else
				Remotes.event("BuyUpgrade"):FireServer(entry.key, buy:GetAttribute("ExpectedLevel"))
			end
		end)
		cards[entry.key] = { frame = frame, detail = detail, buy = buy }
		local function resize()
			local narrow = frame.AbsoluteSize.X < 420
			local short = list.AbsoluteSize.Y < 160
			frame.Size = UDim2.new(1, -10, 0, if short then 112 elseif narrow then 192 else 156)
			description.Visible = not short
			description.Size = UDim2.new(0.73, 0, 0, if narrow then 48 else 28)
			detail.Position = UDim2.new(0.23, 0, 0, if short then 36 elseif narrow then 100 else 74)
			detail.Size = UDim2.new(0.73, 0, 0, if short then 20 elseif narrow then 32 else 20)
		end
		frame:GetPropertyChangedSignal("AbsoluteSize"):Connect(resize)
		list:GetPropertyChangedSignal("AbsoluteSize"):Connect(resize)
		resize()
	end
	local back = UiKit.footer(panel, Locale.term("Back to Shop"), "Back")
	back.BackgroundColor3 = UiKit.CARD_COLOR
	back.Activated:Connect(function()
		UiKit.show("Shop")
		Remotes.event("RequestShopState"):FireServer()
	end)
	panel:GetPropertyChangedSignal("Visible"):Connect(refresh)
end
function Controller.open(key: string)
	UiKit.show("Upgrades")
	Remotes.event("RequestShopState"):FireServer()
	task.defer(function()
		local card = cards[key]
		if card then
			list.CanvasPosition = Vector2.new(
				0,
				math.max(
					0,
					list.CanvasPosition.Y + card.frame.AbsolutePosition.Y - list.AbsolutePosition.Y
				)
			)
		end
	end)
end
function Controller.start()
	Remotes.event("OpenUpgrade").OnClientEvent:Connect(function(key: unknown)
		if typeof(key) == "string" and cards[key] then
			Controller.open(key)
		end
	end)
	for _, attribute in
		{
			"Coins",
			"PedestalCount",
			"NextPedestalCost",
			"Upgrade_training",
			"UpgradeCost_training",
			"Upgrade_treadmill",
			"UpgradeCost_treadmill",
			"Upgrade_warehouse",
			"UpgradeCost_warehouse",
			"Upgrade_carryTraining",
			"UpgradeCost_carryTraining",
		}
	do
		player:GetAttributeChangedSignal(attribute):Connect(refresh)
	end
	refresh()
end
return Controller

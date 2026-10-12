--!strict
-- Owner inventory. Server snapshots include item keys so stale clicks cannot
-- exchange or sell a different creature after a steal / hatch / delivery.
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Remotes = require(Shared.Remotes)
local Locale = require(Shared.Locale)
local Theme = require(Shared.Theme)
local Economy = require(Shared.Config.Economy)
local Format = require(Shared.Util.Format)
local UiKit = require(script.Parent.Parent.Lib.UiKit)

local StationMenuController = {}
local snapshot: any = nil
local selectedSlot: number? = nil
local selectedStorage: number? = nil
local saleKey: string? = nil
local saleUntil = 0
local summary: TextLabel
local selection: TextLabel
local slotsList: ScrollingFrame
local storageList: ScrollingFrame
local swapButton: TextButton
local sellButton: TextButton

local function nameOf(item: any): string
	return if item
		then Locale.term(Theme.CREATURE_NAMES[item.creatureId] or item.rarity)
		else Locale.term("Empty")
end

local function detail(item: any): string
	if not item then
		return ""
	end
	local now = workspace:GetServerTimeNow()
	if item.hatchAt and item.hatchAt > now then
		return Locale.t("station_item_hatching", { time = Format.duration(item.hatchAt - now) })
	end
	return Locale.t("station_item_income", {
		amount = Format.short(item.income),
		mutation = if item.mutation then " ★ " .. Locale.term(item.mutation) else "",
	})
end

local function clear(list: ScrollingFrame)
	for _, child in list:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
end

local function refreshActions()
	local state = snapshot
	local item = state and selectedSlot and state.slots[tostring(selectedSlot)]
	local stored = state and selectedStorage and state.storage[selectedStorage]
	selection.Text = if selectedSlot
		then Locale.t("station_selection", { slot = selectedSlot, name = nameOf(item) })
		else Locale.term("Select a slot first")
	local canSwap = selectedSlot ~= nil and stored ~= nil
	swapButton.Text = Locale.term("Swap selected creature")
	swapButton.BackgroundColor3 = if canSwap then UiKit.BUTTON_COLOR else UiKit.DISABLED_COLOR
	swapButton.Active = canSwap
	local amount = if item then math.floor(item.income * Economy.SELL_SECONDS) else 0
	sellButton.Visible = item ~= nil
	sellButton.Text = Locale.t(
		if item
				and saleKey == item.key
				and os.clock() < saleUntil
			then "station_confirm_sell"
			else "station_sell_button",
		{ amount = Format.short(amount) }
	)
end

local function render()
	if not snapshot then
		return
	end
	local state = snapshot
	local slotsScroll, storageScroll = slotsList.CanvasPosition, storageList.CanvasPosition
	if selectedSlot and selectedSlot > state.capacity then
		selectedSlot = nil
	end
	if selectedStorage and not state.storage[selectedStorage] then
		selectedStorage = nil
	end
	clear(slotsList)
	clear(storageList)
	local used = 0
	for slot = 1, state.capacity do
		local item = state.slots[tostring(slot)]
		if item then
			used += 1
		end
		local b = UiKit.button(
			slotsList,
			Locale.t("station_slot_name", { slot = slot, name = nameOf(item) })
				.. "\n"
				.. detail(item),
			{
				Name = `Slot{slot}`,
				Size = UDim2.new(1, -8, 0, 58),
				LayoutOrder = slot,
				TextXAlignment = Enum.TextXAlignment.Left,
				BackgroundColor3 = if selectedSlot == slot
					then Color3.fromRGB(45, 130, 160)
					else UiKit.CARD_COLOR,
			}
		)
		b.Activated:Connect(function()
			selectedSlot = slot
			saleKey = nil
			render()
		end)
	end
	for index, item in state.storage do
		local b = UiKit.button(storageList, nameOf(item) .. "\n" .. detail(item), {
			Name = `Stored{index}`,
			Size = UDim2.new(1, -8, 0, 58),
			LayoutOrder = index,
			TextXAlignment = Enum.TextXAlignment.Left,
			BackgroundColor3 = if selectedStorage == index
				then Color3.fromRGB(65, 145, 90)
				else UiKit.CARD_COLOR,
		})
		b.Activated:Connect(function()
			selectedStorage = index
			saleKey = nil
			render()
		end)
	end
	if #state.storage == 0 then
		UiKit.text(
			storageList,
			{ Size = UDim2.new(1, -8, 0, 58), Text = Locale.term("Storage is empty") }
		)
	end
	summary.Text = Locale.t(
		"station_summary",
		{ used = used, capacity = state.capacity, stored = #state.storage }
	)
	refreshActions()
	task.defer(function()
		slotsList.CanvasPosition, storageList.CanvasPosition = slotsScroll, storageScroll
	end)
end

function StationMenuController.init()
	local panel = UiKit.panel("Station", Locale.term("Station management"))
	UiKit.text(panel, {
		Text = Locale.term(
			"Select a slot, then a creature from storage. The old creature is kept."
		),
		Position = UDim2.fromScale(0.04, 0.13),
		Size = UDim2.fromScale(0.92, 0.08),
		TextWrapped = true,
		TextColor3 = Color3.fromRGB(175, 210, 230),
	})
	summary = UiKit.text(
		panel,
		{ Position = UDim2.fromScale(0.04, 0.22), Size = UDim2.fromScale(0.92, 0.06), Text = "…" }
	)
	UiKit.text(panel, {
		Position = UDim2.fromScale(0.04, 0.29),
		Size = UDim2.fromScale(0.44, 0.05),
		Text = Locale.term("Station slots"),
	})
	UiKit.text(panel, {
		Position = UDim2.fromScale(0.52, 0.29),
		Size = UDim2.fromScale(0.44, 0.05),
		Text = Locale.term("Storage"),
	})
	slotsList = UiKit.list(panel, UDim2.fromScale(0.04, 0.35), UDim2.fromScale(0.44, 0.43))
	storageList = UiKit.list(panel, UDim2.fromScale(0.52, 0.35), UDim2.fromScale(0.44, 0.43))
	slotsList.Name, storageList.Name = "SlotsList", "StorageList"
	selection = UiKit.text(panel, {
		Position = UDim2.fromScale(0.04, 0.79),
		Size = UDim2.fromScale(0.92, 0.05),
		Text = Locale.term("Select a slot first"),
	})
	swapButton = UiKit.button(panel, Locale.term("Swap selected creature"), {
		Name = "SwapButton",
		Position = UDim2.fromScale(0.04, 0.87),
		Size = UDim2.fromScale(0.52, 0.09),
		BackgroundColor3 = UiKit.DISABLED_COLOR,
	})
	sellButton = UiKit.button(panel, "", {
		Name = "SellButton",
		Position = UDim2.fromScale(0.60, 0.87),
		Size = UDim2.fromScale(0.36, 0.09),
		BackgroundColor3 = Color3.fromRGB(170, 80, 65),
		Visible = false,
	})
	swapButton.Activated:Connect(function()
		if not snapshot or not selectedSlot or not selectedStorage then
			return
		end
		local item, stored =
			snapshot.slots[tostring(selectedSlot)], snapshot.storage[selectedStorage]
		if not stored then
			return
		end
		Remotes.event("StationAction"):FireServer(
			"swap",
			selectedSlot,
			selectedStorage,
			if item then item.key else "",
			stored.key
		)
		saleKey = nil
	end)
	sellButton.Activated:Connect(function()
		if not snapshot or not selectedSlot then
			return
		end
		local item = snapshot.slots[tostring(selectedSlot)]
		if not item then
			return
		end
		if saleKey == item.key and os.clock() < saleUntil then
			Remotes.event("StationAction"):FireServer("sell", selectedSlot, nil, item.key)
			saleKey = nil
		else
			saleKey = item.key
			saleUntil = os.clock() + 4
		end
		refreshActions()
	end)
	UiKit.sideButton(Locale.term("Station"), Color3.fromRGB(45, 130, 165), 6, function()
		UiKit.toggle("Station")
		saleKey = nil
		Remotes.event("StationAction"):FireServer("request")
	end)
end

function StationMenuController.start()
	Remotes.event("StationState").OnClientEvent:Connect(function(state)
		local old = snapshot
		if
			selectedStorage
			and old
			and (
				not state.storage[selectedStorage]
				or not old.storage[selectedStorage]
				or state.storage[selectedStorage].key ~= old.storage[selectedStorage].key
			)
		then
			selectedStorage = nil
		end
		if
			selectedSlot
			and saleKey
			and (
				not state.slots[tostring(selectedSlot)]
				or state.slots[tostring(selectedSlot)].key ~= saleKey
			)
		then
			saleKey = nil
		end
		snapshot = state
		render()
	end)
	while true do
		task.wait(2)
		if UiKit.isOpen("Station") then
			Remotes.event("StationAction"):FireServer("request")
		end
	end
end

return StationMenuController

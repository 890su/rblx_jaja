--!strict
-- Owner inventory. Server snapshots include item keys so stale clicks cannot
-- exchange or sell a different creature after a steal / hatch / delivery.
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Remotes = require(Shared.Remotes)
local Locale = require(Shared.Locale)
local Theme = require(Shared.Theme)
local Economy = require(Shared.Config.Economy)
local Format = require(Shared.Util.Format)
local GuiService = game:GetService("GuiService")
local UiKit = require(script.Parent.Parent.Lib.UiKit)
local Preview = require(script.Parent.Parent.Lib.ItemPreview)
local Players = game:GetService("Players")
local Warehouse = require(Shared.Config.Warehouse)
local UpgradeMath = require(Shared.Util.UpgradeMath)
local player = Players.LocalPlayer

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
local storeButton: TextButton
local buildButton: TextButton
local slotHighlight: Highlight
local rowHeight = 58
local layoutStation: () -> () = function() end
local usedCount = 0
local physicalSession = false

local function ownPlot(): Model?
	local world = workspace:FindFirstChild("World")
	local plots = world and world:FindFirstChild("Plots")
	if plots then
		for _, plot in plots:GetChildren() do
			if plot:IsA("Model") and plot:GetAttribute("OwnerUserId") == player.UserId then
				return plot
			end
		end
	end
	return nil
end

local function nearWarehouse(): boolean
	local plot = ownPlot()
	local locker = plot and plot:FindFirstChild("Warehouse")
	local screen = locker and locker:FindFirstChild("Screen")
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	return screen ~= nil
		and screen:IsA("BasePart")
		and root ~= nil
		and root:IsA("BasePart")
		and (root.Position - screen.Position).Magnitude <= Warehouse.manageDistance
		and player:GetAttribute("Carrying") == nil
end

local function decorateRow(button: TextButton, item: any)
	local padding = button:FindFirstChildOfClass("UIPadding")
	if padding then
		padding:Destroy()
	end
	local view = button:FindFirstChild("Preview") :: ViewportFrame?
	if not view then
		view = Preview.new(button, UDim2.fromOffset(4, 6), UDim2.fromOffset(40, 40))
	end
	Preview.set(
		assert(view, "missing inventory portrait"),
		if item then item.creatureId else "pedestal"
	)
	local label = button:FindFirstChild("Content") :: TextLabel?
	if not label then
		label = UiKit.text(button, {
			Name = "Content",
			Position = UDim2.fromOffset(50, 0),
			Size = UDim2.new(1, -56, 1, 0),
			TextXAlignment = Enum.TextXAlignment.Left,
			TextWrapped = true,
		})
	end
	button.TextTransparency = 1
	assert(label, "missing inventory label").Text = button.Text
	if button:GetAttribute("PortraitLayout") ~= true then
		button:SetAttribute("PortraitLayout", true)
		local function resize()
			local narrow = button.AbsoluteSize.X < 180
			local portrait =
				assert(button:FindFirstChild("Preview"), "missing row portrait") :: ViewportFrame
			local content =
				assert(button:FindFirstChild("Content"), "missing row text") :: TextLabel
			local size = if narrow then 28 else 40
			portrait.Size, portrait.Position =
				UDim2.fromOffset(size, size), UDim2.new(0, 4, 0.5, -size / 2)
			content.Position = UDim2.fromOffset(if narrow then 38 else 50, 0)
			content.Size = UDim2.new(1, if narrow then -44 else -56, 1, 0)
		end
		button:GetPropertyChangedSignal("AbsoluteSize"):Connect(resize)
		resize()
	end
end

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

local function trim(list: ScrollingFrame, keep: { [string]: boolean })
	for _, child in list:GetChildren() do
		if child:IsA("GuiObject") and not keep[child.Name] then
			if GuiService.SelectedObject == child then
				local panel = list:FindFirstAncestor("Station")
				GuiService.SelectedObject = if panel
					then panel:FindFirstChild("Menu") :: GuiButton?
					else nil
			end
			child:Destroy()
		end
	end
end

local function refreshActions()
	local state = snapshot
	local item = state and selectedSlot and state.slots[tostring(selectedSlot)]
	local stored = state and selectedStorage and state.storage[selectedStorage]
	local nearby = nearWarehouse()
	local owned = player:GetAttribute("FacilityOwned_warehouse") == true
	selection.Text = if not owned
		then Locale.t(
			"warehouse_build_hint",
			{ amount = Format.short(assert(UpgradeMath.cost("warehouse", 0))) }
		)
		elseif not nearby then Locale.t("warehouse_approach")
		elseif selectedSlot and (stored or item) then Locale.t(
			if stored and item
				then "warehouse_swap_preview"
				elseif stored then "warehouse_place_preview"
				else "warehouse_store_preview",
			{
				slot = selectedSlot,
				name = nameOf(item),
				incoming = nameOf(stored),
				outgoing = nameOf(item),
			}
		)
		else Locale.t("warehouse_hint")
	local canSwap = nearby and selectedSlot ~= nil and stored ~= nil
	swapButton.Visible = stored ~= nil
	storeButton.Visible = item ~= nil
	swapButton.Text = Locale.term(if item then "Swap selected creature" else "Place creature")
	swapButton.BackgroundColor3 = if canSwap then UiKit.BUTTON_COLOR else UiKit.DISABLED_COLOR
	UiKit.setEnabled(swapButton, canSwap)
	UiKit.setEnabled(storeButton, nearby and item ~= nil)
	storeButton.BackgroundColor3 = if nearby and item
		then UiKit.BUTTON_COLOR
		else UiKit.DISABLED_COLOR
	local amount = if item then math.floor(item.income * Economy.SELL_SECONDS) else 0
	sellButton.Visible = item ~= nil
	UiKit.setEnabled(sellButton, nearby and item ~= nil)
	sellButton.Text = Locale.t(
		if item
				and saleKey == item.key
				and os.clock() < saleUntil
			then "station_confirm_sell"
			else "station_sell_button",
		{ amount = Format.short(amount) }
	)
	local actions: { TextButton } = {}
	buildButton.Visible = not owned
	if not owned then
		swapButton.Visible, storeButton.Visible, sellButton.Visible = false, false, false
	end
	for _, button in { buildButton, swapButton, storeButton, sellButton } do
		if button.Visible then
			table.insert(actions, button)
		end
	end
	for index, button in actions do
		local inset = (32 + 8 * (#actions - 1)) / #actions
		button.Size = UDim2.new(1 / #actions, -inset, 0, 48)
		button.Position = UDim2.new((index - 1) / #actions, 16 + (index - 1) * (8 - inset), 1, -64)
	end
	local plot = ownPlot()
	local pedestal = plot and selectedSlot and plot:FindFirstChild(`Pedestal{selectedSlot}`)
	slotHighlight.Adornee = if pedestal
		then pedestal:FindFirstChild("CryoCapsule") or pedestal
		else nil
	slotHighlight.Enabled = UiKit.isOpen("Station") and pedestal ~= nil
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
	local keepSlots: { [string]: boolean } = {}
	local keepStorage: { [string]: boolean } = {}
	local used = 0
	for slot = 1, state.capacity do
		local item = state.slots[tostring(slot)]
		if item then
			used += 1
		end
		local name = `Slot{slot}`
		keepSlots[name] = true
		local existing = slotsList:FindFirstChild(name) :: TextButton?
		local b = existing
			or UiKit.button(slotsList, "", {
				Name = `Slot{slot}`,
				Size = UDim2.new(1, -8, 0, rowHeight),
				LayoutOrder = slot,
				TextXAlignment = Enum.TextXAlignment.Left,
				BackgroundColor3 = if selectedSlot == slot
					then Color3.fromRGB(45, 130, 160)
					else UiKit.CARD_COLOR,
			})
		b.Text = Locale.t("station_slot_name", { slot = slot, name = nameOf(item) })
			.. "\n"
			.. detail(item)
		b.BackgroundColor3 = if selectedSlot == slot then UiKit.BUTTON_COLOR else UiKit.CARD_COLOR
		decorateRow(b, item)
		if not existing then
			b.Activated:Connect(function()
				selectedSlot = slot
				saleKey = nil
				render()
			end)
		end
	end
	for index, item in state.storage do
		local name = `Stored{index}`
		keepStorage[name] = true
		local existing = storageList:FindFirstChild(name) :: TextButton?
		local b = existing
			or UiKit.button(storageList, "", {
				Name = `Stored{index}`,
				Size = UDim2.new(1, -8, 0, rowHeight),
				LayoutOrder = index,
				TextXAlignment = Enum.TextXAlignment.Left,
				BackgroundColor3 = if selectedStorage == index
					then Color3.fromRGB(65, 145, 90)
					else UiKit.CARD_COLOR,
			})
		b.Text = nameOf(item) .. "\n" .. detail(item)
		b.BackgroundColor3 = if selectedStorage == index
			then UiKit.BUTTON_COLOR
			else UiKit.CARD_COLOR
		decorateRow(b, item)
		if not existing then
			b.Activated:Connect(function()
				selectedStorage = index
				saleKey = nil
				render()
			end)
		end
	end
	if #state.storage == 0 then
		keepStorage.Empty = true
		if not storageList:FindFirstChild("Empty") then
			UiKit.text(storageList, {
				Name = "Empty",
				Size = UDim2.new(1, -8, 0, 58),
				Text = Locale.term("Storage is empty"),
			})
		end
	end
	trim(slotsList, keepSlots)
	trim(storageList, keepStorage)
	usedCount = used
	layoutStation()
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
	local panel = UiKit.panel("Station", Locale.term("Storage"))
	slotHighlight = Instance.new("Highlight")
	slotHighlight.Name, slotHighlight.Enabled = "StorageSelectedSlot", false
	slotHighlight.FillTransparency, slotHighlight.OutlineColor = 0.85, UiKit.ACCENT_COLOR
	slotHighlight.Parent = player:WaitForChild("PlayerGui")
	player:GetAttributeChangedSignal("MenuOpen"):Connect(function()
		if player:GetAttribute("MenuOpen") ~= true then
			slotHighlight.Enabled = false
			physicalSession = false
		end
	end)
	panel:GetPropertyChangedSignal("Visible"):Connect(function()
		if panel.Visible then
			refreshActions()
		else
			slotHighlight.Enabled = false
		end
	end)
	local body = UiKit.body(panel, 88)
	summary =
		UiKit.text(body, { Position = UDim2.new(), Size = UDim2.new(1, 0, 0, 24), Text = "…" })
	local slotsTitle = UiKit.text(body, {
		Position = UDim2.fromOffset(0, 32),
		Size = UDim2.new(0.48, 0, 0, 22),
		Text = Locale.term("Station slots"),
	})
	local storageTitle = UiKit.text(body, {
		Position = UDim2.new(0.52, 0, 0, 32),
		Size = UDim2.new(0.48, 0, 0, 22),
		Text = Locale.term("Storage"),
	})
	slotsList = UiKit.list(body, UDim2.fromOffset(0, 60), UDim2.new(0.48, 0, 1, -60))
	storageList = UiKit.list(body, UDim2.new(0.52, 0, 0, 60), UDim2.new(0.48, 0, 1, -60))
	slotsList.Name, storageList.Name = "SlotsList", "StorageList"
	layoutStation = function()
		local short = body.AbsoluteSize.Y < 120
		rowHeight = if short then 48 elseif body.AbsoluteSize.X < 400 then 72 else 58
		summary.Visible = not short
		slotsTitle.Position = UDim2.fromOffset(0, if short then 0 else 32)
		storageTitle.Position = UDim2.new(0.52, 0, 0, if short then 0 else 32)
		slotsTitle.Size = UDim2.new(0.48, 0, 0, if short then 14 else 22)
		storageTitle.Size = UDim2.new(0.48, 0, 0, if short then 14 else 22)
		local top = if short then 16 else 60
		slotsList.Position, slotsList.Size = UDim2.fromOffset(0, top), UDim2.new(0.48, 0, 1, -top)
		storageList.Position, storageList.Size =
			UDim2.new(0.52, 0, 0, top), UDim2.new(0.48, 0, 1, -top)
		for _, list in { slotsList, storageList } do
			for _, row in list:GetChildren() do
				if row:IsA("GuiObject") then
					row.Size = UDim2.new(1, -8, 0, rowHeight)
				end
			end
		end
		local title = panel:FindFirstChild("Title") :: TextLabel
		title.Text = if short and snapshot
			then Locale.t(
				"ui_station_compact_title",
				{ used = usedCount, capacity = snapshot.capacity }
			)
			else Locale.term("Storage")
	end
	body:GetPropertyChangedSignal("AbsoluteSize"):Connect(layoutStation)
	layoutStation()
	selection = UiKit.text(panel, {
		Position = UDim2.new(0, 16, 1, -104),
		Size = UDim2.new(1, -32, 0, 32),
		Text = Locale.t("ui_station_hint"),
		TextWrapped = true,
	})
	swapButton = UiKit.button(panel, Locale.term("Swap selected creature"), {
		Name = "SwapButton",
		Position = UDim2.new(0, 16, 1, -64),
		Size = UDim2.new(1 / 3, -16, 0, 48),
		BackgroundColor3 = UiKit.DISABLED_COLOR,
	})
	storeButton = UiKit.button(panel, Locale.term("Move to storage"), {
		Name = "StoreButton",
		Position = UDim2.new(1 / 3, 8, 1, -64),
		Size = UDim2.new(1 / 3, -16, 0, 48),
	})
	storeButton.Activated:Connect(function()
		local item = snapshot and selectedSlot and snapshot.slots[tostring(selectedSlot)]
		if item then
			Remotes.event("StationAction"):FireServer("store", selectedSlot, nil, item.key)
		end
		saleKey = nil
	end)
	sellButton = UiKit.button(panel, "", {
		Name = "SellButton",
		Position = UDim2.new(2 / 3, 0, 1, -64),
		Size = UDim2.new(1 / 3, -16, 0, 48),
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
	buildButton = UiKit.button(
		panel,
		Locale.t(
			"facility_build",
			{ amount = Format.short(assert(UpgradeMath.cost("warehouse", 0))) }
		),
		{
			Name = "BuildStorageButton",
			Size = UDim2.new(1, -32, 0, 48),
			Position = UDim2.new(0, 16, 1, -64),
			Visible = false,
		}
	)
	buildButton.Activated:Connect(function()
		Remotes.event("BuyUpgrade"):FireServer("warehouse", 0)
	end)
	player:GetAttributeChangedSignal("FacilityOwned_warehouse"):Connect(refreshActions)
	UiKit.sideButton(Locale.term("Station"), Color3.fromRGB(45, 130, 165), 6, function()
		physicalSession = false
		UiKit.toggle("Station")
		saleKey = nil
		Remotes.event("StationAction"):FireServer("request")
		refreshActions()
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
		if state.openStorage then
			physicalSession = true
			selectedSlot, selectedStorage, saleKey = 1, nil, nil
			if #state.storage > 0 then
				selectedStorage = 1
				for slot = 1, state.capacity do
					if not state.slots[tostring(slot)] then
						selectedSlot = slot
						break
					end
				end
			end
			UiKit.show("Station")
		end
		render()
	end)
	while true do
		task.wait(2)
		if UiKit.isOpen("Station") then
			if physicalSession and not nearWarehouse() then
				UiKit.close()
			else
				Remotes.event("StationAction"):FireServer("request")
			end
		end
	end
end

return StationMenuController

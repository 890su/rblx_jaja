--!strict
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Types = require(Shared.Types)
local Creatures = require(Shared.Config.Creatures)
local Rarity = require(Shared.Config.Rarity)
local Theme = require(Shared.Theme)
local Locale = require(Shared.Locale)
local Remotes = require(Shared.Remotes)
local Format = require(Shared.Util.Format)
local UiKit = require(script.Parent.Parent.Lib.UiKit)
local Preview = require(script.Parent.Parent.Lib.ItemPreview)
local IndexController = {}
local state: Types.IndexState = { discovered = {} }
local cards: { [string]: { view: ViewportFrame, name: TextLabel, detail: TextLabel } } = {}
local panel: Frame
local summary: TextLabel
local progress: Frame
local filters: { [string]: TextButton } = {}
local selectedFilter = "All"
local list: ScrollingFrame
local empty: TextLabel
local function render()
	if not panel.Visible then
		return
	end
	local count = 0
	local visible = 0
	for _, creature in Creatures.LIST do
		local known = state.discovered[creature.id] == true
		if known then
			count += 1
		end
		local entry = cards[creature.id]
		local card = entry.view.Parent :: Frame
		card.Visible = selectedFilter == "All"
			or (selectedFilter == "Discovered" and known)
			or (selectedFilter == "Undiscovered" and not known)
		if card.Visible then
			visible += 1
		end
		Preview.set(entry.view, creature.id, not known)
		entry.name.Text = if known
			then Locale.term(Theme.CREATURE_NAMES[creature.id])
			else Locale.term("Undiscovered")
		entry.detail.Text = if known
			then Locale.t("index_detail", {
				rarity = Locale.ref(creature.rarity),
				zone = creature.zone,
				income = Format.short(Rarity.INFO[creature.rarity].incomePerSecond),
			})
			else Locale.t(
				"index_locked",
				{ rarity = Locale.ref(creature.rarity), zone = creature.zone }
			)
	end
	summary.Text = Locale.t("ui_collection_progress", { count = count, total = #Creatures.LIST })
	progress.Size = UDim2.fromScale(count / #Creatures.LIST, 1)
	list.Visible, empty.Visible = visible > 0, visible == 0
	for name, b in filters do
		b.BackgroundColor3 = if name == selectedFilter then UiKit.BUTTON_COLOR else UiKit.CARD_COLOR
		b:SetAttribute("Selected", name == selectedFilter)
	end
end
function IndexController.init()
	panel = UiKit.panel("Index", Locale.term("Creature Index"))
	local body = UiKit.body(panel)
	summary = UiKit.text(body, {
		Position = UDim2.new(),
		Size = UDim2.new(1, 0, 0, 24),
		TextXAlignment = Enum.TextXAlignment.Left,
	})
	local track = Instance.new("Frame")
	track.Name, track.Position, track.Size =
		"Progress", UDim2.fromOffset(0, 28), UDim2.new(1, -8, 0, 4)
	track.BackgroundColor3, track.BorderSizePixel, track.Parent = UiKit.CARD_COLOR, 0, body
	UiKit.corner(track, 2)
	progress = Instance.new("Frame")
	progress.Name, progress.BackgroundColor3, progress.BorderSizePixel, progress.Parent =
		"Fill", UiKit.ACCENT_COLOR, 0, track
	UiKit.corner(progress, 2)
	for order, name in { "All", "Discovered", "Undiscovered" } do
		local b = UiKit.button(body, Locale.term(name), {
			Name = name,
			Position = UDim2.new((order - 1) / 3, 0, 0, 40),
			Size = UDim2.new(1 / 3, -8, 0, 48),
			BackgroundColor3 = UiKit.CARD_COLOR,
		})
		filters[name] = b
		b.Activated:Connect(function()
			selectedFilter = name
			list.CanvasPosition = Vector2.zero
			render()
		end)
	end
	list = UiKit.list(body, UDim2.fromOffset(0, 100), UDim2.new(1, 0, 1, -100))
	list.Name = "Creatures"
	empty = UiKit.text(body, {
		Name = "Empty",
		Text = Locale.t("ui_collection_empty"),
		Position = UDim2.fromOffset(0, 100),
		Size = UDim2.new(1, -8, 1, -100),
		TextWrapped = true,
		TextColor3 = UiKit.MUTED_COLOR,
		Visible = false,
	})
	assert(list:FindFirstChildOfClass("UIListLayout"), "missing index layout"):Destroy()
	local layout = Instance.new("UIGridLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.CellPadding = UDim2.new(0.025, 0, 0, 10)
	layout.CellSize = UDim2.new(0.315, 0, 0, 184)
	layout.Parent = list
	local function resize()
		local short = list.AbsoluteSize.Y < 125
		layout.CellSize = UDim2.new(
			if short then 0.98 elseif list.AbsoluteSize.X < 500 then 0.48 else 0.315,
			0,
			0,
			if short then math.max(80, list.AbsoluteSize.Y - 4) else 184
		)
		for _, entry in cards do
			entry.view.Position = if short
				then UDim2.fromScale(0.02, 0.08)
				else UDim2.fromScale(0.04, 0.02)
			entry.view.Size = if short
				then UDim2.fromScale(0.24, 0.80)
				else UDim2.fromScale(0.92, 0.60)
			entry.name.Position = if short
				then UDim2.fromScale(0.28, 0.05)
				else UDim2.fromScale(0.04, 0.64)
			entry.name.Size = if short
				then UDim2.fromScale(0.70, 0.24)
				else UDim2.fromScale(0.92, 0.14)
			entry.detail.Position = if short
				then UDim2.fromScale(0.28, 0.32)
				else UDim2.fromScale(0.04, 0.80)
			entry.detail.Size = if short
				then UDim2.fromScale(0.70, 0.58)
				else UDim2.fromScale(0.92, 0.18)
		end
	end
	list:GetPropertyChangedSignal("AbsoluteSize"):Connect(resize)
	resize()
	for order, creature in Creatures.LIST do
		local card = Instance.new("Frame")
		card.Name, card.LayoutOrder, card.Size = creature.id, order, UDim2.new(0.315, 0, 0, 184)
		card.BackgroundColor3, card.Parent = UiKit.CARD_COLOR, list
		UiKit.surface(card, Theme.RARITY_COLORS[creature.rarity])
		cards[creature.id] = {
			view = Preview.new(card, UDim2.fromScale(0.04, 0.02), UDim2.fromScale(0.92, 0.60)),
			name = UiKit.text(
				card,
				{ Position = UDim2.fromScale(0.04, 0.64), Size = UDim2.fromScale(0.92, 0.14) }
			),
			detail = UiKit.text(card, {
				Position = UDim2.fromScale(0.04, 0.80),
				Size = UDim2.fromScale(0.92, 0.18),
				TextWrapped = true,
				TextColor3 = Theme.RARITY_COLORS[creature.rarity],
			}),
		}
	end
	resize()
	panel:GetPropertyChangedSignal("Visible"):Connect(render)
	UiKit.sideButton(Locale.term("Creature Index"), Color3.fromRGB(120, 105, 210), 7, function()
		UiKit.toggle("Index")
		if panel.Visible then
			Remotes.event("RequestIndex"):FireServer()
		end
	end)
end
function IndexController.start()
	Remotes.event("IndexState").OnClientEvent:Connect(function(snapshot: Types.IndexState)
		state = snapshot
		render()
	end)
	Remotes.event("RequestIndex"):FireServer()
end
return IndexController

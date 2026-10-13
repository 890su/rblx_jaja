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
local function render()
	if not panel.Visible then
		return
	end
	local count = 0
	for _, creature in Creatures.LIST do
		local known = state.discovered[creature.id] == true
		if known then
			count += 1
		end
		local entry = cards[creature.id]
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
	summary.Text = Locale.t("index_summary", { count = count, total = #Creatures.LIST })
end
function IndexController.init()
	panel = UiKit.panel("Index", Locale.term("Creature Index"))
	local body = UiKit.body(panel)
	summary = UiKit.text(body, { Position = UDim2.new(), Size = UDim2.new(1, 0, 0, 28) })
	local list = UiKit.list(body, UDim2.fromOffset(0, 36), UDim2.new(1, 0, 1, -36))
	assert(list:FindFirstChildOfClass("UIListLayout"), "missing index layout"):Destroy()
	local layout = Instance.new("UIGridLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.CellPadding = UDim2.new(0.025, 0, 0, 10)
	layout.CellSize = UDim2.new(0.315, 0, 0, 184)
	layout.Parent = list
	local function resize()
		layout.CellSize = UDim2.new(if list.AbsoluteSize.X < 500 then 0.48 else 0.315, 0, 0, 184)
	end
	list:GetPropertyChangedSignal("AbsoluteSize"):Connect(resize)
	resize()
	for order, creature in Creatures.LIST do
		local card = Instance.new("Frame")
		card.Name, card.LayoutOrder, card.Size = creature.id, order, UDim2.new(0.315, 0, 0, 184)
		card.BackgroundColor3, card.Parent = UiKit.CARD_COLOR, list
		UiKit.corner(card)
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

--!strict
-- Stations (bases): plot assignment, pedestals, hatch timers, server income
-- tick, the coin collector, overflow storage and creature visuals. All state
-- lives in the player's profile; the world objects are a view refreshed once
-- per tick. Game pass effects are read from server-set Player attributes
-- (Pass_<key>, written by MonetizationService).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Types = require(Shared.Types)
local Economy = require(Shared.Config.Economy)
local Speed = require(Shared.Config.Speed)
local Rarity = require(Shared.Config.Rarity)
local Creatures = require(Shared.Config.Creatures)
local Theme = require(Shared.Theme)
local Format = require(Shared.Util.Format)
local Remotes = require(Shared.Remotes)

local Income = require(script.Parent.Parent.Data.Income)
local DataService = require(script.Parent.DataService)
local WorldService = require(script.Parent.WorldService)
local SpeedService = require(script.Parent.SpeedService)
local TelemetryService = require(script.Parent.TelemetryService)

type Plot = WorldService.Plot

local StationService = {}

local plotOwner: { [number]: Player } = {}
local playerPlot: { [Player]: Plot } = {}
local storedCoins: { [Player]: number } = {}
local collectDebounce: { [Player]: number } = {}

local notify: RemoteEvent
local fx: RemoteEvent

local isHatched = Income.isHatched
local incomeOf = Income.ofPedestal

local AURA_BRIGHTNESS: { [string]: number } = {
	Common = 0,
	Uncommon = 0.6,
	Rare = 1,
	Epic = 1.5,
	Legendary = 2.2,
	Mythic = 3,
}

local function hasPass(player: Player?, key: string): boolean
	return player ~= nil and player:GetAttribute(`Pass_{key}`) == true
end

-- Pass multipliers on income: 2x Coins and VIP.
function StationService.passIncomeMultiplier(player: Player): number
	local multiplier = 1
	if hasPass(player, "Coins2x") then
		multiplier *= Economy.COINS_PASS_MULTIPLIER
	end
	if hasPass(player, "VIP") then
		multiplier *= 1 + Economy.VIP_COIN_BONUS
	end
	return multiplier
end

-- Usable pedestals: coin-unlocked count + Station Expansion pass.
function StationService.capacity(player: Player, profile: Types.PlayerProfile): number
	local bonus = if hasPass(player, "Expansion") then Economy.PEDESTALS_EXPANSION_PASS else 0
	return profile.pedestalCount + bonus
end

function StationService.incomePerSecond(player: Player, profile: Types.PlayerProfile): number
	return Income.perSecond(profile, os.time(), StationService.passIncomeMultiplier(player))
end

local function creatureName(state: Types.PedestalState): string
	local name = Theme.CREATURE_NAMES[state.creatureId] or state.rarity
	return if state.mutation then `{state.mutation} {name}` else name
end

local function ensureView(pedestal: BasePart): (TextLabel, Part)
	local gui = pedestal:FindFirstChild("Info") :: BillboardGui?
	if not gui then
		local newGui = Instance.new("BillboardGui")
		newGui.Name = "Info"
		newGui.Size = UDim2.fromOffset(160, 50)
		newGui.StudsOffset = Vector3.new(0, 7, 0)
		newGui.MaxDistance = 80
		local label = Instance.new("TextLabel")
		label.Name = "Label"
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundTransparency = 1
		label.TextScaled = true
		label.Font = Enum.Font.FredokaOne
		label.TextStrokeTransparency = 0.3
		label.TextColor3 = Color3.new(1, 1, 1)
		label.Parent = newGui
		newGui.Parent = pedestal
		gui = newGui
	end
	local orb = pedestal:FindFirstChild("Orb") :: Part?
	if not orb then
		local newOrb = Instance.new("Part")
		newOrb.Name = "Orb"
		newOrb.Shape = Enum.PartType.Ball
		newOrb.Size = Vector3.new(4, 4, 4)
		newOrb.Anchored = true
		newOrb.CanCollide = false
		newOrb.CanQuery = false
		newOrb.Material = Enum.Material.Neon
		newOrb.CFrame = pedestal.CFrame + Vector3.new(0, 3.2, 0)
		newOrb.Parent = pedestal
		orb = newOrb
	end
	return (gui :: BillboardGui):FindFirstChild("Label") :: TextLabel, orb :: Part
end

-- Puts the creature's 3D model (ReplicatedStorage.Assets.Creatures.<id>) on the
-- pedestal, with a rarity aura. Returns false if no model exists (orb fallback).
local function showCreature(pedestal: BasePart, state: Types.PedestalState?): boolean
	local key = if state then `{state.creatureId}|{state.mutation or ""}` else ""
	if pedestal:GetAttribute("CreatureKey") == key then
		return pedestal:FindFirstChild("Creature") ~= nil
	end
	pedestal:SetAttribute("CreatureKey", key)
	local old = pedestal:FindFirstChild("Creature")
	if old then
		old:Destroy()
	end
	local light = pedestal:FindFirstChild("Aura") :: PointLight?
	if light then
		light:Destroy()
	end
	if not state then
		return false
	end
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local folder = assets and assets:FindFirstChild("Creatures")
	local template = folder and folder:FindFirstChild(state.creatureId)
	if not template or not template:IsA("Model") then
		return false
	end
	local model = template:Clone()
	model.Name = "Creature"
	local box, size = model:GetBoundingBox()
	local target = pedestal.Position + Vector3.new(0, pedestal.Size.Y / 2 + size.Y / 2 + 0.05, 0)
	model:PivotTo(model:GetPivot() + (target - box.Position))
	if state.mutation == "Golden" then
		local highlight = Instance.new("Highlight")
		highlight.FillColor = Color3.fromRGB(255, 200, 40)
		highlight.FillTransparency = 0.55
		highlight.OutlineColor = Color3.fromRGB(255, 240, 150)
		highlight.Parent = model
	end
	model.Parent = pedestal
	local brightness = AURA_BRIGHTNESS[state.rarity] or 0
	if brightness > 0 then
		local aura = Instance.new("PointLight")
		aura.Name = "Aura"
		aura.Color = Theme.RARITY_COLORS[state.rarity]
		aura.Brightness = brightness
		aura.Range = 10
		aura.Parent = pedestal
	end
	return true
end

local function refreshPlot(plot: Plot, profile: Types.PlayerProfile?)
	local now = os.time()
	local owner = plotOwner[plot.index]
	local capacity = if profile and owner then StationService.capacity(owner, profile) else 0
	for slot, pedestal in plot.pedestals do
		local label, orb = ensureView(pedestal)
		local state = profile and profile.pedestals[tostring(slot)]
		local unlocked = profile ~= nil and slot <= capacity
		pedestal:SetAttribute("Occupied", state ~= nil)
		pedestal.Transparency = if unlocked then 0 else 0.7
		pedestal.Color = if hasPass(owner, "VIP")
			then Color3.fromRGB(230, 185, 60)
			else Color3.fromRGB(90, 95, 120)
		if state then
			local color = Theme.RARITY_COLORS[state.rarity]
			label.TextColor3 = color
			if isHatched(state, now) then
				local hasModel = showCreature(pedestal, state)
				orb.Transparency = if hasModel then 1 else 0
				orb.Color = color
				orb.Size = Vector3.new(4, 4, 4)
				label.Text = `{creatureName(state)}\n+{Format.short(incomeOf(state))}/s`
			else
				showCreature(pedestal, nil)
				orb.Transparency = 0.25
				orb.Color = color
				orb.Size = Vector3.new(2.5, 2.5, 2.5)
				label.Text = `{state.rarity} {Theme.ITEM}\n{Format.duration(
					(state.hatchAt :: number) - now
				)}`
			end
		else
			showCreature(pedestal, nil)
			orb.Transparency = 1
			label.TextColor3 = Color3.new(1, 1, 1)
			label.Text = if not profile then "" elseif unlocked then "Empty" else "Locked"
		end
	end
end

local function setOwnerSign(plot: Plot, player: Player?)
	local sign = plot.model:FindFirstChild("Sign")
	local label = sign and sign:FindFirstChild("Owner", true) :: TextLabel?
	if label then
		label.Text = if player then `{player.DisplayName}'s {Theme.BASE}` else `Empty {Theme.BASE}`
	end
end

local function spawnAtPlot(player: Player, character: Model)
	local plot = playerPlot[player]
	if plot then
		SpeedService.markTeleport(player)
		character:PivotTo(plot.spawn)
	end
end

local function assignPlot(player: Player, profile: Types.PlayerProfile)
	for _, plot in WorldService.getPlots() do
		if not plotOwner[plot.index] then
			plotOwner[plot.index] = player
			playerPlot[player] = plot
			local offline = Income.offline(
				profile,
				os.time(),
				hasPass(player, "OfflinePlus"),
				StationService.passIncomeMultiplier(player)
			)
			storedCoins[player] = offline
			profile.lastOnline = os.time()
			setOwnerSign(plot, player)
			refreshPlot(plot, profile)
			-- Player attributes always replicate (plot parts may be streamed out).
			player:SetAttribute("HomePosition", plot.center)
			player.CharacterAdded:Connect(function(character)
				task.defer(spawnAtPlot, player, character)
			end)
			if player.Character then
				spawnAtPlot(player, player.Character)
			end
			if offline > 0 then
				task.delay(3, function()
					notify:FireClient(
						player,
						`Welcome back! Your creatures made {Format.short(offline)} {Theme.CURRENCY}`,
						"coins"
					)
				end)
			end
			return
		end
	end
	warn(`[StationService] no free plot for {player.Name}`)
end

local function releasePlot(player: Player)
	local plot = playerPlot[player]
	if not plot then
		return
	end
	plotOwner[plot.index] = nil
	playerPlot[player] = nil
	storedCoins[player] = nil
	collectDebounce[player] = nil
	setOwnerSign(plot, nil)
	refreshPlot(plot, nil)
end

local COLLECT_RADIUS = Vector3.new(7, 8, 5) -- half-extents around the collector pad
local COLLECT_CHECK_PERIOD = 0.2

local function bank(player: Player, plot: Plot, silent: boolean)
	local amount = math.floor(storedCoins[player] or 0)
	if amount <= 0 then
		return
	end
	storedCoins[player] -= amount
	DataService.addCoins(player, amount)
	TelemetryService.economy(player, "source", amount, "Income")
	TelemetryService.funnel(player, "FirstCollect")
	if not silent then
		notify:FireClient(player, `+{Format.short(amount)} {Theme.CURRENCY}`, "coins")
		fx:FireClient(player, "collect", plot.collector.Position, amount)
	end
end

-- Server-side proximity instead of Touched: reliable for non-colliding pads
-- and can't be spoofed by firing touch events from the client.
local function tryCollect(player: Player, plot: Plot)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return
	end
	local offset = root.Position - plot.collector.Position
	if
		math.abs(offset.X) > COLLECT_RADIUS.X
		or math.abs(offset.Y) > COLLECT_RADIUS.Y
		or math.abs(offset.Z) > COLLECT_RADIUS.Z
	then
		return
	end
	local now = os.clock()
	if (collectDebounce[player] or 0) > now then
		return
	end
	collectDebounce[player] = now + 1
	bank(player, plot, false)
end

function StationService.getPlot(player: Player): Plot?
	return playerPlot[player]
end

function StationService.ownerOf(plot: Plot): Player?
	return plotOwner[plot.index]
end

function StationService.creatureCount(profile: Types.PlayerProfile): number
	local count = 0
	for _ in profile.pedestals do
		count += 1
	end
	return count
end

function StationService.hasFreePedestal(player: Player): boolean
	local profile = DataService.get(player)
	if not profile then
		return false
	end
	for slot = 1, StationService.capacity(player, profile) do
		if not profile.pedestals[tostring(slot)] then
			return true
		end
	end
	return false
end

function StationService.refresh(player: Player)
	local plot = playerPlot[player]
	local profile = DataService.get(player)
	if plot and profile then
		refreshPlot(plot, profile)
	end
end

-- Puts an existing pedestal state (e.g. stolen or returned) on a free unlocked
-- pedestal, preferring `preferredSlot`. Keeps hatch timer and mutation.
function StationService.placeState(
	player: Player,
	state: Types.PedestalState,
	preferredSlot: string?
): boolean
	local profile = DataService.get(player)
	local plot = playerPlot[player]
	if not profile or not plot or not Creatures.BY_ID[state.creatureId] then
		return false
	end
	local capacity = StationService.capacity(player, profile)
	local key: string? = nil
	if
		preferredSlot
		and not profile.pedestals[preferredSlot]
		and tonumber(preferredSlot) :: number <= capacity
	then
		key = preferredSlot
	else
		for slot = 1, capacity do
			if not profile.pedestals[tostring(slot)] then
				key = tostring(slot)
				break
			end
		end
	end
	if not key then
		return false
	end
	profile.pedestals[key] = table.clone(state)
	refreshPlot(plot, profile)
	return true
end

-- Places a freshly picked-up meteor and starts its hatch timer.
function StationService.placeNew(player: Player, creatureId: string, mutation: string?): boolean
	local creature = Creatures.BY_ID[creatureId]
	if not creature then
		return false
	end
	return StationService.placeState(player, {
		creatureId = creatureId,
		rarity = creature.rarity,
		mutation = mutation,
		hatchAt = os.time() + Rarity.INFO[creature.rarity].hatchSeconds,
	})
end

-- Gives a creature from a purchase/reward: on a free pedestal, else into
-- overflow storage (placed automatically when a pedestal frees up).
function StationService.give(
	player: Player,
	state: Types.PedestalState
): "placed" | "stored" | "failed"
	local profile = DataService.get(player)
	if not profile or not Creatures.BY_ID[state.creatureId] then
		return "failed"
	end
	if StationService.placeState(player, state) then
		return "placed"
	end
	table.insert(profile.storage, table.clone(state))
	return "stored"
end

-- Removes and returns the state on a pedestal (used by stealing).
function StationService.takeState(player: Player, slot: string): Types.PedestalState?
	local profile = DataService.get(player)
	local state = profile and profile.pedestals[slot]
	if not profile or not state then
		return nil
	end
	profile.pedestals[slot] = nil
	local plot = playerPlot[player]
	if plot then
		refreshPlot(plot, profile)
	end
	return state
end

local function tickStation(player: Player, plot: Plot, profile: Types.PlayerProfile)
	-- Treadmill: AFK speed while standing on your own treadmill.
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if root then
		local offset = root.Position - plot.treadmill.Position
		if math.abs(offset.X) <= 4.5 and math.abs(offset.Z) <= 7.5 and offset.Y < 6 then
			local gain = Speed.GAIN_PER_SECOND * Speed.TREADMILL_RATE_NO_PASS
			DataService.setSpeed(player, profile.speed + gain * SpeedService.gainMultiplier(player))
		end
	end

	-- Overflow storage drains onto free pedestals.
	while #profile.storage > 0 and StationService.placeState(player, profile.storage[1]) do
		table.remove(profile.storage, 1)
	end

	local now = os.time()
	profile.lastOnline = now
	profile.playtimeTotal += Economy.INCOME_TICK_SECONDS
	for slot, state in profile.pedestals do
		if isHatched(state, now) and not profile.index[state.creatureId] then
			profile.index[state.creatureId] = true
			notify:FireClient(player, `New creature: {creatureName(state)}!`, "success")
		end
		-- Hatch moment (crossed this tick): burst effect for everyone nearby.
		if
			state.hatchAt
			and now >= state.hatchAt
			and now - state.hatchAt < Economy.INCOME_TICK_SECONDS
		then
			local pedestal = plot.pedestals[tonumber(slot) :: number]
			if pedestal then
				fx:FireAllClients("hatch", pedestal.Position, state.rarity)
			end
			TelemetryService.funnel(player, "FirstHatch")
		end
	end
	storedCoins[player] = (storedCoins[player] or 0)
		+ StationService.incomePerSecond(player, profile) * Economy.INCOME_TICK_SECONDS
	if hasPass(player, "OfflinePlus") then
		bank(player, plot, true) -- Auto-collect
	end
	local stored = math.floor(storedCoins[player])
	local label = plot.collector:FindFirstChild("Label", true) :: TextLabel?
	if label then
		label.Text = if stored > 0 then `Collect {Format.short(stored)}` else ""
	end
	player:SetAttribute("StorageCount", #profile.storage)
	refreshPlot(plot, profile)
end

function StationService.init()
	notify = Remotes.event("Notify")
	fx = Remotes.event("Fx")
	DataService.onLoaded(assignPlot)
	DataService.onRemoving(function(player, profile)
		-- Bank uncollected coins so leaving never loses income.
		local stored = math.floor(storedCoins[player] or 0)
		if stored > 0 then
			profile.coins += stored
		end
		releasePlot(player)
	end)
	for _, plot in WorldService.getPlots() do
		refreshPlot(plot, nil)
	end
end

function StationService.start()
	task.spawn(function()
		while true do
			task.wait(COLLECT_CHECK_PERIOD)
			for player, plot in playerPlot do
				tryCollect(player, plot)
			end
		end
	end)
	while true do
		task.wait(Economy.INCOME_TICK_SECONDS)
		for player, plot in playerPlot do
			local profile = DataService.get(player)
			if profile then
				tickStation(player, plot, profile)
			end
		end
	end
end

return StationService

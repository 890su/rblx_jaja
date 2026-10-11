--!strict
-- Stations (bases): plot assignment, pedestals, hatch timers, server income
-- tick and the coin collector. All state lives in the player's profile; the
-- world objects are just a view refreshed once per tick.

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Types = require(Shared.Types)
local Economy = require(Shared.Config.Economy)
local Rarity = require(Shared.Config.Rarity)
local Creatures = require(Shared.Config.Creatures)
local Theme = require(Shared.Theme)
local Format = require(Shared.Util.Format)
local Remotes = require(Shared.Remotes)

local Income = require(script.Parent.Parent.Data.Income)
local DataService = require(script.Parent.DataService)
local WorldService = require(script.Parent.WorldService)

type Plot = WorldService.Plot

local StationService = {}

local plotOwner: { [number]: Player } = {}
local playerPlot: { [Player]: Plot } = {}
local storedCoins: { [Player]: number } = {}
local collectDebounce: { [Player]: number } = {}

local notify: RemoteEvent

local isHatched = Income.isHatched
local incomeOf = Income.ofPedestal

function StationService.incomePerSecond(profile: Types.PlayerProfile): number
	return Income.perSecond(profile, os.time())
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
		newGui.StudsOffset = Vector3.new(0, 6, 0)
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
		newOrb.Material = Enum.Material.Neon
		newOrb.CFrame = pedestal.CFrame + Vector3.new(0, 3.2, 0)
		newOrb.Parent = pedestal
		orb = newOrb
	end
	return (gui :: BillboardGui):FindFirstChild("Label") :: TextLabel, orb :: Part
end

local function refreshPlot(plot: Plot, profile: Types.PlayerProfile?)
	local now = os.time()
	for slot, pedestal in plot.pedestals do
		local label, orb = ensureView(pedestal)
		local state = profile and profile.pedestals[tostring(slot)]
		local unlocked = profile ~= nil and slot <= profile.pedestalCount
		pedestal.Transparency = if unlocked then 0 else 0.7
		if state then
			local color = Theme.RARITY_COLORS[state.rarity]
			orb.Color = color
			label.TextColor3 = color
			if isHatched(state, now) then
				orb.Transparency = 0
				orb.Size = Vector3.new(4, 4, 4)
				label.Text = `{creatureName(state)}\n+{Format.short(incomeOf(state))}/s`
			else
				orb.Transparency = 0.4
				orb.Size = Vector3.new(2.5, 2.5, 2.5)
				label.Text = `{state.rarity} {Theme.ITEM}\n{Format.duration(
					(state.hatchAt :: number) - now
				)}`
			end
		else
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
		character:PivotTo(plot.spawn)
	end
end

local function assignPlot(player: Player, profile: Types.PlayerProfile)
	for _, plot in WorldService.getPlots() do
		if not plotOwner[plot.index] then
			plotOwner[plot.index] = player
			playerPlot[player] = plot
			local offline = Income.offline(profile, os.time())
			storedCoins[player] = offline
			profile.lastOnline = os.time()
			setOwnerSign(plot, player)
			refreshPlot(plot, profile)
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
	local amount = math.floor(storedCoins[player] or 0)
	if amount <= 0 then
		return
	end
	collectDebounce[player] = now + 1
	storedCoins[player] -= amount
	DataService.addCoins(player, amount)
	notify:FireClient(player, `+{Format.short(amount)} {Theme.CURRENCY}`, "coins")
end

function StationService.getPlot(player: Player): Plot?
	return playerPlot[player]
end

-- Places a meteor (already rolled into a creature) on the first free unlocked
-- pedestal. Returns success.
function StationService.tryPlace(player: Player, creatureId: string, mutation: string?): boolean
	local creature = Creatures.BY_ID[creatureId]
	if not creature then
		return false
	end
	local rarity = creature.rarity
	local profile = DataService.get(player)
	local plot = playerPlot[player]
	if not profile or not plot then
		return false
	end
	for slot = 1, profile.pedestalCount do
		local key = tostring(slot)
		if not profile.pedestals[key] then
			profile.pedestals[key] = {
				creatureId = creatureId,
				rarity = rarity,
				mutation = mutation,
				hatchAt = os.time() + Rarity.INFO[rarity].hatchSeconds,
			}
			refreshPlot(plot, profile)
			return true
		end
	end
	return false
end

function StationService.init()
	notify = Remotes.event("Notify")
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
				local now = os.time()
				profile.lastOnline = now
				profile.playtimeTotal += Economy.INCOME_TICK_SECONDS
				for _, state in profile.pedestals do
					if isHatched(state, now) and not profile.index[state.creatureId] then
						profile.index[state.creatureId] = true
						notify:FireClient(player, `New creature: {creatureName(state)}!`, "success")
					end
				end
				storedCoins[player] = (storedCoins[player] or 0)
					+ StationService.incomePerSecond(profile) * Economy.INCOME_TICK_SECONDS
				local stored = math.floor(storedCoins[player])
				local label = plot.collector:FindFirstChild("Label", true) :: TextLabel?
				if label then
					label.Text = if stored > 0 then `Collect {Format.short(stored)}` else ""
				end
				refreshPlot(plot, profile)
			end
		end
	end
end

return StationService

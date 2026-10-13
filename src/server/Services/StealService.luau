--!strict
-- Stealing and chase-back (GDD §4.5). A thief holds the Steal prompt on another
-- player's pedestal and carries the creature home. The owner gets a speed buff
-- and CHASE_SECONDS to catch the thief and take it back. Every rule is checked
-- here on the server; the client only hides prompts that would be rejected.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Types = require(Shared.Types)
local Steal = require(Shared.Config.Steal)
local Theme = require(Shared.Theme)
local Locale = require(Shared.Locale)

local Notifier = require(script.Parent.Parent.Util.Notifier)
local DataService = require(script.Parent.DataService)
local WorldService = require(script.Parent.WorldService)
local StationService = require(script.Parent.StationService)
local SpeedService = require(script.Parent.SpeedService)
local CarryService = require(script.Parent.CarryService)
local TransferService = require(script.Parent.TransferService)
local TelemetryService = require(script.Parent.TelemetryService)
local RateLimit = require(script.Parent.Parent.Util.RateLimit)
local attemptLimit = RateLimit.new(3, 1)

type Plot = WorldService.Plot
type Chase = { victim: Player, slot: string, endsAt: number, creatureName: string }

local TICK = 0.2
local HOLD_TOLERANCE = 0.25 -- seconds of latency slack on the prompt hold time

local StealService = {}

local lockedUntil: { [Player]: number } = {}
local inStation: { [Player]: boolean } = {}
local lastStealAt: { [Player]: number } = {}
local lastVictimAt: { [Player]: { [Player]: number } } = {}
local holdBegan: { [Player]: { prompt: ProximityPrompt, at: number } } = {}
local reserving: { [Player]: boolean } = {}
local chases: { [Player]: Chase } = {} -- keyed by thief

local function rootOf(player: Player): BasePart?
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not character or not humanoid or humanoid.Health <= 0 then
		return nil
	end
	return character:FindFirstChild("HumanoidRootPart") :: BasePart?
end

local function nameOf(state: Types.PedestalState): string
	return Theme.CREATURE_NAMES[state.creatureId] or state.rarity
end

function StealService.isLocked(owner: Player): boolean
	if (lockedUntil[owner] or 0) > os.clock() then
		return true
	end
	local profile = DataService.get(owner)
	return profile ~= nil and profile.shieldUntil > os.time()
end

function StealService.isProtected(owner: Player): boolean
	local profile = DataService.get(owner)
	if not profile then
		return true
	end
	if profile.playtimeTotal < Steal.NEW_PLAYER_PROTECTION_SECONDS then
		return true
	end
	return profile.rebirths == 0
		and StationService.creatureCount(profile) < Steal.PROTECTION_MIN_CREATURES
end

-- Returns nil if allowed, otherwise a Locale key (+ args) for the reason.
local function rejectReason(
	thief: Player,
	victim: Player,
	slot: string,
	pedestal: BasePart
): (string?, Locale.Args?)
	local thiefProfile = DataService.get(thief)
	local victimProfile = DataService.get(victim)
	if thief == victim or not thiefProfile or not victimProfile then
		return "steal_cant"
	end
	local state = victimProfile.pedestals[slot]
	if not state then
		return "steal_nothing"
	end
	if
		state.paid
		and (
			thief:GetAttribute("PaidItemTradingAllowed") ~= true
			or victim:GetAttribute("PaidItemTradingAllowed") ~= true
		)
	then
		return "steal_paid_restricted"
	end
	if CarryService.get(thief) or reserving[thief] then
		return "steal_hands_full"
	end
	local position = SpeedService.validatePosition(thief)
	if not position or (position - pedestal.Position).Magnitude > Steal.MAX_STEAL_DISTANCE then
		return "steal_too_far"
	end
	local began = holdBegan[thief]
	if
		not began
		or began.prompt.Parent ~= pedestal
		or os.clock() - began.at < Steal.PROMPT_HOLD_SECONDS - HOLD_TOLERANCE
	then
		return "steal_hold"
	end
	if not StationService.hasFreePedestal(thief) then
		return "steal_full"
	end
	if StealService.isLocked(victim) then
		return "steal_locked", { player = victim.DisplayName }
	end
	if StealService.isProtected(victim) then
		return "steal_protected", { player = victim.DisplayName }
	end
	local now = os.clock()
	local sinceLast = now - (lastStealAt[thief] or -math.huge)
	if sinceLast < Steal.THIEF_COOLDOWN_SECONDS then
		return "steal_wait", { seconds = math.ceil(Steal.THIEF_COOLDOWN_SECONDS - sinceLast) }
	end
	local victims = lastVictimAt[thief]
	if victims and now - (victims[victim] or -math.huge) < Steal.SAME_VICTIM_COOLDOWN_SECONDS then
		return "steal_recent", { player = victim.DisplayName }
	end
	if
		state.rarity == "Mythic"
		and StationService.creatureCount(victimProfile) < Steal.MYTHIC_MIN_VICTIM_CREATURES
	then
		return "steal_mythic"
	end
	return nil
end

local function setThiefHighlight(thief: Player, on: boolean)
	local character = thief.Character
	if not character then
		return
	end
	local existing = character:FindFirstChild("ThiefHighlight")
	if on and not existing then
		local highlight = Instance.new("Highlight")
		highlight.Name = "ThiefHighlight"
		highlight.FillColor = Color3.fromRGB(255, 60, 60)
		highlight.OutlineColor = Color3.fromRGB(255, 220, 220)
		highlight.FillTransparency = 0.6
		highlight.Parent = character
	elseif not on and existing then
		existing:Destroy()
	end
end

local function updateVictimBuff(victim: Player)
	if victim.Parent ~= Players then
		return
	end
	local remaining = 0
	for _, chase in chases do
		if chase.victim == victim then
			remaining = math.max(remaining, chase.endsAt - os.clock())
		end
	end
	victim:SetAttribute(
		"ChaseUntil",
		if remaining > 0 then workspace:GetServerTimeNow() + remaining else nil
	)
	SpeedService.apply(victim)
end

local function endChase(thief: Player, _clearVictimBuff: boolean)
	local chase = chases[thief]
	if not chase then
		return
	end
	chases[thief] = nil
	setThiefHighlight(thief, false)
	thief:SetAttribute("ChaseVictim", nil)
	updateVictimBuff(chase.victim)
end

local function tryStealFrom(thief: Player, plot: Plot, slot: string, pedestal: BasePart)
	local victim = StationService.ownerOf(plot)
	if not victim then
		return
	end
	local reason, reasonArgs = rejectReason(thief, victim, slot, pedestal)
	holdBegan[thief] = nil
	if reason then
		Notifier.send(thief, reason, reasonArgs, "warning")
		return
	end

	reserving[thief] = true
	Notifier.send(thief, "steal_reserving", nil, "info")
	local transferId, state = TransferService.reserve(victim, thief, slot)
	reserving[thief] = nil
	if not transferId or not state then
		return
	end
	local position = SpeedService.validatePosition(thief)
	local victimProfile = DataService.get(victim)
	local protectedNow = not victimProfile
		or victimProfile.playtimeTotal < Steal.NEW_PLAYER_PROTECTION_SECONDS
		or (
			victimProfile.rebirths == 0
			and StationService.creatureCount(victimProfile) + 1 < Steal.PROTECTION_MIN_CREATURES
		)
	if
		thief.Parent ~= Players
		or victim.Parent ~= Players
		or not position
		or (position - pedestal.Position).Magnitude > Steal.MAX_STEAL_DISTANCE
		or CarryService.get(thief)
		or not StationService.hasFreePedestal(thief)
		or StealService.isLocked(victim)
		or protectedNow
		or (state.rarity == "Mythic" and victimProfile ~= nil and StationService.creatureCount(
			victimProfile
		) + 1 < Steal.MYTHIC_MIN_VICTIM_CREATURES)
		or (
			state.paid
			and (
				thief:GetAttribute("PaidItemTradingAllowed") ~= true
				or victim:GetAttribute("PaidItemTradingAllowed") ~= true
			)
		)
	then
		TransferService.cancel(victim, transferId)
		return
	end
	local creatureName = nameOf(state)
	local creatureRef = Locale.ref(creatureName)
	local began = CarryService.begin(thief, {
		state = state,
		fresh = false,
		owner = victim,
		ownerSlot = slot,
		transferId = transferId,
		deliver = function(by, preferredSlot)
			return TransferService.complete(victim, by, transferId, preferredSlot)
		end,
		onLost = function(lostBy, _carry)
			-- Thief died or left: the creature goes back to its owner.
			local chase = chases[lostBy]
			endChase(lostBy, true)
			local owner = if chase then chase.victim else victim
			if TransferService.cancel(owner, transferId) then
				Notifier.send(owner, "creature_returned", { creature = creatureRef }, "success")
			end
		end,
		onDelivered = function(by)
			endChase(by, true)
			local thiefProfile = DataService.get(by)
			if thiefProfile then
				thiefProfile.stats.steals += 1
			end
			TelemetryService.custom(by, "StealSuccess")
			local robbedProfile = DataService.get(victim)
			if robbedProfile then
				robbedProfile.stats.timesRobbed += 1
			end
			Notifier.send(by, "steal_success", { creature = creatureRef }, "success")
			if victim.Parent == Players then
				Notifier.send(
					victim,
					"steal_got_away",
					{ player = by.DisplayName, creature = creatureRef },
					"warning"
				)
			end
		end,
	})
	if not began then
		TransferService.cancel(victim, transferId)
		return
	end

	local now = os.clock()
	lastStealAt[thief] = now
	lastVictimAt[thief] = lastVictimAt[thief] or {}
	lastVictimAt[thief][victim] = now
	chases[thief] = {
		victim = victim,
		slot = slot,
		endsAt = now + Steal.CHASE_SECONDS,
		creatureName = creatureName,
	}
	setThiefHighlight(thief, true)
	thief:SetAttribute("ChaseVictim", victim.UserId)
	updateVictimBuff(victim)
	task.delay(Steal.CHASE_SECONDS + 0.1, function()
		if victim.Parent == Players then
			SpeedService.apply(victim)
		end
	end)

	Notifier.send(
		thief,
		"steal_started_thief",
		{ creature = creatureRef, player = victim.DisplayName },
		"pickup"
	)
	Notifier.send(
		victim,
		"steal_started_victim",
		{ player = thief.DisplayName, creature = creatureRef },
		"warning"
	)
end

local function tickChases()
	local now = os.clock()
	for thief, chase in chases do
		local victim = chase.victim
		if victim.Parent ~= Players or now > chase.endsAt then
			endChase(thief, false)
			continue
		end
		local thiefPosition, victimPosition =
			SpeedService.validatePosition(thief), SpeedService.validatePosition(victim)
		if
			thiefPosition
			and victimPosition
			and (thiefPosition - victimPosition).Magnitude <= Steal.CATCH_DISTANCE
		then
			local carry = CarryService.clear(thief)
			endChase(thief, true)
			if carry and carry.transferId and TransferService.cancel(victim, carry.transferId) then
				local victimProfile = DataService.get(victim)
				if victimProfile then
					victimProfile.stats.defends += 1
				end
				TelemetryService.custom(victim, "ChaseCaught")
				Notifier.send(
					victim,
					"chase_caught_victim",
					{ player = thief.DisplayName, creature = Locale.ref(chase.creatureName) },
					"success"
				)
				Notifier.send(
					thief,
					"chase_caught_thief",
					{ player = victim.DisplayName },
					"warning"
				)
			end
		end
	end
end

local function tickStations()
	for _, plot in WorldService.getPlots() do
		local owner = StationService.ownerOf(plot)
		if owner then
			local root = rootOf(owner)
			local inside = root ~= nil and WorldService.isInPlot(plot, root.Position)
			if inside and not inStation[owner] then
				-- Lock refreshes every time the owner comes home.
				local vipBonus = if owner:GetAttribute("Pass_VIP")
					then Steal.VIP_LOCK_BONUS_SECONDS
					else 0
				lockedUntil[owner] = os.clock() + Steal.BASE_LOCK_SECONDS + vipBonus
			end
			inStation[owner] = inside
		end
		local remaining = if owner then math.max(0, (lockedUntil[owner] or 0) - os.clock()) else 0
		local profile = owner and DataService.get(owner)
		if profile and profile.shieldUntil > os.time() then
			remaining = math.max(remaining, profile.shieldUntil - os.time())
		end
		plot.model:SetAttribute("OwnerUserId", if owner then owner.UserId else nil)
		plot.model:SetAttribute("LockedFor", math.ceil(remaining))
		plot.model:SetAttribute("Protected", owner ~= nil and StealService.isProtected(owner))
		local field = plot.model:FindFirstChild("LockField") :: BasePart?
		if field then
			field.Transparency = if remaining > 0 then 0.75 else 1
		end
	end
end

local function setupPlot(plot: Plot)
	local field = Instance.new("Part")
	field.Name = "LockField"
	field.Anchored = true
	field.CanCollide = false
	field.CanQuery = false
	field.CanTouch = false
	field.Material = Enum.Material.ForceField
	field.Color = Color3.fromRGB(90, 170, 255)
	field.Transparency = 1
	field.Size = Vector3.new(62, 30, 62)
	field.Position = plot.center + Vector3.new(0, 15, 0)
	field.Parent = plot.model

	for slot, pedestal in plot.pedestals do
		local prompt = Instance.new("ProximityPrompt")
		prompt.Name = "StealPrompt"
		prompt.ActionText = "Steal"
		prompt.ObjectText = ""
		prompt.HoldDuration = Steal.PROMPT_HOLD_SECONDS
		prompt.MaxActivationDistance = Steal.MAX_STEAL_DISTANCE - 2
		prompt.RequiresLineOfSight = false
		prompt.KeyboardKeyCode = Enum.KeyCode.F
		prompt.Parent = pedestal
		CollectionService:AddTag(prompt, "StealPrompt")
		prompt.PromptButtonHoldBegan:Connect(function(player)
			local root = rootOf(player)
			if
				root
				and (root.Position - pedestal.Position).Magnitude <= Steal.MAX_STEAL_DISTANCE
				and not reserving[player]
				and not CarryService.get(player)
			then
				holdBegan[player] = { prompt = prompt, at = os.clock() }
			end
		end)
		prompt.PromptButtonHoldEnded:Connect(function(player)
			local held = holdBegan[player]
			task.defer(function()
				if holdBegan[player] == held then
					holdBegan[player] = nil
				end
			end)
		end)
		prompt.Triggered:Connect(function(player)
			if attemptLimit:allow(player) then
				tryStealFrom(player, plot, tostring(slot), pedestal)
			end
		end)
	end
end

-- Studio QA only (DebugService): clears cooldowns and the station lock.
function StealService.debugReset(player: Player)
	lastStealAt[player] = nil
	lastVictimAt[player] = nil
	lockedUntil[player] = nil
end

function StealService.debugAttempt(
	thief: Player,
	victim: Player,
	slot: number,
	held: number
): boolean
	require(script.Parent.Parent.Util.CommerceQA)()
	local plot = assert(StationService.getPlot(victim))
	local pedestal = assert(plot.pedestals[slot], "missing QA pedestal")
	local prompt = assert(pedestal:FindFirstChild("StealPrompt")) :: ProximityPrompt
	holdBegan[thief] = { prompt = prompt, at = os.clock() - held }
	tryStealFrom(thief, plot, tostring(slot), pedestal)
	return CarryService.get(thief) ~= nil
end

function StealService.init()
	for _, plot in WorldService.getPlots() do
		setupPlot(plot)
	end
	DataService.onRemoving(function(player, _profile)
		-- Thief leaving mid-chase is handled by CarryService.onLost. An owner
		-- leaving takes the creature home: it is written back into their
		-- profile before it saves, so nothing is lost if the thief then dies.
		for _, thief in CarryService.carriersOf(player) do
			local carry = CarryService.clear(thief)
			endChase(thief, false)
			if carry then
				if carry.transferId then
					TransferService.cancel(player, carry.transferId)
				end
				Notifier.send(thief, "steal_owner_left", { player = player.DisplayName }, "warning")
			end
		end
		for thief, chase in chases do
			if chase.victim == player then
				endChase(thief, false)
			end
		end
		lockedUntil[player] = nil
		inStation[player] = nil
		lastStealAt[player] = nil
		lastVictimAt[player] = nil
		holdBegan[player] = nil
		reserving[player] = nil
		for _, victims in lastVictimAt do
			victims[player] = nil
		end
	end)
end

function StealService.start()
	while true do
		task.wait(TICK)
		tickChases()
		tickStations()
	end
end

return StealService

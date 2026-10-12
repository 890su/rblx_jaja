--!strict
-- Egg guards. Each guard roams around its egg on a smooth, noisy path,
-- sweeping a vision sector over the ground. A carrier caught inside it
-- fills that guard's alert meter (yellow "?"); a full meter starts a chase
-- (red) that pulls in nearby guards. Guards within earshot of a pickup start
-- alert at once (further in noisy deep zones).
-- During a chase only telegraphed attacks drop the egg: the locked dash and,
-- from the attack zone, Undertale-style ground attacks (shared ArenaPatterns
-- math, server hit checks). From the hound zone the guard that starts the
-- chase tears open a portal and a Void Hound leaps out.
-- Each body is one welded assembly moved by its anchored root, so a drone
-- replicates a single CFrame instead of one per part.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config.Snatchers)
local Rarity = require(Shared.Config.Rarity)
local Remotes = require(Shared.Remotes)
local Combat = require(Shared.Util.SnatcherCombat)
local Patterns = require(Shared.Util.ArenaPatterns)
local Notifier = require(script.Parent.Parent.Util.Notifier)
local Knockback = require(script.Parent.Parent.Util.Knockback)
local DataService = require(script.Parent.DataService)
local WorldService = require(script.Parent.WorldService)
local CarryService = require(script.Parent.CarryService)
local Telemetry = require(script.Parent.TelemetryService)

type Drone = {
	kind: string, -- "drone" | "hound"
	model: Model,
	root: BasePart,
	offset: CFrame, -- pivot -> root
	hover: number, -- pivot height above the ground plane
	label: TextLabel,
	line: Part,
	indicator: BasePart?,
	zone: number,
	meteor: BasePart?,
	home: Vector3, -- patrol centre (the egg, or where it was)
	orphanUntil: number?, -- egg taken: keep patrolling until then
	yaw: number, -- vision / facing direction
	seed: number,
	spin: number,
	alert: number, -- 0..1
	alertTarget: Player?,
	spotting: boolean,
	target: Player?,
	carry: CarryService.Carry?,
	factor: number,
	bornAt: number,
	phase: string,
	phaseUntil: number,
	nextAttack: number,
	position: Vector3,
	origin: Vector3,
	direction: Vector3,
	endpoint: Vector3,
	previousTarget: Vector3,
	orbit: number,
	cargo: BasePart?, -- reclaim: the dropped egg being fetched / carried
	haulTo: Vector3?,
}

type Carrier = { player: Player, root: BasePart, carry: CarryService.Carry, moving: boolean }

local Service = {}
local drones: { Drone } = {}
local guards: { [BasePart]: { Drone } } = {}
local folder: Folder
local rayParams = RaycastParams.new()
local rng = Random.new()
local waveEvent: RemoteEvent

-- Per-player chase state.
local fieldWaves: { [Player]: { Patterns.Wave } } = {}
local nextCast: { [Player]: number } = {}
local lastKind: { [Player]: string } = {}
local nextWaveId: { [Player]: number } = {}
local lastPoint: { [Player]: Vector3 } = {}
local spottedNoticeAt: { [Player]: number } = {}
local houndFor: { [CarryService.Carry]: boolean } = setmetatable({}, { __mode = "k" }) :: any

local FLOOR_TOP = 0.2
local COLORS = {
	patrol = Color3.fromRGB(70, 150, 255),
	alert = Color3.fromRGB(255, 205, 65),
	chase = Color3.fromRGB(255, 65, 90),
	recover = Color3.fromRGB(190, 145, 255),
}

local function rootOf(player: Player): BasePart?
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return nil
	end
	return character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
end

local function flatUnit(v: Vector3): Vector3
	local f = Vector3.new(v.X, 0, v.Z)
	return if f.Magnitude > 1e-3 then f.Unit else Vector3.new(0, 0, 1)
end

local function yawOf(direction: Vector3): number
	return math.atan2(direction.Z, direction.X)
end

local function facingOf(yaw: number): Vector3
	return Vector3.new(math.cos(yaw), 0, math.sin(yaw))
end

-- Shortest signed angle from a to b.
local function angleDelta(a: number, b: number): number
	return (b - a + math.pi) % (2 * math.pi) - math.pi
end

local function fallbackModel(kind: string): Model
	local model = Instance.new("Model")
	for _, spec in
		{
			{
				name = "Body",
				size = Vector3.one * 3.2,
				pos = Vector3.zero,
				color = if kind == "hound"
					then Color3.fromRGB(25, 20, 35)
					else Color3.fromRGB(45, 20, 70),
			},
			{
				name = "Eye",
				size = Vector3.one * 1.1,
				pos = Vector3.new(0, 0.3, -1.35),
				color = Color3.fromRGB(255, 50, 70),
			},
		}
	do
		local part = Instance.new("Part")
		part.Name, part.Shape, part.Size = spec.name, Enum.PartType.Ball, spec.size
		part.Color, part.Position = spec.color, spec.pos
		part.Material = if spec.name == "Eye"
			then Enum.Material.Neon
			else Enum.Material.SmoothPlastic
		part.Parent = model
		if spec.name == "Body" then
			model.PrimaryPart = part
		end
	end
	return model
end

local function buildModel(kind: string): Model
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local template = assets
		and assets:FindFirstChild(if kind == "hound" then "VoidHound" else "Snatcher")
	if template and template:IsA("Model") then
		return template:Clone()
	end
	return fallbackModel(kind)
end

-- Weld every part to one anchored root. Returns the root and pivot offset.
local function assemble(model: Model): (BasePart?, CFrame)
	local root: BasePart? = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart", true)
	if not root then
		return nil, CFrame.identity
	end
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			part.CanCollide, part.CanQuery, part.CanTouch = false, false, false
			if part ~= root then
				part.Anchored, part.Massless = false, true
				local weld = Instance.new("WeldConstraint")
				weld.Part0, weld.Part1 = root, part
				weld.Parent = part
			end
		end
	end
	root.Anchored = true
	return root, model:GetPivot():ToObjectSpace(root.CFrame)
end

local function place(drone: Drone, cframe: CFrame)
	drone.root.CFrame = cframe * drone.offset
end

local function alertBar(alert: number): string
	local filled = math.clamp(math.floor(alert * 5 + 0.5), 0, 5)
	return "?  " .. string.rep("▮", filled) .. string.rep("▯", 5 - filled)
end

local function state(drone: Drone, phase: string)
	drone.phase = phase
	drone.model:SetAttribute("State", phase)
	local color = if phase == "guard"
		then COLORS.patrol
		elseif phase == "alert" then COLORS.alert
		elseif phase == "recover" then COLORS.recover
		elseif phase == "warning" then COLORS.alert
		else COLORS.chase
	drone.label.Text = if phase == "warning"
		then "DODGE!"
		elseif phase == "dash" then "ATTACK"
		elseif phase == "guard" then "EGG GUARD"
		elseif phase == "alert" then alertBar(drone.alert)
		elseif phase == "recover" then "RECHARGING"
		elseif phase == "fetch" then "RECLAIMING"
		elseif phase == "haul" then "RETURNING EGG"
		else "CHASING"
	drone.label.TextColor3 = color
	if drone.indicator then
		drone.indicator.Color = if phase == "guard"
			then COLORS.patrol
			elseif phase == "alert" or phase == "fetch" or phase == "haul" then COLORS.alert
			else COLORS.chase
	end
	for _, part in drone.model:GetDescendants() do
		if part:IsA("BasePart") and (part.Name == "Eye" or part.Name == "Ring") then
			part.Color = color
		end
	end
	drone.line.Transparency = if phase == "warning" then 0.25 elseif phase == "dash" then 0.05 else 1
	drone.line.Color = color
end

local function isHauling(drone: Drone): boolean
	return drone.phase == "fetch" or drone.phase == "haul"
end

local function setSpotting(drone: Drone, spotting: boolean)
	if drone.spotting ~= spotting then
		drone.spotting = spotting
		drone.model:SetAttribute("Spotting", spotting)
	end
end

local function spawn(kind: string, zone: number, position: Vector3, meteor: BasePart?): Drone?
	if #drones >= Config.MAX_ACTIVE then
		return nil
	end
	local model = buildModel(kind)
	model.Name = if kind == "hound" then "VoidHound" else "Snatcher"
	local hover = Config.HOVER_HEIGHT
	if kind == "hound" then
		local _, size = model:GetBoundingBox()
		hover = FLOOR_TOP + size.Y / 2
	end
	position = Vector3.new(position.X, hover, position.Z)
	local yaw = rng:NextNumber(0, math.pi * 2)
	-- Move the whole model into place BEFORE welding: a WeldConstraint keeps
	-- the offsets its parts have when it activates, so moving only the root
	-- first would leave every other part behind at the template's location.
	model:PivotTo(CFrame.lookAt(position, position + facingOf(yaw)))
	local root, offset = assemble(model)
	if not root then
		model:Destroy()
		return nil
	end
	-- Status light on top: blue patrol, yellow alert, red chase.
	local indicator: BasePart? = nil
	if kind == "drone" then
		local _, size = model:GetBoundingBox()
		local light = Instance.new("Part")
		light.Name, light.Shape, light.Material =
			"Indicator", Enum.PartType.Ball, Enum.Material.Neon
		light.Size = Vector3.one * 0.9
		light.CanCollide, light.CanQuery, light.CanTouch, light.Massless = false, false, false, true
		light.Anchored = false
		light.CFrame = root.CFrame + Vector3.new(0, size.Y / 2 + 0.4, 0)
		local weld = Instance.new("WeldConstraint")
		weld.Part0, weld.Part1 = root, light
		weld.Parent = light
		light.Parent = model
		indicator = light
	end
	local gui = Instance.new("BillboardGui")
	gui.Name, gui.Adornee, gui.Size, gui.StudsOffset =
		"GuardStatus", root, UDim2.fromOffset(150, 30), Vector3.new(0, 3.5, 0)
	gui.MaxDistance = 100
	local label = Instance.new("TextLabel")
	label.Size, label.BackgroundTransparency, label.TextScaled = UDim2.fromScale(1, 1), 1, true
	label.Font, label.TextStrokeTransparency = Enum.Font.FredokaOne, 0.2
	label.AutoLocalize = true
	label.Parent, gui.Parent = gui, root
	local line = Instance.new("Part")
	line.Name, line.Anchored, line.CanCollide, line.CanQuery, line.CanTouch =
		"AttackWarning", true, false, false, false
	line.Material, line.Transparency, line.CastShadow = Enum.Material.Neon, 1, false
	line.Parent = folder
	local home = meteor and Vector3.new(meteor.Position.X, hover, meteor.Position.Z) or position
	local drone: Drone = {
		kind = kind,
		model = model,
		root = root,
		offset = offset,
		hover = hover,
		label = label,
		line = line,
		indicator = indicator,
		zone = zone,
		meteor = meteor,
		home = home,
		orphanUntil = nil,
		yaw = yaw,
		seed = rng:NextNumber(0, 1000),
		spin = if rng:NextNumber() < 0.5 then -1 else 1,
		alert = 0,
		alertTarget = nil,
		spotting = false,
		target = nil,
		carry = nil,
		factor = Config.SPEED_FACTOR,
		bornAt = 0,
		phase = "guard",
		phaseUntil = 0,
		nextAttack = 0,
		position = position,
		origin = position,
		direction = Vector3.new(0, 0, 1),
		endpoint = position,
		previousTarget = position,
		orbit = rng:NextNumber(0, math.pi * 2),
		cargo = nil,
		haulTo = nil,
	}
	model:SetAttribute("ZoneIndex", zone)
	model:SetAttribute("Kind", kind)
	model:SetAttribute("Spotting", false)
	model.Parent = folder
	state(drone, "guard")
	table.insert(drones, drone)
	if meteor then
		local list = guards[meteor] or {}
		guards[meteor] = list
		table.insert(list, drone)
		meteor:SetAttribute("Guarded", true)
	end
	return drone
end

-- Detach a guard from its egg; it keeps patrolling where the egg was.
local function unguard(drone: Drone)
	local meteor = drone.meteor
	if not meteor then
		return
	end
	local list = guards[meteor]
	if list then
		local index = table.find(list, drone)
		if index then
			table.remove(list, index)
		end
		if #list == 0 then
			guards[meteor] = nil
			if meteor.Parent then
				meteor:SetAttribute("Guarded", false)
			end
		end
	end
	drone.meteor = nil
end

local function despawn(index: number)
	local drone = drones[index]
	unguard(drone)
	table.remove(drones, index)
	drone.line:Destroy()
	drone.model:Destroy()
end

function Service.guardMeteor(meteor: BasePart, zone: number)
	if zone < Config.FROM_ZONE or guards[meteor] then
		return
	end
	local count = Config.GUARDS_BY_ZONE[zone] or 1
	local base = rng:NextNumber(0, math.pi * 2)
	for index = 1, count do
		local angle = base + (index - 1) * 2 * math.pi / count
		local position = Vector3.new(meteor.Position.X, 0, meteor.Position.Z)
			+ Vector3.new(math.cos(angle), 0, math.sin(angle)) * Config.PATROL_MIN_RADIUS
		local drone = spawn("drone", zone, position, meteor)
		if drone then
			drone.orbit = angle
		end
	end
end

local function activate(drone: Drone, player: Player, factor: number, delay: number)
	local root = rootOf(player)
	if not root then
		return
	end
	unguard(drone)
	drone.target, drone.carry, drone.factor = player, CarryService.get(player), factor
	drone.alert, drone.alertTarget = 0, nil
	setSpotting(drone, false)
	drone.bornAt, drone.nextAttack = os.clock(), os.clock() + Config.PICKUP_GRACE + delay
	drone.previousTarget = root.Position
	drone.model:SetAttribute("TargetUserId", player.UserId)
	state(drone, "chase")
end

-- A purple ring tears open at the guard; the hound leaps out after a beat.
local function summonHound(from: Drone, player: Player, zone: number)
	local at = Vector3.new(from.position.X, FLOOR_TOP + 0.1, from.position.Z)
	local portal = Instance.new("Part")
	portal.Name, portal.Shape = "VoidPortal", Enum.PartType.Cylinder
	portal.Anchored, portal.CanCollide, portal.CanQuery, portal.CanTouch = true, false, false, false
	portal.Material, portal.Color = Enum.Material.Neon, Color3.fromRGB(160, 70, 255)
	portal.Size = Vector3.new(0.3, 1, 1)
	portal.CFrame = CFrame.new(at) * CFrame.Angles(0, 0, math.rad(90))
	portal.Parent = folder
	TweenService:Create(
		portal,
		TweenInfo.new(Config.PORTAL_SECONDS, Enum.EasingStyle.Back),
		{ Size = Vector3.new(0.3, 11, 11) }
	):Play()
	task.delay(Config.PORTAL_SECONDS, function()
		local carry = CarryService.get(player)
		if carry and player.Parent == Players then
			local hound = spawn("hound", zone, at, nil)
			if hound then
				activate(hound, player, Config.HOUND_FACTOR, 0)
				hound.nextAttack = os.clock() + Config.PICKUP_GRACE * 0.6
			end
		end
		TweenService
			:Create(
				portal,
				TweenInfo.new(0.5),
				{ Size = Vector3.new(0.3, 0.5, 0.5), Transparency = 1 }
			)
			:Play()
		task.delay(0.6, function()
			portal:Destroy()
		end)
	end)
end

local function chasersOf(player: Player): number
	local count = 0
	for _, drone in drones do
		if drone.target == player and drone.kind == "drone" then
			count += 1
		end
	end
	return count
end

-- A guard's alert meter filled: it calls nearby guards and the chase begins.
local function startChase(spotter: Drone, player: Player)
	local carry = CarryService.get(player)
	if not carry then
		return
	end
	local zone = spotter.zone
	local profile = DataService.get(player)
	local factor = Config.SPEED_FACTOR
	local count = (Config.COUNT_BY_ZONE[zone] or 1)
		+ (Config.EXTRA_BY_RARITY[carry.state.rarity] or 0)
	count = math.min(count, Config.MAX_CHASERS_PER_PLAYER)
	local hound = zone >= Config.HOUND_FROM_ZONE and not houndFor[carry]
	if zone == 1 then
		count, factor = 1, Config.FIRST_TIME_FACTOR
	end
	if profile and not profile.flags.snatcherIntro then
		profile.flags.snatcherIntro = true
		count, factor, hound = 1, Config.FIRST_TIME_FACTOR, false
	end
	local already = chasersOf(player)
	if already >= count then
		-- Enough chasers already: this guard goes back to its patrol.
		spotter.alert, spotter.alertTarget = 0, nil
		setSpotting(spotter, false)
		state(spotter, "guard")
		return
	end
	activate(spotter, player, factor, 0)
	already += 1
	-- Nearby idle guards answer the alarm, nearest first.
	local helpers: { Drone } = {}
	for _, drone in drones do
		if
			drone.target == nil
			and drone.kind == "drone"
			and not isHauling(drone)
			and (drone.position - spotter.position).Magnitude <= Config.ALARM_RADIUS
		then
			table.insert(helpers, drone)
		end
	end
	table.sort(helpers, function(a, b)
		return (a.position - spotter.position).Magnitude < (b.position - spotter.position).Magnitude
	end)
	for _, drone in helpers do
		if already >= count then
			break
		end
		activate(drone, player, factor, already * 0.4)
		already += 1
	end
	local root = rootOf(player)
	while already < count and root do
		local offset = Vector3.new(if already % 2 == 0 then -9 else 9, 0, -10 - already * 3)
		local drone = spawn("drone", zone, root.Position + offset, nil)
		if not drone then
			break
		end
		activate(drone, player, factor, already * 0.4)
		already += 1
	end
	if hound then
		houndFor[carry] = true
		summonHound(spotter, player, zone)
	end
	nextCast[player] = workspace:GetServerTimeNow() + Config.PICKUP_GRACE + 1
	Notifier.send(player, if hound then "hound_summoned" else "snatcher_chasing", nil, "warning")
	Telemetry.custom(player, "GuardChase")
end

local function beginAlert(drone: Drone, player: Player, level: number)
	if drone.target or drone.kind ~= "drone" or isHauling(drone) then
		return
	end
	drone.alertTarget = player
	drone.alert = math.max(drone.alert, level)
	if drone.phase ~= "alert" then
		state(drone, "alert")
		local now = os.clock()
		if now - (spottedNoticeAt[player] or -math.huge) > 6 then
			spottedNoticeAt[player] = now
			Notifier.send(player, "guard_spotted", nil, "warning")
		end
	end
end

-- Egg taken. Its guards stay where the egg was. Guards within earshot start
-- alert straight away (meter half full); deep zones are heard from further.
function Service.onPickup(player: Player, zone: number, _rarity: string, meteor: BasePart)
	local root = rootOf(player)
	if not root then
		return
	end
	local list = guards[meteor]
	if list then
		for _, drone in table.clone(list) do
			drone.home = Vector3.new(meteor.Position.X, drone.hover, meteor.Position.Z)
			drone.orphanUntil = os.clock() + Config.ORPHAN_SECONDS
			unguard(drone)
			if drone.cargo == meteor then
				-- Snatched back from a reclaiming drone.
				drone.cargo, drone.haulTo = nil, nil
				state(drone, "guard")
			end
		end
	end
	-- Guards close by always hear the pickup; deep zones are louder.
	local radius = if zone >= Config.NOISY_FROM_ZONE
		then Config.NOISE_RADIUS
		else Config.PICKUP_HEARING_RADIUS
	for _, drone in drones do
		if
			drone.target == nil
			and drone.kind == "drone"
			and (drone.position - root.Position).Magnitude <= radius
		then
			beginAlert(drone, player, Config.NOISE_ALERT)
		end
	end
end

local function blockedMove(position: Vector3, move: Vector3): Vector3
	if move.Magnitude < 0.001 then
		return Vector3.zero
	end
	local hit = workspace:Raycast(position, move + move.Unit * 1.5, rayParams)
	if hit then
		return move.Unit * math.max(0, hit.Distance - 1.5)
	end
	return move
end

local function anyPlayerNear(position: Vector3, players: { Vector3 }): boolean
	local radius2 = Config.GUARD_ACTIVE_RADIUS * Config.GUARD_ACTIVE_RADIUS
	for _, at in players do
		local dx, dz = at.X - position.X, at.Z - position.Z
		if dx * dx + dz * dz <= radius2 then
			return true
		end
	end
	return false
end

-- Smooth, noisy roaming around the patrol centre; the vision sector sweeps either side
-- of the direction of travel.
local function patrol(drone: Drone, now: number, dt: number)
	local radius = Config.PATROL_MIN_RADIUS
		+ (Config.PATROL_MAX_RADIUS - Config.PATROL_MIN_RADIUS)
			* math.clamp(0.5 + math.noise(drone.seed, now * 0.11), 0, 1)
	local angle = drone.orbit
		+ now * 0.22 * drone.spin
		+ 2.4 * math.noise(drone.seed + 17.3, now * 0.07)
	local goal = drone.home + Vector3.new(math.cos(angle), 0, math.sin(angle)) * radius
	if drone.position.Y > drone.hover then
		-- Back down after a haul was interrupted high over a wall.
		local y = math.max(drone.hover, drone.position.Y - Config.DESCEND_SPEED * dt)
		drone.position = Vector3.new(drone.position.X, y, drone.position.Z)
	end
	local delta = Vector3.new(goal.X - drone.position.X, 0, goal.Z - drone.position.Z)
	if delta.Magnitude > 0.05 then
		local step = delta.Unit * math.min(Config.PATROL_SPEED * dt, delta.Magnitude)
		drone.position += blockedMove(drone.position, step)
		local travel = yawOf(delta)
		local desired = travel + math.sin(now * 0.9 + drone.orbit) * Config.VISION_SWEEP
		drone.yaw += angleDelta(drone.yaw, desired) * math.min(1, dt * 3)
	end
end

local function canSee(drone: Drone, point: Vector3): boolean
	return workspace:Raycast(drone.position, point - drone.position, rayParams) == nil
end

-- Guard / alert behaviour for one drone. Returns false if it was despawned.
local function stepGuard(
	index: number,
	drone: Drone,
	now: number,
	dt: number,
	carriers: { Carrier },
	players: { Vector3 }
): boolean
	local meteor = drone.meteor
	if meteor and not meteor.Parent then
		drone.home = Vector3.new(meteor.Position.X, drone.hover, meteor.Position.Z)
		drone.orphanUntil = now + Config.ORPHAN_SECONDS
		unguard(drone)
	end
	if
		drone.phase == "guard"
		and drone.meteor == nil
		and (drone.orphanUntil == nil or now > drone.orphanUntil)
	then
		despawn(index)
		return false
	end
	if drone.phase == "guard" then
		if not anyPlayerNear(drone.home, players) then
			return true -- nobody can see it: skip the replicated move
		end
		patrol(drone, now, dt)
		local facing = facingOf(drone.yaw)
		local seen: Carrier? = nil
		for _, carrier in carriers do
			if
				Combat.inVision(drone.position, facing, carrier.root.Position)
				and canSee(drone, carrier.root.Position)
			then
				seen = carrier
				break
			end
		end
		setSpotting(drone, seen ~= nil)
		if seen then
			beginAlert(drone, seen.player, 0)
		end
	end
	if drone.phase == "alert" then
		local player = drone.alertTarget
		local carrier: Carrier? = nil
		for _, candidate in carriers do
			if candidate.player == player then
				carrier = candidate
			end
		end
		if not carrier then
			drone.alert, drone.alertTarget = 0, nil
			setSpotting(drone, false)
			state(drone, "guard")
			return true
		end
		-- Hover in place and turn toward the suspect at a limited rate.
		local toward = yawOf(carrier.root.Position - drone.position)
		local turn = angleDelta(drone.yaw, toward)
		drone.yaw += math.clamp(turn, -Config.ALERT_TURN_RATE * dt, Config.ALERT_TURN_RATE * dt)
		local visible = Combat.inVision(drone.position, facingOf(drone.yaw), carrier.root.Position)
			and canSee(drone, carrier.root.Position)
		setSpotting(drone, visible)
		if visible then
			drone.alert += Combat.alertRate(carrier.moving, drone.zone) * dt
		else
			drone.alert -= Config.ALERT_DECAY * dt
		end
		if drone.alert >= 1 then
			startChase(drone, carrier.player)
			return true
		elseif drone.alert <= 0 then
			drone.alert, drone.alertTarget = 0, nil
			setSpotting(drone, false)
			state(drone, "guard")
		else
			local text = alertBar(drone.alert)
			if drone.label.Text ~= text then
				drone.label.Text = text
			end
		end
	end
	local bobbed = drone.position + Vector3.new(0, math.sin(now * 3 + drone.orbit) * 0.25, 0)
	place(drone, CFrame.lookAt(bobbed, bobbed + facingOf(drone.yaw)))
	return true
end

local function warning(drone: Drone, root: BasePart, now: number)
	local direction, endpoint = Combat.plan(drone.position, root.Position)
	-- Telegraph ends at the blocking wall; the dash uses this same endpoint.
	local move = blockedMove(drone.position, endpoint - drone.position)
	drone.origin, drone.direction, drone.endpoint = drone.position, direction, drone.position + move
	local length = move.Magnitude
	drone.line.Size = Vector3.new(Config.HIT_RADIUS * 2, 0.12, math.max(0.1, length))
	local midpoint = (drone.origin + drone.endpoint) / 2
	drone.line.CFrame = CFrame.lookAt(
		Vector3.new(midpoint.X, 0.65, midpoint.Z),
		Vector3.new(midpoint.X, 0.65, midpoint.Z) + direction
	)
	drone.phaseUntil = now
		+ (if drone.zone == 1 then Config.FIRST_ZONE_WARNING_SECONDS else Config.WARNING_SECONDS)
	state(drone, "warning")
end

local function knockOut(player: Player, root: BasePart, telemetry: string, from: Vector3?)
	CarryService.drop(player, root.Position)
	Knockback.apply(player, from)
	fieldWaves[player] = nil
	Notifier.send(player, "snatcher_grabbed", nil, "warning")
	Telemetry.custom(player, telemetry)
end

-- Chase behaviour (dash cycle) for one drone. Returns false if despawned.
local function stepChaser(index: number, drone: Drone, now: number, dt: number): boolean
	local player = drone.target :: Player
	local root = rootOf(player)
	if
		player.Parent ~= Players
		or not root
		or CarryService.get(player) ~= drone.carry
		or player:GetAttribute("ArenaActive") == true
		or now - drone.bornAt > Config.GIVE_UP_SECONDS
		or WorldService.zoneIndexAt(root.Position) == 0
	then
		despawn(index)
		return false
	end
	local target = Vector3.new(root.Position.X, drone.hover, root.Position.Z)
	local delta = target - drone.position
	if drone.phase == "chase" then
		local distance = delta.Magnitude
		if
			distance <= Config.ATTACK_RANGE
			and now >= drone.nextAttack
			and not workspace:Raycast(drone.position, delta, rayParams)
		then
			warning(drone, root, now)
		elseif distance > Config.STANDOFF_DISTANCE then
			local humanoid = (player.Character :: Model):FindFirstChildOfClass("Humanoid")
			local speed =
				Combat.chaseSpeed(if humanoid then humanoid.WalkSpeed else 16, drone.factor)
			local move = delta.Unit * math.min(speed * dt, distance - Config.STANDOFF_DISTANCE)
			-- Slide along walls during chase; a dash stops at the first wall.
			local hit = workspace:Raycast(drone.position, move + delta.Unit * 1.5, rayParams)
			if hit then
				move -= hit.Normal * move:Dot(hit.Normal)
			end
			drone.position += blockedMove(drone.position, move)
		end
	elseif drone.phase == "warning" then
		-- Facing and endpoint stay locked even if the player moves sideways.
		if now >= drone.phaseUntil then
			state(drone, "dash")
		end
	elseif drone.phase == "dash" then
		local speed = if drone.zone == 1 then Config.FIRST_ZONE_DASH_SPEED else Config.DASH_SPEED
		local remaining = (drone.endpoint - drone.position).Magnitude
		local from = drone.position
		local move = blockedMove(from, drone.direction * math.min(speed * dt, remaining))
		drone.position += move
		if
			math.abs(root.Position.Y - drone.hover) < 6
			and Combat.hits(from, drone.position, drone.previousTarget, root.Position)
			and not workspace:Raycast(drone.position, root.Position - drone.position, rayParams)
		then
			knockOut(
				player,
				root,
				if drone.kind == "hound" then "HoundCaught" else "SnatcherCaught",
				from
			)
			despawn(index)
			return false
		end
		if (drone.endpoint - drone.position).Magnitude < 0.1 or move.Magnitude < 0.01 then
			drone.phaseUntil = now + Config.RECOVERY_SECONDS
			state(drone, "recover")
		end
	elseif drone.phase == "recover" and now >= drone.phaseUntil then
		drone.nextAttack = now + 0.35
		state(drone, "chase")
	end
	drone.previousTarget = root.Position
	local facing = if drone.phase == "warning" or drone.phase == "dash"
		then drone.direction
		elseif delta.Magnitude > 0.01 then delta.Unit
		else drone.direction
	facing = flatUnit(facing)
	drone.yaw = yawOf(facing)
	-- Drones bob gently; hounds bound low and quick.
	local bob = if drone.kind == "hound"
		then math.abs(math.sin(now * 9 + drone.orbit)) * 0.5
		else math.sin(now * 3 + drone.orbit) * 0.25
	local pos = drone.position + Vector3.new(0, bob, 0)
	place(drone, CFrame.lookAt(pos, pos + facing))
	return true
end

-- Ground attacks cast at a chased carrier (deep zones), and their hit checks.
local function stepAttacks(players: { Player })
	local now = workspace:GetServerTimeNow()
	for _, player in players do
		local root = rootOf(player)
		local waves = fieldWaves[player]
		if not root or not CarryService.get(player) or player:GetAttribute("ArenaActive") then
			fieldWaves[player] = nil
			continue
		end
		-- Cast: the deepest zone among this player's chasers sets the pace.
		local zone, nearest = 0, math.huge
		for _, drone in drones do
			if drone.target == player and drone.kind == "drone" then
				zone = math.max(zone, drone.zone)
				nearest = math.min(nearest, (drone.position - root.Position).Magnitude)
			end
		end
		local every = Config.ATTACK_EVERY_BY_ZONE[zone] or 0
		if
			zone >= Config.ATTACKS_FROM_ZONE
			and every > 0
			and nearest <= Config.ATTACK_CAST_RANGE
			and now >= (nextCast[player] or 0)
		then
			local carry = CarryService.get(player) :: CarryService.Carry
			local kinds = Config.ATTACK_KINDS
			local kind = kinds[rng:NextInteger(1, #kinds)]
			if kind == lastKind[player] then
				kind = kinds[(table.find(kinds, kind) :: number) % #kinds + 1]
			end
			lastKind[player] = kind
			local level = math.min(
				Patterns.level(Rarity.INFO[carry.state.rarity].order, math.max(zone, 3), 0),
				Config.ATTACK_MAX_LEVEL
			)
			-- Aim where the runner will be when the telegraph ends, and turn
			-- the pattern so its "forward" follows their direction of travel;
			-- otherwise running straight leaves every attack behind.
			local position = root.Position
			local velocity = root.AssemblyLinearVelocity
			local flat = Vector2.new(velocity.X, velocity.Z)
			local moving = flat.Magnitude > 4
			local lead = 0.25 + Patterns.warnTimeFor(level) + 0.1
			local ahead = if moving then flat * lead else Vector2.zero
			if ahead.Magnitude > Config.ATTACK_MAX_LEAD then
				ahead = ahead.Unit * Config.ATTACK_MAX_LEAD
			end
			local target = Vector2.new(position.X, position.Z) + ahead
			local heading = Patterns.axisHeading(if moving then flat else Vector2.new(0, 1))
			local id = (nextWaveId[player] or 1_000_000) + 1
			nextWaveId[player] = id
			local wave: Patterns.Wave = {
				id = id,
				kind = kind,
				t0 = now + 0.25,
				x = target.X,
				z = target.Y,
				laneX = target.X,
				seed = rng:NextInteger(1, 1_000_000),
				level = level,
				speed = Patterns.attackSpeed(level, 24),
				heading = heading,
			}
			waves = waves or {}
			table.insert(waves :: { Patterns.Wave }, wave)
			fieldWaves[player] = waves
			waveEvent:FireClient(player, wave)
			nextCast[player] = now + every
		end
		if not waves then
			lastPoint[player] = root.Position
			continue
		end
		-- Hits.
		local point = Vector2.new(root.Position.X, root.Position.Z)
		local before = lastPoint[player] or root.Position
		local middle = (point + Vector2.new(before.X, before.Z)) / 2
		lastPoint[player] = root.Position
		local hit: Vector3? = nil
		for i = #waves, 1, -1 do
			local wave = waves[i]
			if now > wave.t0 + Patterns.duration(wave) then
				table.remove(waves, i)
				continue
			end
			for _, hazard in Patterns.sample(wave, now) do
				if Patterns.hits(hazard, point, true) or Patterns.hits(hazard, middle, true) then
					hit = Vector3.new(hazard.position.X, root.Position.Y, hazard.position.Y)
					break
				end
			end
			if hit then
				break
			end
		end
		if hit then
			knockOut(player, root, "GroundAttackHit", hit)
		elseif #waves == 0 then
			fieldWaves[player] = nil
		end
	end
end

-- A spot on the open central lane of `zone` (canyons sit beside it).
local function haulPoint(zone: number, hover: number): Vector3
	local zMax = WorldService.gateZ(zone)
	local zMin = WorldService.gateZ(zone + 1)
	local margin = math.min(40, (zMax - zMin) / 4)
	return Vector3.new(rng:NextNumber(-30, 30), hover, rng:NextNumber(zMin + margin, zMax - margin))
end

-- Once grabbed, the egg's mesh is welded to it so moving the egg moves all.
local function weldCargo(meteor: BasePart)
	for _, part in meteor:GetDescendants() do
		if part:IsA("BasePart") and part.Anchored then
			part.Anchored = false
			local weld = Instance.new("WeldConstraint")
			weld.Part0, weld.Part1 = meteor, part
			weld.Parent = part
		end
	end
end

-- Dropped egg left alone: the nearest idle guard (or a drone flying in)
-- fetches it and carries it back to its zone, where it is guarded again.
function Service.reclaimLater(meteor: BasePart, zone: number, dropper: Player?)
	task.delay(Config.RECLAIM_DELAY, function()
		if not meteor.Parent or meteor:GetAttribute("Taken") then
			return
		end
		local best: Drone? = nil
		local bestDistance = Config.RECLAIM_SEARCH_RADIUS
		for _, drone in drones do
			if drone.target == nil and drone.kind == "drone" and drone.phase == "guard" then
				local distance = (drone.position - meteor.Position).Magnitude
				if distance <= bestDistance then
					best, bestDistance = drone, distance
				end
			end
		end
		if not best then
			best = spawn("drone", zone, meteor.Position + Vector3.new(35, 0, 35), nil)
		end
		local hauler = best
		if not hauler then
			return
		end
		unguard(hauler)
		hauler.orphanUntil = nil
		hauler.zone = zone
		hauler.cargo = meteor
		hauler.haulTo = haulPoint(zone, hauler.hover)
		hauler.alert, hauler.alertTarget = 0, nil
		setSpotting(hauler, false)
		-- Registered as the egg's guard: grabbing it back alerts this drone.
		local list = guards[meteor] or {}
		guards[meteor] = list
		table.insert(list, hauler)
		hauler.meteor = meteor
		meteor:SetAttribute("ExpiresAt", math.huge)
		state(hauler, "fetch")
		if dropper and dropper.Parent == Players then
			Notifier.send(dropper, "egg_reclaim", nil, "warning")
		end
	end)
end

-- Height of the tallest wall top under the next `distance` studs of a path
-- (0 = open ground). Rays drop from above onto the wall blockers only.
local function obstacleTop(from: Vector3, direction: Vector3, distance: number): number
	local top = 0
	local d = 0
	while d <= distance do
		local at = from + direction * d
		local hit =
			workspace:Raycast(Vector3.new(at.X, 150, at.Z), Vector3.new(0, -160, 0), rayParams)
		if hit then
			top = math.max(top, hit.Position.Y)
		end
		d += 4
	end
	return top
end

-- Fetch / haul. The hauler flies over canyon walls: it hovers and climbs in
-- front of a wall, crosses above it, then sinks back down. The egg hangs below
-- it and keeps its pickup prompt, so a player can snatch it back when it is low.
local function stepHauler(drone: Drone, now: number, dt: number)
	local meteor = drone.cargo
	if not meteor or not meteor.Parent then
		drone.cargo, drone.haulTo = nil, nil
		drone.meteor = nil
		drone.home = drone.position
		drone.orphanUntil = now + Config.ORPHAN_SECONDS
		state(drone, "guard")
		return
	end
	local goal = if drone.phase == "fetch"
		then Vector3.new(meteor.Position.X, drone.hover, meteor.Position.Z)
		else drone.haulTo :: Vector3
	local delta = Vector3.new(goal.X - drone.position.X, 0, goal.Z - drone.position.Z)
	local speed = if drone.phase == "fetch"
		then Config.RECLAIM_FLY_SPEED
		else Config.RECLAIM_CARRY_SPEED
	local direction = if delta.Magnitude > 0.05 then delta.Unit else Vector3.zero
	-- Altitude: clear the tallest wall just ahead (and the hanging egg).
	local hang = if drone.phase == "haul" then 2.2 + 1.2 else 0
	local ahead = math.min(delta.Magnitude, Config.FLY_LOOKAHEAD)
	local top = obstacleTop(drone.position, direction, ahead)
	local wanted = if top > 0
		then math.max(drone.hover, top + Config.FLY_CLEARANCE + hang)
		else drone.hover
	local altitude = drone.position.Y
	if wanted > altitude then
		altitude = math.min(wanted, altitude + Config.CLIMB_SPEED * dt)
	else
		altitude = math.max(wanted, altitude - Config.DESCEND_SPEED * dt)
	end
	local climbing = wanted - altitude > 0.5 -- not high enough yet: hold position
	local step = if climbing or direction == Vector3.zero
		then Vector3.zero
		else direction * math.min(speed * dt, delta.Magnitude)
	drone.position = Vector3.new(drone.position.X + step.X, altitude, drone.position.Z + step.Z)
	if direction ~= Vector3.zero then
		drone.yaw = yawOf(direction)
	end
	local landed = delta.Magnitude < 1.5 and altitude <= drone.hover + 0.5
	if drone.phase == "fetch" then
		if landed then
			weldCargo(meteor)
			state(drone, "haul")
		end
	else
		meteor.CFrame = CFrame.new(drone.position - Vector3.new(0, 2.2, 0))
		if landed then
			-- Home: set it down as a guarded field egg again.
			meteor.CFrame = CFrame.new(drone.position.X, FLOOR_TOP + 2, drone.position.Z)
			meteor:SetAttribute("ExpiresAt", os.clock() + Config.RECLAIM_REST_SECONDS)
			drone.cargo, drone.haulTo = nil, nil
			drone.home = Vector3.new(meteor.Position.X, drone.hover, meteor.Position.Z)
			state(drone, "guard")
			local extra = (Config.GUARDS_BY_ZONE[drone.zone] or 1) - 1
			for _ = 1, extra do
				spawn("drone", drone.zone, meteor.Position + Vector3.new(-12, 0, 0), meteor)
			end
		end
	end
	local pos = drone.position + Vector3.new(0, math.sin(now * 3 + drone.orbit) * 0.25, 0)
	place(drone, CFrame.lookAt(pos, pos + facingOf(drone.yaw)))
end

local function step(dt: number)
	local now = os.clock()
	local positions: { Vector3 } = {}
	local carriers: { Carrier } = {}
	local all = Players:GetPlayers()
	for _, player in all do
		local root = rootOf(player)
		if root then
			table.insert(positions, root.Position)
			local carry = CarryService.get(player)
			if
				carry
				and carry.fresh
				and player:GetAttribute("ArenaActive") ~= true
				and WorldService.zoneIndexAt(root.Position) > 0
			then
				local before = lastPoint[player] or root.Position
				local moving = (Vector3.new(
					root.Position.X - before.X,
					0,
					root.Position.Z - before.Z
				)).Magnitude / math.max(dt, 1e-3) > 3
				table.insert(
					carriers,
					{ player = player, root = root, carry = carry, moving = moving }
				)
			end
		end
	end
	for index = #drones, 1, -1 do
		local drone = drones[index]
		if drone.target then
			stepChaser(index, drone, now, dt)
		else
			if isHauling(drone) then
				stepHauler(drone, now, dt)
			else
				stepGuard(index, drone, now, dt, carriers, positions)
			end
		end
	end
	stepAttacks(all)
end

function Service.init()
	folder = Instance.new("Folder")
	folder.Name, folder.Parent = "Snatchers", workspace
	rayParams.FilterType = Enum.RaycastFilterType.Include
	waveEvent = Remotes.event("ArenaWave")
	Players.PlayerRemoving:Connect(function(player)
		fieldWaves[player], nextCast[player], lastKind[player] = nil, nil, nil
		nextWaveId[player], lastPoint[player], spottedNoticeAt[player] = nil, nil, nil
	end)
end

function Service.start()
	local world = workspace:WaitForChild("World")
	local function refreshBlockers()
		local blockers: { Instance } = {}
		local canyons = world:FindFirstChild("Canyons")
		local track = world:FindFirstChild("Track")
		if canyons then
			table.insert(blockers, canyons)
		end
		if track then
			for _, child in track:GetChildren() do
				if child.Name == "SideWall" or child.Name == "EndWall" then
					table.insert(blockers, child)
				end
			end
		end
		rayParams.FilterDescendantsInstances = blockers
	end
	refreshBlockers()
	world.ChildAdded:Connect(function(child)
		if child.Name == "Canyons" then
			refreshBlockers()
		end
	end)
	world.ChildRemoved:Connect(function(child)
		if child.Name == "Canyons" then
			refreshBlockers()
		end
	end)
	local elapsed = 0
	RunService.Heartbeat:Connect(function(dt)
		elapsed += dt
		if elapsed >= Config.SERVER_TICK then
			local stepTime = math.min(elapsed, 0.15)
			elapsed = 0
			step(stepTime)
		end
	end)
end
return Service

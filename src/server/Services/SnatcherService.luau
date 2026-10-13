--!strict
-- Egg guards. Each guard roams around its egg on a smooth, noisy path,
-- sweeping a vision sector over the ground. A carrier caught inside it
-- fills that guard's alert meter (yellow "?"); a full meter starts a chase
-- (red) that pulls in nearby guards. Guards within earshot of a pickup start
-- alert at once (further in noisy deep zones).
-- During a chase an alarm line runs ahead of the carrier and every idle
-- guard it touches joins in; chasers left far behind hand off and go back to
-- their posts.
-- Only telegraphed attacks drop the egg: the dash (a yellow laser sight that
-- leads the runner, then locks red) and,
-- from the attack zone, Undertale-style ground attacks (shared ArenaPatterns
-- math, server hit checks). A shared per-carrier budget alternates attackers.
-- The server simulates swept hits; clients render timed dash segments and
-- interpolate ordinary flight. Body replication is batched at 10 Hz.
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
local ChasePlan = require(Shared.Util.ChasePlan)
local Notifier = require(script.Parent.Parent.Util.Notifier)
local Knockback = require(script.Parent.Parent.Util.Knockback)
local DataService = require(script.Parent.DataService)
local WorldService = require(script.Parent.WorldService)
local CarryService = require(script.Parent.CarryService)
local ArenaService = require(script.Parent.ArenaService)
local Telemetry = require(script.Parent.TelemetryService)

type Drone = {
	id: number,
	velocity: Vector3,
	visualCF: CFrame,
	dashStart: number,
	kind: string, -- "drone" | "hound"
	model: Model,
	root: BasePart,
	offset: CFrame, -- pivot -> root
	hover: number, -- pivot height above the ground plane
	label: TextLabel,
	line: Part, -- dash path on the ground
	aimEnd: Attachment, -- laser sight end (the sight starts at the root)
	sight: { Beam },
	trail: Trail,
	indicator: BasePart?,
	zone: number,
	meteor: BasePart?,
	post: BasePart?, -- the egg it guarded before joining a chase
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
	lockAt: number, -- warning: the sight freezes from here
	dashSpeed: number, -- set while aiming, frozen at the lock
	nextAttack: number,
	position: Vector3,
	origin: Vector3,
	direction: Vector3,
	endpoint: Vector3,
	previousTarget: Vector3,
	orbit: number,
	cargo: BasePart?, -- reclaim: the dropped egg being fetched / carried
	waitMeteor: BasePart?, -- regroup: the knocked-out egg this chaser hovers over
	haulTo: Vector3?,
}

type Carrier = { player: Player, root: BasePart, carry: CarryService.Carry }

local Service = {}
local drones: { Drone } = {}
local guards: { [BasePart]: { Drone } } = {}
local folder: Folder
local rayParams = RaycastParams.new()
local rng = Random.new()
local waveEvent: RemoteEvent
local motionEvent: RemoteEvent
local nextDroneId = 0
type Group = {
	members: { Drone },
	heading: Vector3,
	attackUntil: number,
	nextAttackAt: number,
	lastAttacker: number,
	preferCast: boolean,
	castDeadline: number,
}
local groups: { [Player]: Group } = {}
local motionDirty: { [number]: boolean } = {}
local metrics = { frames = 0, seconds = 0, cpu = 0, maxCPU = 0, maxFrame = 0 }

-- Per-player chase state.
local fieldWaves: { [Player]: { Patterns.Wave } } = {}
local nextCast: { [Player]: number } = {}
local lastKind: { [Player]: string } = {}
local chaseSince: { [Player]: number } = {} -- server time this chase began
local nextWaveId: { [Player]: number } = {}
local lastPoint: { [Player]: Vector3 } = {}
local spottedNoticeAt: { [Player]: number } = {}
local houndFor: { [CarryService.Carry]: boolean } = setmetatable({}, { __mode = "k" }) :: any
-- A player's very first chase stays a gentle one-on-one (no relay).
local introChase: { [CarryService.Carry]: boolean } = setmetatable({}, { __mode = "k" }) :: any

local function chaseCap(player: Player, zone: number): number
	local carry = CarryService.get(player)
	if carry and introChase[carry] then
		return 1
	end
	return math.min(Config.ZONE_CHASER_CAP[zone] or 1, Config.MAX_CHASERS_PER_PLAYER)
end

local function leaveGroup(drone: Drone)
	local player = drone.target
	local group = player and groups[player]
	if group then
		local index = table.find(group.members, drone)
		if index then
			table.remove(group.members, index)
		end
		if #group.members == 0 then
			groups[player :: Player] = nil
		end
	end
end

local FLOOR_TOP = 0.2
local COLORS = {
	patrol = Color3.fromRGB(70, 150, 255),
	alert = Color3.fromRGB(255, 205, 65),
	chase = Color3.fromRGB(255, 65, 90),
	recover = Color3.fromRGB(190, 145, 255),
	aim = Color3.fromRGB(255, 215, 50),
	lock = Color3.fromRGB(255, 30, 45),
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
	drone.visualCF = cframe * drone.offset
end

local function alertBar(alert: number): string
	local filled = math.clamp(math.floor(alert * 5 + 0.5), 0, 5)
	return "?  " .. string.rep("▮", filled) .. string.rep("▯", 5 - filled)
end

local function state(drone: Drone, phase: string)
	if drone.phase == phase and drone.model:GetAttribute("State") == phase then
		return
	end
	motionDirty[drone.id] = true
	drone.phase = phase
	drone.model:SetAttribute("State", phase)
	local color = if phase == "guard"
		then COLORS.patrol
		elseif phase == "alert" then COLORS.alert
		elseif phase == "recover" then COLORS.recover
		elseif phase == "warning" then COLORS.alert
		else COLORS.chase
	drone.label.Text = if phase == "warning" or phase == "lock"
		then "DODGE!"
		elseif phase == "dash" then "ATTACK"
		elseif phase == "cast" then "FIRE!"
		elseif phase == "guard" then "EGG GUARD"
		elseif phase == "alert" then alertBar(drone.alert)
		elseif phase == "recover" then "RECHARGING"
		elseif phase == "regroup" then "HUNTING"
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
	-- Dash telegraph: yellow sight while aiming, red once locked, then a
	-- streak along the red path.
	local aiming = phase == "warning" or phase == "lock"
	local sightColor = if phase == "warning" then COLORS.aim else COLORS.lock
	drone.line.Transparency = if phase == "warning"
		then 0.78
		elseif phase == "lock" then 0.45
		elseif phase == "dash" then 0.6
		else 1
	drone.line.Color = sightColor
	for _, beam in drone.sight do
		beam.Enabled = aiming
		beam.Color = ColorSequence.new(
			if beam.Name == "SightCore"
				then sightColor:Lerp(Color3.new(1, 1, 1), 0.5)
				else sightColor
		)
	end
	drone.trail.Enabled = phase == "dash"
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

-- Register a drone as one of `meteor`'s guards, patrolling around it.
local function guard(drone: Drone, meteor: BasePart)
	local list = guards[meteor] or {}
	guards[meteor] = list
	table.insert(list, drone)
	drone.meteor = meteor
	drone.home = Vector3.new(meteor.Position.X, drone.hover, meteor.Position.Z)
	drone.orphanUntil = nil
	meteor:SetAttribute("Guarded", true)
end

local function laser(
	name: string,
	width: number,
	transparency: number,
	a0: Attachment,
	a1: Attachment
): Beam
	local beam = Instance.new("Beam")
	beam.Name = name
	beam.Attachment0, beam.Attachment1 = a0, a1
	beam.Width0, beam.Width1 = width, width
	beam.FaceCamera, beam.Segments = true, 1
	beam.LightEmission, beam.LightInfluence = 1, 0
	beam.Transparency = NumberSequence.new(transparency)
	beam.Enabled = false
	beam.Parent = a0
	return beam
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
	-- Laser sight from the drone's body to the dash endpoint (body height).
	local eye = Instance.new("Attachment")
	eye.Name = "AimEye"
	eye.Parent = root
	local aimEnd = Instance.new("Attachment")
	aimEnd.Name = "AimEnd"
	aimEnd.Parent = workspace.Terrain
	local sight = {
		laser("SightHalo", 1.1, 0.75, eye, aimEnd),
		laser("SightCore", 0.16, 0.05, eye, aimEnd),
	}
	-- Dash streak.
	local top, bottom = Instance.new("Attachment"), Instance.new("Attachment")
	top.Position, bottom.Position = Vector3.new(0, 0.9, 0), Vector3.new(0, -0.9, 0)
	top.Parent, bottom.Parent = root, root
	local trail = Instance.new("Trail")
	trail.Attachment0, trail.Attachment1 = top, bottom
	trail.Lifetime, trail.MinLength = 0.15, 0.1
	trail.FaceCamera, trail.LightEmission, trail.LightInfluence = true, 1, 0
	trail.Color = ColorSequence.new(COLORS.lock)
	trail.Transparency = NumberSequence.new(0.15, 1)
	trail.WidthScale = NumberSequence.new(1, 0.2)
	trail.Enabled = false
	trail.Parent = root
	local home = meteor and Vector3.new(meteor.Position.X, hover, meteor.Position.Z) or position
	nextDroneId += 1
	local drone: Drone = {
		id = nextDroneId,
		velocity = Vector3.zero,
		visualCF = root.CFrame,
		dashStart = 0,
		kind = kind,
		model = model,
		root = root,
		offset = offset,
		hover = hover,
		label = label,
		line = line,
		aimEnd = aimEnd,
		sight = sight,
		trail = trail,
		indicator = indicator,
		zone = zone,
		meteor = nil,
		post = nil,
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
		lockAt = 0,
		dashSpeed = Config.DASH_SPEED,
		nextAttack = 0,
		position = position,
		origin = position,
		direction = Vector3.new(0, 0, 1),
		endpoint = position,
		previousTarget = position,
		orbit = rng:NextNumber(0, math.pi * 2),
		cargo = nil,
		haulTo = nil,
		waitMeteor = nil,
	}
	model:SetAttribute("DroneId", drone.id)
	model:SetAttribute("ZoneIndex", zone)
	model:SetAttribute("Kind", kind)
	model:SetAttribute("Spotting", false)
	model.Parent = folder
	state(drone, "guard")
	table.insert(drones, drone)
	if meteor then
		guard(drone, meteor)
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
	leaveGroup(drone)
	unguard(drone)
	table.remove(drones, index)
	drone.line:Destroy()
	drone.aimEnd:Destroy()
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
	leaveGroup(drone)
	local group = groups[player]
	if not group then
		group = {
			members = {},
			heading = flatUnit(root.CFrame.LookVector),
			attackUntil = 0,
			nextAttackAt = 0,
			lastAttacker = 0,
			preferCast = false,
			castDeadline = 0,
		}
		groups[player] = group
	end
	table.insert(group.members, drone)
	drone.velocity = Vector3.zero
	drone.post = drone.post or drone.meteor
	unguard(drone)
	drone.target, drone.carry, drone.factor = player, CarryService.get(player), factor
	drone.alert, drone.alertTarget = 0, nil
	setSpotting(drone, false)
	drone.bornAt, drone.nextAttack = os.clock(), os.clock() + Config.PICKUP_GRACE + delay
	drone.previousTarget = root.Position
	drone.model:SetAttribute("TargetUserId", player.UserId)
	state(drone, "chase")
end

-- Chase over for this drone: back to its egg if that is still out in the
-- field, else it patrols here for a while and then leaves.
local function release(drone: Drone, now: number)
	leaveGroup(drone)
	drone.target, drone.carry, drone.waitMeteor = nil, nil, nil
	drone.model:SetAttribute("TargetUserId", nil)
	local post = drone.post
	drone.post = nil
	if post and post.Parent and not post:GetAttribute("Taken") then
		guard(drone, post)
	else
		drone.home = Vector3.new(drone.position.X, drone.hover, drone.position.Z)
		drone.orphanUntil = now + Config.ORPHAN_SECONDS
	end
	state(drone, "guard")
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
	count = math.min(count, chaseCap(player, zone))
	local hound = Config.HOUND_ENABLED and zone >= Config.HOUND_FROM_ZONE and not houndFor[carry]
	if zone == 1 then
		count, factor = 1, Config.FIRST_TIME_FACTOR
	end
	if profile and not profile.flags.snatcherIntro then
		profile.flags.snatcherIntro = true
		count, factor, hound = 1, Config.FIRST_TIME_FACTOR, false
		introChase[carry] = true
	end
	local already = chasersOf(player)
	if already >= count then
		if already > 0 and already < count and not introChase[carry] then
			-- A chase is already on: one more guard that sees the thief joins.
			activate(spotter, player, factor, 0)
			return
		end
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
		local forward = flatUnit(root.CFrame.LookVector)
		local right = Vector3.new(-forward.Z, 0, forward.X)
		local offset = right * (if already % 2 == 0 then -9 else 9) - forward * (16 + already * 4)
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
	-- A knocked-out egg grabbed back: its chasers (and hound) resume at once,
	-- now after whoever holds it.
	local resumed = false
	for _, drone in drones do
		if drone.waitMeteor == meteor then
			drone.waitMeteor = nil
			activate(drone, player, drone.factor, 0)
			drone.nextAttack = os.clock() + Config.RESUME_GRACE
			resumed = true
		end
	end
	local list = guards[meteor]
	if list then
		for _, drone in table.clone(list) do
			drone.home = Vector3.new(meteor.Position.X, drone.hover, meteor.Position.Z)
			drone.orphanUntil = os.clock() + Config.ORPHAN_SECONDS
			unguard(drone)
			if drone.cargo == meteor then
				-- Snatched back from a reclaiming drone: it gives chase.
				drone.cargo, drone.haulTo = nil, nil
				activate(drone, player, Config.SPEED_FACTOR, 0)
				drone.nextAttack = os.clock() + Config.RESUME_GRACE
				resumed = true
			end
		end
	end
	if resumed then
		nextCast[player] = workspace:GetServerTimeNow() + Config.RESUME_GRACE + 0.7
		Notifier.send(player, "snatcher_chasing", nil, "warning")
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
			-- No meter: a guard that sees the thief gives chase at once.
			startChase(drone, seen.player)
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
			startChase(drone, carrier.player)
			return true
		end
		drone.alert -= Config.ALERT_DECAY * dt
		if drone.alert <= 0 then
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

-- Persistent join order is the slot order; no sorting roles by distance.
local function moveFormation(
	drone: Drone,
	player: Player,
	root: BasePart,
	dt: number,
	factor: number
)
	local group = groups[player]
	if not group then
		return
	end
	local slot = table.find(group.members, drone) or 1
	local count = #group.members
	local role = ChasePlan.role(slot, count)
	drone.model:SetAttribute("ChaseSlot", slot)
	drone.model:SetAttribute("ChaseRole", role)
	local humanoid = (player.Character :: Model):FindFirstChildOfClass("Humanoid")
	local carrierSpeed = if humanoid then humanoid.WalkSpeed else 16
	local point = ChasePlan.target(
		Vector3.new(root.Position.X, drone.hover, root.Position.Z),
		group.heading,
		carrierSpeed,
		slot,
		count,
		Config.FORMATION
	)
	for i, other in group.members do
		if other ~= drone then
			point += ChasePlan.separation(
				drone.position,
				other.position,
				Config.SEPARATION_DISTANCE,
				group.heading * (if slot > i then 1 else -1)
			) * Config.SEPARATION_WEIGHT
		end
	end
	point = Vector3.new(
		math.clamp(point.X, -Config.TRACK_HALF_WIDTH, Config.TRACK_HALF_WIDTH),
		drone.hover,
		math.clamp(point.Z, Config.TRACK_MIN_Z, -2)
	)
	local speed = math.min(
		Config.ROLE_MAX_SPEED,
		Config.ROLE_BASE_SPEED + carrierSpeed * Config.ROLE_SPEED_SCALE * Config.ROLE_SPEED[role]
	)
	if
		drone.carry and introChase[drone.carry]
		or (drone.zone == 1 and (drone.carry == nil or (drone.carry.originZone or 1) <= 1))
	then
		speed = math.min(speed, math.max(5, carrierSpeed * Config.FIRST_TIME_FACTOR))
	end
	drone.velocity =
		ChasePlan.steer(drone.velocity, point - drone.position, speed * factor, dt, Config.STEERING)
	local move = drone.velocity * dt
	if move.Magnitude > 0.001 then
		local hit = workspace:Raycast(drone.position, move + move.Unit * 1.5, rayParams)
		if hit then
			move -= hit.Normal * move:Dot(hit.Normal)
		end
		local allowed = blockedMove(drone.position, move)
		drone.position += allowed
		drone.velocity = allowed / math.max(dt, 0.001)
	end
end

-- Zone 1's softer dash (slower, longer telegraph, half the lead) is for
-- zone-1 eggs only; a deep-zone egg run through zone 1 gets the full thing.
local function gentle(drone: Drone): boolean
	local carry = drone.carry
	return (carry ~= nil and introChase[carry] == true)
		or (drone.zone == 1 and (carry == nil or (carry.originZone or 1) <= 1))
end

-- The zone's dash speed, but always well above the carrier's current running
-- speed: nobody simply outruns a dash.
local function dashSpeedFor(drone: Drone, root: BasePart): number
	local velocity = root.AssemblyLinearVelocity
	local running = Vector2.new(velocity.X, velocity.Z).Magnitude
	local base = if gentle(drone) then Config.FIRST_ZONE_DASH_SPEED else Config.DASH_SPEED
	return math.max(base, running * Config.DASH_SPEED_FACTOR)
end

local function dashLength(speed: number): number
	return math.max(Config.DASH_DISTANCE, speed * Config.DASH_SECONDS)
end

local function hitRadius(speed: number): number
	return math.max(Config.HIT_RADIUS, speed * Config.DASH_HIT_SECONDS)
end

local function warningSeconds(drone: Drone): number
	return if gentle(drone) then Config.FIRST_ZONE_WARNING_SECONDS else Config.WARNING_SECONDS
end

-- Where the carrier will be when a dash launched `untilDash` seconds from now
-- (at `speed`) reaches them, assuming they keep running straight (at hover
-- height).
local function predict(drone: Drone, root: BasePart, untilDash: number, speed: number): Vector3
	local velocity = root.AssemblyLinearVelocity
	local flat = Vector3.new(velocity.X, 0, velocity.Z)
		* (if gentle(drone) then Config.FIRST_ZONE_DASH_PREDICT else 1)
	local here = Vector3.new(root.Position.X, drone.hover, root.Position.Z)
	-- Runner's offset when the dash starts, then the flight time t solving
	-- |start + flat * t| = speed * t (one positive root: speed > runner).
	local start = here + flat * untilDash - drone.position
	local a = flat:Dot(flat) - speed * speed
	local b = 2 * start:Dot(flat)
	local c = start:Dot(start)
	local flight = if a < -1e-6
		then (-b - math.sqrt(math.max(0, b * b - 4 * a * c))) / (2 * a)
		else start.Magnitude / math.max(speed, 1)
	local ahead = flat * (untilDash + flight)
	if ahead.Magnitude > Config.DASH_MAX_LEAD then
		ahead = ahead.Unit * Config.DASH_MAX_LEAD
	end
	return here + ahead
end

-- Point the dash (and its telegraph) at `point`. It ends at a blocking wall;
-- the dash uses this same endpoint.
local function aim(drone: Drone, point: Vector3)
	local direction, endpoint = Combat.plan(drone.position, point, dashLength(drone.dashSpeed))
	local move = blockedMove(drone.position, endpoint - drone.position)
	drone.origin, drone.direction, drone.endpoint = drone.position, direction, drone.position + move
	drone.line.Size =
		Vector3.new(hitRadius(drone.dashSpeed) * 2, 0.12, math.max(0.1, move.Magnitude))
	local midpoint = (drone.origin + drone.endpoint) / 2
	drone.line.CFrame = CFrame.lookAt(
		Vector3.new(midpoint.X, 0.65, midpoint.Z),
		Vector3.new(midpoint.X, 0.65, midpoint.Z) + direction
	)
	drone.aimEnd.WorldPosition = drone.endpoint
end

local function warning(drone: Drone, point: Vector3, speed: number, now: number)
	drone.dashSpeed = speed
	aim(drone, point)
	local group = drone.target and groups[drone.target]
	if group then
		group.attackUntil = now
			+ warningSeconds(drone)
			+ (drone.endpoint - drone.origin).Magnitude / speed
		group.nextAttackAt = group.attackUntil + Config.GROUP_RECOVERY_SECONDS
		group.lastAttacker = drone.id
		group.preferCast = true
		group.castDeadline = group.nextAttackAt + 0.4
	end
	drone.velocity = Vector3.zero
	drone.phaseUntil = now + warningSeconds(drone)
	drone.lockAt = drone.phaseUntil - Config.LOCK_SECONDS
	state(drone, "warning")
end

local function knockOut(player: Player, root: BasePart, telemetry: string, from: Vector3?)
	if ArenaService.isProtected(player) then
		return
	end
	CarryService.drop(player, root.Position)
	Knockback.apply(player, from)
	fieldWaves[player] = nil
	Notifier.send(player, "snatcher_grabbed", nil, "warning")
	Telemetry.custom(player, telemetry)
end

local function dashTurn(drone: Drone, group: Group, root: BasePart, now: number): boolean
	if
		group.preferCast
		and workspace:GetServerTimeNow() >= (nextCast[drone.target :: Player] or 0)
		and now < group.castDeadline
	then
		return false
	end
	local start = 1
	for i, member in group.members do
		if member.id == group.lastAttacker then
			start = i % #group.members + 1
			break
		end
	end
	for offset = 0, #group.members - 1 do
		local member = group.members[(start + offset - 1) % #group.members + 1]
		if member.phase ~= "chase" or now < member.nextAttack then
			continue
		end
		local speed = dashSpeedFor(member, root)
		local delta = predict(member, root, warningSeconds(member), speed) - member.position
		if
			delta.Magnitude <= Config.ATTACK_RANGE * dashLength(speed) / Config.DASH_DISTANCE
			and not workspace:Raycast(member.position, delta, rayParams)
		then
			return member == drone
		end
	end
	return false
end

-- Chase behaviour (dash cycle) for one drone. Returns false if despawned.
-- Circle the knocked-out egg (on the ground, or under a hauling drone) until
-- someone grabs it back (see onPickup) or the window runs out.
local function stepRegroup(index: number, drone: Drone, now: number, dt: number): boolean
	local meteor = drone.waitMeteor :: BasePart
	if not meteor.Parent or now - drone.bornAt > Config.REGROUP_SECONDS then
		if drone.kind == "hound" then
			despawn(index)
			return false
		end
		release(drone, now)
		return true
	end
	local angle = now * 1.3 + drone.orbit
	local goal = Vector3.new(meteor.Position.X, drone.hover, meteor.Position.Z)
		+ Vector3.new(math.cos(angle), 0, math.sin(angle)) * Config.REGROUP_RADIUS
	local delta = goal - drone.position
	if delta.Magnitude > 0.05 then
		drone.position += delta.Unit * math.min(Config.REGROUP_SPEED * dt, delta.Magnitude)
	end
	local facing = flatUnit(meteor.Position - drone.position)
	drone.yaw = yawOf(facing)
	local pos = drone.position + Vector3.new(0, math.sin(now * 3 + drone.orbit) * 0.25, 0)
	place(drone, CFrame.lookAt(pos, pos + facing))
	return true
end

local function stepChaser(index: number, drone: Drone, now: number, dt: number): boolean
	if drone.waitMeteor then
		return stepRegroup(index, drone, now, dt)
	end
	local player = drone.target :: Player
	local root = rootOf(player)
	if
		player.Parent ~= Players
		or not root
		or CarryService.get(player) ~= drone.carry
		or ArenaService.isProtected(player)
		or now - drone.bornAt > Config.GIVE_UP_SECONDS
		or WorldService.zoneIndexAt(root.Position) == 0
	then
		despawn(index)
		return false
	end
	local target = Vector3.new(root.Position.X, drone.hover, root.Position.Z)
	local delta = target - drone.position
	local group = groups[player]
	if drone.phase == "chase" then
		-- Aim where the runner is going, so a fast carrier cannot just
		-- outrun the telegraph.
		local dashSpeed = dashSpeedFor(drone, root)
		local point = predict(drone, root, warningSeconds(drone), dashSpeed)
		local intercept = point - drone.position
		local range = Config.ATTACK_RANGE * dashLength(dashSpeed) / Config.DASH_DISTANCE
		if
			now >= drone.nextAttack
			and group ~= nil
			and now >= group.nextAttackAt
			and dashTurn(drone, group, root, now)
			and intercept.Magnitude <= range
			and not workspace:Raycast(drone.position, intercept, rayParams)
		then
			warning(drone, point, dashSpeed, now)
		else
			moveFormation(drone, player, root, dt, 1)
		end
	elseif drone.phase == "warning" then
		-- The yellow sight tracks the runner, then locks red.
		if now >= drone.lockAt then
			if group then
				group.attackUntil = drone.phaseUntil
					+ (drone.endpoint - drone.origin).Magnitude / drone.dashSpeed
				group.nextAttackAt = group.attackUntil + Config.GROUP_RECOVERY_SECONDS
				group.castDeadline = group.nextAttackAt + 0.4
			end
			drone.dashStart = workspace:GetServerTimeNow() + math.max(0, drone.phaseUntil - now)
			state(drone, "lock")
		else
			drone.dashSpeed = dashSpeedFor(drone, root)
			aim(drone, predict(drone, root, drone.phaseUntil - now, drone.dashSpeed))
		end
	elseif drone.phase == "cast" then
		-- Hovers still while its attack pours out (aimed when it was cast).
		if now >= drone.phaseUntil then
			drone.nextAttack = math.max(drone.nextAttack, now + 0.4)
			state(drone, "chase")
		end
	elseif drone.phase == "lock" then
		-- Facing and endpoint stay locked even if the player moves sideways.
		if now >= drone.phaseUntil then
			state(drone, "dash")
		end
	end
	if drone.phase == "dash" then
		local speed = drone.dashSpeed
		local from = drone.position
		local progress = math.min(
			(workspace:GetServerTimeNow() - drone.dashStart) * speed,
			(drone.endpoint - drone.origin).Magnitude
		)
		local desired = drone.origin + drone.direction * progress
		local move = blockedMove(from, desired - from)
		drone.position += move
		if
			math.abs(root.Position.Y - drone.hover) < 6
			and Combat.hits(
				from,
				drone.position,
				drone.previousTarget,
				root.Position,
				hitRadius(speed)
			)
			and not workspace:Raycast(drone.position, root.Position - drone.position, rayParams)
		then
			knockOut(
				player,
				root,
				if drone.kind == "hound" then "HoundCaught" else "SnatcherCaught",
				from
			)
			return true -- the drop put this chaser into regroup (see reclaimLater)
		end
		if (drone.endpoint - drone.position).Magnitude < 0.1 or move.Magnitude < 0.01 then
			drone.phaseUntil = now + Config.RECOVERY_SECONDS
			state(drone, "recover")
		end
	elseif drone.phase == "recover" then
		moveFormation(drone, player, root, dt, Config.RECOVERY_SPEED_FACTOR)
		if now >= drone.phaseUntil then
			drone.nextAttack = now + 0.35
			state(drone, "chase")
		end
	end
	drone.previousTarget = root.Position
	local facing = if drone.phase == "warning"
			or drone.phase == "lock"
			or drone.phase == "dash"
			or drone.phase == "cast"
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

local DRONE_FIRED = { bombs = true, spiral = true, laser = true }

-- Pick an unlocked attack some chasing drone can reach and fire it from that
-- drone at where the runner will be. False if no drone is in reach.
local function castAttack(
	player: Player,
	root: BasePart,
	zone: number,
	level: number,
	casters: { Drone },
	now: number
): boolean
	local kinds: { string } = {}
	for kind, from in Config.ATTACK_UNLOCKS do
		if zone >= from and kind ~= lastKind[player] then
			table.insert(kinds, kind)
		end
	end
	for i = #kinds, 2, -1 do
		local j = rng:NextInteger(1, i)
		kinds[i], kinds[j] = kinds[j], kinds[i]
	end
	local velocity = root.AssemblyLinearVelocity
	local flat = Vector2.new(velocity.X, velocity.Z)
	local moving = flat.Magnitude > 4
	local direction = if moving then flat.Unit else Vector2.new(0, 1)
	for _, kind in kinds do
		local ahead = if moving then flat * (0.25 + Patterns.leadFor(kind, level)) else Vector2.zero
		if ahead.Magnitude > Config.ATTACK_MAX_LEAD then
			ahead = ahead.Unit * Config.ATTACK_MAX_LEAD
		end
		local target = Vector2.new(root.Position.X, root.Position.Z) + ahead
		local caster: Drone? = nil
		local best = Config.ATTACK_REACH[kind] or Config.ATTACK_CAST_RANGE
		for _, drone in casters do
			local d = (Vector2.new(drone.position.X, drone.position.Z) - target).Magnitude
			if d <= best and (d >= 6 or not DRONE_FIRED[kind]) then
				caster, best = drone, d
			end
		end
		if not caster then
			continue
		end
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
			-- Ground patterns turn to follow the runner; drone-fired ones aim
			-- from the drone itself.
			heading = if DRONE_FIRED[kind] then nil else Patterns.axisHeading(direction),
			ox = caster.position.X,
			oz = caster.position.Z,
			dx = direction.X,
			dz = direction.Y,
		}
		if DRONE_FIRED[kind] then
			caster.direction =
				flatUnit(Vector3.new(target.X - caster.position.X, 0, target.Y - caster.position.Z))
			caster.phaseUntil = os.clock() + 0.25 + Patterns.castTime(wave)
			state(caster, "cast")
		end
		local waves = fieldWaves[player] or {}
		table.insert(waves, wave)
		fieldWaves[player] = waves
		local group = groups[player]
		if group then
			group.attackUntil = os.clock() + 0.25 + Patterns.duration(wave)
			group.nextAttackAt = group.attackUntil + Config.GROUP_RECOVERY_SECONDS
			group.preferCast = false
			group.lastAttacker = caster.id
		end
		waveEvent:FireClient(player, wave)
		lastKind[player] = kind
		return true
	end
	return false
end

-- Drone attacks cast at a chased carrier, and their hit checks.
local function stepAttacks(players: { Player })
	local now = workspace:GetServerTimeNow()
	for _, player in players do
		local root = rootOf(player)
		local waves = fieldWaves[player]
		if not root or not CarryService.get(player) or ArenaService.isProtected(player) then
			fieldWaves[player] = nil
			chaseSince[player] = nil
			continue
		end
		-- Cast: the deepest zone among this player's chasers (or the egg's
		-- own zone) sets the pace and which attacks are unlocked.
		local zone = 0
		local casters: { Drone } = {}
		local group = groups[player]
		local members: { Drone } = if group then group.members else {}
		for _, drone in members do
			if drone.kind == "drone" and drone.waitMeteor == nil then
				zone = math.max(zone, drone.zone)
				if drone.phase == "chase" then
					table.insert(casters, drone)
				end
			end
		end
		if zone == 0 then
			chaseSince[player] = nil
		else
			-- A deep-zone egg keeps its zone's attacks all the way home.
			local carried = CarryService.get(player) :: CarryService.Carry
			zone = math.max(zone, carried.originZone or 0)
			chaseSince[player] = chaseSince[player] or now
		end
		local every = Config.ATTACK_EVERY_BY_ZONE[zone] or 0
		if
			zone >= Config.ATTACKS_FROM_ZONE
			and every > 0
			and #casters > 0
			and not introChase[CarryService.get(player) :: CarryService.Carry]
			and now >= (nextCast[player] or 0)
			and groups[player] ~= nil
			and os.clock() >= groups[player].nextAttackAt
		then
			local carry = CarryService.get(player) :: CarryService.Carry
			local level = math.min(
				Patterns.level(Rarity.INFO[carry.state.rarity].order, math.max(zone, 3), 0)
					+ Config.ATTACK_RAMP * (now - (chaseSince[player] or now)),
				Config.ATTACK_MAX_LEVEL
			)
			if castAttack(player, root, zone, level, casters, now) then
				nextCast[player] = now + every
			end
		end
		waves = fieldWaves[player]
		if not waves then
			lastPoint[player] = root.Position
			continue
		end
		-- Hits.
		-- Fast runners cross a pellet within one tick: check along the step.
		local point = Vector2.new(root.Position.X, root.Position.Z)
		local before = lastPoint[player] or root.Position
		local from = Vector2.new(before.X, before.Z)
		local samples =
			{ point, from:Lerp(point, 0.25), from:Lerp(point, 0.5), from:Lerp(point, 0.75) }
		lastPoint[player] = root.Position
		local hit: Vector3? = nil
		for i = #waves, 1, -1 do
			local wave = waves[i]
			if now > wave.t0 + Patterns.duration(wave) then
				table.remove(waves, i)
				continue
			end
			for _, hazard in Patterns.sample(wave, now) do
				for _, sample in samples do
					if Patterns.hits(hazard, sample, true) then
						hit = Vector3.new(hazard.position.X, root.Position.Y, hazard.position.Y)
						break
					end
				end
				if hit then
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
	-- The dropper's chasers keep the hunt alive over the egg itself.
	if dropper then
		local now = os.clock()
		for _, drone in drones do
			if drone.target == dropper and drone.waitMeteor == nil then
				drone.waitMeteor, drone.carry = meteor, nil
				drone.bornAt = now
				drone.line.Transparency = 1
				state(drone, "regroup")
			end
		end
	end
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
		guard(hauler, meteor)
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

-- A red ring bursts from a guard the alarm line just reached.
local function alarmPing(drone: Drone)
	local ring = Instance.new("Part")
	ring.Name, ring.Shape = "AlarmPing", Enum.PartType.Cylinder
	ring.Anchored, ring.CanCollide, ring.CanQuery, ring.CanTouch = true, false, false, false
	ring.Material, ring.Color, ring.CastShadow = Enum.Material.Neon, COLORS.lock, false
	ring.Transparency = 0.2
	ring.Size = Vector3.new(0.2, 2, 2)
	ring.CFrame = CFrame.new(drone.position) * CFrame.Angles(0, 0, math.rad(90))
	ring.Parent = folder
	TweenService:Create(
		ring,
		TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Size = Vector3.new(0.2, 16, 16), Transparency = 1 }
	):Play()
	task.delay(0.55, function()
		ring:Destroy()
	end)
end

local function flatDistance(a: Vector3, b: Vector3): number
	return Vector2.new(a.X - b.X, a.Z - b.Z).Magnitude
end

-- The chase relay: an alarm line runs ahead of each chased carrier and idle
-- guards it touches join the chase; chasers left far behind hand off (the
-- nearest one always stays on).
local function stepRelay(now: number)
	for _, player in Players:GetPlayers() do
		local carry = CarryService.get(player)
		local root = rootOf(player)
		if not carry or not root or introChase[carry] or ArenaService.isProtected(player) then
			continue
		end
		local chasers: { Drone } = {}
		for _, drone in drones do
			if
				drone.target == player
				and drone.kind == "drone"
				and drone.waitMeteor == nil
				and drone.carry == carry
			then
				table.insert(chasers, drone)
			end
		end
		if #chasers == 0 then
			continue
		end
		local factor = chasers[1].factor
		table.sort(chasers, function(a, b)
			return flatDistance(a.position, root.Position) < flatDistance(b.position, root.Position)
		end)
		local velocity = root.AssemblyLinearVelocity
		local flat = Vector3.new(velocity.X, 0, velocity.Z)
		local speed = flat.Magnitude
		-- Only chasers the runner has left behind hand off; the ones the line
		-- just woke up ahead are far away too, but still to come.
		for i = #chasers, 2, -1 do
			local drone = chasers[i]
			local behind = speed < 4 or (drone.position - root.Position):Dot(flat) < 0
			if
				(drone.phase == "chase" or drone.phase == "recover")
				and behind
				and flatDistance(drone.position, root.Position) > Config.RELAY_DROP_DISTANCE
			then
				release(drone, now)
				table.remove(chasers, i)
			end
		end
		if speed < 4 then
			continue
		end
		local forward = flat / speed
		local reach = math.clamp(
			speed * Config.RELAY_AHEAD_SECONDS,
			Config.RELAY_MIN_AHEAD,
			Config.RELAY_MAX_AHEAD
		)
		local count = #chasers
		for _, drone in drones do
			if count >= chaseCap(player, WorldService.zoneIndexAt(root.Position)) then
				break
			end
			if drone.target == nil and drone.kind == "drone" and not isHauling(drone) then
				local offset = Vector3.new(
					drone.position.X - root.Position.X,
					0,
					drone.position.Z - root.Position.Z
				)
				local along = offset:Dot(forward)
				if
					along >= 0
					and along <= reach
					and offset:Cross(forward).Magnitude <= Config.RELAY_HALF_WIDTH
				then
					activate(drone, player, factor, 0)
					drone.nextAttack = now + Config.RELAY_GRACE
					alarmPing(drone)
					count += 1
				end
			end
		end
	end
end

local positions: { Vector3 } = {}
local carriers: { Carrier } = {}
local function step(dt: number, guardDt: number?)
	local now = os.clock()
	if guardDt then
		table.clear(positions)
		table.clear(carriers)
		for _, player in Players:GetPlayers() do
			local root = rootOf(player)
			if root then
				table.insert(positions, root.Position)
				local carry = CarryService.get(player)
				if
					carry
					and carry.fresh
					and not ArenaService.isProtected(player)
					and WorldService.zoneIndexAt(root.Position) > 0
				then
					table.insert(carriers, { player = player, root = root, carry = carry })
				end
			end
		end
	end
	for index = #drones, 1, -1 do
		local drone = drones[index]
		if drone.target then
			stepChaser(index, drone, now, dt)
		elseif guardDt then
			if isHauling(drone) then
				stepHauler(drone, now, guardDt)
			else
				stepGuard(index, drone, now, guardDt, carriers, positions)
			end
		end
	end
end

local function requireChaseQA()
	assert(RunService:IsStudio(), "Studio only")
	local args = game:GetService("StudioTestService"):GetTestArgs()
	assert(
		typeof(args) == "table"
			and args.suite == "preprod"
			and (args.mode == "chase" or args.mode == "arena"),
		"opt-in isolated chase test only"
	)
end

function Service.debugEnd(player: Player)
	requireChaseQA()
	CarryService.clear(player)
	local root = rootOf(player)
	if root then
		root.Anchored = false
	end
	for i = #drones, 1, -1 do
		if drones[i].target == player then
			despawn(i)
		end
	end
	groups[player], fieldWaves[player], nextCast[player] = nil, nil, nil
end

function Service.debugBegin(player: Player, count: number, carrierSpeed: number): { number }
	requireChaseQA()
	Service.debugEnd(player)
	local root = assert(rootOf(player), "no body")
	local data = assert(DataService.get(player), "no isolated profile")
	data.flags.snatcherIntro = true
	data.speed, data.rebirths = 10000, 10
	-- Outside the central Void Run corridor; its real service must not consume
	-- this deep-cargo chase fixture before the observations complete.
	local at = Vector3.new(if player.UserId % 2 == 0 then -170 else 170, 4, -700)
	require(script.Parent.SpeedService).markTeleport(player, at)
	local character = assert(player.Character, "no character")
	character:PivotTo(CFrame.new(at))
	root.Anchored = true
	assert(
		CarryService.begin(player, {
			state = { creatureId = "comet_cat", rarity = "Rare", paid = false },
			fresh = true,
			originZone = 3,
			onLost = function(_player, _carry, _position) end,
		}),
		"QA carry"
	)
	local h = (player.Character :: Model):FindFirstChildOfClass("Humanoid")
	if h then
		h.WalkSpeed = carrierSpeed
	end
	local ids = {}
	for i = 1, count do
		local drone =
			assert(spawn("drone", 3, at + Vector3.new((i - 2) * 10, 0, -70), nil), "QA drone")
		activate(drone, player, Config.SPEED_FACTOR, 0)
		drone.nextAttack = os.clock() + 30
		table.insert(ids, drone.id)
	end
	nextCast[player] = workspace:GetServerTimeNow() + 30
	return ids
end

function Service.debugSnapshot(player: Player): any
	requireChaseQA()
	local group = groups[player]
	local result = {}
	if group then
		for slot, drone in group.members do
			table.insert(result, {
				id = drone.id,
				slot = slot,
				role = ChasePlan.role(slot, #group.members),
				position = drone.position,
				phase = drone.phase,
				velocity = drone.velocity,
				attackUntil = group.attackUntil,
			})
		end
	end
	return result
end

function Service.debugMetrics(): any
	requireChaseQA()
	return metrics
end

function Service.debugDash(player: Player): boolean
	requireChaseQA()
	local group = groups[player]
	if not group or os.clock() < group.nextAttackAt then
		return false
	end
	local drone = group.members[1]
	drone.position = (assert(rootOf(player))).Position + Vector3.new(-46, 0, -45)
	drone.origin, drone.endpoint, drone.direction =
		drone.position, drone.position + Vector3.new(46, 0, 0), Vector3.xAxis
	drone.dashSpeed = 115
	drone.phaseUntil = os.clock() + Config.LOCK_SECONDS
	drone.dashStart = workspace:GetServerTimeNow() + Config.LOCK_SECONDS
	drone.velocity = Vector3.zero
	group.attackUntil = drone.phaseUntil + 0.4
	group.nextAttackAt = group.attackUntil + Config.GROUP_RECOVERY_SECONDS
	place(drone, CFrame.lookAt(drone.position, drone.endpoint))
	state(drone, "lock")
	return true
end

-- Exercise the same damage boundary as dash/ground attacks before the arena
-- heartbeat can set its replicated flags. Only isolated Studio QA can call it.
function Service.debugIncomingHit(player: Player): boolean
	requireChaseQA()
	local before = assert(CarryService.get(player), "no QA cargo")
	local root = assert(rootOf(player), "no QA body")
	knockOut(player, root, "QAIncomingHit", root.Position - Vector3.zAxis)
	return CarryService.get(player) == before
end

function Service.init()
	folder = Instance.new("Folder")
	folder.Name, folder.Parent = "Snatchers", workspace
	rayParams.FilterType = Enum.RaycastFilterType.Include
	waveEvent = Remotes.event("ArenaWave")
	motionEvent = Remotes.event("SnatcherMotion")
	Players.PlayerRemoving:Connect(function(player)
		fieldWaves[player], nextCast[player], lastKind[player] = nil, nil, nil
		chaseSince[player] = nil
		groups[player] = nil
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
	local relayElapsed, motionElapsed, attackElapsed, guardElapsed = 0, 0, 0, 0
	RunService.Heartbeat:Connect(function(dt)
		local began = os.clock()
		local stepTime = math.min(dt, Config.MAX_FRAME_DT)
		for player, group in groups do
			local root = rootOf(player)
			if root then
				group.heading = ChasePlan.heading(
					group.heading,
					root.AssemblyLinearVelocity,
					root.CFrame.LookVector,
					stepTime,
					Config.HEADING_TURN_RATE,
					Config.HEADING_MIN_SPEED
				)
			end
		end
		guardElapsed += dt
		local guardDt: number? = nil
		if guardElapsed >= Config.SERVER_TICK then
			guardDt = math.min(guardElapsed, Config.MAX_FRAME_DT)
			guardElapsed = 0
		end
		step(stepTime, guardDt)
		attackElapsed += dt
		if attackElapsed >= Config.SERVER_TICK then
			attackElapsed %= Config.SERVER_TICK
			stepAttacks(Players:GetPlayers())
		end
		relayElapsed += dt
		if relayElapsed >= Config.RELAY_TICK then
			relayElapsed %= Config.RELAY_TICK
			stepRelay(os.clock())
		end
		motionElapsed += dt
		local regularMotion = motionElapsed >= Config.MOTION_TICK
		if next(motionDirty) ~= nil or regularMotion then
			if regularMotion then
				motionElapsed %= Config.MOTION_TICK
			end
			local batch = {}
			local now = workspace:GetServerTimeNow()
			for _, drone in drones do
				if not regularMotion and not motionDirty[drone.id] then
					continue
				end
				drone.root.CFrame = drone.visualCF
				local timed = drone.phase == "lock" or drone.phase == "dash"
				local dashCF = CFrame.lookAt(drone.origin, drone.origin + drone.direction)
					* drone.offset
				table.insert(batch, {
					id = drone.id,
					cf = drone.visualCF,
					time = now,
					phase = drone.phase,
					dashOrigin = if timed then dashCF.Position else nil,
					dashEnd = if timed
						then dashCF.Position + drone.endpoint - drone.origin
						else nil,
					dashStart = if timed then drone.dashStart else nil,
					dashSpeed = if timed then drone.dashSpeed else nil,
				})
			end
			for _, player in Players:GetPlayers() do
				local root = rootOf(player)
				if root then
					local nearby = {}
					for _, snapshot in batch do
						local delta = snapshot.cf.Position - root.Position
						if delta:Dot(delta) <= Config.MOTION_REACH * Config.MOTION_REACH then
							table.insert(nearby, snapshot)
						end
					end
					if #nearby > 0 then
						motionEvent:FireClient(player, nearby)
					end
				end
			end
			table.clear(motionDirty)
		end
		local cpu = os.clock() - began
		metrics.frames += 1
		metrics.seconds += dt
		metrics.cpu += cpu
		metrics.maxCPU = math.max(metrics.maxCPU, cpu)
		metrics.maxFrame = math.max(metrics.maxFrame, dt)
	end)
end
return Service

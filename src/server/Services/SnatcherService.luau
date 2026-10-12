--!strict
-- Field eggs have visible guards before pickup. Contact is harmless except
-- during a warned, locked dash. The server owns all movement and hit checks.
-- From the Void Hound zone a guard tears open a portal on pickup and a hound
-- leaps out to chase on foot, pouncing with the same telegraph.
-- Each body is one welded assembly moved by its anchored root, so a drone
-- replicates a single CFrame instead of one per part.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config.Snatchers)
local Combat = require(Shared.Util.SnatcherCombat)
local Notifier = require(script.Parent.Parent.Util.Notifier)
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
	zone: number,
	meteor: BasePart?,
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
}
local Service = {}
local drones: { Drone } = {}
local guards: { [BasePart]: { Drone } } = {}
local folder: Folder
local rayParams = RaycastParams.new()
local rng = Random.new()

local FLOOR_TOP = 0.2

local function rootOf(player: Player): BasePart?
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return nil
	end
	return character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
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

local function state(drone: Drone, phase: string)
	drone.phase = phase
	drone.model:SetAttribute("State", phase)
	local color = if phase == "warning"
		then Color3.fromRGB(255, 205, 65)
		elseif phase == "dash" then Color3.fromRGB(255, 65, 90)
		elseif phase == "guard" then Color3.fromRGB(120, 225, 255)
		else Color3.fromRGB(190, 145, 255)
	drone.label.Text = if phase == "warning"
		then "DODGE!"
		elseif phase == "dash" then "ATTACK"
		elseif phase == "guard" then "EGG GUARD"
		elseif phase == "recover" then "RECHARGING"
		else "CHASING"
	drone.label.TextColor3 = color
	for _, part in drone.model:GetDescendants() do
		if part:IsA("BasePart") and (part.Name == "Eye" or part.Name == "Ring") then
			part.Color = color
		end
	end
	drone.line.Transparency = if phase == "warning" then 0.25 elseif phase == "dash" then 0.05 else 1
	drone.line.Color = color
end

local function spawn(kind: string, zone: number, position: Vector3, meteor: BasePart?): Drone?
	if #drones >= Config.MAX_ACTIVE then
		return nil
	end
	local model = buildModel(kind)
	model.Name = if kind == "hound" then "VoidHound" else "Snatcher"
	local root, offset = assemble(model)
	if not root then
		model:Destroy()
		return nil
	end
	local hover = Config.HOVER_HEIGHT
	if kind == "hound" then
		local _, size = model:GetBoundingBox()
		hover = FLOOR_TOP + size.Y / 2
	end
	position = Vector3.new(position.X, hover, position.Z)
	local gui = Instance.new("BillboardGui")
	gui.Name, gui.Adornee, gui.Size, gui.StudsOffset =
		"GuardStatus", root, UDim2.fromOffset(150, 30), Vector3.new(0, 3.5, 0)
	gui.MaxDistance = 100
	local label = Instance.new("TextLabel")
	label.Size, label.BackgroundTransparency, label.TextScaled = UDim2.fromScale(1, 1), 1, true
	label.Font, label.TextStrokeTransparency = Enum.Font.FredokaOne, 0.2
	label.Parent, gui.Parent = gui, root
	local line = Instance.new("Part")
	line.Name, line.Anchored, line.CanCollide, line.CanQuery, line.CanTouch =
		"AttackWarning", true, false, false, false
	line.Material, line.Transparency, line.CastShadow = Enum.Material.Neon, 1, false
	line.Parent = folder
	local drone: Drone = {
		kind = kind,
		model = model,
		root = root,
		offset = offset,
		hover = hover,
		label = label,
		line = line,
		zone = zone,
		meteor = meteor,
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
	}
	model:SetAttribute("ZoneIndex", zone)
	model:SetAttribute("Kind", kind)
	place(drone, CFrame.new(position))
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
			+ Vector3.new(math.cos(angle), 0, math.sin(angle)) * Config.PATROL_RADIUS
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

-- Transfer the guards of this exact egg before its Instance is destroyed.
function Service.onPickup(player: Player, zone: number, rarity: string, meteor: BasePart)
	if zone < Config.FROM_ZONE then
		return
	end
	local root = rootOf(player)
	if not root then
		return
	end
	-- Recovering a dropped egg cannot accumulate chasers for the same player.
	for index = #drones, 1, -1 do
		if drones[index].target == player then
			despawn(index)
		end
	end
	local profile = DataService.get(player)
	local factor = Config.SPEED_FACTOR
	local count = (Config.COUNT_BY_ZONE[zone] or 1) + (Config.EXTRA_BY_RARITY[rarity] or 0)
	count = math.min(count, Config.MAX_CHASERS_PER_PLAYER)
	local hound = zone >= Config.HOUND_FROM_ZONE
	if zone == 1 then
		count = 1
		factor = Config.FIRST_TIME_FACTOR
	end
	if profile and not profile.flags.snatcherIntro then
		profile.flags.snatcherIntro = true
		count = 1
		factor = Config.FIRST_TIME_FACTOR
		hound = false
	end
	local guardList = table.clone(guards[meteor] or {})
	local activated: { Drone } = {}
	for index = 1, count do
		local drone = guardList[index]
		if not drone then
			local offset = Vector3.new(if index % 2 == 0 then -9 else 9, 0, 10 + (index - 1) * 3)
			drone = spawn("drone", zone, root.Position + offset, nil)
		end
		if drone then
			activate(drone, player, factor, (index - 1) * 0.4)
			table.insert(activated, drone)
		end
	end
	-- Guards beyond the chaser count leave with the egg.
	for index = count + 1, #guardList do
		local position = table.find(drones, guardList[index] :: Drone)
		if position then
			despawn(position)
		end
	end
	if hound and activated[1] then
		summonHound(activated[1], player, zone)
	end
	if #activated > 0 then
		Notifier.send(
			player,
			if hound then "hound_summoned" else "snatcher_chasing",
			nil,
			"warning"
		)
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

local function patrol(drone: Drone, now: number, players: { Vector3 })
	local meteor = drone.meteor
	if not meteor or not anyPlayerNear(meteor.Position, players) then
		return -- nobody can see it: skip the replicated move
	end
	local angle = now * 0.35 + drone.orbit
	local home = Vector3.new(meteor.Position.X, drone.hover, meteor.Position.Z)
	local offset = Vector3.new(math.cos(angle), 0, math.sin(angle)) * Config.PATROL_RADIUS
	local safe = blockedMove(home, offset)
	drone.position = home + safe
	local facing = home - drone.position
	if facing.Magnitude < 0.01 then
		facing = Vector3.new(0, 0, 1)
	end
	local bobbed = drone.position + Vector3.new(0, math.sin(now * 3 + drone.orbit) * 0.25, 0)
	place(drone, CFrame.lookAt(bobbed, bobbed + facing))
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

local function step(dt: number)
	local now = os.clock()
	local players: { Vector3 } = {}
	for _, player in Players:GetPlayers() do
		local root = rootOf(player)
		if root then
			table.insert(players, root.Position)
		end
	end
	for index = #drones, 1, -1 do
		local drone = drones[index]
		local player = drone.target
		if not player then
			if not drone.meteor or not drone.meteor.Parent then
				despawn(index)
			else
				patrol(drone, now, players)
			end
			continue
		end
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
			continue
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
			local speed = if drone.zone == 1
				then Config.FIRST_ZONE_DASH_SPEED
				else Config.DASH_SPEED
			local remaining = (drone.endpoint - drone.position).Magnitude
			local from = drone.position
			local move = blockedMove(from, drone.direction * math.min(speed * dt, remaining))
			drone.position += move
			if
				math.abs(root.Position.Y - drone.hover) < 6
				and Combat.hits(from, drone.position, drone.previousTarget, root.Position)
				and not workspace:Raycast(drone.position, root.Position - drone.position, rayParams)
			then
				CarryService.drop(player, root.Position)
				Notifier.send(player, "snatcher_grabbed", nil, "warning")
				Telemetry.custom(
					player,
					if drone.kind == "hound" then "HoundCaught" else "SnatcherCaught"
				)
				despawn(index)
				continue
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
		facing = Vector3.new(facing.X, 0, facing.Z)
		if facing.Magnitude < 0.01 then
			facing = Vector3.new(0, 0, 1)
		end
		-- Drones bob gently; hounds bound low and quick.
		local bob = if drone.kind == "hound"
			then math.abs(math.sin(now * 9 + drone.orbit)) * 0.5
			else math.sin(now * 3 + drone.orbit) * 0.25
		local pos = drone.position + Vector3.new(0, bob, 0)
		place(drone, CFrame.lookAt(pos, pos + facing))
	end
end

function Service.init()
	folder = Instance.new("Folder")
	folder.Name, folder.Parent = "Snatchers", workspace
	rayParams.FilterType = Enum.RaycastFilterType.Include
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

--!strict
-- Guards' vision as a film-style laser scanner, drawn locally from each
-- guard's pivot (the server only replicates the drone's CFrame and
-- State/Spotting attributes):
-- * a scan fan: a thin vertical sheet of light from the drone's eye down to a
--   laser line on the ground, sweeping across the vision sector;
-- * two faint rays from the eye to the ends of the sector's far edge;
--   the scan line is a near-white core inside a soft halo;
-- * barely-there haze in the sector and a faint ground fill of the sector and
--   of the hearing circle, so the zone still reads at a glance.
-- Blue while patrolling, red while a carrier is seen, yellow while searching;
-- hidden during a chase and the Void Run. Beams are GPU-cheap: per frame only
-- attachment positions move, colours change only when the state does.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config.Snatchers)

local player = Players.LocalPlayer

local DRAW_DISTANCE = 260
local SLICES = 6
local GROUND_Y = 0.3
local THICKNESS = 0.06
local SWEEP_PERIOD = 2.4 -- seconds for the scan fan to cross the sector and back
local SWEEP_PERIOD_SPOTTING = 0.9
local CORE_WIDTH = 0.07
local HALO_WIDTH = 0.45
local CORE_WHITENESS = 0.6 -- how far a laser's core is lifted toward white
local COLORS = {
	patrol = Color3.fromRGB(70, 170, 255),
	spotting = Color3.fromRGB(255, 40, 55),
	search = Color3.fromRGB(255, 190, 50),
}
local WHITE = Color3.new(1, 1, 1)
-- Haze: a whisper near the eye, gone by the ground.
local HAZE_TRANSPARENCY = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 0.9),
	NumberSequenceKeypoint.new(0.5, 0.97),
	NumberSequenceKeypoint.new(1, 1),
})
-- Scan fan: brightest along the drone's vertical, fading toward the far edge.
local FAN_TRANSPARENCY = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 0.72),
	NumberSequenceKeypoint.new(0.7, 0.9),
	NumberSequenceKeypoint.new(1, 1),
})
-- Rays from the eye: visible near the lens, dissolving into the haze.
local RAY_TRANSPARENCY = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 0.35),
	NumberSequenceKeypoint.new(1, 0.85),
})
local CORE_TRANSPARENCY = NumberSequence.new(0.1)
local HALO_TRANSPARENCY = NumberSequence.new(0.9)

type View = {
	wedges: { WedgePart },
	ring: Part,
	eye: Attachment,
	edge: { Attachment }, -- SLICES + 1 points along the far arc
	mids: { Attachment }, -- slice midpoints on the arc (haze ends)
	scanNear: Attachment, -- ground point under the eye
	scanFar: Attachment, -- the scan line's end on the far arc
	tinted: { Beam }, -- beams in the state colour
	cores: { Beam }, -- laser cores in the whitened state colour
	fan: Beam,
	sweep: number, -- scan phase, advanced each frame
	color: Color3?,
}

local GuardVisionController = {}

local views: { [Model]: View } = {}
local folder: Folder

local function newWedge(): WedgePart
	local wedge = Instance.new("WedgePart")
	wedge.Anchored, wedge.CanCollide, wedge.CanQuery, wedge.CanTouch = true, false, false, false
	wedge.Material = Enum.Material.Neon
	wedge.CastShadow = false
	wedge.Transparency = 0.94
	wedge.Parent = folder
	return wedge
end

local function groundAttachment(): Attachment
	local attachment = Instance.new("Attachment")
	attachment.Parent = workspace.Terrain
	return attachment
end

local function newBeam(a0: Attachment, a1: Attachment, width0: number, width1: number): Beam
	local beam = Instance.new("Beam")
	beam.Attachment0, beam.Attachment1 = a0, a1
	beam.Width0, beam.Width1 = width0, width1
	beam.FaceCamera = true
	beam.LightEmission = 1
	beam.LightInfluence = 0
	beam.Segments = 1
	beam.Parent = folder
	return beam
end

-- A laser from a0 to a1: a thin near-white core inside a soft coloured halo.
local function newLaser(view: View, a0: Attachment, a1: Attachment)
	local halo = newBeam(a0, a1, HALO_WIDTH, HALO_WIDTH)
	halo.Transparency = HALO_TRANSPARENCY
	table.insert(view.tinted, halo)
	local core = newBeam(a0, a1, CORE_WIDTH, CORE_WIDTH)
	core.Transparency = CORE_TRANSPARENCY
	table.insert(view.cores, core)
end

local function newView(root: BasePart): View
	local wedges = {}
	for _ = 1, SLICES * 2 do
		table.insert(wedges, newWedge())
	end
	local ring = Instance.new("Part")
	ring.Shape = Enum.PartType.Cylinder
	ring.Anchored, ring.CanCollide, ring.CanQuery, ring.CanTouch = true, false, false, false
	ring.Material = Enum.Material.Neon
	ring.CastShadow = false
	ring.Transparency = 0.95
	ring.Size = Vector3.new(THICKNESS, Config.HEARING_RADIUS * 2, Config.HEARING_RADIUS * 2)
	ring.Parent = folder
	-- The eye rides on the drone's replicated root, so it follows for free.
	local eye = Instance.new("Attachment")
	eye.Name = "VisionEye"
	eye.Parent = root
	local edge, mids = {}, {}
	for _ = 0, SLICES do
		table.insert(edge, groundAttachment())
	end
	local scanNear, scanFar = groundAttachment(), groundAttachment()
	-- The fan runs along the ground from under the eye to the far arc and is
	-- as tall as the eye at its near end: its upper half is the lit sheet,
	-- the mirrored lower half is hidden by the floor. Fixed (not camera-facing)
	-- with world-up attachments, so it stays a true vertical plane.
	local fan = newBeam(scanNear, scanFar, 0, 0)
	fan.FaceCamera = false
	fan.Transparency = FAN_TRANSPARENCY
	local view: View = {
		wedges = wedges,
		ring = ring,
		eye = eye,
		edge = edge,
		mids = mids,
		scanNear = scanNear,
		scanFar = scanFar,
		tinted = { fan },
		cores = {},
		fan = fan,
		sweep = math.random() * math.pi * 2,
	}
	local chord = 2 * Config.VISION_RANGE * math.sin(Config.VISION_HALF_ANGLE / SLICES)
	for _ = 1, SLICES do
		local mid = groundAttachment()
		table.insert(mids, mid)
		local haze = newBeam(eye, mid, 0.2, chord * 1.05)
		haze.Transparency = HAZE_TRANSPARENCY
		table.insert(view.tinted, haze)
	end
	newLaser(view, scanNear, scanFar)
	for _, index in { 1, SLICES + 1 } do
		local ray = newBeam(eye, edge[index], CORE_WIDTH, CORE_WIDTH)
		ray.Transparency = RAY_TRANSPARENCY
		table.insert(view.cores, ray)
	end
	return view
end

-- Flat triangle a-b-c from two wedges (the classic two-WedgePart method).
local function triangle(a: Vector3, b: Vector3, c: Vector3, w1: WedgePart, w2: WedgePart)
	local ab, ac, bc = b - a, c - a, c - b
	local abd, acd, bcd = ab:Dot(ab), ac:Dot(ac), bc:Dot(bc)
	if abd > acd and abd > bcd then
		c, a = a, c
	elseif acd > bcd and acd > abd then
		a, b = b, a
	end
	ab, ac, bc = b - a, c - a, c - b
	local right = ac:Cross(ab).Unit
	local up = bc:Cross(right).Unit
	local back = bc.Unit
	local height = math.abs(ab:Dot(up))
	w1.Size = Vector3.new(THICKNESS, height, math.abs(ab:Dot(back)))
	w1.CFrame = CFrame.fromMatrix((a + b) / 2, right, up, back)
	w2.Size = Vector3.new(THICKNESS, height, math.abs(ac:Dot(back)))
	w2.CFrame = CFrame.fromMatrix((a + c) / 2, -right, up, -back)
end

local function draw(view: View, pivot: CFrame, color: Color3, period: number, dt: number)
	local look = Vector3.new(pivot.LookVector.X, 0, pivot.LookVector.Z).Unit
	local origin = Vector3.new(pivot.Position.X, GROUND_Y, pivot.Position.Z)
	local yaw = math.atan2(look.Z, look.X)
	local half = Config.VISION_HALF_ANGLE
	local range = Config.VISION_RANGE
	local function arc(angle: number): Vector3
		return origin + Vector3.new(math.cos(angle), 0, math.sin(angle)) * range
	end
	for i = 0, SLICES do
		view.edge[i + 1].WorldPosition = arc(yaw - half + i * 2 * half / SLICES)
	end
	for i = 1, SLICES do
		local a0 = yaw - half + (i - 1) * 2 * half / SLICES
		local a1 = yaw - half + i * 2 * half / SLICES
		view.mids[i].WorldPosition = arc((a0 + a1) / 2)
		triangle(
			origin,
			view.edge[i].WorldPosition,
			view.edge[i + 1].WorldPosition,
			view.wedges[i * 2 - 1],
			view.wedges[i * 2]
		)
	end
	-- Sine sweep: the fan lingers at the sector's edges like a real scanner.
	view.sweep += dt * 2 * math.pi / period
	local scan = yaw + half * 0.97 * math.sin(view.sweep)
	view.scanNear.WorldCFrame = CFrame.new(origin)
	view.scanFar.WorldCFrame = CFrame.new(arc(scan))
	view.fan.Width0 = math.max(pivot.Position.Y - GROUND_Y, 0) * 2
	view.ring.CFrame = CFrame.new(origin) * CFrame.Angles(0, 0, math.rad(90))
	if view.color ~= color then
		view.color = color
		local tint = ColorSequence.new(color)
		for _, beam in view.tinted do
			beam.Color = tint
		end
		local core = ColorSequence.new(color:Lerp(WHITE, CORE_WHITENESS))
		for _, beam in view.cores do
			beam.Color = core
		end
		for _, wedge in view.wedges do
			wedge.Color = color
		end
		view.ring.Color = color
	end
end

local function destroy(view: View)
	for _, wedge in view.wedges do
		wedge:Destroy()
	end
	for _, beam in view.tinted do
		beam:Destroy()
	end
	for _, beam in view.cores do
		beam:Destroy()
	end
	for _, attachment in view.edge do
		attachment:Destroy()
	end
	for _, attachment in view.mids do
		attachment:Destroy()
	end
	view.scanNear:Destroy()
	view.scanFar:Destroy()
	view.eye:Destroy()
	view.ring:Destroy()
end

local function update(dt: number)
	local camera = workspace.CurrentCamera
	local snatchers = workspace:FindFirstChild("Snatchers")
	local seen: { [Model]: boolean } = {}
	local inRun = player:GetAttribute("ArenaActive") == true
		or player:GetAttribute("ArenaPrep") == true
	if snatchers and camera and not inRun then
		local eye = camera.CFrame.Position
		for _, model in snatchers:GetChildren() do
			if not model:IsA("Model") or model:GetAttribute("Kind") ~= "drone" then
				continue
			end
			local phase = model:GetAttribute("State")
			if phase ~= "guard" and phase ~= "alert" then
				continue
			end
			local root = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart")
			if not root then
				continue
			end
			local pivot = model:GetPivot()
			if (pivot.Position - eye).Magnitude > DRAW_DISTANCE then
				continue
			end
			local look = Vector3.new(pivot.LookVector.X, 0, pivot.LookVector.Z)
			if look.Magnitude < 1e-3 then
				continue
			end
			seen[model] = true
			local existing: View? = views[model]
			if existing and not existing.eye.Parent then
				destroy(existing)
				existing = nil
			end
			local view: View = existing or newView(root)
			views[model] = view
			local spotting = model:GetAttribute("Spotting") == true
			draw(
				view,
				pivot,
				if spotting
					then COLORS.spotting
					elseif phase == "alert" then COLORS.search
					else COLORS.patrol,
				if spotting then SWEEP_PERIOD_SPOTTING else SWEEP_PERIOD,
				dt
			)
		end
	end
	for model, view in views do
		if not seen[model] then
			destroy(view)
			views[model] = nil
		end
	end
end

function GuardVisionController.start()
	folder = Instance.new("Folder")
	folder.Name = "LocalGuardVision"
	folder.Parent = workspace
	RunService.RenderStepped:Connect(update)
end

return GuardVisionController

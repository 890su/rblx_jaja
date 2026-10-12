--!strict
-- Void Run view, plus the ground attacks guards cast during an ordinary chase
-- (same wave format, drawn with the normal camera). The camera rises smoothly to a top-down shot that fits the
-- runner's lane across the screen and follows them toward home. Attack waves
-- arrive from the server and are drawn with the same pattern math the server
-- uses for hit checks.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Arena = require(Shared.Config.Arena)
local Patterns = require(Shared.Util.ArenaPatterns)
local Remotes = require(Shared.Remotes)
local Locale = require(Shared.Locale)
local UiKit = require(script.Parent.Parent.Lib.UiKit)
local player = Players.LocalPlayer

type SavedView = {
	camera: Camera,
	cameraType: Enum.CameraType,
	fieldOfView: number,
	subject: Instance?,
	guis: { [ScreenGui]: boolean },
}

local HALF = Arena.LANE_WIDTH / 2 - Arena.EDGE_MARGIN
local COLORS: { [string]: Color3 } = {
	white = Color3.fromRGB(255, 236, 242),
	blue = Color3.fromRGB(70, 170, 255),
	orange = Color3.fromRGB(255, 150, 40),
	warning = Color3.fromRGB(255, 210, 70),
}

local ArenaController = {}
local saved: SavedView? = nil
local mode = "off" -- "off" | "rise" | "run" | "fall"
local modeStarted = 0
local fromCFrame = CFrame.new()
local fromFov = 70
local folder: Folder? = nil
local fieldFolder: Folder? = nil -- ground attacks outside the Void Run
local parts: { [string]: Part } = {}
local emitters: { [string]: Model } = {}
local waves: { Patterns.Wave } = {}
local arenaGui: ScreenGui
local status: TextLabel
local hint: TextLabel
local progress: Frame
local hitFlash: Frame
local playerHighlight: Highlight? = nil
local previousImmune = 0
local hidden: { [Instance]: boolean } = {} -- field clutter hidden during a run
local nextSweep = 0

local function smooth(t: number): number
	t = math.clamp(t, 0, 1)
	return t * t * (3 - 2 * t)
end

local function visual(name: string, parent: Instance): Part
	local p = Instance.new("Part")
	p.Name, p.Anchored, p.CanCollide, p.CanTouch, p.CanQuery = name, true, false, false, false
	p.Material = Enum.Material.Neon
	p.CastShadow = false
	p.Parent = parent
	return p
end

-- Zone eggs and their patrolling guards share the corridor; hide them for
-- the runner only (local, never replicated) so every visible shape is an attack.
local function hideClutter()
	local function hide(root: Instance)
		for _, item in root:GetDescendants() do
			if not hidden[item] then
				if item:IsA("BasePart") then
					item.LocalTransparencyModifier = 1
					hidden[item] = true
				elseif item:IsA("BillboardGui") and item.Enabled then
					item.Enabled = false
					hidden[item] = true
				end
			end
		end
	end
	local meteors = workspace:FindFirstChild("Meteors")
	if meteors then
		hide(meteors)
	end
	local snatchers = workspace:FindFirstChild("Snatchers")
	if snatchers then
		for _, model in snatchers:GetChildren() do
			if model:IsA("Model") and model:GetAttribute("TargetUserId") == nil then
				hide(model)
			end
		end
	end
end

local function showClutter()
	for item in hidden do
		if item.Parent then
			if item:IsA("BasePart") then
				item.LocalTransparencyModifier = 0
			elseif item:IsA("BillboardGui") then
				item.Enabled = true
			end
		end
	end
	hidden = {}
end

local function clearVisuals()
	if folder then
		folder:Destroy()
	end
	if fieldFolder then
		fieldFolder:Destroy()
		fieldFolder = nil
	end
	folder, playerHighlight = nil, nil
	parts, emitters, waves = {}, {}, {}
	showClutter()
end

local function rootPart(): BasePart?
	local character = player.Character
	return character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
end

-- Top-down shot over the lane: the lane width fits the screen, home is up.
local function overheadCFrame(camera: Camera, laneX: number, focusZ: number): CFrame
	local viewport = camera.ViewportSize
	local aspect = math.max(0.3, viewport.X / math.max(1, viewport.Y))
	local tanHalf = math.tan(math.rad(Arena.CAMERA_FOV / 2))
	local height = (Arena.VIEW_WIDTH / 2) / (tanHalf * aspect)
	return CFrame.lookAt(
		Vector3.new(laneX, height, focusZ),
		Vector3.new(laneX, 0, focusZ),
		Vector3.new(0, 0, 1)
	)
end

local function finishRestore()
	local view = saved
	saved = nil
	mode = "off"
	if not view then
		return
	end
	local camera = view.camera
	camera.FieldOfView = view.fieldOfView
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	camera.CameraSubject = if view.subject and view.subject.Parent then view.subject else humanoid
	-- The default camera cannot start from a straight-down view (its pitch
	-- clamp errors), e.g. after dying mid-run: tilt it behind the body first.
	if math.abs(camera.CFrame.LookVector.Y) > 0.95 then
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		local at = if root then root.Position else camera.Focus.Position
		camera.CFrame = CFrame.lookAt(at + Vector3.new(0, 9, -16), at + Vector3.new(0, 2, 0))
	end
	camera.CameraType = view.cameraType
	for gui, enabled in view.guis do
		if gui.Parent then
			gui.Enabled = enabled
		end
	end
end

local function exit()
	clearVisuals()
	arenaGui.Enabled = false
	if not saved then
		return
	end
	local camera = saved.camera
	if not rootPart() then
		finishRestore()
		return
	end
	mode, modeStarted = "fall", os.clock()
	fromCFrame, fromFov = camera.CFrame, camera.FieldOfView
end

local function enter()
	if mode == "rise" or mode == "run" then
		return
	end
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	clearVisuals()
	if not saved then
		local guis: { [ScreenGui]: boolean } = {}
		for _, name in { "MainUi", "Hud" } do
			local gui = player.PlayerGui:FindFirstChild(name)
			if gui and gui:IsA("ScreenGui") then
				guis[gui] = gui.Enabled
				gui.Enabled = false
			end
		end
		saved = {
			camera = camera,
			cameraType = camera.CameraType,
			fieldOfView = camera.FieldOfView,
			subject = camera.CameraSubject,
			guis = guis,
		}
	end
	fromCFrame, fromFov = camera.CFrame, camera.FieldOfView
	camera.CameraType = Enum.CameraType.Scriptable
	mode, modeStarted = "rise", os.clock()
	local world = Instance.new("Folder")
	world.Name = "LocalVoidRun"
	world.Parent = workspace
	folder = world
	previousImmune = 0
	hint.Text = Locale.term("Dodge the attacks! Yellow marks warn you.")
	arenaGui.Enabled = true
	-- Soft lane walls for smooth movement; the server clamps independently.
	local laneX = (player:GetAttribute("ArenaLaneX") :: number?) or 0
	local zMin = (player:GetAttribute("ArenaZMin") :: number?) or -500
	local zMax = (player:GetAttribute("ArenaZMax") :: number?) or 0
	for side = -1, 1, 2 do
		local wall = visual("LaneWall", world)
		wall.Transparency, wall.CanCollide = 1, true
		-- Walls start before the staging strip so the lane is locked early.
		local from, to = zMin - Arena.PREP_DEPTH - 12, zMax + 20
		wall.Size = Vector3.new(1, 16, to - from)
		-- Inner face at HALF + 1: the body (about 1 stud wide) stops near HALF.
		wall.Position = Vector3.new(laneX + side * (HALF + 1.5), 7, (from + to) / 2)
		local glow = visual("LaneGlow", world)
		glow.Color, glow.Transparency = Color3.fromRGB(150, 120, 255), 0.2
		local glowFrom = zMin - Arena.PREP_DEPTH
		glow.Size = Vector3.new(0.5, 0.2, zMax - glowFrom)
		glow.Position = Vector3.new(laneX + side * (HALF + 1), 0.4, (zMax + glowFrom) / 2)
	end
	local character = player.Character
	if character then
		local highlight = Instance.new("Highlight")
		highlight.Adornee, highlight.FillTransparency, highlight.OutlineColor =
			character, 1, Color3.fromRGB(100, 255, 175)
		highlight.Parent = world
		playerHighlight = highlight
	end
end

local function emitterFor(id: string, hazard: Patterns.Hazard, laneX: number, world: Instance)
	local model: Model? = emitters[id]
	if not model then
		local assets = ReplicatedStorage:FindFirstChild("Assets")
		local template = assets and assets:FindFirstChild("Snatcher")
		local created: Model
		if template and template:IsA("Model") then
			created = template:Clone()
		else
			created = Instance.new("Model")
			local p = visual("Drone", created)
			p.Shape, p.Size, p.Color =
				Enum.PartType.Ball, Vector3.one * 3.5, Color3.fromRGB(180, 60, 220)
		end
		for _, p in created:GetDescendants() do
			if p:IsA("BasePart") then
				p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch = true, false, false, false
			end
		end
		created.Parent = world
		emitters[id] = created
		model = created
	end
	local size = hazard.size or Vector2.one
	local at = if size.X > size.Y
		then Vector3.new(laneX - HALF - 5, 5, hazard.position.Y)
		else Vector3.new(hazard.position.X, 5, hazard.position.Y + size.Y / 2 + 3)
	local look = if size.X > size.Y then at + Vector3.new(1, 0, 0) else at - Vector3.new(0, 0, 1);
	(model :: Model):PivotTo(CFrame.lookAt(at, look))
end

local function drawHazards(now: number, world: Instance)
	local seen: { [string]: boolean } = {}
	local seenEmitters: { [string]: boolean } = {}
	local blueActive, orangeActive = false, false
	for index = #waves, 1, -1 do
		local wave = waves[index]
		if now > wave.t0 + Patterns.duration(wave) then
			table.remove(waves, index)
			continue
		end
		blueActive = blueActive or (wave.kind == "blue" and now >= wave.t0)
		orangeActive = orangeActive or (wave.kind == "orange" and now >= wave.t0)
		for _, hazard in Patterns.sample(wave, now) do
			local p = parts[hazard.id]
			if not p then
				p = visual(hazard.id, world)
				parts[hazard.id] = p
			end
			seen[hazard.id] = true
			local color = COLORS[hazard.color] or COLORS.white
			p.Color = if hazard.warning then COLORS.warning:Lerp(color, 0.25) else color
			p.Transparency = if hazard.warning then 0.35 + math.abs(math.sin(now * 9)) * 0.3 else 0
			local position = hazard.position
			if hazard.shape == "rect" then
				local size = hazard.size :: Vector2
				local height = if hazard.warning
					then 0.15
					elseif wave.kind == "blaster" then 1.2
					else 3
				p.Shape = Enum.PartType.Block
				p.Size = Vector3.new(size.X, height, size.Y)
				p.CFrame = CFrame.new(position.X, 0.5 + height / 2, position.Y)
				if wave.kind == "blaster" then
					seenEmitters[hazard.id] = true
					emitterFor(hazard.id, hazard, wave.laneX, world)
				end
			elseif hazard.shape == "capsule" then
				local finish = hazard.finish :: Vector2
				local mid = (position + finish) / 2
				local length = (finish - position).Magnitude + hazard.radius * 2
				p.Shape = Enum.PartType.Block
				p.Size =
					Vector3.new(hazard.radius * 2, if hazard.warning then 0.15 else 1.6, length)
				p.CFrame = CFrame.lookAt(
					Vector3.new(mid.X, 1.3, mid.Y),
					Vector3.new(finish.X, 1.3, finish.Y)
				)
			elseif wave.kind == "spears" then
				-- Telegraph: flat disc; strike: a tall spike out of the ground.
				p.Shape = Enum.PartType.Cylinder
				local height = if hazard.warning then 0.15 else 5
				p.Size = Vector3.new(height, hazard.radius * 2, hazard.radius * 2)
				p.CFrame = CFrame.new(position.X, 0.5 + height / 2, position.Y)
					* CFrame.Angles(0, 0, math.rad(90))
			else
				p.Shape = Enum.PartType.Ball
				p.Size = Vector3.one * hazard.radius * 2
				p.CFrame = CFrame.new(position.X, 1.6, position.Y)
			end
		end
	end
	for id, p in parts do
		if not seen[id] then
			p:Destroy()
			parts[id] = nil
		end
	end
	for id, model in emitters do
		if not seenEmitters[id] then
			model:Destroy()
			emitters[id] = nil
		end
	end
	hint.Text = if blueActive
		then Locale.term("BLUE: stand still!")
		elseif orangeActive then Locale.term("ORANGE: keep moving!")
		else Locale.term("Dodge the attacks! Yellow marks warn you.")
	hint.TextColor3 = if blueActive
		then COLORS.blue
		elseif orangeActive then COLORS.orange
		else Color3.fromRGB(255, 235, 180)
end

-- Guards' ground attacks during an ordinary chase: hazards only, no camera.
local function renderField()
	if #waves == 0 then
		if fieldFolder then
			drawHazards(workspace:GetServerTimeNow(), fieldFolder)
			fieldFolder:Destroy()
			fieldFolder = nil
			parts, emitters = {}, {}
		end
		return
	end
	if not fieldFolder then
		local created = Instance.new("Folder")
		created.Name = "LocalFieldAttacks"
		created.Parent = workspace
		fieldFolder = created
	end
	drawHazards(workspace:GetServerTimeNow(), fieldFolder :: Folder)
end

local function render(dt: number)
	if mode == "off" then
		renderField()
		return
	end
	local view = saved
	if not view then
		mode = "off"
		return
	end
	local camera = view.camera
	local root = rootPart()
	if mode == "fall" then
		if not root then
			finishRestore()
			return
		end
		local alpha = smooth((os.clock() - modeStarted) / Arena.CAMERA_FALL_SECONDS)
		local behind = CFrame.lookAt(
			root.Position + Vector3.new(0, 9, -16),
			root.Position + Vector3.new(0, 2, 0)
		)
		camera.CFrame = fromCFrame:Lerp(behind, alpha)
		camera.FieldOfView = fromFov + (view.fieldOfView - fromFov) * alpha
		if alpha >= 1 then
			finishRestore()
		end
		return
	end
	local world = folder
	if not root or not world then
		return
	end
	local laneX = (player:GetAttribute("ArenaLaneX") :: number?) or root.Position.X
	local zMin = (player:GetAttribute("ArenaZMin") :: number?) or -500
	local zMax = (player:GetAttribute("ArenaZMax") :: number?) or 0
	local target = overheadCFrame(camera, laneX, root.Position.Z + Arena.CAMERA_LEAD)
	if mode == "rise" then
		local alpha = smooth((os.clock() - modeStarted) / Arena.CAMERA_RISE_SECONDS)
		camera.CFrame = fromCFrame:Lerp(target, alpha)
		camera.FieldOfView = fromFov + (Arena.CAMERA_FOV - fromFov) * alpha
		if alpha >= 1 then
			mode = "run"
		end
	else
		camera.CFrame = camera.CFrame:Lerp(target, 1 - math.exp(-dt * 10))
		camera.FieldOfView = Arena.CAMERA_FOV
	end
	camera.Focus = CFrame.new(root.Position)

	local now = workspace:GetServerTimeNow()
	if os.clock() >= nextSweep then
		nextSweep = os.clock() + 0.5
		hideClutter()
	end
	drawHazards(now, world)

	local lives = (player:GetAttribute("ArenaLives") :: number?) or Arena.LIVES
	if player:GetAttribute("ArenaActive") == true then
		status.Text = Locale.t("arena_status", {
			hearts = string.rep("♥", math.max(0, lives))
				.. string.rep("♡", math.max(0, Arena.LIVES - lives)),
			meters = math.max(0, math.floor(zMax - root.Position.Z)),
		})
	else
		-- Staging strip: nothing attacks yet.
		status.Text = Locale.t("arena_prep", {
			meters = math.max(0, math.floor(zMin - root.Position.Z)),
		})
		hint.Text = Locale.term("Stay in your lane. Attacks start at the orange line!")
	end
	progress.Size =
		UDim2.fromScale(math.clamp((root.Position.Z - zMin) / math.max(1, zMax - zMin), 0, 1), 1)
	local immune = (player:GetAttribute("ArenaIFramesUntil") :: number?) or 0
	if immune > previousImmune then
		previousImmune = immune
		hitFlash.BackgroundTransparency = 0.7
	end
	hitFlash.BackgroundTransparency = math.min(1, hitFlash.BackgroundTransparency + dt)
	if playerHighlight then
		playerHighlight.FillColor = Color3.fromRGB(255, 70, 90)
		playerHighlight.FillTransparency = if immune > now
			then 0.3 + math.abs(math.sin(now * 18)) * 0.65
			else 1
	end
end

function ArenaController.init()
	arenaGui = Instance.new("ScreenGui")
	arenaGui.Name, arenaGui.ResetOnSpawn, arenaGui.Enabled = "ArenaUi", false, false
	arenaGui.DisplayOrder, arenaGui.ZIndexBehavior = 30, Enum.ZIndexBehavior.Sibling
	arenaGui.IgnoreGuiInset = true
	status = UiKit.text(arenaGui, {
		Name = "Status",
		Position = UDim2.fromScale(0.2, 0.02),
		Size = UDim2.fromScale(0.6, 0.07),
		Text = "",
		TextColor3 = Color3.fromRGB(255, 120, 155),
		TextStrokeTransparency = 0.2,
	})
	hint = UiKit.text(arenaGui, {
		Name = "Hint",
		Position = UDim2.fromScale(0.13, 0.9),
		Size = UDim2.fromScale(0.74, 0.06),
		Text = "",
		TextColor3 = Color3.fromRGB(255, 235, 180),
		TextWrapped = true,
		TextStrokeTransparency = 0.15,
	})
	local track = Instance.new("Frame")
	track.Position, track.Size, track.BackgroundColor3 =
		UDim2.fromScale(0.25, 0.09), UDim2.fromScale(0.5, 0.012), Color3.fromRGB(35, 40, 55)
	track.Parent = arenaGui
	progress = Instance.new("Frame")
	progress.Size, progress.BackgroundColor3, progress.BorderSizePixel =
		UDim2.fromScale(0, 1), Color3.fromRGB(100, 240, 170), 0
	progress.Parent = track
	hitFlash = Instance.new("Frame")
	hitFlash.Size, hitFlash.BackgroundColor3, hitFlash.BackgroundTransparency, hitFlash.ZIndex =
		UDim2.fromScale(1, 1), Color3.fromRGB(255, 35, 65), 1, 10
	hitFlash.Parent = arenaGui
	arenaGui.Parent = player:WaitForChild("PlayerGui")
end

function ArenaController.start()
	Remotes.event("ArenaWave").OnClientEvent:Connect(function(wave: Patterns.Wave)
		if typeof(wave) == "table" and typeof(wave.kind) == "string" then
			table.insert(waves, wave)
		end
	end)
	-- Staging (ArenaPrep) and the run (ArenaActive) share one overhead view.
	-- The server flips one off right after the other on; a short grace keeps
	-- that hand-over from dropping and re-raising the camera.
	local function wanted(): boolean
		return player:GetAttribute("ArenaActive") == true
			or player:GetAttribute("ArenaPrep") == true
	end
	local function changed()
		if wanted() then
			enter()
		else
			task.delay(0.2, function()
				if not wanted() then
					exit()
				end
			end)
		end
	end
	player:GetAttributeChangedSignal("ArenaActive"):Connect(changed)
	player:GetAttributeChangedSignal("ArenaPrep"):Connect(changed)
	-- Losing the egg ends any ground attacks aimed at us.
	player:GetAttributeChangedSignal("Carrying"):Connect(function()
		if player:GetAttribute("Carrying") == nil and mode == "off" then
			waves = {}
		end
	end)
	player.CharacterRemoving:Connect(function()
		clearVisuals()
		arenaGui.Enabled = false
		finishRestore()
	end)
	RunService:BindToRenderStep("VoidRunCamera", Enum.RenderPriority.Camera.Value + 1, render)
end

return ArenaController

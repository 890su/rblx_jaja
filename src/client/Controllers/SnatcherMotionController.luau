--!strict
-- Restore the presentation pose immediately before rendering. The anchored
-- assembly, attachments, status GUI and replicated state all stay intact;
-- no visual duplicate or client-authoritative collision object is created.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared.Remotes)
local Pose = require(Shared.Util.SnatcherPose)
local Config = require(Shared.Config.Snatchers)

type Snapshot = Pose.Snapshot
type SamplePair = {
	previous: Snapshot?,
	current: Snapshot,
	transitionFrom: CFrame?,
	transitionAt: number?,
}
type View = {
	id: number?,
	root: BasePart?,
	offset: CFrame?,
	frames: number,
	connection: RBXScriptConnection,
}

local Controller = {}
local samples: { [number]: SamplePair } = {}
local views: { [Model]: View } = {}
local watchedFolder: Folder? = nil
local added: RBXScriptConnection? = nil
local removed: RBXScriptConnection? = nil
local started = false
local cleanupElapsed = 0
local STALE_SECONDS = Config.MOTION_STALE_SECONDS
local DRAW_DISTANCE_SQUARED = Config.MOTION_DRAW_DISTANCE * Config.MOTION_DRAW_DISTANCE

local function removeModel(child: Instance)
	if not child:IsA("Model") then
		return
	end
	local view = views[child]
	if view then
		view.connection:Disconnect()
		views[child] = nil
	end
end

local function addModel(child: Instance)
	if not child:IsA("Model") or views[child] then
		return
	end
	local view: View
	local function updateId()
		local id = child:GetAttribute("DroneId")
		view.id = if typeof(id) == "number" then id else nil
	end
	view = {
		id = nil,
		root = nil,
		offset = nil,
		frames = 0,
		connection = child:GetAttributeChangedSignal("DroneId"):Connect(updateId),
	}
	views[child] = view
	updateId()
end

local function watchFolder(child: Instance)
	if child.Name ~= "Snatchers" or not child:IsA("Folder") or child == watchedFolder then
		return
	end
	if added then
		added:Disconnect()
	end
	if removed then
		removed:Disconnect()
	end
	for model in views do
		removeModel(model)
	end
	watchedFolder = child
	added = child.ChildAdded:Connect(addModel)
	removed = child.ChildRemoved:Connect(removeModel)
	for _, model in child:GetChildren() do
		addModel(model)
	end
end

local function samplePair(pair: SamplePair, now: number): CFrame
	local target = Pose.sample(pair.previous, pair.current, now)
	if pair.transitionFrom and pair.transitionAt then
		return Pose.transition(pair.transitionFrom, target, now - pair.transitionAt)
	end
	return target
end

local function receive(batch: { Snapshot })
	local now = workspace:GetServerTimeNow()
	for _, incoming in batch do
		local existing = samples[incoming.id]
		if Pose.isNewer(if existing then existing.current else nil, incoming) then
			local transitionFrom: CFrame? = nil
			local transitionAt: number? = nil
			if existing then
				local previousPhase = existing.current.phase
				if
					(previousPhase == "chase" or previousPhase == "recover")
					and (incoming.phase == "warning" or incoming.phase == "cast")
				then
					transitionFrom, transitionAt = samplePair(existing, now), now
				elseif previousPhase == incoming.phase then
					transitionFrom, transitionAt = existing.transitionFrom, existing.transitionAt
				end
			end
			samples[incoming.id] = {
				previous = if existing then existing.current else nil,
				current = incoming,
				transitionFrom = transitionFrom,
				transitionAt = transitionAt,
			}
		end
	end
end

function Controller.getPivot(model: Model): CFrame
	local view = views[model]
	local pair = view and view.id and samples[view.id]
	if
		pair
		and view
		and view.offset
		and workspace:GetServerTimeNow() - pair.current.time < STALE_SECONDS
	then
		return samplePair(pair, workspace:GetServerTimeNow()) * view.offset:Inverse()
	end
	return model:GetPivot()
end

local function render(dt: number)
	local now = workspace:GetServerTimeNow()
	local camera = workspace.CurrentCamera
	for model, view in views do
		local pair = if view.id then samples[view.id] else nil
		if not pair or now - pair.current.time > STALE_SECONDS then
			continue
		end
		if camera then
			local delta = pair.current.cf.Position - camera.CFrame.Position
			if delta:Dot(delta) > DRAW_DISTANCE_SQUARED then
				continue
			end
		end
		-- Partial streaming may deliver welded body parts before the actual
		-- root. Never cache a secondary part as the presentation authority.
		local root = model.PrimaryPart
		if not root or not root.Anchored or not root:IsDescendantOf(model) then
			view.root, view.offset = nil, nil
			continue
		end
		if root ~= view.root then
			view.root = root
			view.offset = model:GetPivot():ToObjectSpace(root.CFrame)
		end
		if root then
			root.CFrame = samplePair(pair, now)
			view.frames += 1
			-- Snapshot cadence diagnostics are local; they never affect the server.
			if model:GetAttribute("MotionSourceTime") ~= pair.current.time then
				model:SetAttribute("MotionReady", true)
				model:SetAttribute("MotionSourceTime", pair.current.time)
				model:SetAttribute("MotionSourceCF", pair.current.cf)
				model:SetAttribute("MotionPhase", pair.current.phase)
				model:SetAttribute("MotionFrames", view.frames)
			end
		end
	end
	cleanupElapsed += dt
	if cleanupElapsed >= 1 then
		cleanupElapsed = 0
		for id, pair in samples do
			if now - pair.current.time > STALE_SECONDS then
				samples[id] = nil
			end
		end
	end
end

function Controller.start()
	if started then
		return
	end
	started = true
	Remotes.event("SnatcherMotion").OnClientEvent:Connect(receive)
	workspace.ChildAdded:Connect(watchFolder)
	local folder = workspace:FindFirstChild("Snatchers")
	if folder then
		watchFolder(folder)
	end
	RunService:BindToRenderStep("SnatcherMotion", Enum.RenderPriority.Camera.Value - 1, render)
end

return Controller

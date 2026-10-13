--!strict
-- Studio opt-in observations of the real per-frame drone renderer.
local RunService = game:GetService("RunService")
if not RunService:IsStudio() then
	return
end
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local remote = ReplicatedStorage:WaitForChild("ChaseQA", 30)
if not remote or not remote:IsA("RemoteEvent") then
	return
end
type Observation = {
	model: Model?,
	body: BasePart?,
	last: Vector3?,
	lastBody: Vector3?,
	firstFrames: number?,
	lastFrames: number,
	positions: number,
	dashPositions: number,
	bodyPositions: number,
	dashBodyPositions: number,
	ready: boolean,
}
remote.OnClientEvent:Connect(
	function(nonce: number, request: { mode: string, ids: { number }, duration: number })
		local observations: { [number]: Observation } = {}
		for _, id in request.ids do
			observations[id] = {
				model = nil,
				body = nil,
				last = nil,
				lastBody = nil,
				firstFrames = nil,
				lastFrames = 0,
				positions = 0,
				dashPositions = 0,
				bodyPositions = 0,
				dashBodyPositions = 0,
				ready = false,
			}
		end
		local renderFrames = 0
		local started = os.clock()
		local connection = RunService.PreRender:Connect(function()
			renderFrames += 1
			for _, observation in observations do
				local model = observation.model
				if not model or not model.Parent then
					continue
				end
				local root = model.PrimaryPart
				if not root then
					continue
				end
				observation.ready = observation.ready or model:GetAttribute("MotionReady") == true
				local frames = model:GetAttribute("MotionFrames")
				if typeof(frames) == "number" then
					observation.firstFrames = observation.firstFrames or frames
					observation.lastFrames = frames
				end
				local position = root.Position
				if not observation.last or (position - observation.last).Magnitude > 0.01 then
					observation.positions += 1
					if model:GetAttribute("State") == "dash" then
						observation.dashPositions += 1
					end
				end
				observation.last = position
				local body = observation.body
				if body and body.Parent then
					local bodyPosition = body.Position
					if
						not observation.lastBody
						or (bodyPosition - observation.lastBody).Magnitude > 0.01
					then
						observation.bodyPositions += 1
						if model:GetAttribute("State") == "dash" then
							observation.dashBodyPositions += 1
						end
					end
					observation.lastBody = bodyPosition
				end
			end
		end)
		-- Streaming may expose fixtures after the event; retry discovery outside the
		-- per-frame loop and never walk the whole world on every render frame.
		while os.clock() - started < request.duration do
			local folder = workspace:FindFirstChild("Snatchers")
			if folder then
				for _, instance in folder:GetChildren() do
					local id = instance:GetAttribute("DroneId")
					if instance:IsA("Model") and typeof(id) == "number" and observations[id] then
						local observation = observations[id]
						observation.model = instance
						if not observation.body then
							for _, descendant in instance:GetDescendants() do
								if
									descendant:IsA("BasePart")
									and descendant ~= instance.PrimaryPart
									and descendant.Name ~= "Indicator"
								then
									observation.body = descendant
									break
								end
							end
						end
					end
				end
			end
			task.wait(0.05)
		end
		connection:Disconnect()
		local ready = 0
		local minimumFrames = math.huge
		local movingPositions = 0
		local dashPositions = 0
		local bodyPositions = 0
		local dashBodyPositions = 0
		for _, observation in observations do
			if observation.ready then
				ready += 1
			end
			minimumFrames =
				math.min(minimumFrames, observation.lastFrames - (observation.firstFrames or 0))
			movingPositions = math.max(movingPositions, observation.positions)
			dashPositions = math.max(dashPositions, observation.dashPositions)
			bodyPositions = math.max(bodyPositions, observation.bodyPositions)
			dashBodyPositions = math.max(dashBodyPositions, observation.dashBodyPositions)
		end
		-- Judge continuity against frames actually rendered. Two Studio clients
		-- can be GPU/CPU limited; a fixed 60-FPS assumption masks the diagnosis.
		local success = ready == #request.ids
			and renderFrames >= 10
			and minimumFrames >= renderFrames * 0.65
			and (
				if request.mode == "dash"
					then dashPositions >= 2 and dashBodyPositions >= 2
					else movingPositions >= renderFrames * 0.7
						and bodyPositions >= renderFrames * 0.65
			)
		local status = if renderFrames < 10
			then "inconclusive_render_throttled"
			elseif success then "pass"
			else "fail"
		remote:FireServer(nonce, {
			ok = success,
			status = status,
			mode = request.mode,
			ready = ready,
			expected = #request.ids,
			renderFrames = renderFrames,
			motionFrames = minimumFrames,
			movingPositions = movingPositions,
			dashPositions = dashPositions,
			bodyPositions = bodyPositions,
			dashBodyPositions = dashBodyPositions,
			duration = os.clock() - started,
			fps = renderFrames / (os.clock() - started),
		})
	end
)

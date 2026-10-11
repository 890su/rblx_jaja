--!strict
-- Client-side effects (no gameplay): rarity sparkles on meteors (field and
-- carried), hatch / collect bursts, crate flash and Meteor Shower streaks.
-- Driven by streamed instances and the server "Fx" remote.

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Theme = require(Shared.Theme)
local Rarity = require(Shared.Config.Rarity)
local Remotes = require(Shared.Remotes)

local UiKit = require(script.Parent.Parent.Lib.UiKit)

local SPARKLE = "rbxasset://textures/particles/sparkles_main.dds"

local VfxController = {}

local function rarityColor(rarity: any): Color3
	return (Theme.RARITY_COLORS :: any)[rarity] or Color3.new(1, 1, 1)
end

local function rarityOrder(rarity: any): number
	local info = Rarity.INFO[rarity]
	return if info then info.order else 1
end

local function emitter(parent: Instance, color: Color3, rate: number, size: number): ParticleEmitter
	local e = Instance.new("ParticleEmitter")
	e.Texture = SPARKLE
	e.Color = ColorSequence.new(color)
	e.LightEmission = 1
	e.Rate = rate
	e.Lifetime = NumberRange.new(0.6, 1.2)
	e.Speed = NumberRange.new(1, 3)
	e.SpreadAngle = Vector2.new(180, 180)
	e.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, size),
		NumberSequenceKeypoint.new(1, 0),
	})
	e.Parent = parent
	return e
end

local function decorateMeteor(part: Instance)
	if not part:IsA("BasePart") or part:FindFirstChild("Sparkles") then
		return
	end
	local rarity = part:GetAttribute("Rarity")
	local order = rarityOrder(rarity)
	local e = emitter(part, rarityColor(rarity), 2 + order * 3, 0.4 + order * 0.08)
	e.Name = "Sparkles"
	if order >= 3 then
		local light = Instance.new("PointLight")
		light.Color = rarityColor(rarity)
		light.Brightness = order * 0.4
		light.Range = 8 + order * 2
		light.Parent = part
	end
end

local function burst(position: Vector3, color: Color3, count: number, size: number)
	local anchor = Instance.new("Part")
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.Transparency = 1
	anchor.Size = Vector3.one
	anchor.Position = position
	local e = emitter(anchor, color, 0, size)
	e.Speed = NumberRange.new(8, 16)
	e.Lifetime = NumberRange.new(0.5, 1)
	anchor.Parent = workspace
	e:Emit(count)
	Debris:AddItem(anchor, 2)
end

local function flash(color: Color3)
	local frame = Instance.new("Frame")
	frame.Size = UDim2.fromScale(1, 1)
	frame.BackgroundColor3 = color
	frame.BackgroundTransparency = 0.4
	frame.ZIndex = 20
	frame.Parent = UiKit.gui()
	local tween = TweenService:Create(frame, TweenInfo.new(0.6), { BackgroundTransparency = 1 })
	tween:Play()
	Debris:AddItem(frame, 0.7)
end

local function showerStreaks(duration: number)
	local endsAt = os.clock() + math.min(duration, 20)
	task.spawn(function()
		while os.clock() < endsAt do
			local camera = workspace.CurrentCamera
			if camera then
				local base = camera.CFrame.Position
				local start = base
					+ Vector3.new(math.random(-150, 150), 220, math.random(-150, 150))
				local finish = start
					+ Vector3.new(math.random(-60, 60), -260, math.random(-120, -40))
				local streak = Instance.new("Part")
				streak.Anchored = true
				streak.CanCollide = false
				streak.CanQuery = false
				streak.CanTouch = false
				streak.Material = Enum.Material.Neon
				streak.Color = Color3.fromRGB(255, 180, 90)
				streak.Shape = Enum.PartType.Ball
				streak.Size = Vector3.one * 2
				streak.Position = start
				local a0, a1 = Instance.new("Attachment"), Instance.new("Attachment")
				a0.Position = Vector3.new(0, 0.8, 0)
				a1.Position = Vector3.new(0, -0.8, 0)
				a0.Parent, a1.Parent = streak, streak
				local trail = Instance.new("Trail")
				trail.Attachment0, trail.Attachment1 = a0, a1
				trail.Lifetime = 0.5
				trail.LightEmission = 1
				trail.Color =
					ColorSequence.new(Color3.fromRGB(255, 220, 140), Color3.fromRGB(255, 90, 40))
				trail.Parent = streak
				streak.Parent = workspace
				TweenService
					:Create(
						streak,
						TweenInfo.new(1.4, Enum.EasingStyle.Linear),
						{ Position = finish }
					)
					:Play()
				Debris:AddItem(streak, 1.6)
			end
			task.wait(0.25)
		end
	end)
end

local function onFx(kind: string, position: Vector3, extra: any)
	if kind == "hatch" then
		local order = rarityOrder(extra)
		burst(
			position + Vector3.new(0, 3, 0),
			rarityColor(extra),
			15 + order * 10,
			0.8 + order * 0.15
		)
	elseif kind == "collect" then
		burst(position + Vector3.new(0, 1, 0), Color3.fromRGB(255, 210, 70), 30, 0.7)
	elseif kind == "crate" then
		flash(rarityColor(extra))
	elseif kind == "shower" then
		showerStreaks(tonumber(extra) or 20)
	end
end

function VfxController.start()
	Remotes.event("Fx").OnClientEvent:Connect(onFx)
	-- Field meteors (stream in and out) and carried meteors on characters.
	local function watch(container: Instance)
		container.ChildAdded:Connect(decorateMeteor)
		for _, child in container:GetChildren() do
			decorateMeteor(child)
		end
	end
	task.spawn(function()
		watch(workspace:WaitForChild("Meteors"))
	end)
	workspace.DescendantAdded:Connect(function(descendant)
		if descendant.Name == "CarriedMeteor" then
			task.defer(decorateMeteor, descendant)
		end
	end)
	for _, other in Players:GetPlayers() do
		local character = other.Character
		local carried = character and character:FindFirstChild("CarriedMeteor")
		if carried then
			decorateMeteor(carried)
		end
	end
end

return VfxController

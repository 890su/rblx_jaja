--!strict
-- Small readability effects:
-- * Treadmill belt chevrons slide back-to-front so it reads as a treadmill.
-- * "+1" speed popups rise from the character whenever Speed grows, so new
--   players see that running (or the treadmill) makes them faster.

local CollectionService = game:GetService("CollectionService")
local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Format = require(Shared.Util.Format)

local player = Players.LocalPlayer

local BELT_SPEED = 0.5 -- belt lengths per second
local CHEVRON_ANGLE = math.rad(35)
local POPUP_MIN_INTERVAL = 0.45

local FeedbackController = {}

local lastSpeed = 0
local pending = 0
local lastPopup = 0

local function popup(amount: number)
	local character = player.Character
	local head = character and character:FindFirstChild("Head") :: BasePart?
	if not head then
		return
	end
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(90, 34)
	gui.StudsOffset = Vector3.new(math.random(-15, 15) / 10, 2.2, 0)
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.TextScaled = true
	label.Font = Enum.Font.FredokaOne
	label.TextColor3 = Color3.fromRGB(120, 230, 255)
	label.TextStrokeTransparency = 0.2
	label.AutoLocalize = false
	label.Text = `⚡+{Format.short(amount)}`
	label.Parent = gui
	gui.Adornee = head
	gui.Parent = player:WaitForChild("PlayerGui")
	local info = TweenInfo.new(0.9, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService:Create(gui, info, { StudsOffset = gui.StudsOffset + Vector3.new(0, 2.5, 0) })
		:Play()
	TweenService:Create(label, info, { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
	Debris:AddItem(gui, 1)
end

local function onSpeedChanged()
	local speed = (player:GetAttribute("Speed") :: number?) or 0
	local delta = speed - lastSpeed
	lastSpeed = speed
	if delta <= 0 or delta > 1000 then
		pending = 0 -- reset (rebirth) or a big debug jump: no popup
		return
	end
	pending += delta
	local now = os.clock()
	if now - lastPopup >= POPUP_MIN_INTERVAL then
		lastPopup = now
		popup(pending)
		pending = 0
	end
end

function FeedbackController.start()
	lastSpeed = (player:GetAttribute("Speed") :: number?) or 0
	player:GetAttributeChangedSignal("Speed"):Connect(onSpeedChanged)

	local offset = 0
	RunService.RenderStepped:Connect(function(dt: number)
		offset = (offset + dt * BELT_SPEED) % 1
		for _, belt in CollectionService:GetTagged("TreadmillBelt") do
			local beltCFrame = belt:GetAttribute("BeltCFrame") :: CFrame?
			local length = (belt:GetAttribute("BeltLength") :: number?) or 12
			if not beltCFrame then
				continue
			end
			for _, arm in belt:GetChildren() do
				if not arm:IsA("BasePart") then
					continue
				end
				local phase = ((arm:GetAttribute("Phase") :: number?) or 0) + offset
				phase %= 1
				local side = (arm:GetAttribute("Side") :: number?) or 1
				-- Phase 0 = back of the belt (+Z), 1 = front by the console (-Z).
				-- Arms meet at the front to form a ^ pointing toward the console.
				local z = length / 2 - phase * length
				arm.CFrame = beltCFrame
					* CFrame.new(side * 0.33 * arm.Size.Z, 0, z)
					* CFrame.Angles(0, CHEVRON_ANGLE * side, 0)
				-- Fade in/out at the belt ends.
				arm.Transparency = 0.15 + 0.85 * math.max(0, 1 - math.min(phase, 1 - phase) * 6)
			end
		end
	end)
end

return FeedbackController

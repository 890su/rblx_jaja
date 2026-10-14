--!strict
-- First-minutes guide (GDD §5): one goal line at a time plus an always-on-top
-- marker over the target. Steps follow what the player actually does; the
-- server decides when the tutorial is finished (TutorialDone attribute).

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Theme = require(Shared.Theme)
local Zones = require(Shared.Config.Zones)
local Locale = require(Shared.Locale)

local UiKit = require(script.Parent.Parent.Lib.UiKit)

local player = Players.LocalPlayer

local TutorialController = {}

type Step = "run" | "grab" | "home" | "collect" | "gate" | "done"

local banner: TextLabel
local markerPart: Part
local step: Step = "run"
local coinsAtStart = 0

local function attr(name: string): number
	return (player:GetAttribute(name) :: number?) or 0
end

local function nearestMeteor(from: Vector3): Vector3?
	local folder = workspace:FindFirstChild("Meteors")
	local best, bestDistance = nil, math.huge
	if folder then
		for _, meteor in folder:GetChildren() do
			if meteor:IsA("BasePart") then
				local distance = (meteor.Position - from).Magnitude
				if distance < bestDistance then
					best, bestDistance = meteor.Position, distance
				end
			end
		end
	end
	return best
end

local function setMarker(position: Vector3?)
	if position then
		markerPart.Position = position + Vector3.new(0, 5, 0)
		markerPart.Parent = workspace
	else
		markerPart.Parent = nil
	end
end

local function update()
	if player:GetAttribute("MenuOpen") == true then
		banner.Visible = false
		setMarker(nil)
		return
	end
	if player:GetAttribute("HudNoticeActive") == true then
		banner.Visible = false
		return
	end
	if player:GetAttribute("TutorialDone") then
		step = "done"
	end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if step == "done" or not root then
		banner.Visible = step ~= "done" and banner.Visible
		setMarker(nil)
		if step == "done" then
			banner.Visible = false
		end
		return
	end
	local home = player:GetAttribute("HomePosition") :: Vector3?
	local carrying = player:GetAttribute("Carrying") ~= nil

	if step == "run" and attr("Speed") >= 15 then
		step = "grab"
	end
	if step == "grab" and carrying then
		step = "home"
	end
	if step == "home" and not carrying then
		step = "collect"
	end
	if step == "collect" and attr("Coins") > coinsAtStart then
		step = "gate"
	end

	banner.Visible = true
	if step == "run" then
		banner.Text = Locale.term("Run onto the track! Your Speed grows every second")
		setMarker(Vector3.new(root.Position.X, 3, -40))
	elseif step == "grab" then
		banner.Text = Locale.term("Grab a glowing Meteor on the track")
		setMarker(nearestMeteor(root.Position))
	elseif step == "home" then
		banner.Text = Locale.term("Bring it home! Follow the green arrow")
		setMarker(nil)
	elseif step == "collect" then
		banner.Text = Locale.term("Your creatures earn Stardust. Step on the yellow pad to collect")
		setMarker(if home then home + Vector3.new(0, 0, -12) else nil)
	elseif step == "gate" then
		local gate = Zones.ZONES[2].speedGate
		banner.Text =
			Locale.t("tutorial_gate", { speed = gate, zone = Locale.ref(Theme.ZONE_NAMES[2]) })
		setMarker(nil)
	end
end

function TutorialController.init()
	banner = UiKit.text(UiKit.gui(), {
		Name = "TutorialBanner",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 134),
		Size = UDim2.new(0.75, 0, 0, 28),
		TextColor3 = Color3.fromRGB(255, 240, 150),
		TextStrokeTransparency = 0.2,
		Visible = false,
	})

	markerPart = Instance.new("Part")
	markerPart.Name = "TutorialMarker"
	markerPart.Anchored = true
	markerPart.CanCollide = false
	markerPart.CanQuery = false
	markerPart.CanTouch = false
	markerPart.Transparency = 1
	markerPart.Size = Vector3.one
	local gui = Instance.new("BillboardGui")
	gui.AlwaysOnTop = true
	gui.Size = UDim2.fromOffset(60, 60)
	local arrow = Instance.new("TextLabel")
	arrow.BackgroundTransparency = 1
	arrow.Size = UDim2.fromScale(1, 1)
	arrow.Text = "▼"
	arrow.TextScaled = true
	arrow.Font = Enum.Font.GothamBlack
	arrow.TextColor3 = Color3.fromRGB(255, 230, 90)
	arrow.TextStrokeTransparency = 0
	arrow.Parent = gui
	gui.Parent = markerPart
	TweenService:Create(
		gui,
		TweenInfo.new(0.6, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
		{ StudsOffset = Vector3.new(0, 2, 0) }
	):Play()
end

function TutorialController.start()
	coinsAtStart = attr("Coins")
	while step ~= "done" do
		update()
		task.wait(0.3)
	end
	update()
end

return TutorialController

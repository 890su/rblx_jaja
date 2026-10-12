--!strict
-- Greybox HUD: Speed (hero number), currency, current zone, carry status and
-- toast notifications from the server. Reads replicated Player attributes —
-- display only.

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Zones = require(Shared.Config.Zones)
local Theme = require(Shared.Theme)
local Format = require(Shared.Util.Format)
local Remotes = require(Shared.Remotes)
local Locale = require(Shared.Locale)

local player = Players.LocalPlayer

local HudController = {}

local speedLabel: TextLabel
local speedHint: TextLabel
local coinsLabel: TextLabel
local zoneLabel: TextLabel
local carryLabel: TextLabel
local toastFrame: Frame

local TOAST_COLORS: { [string]: Color3 } = {
	coins = Color3.fromRGB(255, 210, 70),
	success = Color3.fromRGB(110, 230, 130),
	warning = Color3.fromRGB(255, 120, 90),
	pickup = Color3.fromRGB(140, 200, 255),
}

local function label(name: string, parent: Instance, props: { [string]: any }): TextLabel
	local l = Instance.new("TextLabel")
	l.Name = name
	l.BackgroundTransparency = 1
	l.Font = Enum.Font.FredokaOne
	l.TextScaled = true
	l.TextColor3 = Color3.new(1, 1, 1)
	l.TextStrokeTransparency = 0.2
	for key, value in props do
		(l :: any)[key] = value
	end
	l.Parent = parent
	return l
end

local function zoneIndexAt(z: number): number
	-- Mirrors WorldService layout: track starts at Z = 0 and runs toward -Z.
	if z > 0 then
		return 0
	end
	local boundary = 0
	for i, zone in Zones.ZONES do
		boundary -= zone.lengthStuds
		if z > boundary then
			return i
		end
	end
	return #Zones.ZONES
end

local function refreshStats()
	speedLabel.Text = `⚡ {Format.short((player:GetAttribute("Speed") :: number?) or 0)}`
	coinsLabel.Text = Locale.t(
		"amount_coins",
		{ amount = Format.short((player:GetAttribute("Coins") :: number?) or 0) }
	)
	local carrying = player:GetAttribute("Carrying") :: string?
	carryLabel.Visible = carrying ~= nil
	if carrying then
		carryLabel.Text = Locale.t("hud_carrying", { rarity = Locale.ref(carrying) })
		carryLabel.TextColor3 = (Theme.RARITY_COLORS :: any)[carrying] or Color3.new(1, 1, 1)
	end
end

local function refreshSpeedHint()
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local pace = if humanoid
		then (humanoid:GetAttribute("TargetWalkSpeed") :: number?) or humanoid.WalkSpeed
		else 16
	local gain = (player:GetAttribute("SpeedGainPerSecond") :: number?) or 0
	speedHint.Text = Locale.t("speed_training", {
		source = Locale.ref((player:GetAttribute("SpeedGainSource") :: string?) or "Idle"),
		gain = tostring(math.round(gain * 10) / 10),
		pace = math.floor(pace),
	})
end

-- Server sends a Locale key + args; rendered in the player's language.
local function toast(key: string, args: Locale.Args?, kind: string?)
	local message = Locale.t(key, args)
	local item = label("Toast", toastFrame, {
		Size = UDim2.new(1, 0, 0, 34),
		Text = message,
		TextColor3 = TOAST_COLORS[kind or ""] or Color3.new(1, 1, 1),
		TextTransparency = 0,
	})
	task.delay(2.5, function()
		local tween = TweenService:Create(
			item,
			TweenInfo.new(0.5),
			{ TextTransparency = 1, TextStrokeTransparency = 1 }
		)
		tween:Play()
		tween.Completed:Wait()
		item:Destroy()
	end)
end

function HudController.init()
	local gui = Instance.new("ScreenGui")
	gui.Name = "Hud"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = false

	speedLabel = label("Speed", gui, {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 8),
		Size = UDim2.new(0.35, 0, 0.09, 0),
		TextColor3 = Color3.fromRGB(120, 220, 255),
	})
	speedHint = label("SpeedHint", gui, {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.095),
		Size = UDim2.fromScale(0.65, 0.025),
		TextColor3 = Color3.fromRGB(190, 220, 235),
	})
	coinsLabel = label("Coins", gui, {
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 12, 0.5, 0),
		Size = UDim2.new(0.25, 0, 0.06, 0),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Color3.fromRGB(255, 220, 90),
	})
	zoneLabel = label("Zone", gui, {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0.125, 4),
		Size = UDim2.new(0.3, 0, 0.04, 0),
	})
	carryLabel = label("Carry", gui, {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 0.85, 0),
		Size = UDim2.new(0.5, 0, 0.05, 0),
		Visible = false,
	})

	toastFrame = Instance.new("Frame")
	toastFrame.Name = "Toasts"
	toastFrame.BackgroundTransparency = 1
	toastFrame.AnchorPoint = Vector2.new(0.5, 0)
	toastFrame.Position = UDim2.new(0.5, 0, 0.18, 0)
	toastFrame.Size = UDim2.new(0.5, 0, 0.3, 0)
	local layout = Instance.new("UIListLayout")
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.Padding = UDim.new(0, 4)
	layout.Parent = toastFrame
	toastFrame.Parent = gui

	gui.Parent = player:WaitForChild("PlayerGui")
end

function HudController.start()
	for _, attribute in { "Speed", "Coins", "Carrying" } do
		player:GetAttributeChangedSignal(attribute):Connect(refreshStats)
	end
	refreshStats()
	Remotes.event("Notify").OnClientEvent:Connect(toast)

	local lastZone = -1
	while true do
		refreshSpeedHint()
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if root then
			local zone = zoneIndexAt(root.Position.Z)
			if zone ~= lastZone then
				lastZone = zone
				zoneLabel.Text = Locale.term(
					if zone == 0 then Theme.BASE else Theme.ZONE_NAMES[zone] or `Zone {zone}`
				)
			end
		end
		task.wait(0.25)
	end
end

return HudController

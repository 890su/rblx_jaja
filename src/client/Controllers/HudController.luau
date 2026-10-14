--!strict
-- Compact corner stats, zone arrivals, carry status and
-- toast notifications from the server. Reads replicated Player attributes —
-- display only.

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local GuiService = game:GetService("GuiService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Zones = require(Shared.Config.Zones)
local Theme = require(Shared.Theme)
local Format = require(Shared.Util.Format)
local Remotes = require(Shared.Remotes)
local Locale = require(Shared.Locale)
local UiKit = require(script.Parent.Parent.Lib.UiKit)
local Icons = require(script.Parent.Parent.Lib.UiIcons)
local Interface = require(Shared.Config.Interface)
local HUD = Interface.hud

local player = Players.LocalPlayer

local HudController = {}

local speedLabel: TextLabel
local speedHint: TextLabel
local coinsLabel: TextLabel
local zoneLabel: TextLabel
local zoneArrival: CanvasGroup
local zoneTitle: TextLabel
local zoneScale: UIScale
local zoneSerial = 0
local zoneTweens: { Tween } = {}
local carryLabel: TextLabel
local toastFrame: Frame
type Notice = { message: string, kind: string? }
local noticeQueue: { Notice } = {}
local activeNotice: Notice? = nil
local showingNotice = false
local activeItem: CanvasGroup? = nil
local activeTween: Tween? = nil
local noticeSerial = 0

local function announceZone(title: string)
	zoneSerial += 1
	local serial = zoneSerial
	for _, tween in zoneTweens do
		tween:Cancel()
	end
	table.clear(zoneTweens)
	zoneTitle.Text = title
	zoneArrival.GroupTransparency = 0
	zoneArrival.Visible = player:GetAttribute("MenuOpen") ~= true and not showingNotice
	zoneLabel.Visible = false
	zoneScale.Scale = if GuiService.ReducedMotionEnabled then 1 else 0.94
	local intro = TweenService:Create(zoneScale, TweenInfo.new(Interface.openMotion), { Scale = 1 })
	table.insert(zoneTweens, intro)
	intro:Play()
	task.delay(HUD.zoneHold, function()
		if serial ~= zoneSerial then
			return
		end
		local fade =
			TweenService:Create(zoneArrival, TweenInfo.new(HUD.zoneFade), { GroupTransparency = 1 })
		table.insert(zoneTweens, fade)
		fade:Play()
		fade.Completed:Once(function()
			if serial == zoneSerial then
				zoneArrival.Visible = false
				zoneLabel.Visible = not UiKit.compact()
			end
		end)
	end)
end

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
	l.Font = UiKit.FONT
	l.AutoLocalize = false
	l.Text = ""
	l.TextScaled = true
	l.TextColor3 = Color3.new(1, 1, 1)
	l.TextStrokeTransparency = 0.2
	for key, value in props do
		(l :: any)[key] = value
	end
	l.Parent = parent
	local limit = Instance.new("UITextSizeConstraint")
	limit.MinTextSize, limit.MaxTextSize = 12, 26
	limit.Parent = l
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
	speedLabel.Text = Format.short((player:GetAttribute("Speed") :: number?) or 0)
	coinsLabel.Text = Format.short((player:GetAttribute("Coins") :: number?) or 0)
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

local function layoutNotice(item: CanvasGroup)
	local menuOpen = player:GetAttribute("MenuOpen") == true
	item.AutomaticSize = if menuOpen then Enum.AutomaticSize.None else Enum.AutomaticSize.Y
	item.Size = UDim2.new(1, 0, 0, if menuOpen then 38 else 52)
	local message = item:FindFirstChild("Message") :: TextLabel?
	if message then
		message.AutomaticSize = if menuOpen then Enum.AutomaticSize.None else Enum.AutomaticSize.Y
		message.Size = UDim2.new(1, 0, 0, if menuOpen then 18 else 32)
		message.TextWrapped = not menuOpen
		message.TextTruncate = if menuOpen then Enum.TextTruncate.AtEnd else Enum.TextTruncate.None
	end
end

local function showNextNotice()
	if showingNotice or #noticeQueue == 0 then
		return
	end
	local notice = table.remove(noticeQueue, 1) :: Notice
	activeNotice, showingNotice = notice, true
	noticeSerial += 1
	local serial = noticeSerial
	local color = TOAST_COLORS[notice.kind or ""] or Color3.new(1, 1, 1)
	local item = Instance.new("CanvasGroup")
	item.Name = "Toast"
	item.Size = UDim2.new(1, 0, 0, 52)
	item.AutomaticSize = Enum.AutomaticSize.Y
	item.BackgroundColor3, item.BackgroundTransparency = UiKit.PANEL_COLOR, 0.06
	item.BorderSizePixel, item.Active = 0, false
	UiKit.corner(item, 10)
	local padding = Instance.new("UIPadding")
	padding.PaddingLeft, padding.PaddingRight = UDim.new(0, 14), UDim.new(0, 12)
	padding.PaddingTop, padding.PaddingBottom = UDim.new(0, 10), UDim.new(0, 10)
	padding.Parent = item
	label("Message", item, {
		Size = UDim2.new(1, 0, 0, 32),
		AutomaticSize = Enum.AutomaticSize.Y,
		TextScaled = false,
		TextSize = 17,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextStrokeTransparency = 1,
		Text = notice.message,
		TextColor3 = color,
	})
	item.Parent = toastFrame
	activeItem = item
	layoutNotice(item)
	player:SetAttribute("HudNoticeActive", true)
	local function finish()
		if serial ~= noticeSerial then
			return
		end
		item:Destroy()
		activeNotice, activeItem, activeTween, showingNotice = nil, nil, nil, false
		player:SetAttribute("HudNoticeActive", false)
		showNextNotice()
	end
	task.delay(HUD.toastDuration, function()
		if serial ~= noticeSerial then
			return
		end
		if item.Parent and not GuiService.ReducedMotionEnabled then
			local tween = TweenService:Create(item, TweenInfo.new(0.18), { GroupTransparency = 1 })
			activeTween = tween
			tween:Play()
			task.delay(0.18, finish)
		else
			finish()
		end
	end)
end

-- One visible message; repeated notifications cannot fill the screen.
local function toast(key: string, args: Locale.Args?, kind: string?)
	local message = Locale.t(key, args)
	if activeNotice and activeNotice.message == message then
		return
	end
	for _, pending in noticeQueue do
		if pending.message == message then
			return
		end
	end
	if kind == "coins" or kind == "warning" then
		for i = #noticeQueue, 1, -1 do
			if noticeQueue[i].kind == "coins" then
				table.remove(noticeQueue, i)
			end
		end
	end
	-- Combat and purchase warnings describe the current action, so show them
	-- immediately instead of putting them behind older rewards.
	if kind == "warning" and showingNotice then
		noticeSerial += 1
		if activeTween then
			activeTween:Cancel()
		end
		if activeItem then
			activeItem:Destroy()
		end
		activeNotice, activeItem, activeTween, showingNotice = nil, nil, nil, false
	end
	if #noticeQueue >= HUD.toastQueueLimit then
		local discard = 1
		for i, pending in noticeQueue do
			if pending.kind ~= "warning" then
				discard = i
				break
			end
		end
		table.remove(noticeQueue, discard)
	end
	local notice: Notice = { message = message, kind = kind }
	if kind == "warning" then
		table.insert(noticeQueue, 1, notice)
	else
		table.insert(noticeQueue, notice)
	end
	showNextNotice()
end

local function statCard(
	gui: ScreenGui,
	name: string,
	title: string,
	color: Color3
): (Frame, TextLabel)
	local card = Instance.new("Frame")
	card.Name, card.BorderSizePixel = name .. "Card", 0
	card.BackgroundTransparency = 1
	card.Parent = gui
	local icon = Icons.new(card, name, color)
	icon.Position, icon.Size = UDim2.fromOffset(4, 5), UDim2.fromOffset(26, 26)
	local caption = label("Title", card, {
		Position = UDim2.fromOffset(168, 0),
		Size = UDim2.new(1, -168, 1, 0),
		Text = title,
		TextSize = 15,
		TextScaled = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = UiKit.MUTED_COLOR,
		TextStrokeTransparency = 0.35,
	})
	local captionLimit =
		caption:FindFirstChildOfClass("UITextSizeConstraint") :: UITextSizeConstraint
	captionLimit.MinTextSize, captionLimit.MaxTextSize = 12, 15
	local value = label(name, card, {
		Position = UDim2.fromOffset(36, 0),
		Size = UDim2.fromOffset(124, HUD.statHeight),
		Font = Enum.Font.GothamBold,
		TextColor3 = color,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextStrokeTransparency = 0.25,
	})
	local limit = value:FindFirstChildOfClass("UITextSizeConstraint") :: UITextSizeConstraint
	limit.MinTextSize, limit.MaxTextSize = HUD.numberMin, HUD.numberMax
	return card, value
end

function HudController.init()
	local gui = Instance.new("ScreenGui")
	gui.Name = "Hud"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = false
	gui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets

	local speedCard, speedValue =
		statCard(gui, "Speed", Locale.term("Speed"), Color3.fromRGB(120, 220, 255))
	speedLabel = speedValue
	speedHint = label("SpeedHint", gui, {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 44),
		Size = UDim2.new(0.65, 0, 0, 18),
		TextColor3 = Color3.fromRGB(190, 220, 235),
	})
	local coinsCard, coinsValue =
		statCard(gui, "Coins", Locale.term("Stardust"), Color3.fromRGB(255, 220, 90))
	coinsLabel = coinsValue
	zoneLabel = label("Zone", gui, {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 8),
		Size = UDim2.new(0.5, 0, 0, 22),
	})
	zoneArrival = Instance.new("CanvasGroup")
	zoneArrival.Name = "ZoneArrival"
	zoneArrival.GroupTransparency = 1
	zoneArrival.BackgroundTransparency = 1
	zoneArrival.AnchorPoint = Vector2.new(0.5, 0)
	zoneArrival.Position = UDim2.new(0.5, 0, 0, 104)
	zoneArrival.Visible, zoneArrival.Active = false, false
	zoneArrival.Parent = gui
	zoneScale = Instance.new("UIScale")
	zoneScale.Parent = zoneArrival
	zoneTitle = label("Title", zoneArrival, {
		Size = UDim2.new(1, 0, 1, -14),
		Font = Enum.Font.GothamBold,
		TextColor3 = Color3.fromRGB(225, 250, 246),
		TextStrokeTransparency = 0.3,
	})
	local titleLimit =
		zoneTitle:FindFirstChildOfClass("UITextSizeConstraint") :: UITextSizeConstraint
	titleLimit.MinTextSize, titleLimit.MaxTextSize = 22, 44
	local line = Instance.new("Frame")
	line.Name, line.BorderSizePixel = "Accent", 0
	line.AnchorPoint, line.Position = Vector2.new(0.5, 1), UDim2.fromScale(0.5, 1)
	line.Size = UDim2.new(0.36, 0, 0, 2)
	line.BackgroundColor3, line.BackgroundTransparency = UiKit.ACCENT_COLOR, 0.15
	line.Parent = zoneArrival
	carryLabel = label("Carry", gui, {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 0.85, 0),
		Size = UDim2.new(0.5, 0, 0.05, 0),
		Visible = false,
	})

	toastFrame = Instance.new("Frame")
	toastFrame.Name = "Toasts"
	toastFrame.BackgroundTransparency = 1
	toastFrame.AnchorPoint = Vector2.new(1, 0)
	toastFrame.AutomaticSize = Enum.AutomaticSize.Y
	toastFrame.Active = false
	local notices = Instance.new("ScreenGui")
	notices.Name, notices.ResetOnSpawn, notices.DisplayOrder = "Notifications", false, 30
	notices.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
	toastFrame.Parent = notices
	notices.Parent = player:WaitForChild("PlayerGui")

	gui.Parent = player:WaitForChild("PlayerGui")
	local function resize()
		local compact = UiKit.compact()
		-- Notifications remain enabled while the main HUD is hidden by a menu;
		-- use their live safe area when the device rotates with a menu open.
		local width = notices.AbsoluteSize.X
		local cardWidth = if compact then HUD.statPhoneWidth else HUD.statWidth
		speedCard.AnchorPoint = Vector2.new(1, 0)
		speedCard.Position, speedCard.Size =
			UDim2.new(1, -16, 0, 8), UDim2.fromOffset(cardWidth, HUD.statHeight)
		coinsCard.Position = UDim2.new(1, -16, 0, 48)
		coinsCard.AnchorPoint = Vector2.new(1, 0)
		coinsCard.Size = UDim2.fromOffset(cardWidth, HUD.statHeight)
		for _, card in { speedCard, coinsCard } do
			local caption = card:FindFirstChild("Title") :: TextLabel
			caption.Visible = not compact
		end
		for _, value in { speedLabel, coinsLabel } do
			local limit =
				value:FindFirstChildOfClass("UITextSizeConstraint") :: UITextSizeConstraint
			limit.MaxTextSize = if compact then HUD.numberPhoneMax else HUD.numberMax
		end
		zoneLabel.AnchorPoint = Vector2.new(0.5, 0)
		zoneLabel.Position = UDim2.new(0.5, 0, 0, 8)
		zoneLabel.Size =
			UDim2.fromOffset(math.min(280, math.max(48, width - cardWidth * 2 - 64)), 24)
		zoneLabel.Visible = not compact and zoneArrival.GroupTransparency >= 1
		zoneArrival.Size = UDim2.fromOffset(math.min(520, width - 32), if compact then 60 else 76)
		titleLimit.MaxTextSize = if compact then 30 else 44
		zoneArrival.Visible = zoneArrival.GroupTransparency < 1
			and player:GetAttribute("MenuOpen") ~= true
			and not showingNotice
		speedHint.Size = UDim2.fromOffset(math.max(100, width - cardWidth * 2 - 64), 22)
		speedHint.Visible = not compact
		local menuOpen = player:GetAttribute("MenuOpen") == true
		toastFrame.AnchorPoint = if menuOpen then Vector2.zero else Vector2.new(1, 0)
		toastFrame.Position = if menuOpen then UDim2.fromOffset(16, 8) else UDim2.new(1, -16, 0, 96)
		local noticeWidth = if menuOpen
			then width - 160
			else if compact then width * 0.5 else HUD.toastWidth
		toastFrame.Size = UDim2.fromOffset(math.min(HUD.toastWidth, noticeWidth), 0)
		if activeItem then
			layoutNotice(activeItem)
		end
		gui.Enabled = not menuOpen
	end
	gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(resize)
	notices:GetPropertyChangedSignal("AbsoluteSize"):Connect(resize)
	player:GetAttributeChangedSignal("MenuOpen"):Connect(resize)
	player:GetAttributeChangedSignal("HudNoticeActive"):Connect(resize)
	if workspace.CurrentCamera then
		workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(resize)
	end
	resize()
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
				announceZone(zoneLabel.Text)
			end
		end
		task.wait(0.25)
	end
end

return HudController

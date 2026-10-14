--!strict
-- Shared responsive menu shell, navigation and interaction states.

local Players = game:GetService("Players")
local GuiService = game:GetService("GuiService")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config.Interface)
local Locale = require(Shared.Locale)
local Icons = require(script.Parent.UiIcons)

local UiKit = {}

UiKit.FONT = Enum.Font.GothamMedium
UiKit.PANEL_COLOR = Config.colors.panel
UiKit.CARD_COLOR = Config.colors.card
UiKit.BUTTON_COLOR = Config.colors.primary
UiKit.DISABLED_COLOR = Config.colors.disabled
UiKit.MUTED_COLOR = Config.colors.muted
UiKit.ACCENT_COLOR = Config.colors.accent

local gui: ScreenGui? = nil
local side: Frame? = nil
local panels: { [string]: Frame } = {}
local openPanel: Frame? = nil
local previousMouseIcon = true
local shade: Frame? = nil
local moreList: ScrollingFrame? = nil
local moreButton: TextButton? = nil
local sideButtons: { [number]: TextButton } = {}
local sections: { [string]: Frame } = {}
local callbacks: { [string]: () -> () } = {}
local history: { string } = {}
local panelTween: Tween? = nil
local menuBlur: BlurEffect? = nil
local blurTween: Tween? = nil
local actionNames =
	{ "Shop", "Rebirth", "Store", "Daily", "Invite", "Station", "Index", "Wave", "Chat" }
local navNames = { "Shop", "Upgrades", "Store", "Station", "Index", "More" }
local navLabels = {
	Shop = "Shop",
	Upgrades = "Upgrades",
	Store = "Robux",
	Station = "Station",
	Index = "Collection",
	More = "Menu",
}

function UiKit.headerHeight(): number
	return Config.header + (if UiKit.compact() then 0 else Config.navHeight)
end

function UiKit.navigate(name: string)
	local callback = callbacks[name]
	if callback then
		callback()
	else
		UiKit.show(name)
	end
end

function UiKit.back()
	if #history > 1 then
		table.remove(history)
		local name = table.remove(history) :: string
		UiKit.show(name)
	else
		UiKit.close()
	end
end

function UiKit.compact(): boolean
	local camera = workspace.CurrentCamera
	local size = if camera and camera.ViewportSize.X > 100
		then camera.ViewportSize
		else (if gui then gui.AbsoluteSize else Vector2.new(800, 600))
	return size.X < Config.phoneWidth or size.Y < Config.phoneHeight
end

function UiKit.border(parent: Instance, color: Color3?)
	local stroke = Instance.new("UIStroke")
	stroke.Name = "Border"
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Thickness = 1
	stroke.Color = color or Config.colors.border
	stroke.Transparency = 0.35
	stroke.Parent = parent
end

function UiKit.surface(parent: GuiObject, accent: Color3?)
	parent.BackgroundColor3 = UiKit.CARD_COLOR
	parent.BackgroundTransparency = Config.glass.card
	parent.BorderSizePixel = 0
	UiKit.corner(parent, 12)
	UiKit.border(parent, accent)
	local gradient = Instance.new("UIGradient")
	gradient.Rotation = 90
	gradient.Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(204, 218, 239))
	gradient.Parent = parent
end

function UiKit.gui(): ScreenGui
	if not gui then
		local newGui = Instance.new("ScreenGui")
		newGui.Name = "MainUi"
		newGui.ResetOnSpawn = false
		newGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
		newGui.DisplayOrder = 10
		newGui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
		newGui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
		gui = newGui
		local backdrop = Instance.new("Frame")
		backdrop.Name = "MenuShade"
		backdrop.Size = UDim2.fromScale(1, 1)
		backdrop.BackgroundColor3 = Color3.new()
		backdrop.BackgroundTransparency = Config.glass.shade
		backdrop.BorderSizePixel, backdrop.ZIndex = 0, 4
		backdrop.Visible, backdrop.Active = false, true
		backdrop.Parent = newGui
		shade = backdrop
		local blur = Instance.new("BlurEffect")
		blur.Name, blur.Size, blur.Enabled = "MeteorMenuBlur", 0, false
		blur.Parent = game:GetService("Lighting")
		menuBlur = blur
		-- Modern first-person cameras can re-lock the cursor despite Modal.
		-- Run after camera updates, only while a visible menu owns input.
		RunService:BindToRenderStep(
			"MeteorMenuCursor",
			Enum.RenderPriority.Last.Value + 1,
			function()
				if openPanel and openPanel.Visible and newGui.Enabled then
					UserInputService.MouseBehavior = Enum.MouseBehavior.Default
					UserInputService.MouseIconEnabled = true
				end
			end
		)
		newGui.Destroying:Connect(function()
			UiKit.close()
			blur:Destroy()
			menuBlur = nil
			RunService:UnbindFromRenderStep("MeteorMenuCursor")
		end)
		local player = Players.LocalPlayer
		player.CharacterRemoving:Connect(function()
			UiKit.close()
		end)
		for _, attribute in { "ArenaPrep", "ArenaActive" } do
			player:GetAttributeChangedSignal(attribute):Connect(function()
				if player:GetAttribute(attribute) == true then
					UiKit.close()
				end
			end)
		end
		UserInputService.InputBegan:Connect(function(input, processed)
			if input.KeyCode == Enum.KeyCode.ButtonB then
				UiKit.back()
			elseif input.KeyCode == Enum.KeyCode.Escape then
				UiKit.close()
			elseif
				not processed
				and not UserInputService:GetFocusedTextBox()
				and (input.KeyCode == Enum.KeyCode.M or input.KeyCode == Enum.KeyCode.ButtonY)
			then
				UiKit.toggle("More")
			elseif
				input.KeyCode == Enum.KeyCode.Tab
				and openPanel
				and not GuiService.SelectedObject
			then
				GuiService.SelectedObject = openPanel:FindFirstChild("Close") :: GuiButton?
			end
		end)
	end
	return gui :: ScreenGui
end

function UiKit.setEnabled(b: GuiButton, enabled: boolean)
	b.Active, b.Interactable, b.Selectable, b.AutoButtonColor = enabled, enabled, enabled, enabled
	if b:IsA("TextButton") then
		b.TextColor3 = if enabled then Color3.fromRGB(240, 248, 255) else UiKit.MUTED_COLOR
	end
	if not enabled and GuiService.SelectedObject == b then
		GuiService.SelectedObject = nil
	end
end

function UiKit.close()
	if blurTween then
		blurTween:Cancel()
		blurTween = nil
	end
	if menuBlur then
		menuBlur.Size, menuBlur.Enabled = 0, false
	end
	if panelTween then
		panelTween:Cancel()
		panelTween = nil
	end
	table.clear(history)
	if openPanel then
		UserInputService.MouseIconEnabled = previousMouseIcon
	end
	openPanel = nil
	if shade then
		shade.Visible = false
	end
	if side then
		side.Visible = true
	end
	Players.LocalPlayer:SetAttribute("MenuOpen", false)
	for _, frame in panels do
		frame.Visible = false
	end
	GuiService.SelectedObject = nil
end

function UiKit.corner(parent: Instance, radius: number?)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius or 10)
	c.Parent = parent
end

function UiKit.text(parent: Instance, props: { [string]: any }): TextLabel
	local l = Instance.new("TextLabel")
	l.Text = ""
	l.BackgroundTransparency = 1
	l.Font = UiKit.FONT
	l.TextScaled = true
	l.TextColor3 = Color3.fromRGB(236, 244, 255)
	l.AutoLocalize = false -- Locale already translated the content.
	for key, value in props do
		(l :: any)[key] = value
	end
	l.Parent = parent
	local limit = Instance.new("UITextSizeConstraint")
	limit.MinTextSize, limit.MaxTextSize = Config.fontMin, Config.fontMax
	limit.Parent = l
	return l
end

function UiKit.button(parent: Instance, label: string, props: { [string]: any }): TextButton
	local b = Instance.new("TextButton")
	b.Font = UiKit.FONT
	b.TextScaled = true
	b.Text = label
	b.TextColor3 = Color3.new(1, 1, 1)
	b.BackgroundColor3 = UiKit.BUTTON_COLOR
	b.BackgroundTransparency = Config.glass.button
	b.AutoButtonColor = true
	b.AutoLocalize = false
	b.TextWrapped = true
	for key, value in props do
		(b :: any)[key] = value
	end
	UiKit.corner(b, 8)
	local pad = Instance.new("UIPadding")
	pad.PaddingTop, pad.PaddingBottom = UDim.new(0, 6), UDim.new(0, 6)
	pad.PaddingLeft, pad.PaddingRight = UDim.new(0, 10), UDim.new(0, 10)
	pad.Parent = b
	b.Parent = parent
	UiKit.border(b)
	local gradient = Instance.new("UIGradient")
	gradient.Rotation, gradient.Color, gradient.Parent =
		90, ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(208, 226, 240)), b
	local scale = Instance.new("UIScale")
	scale.Parent = b
	local tween: Tween? = nil
	local function animate(value: number, focused: boolean)
		if tween then
			tween:Cancel()
		end
		value = if GuiService.ReducedMotionEnabled then 1 else value
		tween = TweenService:Create(
			scale,
			TweenInfo.new(
				if GuiService.ReducedMotionEnabled then 0 else Config.fastMotion,
				Enum.EasingStyle.Quad
			),
			{ Scale = value }
		)
		assert(tween, "missing button tween"):Play()
		local stroke = b:FindFirstChild("Border") :: UIStroke
		stroke.Transparency, stroke.Thickness =
			if focused then 0 else 0.35, if focused then 2 else 1
	end
	b.MouseEnter:Connect(function()
		if b.Interactable then
			animate(1, true)
		end
	end)
	b.MouseLeave:Connect(function()
		animate(1, GuiService.SelectedObject == b)
	end)
	b.SelectionGained:Connect(function()
		animate(1, true)
	end)
	b.SelectionLost:Connect(function()
		animate(1, false)
	end)
	b.MouseButton1Down:Connect(function()
		if b.Interactable then
			animate(0.97, true)
		end
	end)
	b.MouseButton1Up:Connect(function()
		animate(1, GuiService.SelectedObject == b)
	end)
	b:GetPropertyChangedSignal("Interactable"):Connect(function()
		animate(1, false)
	end)
	b.Destroying:Connect(function()
		if tween then
			tween:Cancel()
		end
	end)
	local limit = Instance.new("UITextSizeConstraint")
	limit.MinTextSize, limit.MaxTextSize = Config.fontMin, Config.fontMax
	limit.Parent = b
	return b
end

local function decorateNavigation(b: TextButton, name: string, accent: Color3)
	local padding = b:FindFirstChildOfClass("UIPadding")
	if padding then
		padding:Destroy()
	end
	b.TextTransparency = 1
	local icon = Icons.new(b, name, accent)
	icon.Position = UDim2.new(0, 12, 0.5, -12)
	local label = UiKit.text(b, {
		Name = "Label",
		Text = b.Text,
		Position = UDim2.fromOffset(44, 6),
		Size = UDim2.new(1, -52, 1, -12),
		TextXAlignment = Enum.TextXAlignment.Left,
	})
	local function resizeDecoration()
		local narrow = b.AbsoluteSize.X < 112
		icon.Position = if narrow then UDim2.new(0.5, -10, 0, 3) else UDim2.new(0, 12, 0.5, -12)
		icon.Size = UDim2.fromOffset(if narrow then 20 else 24, if narrow then 20 else 24)
		label.Position = if narrow then UDim2.fromOffset(4, 25) else UDim2.fromOffset(44, 6)
		label.Size = if narrow then UDim2.new(1, -8, 0, 18) else UDim2.new(1, -52, 1, -12)
		label.TextXAlignment = if narrow
			then Enum.TextXAlignment.Center
			else Enum.TextXAlignment.Left
		label.TextWrapped = not narrow
		local limit = label:FindFirstChildOfClass("UITextSizeConstraint") :: UITextSizeConstraint
		limit.MaxTextSize = if narrow then 14 else Config.fontMax
	end
	b:GetPropertyChangedSignal("AbsoluteSize"):Connect(resizeDecoration)
	resizeDecoration()
	b:GetPropertyChangedSignal("Text"):Connect(function()
		label.Text = b.Text
	end)
	b:GetPropertyChangedSignal("TextColor3"):Connect(function()
		label.TextColor3 = b.TextColor3
	end)
end

local function layoutAction(action: TextButton)
	local compact = UiKit.compact()
	local icon = action:FindFirstChild("Icon") :: Frame?
	local label = action:FindFirstChild("Label") :: TextLabel?
	if icon then
		icon.Position = if compact then UDim2.new(0, 12, 0.5, -12) else UDim2.fromOffset(12, 12)
	end
	if label then
		label.Position = if compact then UDim2.fromOffset(44, 6) else UDim2.fromOffset(12, 42)
		label.Size = if compact then UDim2.new(1, -56, 0, 40) else UDim2.new(1, -24, 0, 30)
	end
end

local function menuSection(name: string, order: number): Frame
	if sections[name] then
		return sections[name]
	end
	local list = assert(moreList, "missing More list")
	local label = UiKit.text(list, {
		Text = Locale.term(name),
		LayoutOrder = order,
		Size = UDim2.new(1, -8, 0, 24),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = UiKit.MUTED_COLOR,
	})
	label.Name = name .. "Heading"
	local frame = Instance.new("Frame")
	frame.Name, frame.BackgroundTransparency, frame.LayoutOrder = name, 1, order + 1
	frame.Size, frame.Parent = UDim2.new(1, -8, 0, 0), list
	local grid = Instance.new("UIGridLayout")
	grid.CellPadding, grid.SortOrder, grid.Parent =
		UDim2.fromOffset(10, 10), Enum.SortOrder.LayoutOrder, frame
	local function resize()
		local columns = if frame.AbsoluteSize.X < 650 then 2 else 3
		grid.CellSize = UDim2.new(1 / columns, -10, 0, if UiKit.compact() then 64 else 88)
		for _, child in frame:GetChildren() do
			if child:IsA("TextButton") then
				layoutAction(child)
			end
		end
		frame.Size = UDim2.new(1, -8, 0, grid.AbsoluteContentSize.Y)
	end
	frame:GetPropertyChangedSignal("AbsoluteSize"):Connect(resize)
	grid:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(resize)
	resize()
	sections[name] = frame
	return frame
end

local function addAction(
	label: string,
	accent: Color3,
	order: number,
	name: string,
	onClick: () -> ()
): TextButton
	local group = if order == 1
			or order == 3
			or order == 6
			or order == 7
			or order == 10
		then "Explore"
		elseif order == 2 or order == 4 then "Progress"
		else "Social"
	local groupOrder = if group == "Explore" then 10 elseif group == "Progress" then 20 else 30
	local action = UiKit.button(menuSection(group, groupOrder), label, {
		Name = `Action{order}`,
		LayoutOrder = if group == "Explore"
			then ({ [1] = 1, [10] = 2, [6] = 3, [7] = 4, [3] = 5 })[order]
			else order,
		BackgroundColor3 = UiKit.CARD_COLOR,
		TextTransparency = 1,
	})
	local icon = Icons.new(action, name, accent)
	icon.Position = UDim2.fromOffset(12, 12)
	UiKit.text(action, {
		Name = "Label",
		Text = label,
		Position = UDim2.fromOffset(12, 42),
		Size = UDim2.new(1, -24, 0, 30),
		TextXAlignment = Enum.TextXAlignment.Left,
	})
	layoutAction(action)
	action.Activated:Connect(onClick)
	return action
end

-- One compact gameplay menu button; destinations live inside the menu.
function UiKit.sideButton(
	label: string,
	color: Color3,
	order: number,
	onClick: () -> ()
): TextButton
	if not side then
		local frame = Instance.new("Frame")
		frame.Name = "Side"
		frame.BackgroundTransparency = 1
		frame.Position = UDim2.fromOffset(Config.padding, 8)
		frame.Size = UDim2.fromOffset(Config.target, Config.target)
		local layout = Instance.new("UIListLayout")
		layout.Padding = UDim.new(0, Config.gap)
		layout.SortOrder = Enum.SortOrder.LayoutOrder
		layout.Parent = frame
		frame.Parent = UiKit.gui()
		side = frame
		local more = UiKit.panel("More", Locale.term("Menu"))
		moreList = UiKit.list(UiKit.body(more), UDim2.new(), UDim2.fromScale(1, 1))
		local menuLayout = assert(moreList, "missing menu list"):FindFirstChildOfClass(
			"UIListLayout"
		) :: UIListLayout
		menuLayout.Padding = UDim.new(0, 8)
		moreButton = UiKit.button(frame, Locale.term("Menu"), {
			Name = "More",
			LayoutOrder = 100,
			Size = UDim2.fromOffset(Config.target, Config.target),
			BackgroundColor3 = UiKit.CARD_COLOR,
			TextXAlignment = Enum.TextXAlignment.Left,
		})
		decorateNavigation(assert(moreButton, "missing More button"), "More", UiKit.ACCENT_COLOR)
		addAction(Locale.term("Upgrades"), UiKit.ACCENT_COLOR, 10, "Upgrades", function()
			UiKit.show("Upgrades")
		end)
		assert(moreButton, "missing More button").Activated:Connect(function()
			UiKit.toggle("More")
		end)
		local function resize()
			frame.AnchorPoint = Vector2.zero
			frame.Position = UDim2.fromOffset(Config.padding, 8)
			frame.Size = UDim2.fromOffset(Config.target, Config.target)
			for _, button in sideButtons do
				button.Visible = false
			end
			if moreButton then
				moreButton.Size = UDim2.fromOffset(Config.target, Config.target)
			end
		end
		if workspace.CurrentCamera then
			workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(resize)
		end
		frame:SetAttribute("Compact", UiKit.compact())
		frame.ChildAdded:Connect(resize)
		resize()
	end
	local b = UiKit.button(side :: Frame, label, {
		Size = UDim2.fromOffset(156, Config.target),
		BackgroundColor3 = UiKit.CARD_COLOR,
		LayoutOrder = order,
		TextXAlignment = Enum.TextXAlignment.Left,
	})
	local name = actionNames[order] or "More"
	callbacks[name] = onClick
	decorateNavigation(b, name, color)
	b.Activated:Connect(onClick)
	b.Name = `Menu{order}`
	sideButtons[order] = b
	b.Visible = false
	b.Size = UDim2.fromOffset(Config.target, Config.target)
	local action = addAction(label, color, order, name, function()
		-- Social actions return to play; destinations keep Menu in the back stack.
		if name == "Invite" or name == "Chat" or name == "Wave" then
			UiKit.close()
		end
		onClick()
	end)
	for _, property in { "Text", "Interactable" } do
		b:GetPropertyChangedSignal(property):Connect(function()
			action.Text = b.Text
			local actionLabel = action:FindFirstChild("Label") :: TextLabel
			actionLabel.Text = b.Text
			UiKit.setEnabled(action, b.Interactable)
			actionLabel.TextColor3 = if b.Interactable
				then Color3.fromRGB(236, 244, 255)
				else UiKit.MUTED_COLOR
		end)
	end
	return b
end

function UiKit.menuInfo(name: string): TextLabel
	return UiKit.text(
		assert(moreList, "missing More list"),
		{ Name = name, LayoutOrder = 40, Size = UDim2.new(1, -8, 0, 32) }
	)
end

-- Shows `name` and hides every other panel (toggle if already open).
function UiKit.toggle(name: string)
	if UiKit.isOpen(name) then
		UiKit.close()
	else
		UiKit.show(name)
	end
end

function UiKit.show(name: string)
	local target = panels[name]
	if not target then
		return
	end
	local player = Players.LocalPlayer
	if player:GetAttribute("ArenaPrep") == true or player:GetAttribute("ArenaActive") == true then
		return
	end
	if not openPanel then
		previousMouseIcon = UserInputService.MouseIconEnabled
	end
	local existing = table.find(history, name)
	if existing then
		while #history >= existing do
			table.remove(history)
		end
	end
	table.insert(history, name)
	if panelTween then
		panelTween:Cancel()
	end
	if openPanel then
		openPanel.Position = UDim2.fromScale(0.5, 0.5)
	end
	openPanel = target
	if menuBlur then
		if blurTween then
			blurTween:Cancel()
		end
		menuBlur.Enabled = true
		blurTween = TweenService:Create(
			menuBlur,
			TweenInfo.new(Config.fastMotion),
			{ Size = Config.glass.blur }
		)
		assert(blurTween, "missing menu blur tween"):Play()
	end
	if shade then
		shade.Visible = openPanel ~= nil
	end
	if side then
		side.Visible = openPanel == nil
	end
	Players.LocalPlayer:SetAttribute("MenuOpen", openPanel ~= nil)
	if openPanel then
		UserInputService.MouseBehavior = Enum.MouseBehavior.Default
		UserInputService.MouseIconEnabled = true
	end
	GuiService.SelectedObject = nil
	for panelName, frame in panels do
		frame.Visible = panelName == name
	end
	target.Position = UDim2.new(0.5, 0, 0.5, if GuiService.ReducedMotionEnabled then 0 else 8)
	panelTween = TweenService:Create(
		target,
		TweenInfo.new(
			if GuiService.ReducedMotionEnabled then 0 else Config.openMotion,
			Enum.EasingStyle.Quad,
			Enum.EasingDirection.Out
		),
		{ Position = UDim2.fromScale(0.5, 0.5) }
	)
	assert(panelTween, "missing panel tween"):Play()
	local lastInput = UserInputService:GetLastInputType()
	if string.find(lastInput.Name, "Gamepad") then
		GuiService.SelectedObject = target:FindFirstChild("Close") :: GuiButton?
	end
end

function UiKit.isOpen(name: string): boolean
	local frame: Frame? = panels[name]
	return if frame then frame.Visible else false
end

function UiKit.panel(name: string, title: string): Frame
	local frame = Instance.new("Frame")
	frame.Name = name
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.Position = UDim2.fromScale(0.5, 0.5)
	frame.Size = UDim2.fromScale(0.76, 0.88)
	frame.BorderSizePixel = 0
	frame.SelectionGroup = true
	frame.SelectionBehaviorUp, frame.SelectionBehaviorDown =
		Enum.SelectionBehavior.Stop, Enum.SelectionBehavior.Stop
	frame.SelectionBehaviorLeft, frame.SelectionBehaviorRight =
		Enum.SelectionBehavior.Stop, Enum.SelectionBehavior.Stop
	local bounds = Instance.new("UISizeConstraint")
	bounds.MaxSize = Config.maxWindow
	bounds.Parent = frame
	frame.BackgroundColor3 = UiKit.PANEL_COLOR
	frame.BackgroundTransparency = Config.glass.panel
	frame.Visible = false
	frame.ZIndex = 5
	-- Keep panel contents above the panel even under Global ZIndexBehavior
	-- (the engine may report Global regardless of what we set).
	frame.DescendantAdded:Connect(function(descendant)
		if descendant:IsA("GuiObject") then
			local depth = 0
			local node: Instance? = descendant.Parent
			while node and node ~= frame do
				depth += 1
				node = node.Parent
			end
			descendant.ZIndex = math.max(descendant.ZIndex, frame.ZIndex + 1 + depth)
		end
	end)
	UiKit.corner(frame, 18)
	UiKit.border(frame, Config.colors.border)
	local glow = Instance.new("UIGradient")
	glow.Color, glow.Rotation, glow.Parent =
		ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(202, 214, 234)), 90, frame
	local function resize()
		frame.Size = if UiKit.compact()
			then UDim2.fromScale(0.96, 0.96)
			else UDim2.fromScale(0.76, 0.88)
	end
	resize()
	if workspace.CurrentCamera then
		workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(resize)
	end
	local titleLabel = UiKit.text(frame, {
		Name = "Title",
		Text = title,
		TextWrapped = true,
		Size = UDim2.new(1, -156, 0, Config.target),
		Position = UDim2.fromOffset(Config.padding, 8),
		TextXAlignment = Enum.TextXAlignment.Left,
		Font = Enum.Font.GothamBold,
	})
	local titleLimit =
		titleLabel:FindFirstChildOfClass("UITextSizeConstraint") :: UITextSizeConstraint
	titleLimit.MaxTextSize = Config.titleMax
	local home = UiKit.button(frame, "", {
		Name = "Menu",
		Size = UDim2.fromOffset(Config.target, Config.target),
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -72, 0, 8),
		BackgroundColor3 = UiKit.CARD_COLOR,
	})
	local homeIcon = Icons.new(
		home,
		if name == "More" or name == "Odds" then "Back" else "More",
		UiKit.MUTED_COLOR
	)
	homeIcon.AnchorPoint, homeIcon.Position = Vector2.new(0.5, 0.5), UDim2.fromScale(0.5, 0.5)
	home.Activated:Connect(function()
		if name == "More" or name == "Odds" then
			UiKit.back()
		else
			UiKit.show("More")
		end
	end)
	local close = UiKit.button(frame, "", {
		Name = "Close",
		Size = UDim2.fromOffset(Config.target, Config.target),
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -Config.padding, 0, 8),
		BackgroundColor3 = UiKit.CARD_COLOR,
	})
	local closeIcon = Icons.new(close, "Close", UiKit.MUTED_COLOR)
	closeIcon.AnchorPoint, closeIcon.Position = Vector2.new(0.5, 0.5), UDim2.fromScale(0.5, 0.5)
	home.NextSelectionRight, close.NextSelectionLeft = close, home
	-- The always-enabled close button releases first-person/Shift Lock mouse
	-- capture even when every purchase button is sold out or unavailable.
	close.Modal = true
	close.Activated:Connect(function()
		if name == "Odds" then
			UiKit.show("Store")
		else
			UiKit.close()
		end
	end)
	frame.Parent = UiKit.gui()
	panels[name] = frame
	-- Tabs give large screens one-click destinations. Compact screens use the
	-- header's grid button, keeping room for the content and large touch targets.
	if name ~= "Odds" and name ~= "Intro" then
		local nav = Instance.new("Frame")
		nav.Name, nav.BackgroundTransparency = "Navigation", 1
		nav.Position, nav.Size, nav.Parent =
			UDim2.fromOffset(Config.padding, 64), UDim2.new(1, -32, 0, 48), frame
		local layout = Instance.new("UIListLayout")
		layout.SortOrder = Enum.SortOrder.LayoutOrder
		layout.FillDirection, layout.Padding, layout.Parent =
			Enum.FillDirection.Horizontal, UDim.new(0, 8), nav
		local buttons: { TextButton } = {}
		for order, destination in navNames do
			local selected = destination == name
			local tab = UiKit.button(nav, Locale.term(navLabels[destination]), {
				Name = destination,
				LayoutOrder = order,
				Size = UDim2.new(1 / #navNames, -7, 1, 0),
				BackgroundColor3 = if selected then UiKit.BUTTON_COLOR else UiKit.CARD_COLOR,
			})
			if selected then
				local indicator = Instance.new("Frame")
				indicator.Name, indicator.Size, indicator.Position =
					"Selected", UDim2.new(1, -20, 0, 2), UDim2.new(0, 10, 1, -5)
				indicator.BackgroundColor3, indicator.BorderSizePixel, indicator.Parent =
					UiKit.ACCENT_COLOR, 0, tab
			end
			tab.Activated:Connect(function()
				if not selected then
					UiKit.navigate(destination)
				end
			end)
			table.insert(buttons, tab)
		end
		for i, tab in buttons do
			tab.NextSelectionLeft = buttons[math.max(1, i - 1)]
			tab.NextSelectionRight = buttons[math.min(#buttons, i + 1)]
			tab.NextSelectionUp = home
		end
		local function navResize()
			nav.Visible = not UiKit.compact()
		end
		if workspace.CurrentCamera then
			workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(navResize)
		end
		navResize()
	end
	return frame
end

-- Consistent space below the header and above optional footer actions.
function UiKit.body(panel: Frame, footerHeight: number?, customLayout: boolean?): Frame
	local body = Instance.new("Frame")
	body.Name, body.BackgroundTransparency = "Body", 1
	body.Parent = panel
	-- Some headers reserve their own responsive status row. Give those panels
	-- a single layout owner instead of racing two AbsoluteSize callbacks.
	if customLayout then
		return body
	end
	local function resize()
		local header = if panel.Name == "Intro" then Config.header else UiKit.headerHeight()
		body.Position = UDim2.fromOffset(Config.padding, header)
		body.Size =
			UDim2.new(1, -Config.padding * 2, 1, -header - Config.padding - (footerHeight or 0))
	end
	panel:GetPropertyChangedSignal("AbsoluteSize"):Connect(resize)
	resize()
	return body
end

function UiKit.footer(panel: Frame, label: string, name: string?): TextButton
	return UiKit.button(panel, label, {
		Name = name or "Footer",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, Config.padding, 1, -Config.padding),
		Size = UDim2.new(1, -Config.padding * 2, 0, Config.target),
	})
end

-- Scrolling list area inside a panel; children laid out vertically.
function UiKit.list(parent: Instance, position: UDim2, size: UDim2): ScrollingFrame
	local scroll = Instance.new("ScrollingFrame")
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.Position = position
	scroll.Size = size
	scroll.ScrollBarThickness = 4
	scroll.ScrollBarImageColor3 = UiKit.MUTED_COLOR
	scroll.ScrollingDirection = Enum.ScrollingDirection.Y
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.CanvasSize = UDim2.new()
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 10)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = scroll
	scroll.Parent = parent
	return scroll
end

return UiKit

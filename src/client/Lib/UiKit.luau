--!strict
-- Shared greybox UI building blocks: one ScreenGui, a side button column, and
-- mutually exclusive centered panels. Used by every menu controller.

local Players = game:GetService("Players")
local GuiService = game:GetService("GuiService")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config.Interface)
local Locale = require(Shared.Locale)

local UiKit = {}

UiKit.FONT = Enum.Font.GothamMedium
UiKit.PANEL_COLOR = Color3.fromRGB(28, 30, 46)
UiKit.CARD_COLOR = Color3.fromRGB(42, 45, 68)
UiKit.BUTTON_COLOR = Color3.fromRGB(70, 170, 90)
UiKit.DISABLED_COLOR = Color3.fromRGB(90, 90, 100)

local gui: ScreenGui? = nil
local side: Frame? = nil
local panels: { [string]: Frame } = {}
local openPanel: Frame? = nil
local previousMouseIcon = true
local shade: Frame? = nil
local moreList: ScrollingFrame? = nil
local moreButton: TextButton? = nil
local sideButtons: { [number]: TextButton } = {}
local moreActions: { [number]: TextButton } = {}

local function dockWidth(): number
	local camera = workspace.CurrentCamera
	return math.min(328, if camera then camera.ViewportSize.X - Config.padding * 2 else 328)
end

function UiKit.compact(): boolean
	local camera = workspace.CurrentCamera
	return camera ~= nil
		and (
			camera.ViewportSize.X < Config.phoneWidth
			or camera.ViewportSize.Y < Config.phoneHeight
		)
end

function UiKit.border(parent: Instance, color: Color3?)
	local stroke = Instance.new("UIStroke")
	stroke.Name = "Border"
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Thickness = 1
	stroke.Color = color or Color3.fromRGB(73, 84, 111)
	stroke.Transparency = 0.35
	stroke.Parent = parent
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
		backdrop.BackgroundTransparency = 0.35
		backdrop.BorderSizePixel, backdrop.ZIndex = 0, 4
		backdrop.Visible, backdrop.Active = false, true
		backdrop.Parent = newGui
		shade = backdrop
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
		UserInputService.InputBegan:Connect(function(input)
			if input.KeyCode == Enum.KeyCode.Escape or input.KeyCode == Enum.KeyCode.ButtonB then
				UiKit.close()
			end
		end)
	end
	return gui :: ScreenGui
end

function UiKit.setEnabled(b: GuiButton, enabled: boolean)
	b.Active, b.Interactable, b.Selectable, b.AutoButtonColor = enabled, enabled, enabled, enabled
	if not enabled and GuiService.SelectedObject == b then
		GuiService.SelectedObject = nil
	end
end

function UiKit.close()
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
	l.TextColor3 = Color3.new(1, 1, 1)
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
	local limit = Instance.new("UITextSizeConstraint")
	limit.MinTextSize, limit.MaxTextSize = Config.fontMin, Config.fontMax
	limit.Parent = b
	return b
end

-- Adds a button to the left-side menu column (in call order).
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
		frame.Position = UDim2.new(0, Config.padding, 0, 110)
		frame.Size = UDim2.fromOffset(156, 280)
		local layout = Instance.new("UIListLayout")
		layout.Padding = UDim.new(0, Config.gap)
		layout.SortOrder = Enum.SortOrder.LayoutOrder
		layout.Parent = frame
		frame.Parent = UiKit.gui()
		side = frame
		local more = UiKit.panel("More", Locale.term("Menu"))
		moreList = UiKit.list(UiKit.body(more), UDim2.new(), UDim2.fromScale(1, 1))
		moreButton = UiKit.button(frame, Locale.term("More"), {
			Name = "More",
			LayoutOrder = 100,
			Size = UDim2.fromOffset(156, Config.target),
			BackgroundColor3 = Color3.fromRGB(65, 85, 125),
		})
		assert(moreButton, "missing More button").Activated:Connect(function()
			UiKit.toggle("More")
		end)
		local function resize()
			local compact = UiKit.compact()
			frame.AnchorPoint = if compact then Vector2.new(0.5, 0) else Vector2.zero
			frame.Position = if compact
				then UDim2.new(0.5, 0, 0, 76)
				else UDim2.new(0, Config.padding, 0, 110)
			frame.Size = if compact
				then UDim2.fromOffset(dockWidth(), Config.target)
				else UDim2.fromOffset(156, 280)
			layout.FillDirection = if compact
				then Enum.FillDirection.Horizontal
				else Enum.FillDirection.Vertical
			for number, button in sideButtons do
				button.Visible = number == 1
					or number == 6
					or (not compact and (number == 3 or number == 7))
				button.Size = UDim2.fromOffset(
					if compact then (dockWidth() - Config.gap * 2) / 3 else 156,
					Config.target
				)
			end
			if moreButton then
				moreButton.Size = UDim2.fromOffset(
					if compact then (dockWidth() - Config.gap * 2) / 3 else 156,
					Config.target
				)
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
		BackgroundColor3 = color,
		LayoutOrder = order,
	})
	b.Activated:Connect(onClick)
	b.Name = `Menu{order}`
	sideButtons[order] = b
	b.Visible = order == 1 or order == 6 or (not UiKit.compact() and (order == 3 or order == 7))
	b.Size = UDim2.fromOffset(
		if UiKit.compact() then (dockWidth() - Config.gap * 2) / 3 else 156,
		Config.target
	)
	local action = UiKit.button(assert(moreList, "missing More actions list"), label, {
		Name = `Action{order}`,
		Size = UDim2.new(1, -8, 0, Config.target),
		LayoutOrder = order,
		BackgroundColor3 = color,
	})
	moreActions[order] = action
	action.Activated:Connect(function()
		UiKit.close()
		onClick()
	end)
	for _, property in { "Text", "Interactable", "BackgroundColor3" } do
		b:GetPropertyChangedSignal(property):Connect(function()
			action.Text, action.BackgroundColor3 = b.Text, b.BackgroundColor3
			UiKit.setEnabled(action, b.Interactable)
		end)
	end
	return b
end

function UiKit.menuInfo(name: string): TextLabel
	return UiKit.text(
		assert(moreList, "missing More list"),
		{ Name = name, LayoutOrder = -1, Size = UDim2.new(1, -8, 0, 32) }
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
	local player = Players.LocalPlayer
	if player:GetAttribute("ArenaPrep") == true or player:GetAttribute("ArenaActive") == true then
		return
	end
	if not openPanel then
		previousMouseIcon = UserInputService.MouseIconEnabled
	end
	openPanel = panels[name]
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
	local bounds = Instance.new("UISizeConstraint")
	bounds.MaxSize = Config.maxWindow
	bounds.Parent = frame
	frame.BackgroundColor3 = UiKit.PANEL_COLOR
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
	UiKit.corner(frame, 14)
	UiKit.border(frame, Color3.fromRGB(100, 135, 175))
	local function resize()
		frame.Size = if UiKit.compact()
			then UDim2.fromScale(0.96, 0.96)
			else UDim2.fromScale(0.76, 0.88)
	end
	resize()
	if workspace.CurrentCamera then
		workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(resize)
	end
	UiKit.text(frame, {
		Name = "Title",
		Text = title,
		TextWrapped = true,
		Size = UDim2.new(1, -96, 0, Config.target),
		Position = UDim2.fromOffset(Config.padding, 8),
		TextXAlignment = Enum.TextXAlignment.Left,
	})
	local close = UiKit.button(frame, "X", {
		Name = "Close",
		Size = UDim2.fromOffset(Config.target, Config.target),
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -Config.padding, 0, 8),
		BackgroundColor3 = Color3.fromRGB(190, 70, 70),
	})
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
	return frame
end

-- Consistent space below the header and above optional footer actions.
function UiKit.body(panel: Frame, footerHeight: number?): Frame
	local body = Instance.new("Frame")
	body.Name, body.BackgroundTransparency = "Body", 1
	body.Position = UDim2.fromOffset(Config.padding, Config.header)
	body.Size =
		UDim2.new(1, -Config.padding * 2, 1, -Config.header - Config.padding - (footerHeight or 0))
	body.Parent = panel
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
	scroll.ScrollBarThickness = 6
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.CanvasSize = UDim2.new()
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 6)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = scroll
	scroll.Parent = parent
	return scroll
end

return UiKit

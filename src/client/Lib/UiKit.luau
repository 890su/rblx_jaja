--!strict
-- Shared greybox UI building blocks: one ScreenGui, a side button column, and
-- mutually exclusive centered panels. Used by every menu controller.

local Players = game:GetService("Players")
local GuiService = game:GetService("GuiService")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

local UiKit = {}

UiKit.FONT = Enum.Font.FredokaOne
UiKit.PANEL_COLOR = Color3.fromRGB(28, 30, 46)
UiKit.CARD_COLOR = Color3.fromRGB(42, 45, 68)
UiKit.BUTTON_COLOR = Color3.fromRGB(70, 170, 90)
UiKit.DISABLED_COLOR = Color3.fromRGB(90, 90, 100)

local gui: ScreenGui? = nil
local side: Frame? = nil
local panels: { [string]: Frame } = {}
local openPanel: Frame? = nil
local previousMouseIcon = true

function UiKit.gui(): ScreenGui
	if not gui then
		local newGui = Instance.new("ScreenGui")
		newGui.Name = "MainUi"
		newGui.ResetOnSpawn = false
		newGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
		newGui.DisplayOrder = 10
		newGui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
		gui = newGui
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
	for key, value in props do
		(l :: any)[key] = value
	end
	l.Parent = parent
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
	for key, value in props do
		(b :: any)[key] = value
	end
	UiKit.corner(b, 8)
	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0.12, 0)
	pad.PaddingBottom = UDim.new(0.12, 0)
	pad.Parent = b
	b.Parent = parent
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
		frame.Position = UDim2.new(0, 12, 0.56, 0)
		frame.Size = UDim2.fromScale(0.13, 0.42)
		local layout = Instance.new("UIListLayout")
		layout.Padding = UDim.new(0.02, 0)
		layout.SortOrder = Enum.SortOrder.LayoutOrder
		layout.Parent = frame
		frame.Parent = UiKit.gui()
		side = frame
	end
	local b = UiKit.button(
		side :: Frame,
		label,
		{ Size = UDim2.fromScale(1, 0.13), BackgroundColor3 = color, LayoutOrder = order }
	)
	b.Activated:Connect(onClick)
	b.Name = `Menu{order}`
	return b
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
	frame.Position = UDim2.fromScale(0.5, 0.52)
	frame.Size = UDim2.fromScale(0.68, 0.78)
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
	local function resize()
		local camera = workspace.CurrentCamera
		local small = camera and (camera.ViewportSize.X < 700 or camera.ViewportSize.Y < 450)
		frame.Size = if small then UDim2.fromScale(0.90, 0.86) else UDim2.fromScale(0.68, 0.78)
	end
	resize()
	if workspace.CurrentCamera then
		workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(resize)
	end
	UiKit.text(frame, {
		Name = "Title",
		Text = title,
		Size = UDim2.fromScale(0.7, 0.1),
		Position = UDim2.fromScale(0.04, 0.02),
		TextXAlignment = Enum.TextXAlignment.Left,
	})
	local close = UiKit.button(frame, "X", {
		Name = "Close",
		Size = UDim2.fromScale(0.07, 0.1),
		Position = UDim2.fromScale(0.91, 0.02),
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

--!strict
if not game:GetService("RunService"):IsStudio() then
	return
end
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local remote = ReplicatedStorage:WaitForChild("CommerceQA", 180)
if not remote or not remote:IsA("RemoteEvent") then
	return
end
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared.Remotes)
local Locale = require(Shared.Locale)
local UiKit = require(script.Parent.Parent.Lib.UiKit)
local Store = require(script.Parent.Parent.Controllers.StoreController)
local player = game:GetService("Players").LocalPlayer
remote.OnClientEvent:Connect(function(nonce: number, op: string, key: any)
	remote:FireServer("stage", op)
	local ok, result = pcall(function(): any
		if op == "stationAction" then
			Remotes.event("StationAction")
				:FireServer(key.action, key.slot, key.index, key.expectedSlot, key.expectedStored)
			task.wait(0.35)
			return true
		end
		if op == "warehouse" then
			local g = UiKit.gui()
			local panel = assert(g:FindFirstChild("Station"), "missing inventory panel")
			local store =
				assert(panel:FindFirstChild("StoreButton"), "missing storage action") :: TextButton
			local foreignPrompts, foreignPreviews = 0, 0
			for _, prompt in game:GetService("CollectionService"):GetTagged("WarehousePrompt") do
				local plot = prompt.Parent and prompt.Parent.Parent and prompt.Parent.Parent.Parent
				if
					plot
					and plot:GetAttribute("OwnerUserId") ~= player.UserId
					and prompt:IsA("ProximityPrompt")
					and prompt.Enabled
				then
					foreignPrompts += 1
				end
			end
			for _, plot in workspace.World.Plots:GetChildren() do
				if plot:GetAttribute("OwnerUserId") ~= player.UserId then
					local locker = plot:FindFirstChild("Warehouse")
					if locker and locker:FindFirstChild("PrivateStoragePreviews") then
						foreignPreviews += 1
					end
				end
			end
			return {
				open = UiKit.isOpen("Station"),
				foreignPrompts = foreignPrompts,
				foreignPreviews = foreignPreviews,
				storeHeight = store.AbsoluteSize.Y,
			}
		end
		if op == "buy" then
			Remotes.event("ShopBuy"):FireServer(key)
			task.wait(0.3)
			return true
		end
		if op == "upgrade" then
			if typeof(key) == "table" then
				Remotes.event("BuyUpgrade"):FireServer(key.key, key.expected)
			else
				Remotes.event("BuyUpgrade"):FireServer(key)
			end
			task.wait(0.3)
			return true
		end
		if op == "facility" then
			local panel = UiKit.gui():FindFirstChild("Upgrades") :: Frame
			local card = assert(panel:FindFirstChild(key, true), "missing facility card")
			local buy = card:FindFirstChild("Buy") :: TextButton
			local foreign = 0
			for _, prompt in game:GetService("CollectionService"):GetTagged("FacilityPrompt") do
				if
					prompt:IsA("ProximityPrompt")
					and prompt.Enabled
					and prompt.Parent
					and prompt.Parent.Parent
					and prompt.Parent.Parent:GetAttribute("OwnerUserId") ~= player.UserId
				then
					foreign += 1
				end
			end
			return {
				open = UiKit.isOpen("Upgrades"),
				label = buy.Text,
				enabled = buy.Interactable,
				foreign = foreign,
			}
		end
		if op == "credit" then
			Remotes.event("UsePurchaseCredit"):FireServer(key)
			task.wait(0.3)
			return true
		end
		if op == "menus" then
			local gui = UiKit.gui()
			local checked = 0
			local layouts: { any } = {}
			for _, name in { "Shop", "Rebirth", "Store", "Upgrades", "Station", "Daily", "Index" } do
				remote:FireServer("stage", "menu:" .. name)
				UiKit.show(name)
				task.wait(0.1)
				local panel = gui:FindFirstChild(name) :: Frame
				assert(
					panel and panel.Visible and panel.AbsoluteSize.X > 0,
					"menu invisible: "
						.. name
						.. "; panel="
						.. tostring(panel)
						.. "; visible="
						.. tostring(if panel then panel.Visible else nil)
						.. "; size="
						.. tostring(if panel then panel.AbsoluteSize else nil)
						.. "; viewport="
						.. tostring(workspace.CurrentCamera.ViewportSize)
						.. "; arena="
						.. tostring(player:GetAttribute("ArenaActive"))
						.. "/"
						.. tostring(player:GetAttribute("ArenaPrep"))
				)
				local close = panel:FindFirstChild("Close") :: TextButton
				local badge = gui:FindFirstChild("StorageBadge") :: TextLabel?
				assert(not badge or not badge.Visible, "storage HUD overlaps menu")
				local body = panel:FindFirstChild("Body") :: Frame
				assert(body.AbsoluteSize.Y > 0, "menu has no content space: " .. name)
				table.insert(layouts, {
					name = name,
					width = panel.AbsoluteSize.X,
					height = panel.AbsoluteSize.Y,
					bodyHeight = body.AbsoluteSize.Y,
					compact = UiKit.compact(),
					viewport = tostring(workspace.CurrentCamera.ViewportSize),
				})
				assert(close.Modal and close.Interactable, "close lost mouse release")
				assert(
					close.AbsoluteSize.X >= 48 and close.AbsoluteSize.Y >= 48,
					"close touch target too small"
				)
				local notices = player.PlayerGui:FindFirstChild("Notifications") :: ScreenGui?
				assert(
					notices and notices.Enabled and notices.DisplayOrder > gui.DisplayOrder,
					"notifications hidden by menu"
				)
				local visible = 0
				for _, other in gui:GetChildren() do
					if other:IsA("Frame") and other:FindFirstChild("Close") and other.Visible then
						visible += 1
					end
				end
				assert(visible == 1, "overlapping menu panels")
				UiKit.toggle(name)
				assert(not panel.Visible, "menu toggle did not close")
				checked += 1
			end
			Store.showOdds("Crate1")
			assert(UiKit.isOpen("Odds") and not UiKit.isOpen("Store"), "odds did not open")
			UiKit.show("Store")
			assert(not UiKit.isOpen("Odds"), "odds did not close")
			UiKit.close()
			UiKit.show("More")
			UiKit.show("Upgrades")
			UiKit.back()
			assert(UiKit.isOpen("More"), "back lost menu destination")
			UiKit.back()
			assert(player:GetAttribute("MenuOpen") == false, "back lost gameplay input")
			UiKit.show("Shop")
			UiKit.show("Upgrades")
			UiKit.show("Shop")
			UiKit.back()
			assert(player:GetAttribute("MenuOpen") == false, "navigation cycle left stale history")
			for _, section in { "Shop", "Store", "Station", "Index" } do
				UiKit.navigate(section)
				assert(UiKit.isOpen(section), "navigation failed: " .. section)
				if section == "Station" and workspace.CurrentCamera.ViewportSize.X > 100 then
					local station = gui:FindFirstChild("Station") :: Frame
					local slot = station:FindFirstChild("Slot1", true) :: GuiButton?
					local deadline = os.clock() + 10
					while not slot and os.clock() < deadline do
						task.wait(0.05)
						slot = station:FindFirstChild("Slot1", true) :: GuiButton?
					end
					assert(slot, "missing initial station slot")
					local service = game:GetService("GuiService")
					service.SelectedObject = slot
					assert(service.SelectedObject == slot, "station initial focus unavailable")
					remote:FireServer(
						"stage",
						"station focus viewport: " .. tostring(workspace.CurrentCamera.ViewportSize)
					)
					Remotes.event("StationAction"):FireServer("request")
					task.wait(0.3)
					local focus = service.SelectedObject
					assert(
						focus and focus.Name == "Slot1" and focus == slot,
						"station refresh lost focus"
					)
				end
				UiKit.close()
			end
			UiKit.show("More")
			local more = gui:FindFirstChild("More") :: Frame
			task.wait(0.2)
			for _, order in { 1, 2, 3, 4, 5, 6, 7, 8, 9, 10 } do
				local action = more:FindFirstChild(`Action{order}`, true) :: TextButton
				assert(
					action and action:FindFirstChild("Icon") and action:FindFirstChild("Label"),
					"hub destination missing"
				)
				assert(action.AbsoluteSize.Y >= 48, "hub touch target too small")
			end
			local dock = gui:FindFirstChild("Side") :: Frame
			local visible = 0
			for _, name in { "Menu1", "Menu6", "More" } do
				local b = dock:FindFirstChild(name) :: TextButton
				if b.Visible then
					visible += 1
					assert(
						b.AbsoluteSize.X >= 48 and b.AbsoluteSize.Y >= 48,
						"menu touch target too small"
					)
				end
				local icon = b:FindFirstChild("Icon") :: Frame
				local label = b:FindFirstChild("Label") :: TextLabel
				assert(
					icon.AbsolutePosition.X + icon.AbsoluteSize.X <= label.AbsolutePosition.X
						or icon.AbsolutePosition.Y + icon.AbsoluteSize.Y
							<= label.AbsolutePosition.Y,
					"navigation icon overlaps its label"
				)
			end
			assert(
				visible == 1 and (dock:FindFirstChild("More") :: GuiObject).Visible,
				"gameplay menu must stay compact"
			)
			UiKit.close()
			return { menus = checked, odds = true, layout = layouts }
		end
		if op == "shop" then
			UiKit.show("Shop")
			task.wait(0.3)
			local gui = UiKit.gui()
			local panel = assert(gui:FindFirstChild("Shop"), "QA Shop")
			local b = panel:FindFirstChild("Buy1", true) :: TextButton
			local close = panel:FindFirstChild("Close") :: TextButton
			local cameraMode = player.CameraMode
			player.CameraMode = Enum.CameraMode.LockFirstPerson
			task.wait(0.3)
			-- Background Studio test clients may not render a frame at all.
			-- Keep the input observation bounded and report that condition.
			local rendered = false
			local renderConnection = game:GetService("RunService").PreRender:Connect(function()
				rendered = true
			end)
			local renderDeadline = os.clock() + 1
			while not rendered and os.clock() < renderDeadline do
				task.wait(0.05)
			end
			renderConnection:Disconnect()
			local released = game:GetService("UserInputService").MouseBehavior
				== Enum.MouseBehavior.Default
			player.CameraMode = cameraMode
			local views = 0
			for _, item in panel:GetDescendants() do
				if item:IsA("ViewportFrame") and item:FindFirstChild("Subject") then
					views += 1
				end
			end
			return {
				enabled = b.Interactable,
				soldOut = b.Text == Locale.term("Sold out"),
				modal = close.Modal,
				mouseReleased = released,
				previews = views,
				rendered = rendered,
			}
		end
		if op == "index" then
			UiKit.show("Index")
			task.wait(0.3)
			local gui = UiKit.gui()
			local dark = 0
			local known = 0
			for _, item in assert(gui:FindFirstChild("Index"), "QA Index"):GetDescendants() do
				if item:IsA("ViewportFrame") then
					if item:GetAttribute("PreviewKey") == "comet_cat:known" then
						known += 1
					end
					if item:GetAttribute("PreviewKey") == "moon_moth:locked" then
						for _, part in item:GetDescendants() do
							if part:IsA("BasePart") and part.Color.R < 0.05 then
								dark += 1
							end
						end
					end
				end
			end
			return { known = known, dark = dark, indexCount = player:GetAttribute("IndexCount") }
		end
		return false
	end)
	remote:FireServer(nonce, { ok = ok, result = result })
end)
-- The probe subscribes independently of the client bootstrap. Do not start
-- menu assertions before panels and the first-visit intro have initialized.
local deadline = os.clock() + 120
while os.clock() < deadline do
	local gui = player.PlayerGui:FindFirstChild("MainUi")
	local ready = gui ~= nil and player:GetAttribute("TutorialDone") ~= nil
	for _, name in { "Shop", "Rebirth", "Store", "Upgrades", "Station", "Daily", "Index" } do
		ready = ready and gui ~= nil and gui:FindFirstChild(name) ~= nil
	end
	ready = ready
		and (
			player:GetAttribute("TutorialDone") == true
			or (gui ~= nil and gui:FindFirstChild("Intro") ~= nil)
		)
	if ready then
		UiKit.close()
		remote:FireServer("ready")
		break
	end
	task.wait(0.1)
end

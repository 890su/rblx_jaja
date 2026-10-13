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
		if op == "buy" then
			Remotes.event("ShopBuy"):FireServer(key)
			task.wait(0.3)
			return true
		end
		if op == "upgrade" then
			Remotes.event("BuyUpgrade"):FireServer(key)
			task.wait(0.3)
			return true
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
					task.wait(0.3)
					local station = gui:FindFirstChild("Station") :: Frame
					local slot = station:FindFirstChild("Slot1", true) :: GuiButton
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
			for _, name in { "Menu1", "Menu6", "More" } do
				local b = dock:FindFirstChild(name) :: TextButton
				local icon = b:FindFirstChild("Icon") :: Frame
				local label = b:FindFirstChild("Label") :: TextLabel
				assert(
					icon.AbsolutePosition.X + icon.AbsoluteSize.X <= label.AbsolutePosition.X,
					"navigation icon overlaps its label"
				)
			end
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
			game:GetService("RunService").PreRender:Wait()
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
remote:FireServer("ready")

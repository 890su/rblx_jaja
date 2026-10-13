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
			for _, name in { "Shop", "Rebirth", "Store", "Upgrades", "Station", "Daily", "Index" } do
				remote:FireServer("stage", "menu:" .. name)
				UiKit.show(name)
				task.wait(0.1)
				local panel = gui:FindFirstChild(name) :: Frame
				assert(
					panel and panel.Visible and panel.AbsoluteSize.X > 0,
					"menu invisible: " .. name
				)
				local close = panel:FindFirstChild("Close") :: TextButton
				assert(close.Modal and close.Interactable, "close lost mouse release")
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
			return { menus = checked, odds = true }
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

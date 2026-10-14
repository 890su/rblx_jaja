--!strict
-- Unbought facilities live outside Workspace, with a low floor marker instead.
local Shared = game:GetService("ReplicatedStorage").Shared
local Math = require(Shared.Util.UpgradeMath)
local Format = require(Shared.Util.Format)
local CollectionService = game:GetService("CollectionService")
local ServerStorage = game:GetService("ServerStorage")
local Config = require(Shared.Config.BaseLayout)
local Build = {}

function Build.marker(parent: Model, key: string, position: Vector3): BasePart
	local spec = assert(Math.spec(key), "unknown facility")
	local part = Instance.new("Part")
	part.Name, part.Size, part.Position = key .. "BuildSite", Vector3.new(5, 0.08, 4), position
	part.Anchored, part.CanCollide, part.CanTouch, part.CanQuery = true, false, false, false
	part.Color, part.Material, part.Transparency =
		Color3.fromRGB(65, 160, 160), Enum.Material.SmoothPlastic, 0.75
	local gui = Instance.new("BillboardGui")
	gui.Name, gui.Size, gui.StudsOffset = "Offer", UDim2.fromOffset(160, 48), Vector3.new(0, 1.5, 0)
	gui.MaxDistance, gui.Enabled, gui.AlwaysOnTop = 32, false, false
	for index, text in { spec.title, Format.short(assert(Math.cost(key, 0))) } do
		local label = Instance.new("TextLabel")
		label.Size, label.Position = UDim2.fromScale(1, 0.5), UDim2.fromScale(0, (index - 1) / 2)
		label.BackgroundTransparency, label.TextScaled = 1, true
		label.Text, label.AutoLocalize = text, index == 1
		label.TextColor3, label.Font = Color3.fromRGB(120, 235, 220), Enum.Font.GothamBold
		label.TextStrokeTransparency = 0.3
		label.Parent = gui
	end
	gui.Parent = part
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name, prompt.ActionText, prompt.ObjectText = "BuildFacilityPrompt", "Build", spec.title
	prompt.HoldDuration, prompt.MaxActivationDistance, prompt.RequiresLineOfSight =
		0.15, Config.purchaseDistance - 2, false
	prompt:SetAttribute("UpgradeKey", key)
	prompt.Parent = part
	part.Parent = parent
	CollectionService:AddTag(prompt, "FacilityPrompt")
	return part
end

function Build.setOwned(plot: Model, facility: Model, key: string, owned: boolean)
	local folder = ServerStorage:FindFirstChild("PlotFacilities")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name, folder.Parent = "PlotFacilities", ServerStorage
	end
	local target: Instance = if owned then plot else assert(folder, "missing facilities folder")
	if facility.Parent ~= target then
		facility.Parent = target
	end
	plot:SetAttribute(`FacilityOwned_{key}`, owned)
end

return Build

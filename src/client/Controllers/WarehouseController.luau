--!strict
-- Only this player sees previews from their private inventory. No moving
-- physics, render loop, or replication of another player's stored roster.
local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")
local ProximityPromptService = game:GetService("ProximityPromptService")
local Shared = game:GetService("ReplicatedStorage").Shared
local Config = require(Shared.Config.Warehouse)
local Locale = require(Shared.Locale)
local Types = require(Shared.Types)
local Remotes = require(Shared.Remotes)
local player = Players.LocalPlayer
local Controller = {}
local watched: { [ProximityPrompt]: RBXScriptConnection } = {}
local snapshot: Types.StationState? = nil
local previewFolder: Folder? = nil
local previewModel: Model? = nil

local function plotOf(prompt: ProximityPrompt): Model?
	local screen = prompt.Parent
	local warehouse = screen and screen.Parent
	local plot = warehouse and warehouse.Parent
	return if plot and plot:IsA("Model") then plot else nil
end

local function render()
	local mine: Model? = nil
	for prompt in watched do
		local plot = plotOf(prompt)
		if plot and plot:GetAttribute("OwnerUserId") == player.UserId then
			local warehouse = prompt.Parent and prompt.Parent.Parent
			if warehouse and warehouse:IsA("Model") then
				mine = warehouse
			end
			break
		end
	end
	if previewModel ~= mine and previewFolder then
		previewFolder:Destroy()
		previewFolder = nil
	end
	previewModel = mine
	if previewFolder and previewFolder.Parent ~= mine then
		previewFolder = nil
	end
	if not mine or not snapshot then
		return
	end
	local body = mine:FindFirstChild("Body")
	if not body or not body:IsA("BasePart") then
		return
	end
	if not previewFolder then
		local fresh = Instance.new("Folder")
		fresh.Name, fresh.Parent = "PrivateStoragePreviews", mine
		previewFolder = fresh
	end
	local folder = assert(previewFolder, "missing storage preview folder")
	local assets = game.ReplicatedStorage:FindFirstChild("Assets")
	local creatures = assets and assets:FindFirstChild("Creatures")
	for index = 1, Config.previewCount do
		local state = snapshot.storage[index]
		local hatching = state and state.hatchAt and state.hatchAt > workspace:GetServerTimeNow()
		local key = if state then state.key .. (if hatching then ":egg" else ":creature") else ""
		local old = folder:FindFirstChild(tostring(index))
		if old and old:GetAttribute("PreviewKey") == key then
			continue
		end
		if old then
			old:Destroy()
		end
		local anchor = body:FindFirstChild(`Preview{index}`)
		local source = if hatching
			then assets and assets:FindFirstChild("Meteor")
			else state and creatures and creatures:FindFirstChild(state.creatureId)
		if
			not state
			or not anchor
			or not anchor:IsA("Attachment")
			or not source
			or not source:IsA("Model")
		then
			continue
		end
		local model = source:Clone()
		model.Name = tostring(index)
		model:SetAttribute("PreviewKey", key)
		local _, size = model:GetBoundingBox()
		model:ScaleTo(model:GetScale() * Config.previewSize / math.max(0.01, size.Magnitude))
		local box = model:GetBoundingBox()
		model:PivotTo(model:GetPivot() + (anchor.WorldPosition - box.Position))
		for _, node in model:GetDescendants() do
			if node:IsA("BasePart") then
				node.Anchored, node.CanCollide, node.CanQuery, node.CanTouch =
					true, false, false, false
			elseif
				node:IsA("LuaSourceContainer")
				or node:IsA("ParticleEmitter")
				or node:IsA("Trail")
				or node:IsA("Light")
			then
				node:Destroy()
			end
		end
		model.Parent = folder
		if hatching then
			task.delay(
				math.max(0.1, (state.hatchAt :: number) - workspace:GetServerTimeNow()) + 0.1,
				render
			)
		end
	end
end

local function refresh()
	for prompt in watched do
		local plot = plotOf(prompt)
		prompt.Enabled = plot ~= nil
			and plot:GetAttribute("OwnerUserId") == player.UserId
			and player:GetAttribute("MenuOpen") ~= true
			and player:GetAttribute("Carrying") == nil
			and player:GetAttribute("ArenaActive") ~= true
			and player:GetAttribute("ArenaPrep") ~= true
		prompt.ActionText, prompt.ObjectText =
			Locale.term("Manage creatures"), Locale.term("Storage")
	end
	render()
end

local function watch(instance: Instance)
	if not instance:IsA("ProximityPrompt") or watched[instance] then
		return
	end
	local plot = plotOf(instance)
	if not plot then
		return
	end
	watched[instance] = plot:GetAttributeChangedSignal("OwnerUserId"):Connect(refresh)
	refresh()
end

function Controller.start()
	CollectionService:GetInstanceAddedSignal("WarehousePrompt"):Connect(watch)
	CollectionService:GetInstanceRemovedSignal("WarehousePrompt"):Connect(function(instance)
		if instance:IsA("ProximityPrompt") and watched[instance] then
			watched[instance]:Disconnect()
			watched[instance] = nil
			refresh()
		end
	end)
	for _, instance in CollectionService:GetTagged("WarehousePrompt") do
		watch(instance)
	end
	for _, attribute in { "MenuOpen", "Carrying", "ArenaActive", "ArenaPrep" } do
		player:GetAttributeChangedSignal(attribute):Connect(refresh)
	end
	ProximityPromptService.PromptShown:Connect(function(prompt)
		if watched[prompt] and prompt.Enabled then
			Remotes.event("StationAction"):FireServer("request")
		end
	end)
	Remotes.event("StationState").OnClientEvent:Connect(function(state: Types.StationState)
		snapshot = state
		render()
	end)
end

return Controller

--!strict
-- Player profiles. WEEK 1: in-memory only. Week 2 swaps the backend to
-- ProfileStore (session locking, autosave, BindToClose) behind this same API.
-- Key stats are mirrored to Player attributes (+ leaderstats) for the client;
-- attributes are display-only and never read back as truth.

local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Types = require(Shared.Types)
local Economy = require(Shared.Config.Economy)

type Profile = Types.PlayerProfile
type LoadedCallback = (player: Player, profile: Profile) -> ()

local DataService = {}

local profiles: { [Player]: Profile } = {}
local loadedCallbacks: { LoadedCallback } = {}
local removingCallbacks: { (player: Player, profile: Profile) -> () } = {}

local function newProfile(): Profile
	return {
		schema = 1,
		coins = 0,
		speed = 0,
		rebirths = 0,
		pedestalCount = Economy.PEDESTALS_START,
		pedestals = {},
		lastOnline = os.time(),
		playtimeTotal = 0,
		flags = {},
	}
end

local function syncAttributes(player: Player, profile: Profile)
	player:SetAttribute("Speed", math.floor(profile.speed))
	player:SetAttribute("Coins", math.floor(profile.coins))
	player:SetAttribute("Rebirths", profile.rebirths)
	local leaderstats = player:FindFirstChild("leaderstats")
	if leaderstats then
		local speed = leaderstats:FindFirstChild("Speed") :: IntValue?
		local rebirths = leaderstats:FindFirstChild("Rebirths") :: IntValue?
		if speed then
			speed.Value = math.floor(profile.speed)
		end
		if rebirths then
			rebirths.Value = profile.rebirths
		end
	end
end

local function createLeaderstats(player: Player)
	local folder = Instance.new("Folder")
	folder.Name = "leaderstats"
	for _, statName in { "Speed", "Rebirths" } do
		local value = Instance.new("IntValue")
		value.Name = statName
		value.Parent = folder
	end
	folder.Parent = player
end

local function onPlayerAdded(player: Player)
	local profile = newProfile()
	profiles[player] = profile
	createLeaderstats(player)
	syncAttributes(player, profile)
	for _, callback in loadedCallbacks do
		task.spawn(callback, player, profile)
	end
end

local function onPlayerRemoving(player: Player)
	local profile = profiles[player]
	if not profile then
		return
	end
	profile.lastOnline = os.time()
	for _, callback in removingCallbacks do
		task.spawn(callback, player, profile)
	end
	profiles[player] = nil
end

-- Runs `callback` for every player whose profile is (or becomes) loaded.
function DataService.onLoaded(callback: LoadedCallback)
	table.insert(loadedCallbacks, callback)
	for player, profile in profiles do
		task.spawn(callback, player, profile)
	end
end

function DataService.onRemoving(callback: (player: Player, profile: Profile) -> ())
	table.insert(removingCallbacks, callback)
end

function DataService.get(player: Player): Profile?
	return profiles[player]
end

function DataService.addCoins(player: Player, delta: number)
	local profile = profiles[player]
	if not profile then
		return
	end
	profile.coins = math.max(0, profile.coins + delta)
	syncAttributes(player, profile)
end

function DataService.setSpeed(player: Player, value: number)
	local profile = profiles[player]
	if not profile then
		return
	end
	profile.speed = math.max(0, value)
	syncAttributes(player, profile)
end

function DataService.sync(player: Player)
	local profile = profiles[player]
	if profile then
		syncAttributes(player, profile)
	end
end

function DataService.start()
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end
end

return DataService

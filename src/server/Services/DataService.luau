--!strict
-- Player profiles on ProfileStore: session locking, autosave (every 300 s by
-- ProfileStore) and save-on-shutdown (ProfileStore binds BindToClose itself).
-- Studio uses a separate "_dev" store. Key stats are mirrored to Player
-- attributes (+ leaderstats) for the client; those are display-only.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Types = require(Shared.Types)
local Economy = require(Shared.Config.Economy)

local ProfileStore =
	require(ServerScriptService:WaitForChild("ServerPackages"):WaitForChild("ProfileStore")) :: any
local Migrations = require(script.Parent.Parent.Data.Migrations)

type Profile = Types.PlayerProfile
type LoadedCallback = (player: Player, profile: Profile) -> ()

local STORE_NAME = if RunService:IsStudio() then "PlayerData_dev" else "PlayerData"
local KICK_LOAD_FAILED = "Your data couldn't load. Please rejoin in a moment."
local KICK_SESSION_ENDED = "Your data was opened on another server. Please rejoin."

local TEMPLATE: Profile = {
	schema = Migrations.LATEST,
	coins = 0,
	speed = 0,
	rebirths = 0,
	pedestalCount = Economy.PEDESTALS_START,
	pedestals = {},
	lastOnline = 0, -- 0 = never played (no offline income on first join)
	playtimeTotal = 0,
	flags = {},
	index = {},
	shieldUntil = 0,
	stats = { steals = 0, defends = 0, timesRobbed = 0 },
	shop = { cycle = -1, bought = {} },
}

local DataService = {}

local store: any
local sessions: { [Player]: any } = {} -- ProfileStore Profile objects
local loadedCallbacks: { LoadedCallback } = {}
local removingCallbacks: { (player: Player, profile: Profile) -> () } = {}

local function dataOf(player: Player): Profile?
	local session = sessions[player]
	return if session then session.Data :: Profile else nil
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
	local session = store:StartSessionAsync(`Player_{player.UserId}`, {
		Cancel = function()
			return player.Parent ~= Players
		end,
	})
	if session == nil then
		player:Kick(KICK_LOAD_FAILED)
		return
	end

	session:AddUserId(player.UserId) -- GDPR erasure support
	session:Reconcile() -- fill fields added to TEMPLATE since this profile was saved
	local ok, err = pcall(function()
		local migrated = Migrations.run(session.Data)
		session.Data = migrated
	end)
	if not ok then
		warn(`[DataService] migration failed for {player.UserId}: {err}`)
		session:EndSession()
		player:Kick(KICK_LOAD_FAILED)
		return
	end

	session.OnSessionEnd:Connect(function()
		sessions[player] = nil
		player:Kick(KICK_SESSION_ENDED)
	end)

	if player.Parent ~= Players then
		session:EndSession()
		return
	end

	sessions[player] = session
	local profile = session.Data :: Profile
	createLeaderstats(player)
	syncAttributes(player, profile)
	for _, callback in loadedCallbacks do
		task.spawn(callback, player, profile)
	end
end

local function onPlayerRemoving(player: Player)
	local session = sessions[player]
	if not session then
		return
	end
	local profile = session.Data :: Profile
	-- Callbacks run synchronously so their final writes land before the save.
	for _, callback in removingCallbacks do
		local ok, err = pcall(callback :: any, player, profile)
		if not ok then
			warn(`[DataService] removing callback failed: {err}`)
		end
	end
	profile.lastOnline = os.time()
	sessions[player] = nil
	session:EndSession()
end

-- Runs `callback` for every player whose profile is (or becomes) loaded.
function DataService.onLoaded(callback: LoadedCallback)
	table.insert(loadedCallbacks, callback)
	for player, session in sessions do
		task.spawn(callback, player, session.Data :: Profile)
	end
end

-- Runs synchronously right before a leaving player's profile is saved.
function DataService.onRemoving(callback: (player: Player, profile: Profile) -> ())
	table.insert(removingCallbacks, callback)
end

function DataService.get(player: Player): Profile?
	return dataOf(player)
end

function DataService.addCoins(player: Player, delta: number)
	local profile = dataOf(player)
	if not profile then
		return
	end
	profile.coins = math.max(0, profile.coins + delta)
	syncAttributes(player, profile)
end

function DataService.setSpeed(player: Player, value: number)
	local profile = dataOf(player)
	if not profile then
		return
	end
	profile.speed = math.max(0, value)
	syncAttributes(player, profile)
end

function DataService.sync(player: Player)
	local profile = dataOf(player)
	if profile then
		syncAttributes(player, profile)
	end
end

function DataService.init()
	store = ProfileStore.New(STORE_NAME, TEMPLATE)
end

function DataService.start()
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end
end

return DataService

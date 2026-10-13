--!strict
-- Player profiles on ProfileStore: session locking, configured autosave and
-- save-on-shutdown (ProfileStore binds BindToClose itself).
-- Studio uses a separate "_dev" store. Key stats are mirrored to Player
-- attributes (+ leaderstats) for the client; those are display-only.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")
local HttpService = game:GetService("HttpService")
local StudioTestService = game:GetService("StudioTestService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Types = require(Shared.Types)
local Economy = require(Shared.Config.Economy)
local Environment = require(Shared.Config.Environment)

local ProfileStore =
	require(ServerScriptService:WaitForChild("ServerPackages"):WaitForChild("ProfileStore")) :: any
local Migrations = require(script.Parent.Parent.Data.Migrations)
local SaveConfirmation = require(script.Parent.Parent.Data.SaveConfirmation)

type Profile = Types.PlayerProfile
type LoadedCallback = (player: Player, profile: Profile) -> ()

local testArgs = if RunService:IsStudio() then StudioTestService:GetTestArgs() else nil
local preflight = RunService:IsStudio()
	and typeof(testArgs) == "table"
	and testArgs.suite == "preprod"
local STORE_NAME = if preflight
	then "PreflightData_dev"
	else Environment.storeName("PlayerData", RunService:IsStudio(), game.GameId, game.PlaceId)
local function keyFor(userId: number): string
	return if preflight then `QA_{testArgs.runId}_{userId}` else `Player_{userId}`
end
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
	storage = {},
	purchases = {},
	daily = { streak = 0, lastClaimDay = -1 },
	codes = {},
	training = 0,
	uncollectedCoins = 0,
	serverLuckUntil = 0,
	outgoingTransfers = {},
	incomingTransfers = {},
}

local DataService = {}

local store: any
local sessions: { [Player]: any } = {} -- ProfileStore Profile objects
local ready: { [Player]: boolean } = {}
local closing: { [Player]: boolean } = {}
local admitted: { [Player]: boolean } = {}
local loadedCallbacks: { LoadedCallback } = {}
local preloadCallbacks: { LoadedCallback } = {}
local removingCallbacks: { (player: Player, profile: Profile) -> () } = {}
local preflightEvents: { string } = {}
local function tracePreflight(message: string)
	if preflight then
		table.insert(preflightEvents, message)
	end
end

local function dataOf(player: Player): Profile?
	local session = sessions[player]
	return if session and (ready[player] or closing[player]) then session.Data :: Profile else nil
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
	if admitted[player] then
		return
	end
	local count = 0
	for _ in admitted do
		count += 1
	end
	-- Reserve capacity before yielding for data. The world has eight stations.
	if count >= Economy.SERVER_SIZE then
		tracePreflight(`reject {player.UserId}: capacity {count}`)
		player:Kick("This server is full. Please join another server.")
		return
	end
	admitted[player] = true
	tracePreflight(`admit {player.UserId}: previous {count}`)
	local deadline = os.clock() + Economy.PROFILE_LOAD_TIMEOUT_SECONDS
	task.delay(Economy.PROFILE_LOAD_TIMEOUT_SECONDS, function()
		if admitted[player] and not ready[player] and player.Parent == Players then
			tracePreflight(`load timeout {player.UserId}`)
			warn(`[DataService] profile load timed out for {player.UserId}`)
			player:Kick(KICK_LOAD_FAILED)
		end
	end)
	local started, session = pcall(function()
		return store:StartSessionAsync(keyFor(player.UserId), {
			Cancel = function()
				return player.Parent ~= Players or os.clock() >= deadline
			end,
		})
	end)
	if not started or session == nil then
		tracePreflight(`load failed {player.UserId}`)
		if not started then
			warn(`[DataService] profile load failed for {player.UserId}: {session}`)
		end
		admitted[player] = nil
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
		ready[player] = nil
		closing[player] = nil
		player:Kick(KICK_SESSION_ENDED)
	end)

	if player.Parent ~= Players then
		session:EndSession()
		return
	end

	sessions[player] = session
	local profile = session.Data :: Profile
	for _, state in profile.pedestals do
		state.id = state.id or HttpService:GenerateGUID(false)
	end
	for _, state in profile.storage do
		state.id = state.id or HttpService:GenerateGUID(false)
	end
	-- Preload hooks run in order and may yield (e.g. game pass checks) so
	-- every onLoaded callback sees the finished state.
	for _, callback in preloadCallbacks do
		local preloadOk, preloadErr = pcall(callback :: any, player, profile)
		if not preloadOk then
			warn(`[DataService] preload callback failed: {preloadErr}`)
			sessions[player] = nil
			session:EndSession()
			player:Kick(KICK_LOAD_FAILED)
			return
		end
	end
	if sessions[player] ~= session then
		return
	end
	createLeaderstats(player)
	syncAttributes(player, profile)
	ready[player] = true
	for _, callback in loadedCallbacks do
		task.spawn(callback, player, profile)
	end
end

local function onPlayerRemoving(player: Player)
	tracePreflight(`left {player.UserId}`)
	local wasReady = ready[player]
	closing[player] = true
	ready[player] = nil
	admitted[player] = nil
	local session = sessions[player]
	if not session then
		closing[player] = nil
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
	if wasReady then
		profile.lastOnline = os.time()
	end
	sessions[player] = nil
	session:EndSession()
	closing[player] = nil
end

-- Runs `callback` for every player whose profile is (or becomes) loaded.
function DataService.onLoaded(callback: LoadedCallback)
	table.insert(loadedCallbacks, callback)
	for player, session in sessions do
		if ready[player] then
			task.spawn(callback, player, session.Data :: Profile)
		end
	end
end

-- Runs (in registration order, may yield) after load and before onLoaded.
function DataService.onPreload(callback: LoadedCallback)
	table.insert(preloadCallbacks, callback)
end

-- Requests an immediate save (e.g. after granting a Robux purchase).
function DataService.saveNow(player: Player)
	local session = sessions[player]
	if session then
		session:Save()
	end
end

function DataService.awaitReady(player: Player): Profile?
	while player.Parent == Players and not ready[player] do
		task.wait(0.1)
	end
	return if ready[player] then dataOf(player) else nil
end

function DataService.debugPreflightEvents(): { string }
	assert(preflight, "preflight only")
	return table.clone(preflightEvents)
end

function DataService.saveConfirmed(player: Player, predicate: (data: any) -> boolean): boolean
	local session = sessions[player]
	if not session then
		return false
	end
	return SaveConfirmation.wait(
		session,
		predicate,
		function()
			return sessions[player] == session
		end,
		os.clock,
		function(seconds)
			task.wait(seconds)
		end,
		30
	)
end

-- Runs synchronously right before a leaving player's profile is saved.
function DataService.onRemoving(callback: (player: Player, profile: Profile) -> ())
	table.insert(removingCallbacks, callback)
end

function DataService.get(player: Player): Profile?
	return dataOf(player)
end

function DataService.debugReadSaved(userId: number): Profile?
	assert(preflight, "saved fixture inspection is preflight-only")
	local profile = store:GetAsync(keyFor(userId))
	return profile and profile.Data
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
	ProfileStore.SetConstant("AUTO_SAVE_PERIOD", Economy.AUTOSAVE_SECONDS)
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

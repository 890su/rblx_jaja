--!strict
local Players = game:GetService("Players")
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Remotes = require(Shared.Remotes)
local Creatures = require(Shared.Config.Creatures)
local CollectionBook = require(Shared.Util.CollectionBook)
local Types = require(Shared.Types)
local Theme = require(Shared.Theme)
local Locale = require(Shared.Locale)
local Notifier = require(script.Parent.Parent.Util.Notifier)
local Data = require(script.Parent.DataService)
local RateLimit = require(script.Parent.Parent.Util.RateLimit)
local limit = RateLimit.new(4, 1)
local CollectionService = {}
local stateEvent: RemoteEvent
local counts: { [Player]: number } = {}
local function discover(player: Player, profile: Types.PlayerProfile): boolean
	local changed, found = CollectionBook.discover(profile, os.time())
	for _, id in found do
		Notifier.send(
			player,
			"new_creature",
			{ creature = Locale.ref(Theme.CREATURE_NAMES[id]) },
			"success"
		)
	end
	return changed
end
function CollectionService.push(player: Player)
	local profile = Data.get(player)
	if not profile then
		return
	end
	discover(player, profile)
	local discovered: { [string]: boolean } = {}
	local count = 0
	for _, creature in Creatures.LIST do
		if profile.index[creature.id] then
			discovered[creature.id] = true
			count += 1
		end
	end
	counts[player] = count
	player:SetAttribute("IndexCount", count)
	stateEvent:FireClient(player, { discovered = discovered })
end
function CollectionService.init()
	stateEvent = Remotes.event("IndexState")
	Remotes.event("RequestIndex").OnServerEvent:Connect(function(player)
		if limit:allow(player) then
			CollectionService.push(player)
		end
	end)
	Data.onLoaded(CollectionService.push)
	Data.onRemoving(function(player)
		counts[player] = nil
	end)
end
function CollectionService.start()
	while true do
		task.wait(1)
		for _, player in Players:GetPlayers() do
			local profile = Data.get(player)
			if profile then
				local changed = discover(player, profile)
				local count = 0
				for _, creature in Creatures.LIST do
					if profile.index[creature.id] then
						count += 1
					end
				end
				if changed or count ~= counts[player] then
					CollectionService.push(player)
				end
			end
		end
	end
end
return CollectionService

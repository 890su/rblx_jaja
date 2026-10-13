--!strict
-- Friends-in-server tracking for the friend speed bonus (GDD §4.9). Publishes
-- player attribute FriendsInServer, read by SpeedService and the HUD.

local Players = game:GetService("Players")

local FriendService = {}

local friends: { [Player]: { [Player]: boolean } } = {}

local function publish(player: Player)
	local count = 0
	local set = friends[player]
	if set then
		for _ in set do
			count += 1
		end
	end
	player:SetAttribute("FriendsInServer", count)
end

local function isFriends(a: Player, b: Player): boolean
	local ok, result = pcall(function()
		return a:IsFriendsWithAsync(b.UserId)
	end)
	return ok and result == true
end

local function onPlayerAdded(player: Player)
	friends[player] = friends[player] or {}
	for _, other in Players:GetPlayers() do
		if other ~= player and friends[other] and isFriends(player, other) then
			if
				player.Parent ~= Players
				or other.Parent ~= Players
				or not friends[player]
				or not friends[other]
			then
				continue
			end
			friends[player][other] = true
			friends[other][player] = true
			publish(other)
		end
	end
	publish(player)
end

function FriendService.count(player: Player): number
	return (player:GetAttribute("FriendsInServer") :: number?) or 0
end

function FriendService.start()
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(function(player)
		local set = friends[player]
		if set then
			for other in set do
				if friends[other] then
					friends[other][player] = nil
					publish(other)
				end
			end
		end
		friends[player] = nil
	end)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end
end

return FriendService

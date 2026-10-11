--!strict
-- Per-player token bucket for remote handlers.
--   local limit = RateLimit.new(5, 1) -- burst 5, refill 1 token/s
--   if not limit:allow(player) then return end

local Players = game:GetService("Players")

export type Limiter = {
	allow: (self: Limiter, player: Player) -> boolean,
}

local RateLimit = {}

function RateLimit.new(burst: number, refillPerSecond: number): Limiter
	local buckets: { [Player]: { tokens: number, at: number } } = {}
	Players.PlayerRemoving:Connect(function(player)
		buckets[player] = nil
	end)
	local limiter = {}
	function limiter.allow(_self: Limiter, player: Player): boolean
		local now = os.clock()
		local bucket = buckets[player]
		if not bucket then
			bucket = { tokens = burst, at = now }
			buckets[player] = bucket
		end
		bucket.tokens = math.min(burst, bucket.tokens + (now - bucket.at) * refillPerSecond)
		bucket.at = now
		if bucket.tokens < 1 then
			return false
		end
		bucket.tokens -= 1
		return true
	end
	return limiter :: any
end

return RateLimit

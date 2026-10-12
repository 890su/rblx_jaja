--!strict
-- Void Run (GDD §4.5c): a top-down dodge corridor that covers the whole of
-- zone 1. Only eggs from deep zones trigger it, on the way home.
local deepFreeze = require(script.Parent.Parent.Util.deepFreeze)
return deepFreeze({
	FROM_ORIGIN_ZONE = 3, -- eggs picked up in this zone or deeper
	FIELD_ZONE = 1, -- the corridor spans this whole zone
	LANE_WIDTH = 70, -- = plot pitch: eight lanes tile the track, no snapping
	EDGE_MARGIN = 2.5,
	LIVES = 3,
	INVULNERABLE_SECONDS = 1.1,
	-- Corridor run speed: a share of the player's normal WalkSpeed, clamped.
	WALK_SPEED_MIN = 24,
	WALK_SPEED_MAX = 38,
	WALK_SPEED_SHARE = 0.3,
	PLAYER_RADIUS = 1.25,
	STILL_SPEED = 3, -- studs/s under which the player counts as standing still
	SERVER_TICK = 1 / 30,
	LEAD_TIME = 0.25, -- waves start this far in the future (latency cushion)
	FIRST_WAVE_DELAY = 1.6, -- camera rise before the first attack
	AHEAD = 30, -- wave anchor distance in front of the player (toward home)
	MAX_LEVEL = 1.6,
	RETRY_GRACE = 2,
	-- Client camera
	VIEW_WIDTH = 80, -- studs of lane the top-down view must show across
	CAMERA_FOV = 50,
	CAMERA_RISE_SECONDS = 1.4,
	CAMERA_FALL_SECONDS = 0.7,
	CAMERA_LEAD = 12, -- look this far ahead of the player
})

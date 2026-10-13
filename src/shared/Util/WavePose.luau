--!strict
-- Absolute overlay poses: the caller applies them after Animator evaluation.
-- R6 shoulders use different joint axes and have no elbows, wrists or waist.
local Config = require(script.Parent.Parent.Config.Emotes)
local WavePose = {}
local IDENTITY = CFrame.identity

function WavePose.blend(elapsed: number): number
	if elapsed <= 0 or elapsed >= Config.WAVE_DURATION then
		return 0
	end
	local x =
		math.clamp(math.min(elapsed, Config.WAVE_DURATION - elapsed) / Config.FADE_SECONDS, 0, 1)
	return x * x * (3 - 2 * x)
end

function WavePose.sample(elapsed: number, r6: boolean): (CFrame, CFrame, CFrame, CFrame, CFrame)
	local blend = WavePose.blend(elapsed)
	local phase = math.clamp(
		(elapsed - Config.FADE_SECONDS) / (Config.WAVE_DURATION - 2 * Config.FADE_SECONDS),
		0,
		1
	)
	local wave = math.sin(phase * math.pi * 2 * Config.WAVE_CYCLES)
	local shoulder = if r6
		then CFrame.Angles(math.rad(-155 + wave * 9), 0, math.rad(12))
		else CFrame.Angles(math.rad(150), math.rad(wave * 5), math.rad(18))
	local elbow = if r6
		then CFrame.identity
		else CFrame.Angles(math.rad(-40), 0, math.rad(wave * 8))
	local wrist = if r6 then CFrame.identity else CFrame.Angles(0, 0, math.rad(wave * 24))
	local neck = if r6
		then CFrame.Angles(math.rad(-4), 0, math.rad(-6))
		else CFrame.Angles(math.rad(-4), math.rad(6), math.rad(-4))
	local waist = if r6 then CFrame.identity else CFrame.Angles(0, math.rad(-6), math.rad(-3))
	return IDENTITY:Lerp(shoulder, blend),
		IDENTITY:Lerp(elbow, blend),
		IDENTITY:Lerp(wrist, blend),
		IDENTITY:Lerp(neck, blend),
		IDENTITY:Lerp(waist, blend)
end

return table.freeze(WavePose)

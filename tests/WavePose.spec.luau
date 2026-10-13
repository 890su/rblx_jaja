--!strict
local Shared = game:GetService("ReplicatedStorage").Shared
local WavePose = require(Shared.Util.WavePose)
local Config = require(Shared.Config.Emotes)
local passed = 0
local function check(value: boolean)
	assert(value, `wave pose contract {passed + 1}`)
	passed += 1
end
for _, r6 in { true, false } do
	for _, at in { -1, 0, Config.WAVE_DURATION, Config.WAVE_DURATION + 1 } do
		local a, b, c, d, e = WavePose.sample(at, r6)
		check(
			a == CFrame.identity
				and b == CFrame.identity
				and c == CFrame.identity
				and d == CFrame.identity
				and e == CFrame.identity
		)
	end
	local shoulder, elbow, wrist, _, waist = WavePose.sample(1, r6)
	check(shoulder ~= CFrame.identity)
	if r6 then
		check(elbow == CFrame.identity and wrist == CFrame.identity and waist == CFrame.identity)
	else
		check(elbow ~= CFrame.identity and waist ~= CFrame.identity)
	end
end
check(WavePose.blend(Config.FADE_SECONDS) == 1)
check(WavePose.blend(Config.FADE_SECONDS / 2) > 0 and WavePose.blend(Config.FADE_SECONDS / 2) < 1)
return `PASS {passed}`

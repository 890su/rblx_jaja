--!strict
-- Sound effects for server events (Fx remote, notification kinds) and a
-- looping background playlist. Purely cosmetic; all audio is client-side.

local SoundService = game:GetService("SoundService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Sounds = require(Shared.Config.Sounds)
local Remotes = require(Shared.Remotes)

local SoundController = {}

local sfx: { [string]: Sound } = {}

-- Notification keys/kinds that deserve a specific sound.
local KEY_SOUNDS: { [string]: string } = {
	steal_started_victim = "warning",
	steal_started_thief = "whoosh",
	chase_caught_victim = "success",
	chase_caught_thief = "warning",
	shower_started = "impact",
	shower_warning = "warning",
	shop_bought = "purchase",
	pedestal_unlocked = "purchase",
	training_up = "success",
	rebirth_done = "hatch",
	creature_replaced = "coins",
	snatcher_chasing = "warning",
	snatcher_grabbed = "impact",
}
local KIND_SOUNDS: { [string]: string } = {
	pickup = "pickup",
	success = "success",
	coins = "coins",
	warning = "warning",
}

local function make(name: string, def: Sounds.Sound, parent: Instance): Sound
	local sound = Instance.new("Sound")
	sound.Name = name
	sound.SoundId = `rbxassetid://{def.id}`
	sound.Volume = def.volume
	sound.Parent = parent
	return sound
end

function SoundController.play(name: string)
	local sound = sfx[name]
	if sound then
		sound.TimePosition = 0
		sound:Play()
	end
end

local function startMusic(folder: Folder)
	local tracks = {}
	for i, def in Sounds.MUSIC do
		tracks[i] = make(`Music{i}`, def, folder)
	end
	task.spawn(function()
		local index = math.random(1, #tracks)
		while true do
			local track = tracks[index]
			track:Play()
			track.Ended:Wait()
			index = index % #tracks + 1
		end
	end)
end

function SoundController.init()
	local folder = Instance.new("Folder")
	folder.Name = "GameSounds"
	folder.Parent = SoundService
	for name, def in Sounds.SFX do
		sfx[name] = make(name, def, folder)
	end
	startMusic(folder)
end

function SoundController.start()
	Remotes.event("Notify").OnClientEvent:Connect(function(key: string, _args: any, kind: string?)
		local name = KEY_SOUNDS[key] or (kind and KIND_SOUNDS[kind])
		if name then
			SoundController.play(name)
		end
	end)
	Remotes.event("Fx").OnClientEvent:Connect(function(kind: string, position: Vector3?)
		if kind == "hatch" then
			-- Hatches are broadcast to everyone; only play the nearby ones.
			local camera = workspace.CurrentCamera
			if position and camera and (camera.CFrame.Position - position).Magnitude < 80 then
				SoundController.play("hatch")
			end
		elseif kind == "crate" then
			SoundController.play("crate")
		end
	end)
end

return SoundController

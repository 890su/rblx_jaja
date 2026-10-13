--!strict
if not game:GetService("RunService"):IsStudio() then
	return
end
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local remote = ReplicatedStorage:WaitForChild("BiomeQA", 30)
if not remote or not remote:IsA("RemoteEvent") then
	return
end
local Lighting = game:GetService("Lighting")
local CollectionService = game:GetService("CollectionService")
local Biomes = require(ReplicatedStorage.Shared.Theme.Biomes)
local Config = require(ReplicatedStorage.Shared.Config.BiomeAtmosphere)
remote.OnClientEvent:Connect(function(nonce: number, expected: number)
	task.wait(Config.TRANSITION_SECONDS + Config.UPDATE_PERIOD + 0.7)
	local look = if expected == 0 then Biomes.STATION else Biomes.ZONES[expected].look
	local atmosphere = Lighting:FindFirstChild("MeteorAtmosphere") :: Atmosphere?
	local grade = Lighting:FindFirstChild("MeteorGrade") :: ColorCorrectionEffect?
	local emitters = 0
	local pulsing = 0
	for _, instance in CollectionService:GetTagged("BiomePulse") do
		if instance:IsA("BasePart") and instance.Transparency > 0.081 then
			pulsing += 1
		end
	end
	for _, instance in CollectionService:GetTagged("BiomeMotes") do
		if instance:IsA("ParticleEmitter") and instance.Enabled then
			emitters += 1
		end
	end
	local ok = Lighting:GetAttribute("VisualBiome") == expected
		and math.abs(Lighting.ClockTime - look.lighting.ClockTime) < 0.01
		and atmosphere ~= nil
		and math.abs(atmosphere.Density - look.atmosphere.Density) < 0.001
		and grade ~= nil
		and (Vector3.new(grade.TintColor.R, grade.TintColor.G, grade.TintColor.B) - Vector3.new(
			look.grade.TintColor.R,
			look.grade.TintColor.G,
			look.grade.TintColor.B
		)).Magnitude < 0.001
		and emitters <= Config.MAX_EMITTERS
		and (expected < 1 or expected > 3 or emitters > 0)
		and (expected ~= 5 or pulsing > 0)
	remote:FireServer(nonce, {
		ok = ok,
		biome = Lighting:GetAttribute("VisualBiome"),
		emitters = emitters,
		pulsing = pulsing,
		clockTime = Lighting.ClockTime,
		position = game:GetService("Players").LocalPlayer.Character and tostring(
			(game:GetService("Players").LocalPlayer.Character :: Model):GetPivot().Position
		),
		density = atmosphere and atmosphere.Density,
	})
end)

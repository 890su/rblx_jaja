--!strict
-- Local lighting and culled ambience; never changes shared time or movement.
local CollectionService = game:GetService("CollectionService")
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Biomes = require(Shared.Theme.Biomes)
local Config = require(Shared.Config.BiomeAtmosphere)
local BiomeZone = require(Shared.Util.BiomeZone)
local player = Players.LocalPlayer
local Controller = {}
type Effect = {
	part: BasePart,
	emitter: ParticleEmitter?,
	tween: Tween?,
	enabled: boolean,
	transparency: number,
}
local effects: { [Instance]: Effect } = {}
local connections: { RBXScriptConnection } = {}
local transitions: { Tween } = {}
local root: BasePart? = nil
local active = false
local currentZone = -1
local atmosphere: Atmosphere?
local grade: ColorCorrectionEffect?
local transitionInfo =
	TweenInfo.new(Config.TRANSITION_SECONDS, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
local pulseInfo =
	TweenInfo.new(Config.PULSE_SECONDS, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true)

local function removeEffect(instance: Instance)
	local effect = effects[instance]
	if not effect then
		return
	end
	if effect.tween then
		effect.tween:Cancel()
		effect.tween:Destroy()
	end
	if effect.emitter then
		effect.emitter.Enabled = false
	end
	effect.part.Transparency = effect.transparency
	effects[instance] = nil
end
local function addEffect(instance: Instance)
	if effects[instance] then
		return
	end
	if instance:IsA("ParticleEmitter") and instance.Parent and instance.Parent:IsA("BasePart") then
		effects[instance] = {
			part = instance.Parent,
			emitter = instance,
			enabled = false,
			transparency = instance.Parent.Transparency,
		}
	elseif instance:IsA("BasePart") then
		effects[instance] =
			{ part = instance, enabled = false, transparency = instance.Transparency }
	end
end
local function clearTransitions()
	for _, tween in transitions do
		tween:Cancel()
		tween:Destroy()
	end
	table.clear(transitions)
end
local function apply(zone: number)
	clearTransitions()
	local look = if zone == 0 then Biomes.STATION else Biomes.ZONES[zone].look
	for target, properties in
		{
			[Lighting] = look.lighting,
			[atmosphere :: Atmosphere] = look.atmosphere,
			[grade :: ColorCorrectionEffect] = look.grade,
		}
	do
		local tween = TweenService:Create(target, transitionInfo, properties)
		table.insert(transitions, tween)
		tween:Play()
	end
	Lighting:SetAttribute("VisualBiome", zone)
	currentZone = zone
end
local function characterAdded(character: Model)
	root = nil
	local candidate = character:WaitForChild("HumanoidRootPart", 10)
	if active and player.Character == character and candidate and candidate:IsA("BasePart") then
		root = candidate
	end
end
local function cleanup()
	active = false
	for _, connection in connections do
		connection:Disconnect()
	end
	table.clear(connections)
	clearTransitions()
	for instance in effects do
		removeEffect(instance)
	end
	root = nil
end
function Controller.start()
	if active then
		return
	end
	local a = Lighting:WaitForChild("MeteorAtmosphere", 30)
	local g = Lighting:WaitForChild("MeteorGrade", 30)
	if not a or not a:IsA("Atmosphere") or not g or not g:IsA("ColorCorrectionEffect") then
		warn("[MeteorRush] biome lighting unavailable")
		return
	end
	atmosphere, grade = a, g
	active = true
	for _, tag in { "BiomeMotes", "BiomePulse" } do
		table.insert(connections, CollectionService:GetInstanceAddedSignal(tag):Connect(addEffect))
		table.insert(
			connections,
			CollectionService:GetInstanceRemovedSignal(tag):Connect(removeEffect)
		)
		for _, instance in CollectionService:GetTagged(tag) do
			addEffect(instance)
		end
	end
	table.insert(connections, player.CharacterAdded:Connect(characterAdded))
	table.insert(
		connections,
		player.CharacterRemoving:Connect(function()
			root = nil
		end)
	)
	if player.Character then
		task.spawn(characterAdded, player.Character)
	end
	table.insert(connections, script.Destroying:Connect(cleanup))
	local accumulated = 0
	table.insert(
		connections,
		RunService.Heartbeat:Connect(function(dt: number)
			accumulated += dt
			if accumulated < Config.UPDATE_PERIOD then
				return
			end
			accumulated %= Config.UPDATE_PERIOD
			local position = if root then root.Position else nil
			local zone = if position then BiomeZone.at(position.Z, currentZone) else 0
			if zone ~= currentZone then
				apply(zone)
			end
			local emitters = 0
			for _, effect in effects do
				local enabled = position ~= nil
					and (effect.part.Position - (position :: Vector3)).Magnitude
						< Config.EFFECT_DISTANCE
				if effect.emitter and enabled then
					emitters += 1
					enabled = emitters <= Config.MAX_EMITTERS
				end
				if enabled ~= effect.enabled then
					effect.enabled = enabled
					if effect.emitter then
						effect.emitter.Enabled = enabled
					elseif enabled then
						local tween = TweenService:Create(
							effect.part,
							pulseInfo,
							{ Transparency = Config.PULSE_TRANSPARENCY }
						)
						effect.tween = tween
						tween:Play()
					elseif effect.tween then
						effect.tween:Cancel()
						effect.tween:Destroy()
						effect.tween = nil
						effect.part.Transparency = effect.transparency
					end
				end
			end
		end)
	)
end
return Controller

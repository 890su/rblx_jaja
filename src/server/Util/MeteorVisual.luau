--!strict
-- Puts the meteor mesh (ReplicatedStorage.Assets.Meteor) inside a meteor part,
-- turning the neon ball into a translucent rarity aura. Falls back to the plain
-- ball when the asset is missing. `welded` = for parts that move (carried).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MeteorVisual = {}

function MeteorVisual.attach(part: BasePart, welded: boolean, scale: number?)
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local template = assets and assets:FindFirstChild("Meteor")
	if not template or not template:IsA("Model") then
		return
	end
	local model = template:Clone()
	model.Name = "Mesh"
	if scale then
		model:ScaleTo(model:GetScale() * scale)
	end
	model:PivotTo(part.CFrame)
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.CanCollide = false
			descendant.CanQuery = false
			descendant.CanTouch = false
			descendant.Massless = true
			if welded then
				descendant.Anchored = false
				local weld = Instance.new("WeldConstraint")
				weld.Part0 = descendant
				weld.Part1 = part
				weld.Parent = descendant
			end
		end
	end
	part.Transparency = 0.86
	part.Size = part.Size * 1.15
	model.Parent = part
end

return MeteorVisual

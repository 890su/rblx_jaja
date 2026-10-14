--!strict
-- Small vector icons: no asset download, font glyph, or locale dependency.
local Icons = {}
function Icons.new(parent: Instance, kind: string, color: Color3): Frame
	local root = Instance.new("Frame")
	root.Name, root.BackgroundTransparency = "Icon", 1
	root.Size = UDim2.fromOffset(24, 24)
	root.Parent = parent
	local function shape(
		x: number,
		y: number,
		w: number,
		h: number,
		round: number?,
		hollow: boolean?
	): Frame
		local f = Instance.new("Frame")
		f.Position, f.Size = UDim2.fromScale(x, y), UDim2.fromScale(w, h)
		f.BorderSizePixel, f.BackgroundColor3 = 0, color
		f.Parent = root
		if round then
			local corner = Instance.new("UICorner")
			corner.CornerRadius, corner.Parent = UDim.new(round, 0), f
		end
		if hollow then
			f.BackgroundTransparency = 1
			local stroke = Instance.new("UIStroke")
			stroke.Color, stroke.Thickness, stroke.Parent = color, 2, f
		end
		return f
	end
	if kind == "Speed" then
		-- A lightning bolt built from two diagonal bars and a connecting bar.
		shape(0.40, 0.05, 0.18, 0.48, 0.1).Rotation = 30
		shape(0.30, 0.43, 0.42, 0.15, 0.1)
		shape(0.43, 0.49, 0.18, 0.48, 0.1).Rotation = 30
	elseif kind == "Coins" then
		shape(0.12, 0.12, 0.76, 0.76, 0.5, true)
		shape(0.28, 0.28, 0.44, 0.44, 0.5, true)
		shape(0.46, 0.34, 0.08, 0.32, 0.2)
	elseif kind == "Shop" or kind == "Store" then
		shape(0.16, 0.30, 0.68, 0.56, 0.15, true)
		shape(0.32, 0.10, 0.36, 0.32, 0.5, true)
		if kind == "Store" then
			shape(0.43, 0.47, 0.14, 0.22, 0.2)
		end
	elseif kind == "Station" then
		shape(0.10, 0.70, 0.80, 0.13, 0.2)
		shape(0.19, 0.42, 0.15, 0.24, 0.1)
		shape(0.43, 0.17, 0.15, 0.49, 0.1)
		shape(0.68, 0.32, 0.15, 0.34, 0.1)
	elseif kind == "Index" then
		shape(0.15, 0.15, 0.70, 0.72, 0.1, true)
		shape(0.48, 0.17, 0.07, 0.68)
		shape(0.24, 0.31, 0.15, 0.06)
		shape(0.24, 0.48, 0.15, 0.06)
		shape(0.63, 0.31, 0.13, 0.06)
	elseif kind == "Upgrades" or kind == "Rebirth" then
		shape(0.42, 0.25, 0.16, 0.60, 0.1)
		shape(0.26, 0.21, 0.16, 0.46, 0.1).Rotation = 45
		shape(0.58, 0.21, 0.16, 0.46, 0.1).Rotation = -45
	elseif kind == "Daily" then
		shape(0.15, 0.30, 0.70, 0.57, 0.08, true)
		shape(0.10, 0.28, 0.80, 0.16, 0.1)
		shape(0.45, 0.20, 0.10, 0.65)
		shape(0.23, 0.09, 0.27, 0.24, 0.5, true)
		shape(0.50, 0.09, 0.27, 0.24, 0.5, true)
	elseif kind == "Invite" or kind == "Chat" then
		shape(0.23, 0.12, 0.42, 0.38, 0.5, true)
		shape(0.12, 0.57, 0.62, 0.30, 0.5, true)
		shape(0.77, 0.46, 0.08, 0.34)
		shape(0.64, 0.59, 0.34, 0.08)
	elseif kind == "Wave" then
		shape(0.30, 0.38, 0.43, 0.48, 0.4)
		for i = 0, 3 do
			shape(0.30 + i * 0.12, 0.07 + math.abs(1 - i) * 0.04, 0.09, 0.42, 0.5)
		end
		shape(0.12, 0.42, 0.12, 0.40, 0.5).Rotation = -30
	elseif kind == "Close" then
		shape(0.43, 0.10, 0.13, 0.80, 0.3).Rotation = 45
		shape(0.43, 0.10, 0.13, 0.80, 0.3).Rotation = -45
	elseif kind == "Back" then
		shape(0.28, 0.16, 0.13, 0.46, 0.3).Rotation = 45
		shape(0.28, 0.43, 0.13, 0.46, 0.3).Rotation = -45
	else
		for x = 0, 1 do
			for y = 0, 1 do
				shape(0.12 + x * 0.44, 0.12 + y * 0.44, 0.30, 0.30, 0.2, true)
			end
		end
	end
	return root
end
return Icons

--!strict
-- Single registry of remotes. The server creates every RemoteEvent listed in
-- EVENT_NAMES; clients wait for them. Payload validation is the receiving
-- service's job — never trust client arguments.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local FOLDER_NAME = "Remotes"

-- Add names here as systems land (see docs/02-development-plan.md milestones).
local EVENT_NAMES: { string } = {
	"Notify", -- server -> client: (message: string, kind: string?)
	"ShopState", -- server -> client: (state: Types.ShopState)
	"ShopBuy", -- client -> server: (slot: number)
	"BuyPedestal", -- client -> server: ()
	"Rebirth", -- client -> server: ()
	"Fx", -- server -> client: (kind: string, position: Vector3, extra: any)
	"ClaimDaily", -- client -> server: ()
	"RedeemCode", -- client -> server: (code: string)
}

local Remotes = {}

local folder: Folder
if RunService:IsServer() then
	local existing = ReplicatedStorage:FindFirstChild(FOLDER_NAME)
	if existing and existing:IsA("Folder") then
		folder = existing
	else
		folder = Instance.new("Folder")
		folder.Name = FOLDER_NAME
		folder.Parent = ReplicatedStorage
	end
	for _, name in EVENT_NAMES do
		if not folder:FindFirstChild(name) then
			local remote = Instance.new("RemoteEvent")
			remote.Name = name
			remote.Parent = folder
		end
	end
else
	folder = ReplicatedStorage:WaitForChild(FOLDER_NAME) :: Folder
end

function Remotes.event(name: string): RemoteEvent
	assert(table.find(EVENT_NAMES, name), `Unknown remote: {name}`)
	return folder:WaitForChild(name) :: RemoteEvent
end

return table.freeze(Remotes)

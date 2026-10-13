--!strict
-- Pure journal decisions and atomic profile mutations. Journal decisions never
-- change after commit/cancel; both profiles persist an intent before commit.
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Types = require(Shared.Types)
type Intent = Types.TransferIntent
type Profile = Types.PlayerProfile
export type Record = { intent: Intent, phase: string }

local Transfers = {}

function Transfers.decide(current: Record?, intent: Intent, phase: string): Record
	assert(
		phase == "pending" or phase == "cancelled" or phase == "committed",
		"invalid transfer phase"
	)
	if current then
		assert(
			current.intent.ownerUserId == intent.ownerUserId
				and current.intent.recipientUserId == intent.recipientUserId
				and current.intent.state.id == intent.state.id,
			"transfer identity mismatch"
		)
		if current.phase ~= "pending" or phase == "pending" then
			return current
		end
	end
	-- A missing reservation can only be created pending/cancelled, never committed.
	assert(current ~= nil or phase ~= "committed", "missing transfer reservation")
	return { intent = intent, phase = phase }
end

function Transfers.restore(profile: Profile, id: string)
	local intent = profile.outgoingTransfers[id]
	if not intent then
		return
	end
	if
		not profile.pedestals[intent.slot]
		and tonumber(intent.slot)
		and (tonumber(intent.slot) :: number) <= profile.pedestalCount
	then
		profile.pedestals[intent.slot] = table.clone(intent.state)
	else
		table.insert(profile.storage, table.clone(intent.state))
	end
	profile.outgoingTransfers[id] = nil
end

function Transfers.apply(
	profile: Profile,
	id: string,
	capacity: number,
	preferredSlot: number?
): boolean
	local intent = profile.incomingTransfers[id]
	if not intent then
		return false
	end
	if intent.applied then
		return true
	end
	local slot = preferredSlot
	if slot == nil then
		for i = 1, capacity do
			if not profile.pedestals[tostring(i)] then
				slot = i
				break
			end
		end
	end
	if slot and slot >= 1 and slot <= capacity and slot % 1 == 0 then
		local key = tostring(slot)
		local previous = profile.pedestals[key]
		if previous then
			table.insert(profile.storage, previous)
		end
		profile.pedestals[key] = table.clone(intent.state)
	else
		table.insert(profile.storage, table.clone(intent.state))
	end
	intent.applied = true -- persisted in the same snapshot as the item
	return true
end

return Transfers

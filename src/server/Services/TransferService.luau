--!strict
-- Cross-profile transfers use a durable per-transfer journal. Never restore an
-- item on an unknown datastore result: retain escrow for recovery on next join.
local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Types = require(Shared.Types)
local Environment = require(Shared.Config.Environment)
local DataService = require(script.Parent.DataService)
local StationService = require(script.Parent.StationService)
local Transfers = require(script.Parent.Parent.Data.Transfers)
type Intent = Types.TransferIntent

local TransferService = {}
local journal = DataStoreService:GetDataStore(
	Environment.storeName("Transfers", RunService:IsStudio(), game.GameId, game.PlaceId)
)

local function decide(id: string, intent: Intent, phase: string): Transfers.Record?
	for attempt = 1, 4 do
		local ok, result = pcall(function()
			return journal:UpdateAsync(id, function(current)
				return Transfers.decide(current, intent, phase)
			end)
		end)
		if ok then
			return result :: Transfers.Record
		end
		warn(`[Transfers] {id} {phase} failed: {result}`)
		if attempt < 4 then
			task.wait(2 ^ (attempt - 1))
		end
	end
	return nil
end

function TransferService.cancel(owner: Player, id: string): boolean
	local profile = DataService.get(owner)
	local intent = profile and profile.outgoingTransfers[id]
	if not profile or not intent then
		return false
	end
	local record = decide(id, intent, "cancelled")
	if not record or DataService.get(owner) ~= profile then
		return false
	end
	if record.phase == "cancelled" then
		Transfers.restore(profile, id)
	else
		profile.outgoingTransfers[id] = nil
	end
	StationService.refresh(owner)
	DataService.saveNow(owner)
	return record.phase == "cancelled"
end

function TransferService.reserve(
	owner: Player,
	recipient: Player,
	slot: string
): (string?, Types.PedestalState?)
	local profile = DataService.get(owner)
	local state = profile and profile.pedestals[slot]
	if not profile or not state then
		return nil, nil
	end
	if
		state.paid
		and (
			owner:GetAttribute("PaidItemTradingAllowed") ~= true
			or recipient:GetAttribute("PaidItemTradingAllowed") ~= true
		)
	then
		return nil, nil
	end
	local id = HttpService:GenerateGUID(false)
	state.id = state.id or HttpService:GenerateGUID(false)
	local intent: Intent = {
		state = table.clone(state),
		ownerUserId = owner.UserId,
		recipientUserId = recipient.UserId,
		slot = slot,
	}
	profile.pedestals[slot] = nil
	profile.outgoingTransfers[id] = intent
	StationService.refresh(owner)
	if
		not DataService.saveConfirmed(owner, function(saved)
			return saved.outgoingTransfers[id] ~= nil
		end)
	then
		TransferService.cancel(owner, id)
		return nil, nil
	end
	local record = decide(id, intent, "pending")
	if not record or record.phase ~= "pending" or DataService.get(owner) ~= profile then
		TransferService.cancel(owner, id)
		return nil, nil
	end
	return id, table.clone(intent.state)
end

function TransferService.complete(
	owner: Player,
	recipient: Player,
	id: string,
	preferredSlot: number?
): boolean
	local ownerProfile, profile = DataService.get(owner), DataService.get(recipient)
	local intent = ownerProfile and ownerProfile.outgoingTransfers[id]
	if
		not ownerProfile
		or not profile
		or not intent
		or intent.recipientUserId ~= recipient.UserId
	then
		return false
	end
	-- No callback yields between adding intent and saving: the recipient is
	-- always recoverable before the journal can become committed.
	profile.incomingTransfers[id] = profile.incomingTransfers[id] or table.clone(intent)
	if
		not DataService.saveConfirmed(recipient, function(saved)
			return saved.incomingTransfers[id] ~= nil
		end)
	then
		return false
	end
	local record = decide(id, intent, "committed")
	if not record or DataService.get(recipient) ~= profile then
		return false
	end
	if record.phase ~= "committed" then
		profile.incomingTransfers[id] = nil
		return false
	end
	Transfers.apply(profile, id, StationService.capacity(recipient, profile), preferredSlot)
	StationService.refresh(recipient)
	if
		not DataService.saveConfirmed(recipient, function(saved)
			local savedIntent = saved.incomingTransfers[id]
			return savedIntent ~= nil and savedIntent.applied == true
		end)
	then
		return false
	end
	profile.incomingTransfers[id] = nil
	if DataService.get(owner) == ownerProfile then
		ownerProfile.outgoingTransfers[id] = nil
		DataService.saveNow(owner)
	end
	DataService.saveNow(recipient)
	return true
end

function TransferService.init()
	DataService.onPreload(function(player, profile)
		for id, intent in profile.outgoingTransfers do
			local record = decide(id, intent, "cancelled")
			assert(record, "transfer recovery unavailable")
			if record.phase == "cancelled" then
				Transfers.restore(profile, id)
			else
				profile.outgoingTransfers[id] = nil
			end
		end
		for id, intent in profile.incomingTransfers do
			local record = decide(id, intent, "cancelled")
			assert(record, "transfer recovery unavailable")
			if record.phase == "committed" then
				Transfers.apply(profile, id, StationService.capacity(player, profile))
			end
			profile.incomingTransfers[id] = nil
		end
	end)
	DataService.onRemoving(function(player, profile)
		for id in profile.outgoingTransfers do
			TransferService.cancel(player, id)
		end
	end)
end

return TransferService

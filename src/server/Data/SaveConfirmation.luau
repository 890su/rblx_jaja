--!strict
-- Save() is asynchronous. Only the persisted snapshot can acknowledge a grant.
local SaveConfirmation = {}

function SaveConfirmation.wait(
	session: any,
	predicate: (data: any) -> boolean,
	current: () -> boolean,
	now: () -> number,
	pause: (number) -> (),
	timeout: number
): boolean
	local deadline = now() + timeout
	local nextSave = -math.huge
	while current() and session:IsActive() do
		if session.LastSavedData and predicate(session.LastSavedData) then
			return true
		end
		if now() >= deadline then
			return false
		end
		if now() >= nextSave then
			session:Save()
			nextSave = now() + 5
		end
		pause(0.1)
	end
	return false
end

return SaveConfirmation

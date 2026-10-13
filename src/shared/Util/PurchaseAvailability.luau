--!strict
local Availability = {}
export type State = {
	configured: boolean,
	loaded: boolean,
	failed: boolean,
	owned: boolean,
	policyReady: boolean,
	restricted: boolean,
	applicable: boolean,
	prompting: boolean,
}
function Availability.status(state: State): string
	if state.owned then
		return "owned"
	end
	if not state.configured or state.failed then
		return "unavailable"
	end
	if not state.loaded or not state.policyReady then
		return "loading"
	end
	if state.restricted then
		return "restricted"
	end
	if not state.applicable then
		return "unavailable"
	end
	if state.prompting then
		return "pending"
	end
	return "ready"
end
return Availability

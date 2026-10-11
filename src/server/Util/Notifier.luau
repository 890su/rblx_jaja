--!strict
-- Sends localized notifications: a Locale key + args, rendered on the client in
-- the player's language (see shared/Locale). Use Locale.ref(term) for args that
-- are translatable terms (creature names, rarities, zones).

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Locale = require(Shared.Locale)
local Remotes = require(Shared.Remotes)

local Notifier = {}

function Notifier.send(player: Player, key: string, args: Locale.Args?, kind: string?)
	Remotes.event("Notify"):FireClient(player, key, args or {}, kind)
end

function Notifier.all(key: string, args: Locale.Args?, kind: string?)
	Remotes.event("Notify"):FireAllClients(key, args or {}, kind)
end

return Notifier

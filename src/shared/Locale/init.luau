--!strict
-- Localization (English source). Every player-facing sentence is a keyed
-- template with {named} parameters; standalone words (creature names,
-- rarities, zones, product names...) are TERMS translated as-is.
--
-- * Server sends (key, args) to clients; it never sends finished sentences.
-- * Client renders with Locale.t(key, args): Roblox Translator.FormatByKey for
--   the player's language (cloud localization table, AI auto-translated), with
--   an English fallback when a key isn't uploaded yet.
-- * An arg value "@Some Term" (or a list of them) is translated as a term.
-- * Locale.csv() produces the table to upload (Creator Hub → Localization →
--   Table management → Upload CSV). Regenerate after adding strings:
--   run it in Studio via MCP (see scripts/export_locale_csv.py).

local LocalizationService = game:GetService("LocalizationService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Theme = require(script.Parent.Theme)

export type Args = { [string]: any }

local STRINGS: { [string]: string } = {
	odds_first_pickup_context = "First pickup guarantee",
	facility_offer = "{name} · {amount} Stardust",
	facility_build = "Build · {amount}",
	facility_ready = "Built",
	facility_unbuilt = "Not built yet",
	warehouse_build_hint = "Build your storage locker for {amount} Stardust to manage creatures",
	warehouse_required = "Your pedestals are full. Build storage or unlock another pedestal",
	warehouse_approach = "Approach the storage terminal on your plot to manage creatures",
	warehouse_stored = "Creature safely stored. It earns Stardust when placed on a pedestal",
	warehouse_swap_preview = "Slot {slot}: {incoming} in · {outgoing} goes to storage",
	warehouse_place_preview = "Slot {slot}: place {incoming} here",
	warehouse_store_preview = "Slot {slot} · {name} can move to storage without selling",
	warehouse_hint = "Select a pedestal to store its creature, or choose a stored creature and its destination",
	ui_station_compact_title = "Station · {used}/{capacity}",
	ui_station_hint = "1. Select a slot   2. Select a stored creature   3. Swap — the old creature stays in storage",
	ui_station_pick_storage = "Slot {slot} · {name} — select a stored creature to swap",
	ui_station_swap_preview = "Slot {slot} → {name} · the old creature stays in storage",
	ui_collection_progress = "{count} of {total} creatures discovered",
	ui_collection_empty = "No discoveries yet. Bring a meteor home and hatch it to reveal a creature",
	upgrade_max = "This upgrade is already at its maximum level",
	purchase_credit_saved = "Purchase saved as a credit. Use it in Store when eligible eggs or stock are available",
	purchase_use_credit = "Use credit · {count}",
	upgrade_bought = "{name} upgraded to level {level}",
	upgrade_level = "Level {level}",
	upgrade_buy = "Upgrade · {amount} Stardust",
	upgrade_treadmill_effect = "x{rate} base Speed per second; training and passes also apply",
	upgrade_carry_effect = "Carry at {rate}% of your running speed",
	upgrade_training_effect = "+{bonus}% to all Speed gains",
	upgrade_pedestal_effect = "{count} unlocked pedestals",
	index_summary = "{count}/{total} discovered · discoveries stay after selling or theft",
	index_field_locked = "{rarity} · first field zone {zone} · collect and hatch to reveal",
	index_field_detail = "{rarity} · first field zone {zone} · base +{income}/s",
	purchase_loading = "Loading price…",
	purchase_unavailable = "Unavailable",
	purchase_prompt_failed = "Purchase window could not open. Try again",
	steal_paid_restricted = "This creature cannot be transferred between these accounts",
	steal_reserving = "Securing the creature… stay near the pedestal",
	emote_wave = "Wave",
	emote_wave_keyboard = "Wave · G",
	emote_stop = "Stop gesture",
	odds_context = "{zone} · {canyon} · {event} · {index}/{count} →",
	luck_odds_legend = "Each outcome: current chance → chance with Server Luck",
	luck_odds_row = "{name} {mutation}: {before} → {after}",
	luck_first_visit = "Your first field pickup in Zone 2 is at least Rare. Species and Golden chances use the same rolls.",
	purchase_delivered = "Purchase delivered! Your creatures are safe in your station or storage",

	purchase_restricted = "This purchase is unavailable for your account",
	purchase_fixed_reward = "Purchase delivered as guaranteed Cosmic Leviathan creatures",
	transfer_pending = "Your creature is reserved safely. Rejoin if the transfer cannot finish",
	arena_prep = "Void Run in {meters} m — get ready!",
	arena_status = "{hearts}  ·  {meters} m to home",
	arena_cleared = "Void Run cleared! Your egg made it home",
	arena_failed = "Knocked out! Your egg dropped here — grab it and run again",
	-- Carry / meteors
	pedestals_full = "All pedestals are full!",
	station_full_manual_hint = "Station full! Hold E at a creature to replace it; the old one stays in storage. Or open Station",
	storage_manage = "{count} stored creatures · open Station",
	station_manage_home = "Return to your station to manage creatures",
	station_swapped = "Creature exchanged — the old one is safe in storage",
	station_sold = "Creature sold for {amount} Stardust",
	station_changed = "Your station changed. Select the creature again",
	station_carry_replaced = "Meteor placed! The previous creature is safe in storage",
	station_slot_income = "Slot {slot} · +{amount}/s",
	station_slot_name = "{slot}. {name}",
	station_summary = "{used}/{capacity} slots · {stored} in storage",
	station_item_income = "+{amount}/s{mutation}",
	station_item_hatching = "Hatching · {time}",
	station_sell_button = "Sell for {amount}",
	station_confirm_sell = "Confirm sale · {amount}",
	station_selection = "Selected slot {slot} · {name}",
	snatcher_chasing = "Egg guard alerted! Yellow lane = incoming dash. Step sideways!",
	snatcher_grabbed = "Dash hit! Your egg dropped here — pick it up to retry",
	egg_reclaim = "A drone is coming for your egg — grab it before it's flown away!",
	guard_spotted = "A guard heard you! Stay out of its beam: one look and it gives chase",
	hound_summoned = "A Void Hound tore through a portal! Watch for its yellow pounce lane",
	creature_replaced = "Replaced {old} (+{amount} Stardust) — your station got stronger!",
	meteor_pickup = "{rarity} Meteor{odds}! Bring it home",
	meteor_placed = "{rarity} Meteor placed — hatching!",
	-- Events
	shower_started = "Meteor Shower! Boosted meteors in the deep zones",
	shower_warning = "Meteor Shower in {seconds} seconds!",
	craters_shifted = "The craters shifted! New canyon paths today",
	-- Monetization
	starter_pack = "Starter Pack unlocked! Enjoy your new creatures",
	shielded = "Station shielded for 15 minutes",
	all_hatched = "Everything hatched!",
	shop_refilled = "Your Meteor Shop stock is refilled",
	server_luck = "{player} activated Server Luck! x2 rare meteors",
	crate_result = "Crate: {list}",
	pass_unlocked = "{pass} unlocked!",
	-- Rebirth
	rebirth_need_speed = "Rebirth needs {amount} Speed",
	rebirth_need_coins = "Rebirth needs {amount} Stardust",
	rebirth_done = "Rebirth {count}! Permanent bonus unlocked",
	-- Rewards
	daily_claimed = "Day {day} reward claimed!",
	code_invalid = "That code doesn't work",
	code_used = "You already used this code",
	code_redeemed = "Code redeemed!",
	-- Shop
	shop_sold_out = "Sold out — wait for the restock",
	not_enough_coins = "Not enough Stardust",
	shop_bought = "Bought {rarity} Meteor ({creature}) — hatching!",
	shop_bought_storage = "Bought {creature} — kept in storage. Open Station to place it",
	pedestals_all_unlocked = "All pedestals unlocked",
	need_coins = "Need {amount} Stardust",
	pedestal_unlocked = "Pedestal {number} unlocked!",
	shop_restocked = "The Meteor Shop restocked!",
	training_up = "Run Training level {level}! +{bonus}% speed gain",
	training_button = "Run Training {level} → {next} · {amount} Stardust",
	-- Station / speed
	speed_training = "{source} · +{gain}/s · Pace {pace}",
	zone_locked = "{zone} needs {speed} Speed",
	welcome_back = "Welcome back! Your creatures made {amount} Stardust",
	coins_collected = "+{amount} Stardust",
	new_creature = "New creature: {creature}!",
	-- Stealing
	steal_cant = "Can't steal here",
	steal_nothing = "Nothing to steal",
	steal_hands_full = "Your hands are full",
	steal_too_far = "Too far away",
	steal_hold = "Hold to steal",
	steal_full = "Your pedestals are full",
	steal_locked = "{player}'s Station is locked",
	steal_protected = "{player} is protected (new player)",
	steal_wait = "Wait {seconds}s to steal again",
	steal_recent = "You robbed {player} recently",
	steal_mythic = "That Mythic is protected",
	creature_returned = "Your {creature} came back home!",
	steal_success = "You stole {creature}!",
	steal_got_away = "{player} got away with your {creature}",
	steal_owner_left = "{player} left — the creature went home with them",
	steal_started_thief = "Stolen {creature}! Run home before {player} catches you!",
	steal_started_victim = "{player} stole your {creature}! Catch them!",
	chase_caught_victim = "Caught {player}! {creature} is back",
	chase_caught_thief = "{player} caught you!",
	-- HUD / menus
	hud_carrying = "Carrying {rarity} Meteor — run home!",
	amount_coins = "{amount} Stardust",
	shop_restock_in = "Restock in {time}",
	shop_left = "{count} left",
	pedestal_unlock_button = "Unlock pedestal {number} · {amount} Stardust",
	rebirth_count = "Rebirths: {count}",
	rebirth_speed = "Speed: {have} / {need}",
	rebirth_coins = "Stardust: {have} / {need}",
	rebirth_reward = "Reward: +{income}% income, +{speed}% speed gain",
	rebirth_unlocks = "Unlocks {zone}",
	shower_now = "Meteor Shower NOW · {time}",
	shower_in = "Meteor Shower in {time}",
	daily_claim = "Claim day {day}",
	daily_day = "Day {day}",
	-- Tutorial
	tutorial_gate = "Reach {speed} Speed to open {zone} — rarer Meteors!",
	-- Store / odds
	odds_title = "{name} · odds",
	price_robux = "R$ {price}",
	odds_button = "Odds · R$ {price}",
	odds_buy = "Buy · R$ {price}",
	odds_total = "Total: {pct} · each crate item is rolled independently",
	-- New keys avoid stale cloud translations of the previous home-zone and
	-- non-Common boost rules while updated translations are being uploaded.
	luck_zone_effect = "Effect: x{boost} weight for rarities above each zone's minimum for {minutes} min. The minimum rarity is not boosted.",
}

-- Fixed words and sentences shown as-is (auto-translated when displayed).
local STATIC_TERMS: { string } = {
	"Explore",
	"Progress",
	"Social",
	"Collection",
	"Robux",
	"Robux Store",
	"Permanent perks",
	"One-time purchases",
	"All",
	"Discovered",
	"Claimed",
	"Menu",
	"More",
	"Undiscovered",
	"Chat",
	"Hide chat",
	"Creature Index",
	"Upgrades",
	"Upgrades · Treadmill · Carry speed",
	"Back to Shop",
	"Run Training",
	"Carry speed",
	"Pedestals",
	"Max level",
	"Training improves all Speed gains",
	"Build a treadmill, then improve its idle Speed gain",
	"Build a locker to store and exchange your creatures",
	"Build",
	"Move faster while carrying an egg or stolen creature",
	"Unlock another slot for creature income",
	"Canyon",
	"Field",
	"Normal",
	"VOID RUN",
	"RECLAIMING",
	"HUNTING",
	"RETURNING EGG",
	"Dodge the attacks! Yellow marks warn you.",
	"BLUE: stand still!",
	"Stay in your lane. Attacks start at the orange line!",
	"ORANGE: keep moving!",
	"Meteor",
	"Station",
	"Speed",
	"Idle",
	"Running",
	"Treadmill",
	"OFFLINE",
	"ACTIVE",
	"Hatching",
	"Ready",
	"EGG GUARD",
	"DODGE!",
	"ATTACK",
	"RECHARGING",
	"CHASING",
	"Stardust",
	"Golden",
	"Starborn",
	"Shop",
	"Rebirth",
	"Rebirth!",
	"Store",
	"Daily",
	"Daily (!)",
	"Invite +10%",
	"Meteor Shop",
	"Daily Rewards",
	"Enter code",
	"Redeem",
	"Buy",
	"Buy to storage",
	"Sold out",
	"Too pricey",
	"All pedestals unlocked",
	"Run Training maxed",
	"Unlock",
	"Station Expansion",
	"Will replace",
	"Suggested replacement",
	"Replace (keep old in storage)",
	"Station management",
	"Select a slot, then a creature from storage. The old creature is kept.",
	"Select a creature from storage",
	"Storage is empty",
	"Swap selected creature",
	"Select a slot first",
	"Station slots",
	"Storage",
	"Manage creatures",
	"Move to storage",
	"Place creature",
	"Home",
	"Safe station area",
	"Canyon entrances",
	"CRATER FIELD",
	"Meteors this way",
	"Your creatures earn Stardust",
	"Collect Stardust",
	"TREADMILL",
	"+Speed while you stand here",
	"Got it!",
	"How to play",
	"Run! Every second you get faster",
	"Grab meteors on the track and carry them home",
	"They hatch into creatures that earn Stardust",
	"Watch out for Void Snatchers — and other players!",
	"Owned",
	"Coming soon",
	"Odds",
	"Grab",
	"Steal",
	"Empty",
	"Locked",
	"Collect",
	"TREADMILL · stand here for Speed",
	"Come back tomorrow!",
	"Resets Speed and Stardust. Creatures stay.",
	"Run onto the track! Your Speed grows every second",
	"Grab a glowing Meteor on the track",
	"Bring it home! Follow the green arrow",
	"Your creatures earn Stardust. Step on the yellow pad to collect",
}

local Locale = {}

Locale.STRINGS = STRINGS

local translator: Translator? = nil
local translatorRequested = false

local function getTranslator(): Translator?
	if translator or translatorRequested or not RunService:IsClient() then
		return translator
	end
	translatorRequested = true
	task.spawn(function()
		local ok, result = pcall(function()
			return LocalizationService:GetTranslatorForPlayerAsync(Players.LocalPlayer)
		end)
		if ok then
			translator = result
		end
	end)
	return nil
end

-- English template substitution (also the fallback path).
local function substitute(template: string, args: { [string]: string }): string
	return (template:gsub("{(%w+)}", function(name)
		return args[name] or `\{{name}\}`
	end))
end

-- Translates a standalone term for the local player (client); identity on server.
function Locale.term(text: string): string
	local t = getTranslator()
	if t then
		local ok, result = pcall(function()
			return t:Translate(game, text)
		end)
		if ok and result ~= "" then
			return result
		end
	end
	return text
end

local function resolveArg(value: any): string
	if type(value) == "table" then
		local parts = {}
		for _, item in value do
			table.insert(parts, resolveArg(item))
		end
		return table.concat(parts, ", ")
	end
	local text = tostring(value)
	if text:sub(1, 1) == "@" then
		return Locale.term(text:sub(2))
	end
	return text
end

-- Renders a keyed template in the local player's language.
function Locale.t(key: string, args: Args?): string
	local resolved: { [string]: string } = {}
	if args then
		for name, value in args do
			resolved[name] = resolveArg(value)
		end
	end
	local t = getTranslator()
	if t then
		local ok, result = pcall(function()
			return t:FormatByKey(key, resolved)
		end)
		if ok and result ~= "" then
			return result
		end
	end
	local template = STRINGS[key]
	return if template then substitute(template, resolved) else key
end

-- Marks a value as a term to translate on the client: Locale.ref("Comet Cat").
function Locale.ref(text: string): string
	return "@" .. text
end

-- All terms: static words + theme names (creatures, zones, rarities).
function Locale.terms(): { string }
	local list = table.clone(STATIC_TERMS)
	for _, name in Theme.CREATURE_NAMES do
		table.insert(list, name)
	end
	for _, name in Theme.ZONE_NAMES do
		table.insert(list, name)
	end
	for rarity in Theme.RARITY_COLORS :: { [string]: Color3 } do
		table.insert(list, rarity)
	end
	return list
end

-- CSV for the cloud localization table (Key,Source,Context,Example).
function Locale.csv(extraTerms: { string }?): string
	local function quote(text: string): string
		return '"' .. text:gsub('"', '""') .. '"'
	end
	local lines = { "Key,Source,Context,Example" }
	local keys: { string } = {}
	for key in STRINGS do
		table.insert(keys, key)
	end
	table.sort(keys)
	for _, key in keys do
		table.insert(lines, `{quote(key)},{quote(STRINGS[key])},,`)
	end
	local seen: { [string]: boolean } = {}
	local terms = Locale.terms()
	if extraTerms then
		for _, extra in extraTerms do
			table.insert(terms, extra)
		end
	end
	for _, term in terms do
		if not seen[term] then
			seen[term] = true
			table.insert(lines, `,{quote(term)},,`)
		end
	end
	return table.concat(lines, "\n")
end

return Locale

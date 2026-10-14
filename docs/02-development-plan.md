# Meteor Rush — Development Plan

Version 0.1 · 2026-10-11 · Team: 1 programmer (+ freelance 3D/thumbnail artist). MVP target: soft launch week of 2026-11-23.
Design spec: `docs/01-game-design.md`.

Current implementation audit (2026-10-14), next art/animation work and release gates: [current plan](12-current-status-and-art-plan.md). The dated milestone table below is the original schedule; it does not mean every future-dated feature remains unimplemented.

## 1. Tech stack
| Area | Choice |
|---|---|
| Sync | Filesystem is source of truth. Push to Studio with `python -I scripts/mcp_sync.py` (Studio MCP `execute_luau`, one-way, replaces Shared/Server/Client). Rojo (`rojo serve`) remains an alternative |
| Packages | Wally |
| Language | Luau `--!strict` everywhere |
| Lint/format | Selene + StyLua, CI on GitHub Actions |
| Data | ProfileStore (session locking, autosave, BindToClose) |
| Networking | RemoteEvents in one `Remotes` module, typed payloads, server validation + rate limits |
| Tests | TestEZ for pure logic (economy math, odds, timers); multi-client playtests in Studio |
| Studio automation | Roblox Studio built-in MCP (`Roblox_Studio`, local scope): `execute_luau` (Edit/Server/Client), `start_stop_play`, `character_navigation`, `get_console_output` for automated playtests |
| Type check | `bash scripts/typecheck.sh` (luau-lsp strict). Rarity is typed `string` (old solver widens singleton unions across modules) |
Scaffold with `/roblox-dev:setup`; new client/server features with `/roblox-dev:new-system`.

## 2. Architecture
```
src/
  server/            -- Script bootstrap + Services (ModuleScripts)
    Services/
      DataService       ProfileStore, schema version, migrations
      SpeedService      +1/s tick, movement validation, WalkSpeed mapping
      TrackService      zones, gates, meteor spawning, shower spawns
      StationService    plots, pedestals, income tick, collector, offline income
      HatchService      timers, rarity/mutation roll at pickup (server RNG)
      StealService      prompts, carry state, chase, locks, shields, protections
      RebirthService
      ShopService       global-clock rotation, stock, purchases (coins)
      MonetizationService  passes, products, ProcessReceipt (idempotent)
      EventService      Meteor Shower, Starfall, midweek events (global clock)
      CrewService       crews, merged stations, friend bonus
      DailyService      streaks, codes, group reward
      NotificationService  experience notifications (13+)
      AnalyticsService  funnel/economy/custom event wrappers
  client/
    Controllers/       HUD, Shop, Crate+Odds, Inventory, Rebirth, Daily, Crew, Tutorial, VFX, Audio
  shared/
    Config/            Speed, Zones, Rarity, Creatures, Economy, Products, Events  (all tuning numbers)
    Theme/             names, model refs, colors, strings (reskin layer)
    Types.luau, Remotes.luau, Clock.luau (global UTC clock helpers)
```
Rules: no `_G`; services expose typed APIs; client never decides outcomes (rarity, steal, income, purchases); every `:Connect` cleaned up (Trove); no per-frame allocations in hot paths.

## 3. Data schema (v4)

Authoritative definitions: `src/shared/Types.luau` (`Profile`), `src/server/Services/DataService.luau` (`TEMPLATE`) and `src/server/Data/Migrations.luau` (`LATEST = 3`). Abbreviated current shape:
```
Profile = {
  schema = 4,
  coins: number, speed: number, rebirths: number,
  pedestals: { [slot]: { creatureId, rarity, mutation?, hatchAt: number?, paid? } },
  pedestalCount: number,
  storage: { PedestalState }, index: { [creatureId]: true },
  lastOnline: number, playtimeTotal: number,
  daily: { streak: number, lastClaimDay: number },
  shieldUntil: number, codes: { [code]: true },
  purchases: { [purchaseId]: number },
  training: number, treadmill: number, carryTraining: number,
  // treadmill 0=unbuilt, 1=installed, 2..11=upgrades; flags.warehouseOwned=locker purchase
  hatchCredits: number, restockCredits: number,
  uncollectedCoins: number, serverLuckUntil: number,
  outgoingTransfers: {...}, incomingTransfers: {...},
  stats: { steals, defends, timesRobbed }
}
```
Migrations are pure functions `vN → vN+1`, unit-tested. v3→v4 keeps the old free facilities: treadmill level increases by one without changing its rate or next upgrade price, and warehouseOwned becomes true. New v4 profiles start with neither facility. See [base progression](13-physical-warehouse.md).

## 4. Milestones (weeks)
| Wk | Dates | Deliverable | Acceptance criteria |
|---|---|---|---|
| 0 | Oct 11–12 | Repo scaffold, CI green, Rojo sync, Config/Theme skeleton | `rojo serve` + CI lint/format pass |
| 1 | Oct 12–18 | Speed +1/s, track & 5 zones, gates, meteor spawn, pickup/carry/drop, plots, server income tick | 8-player test: speed grows only while moving; gates enforced server-side |
| 2 | Oct 19–25 | ProfileStore, autosave, offline income, hatch timers, rarity "1 in X", creatures v1 (placeholders) | Rejoin restores everything; offline income matches formula; no data loss on server shutdown |
| 3 | Oct 26–Nov 1 | Stealing, chase-back, base lock, shields, protections, anti-exploit | Exploit checklist passes (teleport steal, prompt spam, remote fuzz) |
| 4 | Nov 2–8 | Crater Canyons (GDD §4.2b, pulled forward), Meteor Shop rotation, pedestal upgrades, treadmill, rebirth, Meteor Shower, friend bonus + invite. **Done 2026-10-11.** Merged crew stations moved to live-ops backlog (first item in the plan's cut order); free private servers = game setting | Global clock identical across servers; crew merge/split safe |
| 5 | Nov 9–15 | All MVP products + passes, Odds windows, receipts, FTUE, analytics funnel, daily, codes. **Implemented 2026-10-11; IDs configured.** Commerce hardening, coin upgrades, creature portraits and permanent index added 2026-10-13. Studio receipt tests pass; live platform checkout acceptance remains (see docs/06 and commerce report). Notifications + group reward deferred (need Dashboard setup). Art: AI-generated creature meshes via `scripts/gen_creatures.py`, code VFX | Test purchases in Studio; odds sum 100%; funnel events visible |
| 6 | Nov 16–22 | Final art pass, VFX/audio, closed test (20–50 players), balance, perf pass, thumbnails/icon/video | D1 of testers tracked; no P0/P1 bugs; mobile 60 FPS on mid device |
| 7 | Nov 23–29 | Soft launch (see `docs/03-launch-plan.md`) | Live, monitoring on |
Buffer: Season/winter content (Dec) is built in parallel during weeks 6–8 by the artist.

## 5. Definition of done (every feature)
- `--!strict` with no type errors; Selene/StyLua clean.
- Server validates every remote: types, ranges, ownership, distance, cooldown.
- Numbers in Config, strings in Theme.
- Analytics event added if it is a funnel step, economy flow, or decision point.
- Reviewed by `roblox-dev:roblox-reviewer` agent; DataStore code also against `roblox-dev:roblox-datastores`.
- Playtested with ≥ 2 clients (Studio multi-client) incl. mobile emulation.

## 6. Security checklist (stealing game = exploit magnet)
- Speed computed server-side from validated movement; client WalkSpeed is cosmetic re-applied by server; flag teleports (> max distance per tick).
- Steal requires server-side proximity + prompt hold time + station unlocked + protections + cooldown.
- Carry state lives on server; dropping/transfer only by server.
- Rate-limit every remote (token bucket per player).
- Purchases only via `ProcessReceipt`/`UserOwnsGamePassAsync`; never trust client "I bought".
- Codes validated server-side, one per account.

## 7. Performance budget
- ≤ 8 players/server, StreamingEnabled on, track parts instanced & anchored, meteors pooled.
- Server tick loops batched (1 Hz income, 1 Hz speed, 5 Hz steal checks), no per-player `while true`.
- Client: VFX pooled, ≤ 2 ms/frame scripts on mobile.

## 8. Risks
| Risk | Mitigation |
|---|---|
| Scope creep | MVP list in GDD §8 is frozen; everything else → live-ops backlog |
| Data loss | ProfileStore, BindToClose, migration tests, staging place |
| Exploits | §6 checklist, server authority, weekly log review |
| Art bottleneck | Placeholders first, Creator Store assets restyled, freelancer from week 3 |
| Schedule slip | Cut order: crews → midweek events → codes; never cut FTUE, data safety, odds windows |

## 9. Environments
- `Meteor Rush [DEV]` place (team only), `Meteor Rush` live place. Publish to live only from a tagged commit.
- Separate DataStore names per environment (`_dev` suffix).

## 10. Zone identity and creator emotes

Owner's weekly work, five distinct zone prototypes, emote groups, achievement unlocks, cosmetic packs and recording mode: [roadmap](09-zone-and-emote-roadmap.md). The first free wave prototype supports R6/R15; advanced emotes and recording tools follow playtesting and the outstanding release checks.

## 11. UI cleanup and speed balance

Unified menu layout, mobile navigation, optional chat, readable creature discovery labels and viewport portrait fitting implemented 2026-10-13. Current hound status and proposed AFK/difficulty tuning: [UI and speed balance](10-ui-and-speed-balance.md). Speed losses and economy tuning remain proposals; no saved progress is reduced by this UI work.

2026-10-14: single gameplay Menu button, corner stats, translucent menus, zone arrivals and approved speed-transition validation: [validation report](../reports/hud-and-movement-2026-10-14.md).

## 12. Zone loot and income progression

2026-10-14: increasing rarity floors, progressive species pools, shorter hatch times and matching Luck/FTUE odds implemented. Saved creature identities remain intact; old long hatch deadlines only shorten. Specification: [zone loot progression](14-zone-loot-progression.md). Source-backed balance comparison, two-client acceptance and remaining live checks: [validation report](../reports/zone-progression-2026-10-14.md).

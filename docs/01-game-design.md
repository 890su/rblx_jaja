# Meteor Rush — Game Design Document

Version 0.3 · 2026-10-11 · **Public title: "Meteor Heist"** (set in Creator Hub 2026-10-11; "Meteor Rush" remains the internal codename in docs/code) · Working title (validate via thumbnail A/B before content spend).
Source research: `reports/Простые трендовые игры Roblox.md`.

## 1. Concept

**One-liner:** Run faster every second, grab falling meteors far out on the crater field, hatch them into star creatures that earn coins (even offline), and defend your station from thieves with your crew.

**Reference blend**
| Reference | What we take | What we drop |
|---|---|---|
| +1 Speed Every Second / Keyboard Escape | Speed grows +1/s while running; distance = rarity; treadmill AFK progress; friend speed bonus | Pure obby with no interaction |
| Steal a Brainrot / Steal An Egg | Base with passive income, stealing, base lock, shields, rebirth | Brainrot IP, "Steal a ___" naming, Reels/watch-to-earn feeds, admin-command sales |
| Grow a Garden | Real-time timers, offline growth, rotating shop, weekly Saturday update + event | Garden theme |

**Differentiators:** (1) Chase-back: owner can catch the thief and recover loot — clip-ready, reduces child frustration. (2) Meteor Shower every 15 min synchronizes the server. (3) Crew stations with friends — directly feeds the "play with friends" Home signal.

**Audience:** Roblox core 9–16. ~35% under 13 → retention must not depend on notifications or rewarded ads.

**Success target (first 30 days):** ~1,000 CCU, D1 ≥ 30%, D7 ≥ 15%.

## 2. Design pillars
1. **Reward in 30 seconds** — first meteor hatched before the player thinks about leaving.
2. **Short sessions, many days** — timers, rotation, showers; Home caps credited playtime at 60 min/day.
3. **Social tension, fair outcome** — stealing is exciting, never devastating (chase-back, protection, shields).
4. **Honest monetization** — power via time/multipliers, prestige via cosmetics, all odds on screen.
5. **Reskinnable** — theme lives in data/assets; mechanics never reference theme names in code.

## 3. Core loop
```
Run (+1 speed/s) → reach farther zone → pick up meteor → carry home (slower)
→ place on pedestal → hatch timer → creature earns coins/s (offline at reduced rate)
→ spend coins (pedestals, shop meteors, shields, upgrades) → run farther
→ steal from others / defend own station → Rebirth (reset speed+coins, permanent multiplier, unlock zone)
```
Session rhythm: 3–15 min sessions anchored to Meteor Shower (15 min), shop rotation (5 min), hatch timers.

## 4. Systems

### 4.1 Speed
- `Speed` is an unbounded training stat; fractional gains are saved and the HUD rounds the displayed number. Running grants +1/s (server-validated movement); standing on the player's own treadmill grants +0.5/s before gain multipliers. Ordinary idle grants nothing; treadmill movement cannot also earn running gains.
- Movement mapping: `WalkSpeed = 16 + 6 * sqrt(Speed)`, hard cap 400 (MVP). Tune in `Config/Speed`.
- Carrying multiplies ordinary pace by 0.6 (up to 240 without temporary buffs); the Void Run uses a fixed corridor pace of 30% of normal WalkSpeed, clamped to 24–38. Outside the Void Run, movement ramps up over ~0.9 s and coasts to a stop over ~0.5 s (client `MovementController`; the server WalkSpeed stays authoritative). HUD separately shows the training source, gain rate and movement pace.
- Multipliers: 2x Speed pass, rebirth bonus (+25% gain per rebirth), friend bonus (+10% per friend in server, cap +30%).

### 4.2 Track and zones
- One long straight crater track from the base row. Zone 1 is 500 studs (a newcomer at 16 studs/s crosses it in ~30 s; it also hosts the Void Run); zones 2–5 are 1,000 studs each — at their gate speeds (76–400 studs/s) that is a 3–13 s run. Gates by Speed:
| Zone | Name | Speed gate | Extra gate |
|---|---|---|---|
| 1 | Dust Flats | 0 | — |
| 2 | Ember Ridge | 100 | — |
| 3 | Frost Rim | 500 | — |
| 4 | Void Basin | 2,000 | — |
| 5 | Nova Core | 8,000 | Rebirth ≥ 1 |
- Meteors spawn on server timers per zone (max N alive per zone), each with server-rolled rarity.

### 4.2b Crater Canyons (decided 2026-10-11)
Goal: make escaping and chasing a decision ("which way do I run?") without killing the speed fantasy or the first minute.
- **Zones 1–2 stay straight** (FTUE, first reward < 30 s).
- **Zones 3–5:** a central **speed lane** (80 studs wide) flanked by **canyon mazes** on both sides (grid of 48-stud cells, walls ~28 studs high).
- Maze = braided (loops, few dead ends): recursive backtracker + ~35% extra wall removal, so there are always several routes. Several openings connect canyons to the lane.
- **Risk/reward:** ~70% of meteors in canyon zones spawn inside canyons with a ×2 rarity boost (shown in the "1 in X" text); the lane is safe but poorer.
- **Shifting craters:** layout is seeded by UTC day (same on every server — learnable, clip-friendly) and reshuffles daily with a server-wide announcement. Candidate later: reshuffle on each Meteor Shower.
- **Never lost:** while carrying, a 3D arrow points home; the thief highlight is visible through walls so chases continue around corners.
- Metrics to judge it: bounce bands, session length, % chases ending in a catch, canyon vs lane pickup share. Tunables in `Config/Canyons`.

### 4.3 Meteors, rarity, creatures
- 6 rarities, shown as "1 in X" (Fish It style). Default spawn weights per zone in `Config/Rarity`.
| Rarity | Income/s | Hatch time | Approx. odds in its best zone |
|---|---|---|---|
| Common | 1 | 10 s | — |
| Uncommon | 4 | 1 min | 1 in 3 |
| Rare | 15 | 5 min | 1 in 10 |
| Epic | 60 | 20 min | 1 in 40 |
| Legendary | 250 | 1 h | 1 in 200 |
| Mythic | 1,200 | 8 h | 1 in 2,000 |
- ~30 creatures in MVP (≈5 per rarity), each with a home zone. An egg hatches any creature of its rarity, weighted toward the pickup zone (home ×4, neighbouring zone ×2, others ×1), so a zone keeps its flavour without repeats (Common in Zone 1: 46% / 22% / 11% ×3). While hatching, the capsule shows the meteor itself (spinning, rarity aura). Mutation: Golden (2% at hatch, ×2 income). More mutations are live-ops content.
- Carrying: one meteor at a time; carrier speed ×0.6; dropping on death/reset returns it to the field for 10 s.

### 4.4 Station (base)
Pedestal slots are cryo capsules: metal bases and supports, transparent domed chambers and rarity lighting. A large upper plate shows creature income or the hatch countdown; the lower panel shows the creature name, status and hatch progress. Locked capsules stay dim; VIP adds a restrained gold collar. Creature displays fit the chamber, while the original slot anchors keep replacement, unlock and stealing interactions intact.
Each server income tick produces a floating Stardust amount above the corresponding capsule. Amounts include mutations, Rebirth and coin bonuses; empty and incubating capsules show no earnings. Labels rise and fade, with small offsets between slots and rendering limited to nearby capsules.
- 8 plots per server (server size 8). Start with 3 pedestals; buy pedestals 4–8 with coins (500 / 2.5K / 10K / 60K / 250K); +2 via Station Expansion pass (10 max).
- **Full station:** hold E at a chosen occupied pedestal to replace its creature with the carried meteor; the previous creature is kept in storage. The Station menu exchanges creatures with storage or sells a selected occupant for income × 30 s after confirmation. Shop purchases go to storage when all pedestals are full.
- **Run Training** (coin sink): 10 levels, +10% speed gain each, cost 2K × 2.2^level.
- Income ticks on server every 1 s into the "collector"; touch collector to bank (Auto-collect pass skips this).
- Offline income: 25% rate, cap 12 h (pass: 50%, 24 h). Calculated on join from saved timestamp, server-side.
- Hatch timers run in real time, including offline.

### 4.5 Stealing and chase
- Thief enters an unlocked station, holds ProximityPrompt (1.5 s) on a pedestal → carries the meteor/creature (speed ×0.6).
- Owner gets alert + "Chase" buff (+50% speed, 20 s). Owner touching the thief within 20 s → loot returns home. Thief reaching own station → loot transfers.
- Base lock: 30 s after owner enters their station (VIP +10 s). Shield product: 15 min full lock.
- Protections: new players protected for first 10 min of total playtime and while Rebirth 0 has < 3 creatures; per-thief cooldown 60 s; cannot steal from same victim twice in 5 min; Mythics can be stolen only from players with ≥ 4 creatures.
- All steal logic server-authoritative (distance checks, prompt validation, rate limits).

### 4.5b Void Snatchers (egg guards and PvE chase)
Regular and shower field eggs have visible patrolling guards before pickup in all five zones: one per egg in Zone 1, two per egg from Zone 2. Pickup alerts that egg's guards; chasers per zone are 1/2/2/3/4 plus rarity extras (Epic/Legendary +1, Mythic +2), capped at 4. From Zone 3 one guard also tears open a purple portal and a **Void Hound** leaps out 0.7 s later to chase on foot, pouncing with the same telegraph (model: Creator Store "Hellhound" 857040608, scripts and helper parts removed, `Assets.VoidHound`). Zone 1 and the first encounter use a single gentle drone and no hound. Recovering a dropped egg starts a fresh encounter without accumulating previous chasers. Each drone/hound is one welded assembly (one replicated CFrame); idle guards with no player within 300 studs skip their patrol updates.

The player gets 1.5 seconds after pickup before an attack can start. A guard approaches, locks an attack line and shows a yellow floor strip plus DODGE for 0.9 seconds (1.25 in Zone 1). It then dashes along that fixed line, followed by 1.4 seconds of recovery. Contact only drops the egg during the red dash; ordinary patrol, chase and warning contact are harmless. Chase speed is capped at 40 studs/s; dash speed is 65 (42 in Zone 1). Walls block attacks; server collision uses swept relative movement. Chasers give up after 30 seconds and leave upon entering a station or the Void Run. Tunables: `Config/Snatchers`.

### 4.5c Void Run — top-down dodge corridor (reworked 2026-10-12)
- **Trigger:** only eggs first picked up in Zone 3 or deeper (`OriginZone`, kept by dropped eggs so a fail cannot be laundered). Entering Zone 1 on the way home starts the run; Zone 1–2 eggs never trigger it (FTUE stays calm).
- **Field:** the whole of Zone 1 (500 studs). Eight 70-stud lanes tile the track, one in front of each station, so nobody is snapped sideways; the runner is confined to the lane they entered. Orange start line, green finish line, "VOID RUN" signs; Zone 1 route beacons and lane edges are omitted so every visible shape in the corridor is an attack.
- **Camera:** rises smoothly (1.4 s, smoothstep) to a straight top-down shot that fits the lane width on any aspect ratio, home at the top of the screen, following the runner with a 12-stud lead; descends behind the player (0.7 s) when the run ends. Field eggs and idle guards are hidden locally during the run.
- **Goal:** reach the finish line (station side) with lives left. Three lives, 1.1 s invulnerability after a hit. Losing all lives knocks the egg out where the runner fell (60 s pickup window, any player can grab it); grabbing it again restarts the run from there.
- **Attacks** (Undertale-inspired, all telegraphed in yellow first): bone walls with a gap (Papyrus/Sans), blue walls that only hurt if you move and orange walls that only hurt if you stand still, Gaster-Blaster beams across or down the lane, ground spears around your predicted position (Undyne), a closing pellet ring with one exit facing the lane centre (Flowey), side crossfire (Undyne/Muffet), a rotating sweeper bar (Asgore/Mettaton), sine fire streams (Toriel/Asriel).
- **Difficulty:** `level = 0.12·(rarity order − 1) + 0.15·(origin zone − 3) + 0.04·min(rebirths, 10)`, plus up to +0.5 as the runner nears home (cap 1.6). Higher levels unlock advanced kinds (ring 0.15, stream/blaster 0.3, blue/orange 0.55, sweeper 0.6), shorten wave intervals (2.3 s → 0.85 s), allow more simultaneous waves (2 → 4), shorten warnings (0.9 s → 0.45 s) and add projectiles; faster runners face proportionally faster attacks.
- **Authority:** the server schedules waves (`ArenaWave` remote), checks hits every 1/30 s with the shared pure `ArenaPatterns` math (seeded integer hash, identical on every platform), clamps the lane and owns lives and the finish. Clients only render. Tunables: `Config/Arena`.
- Treadmill running and the egg-holding pose support both Motor6D and modern AnimationConstraint avatar joints.

### 4.6 Rebirth
- Cost: coins `300,000 × 4^n` and Speed ≥ 5,000 × (n+1) (tuned with tools/balance_sim.py: F2P Rebirth 1 ≈ 1h40, Zone 5 ≈ 3h, a new goal every 10–20 min). Resets Speed and coins; keeps creatures and pedestals.
- Rewards: +50% income multiplier (additive per rebirth), +25% speed gain, unlocks Zone 5 at Rebirth 1, cosmetic trail tier.

### 4.7 Shops
- **Meteor Shop (coins):** 6 slots, restocks every 5 min (global clock, same for all servers), limited stock per slot, rare slots probabilistic. Restock countdown always visible.
- **Upgrades (coins):** pedestals, carry speed, treadmill rate.
- **Crate Shop (Robux):** featured creature rotates every 30 min. Odds table mandatory.

### 4.8 Events
- **Meteor Shower:** every 15 min (global clock), 60 s, 12 meteors at zones 3–5 ends with rarity boost ×3. Server-wide race, announcement 60 s before.
- **Starfall (Saturday):** 1 h before weekly update; exclusive mutation (e.g., "Starborn" ×3) only obtainable online.
- **Midweek mini-event (Wednesday):** themed boost (double hatch speed, double shower) — live-ops lever.

### 4.9 Crew
- Up to 3 players form a crew (friends or invited). Merged station: shared shield, +2 pedestals per extra member, income split per pedestal owner.
- Friend bonus: +10% speed gain per friend in server (cap +30%).
- Free private (reserved) servers. Invite button in HUD (SocialService prompts).

### 4.10 Daily and return hooks
- Daily gift: 7-day streak calendar (coins → rare meteor → shield → Epic meteor on day 7). Missing a day resets to day 1 but never removes earned items.
- Experience notifications (13+, opted-in): "Your Legendary hatched", "Meteor Shower in 5 min", "Your station was raided — chase is over, recover with a shield?" (personal, actionable, ≤ 99 chars).
- Group join reward: one-time Rare meteor.
- Codes system (Twitter/YouTube/Discord promo codes) — server-validated, expiry dates.

## 5. FTUE (first 3 minutes)
| Time | Beat | Signal served |
|---|---|---|
| 0 s | Spawn on own station; a glowing meteor already on pedestal 1 | bounce < 60 s |
| 0–10 s | Arrow + "Run!" prompt; +1 speed counter flies up | |
| 10 s | First creature hatches → coins tick visibly | first reward < 30 s |
| 20–60 s | Run to Zone 1, pick up meteor, carry home, place | |
| 60–120 s | Guaranteed Rare in Zone 2 (first visit), "1 in 10!" banner | bounce 61–180 s |
| ~120 s | Guided steal from an NPC bot station; shield tutorial | |
| ~180 s | Goal panel: "Reach Speed 500 → Frost Rim", next shower countdown | 5-min goal |
No modal walls of text; every tutorial step is an in-world arrow + one line.

## 6. Monetization
Prices are starting points; enable regional pricing at launch; run Price Optimization after 2 weeks of data. Items marked **ODDS** need a pre-purchase odds window (all outcomes, %, sum = 100%, labeled — not a bare (i) icon).

| Product | Type | R$ | Notes |
|---|---|---|---|
| Starter Pack (3 Rare+ meteors, 30-min shield) | Dev product, once per account | 49 | ODDS if contents random |
| 2x Coins | Game pass | 199 | |
| 2x Speed | Game pass | 149 | |
| VIP (+0.5x coins, chat tag, +10 s lock, gold pedestal) | Game pass | 299 | |
| Offline x2 + Auto-collect | Game pass | 249 | |
| Station Expansion (+2 pedestals) | Game pass | 399 | |
| Shield 15 min | Dev product, repeatable | 39 | |
| Instant Hatch | Dev product, repeatable | 25–99 by rarity | ODDS if hatch result random (mutations) |
| Restock Shop Now (personal) | Dev product, repeatable | 49 | |
| Meteor Crate ×1/×3/×10 | Dev product, paid random | 99/249/699 | ODDS mandatory |
| Server Luck 15 min | Dev product | 249 | Probability modifier → disclose effect on odds |
| Season Pass (50 tiers, cosmetics + exclusive creature) | Dev product per season | 799 | Live-ops, not MVP |
| Station/trail cosmetics | Pass / product | 1,000–1,500 | Prestige, no power |

**Never:** admin-command sales, escalating infinite packs, watch-a-feed-to-earn, rewarded ads for < 13, fake scarcity timers.
Receipt handling: grant then return `PurchaseGranted`; idempotent by `PurchaseId`.

## 7. Economy guardrails
- All coin sources/sinks logged (AnalyticsService economy events).
- Target: Rebirth 1 at ~2–3 h cumulative play for F2P, ~1.5 h with 2x Coins.
- Offline income never exceeds 50% of online rate. Steal value capped per hour per victim.
- Config-driven: every number above lives in `src/shared/Config/*`.

## 8. Content (MVP)
- 1 track, 5 zones, 8 station plots, ~30 creatures (low-poly; Creator Store assets allowed if licensed & restyled), 6 rarity VFX, 2 mutations (Golden, Starborn).
- UI: HUD (speed, coins, shower timer), Shop, Crate + Odds, Inventory/Index, Rebirth, Daily, Crew, Settings, Codes.
- Audio: running loop pitch-scaled with speed, pickup, hatch fanfare per rarity, alarm, shower siren.

## 9. Analytics
- Funnel (`LogOnboardingFunnelStepEvent`): spawn → first hatch → first pickup → first place → zone 2 → first steal/defend → first rebirth.
- Economy events for every coin source/sink and Robux purchase.
- Custom: shower participation, chase outcome, crew formed, notification opt-in.
- Review in Creator Analytics: PTR, bounce < 60 s / 61–180 s, D1/D7/D28, play days, sessions, friends-play days, payer conversion.

## 10. Compliance checklist
- Paid random items disclosure (crates, luck, random hatch results, pity).
- Maturity questionnaire completed; no blood/gore; theft is cartoon.
- No misleading metadata or copycat thumbnails/titles.
- Experience notifications only for 13+ opted-in, personal and actionable.
- Text filtering for crew names/any player text.
- No Reels/feed-watch reward mechanics.

## 11. Theme fallback
If thumbnail tests for "meteor/space" underperform, swap skin with zero code changes: "Firefly Catchers" (night meadow) or "Crystal Hunters" (caves). Theme-dependent strings, models, colors live in `src/shared/Theme/`.

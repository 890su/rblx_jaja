# Meteor Rush — Game Design Document

Version 0.1 · 2026-10-11 · Working title (validate via thumbnail A/B before content spend).
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
- `Speed` stat (integer, unbounded, displayed big on HUD). +1 per second while the character is moving (server-tick, validated by server position delta). Treadmill on base: +1/s while standing on it (AFK path, 50% rate without pass).
- Movement mapping: `WalkSpeed = 16 + 6 * sqrt(Speed)`, hard cap 400 (MVP). Tune in `Config/Speed`.
- Multipliers: 2x Speed pass, rebirth bonus (+25% gain per rebirth), friend bonus (+10% per friend in server, cap +30%).

### 4.2 Track and zones
- One long straight crater track from the base row. 5 zones × ~1,000 studs. Gates by Speed:
| Zone | Name | Speed gate | Extra gate |
|---|---|---|---|
| 1 | Dust Flats | 0 | — |
| 2 | Ember Ridge | 100 | — |
| 3 | Frost Rim | 500 | — |
| 4 | Void Basin | 2,000 | — |
| 5 | Nova Core | 8,000 | Rebirth ≥ 1 |
- Meteors spawn on server timers per zone (max N alive per zone), each with server-rolled rarity.

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
- ~30 creatures in MVP (≈5 per rarity), each zone has its own pool. Mutation: Golden (2% at hatch, ×2 income). More mutations are live-ops content.
- Carrying: one meteor at a time; carrier speed ×0.6; dropping on death/reset returns it to the field for 10 s.

### 4.4 Station (base)
- 8 plots per server (server size 8). Start with 3 pedestals; buy pedestals 4–6 with coins (escalating); +2 via Station Expansion pass.
- Income ticks on server every 1 s into the "collector"; touch collector to bank (Auto-collect pass skips this).
- Offline income: 25% rate, cap 12 h (pass: 50%, 24 h). Calculated on join from saved timestamp, server-side.
- Hatch timers run in real time, including offline.

### 4.5 Stealing and chase
- Thief enters an unlocked station, holds ProximityPrompt (1.5 s) on a pedestal → carries the meteor/creature (speed ×0.6).
- Owner gets alert + "Chase" buff (+50% speed, 20 s). Owner touching the thief within 20 s → loot returns home. Thief reaching own station → loot transfers.
- Base lock: 30 s after owner enters their station (VIP +10 s). Shield product: 15 min full lock.
- Protections: new players protected for first 10 min of total playtime and while Rebirth 0 has < 3 creatures; per-thief cooldown 60 s; cannot steal from same victim twice in 5 min; Mythics can be stolen only from players with ≥ 4 creatures.
- All steal logic server-authoritative (distance checks, prompt validation, rate limits).

### 4.6 Rebirth
- Cost: coins `5,000 × 4^n` and Speed ≥ 10,000 × (n+1). Resets Speed and coins; keeps creatures and pedestals.
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

# Meteor Rush — Live Ops, Support & Update Plan

Version 0.1 · 2026-10-11 · Principle: games that stop updating "die within weeks"; hits lose 95–99% of peak in 3–6 months. The weekly rhythm is the product.

## 1. Fixed cadence
| When (UTC) | What |
|---|---|
| Every 5 min | Meteor Shop restock (global clock) |
| Every 15 min | Meteor Shower |
| Every 30 min | Crate featured creature rotation |
| Wed | Midweek mini-event (double hatch speed / double shower / mutation boost), config-only |
| Fri | Teaser post + new code |
| Sat 14:00 | Starfall (1 h, exclusive mutation) → 15:00 weekly update (shutdown-free if possible: soft shutdown / migrate servers) |
| Mon | Patch-notes recap, weekly KPI review |
| Every 4–6 weeks | Season (Season Pass 799 R$, theme dressing, new zone or creature set) |

## 2. Content pipeline
- Keep an **8–10 week content buffer** (creatures, mutations, zone dressing) before launch-scale.
- Weekly update minimum: 1 new creature OR 1 mutation OR 1 system tweak + bug fixes + new code.
- Monthly: 1 meaningful system (e.g., trading, creature fusion, crew leaderboard, new zone).
- Everything event-related is config-driven (`Config/Events`) so midweek events need no code deploy.

## 3. Roadmap backlog (post-MVP, prioritize by weakest metric)
| Metric weak | Candidate features |
|---|---|
| D1 | FTUE polish, faster first rare, clearer goals panel |
| D7 | Creature index rewards, rebirth milestones, daily quests, crew leaderboard |
| D28 | Seasons, trading (with scam protection), fusion, new zones, collections |
| Friends-play | Crew quests, crew-only shower, invite rewards |
| Monetization | Season Pass, cosmetics, Server Luck tuning (never power-only paywalls) |

## 4. Weekly KPI review (Monday template)
```
Week of: ____  Build: ____
Traffic: impressions __ | PTR __ (Δ) | Home share __%
Bounce <60s __% | 61–180s __%
D1 __% | D7 __% | D28 __%  (vs last week, vs peer scorecard)
Avg session __ min | sessions/DAU __ | play days/user __
Friends-play share __%
DAU __ | peak CCU __ | payer conv __% | ARPDAU __ | top 3 products
Economy: coins created/destroyed ratio __ | median time to Rebirth 1 __
Exploit reports __ | bans __ | crashes/errors top 3
Decision: what ONE metric we attack this week, and with what
```

## 5. Support
**Bug intake:** Discord #bugs + in-game "Report" button (logs placeId, jobId, version, last errors). Triage daily.
| Priority | Definition | SLA |
|---|---|---|
| P0 | Data loss, purchases not granted, game-breaking exploit | Hotfix same day (shutdown update OK) |
| P1 | Core loop broken for a segment (device, zone) | ≤ 48 h |
| P2 | Visual/UX bugs | Saturday update |
| P3 | Polish | Backlog |
**Purchase issues:** verify via receipt logs (purchaseId in profile); grant manually with an admin tool logged to a DataStore audit trail. Never ask players for passwords/account details.
**Data issues:** ProfileStore version history; restoration tool for admins with audit log.

## 6. Anti-exploit operations
- Server logs: impossible speed deltas, steal attempts while locked, remote rate-limit hits.
- Weekly review → tune thresholds; auto-kick on hard violations, ban list in DataStore for repeat offenders.
- Never rely on client checks. Patch exploits in the next update; P0 if economy-breaking.

## 7. Economy health
- Watch coin inflation (sources vs sinks), median coins at rebirth, top-1% wealth.
- New sinks each season (cosmetic upgrades, station decor).
- Never nerf purchased items; if a pass is overpowered, add content around it.

## 8. Moderation & community
- Text filtering on all player text (crew names, signs).
- Discord moderators (trusted 13+ volunteers later); clear rules; no trading-scam channels.
- Respond to feedback in patch notes ("You asked, we shipped").

## 9. Release process
1. Branch → PR → CI (lint/format/tests) → reviewer agent pass.
2. Publish to DEV place → 2-client playtest + data migration test.
3. Tag release → publish to live Sat 15:00 UTC → monitor 2 h.
4. Rollback via place Version History if error rate spikes.

## 10. Scale / partner decision
- At ~1,000 CCU with D1 ≥ 30%: evaluate partner (studio support like Splitting Point for Grow a Garden at ~1k CCU). Keep creative + monetization control (Fisch lesson: buyer's aggressive monetization crashed the player base).
- If metrics decay for 4 consecutive weeks despite updates: reskin/relaunch or sunset (keep servers up, stop content).

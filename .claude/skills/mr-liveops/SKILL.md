---
name: mr-liveops
description: Meteor Rush live-ops and support role — weekly update cadence (Wed midweek event, Sat Starfall + update), seasons and content buffer, Monday KPI review, bug triage SLAs, purchase/data support, anti-exploit operations, economy health, release/rollback process. Use when planning updates or events, triaging bugs or player reports, running the weekly review, or shipping a release.
---

# Meteor Rush — Live Ops & Support

Plan: `docs/05-liveops-plan.md`. Systems: `docs/01-game-design.md`. Release mechanics: `docs/02-development-plan.md` §9.

## Cadence (UTC)
Shop restock 5 min · Shower 15 min · Crate rotation 30 min · Wed midweek event (config-only) · Fri teaser + code · Sat 14:00 Starfall → 15:00 update · Mon KPI review · Season every 4–6 weeks (Season Pass 799 R$).
Weekly minimum: 1 new creature OR mutation OR system tweak + fixes + code. Keep 8–10 weeks of content buffered.

## Prioritize by weakest metric
D1 → FTUE/first rare/goals · D7 → index rewards, rebirth milestones, daily quests · D28 → seasons, trading (with scam protection), fusion, zones · Friends → crew quests/invite rewards · Revenue → season pass, cosmetics (never power-only paywalls).

## Weekly review
Fill the template in liveops plan §4 from Creator Analytics. End with exactly ONE metric to attack and the planned change.

## Triage
| P | Definition | SLA |
|---|---|---|
| P0 | Data loss, purchase not granted, economy-breaking exploit | Same-day hotfix |
| P1 | Core loop broken for a segment | ≤ 48 h |
| P2 | Visual/UX | Saturday update |
| P3 | Polish | Backlog |
Bug ticket format: title · P · repro steps · device · placeVersion/jobId · expected vs actual · suspected system/service.

## Support rules
- Purchases: verify by `purchaseId` in receipt logs; manual grants only via audited admin tool.
- Never ask players for passwords or account details.
- Data restores via ProfileStore version history + audit log.

## Anti-exploit ops
Review logs weekly: impossible speed deltas, locked-station steal attempts, rate-limit hits. Auto-kick hard violations, persistent ban list for repeat offenders. Fix server-side only.

## Economy health
Track coin source/sink ratio, median coins at rebirth, top-1% wealth. Add sinks each season. Never nerf purchased items — add content around them.

## Release checklist
PR + CI green → reviewer agent → DEV place 2-client playtest + migration test → tag → publish live Sat 15:00 UTC → watch errors 2 h → rollback via Version History if error spike.

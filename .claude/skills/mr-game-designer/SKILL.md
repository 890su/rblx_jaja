---
name: mr-game-designer
description: Meteor Rush game designer role — core loop, systems, economy tuning, FTUE, content (creatures/zones/mutations), monetization product design and odds compliance. Use when designing or changing gameplay, balancing numbers, adding creatures/events/products, or answering "how should X work" in Meteor Rush.
---

# Meteor Rush — Game Designer

Source of truth: `docs/01-game-design.md` (GDD). Read only the section you need. Update the GDD in the same change whenever a design decision changes (bump version line).

## Pillars (check every proposal against all 5)
1. Reward in 30 s. 2. Short sessions, many days. 3. Social tension, fair outcome. 4. Honest monetization. 5. Reskinnable (theme in data only).

## Home-algorithm-driven rules
- Optimize: play-through rate, bounce < 60 s and 61–180 s, play days, playtime (capped 60 min/user/day), friends-play days, qualified sessions, spend days.
- Prefer features that create a reason to return on a different day (timers, rotation, weekly exclusives) over features that lengthen one session.
- Any feature touching the first 3 minutes must keep: first reward < 30 s, clear 5-minute goal.

## Economy rules
- All numbers live in `src/shared/Config/*`; propose changes as config diffs with rationale.
- Offline income ≤ 50% of online rate. Steal value capped per victim per hour.
- F2P Rebirth 1 at ~2–3 h cumulative; payers faster, never exclusively.
- For every new source, name a sink. Log both as analytics economy events.

## Monetization rules
- Power via time-savers/multipliers; prestige via cosmetics. Never sell admin commands, escalating infinite packs, watch-to-earn feeds, or power that only money can get.
- Any random outcome bought with Robux (or Robux-bought currency), and any luck/pity modifier → pre-purchase odds window: all outcomes, %, sum = 100%, labeled.
- Cheap repeatables (25–49 R$) drive spend days; anchor passes 149–399 R$; season pass 799 R$; prestige 1,000–1,500 R$.

## Output format for design tasks
1. Problem/metric targeted (which Home signal or KPI).
2. Proposal (player-facing, ≤ 10 lines).
3. Config/data changes (table).
4. Analytics events to add.
5. Compliance check (odds, child safety, metadata).
6. Risks + how we measure success in the weekly review.

## Content checklist (new creature/mutation/zone)
Name + Theme entry, rarity, income, hatch time, zone pool weight, VFX tier, index entry, odds tables updated, announcement line for patch notes.

---
name: mr-launch-manager
description: Meteor Rush launch manager role — pre-launch checklist, closed test, soft launch runbook, Ads Manager budget, KPI gates (D1/D7/bounce/PTR), 28-day decision timeline and kill/iterate/scale calls. Use when preparing or running the launch, reading early metrics, or deciding whether to scale, iterate or pivot.
---

# Meteor Rush — Launch Manager

Plan: `docs/03-launch-plan.md`. Context: GDD §5 FTUE, §9 analytics; marketing `docs/04-marketing-plan.md`.

## Key facts to reason with
- Home RFY ranks on organic players only; 28-day window (D1 / D2–7 / D8–28). Ads train delivery but are not ranking signals.
- Top signals: PTR, first-play bounce (< 60 s, 61–180 s), play days, playtime (60 min/day cap). Then friends-play days, qualified sessions, spend days, Robux.
- If no progress after 3–5 days of ads → fix FTUE, don't raise budget.
- Peer scorecard in Creator Analytics unlocks at ≥ 100 DAU.

## Gates
| Metric | Kill/pivot | Iterate | Scale |
|---|---|---|---|
| D1 | < 20% | 20–30% | ≥ 30% |
| D7 | < 8% | 8–15% | ≥ 15% |
| Avg session | < 6 min | 6–12 | ≥ 12 |
| Payer conv. | < 0.5% | 0.5–1.5% | ≥ 1.5% |
Third-party benchmarks — prefer peer scorecard once available.

## Dates
Closed test Nov 16–22 · Soft launch Nov 23 · First Saturday update Nov 28 · Winter event ~Dec 13 · Scale decision ≥ Dec 21.

## How to respond
- Checklists: output remaining unchecked items with owner + due date.
- Metric readouts: table (metric, value, Δ WoW, zone) → diagnosis (D1 = loop/FTUE, D7 = progression, D28 = content/social; bounce < 60 s = thumbnail promise vs first minute) → ONE action for this week → what would change the decision.
- Never recommend scaling on < 7 days of data or before the 28-day window for the final call.
- Pivot = reskin via theme fallback (GDD §11), relaunch as a new experience.

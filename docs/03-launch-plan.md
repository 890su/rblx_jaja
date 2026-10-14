# Meteor Rush — Launch Plan

Version 0.1 · 2026-10-11 · Soft launch window: 2026-11-23 → 11-29. Scale decision: not before 2026-12-21 (28-day signal window).

Implementation status audited 2026-10-14: [current art/release plan](12-current-status-and-art-plan.md), [HUD/movement and 75-check commerce validation](../reports/hud-and-movement-2026-10-14.md). Meteor shell variants and a rigged deep-zone creature remain outstanding art work; do not infer release completion from the original schedule below.

## 1. Launch philosophy
- Home "Recommended For You" ranks on organic players only, over a 28-day window (Day 1 / Days 2–7 / Days 8–28). Ads train the system but do not count as signals.
- Most important signals: play-through rate (PTR), first-play bounce (< 60 s and 61–180 s), play days, playtime (capped 60 min/user/day). Important: friends-play days, qualified sessions, spend days, Robux spent.
- Therefore: launch quietly, fix FTUE fast, judge on weeks 2–4 — never on day 1.

## 2. Pre-launch checklist (complete by Nov 21)
**Experience page**
- [ ] Final name checked for collisions/trademarks; does not use "Steal a ___" or leader titles.
- [ ] Description: first line = the hook ("Run faster every second, grab meteors, hatch star creatures!"), no keyword stuffing.
- [ ] Icon + 3–4 thumbnails (chase-back scene, rare hatch, shower race, crew station) loaded into Thumbnail Personalization A/B.
- [ ] 30-s gameplay video (autoplays in RFY since 2026-07-29).
- [ ] Maturity & compliance questionnaire; genre/subgenre set.
- [ ] Supported devices: phone, tablet, PC, console (check gamepad UI).
- [ ] Regional pricing ON for all products.
- [ ] Social links: Roblox group (join reward), Discord (13+), YouTube/TikTok.
**Game**
- [ ] P0/P1 bug count = 0; exploit checklist (dev plan §6) passed.
- [ ] Odds windows verified for every random/luck product.
- [ ] Analytics: onboarding funnel + economy events visible in Creator Analytics.
- [ ] Live DataStore isolated from dev; BindToClose tested via shutdown.
- [ ] Codes ready: `LAUNCH`, `METEOR`, creator codes.
- [ ] Today's Picks nomination form submitted (new-game curation).

## 3. Closed test (Nov 16–22)
- Before the larger cohort: run the [3–5-player smoke test](11-small-group-playtest.md) for 20–30 minutes after publishing to a fresh server.
- 20–50 players (friends, small Discord, DevForum testers). Private server links.
- Measure: time to first hatch, % reaching Zone 2, % completing steal tutorial, D1 of testers, crash/error logs.
- Gate to soft launch: median first reward < 30 s; ≥ 70% reach Zone 2 in session 1; no data loss reports.

## 4. Soft launch (Nov 23–29)
| Day | Action |
|---|---|
| D0 (Mon) | Publish public; start Ads Manager campaign objective "Plays", small daily budget (start ~1,500–3,000 R$/day), broad targeting |
| D0–D2 | Watch errors/exploits hourly; hotfix freely |
| D2–D4 | Read bounce < 60 s and 61–180 s, PTR vs own baseline. If no progress in 3–5 days → fix FTUE, do NOT raise budget |
| D5 (Sat) | First Saturday update + Starfall event (small: 1 creature + mutation) |
| D7 | Weekly review (template in `docs/05-liveops-plan.md`) |

## 5. KPIs and gates
| Metric | Kill/pivot zone | Iterate | Scale |
|---|---|---|---|
| D1 retention | < 20% | 20–30% | ≥ 30% |
| D7 retention | < 8% | 8–15% | ≥ 15% |
| Bounce < 60 s | rising week over week | flat | falling |
| Avg session | < 6 min | 6–12 min | ≥ 12 min |
| Payer conversion (DAU) | < 0.5% | 0.5–1.5% | ≥ 1.5% |
| Friends-play share | — | track | rising |
Benchmarks are third-party estimates; compare against Creator Analytics peer scorecard once ≥ 100 DAU.

## 6. Decision timeline
- **Week 1–2:** FTUE and bug fixes only; thumbnails A/B running.
- **Week 3–4 (Dec 7–20):** Winter event build ships mid-Dec; economy tuning; Price Optimization enabled after 2 weeks of sales.
- **Dec 21 decision:**
  - Scale zone → raise ad budget stepwise (×1.5/week while ROAS-neutral), creator outreach wave 2.
  - Iterate zone → 2 more weeks focused on the weakest bucket (D1 = loop/FTUE, D7 = progression, D28 = content/social).
  - Kill/pivot zone → reskin (theme fallback in GDD §11) and relaunch as new experience, or move on.
- At ~1,000 CCU with D1 ≥ 30%: consider partner/publisher; keep monetization control in contract.

## 7. Launch-day runbook
- Owners: dev (hotfixes, logs), community (Discord, codes, bug intake), marketing (clips, posts).
- Hotfix rule: data/economy/exploit issues → shutdown-update immediately with migration safety; cosmetic issues → batch to Saturday.
- Rollback: keep previous place version; publish older version from Version History if a release breaks data flow.

# Roblox Retention, Conversion (Click-to-Play) and Discovery Mechanics (as of Oct 2026)

## 1. How Roblox's discovery / recommendation algorithm works in 2025–2026, and what Roblox has officially said matters

### Takeaway
Home's "Recommended For You" (RFY) sort is the main traffic source. Roblox's 2025 post says over 90% of traffic begins on Home. RFY ranks games on per-user averages taken only from players who joined organically from RFY. The signals are play-through rate, first-play bounce, play days, playtime (capped at 60 min per user per day), co-play, qualified sessions and spending. The algorithm has moved steadily toward **long-term retention plus monetization**. In June 2026 the window grew from 7 days to 28 days and qPTR was removed. In August 2026 Home began favoring games that are strong in both retention and monetization.

### Cited Findings
**Timeline of official changes**
- **Mar 31, 2025.** Roblox announced an improved RFY algorithm and a "Home Recommendations" analytics tab. The signals then were qualified play-through rate (qPTR) plus 7-day playtime per user, 7-day play days per user, 7-day spend days per user, 7-day Robux spent per user, and 7-day intentional co-play days per user. — [DevForum: Boost Your Discovery with the Improved RFY Algorithm (Mar 31, 2025)](https://devforum.roblox.com/t/boost-your-discovery-with-the-improved-recommended-for-you-algorithm-and-analytics-for-creators/3587441)
  - qPTR was defined as "the number of engaging plays divided by the number of impressions from Recommended For You." Creator analytics later switched qPTR from a unique-user level to a session level, and session-level values are usually lower. — [same thread](https://devforum.roblox.com/t/boost-your-discovery-with-the-improved-recommended-for-you-algorithm-and-analytics-for-creators/3587441)
  - Playtime counts only up to **60 minutes per user, per experience, per day**. — [same](https://devforum.roblox.com/t/boost-your-discovery-with-the-improved-recommended-for-you-algorithm-and-analytics-for-creators/3587441); also stated in [Creator Docs: Discovery](https://create.roblox.com/docs/discovery)
  - "Intentional co-play" means playing with friends through a join, an invite or a private server, rather than through matchmaking. — [same](https://devforum.roblox.com/t/boost-your-discovery-with-the-improved-recommended-for-you-algorithm-and-analytics-for-creators/3587441)
  - Roblox says over 90% of traffic begins on Home, and most signals update within 24 hours. In one example, a qPTR dip on Feb 28 was followed by a drop in impressions on Mar 3. — [same](https://devforum.roblox.com/t/boost-your-discovery-with-the-improved-recommended-for-you-algorithm-and-analytics-for-creators/3587441)
- **Dec 11, 2025.** Reserved-server play sessions now count as intentional co-play, and an attribution bug was fixed so that only RFY clicks and plays feed RFY signals. — [same thread, Dec 11 update](https://devforum.roblox.com/t/boost-your-discovery-with-the-improved-recommended-for-you-algorithm-and-analytics-for-creators/3587441)
- **Earlier (late 2024).** Roblox said it ranked on engagement signals such as D1/D7 retention and playtime, and on monetization signals such as payer conversion and Robux spent. — [DevForum: Testing Improvements to the RFY Algorithms](https://devforum.roblox.com/t/testing-improvements-to-the-%E2%80%9Crecommended-for-you%E2%80%9D-algorithms/3275201)
- **Mar 9, 2026 ("How we are improving Home this year"):**
  - Today's Picks becomes a sort for **novel games**, picked by the curation team. Creators can nominate games through a form.
  - A new **"Deep play through rate"** RFY signal was introduced. It measures sustained interest and active participation, unlike qPTR's impression-to-play funnel.
  - Labeled **ads are blended into RFY** for all users, spread through the sort rather than placed in one row.
  - Roblox is exploring genre sorts, "Because you played X" sorts and sorts for first-time players.
  - FAQ: once a user plays a game, it moves to their Continue sort and is no longer shown to them in RFY. RFY impressions may dip after a curation feature or ad campaign.
  - Source: [DevForum: How we are improving Home this year](https://devforum.roblox.com/t/how-we-are-improving-home-this-year/4502571)
- **Mar 26, 2026.** A new **7-day qualified play sessions per user** signal measures whether a game brings players back after the first session. A **"Not interested"** dismissal signal is now integrated into discovery. — [same thread](https://devforum.roblox.com/t/how-we-are-improving-home-this-year/4502571)
- **Apr–Jul 2026.** Standout Games now mainly shows video previews, and an Avatar sort launched. Gameplay video in Standout Games raised **quality plays by +47%** and playtime by +1.09% (May 14 post). Games with video saw **up to +39% more playtime from RFY** in tests run May–July 2026. Video **autoplay in RFY** launched Jul 29, 2026 (on hover for desktop, when scrolling stops on mobile), and Roblox says it "does not change how recommendations are ranked." — [same thread](https://devforum.roblox.com/t/how-we-are-improving-home-this-year/4502571)
- **Jun 15, 2026 ("RFY Algorithm Improvements That Better Value Long-Term Retention"):**
  - The signal window grew **from 7 to 28 days**, split into three buckets: **Day 1, Days 2–7 and Days 8–28**.
  - Signals in each bucket: playtime, play days, qualified play sessions, intentional co-play days, spend days and Robux spent.
  - **qPTR was removed** and replaced by **play-through rate (PTR)** and **first-play bounce rate**.
  - Roblox published the relative importance of each signal. The weights appear only in an image that I could not read.
  - Thumbnail personalization will be tested with PTR.
  - Source: [DevForum announcement (Jun 15, 2026)](https://devforum.roblox.com/t/recommended-for-you-algorithm-improvements-that-better-value-long-term-retention/4684575); secondary summary in [zehn-studio26](https://zehn-studio26.com/news/recommended-for-you-retention-update/)
- **Current Creator Docs priority tiers** ([Creator Docs: Discovery](https://create.roblox.com/docs/discovery)):
  - **Most important:**
    - Play-through rate.
    - First-play bounce rate, a negative signal measured in two bands: **under 60 s** and **61–180 s**.
    - Play days per user (D1, D2–7, D8–28).
    - Playtime per user (60-minute daily cap).
  - **Important:**
    - Intentional co-play days per user.
    - Qualified play sessions per user, which "filters out accidental clicks or quick bounces."
    - Spend days per user and Robux spent per user.
  - The process has two stages: retrieval (signals such as engagement, retention and monetization) and then personalized ranking.
  - Roblox uses explore and expand phases to test which user cohorts a game suits.
- **Organic-only rule.** "Roblox doesn't count the engagement, monetization, or retention of users first acquired from ads." Only users who organically join from RFY count toward ranking. — [Creator Docs: Discovery](https://create.roblox.com/docs/discovery)
- **Aug 6, 2026 ("Boost Your Discovery by Building Games People Want to Play"):**
  - Home recommendations now weigh long-term value more heavily, combining **retention** with **monetization** ("games where players find value in the purchases they make").
  - "Games that are strong in both retention and monetization are best positioned to earn more impressions over time." Games strong in only one area keep getting impressions but may see their distribution change.
  - Live for all players from the week of Aug 20, 2026.
  - Recommended monetization formats: items, passes, developer products, subscriptions and **rewarded video ads**.
  - Source: [DevForum (Aug 6, 2026, updated Aug 20)](https://devforum.roblox.com/t/boost-your-discovery-by-building-games-people-want-to-play/4779042)
- **Things that limit exposure:**
  - Giveaway-led titles, metadata that does not match the game, and non-unique or copycat games.
  - "You should not rely on promotional monetary rewards to drive engagement."
  - The Creator Dashboard shows a reduced-exposure banner, updated daily.
  - Source: [Creator Docs: Discovery](https://create.roblox.com/docs/discovery)
  - Ads Manager docs add that games whose metadata closely resembles existing games rank lower in search and are not prioritized for recommendations. — [Creator Docs: Ads Manager](https://create.roblox.com/docs/production/promotion/ads-manager)
- **Other surfaces:**
  - Home sorts: Standout Games (hand-curated), Live Events, Sponsored, and the Avatar sort (2026).
  - **Semantic search** in all officially supported languages, which handles natural-language queries such as "food games."
  - Discover page: top and trending sorts.
  - Game Details page: up to **5 thumbnails** can promote an event.
  - Notifications can "resurrect lapsed users."
  - Source: [Creator Docs: Discovery](https://create.roblox.com/docs/discovery)
- **Four factors drive impression changes:** your own updates, Roblox algorithm changes, total Home traffic (weekly and holiday seasonality), and competing games. Benchmark games have **no effect** on the algorithm. — [Creator Docs: Discovery](https://create.roblox.com/docs/discovery); [Jun 2026 DevForum](https://devforum.roblox.com/t/recommended-for-you-algorithm-improvements-that-better-value-long-term-retention/4684575)
- **Platform context (Q2 2026):**
  - 123M DAU, +10% YoY, but down for a third straight quarter from a Q3 2025 peak of 152M.
  - 29B engagement hours, +5% YoY (Q3 2025 peak was 40B).
  - Bookings per DAU $12.66.
  - Management cited "a greater than expected shift of engagement toward lower-monetizing games."
  - Source: [Shacknews](https://www.shacknews.com/article/150208/roblox-daus-grew-10-percent-yoy); [PocketGamer.biz](https://www.pocketgamer.biz/roblox-revenue-rises-36-yy-but-young-north-americans-see-falling-per-hour-monetisation/); [Roblox Q2 2026 8-K](https://www.sec.gov/Archives/edgar/data/0001315098/000162828026051059/ex991-robloxq22026earnin.htm)

### Inferences
- **What wins under the 2026 rules:** a strong first 60–180 seconds (bounce bands), a reason to come back on Day 1 and across Days 2–28 (play days and qualified sessions), friend co-play, and "spend days" (frequent small purchases rather than one large purchase). Repeated short sessions across many days likely score better than one long binge, because playtime is capped at 60 min per day while play days and qualified sessions are counted separately.
- **Why the August 2026 change probably happened:** Q2 2026 earnings flagged engagement shifting toward low-monetizing games. The monetization-weighted change followed soon after. A game that retains well but monetizes poorly is now at relative risk.
- **Ads can't buy ranking:** ad users do not feed RFY signals, so ads help only through their indirect "help the system learn" effect (see Q5) and through organic word of mouth.
- **Cold start is slower:** with the 28-day window, a new game needs about 4 weeks of organic cohort data before the full signal set is mature. Forum replies raised this concern, but Roblox had not answered it in the thread.

### Gaps
- The actual relative signal weights from the Jun 15, 2026 post were in an image I could not read.
- The exact definition and threshold of "qualified play" (minimum seconds) was not found in official text.
- Docs and forum posts don't fully agree on whether "Deep PTR" (Mar 2026) survived the June 2026 overhaul. The June post names PTR and first-play bounce, and the current Discovery doc doesn't list Deep PTR.
- No official statement found on how search ranking is weighted, beyond semantic search and the copycat penalty.
- No RDC 2025 talk transcripts were retrieved.

## 2. Benchmarks: D1 / D7 / D30 retention, session length, thumbnail CTR / PTR

### Takeaway
Roblox publishes **no official numeric retention or CTR targets**. Creator Analytics compares each game with a scorecard of similar games, which requires at least 100 DAU. Third-party genre ranges cluster around D1 20–35%, D7 10–18% and D30 around 5% or below for most genres (higher for roleplay). These are unverified. Treat D1 under 20% as a red flag.

### Cited Findings
- **Official definitions:**
  - D1 is the share of new users who return the day after their first visit.
  - D7 is the share who return on the 8th day.
  - D30 is the share who return on the 31st day.
  - Cohorts are keyed by the date of first play.
  - Source: [Creator Docs: Retention analytics](https://create.roblox.com/docs/production/analytics/retention)
- **Official diagnosis:**
  - Low **D1**: fix the core loop, the FTUE and performance.
  - Low **D7**: fix progression (goals, content variety, difficulty balance).
  - Low **D30**: add content regularly and add social mechanics.
  - A dip after a big influx of new users can be "a typical and temporary outcome."
  - Source: [Creator Docs: Retention](https://create.roblox.com/docs/production/analytics/retention)
- **Official stance on benchmarks.** Roblox has no single target. Grow these metrics to match or beat the benchmarks of similar experiences before driving many new users in. Benchmark scorecards need at least 100 DAU. — [Creator Docs: Analytics essentials](https://create.roblox.com/docs/production/game-design/analytics-essentials) (summarized via search; see also [Analytics](https://create.roblox.com/docs/production/analytics))
- Creators can view retention by acquisition source and choose their benchmark set. — [DevForum: View retention by acquisition source and select your benchmark set](https://devforum.roblox.com/t/analytics-view-retention-by-acquisition-source-and-select-your-benchmark-set/4010157)
- **Third-party genre ranges (no methodology stated, unverified):**
  - Obby: D1 25–35%, D7 10–15%, D30 below 5% considered normal.
  - Roleplay/social: D1 15–22%, D30 8–15%.
  - Tycoon/incremental: D1 20–28%, D7 12–18%. A drop of more than 60% from D14 to D30 is a problem.
  - Shooter: D1 22–30%, D7 12–16%.
  - Source: [RoWatcher: Retention benchmarks by genre](https://rowatcher.com/news/retention-benchmarks-by-roblox-genre-what-good-actually-looks-like)
- **Another third-party guide:**
  - D1 below 20% is critical; 20–30% is below average.
  - Simulators: "good" D1 35%, D7 18%.
  - Tycoons: "good" D1 30%, D7 15%.
  - D30 above 5% means strong long-term engagement.
  - Source: [rolearn.dev: First-week retention optimization](https://rolearn.dev/guidance/first-week-retention-optimization); [creation.dev](https://www.creation.dev/blog/roblox-player-retention) (unverified)
- **Session length / playtime:**
  - The algorithm caps credited playtime at 60 min per user per game per day. — [Creator Docs: Discovery](https://create.roblox.com/docs/discovery)
  - Platform average for Q2 2026: 29B hours ÷ 123M DAU, about 2.6 h per DAU per day across all games. This is my own derivation, not a company figure. — [Shacknews](https://www.shacknews.com/article/150208/roblox-daus-grew-10-percent-yoy)
- **CTR / PTR:**
  - One creator reported a Home qPTR of **0.07%** in early 2025 and called it "extremely low." This is a user report, not a benchmark. — [DevForum: Extremely low home recommendation play through rate](https://devforum.roblox.com/t/extremely-low-home-recommendation-play-through-rate/3548913)
  - Session-level qPTR is usually lower than user-level qPTR. — [DevForum Mar 2025](https://devforum.roblox.com/t/boost-your-discovery-with-the-improved-recommended-for-you-algorithm-and-analytics-for-creators/3587441)
  - Illustrative example from the docs: 25k RFY impressions producing 10k daily players, plus 5k players from 20k sponsored impressions. — [Creator Docs: Discovery](https://create.roblox.com/docs/discovery)

### Inferences
- PTR and CTR depend heavily on genre, device mix and placement. The only defensible way to set a target is the Creator Analytics benchmark scorecard for "similar experiences."
- The docs example implies conversion from impression to player can look very high in illustrative numbers. Real user reports such as 0.07% show the range is enormous. Do not quote a universal "good CTR."

### Gaps
- I found no official Roblox numeric D1/D7/D30 percentiles, no official average session length per game, and no official thumbnail CTR or PTR benchmark.
- Third-party genre numbers lack methodology. GameAnalytics, Bloxbiz or Gamefam reports with Roblox-specific numbers were not found in this pass.

## 3. Retention mechanics used by hits (Grow a Garden, Steal a Brainrot, etc.)

### Takeaway
2025's mega-hits combine **real-time/offline progression** (crops grow while away, offline income), **short restock timers** with scarcity, **scheduled weekly updates plus "admin abuse" live events**, and **social risk/reward** (stealing, raiding, trading). All of these map directly onto RFY's play-days and qualified-sessions signals.

### Cited Findings
- **Grow a Garden (released Mar 26, 2025; BMWLux / Splitting Point Studios):**
  - Crops **grow while the player is offline**.
  - **Seed stock rotates**.
  - **Exclusive items released weekly must be claimed while online**, which "help[s] boost player retention."
  - Pets come from loot boxes (eggs).
  - Robux can skip waits, unlock perks and **steal other players' crops**.
  - Some short-lived items create an incentive to bot.
  - Source: [Wikipedia: Grow a Garden](https://en.wikipedia.org/wiki/Grow_a_Garden)
- **Grow a Garden restock timers (community estimates, unofficial):**
  - Seed shop about every **5 min**, gear shop about every 5 min, egg shop about every **30 min**, daily deals every 24 h.
  - Figures for "Grow a Garden 2" are inherited from GAG1 and not re-verified.
  - Live-stock browser trackers exist, which is itself evidence that players care about restocks.
  - Source: [Nerdschalk](https://nerdschalk.com/grow-a-garden-2-shop-restock-times/); [Firefox add-on "Grow a Garden Stocks"](https://addons.mozilla.org/addon/grow-a-garden/)
- Roblox credited Grow a Garden's success to "exceptional user retention and vibrant social interactions." — via [Wikipedia](https://en.wikipedia.org/wiki/Grow_a_Garden)
- **Steal a Brainrot (released May 16, 2025; SpyderSammy / DoBig Studios):**
  - Brainrots are bought from a **conveyor belt** and generate income over time.
  - Players can **steal** others' brainrots, a capture-the-flag-style loop.
  - A base **shield button** protects against theft.
  - **Rebirth** resets progress for better stats.
  - Traps and items can be bought with currency or Robux.
  - **Admin-abuse events** award exclusive characters.
  - Server-admin powers are sold, and Polygon criticized the pay-to-win design ("the best items are only available for cash").
  - Source: [Wikipedia: Steal a Brainrot](https://en.wikipedia.org/wiki/Steal_a_Brainrot)
- **Steal a Brainrot details (fan/guide sources, lower reliability):**
  - The base locks for 30 s on join, and each rebirth adds 10 s.
  - **Offline income accrues at a reduced rate**.
  - A thief who grabs a brainrot is slowed and stripped of items, and the owner is alerted.
  - Duels risk losing every brainrot.
  - Source: [u7buy guide](https://www.u7buy.com/blog/steal-a-brainrot-game-mechanics/); [Steal a Brainrot wiki](https://stealabrainrot.fandom.com/wiki/Methods_Of_Stealing)
- **Experience Notifications (official):**
  - Eligibility: the game needs at least 100 visits and must not be under moderation.
  - Users aged **13+** opt in through the Notify button or an in-game prompt.
  - Messages should be **personalized, based on in-game activity, and immediately actionable**, not generic ads. Roblox's example is being N quests away from finishing a weekly challenge.
  - Strings are capped at 99 characters, set up under Creator Dashboard > Engagement > Notifications.
  - **Join data** can route the player to a location or personalize their join.
  - Triggered from the Engine API (server scripts) or the Open Cloud API, with performance analytics in the dashboard.
  - Source: [Creator Docs: Experience notifications](https://create.roblox.com/docs/production/promotion/experience-notifications); [Open Cloud guide](https://create.roblox.com/docs/cloud/open-cloud/experience-notifications)
- **Social signals officially rewarded:**
  - Intentional co-play days (friend joins, invites, private and reserved servers). — [Creator Docs: Discovery](https://create.roblox.com/docs/discovery); [DevForum Dec 2025 update](https://devforum.roblox.com/t/boost-your-discovery-with-the-improved-recommended-for-you-algorithm-and-analytics-for-creators/3587441)
  - Roblox's docs recommend social mechanics as the fix for low D30. — [Creator Docs: Retention](https://create.roblox.com/docs/production/analytics/retention)
- **Timed resets as a concurrency driver.** Global resets, leaderboard deadlines and limited cosmetics push players online at the same time. This is a generic industry opinion. — per search summary of [Steal a Brainrot coverage](https://www.rpgstash.com/blog/steal-a-brainrot-ccu-record-25-million-players) (low reliability)

### Inferences
- **Design mapping to 2026 signals:**
  - Offline growth, restock timers and weekly drops create many short return visits. These raise play days (D2–7, D8–28) and qualified sessions without running into the 60-min cap.
  - Stealing, trading and gifting create friend co-play and rivalry, which raise intentional co-play days.
  - Cheap, frequent purchases (skip timers, restocks) raise spend days.
- A notification ("your plant is ready," "restock in 1 min") is the natural partner of real-time timers. It is limited to opted-in users aged 13+, and about 35% of Grow a Garden players are under 13 ([Wikipedia](https://en.wikipedia.org/wiki/Grow_a_Garden)), so in-game cadence still matters.
- Avoid relying on "promotional monetary rewards" or giveaway framing, which Roblox flags as a limiting issue.

### Gaps
- No authoritative source was retrieved on daily login rewards and streaks, group join rewards, codes, friend boosts or leaderboards in these specific hits. They are widely used in Roblox games, but not evidenced here.
- No Naavik or Deconstructor of Fun deep dive on Grow a Garden or Steal a Brainrot was found by search. It may exist behind other titles.
- No developer-published retention numbers (D1/D7) were found for GAG or SAB.

## 4. Onboarding / FTUE, and thumbnail / icon / title best practices and A/B testing

### Takeaway
Officially, players should reach "the fun" within **5 minutes**. The algorithm now penalizes bounces at **under 60 s and 61–180 s**, so the practical target is a clear goal and first reward in the first minute. Thumbnail Personalization, Roblox's built-in thumbnail A/B testing, has shown an average **+8.5% qPTR** (up to +50%). Gameplay video previews are the newest conversion lever (+47% quality plays in Standout Games).

### Cited Findings
- **FTUE guidance (official):**
  - Keep the FTUE brief, ideally reaching the fun within 5 minutes.
  - Use a short tutorial or tooltips, reward the first completion, and preview later progression.
  - Instrument each core-loop step as a funnel, track negative outcomes, and fix the largest drop-offs.
  - Source: [Creator Docs: Retention](https://create.roblox.com/docs/production/analytics/retention)
- First-play bounce rate under 60 s and 61–180 s is now one of the "most important" negative RFY signals. "High bounce rates suggest players aren't finding enough to stay engaged early." — [Creator Docs: Discovery](https://create.roblox.com/docs/discovery)
- **Third-party opinion (unverified):**
  - The first 30–60 s are critical, and players leave if they don't understand what to do within a minute.
  - Teach in context (show mechanics when needed, with visual cues and guided first actions) rather than through long tutorials.
  - Source: [creation.dev glossary: Onboarding](https://www.creation.dev/glossary/onboarding)
- **Thumbnail personalization (official A/B tool):**
  - In testing, experiences using it averaged **+8.5% qPTR**, and some gained +50%. — [Creator Docs: Thumbnails](https://create.roblox.com/docs/production/publishing/thumbnails)
  - A 2025 update "remembers winning thumbnails": new tests keep most traffic on the current winner and adjust within hours. It produced +0.19% qPTR and 21% fewer impressions on non-winning thumbnails. — [DevForum](https://devforum.roblox.com/t/thumbnail-personalization-now-remembers-your-existing-winning-thumbnails/3793665)
  - Roblox requires that "all thumbnails accurately reflect your game." — [Creator Docs: Discovery](https://create.roblox.com/docs/discovery)
  - Thumbnail personalization is to be tested with PTR after qPTR's removal. — [DevForum Jun 2026](https://devforum.roblox.com/t/recommended-for-you-algorithm-improvements-that-better-value-long-term-retention/4684575)
- **Video previews:** +47% quality plays in Standout Games, and up to +39% RFY playtime in tests from May–July 2026. Autoplay in RFY has been live since Jul 29, 2026. — [DevForum: How we are improving Home this year](https://devforum.roblox.com/t/how-we-are-improving-home-this-year/4502571)
- **Metadata rules:** be accurate, don't stuff irrelevant keywords, and avoid repetitive titles or images and copycat games. — [Creator Docs: Discovery](https://create.roblox.com/docs/discovery); [Ads Manager docs](https://create.roblox.com/docs/production/promotion/ads-manager)
- **Opinion piece:** "The Roblox thumbnail is a conversion ad," so design it for clarity rather than art. — [RoWatcher](https://rowatcher.com/news/the-roblox-thumbnail-is-a-conversion-ad-stop-designing-it-like-art)

### Inferences
- Clickbait thumbnails that raise PTR but also raise first-play bounce likely now net out negative, since bounce is weighed at the same "most important" level.
- Uploading a gameplay video is likely the highest-ROI discovery action available to a small dev in 2026, based on Roblox's own test lifts.

### Gaps
- No official numeric guidance was found on icon versus thumbnail specs or title length, and no Roblox-published A/B results for icons.
- No official "60-second" FTUE figure exists. The 60 s figure comes from the bounce-rate band, not an FTUE guideline.

## 5. Update cadence and timed events as CCU drivers; marketing levers for small devs

### Takeaway
Grow a Garden's record CCU peaks lined up with named weekly Saturday updates and scheduled "admin abuse" events. The peaks were about 5M on May 18, 2025, then 11.7M, 16M+, 21.3M, and 22.3M+ on Aug 23, 2025. The Aug 23 GAG vs. SAB "admin war" pushed Roblox to an all-time platform record of 47.4M concurrent users. For small devs, paid levers are Ads Manager (auto-bid, measured in cost per play) and brand deals. Ad-acquired users do not count toward RFY ranking, so ads mainly help seed the algorithm.

### Cited Findings
- **Grow a Garden CCU milestones by update:**
  - About 5M on May 18, 2025 ("Blood Moon").
  - 11.7M+ on May 31 ("Bizzy Bees").
  - 16M+ on Jun 14 ("Working Bees").
  - 21.3M on Jun 21 ("Summer Update").
  - 22.3M+ on Aug 23 (admin war with SAB).
  - The record passed to SAB in Sep 2025.
  - Other stats: 1B visits in 33 days (fastest ever), over 35.3B visits by May 2026, and about 35% of players under 13.
  - Source: [Wikipedia: Grow a Garden](https://en.wikipedia.org/wiki/Grow_a_Garden)
  - Conflicting figures: iTWire cites a Guinness record of **21.6M** CCU. — [iTWire](https://itwire.com/your-it-news/entertainment/roblox-from-gardens-to-brainrots-australia%E2%80%99s-top-roblox-gaming-obsessions-of-2025)
  - The fan wiki gives 23.375M for GAG vs. 20.619M for SAB in the admin war. — [GAG wiki: Admin Abuse War](https://growagarden.fandom.com/wiki/Admin_Abuse_War)
- **Event schedule:**
  - Saturday admin abuse runs about 60 min before the weekly Saturday update, which typically lands around 8:30 PM UTC per guides.
  - A Wednesday slot ("Watering Wednesday") was added in April 2026.
  - Timing is not guaranteed.
  - Source: [Bloxswaps](https://bloxswaps.com/blog/grow-a-garden-admin-abuse); [TechWiser](https://techwiser.com/roblox-grow-a-garden-admin-abuse-guide-start-time/) (guide sites, medium reliability)
- **Steal a Brainrot peaks:**
  - 5M CCU in Jul 2025 and 20M in Aug 2025.
  - **24M** at the Sep 13, 2025 "Extinct Event."
  - **25.4M** in Oct 2025, the first game above 25M.
  - About 1M average CCU in Sep 2025.
  - Bruno Mars concert in Jan 2026: 12.8M CCU peak.
  - Source: [Wikipedia: Steal a Brainrot](https://en.wikipedia.org/wiki/Steal_a_Brainrot)
- **Virality:**
  - Meme alignment (Italian brainrot) and chaotic, clip-friendly moments helped both games spread on TikTok. This comes from news and listicle analysis, low rigor. — [Wikipedia: Steal a Brainrot](https://en.wikipedia.org/wiki/Steal_a_Brainrot); [iTWire](https://itwire.com/your-it-news/entertainment/roblox-from-gardens-to-brainrots-australia%E2%80%99s-top-roblox-gaming-obsessions-of-2025)
  - Bot allegation: TD Cowen claimed bots inflated GAG's visibility but retracted the manipulation claim. Roblox said its analysis showed "genuine popularity." — [Wikipedia: Grow a Garden](https://en.wikipedia.org/wiki/Grow_a_Garden)
- **Ads Manager (official):**
  - **Auto-bid only**. You set a budget and duration, and the reported cost metric is **CPP (cost per play)**.
  - Objectives: Plays, Earnings (limited) and Engagement. Engagement has a higher CPP.
  - Daily or lifetime budgets. Minimum credit purchase is 1 ad credit, and first-time card users are charged $5.
  - Robux converts to ad credits irreversibly. Earned Robux convert first at the U.S. 18+ DevEx rate. At $0.0035 per Robux, that is about 350 credits per 100k Robux (my arithmetic).
  - Audiences: New Players (never played, or not in 180+ days), Recent Players (needs 10k+), Lapsed Players (needs 20k+). Advanced targeting covers location, age, gender, genre and device.
  - Up to 10 thumbnails at 16:9.
  - The Plays objective helps the system learn and "qualify your game for Recommended For You."
  - Plays are attributed up to 30 days after the ad, and invalid-traffic refunds are applied 16 days after the campaign ends.
  - Docs advise: if there is no progress after 3–5 days, fix onboarding and the FTUE first.
  - Source: [Creator Docs: Ads Manager](https://create.roblox.com/docs/production/promotion/ads-manager)
- Engagement, monetization and retention of ad-acquired users don't count toward RFY ranking. — [Creator Docs: Discovery](https://create.roblox.com/docs/discovery)
- **Anecdotal ad costs (unverified or dated):**
  - A third-party claim puts cost per visit at about 4–12 Robux.
  - An old-system DevForum estimate: 5,000 R$ bought about 1,500 new players per day (dated).
  - Developers complain that daily budgets get spent early in the day, and some recommend lifetime budgets instead.
  - Source: [RoWatcher: Roblox Ads in 2026 break-even math](https://rowatcher.com/news/roblox-ads-in-2026-the-break-even-math-small-devs-ignore); [DevForum: Roblox sponsoring issues](https://devforum.roblox.com/t/roblox-sponsoring-issues/3379966); [DevForum: Game launch advertising cost](https://devforum.roblox.com/t/game-launch-advertising-cost/3667546)
- **Brand integration fees (separate from Ads Manager)** move to a cost-per-thousand-visits model from Jan 1, 2027:
  - $1.50 CPM for U.S. visits.
  - $0.75 for the UK, Australia, New Zealand, Canada and the Nordics.
  - $0.20 for Japan, Western Europe and South Korea.
  - $0.05 for everywhere else.
  - A flat $0.10 after 28 days live.
  - This comes from a single secondary report, and it follows Roblox's March 2026 move to take a revenue share on brand deals. — [Outlook Respawn](https://respawn.outlookindia.com/gaming/gaming-news/roblox-reveals-2027-pricing-model-for-brand-integrations)
- Free curated route: **Today's Picks / Standout Games** nominations for novel games, via a form. — [DevForum Mar 2026](https://devforum.roblox.com/t/how-we-are-improving-home-this-year/4502571)

### Inferences
- **Weekly update rhythm:** a fixed weekly update slot plus a pre-update live event lets the whole player base show up at once, which produces the CCU spikes. A predictable cadence also trains the D8–28 return habit that the June 2026 algorithm now measures.
- **Small-dev playbook implied by the rules:**
  1. Fix bounce and D1 first.
  2. Run a small Plays-objective campaign to seed impressions.
  3. Rely on organic RFY cohorts for ranking.
  4. Add a gameplay video and thumbnail tests.
  5. Nominate novel games to Today's Picks.
  6. Encourage friend invites and private servers for co-play.

### Gaps
- No official CPM/CPC or typical CPP figures for Sponsored or Search ads were found. Pricing is auto-bid only and visible in each creator's dashboard.
- No verified data on YouTuber/TikTok campaign costs or conversion for Roblox games.
- No first-party GAG or SAB developer post-mortem with retention or update-impact numbers was found.

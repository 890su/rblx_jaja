# Monetization setup (Creator Dashboard)

**Status 2026-10-11:** all 5 passes and 8 products created, on sale, managed pricing (regional + optimization) ON, IDs written to `Products.luau`. Trading/gifting declared as not allowed. Private servers: set in Studio (Game Settings → Monetization).

All IDs are configured in `src/shared/Config/Products.luau`. On 2026-10-13, a Studio client loaded Marketplace prices for all 13 configured items. The UI disables owned, restricted, inapplicable and unavailable products; no price API failure may leave a clickable purchase button.

## 1. Create game passes
Creator Dashboard → Creations → **Meteor Rush** experience → Monetization → **Passes** → Create a Pass.
Upload any 512×512 icon (placeholder is fine), then set **On Sale** + price.

| key (code) | Name | Price (R$) | Description |
|---|---|---|---|
| Coins2x | 2x Stardust | 199 | Double all creature income forever |
| Speed2x | 2x Speed | 149 | Gain Speed twice as fast |
| VIP | VIP | 299 | +50% income, VIP chat tag, +10 s station lock, gold pedestals |
| OfflinePlus | Offline x2 + Auto-collect | 249 | Earn 50% offline for up to 24 h and collect automatically |
| Expansion | Station Expansion | 399 | +2 pedestals |

Copy each pass ID (number in the pass URL) into `PASSES[...].id`.

## 2. Create developer products
Monetization → **Developer Products** → Create.

| key (code) | Name | Price (R$) | Random? |
|---|---|---|---|
| StarterPack | Starter Pack | 49 | No (fixed: Comet Cat + Solar Stag + 30 min shield) |
| Shield15 | Shield 15 min | 39 | No |
| InstantHatch | Instant Hatch | 49 | No |
| Restock | Restock Shop | 49 | No |
| Crate1 | Meteor Crate | 99 | **Yes — odds window shown in game** |
| Crate3 | Meteor Crate x3 | 249 | **Yes** |
| Crate10 | Meteor Crate x10 | 699 | **Yes** |
| ServerLuck | Server Luck 15 min | 249 | **Probability modifier — effect shown in game** |

Copy each product ID into `PRODUCTS[...].id`, then run `python -I scripts/mcp_sync.py` and publish.

## 3. Experience settings
- **Regional pricing:** Monetization → turn on for every pass/product (Roblox tests: +17–52% spend in MX/BR/PH).
- **Price optimization:** enable after ~2 weeks of sales data.
- **Private servers:** Monetization → Private Servers → enable, price **0** (crew play = friends signal).
- **Questionnaire:** Experience questionnaire must declare paid random items (crates) — answer Yes.

## 4. Compliance checklist (already implemented in code)
- Crates: every creature listed with its % (rarity % ÷ creatures in rarity), total 100% shown before purchase.
- Server Luck: per-zone before→after % table shown before purchase.
- No rewarded ads, no watch-to-earn, no admin-command sales, no escalating infinite packs.
- Receipts: idempotent by PurchaseId, granted before `PurchaseGranted`, profile saved immediately.
- Instant Hatch and Restock: reject checkout when no effect is applicable. If state changes during checkout, store a persisted credit instead of consuming the purchase without a reward. Use Credit consumes one credit only after applying its effect.
- Paid-creature stealing: both the prompt and final server transfer enforce paid-item transfer policy. Client button visibility cannot authorize a transfer.
- Checkout: one outstanding prompt per player; close the game menu before the native Roblox prompt, restore it after completion/cancellation. Repeat receipts refresh state without repeating success notices.

## Verification 2026-10-13
- 308 pure commerce assertions plus the existing persistence/economy suites passed. A two-client isolated Studio run passed 75 integration checks, including all eight product receipt paths, duplicate receipts, five pass effects, upgrades, index discovery, cursor release and stealing.
- Test profiles use `PreflightData_dev` and unique run IDs. Receipt delivery is simulated through the real receipt handler; no Robux are spent by this suite.
- Real platform checkout, cancellation, regional prices and live-server reconnect/payment recovery still require a post-publication acceptance run. See `reports/commerce-2026-10-13.md` for the exact coverage and limits.

## 5. Later (not in MVP code yet)
- Season Pass (799 R$) — live-ops, first season.
- Experience Notifications (13+ opt-in) — needs notification strings created in Dashboard → Engagement.
- Group join reward — needs the group ID.

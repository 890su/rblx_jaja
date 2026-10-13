# Meteor Heist — menus and navigation

Status: implemented and verified in Studio (user requested a complete redesign, 2026-10-13).

## Player goals

Buy a creature, improve movement/base, manage storage, inspect discoveries, and
find optional rewards/social actions without memorizing a rainbow of buttons.

## Visual language

Deep navy surfaces, readable near-white text, teal primary actions, quiet borders
and 12–18 px corners. Rarity accents belong to creatures. Use native vector icons
alongside labels; symbols must never depend on emoji or an uploaded asset.
Keep the actual 3D creature previews. Price, stock and eligibility remain explicit.

## Navigation

Desktop/tablet: six consistent destinations inside each main window: Shop,
Upgrades, Robux, Station, Collection, Menu. Selected destination has both a color
and underline. Mobile: retain content space and use the header grid button to
open a two-column hub grouped into Explore, Progress, Social. The play HUD keeps
Shop, Station and More. Each touch action and Close is at least 48 px high.
Closing returns to play. Back on the hub / gamepad B returns to the previous
surface. Odds keep a path to the Robux store. M opens the hub; Tab starts focus.
Only one surface owns input; gameplay HUD is hidden while notifications remain.

## Content and states

- Shop: loading before a snapshot; creature art/name/rarity/price/remaining stock;
  Buy to storage when base is full; disabled Sold out / insufficient funds.
- Robux: permanent perks separated from one-time purchases; native prices,
  owned/loading/policy-restricted/unavailable/receipt-pending states preserved.
- Upgrades: clear name, description, level/effect and price; max/funds states.
- Station: two lists; select a slot then a stored creature; preview the replacement
  name; old creature stays in storage on swap; sale still needs confirmation.
  Reuse rows on snapshots to preserve focus and scroll. Short screens show counts
  in the title and 48 px rows.
- Collection: persistent discovery count/progress and All/Discovered/Undiscovered
  filters; locked creatures keep silhouette art.
- Hub: visible destination labels, social actions return to play.

## Responsive and motion policy

Use CoreUISafeInsets. Small/short screens collapse desktop tabs; lists scroll
vertically. A short Shop uses one horizontal product row with a full 48 px CTA.
Panels open with a short 8 px slide; hover/focus changes outline and press scale
returns to 1. Cancel old tweens on rapid input and honor Roblox's Reduced Motion
setting. No animated preview grid. Short Upgrade/Index rows retain visible
actions/names, and Daily codes scroll while Claim stays fixed.
Localization uses Locale keys and separate icon geometry.

## Validation

Static formatting/lint/strict checks; real two-client isolated commerce regression;
desktop, small landscape phone, notched phone and tablet visual inspection. Record
viewport dimensions and any tool limitations in the verification report.

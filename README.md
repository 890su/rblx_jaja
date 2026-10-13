# Meteor Heist

Roblox game built with [Rojo](https://rojo.space). Design and plans: `docs/` (start with `docs/01-game-design.md`).

## Development

1. Install the toolchain: `aftman install`
2. Open the DEV place in Roblox Studio (Studio MCP server enabled).
3. Push code: `python -I scripts/mcp_sync.py` (re-run after every change). Alternative: `rojo serve` + Rojo plugin.

## Structure

- `src/shared` → ReplicatedStorage/Shared — `Config/` (all tuning numbers), `Theme/` (reskin layer), `Types`, `Remotes`, `Clock`, `Util/`
- `src/server` → ServerScriptService/Server — `Services/` (authoritative game systems)
- `src/client` → StarterPlayerScripts/Client — `Controllers/` (rendering, input, UI)

Bootstrap is two-phase: every Service/Controller module may export `init()` (wire-up, no yielding) and `start()` (runs in its own thread).

## Localization

- Source language English; 13 languages AI auto-translated in Creator Hub (strings + experience info).
- Player-facing sentences live in `src/shared/Locale` as keyed templates; the server sends `Notifier.send(player, key, args)`, the client renders `Locale.t(key, args)`. Translatable words passed as args use `Locale.ref(term)`.
- World labels keep words and numbers in separate TextLabels (words auto-localize, numbers don't).
- After adding strings: `python -I scripts/mcp_sync.py` → `python -I scripts/export_locale_csv.py` → upload `localization/upload/part*.csv` one by one (Creator Hub → Localization → Table management → Upload CSV; the full file times out).

## Checks

- Format: `stylua --check src tests`
- Lint: `selene src tests`
- Types: `bash scripts/typecheck.sh` (luau-lsp, strict)
- Unit tests: `tests/*.spec.luau` — run in Studio Edit mode via MCP `execute_luau` (returns `PASS n`)
- Run all Studio checks: `python -I scripts/run_studio_checks.py` (Edit mode)
- Packages: `wally install` (ServerPackages is git-ignored; synced by `mcp_sync.py`)
- Build: `rojo build -o build.rbxl`

## Release checks

Zone identity, emotes and the owner's weekly work: [design roadmap](docs/09-zone-and-emote-roadmap.md). First emote: `Wave` button or **G**, with separate R6/R15 poses.

Current fixes, test results and remaining launch requirements: [pre-production report](reports/preprod-2026-10-12.md). Multi-client integration checks run only in Studio with `StudioTestService` arguments `suite = "preprod"`, `mode = "transactions"` and a unique `runId`; they use an isolated `PreflightData_dev` store and synthetic receipts. For station capacity, use eight clients and `mode = "capacity"`.

`assets/Assets.rbxmx` and `assets/AssistantMaterials.rbxmx` are part of the Rojo build. Refresh the snapshots with `python -I scripts/export_studio_assets.py` after intentional Studio asset changes.

`src/shared/Config/Environment.luau` identifies the release universe/place. Only that pair uses `PlayerData` and `Transfers`; Studio uses `_dev`, and other published places use `_dev_<PlaceId>`. Update the release IDs deliberately when moving LIVE to another place.

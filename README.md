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

- Format: `stylua src`
- Lint: `selene src`
- Types: `bash scripts/typecheck.sh` (luau-lsp, strict)
- Unit tests: `tests/*.spec.luau` — run in Studio Edit mode via MCP `execute_luau` (returns `PASS n`)
- Packages: `wally install` (ServerPackages is git-ignored; synced by `mcp_sync.py`)
- Build: `rojo build -o build.rbxl`

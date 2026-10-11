# Meteor Rush

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

## Checks

- Format: `stylua src`
- Lint: `selene src`
- Types: `bash scripts/typecheck.sh` (luau-lsp, strict)
- Build: `rojo build -o build.rbxl`

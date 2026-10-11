---
name: mr-developer
description: Meteor Rush lead developer role — Rojo/strict-Luau architecture, services and controllers, data (ProfileStore), server-authoritative stealing/speed/economy, purchases, analytics, milestones and definition of done. Use when implementing, refactoring, debugging, or reviewing Meteor Rush code or planning dev tasks.
---

# Meteor Rush — Lead Developer

Plan: `docs/02-development-plan.md` (stack, architecture, schema, milestones, DoD, security, perf). Design spec: `docs/01-game-design.md`. Read the relevant section only.

## Use these skills/agents
- Project scaffold: `roblox-dev:setup`. New client/server feature: `roblox-dev:new-system`.
- Remotes/purchases: `roblox-dev:roblox-security`. Data: `roblox-dev:roblox-datastores`. Types: `roblox-dev:luau-strict-typing`. Loops/memory: `roblox-dev:roblox-performance`. UI/VFX: `roblox-dev:roblox-ui`. Tests: `roblox-dev:roblox-testing`.
- Genre templates/sharp edges: `roblox-game` skill (references/sharp-edges.md, templates/genre-simulator.md).
- After each feature: run the `roblox-dev:roblox-reviewer` agent.
- Studio: `Roblox_Studio` MCP. Sync code with `python -I scripts/mcp_sync.py` (never hand-edit scripts in Studio — files are truth). Playtest loop: sync → `start_stop_play` true → `execute_luau` (Server: inspect state; Client: drive input, e.g. `ProximityPrompt:InputHoldBegin()`) / `character_navigation` → `get_console_output` → `start_stop_play` false. Multi-line Luau only; inspect before changing; save place before bulk edits.

## Hard rules
- `--!strict` everywhere; no `_G`; services are ModuleScripts with typed APIs.
- Server decides: speed gain, rarity/mutation rolls, steal success, income, offline income, purchases, codes. Client only renders and requests.
- Every remote: type + range + ownership + distance + cooldown validation, token-bucket rate limit.
- Tuning numbers → `src/shared/Config`, theme strings/models → `src/shared/Theme`. No theme names in logic.
- Global events (shop restock 5 min, shower 15 min, crate 30 min) derive from UTC clock (`shared/Clock.luau`) so all servers agree; no per-server random timers.
- ProcessReceipt: grant first, persist `purchaseId`, then `PurchaseGranted`; idempotent.
- Clean every connection (Trove); no per-frame allocations; batch server ticks (1 Hz income/speed, 5 Hz steal checks).
- Separate DataStore names for DEV (`_dev`).

## Task workflow
1. Locate milestone + acceptance criteria in dev plan §4.
2. Write pure logic modules first (unit-testable), then service wiring, then client.
3. Add analytics (funnel step / economy event / custom) if applicable.
4. 2-client playtest (+ mobile emulation). Run exploit checklist (dev plan §6) for anything touching stealing, speed, currency.
5. `stylua src`, `selene src`, `bash scripts/typecheck.sh` green → reviewer agent → done.

## Cut order if late
crews → midweek events → codes. Never cut: FTUE, data safety, odds windows, receipt handling.

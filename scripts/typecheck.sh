#!/usr/bin/env bash
# Strict type check with luau-lsp. Roblox type definitions are pinned to the
# luau-lsp version in aftman.toml so CI and local runs see the same API.
# Needs ServerPackages: run `wally install` after cloning.
set -euo pipefail
cd "$(dirname "$0")/.."
LSP_VERSION=1.70.1
DEFS=".luau/globalTypes-${LSP_VERSION}.d.luau"
mkdir -p .luau
[ -f "$DEFS" ] || curl -fsSL -o "$DEFS" \
	"https://raw.githubusercontent.com/JohnnyMorganz/luau-lsp/${LSP_VERSION}/scripts/globalTypes.d.luau"
rojo sourcemap default.project.json -o sourcemap.json
luau-lsp analyze --sourcemap=sourcemap.json --definitions="$DEFS" src tests

#!/usr/bin/env bash
# Strict type check with luau-lsp (downloads Roblox type definitions once).
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .luau
[ -f .luau/globalTypes.d.luau ] || curl -sL -o .luau/globalTypes.d.luau \
	https://raw.githubusercontent.com/JohnnyMorganz/luau-lsp/main/scripts/globalTypes.d.luau
rojo sourcemap default.project.json -o sourcemap.json
luau-lsp analyze --sourcemap=sourcemap.json --definitions=.luau/globalTypes.d.luau src

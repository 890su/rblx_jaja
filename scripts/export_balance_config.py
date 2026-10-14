"""Export the actual synced Studio config for tools/balance_sim.py (Edit only)."""
from pathlib import Path
import importlib.util
import json
import sys

ROOT = Path(__file__).resolve().parent.parent
spec = importlib.util.spec_from_file_location("mcp_sync", ROOT / "scripts/mcp_sync.py")
sync = importlib.util.module_from_spec(spec)
spec.loader.exec_module(sync)

CODE = '''
local s = game.ReplicatedStorage.Shared
local function c(name) return require(s.Config[name]) end
return game.HttpService:JSONEncode({
    zones = c("Zones").ZONES, guarantee = c("Zones").FIRST_VISIT_GUARANTEE,
    rarity = c("Rarity").INFO, mutations = c("Rarity").MUTATIONS,
    speed = c("Speed"), economy = c("Economy"), upgrades = c("Upgrades"),
    canyons = c("Canyons"), arena = c("Arena"),
    creatures = c("Creatures").LIST, events = c("Events"),
    serverLuck = c("Products").SERVER_LUCK,
    boostAboveZoneFloor = require(s.Util.Odds).minimum ~= nil,
})
'''

def main():
    target = Path(sys.argv[1])
    mcp = sync.Mcp()
    try:
        sid = mcp.studio_id()
        state = mcp.tool("get_studio_state", {"studio_id": sid})
        if "Available DataModels: Edit" not in state:
            raise RuntimeError("Stop Play before exporting config")
        value = mcp.tool("execute_luau", {"studio_id": sid, "datamodel_type": "Edit", "code": CODE})
        data = json.loads(value)
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")
        print(f"Exported {len(data['zones'])} zones to {target}")
    finally:
        mcp.close()

if __name__ == "__main__":
    main()

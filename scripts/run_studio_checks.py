"""Run existing pure Luau checks through MCP, without editing the place."""
from pathlib import Path
import importlib.util

ROOT = Path(__file__).resolve().parent.parent
spec = importlib.util.spec_from_file_location("mcp_sync", ROOT / "scripts" / "mcp_sync.py")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
Mcp = module.Mcp

def main():
    mcp = Mcp()
    try:
        sid = mcp.studio_id()
        state = mcp.tool("get_studio_state", {"studio_id": sid})
        if "Available DataModels: Edit" not in state:
            raise RuntimeError("Stop the playtest before running Edit checks")
        failures = []
        for path in sorted((ROOT / "tests").glob("*.spec.luau")):
            code = "local function run()\n" + path.read_text(encoding="utf-8") + "\nend\nreturn run()"
            result = mcp.tool("execute_luau", {"studio_id": sid, "datamodel_type": "Edit", "code": code})
            print(f"{path.name}: {result}")
            if not result.startswith("PASS "):
                failures.append(f"{path.name}: {result}")
        if failures:
            raise RuntimeError("\n".join(failures))
    finally:
        mcp.close()

if __name__ == "__main__":
    main()

"""Export the cloud localization table CSV from shared/Locale (run in Studio via
the Studio MCP server) to localization/meteor_heist.csv.

Upload it in Creator Hub → Localization → Table management → Upload CSV.
Roblox AI auto-translation then fills every enabled language.

Usage: python -I scripts/export_locale_csv.py   (after scripts/mcp_sync.py)
"""

import importlib.util
import sys
from pathlib import Path

sys.stdout.reconfigure(encoding="utf-8")
ROOT = Path(__file__).resolve().parent.parent
spec = importlib.util.spec_from_file_location("mcp_sync", ROOT / "scripts" / "mcp_sync.py")
mcp_sync = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mcp_sync)

LUAU = """
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Locale = require(Shared.Locale)
local Products = require(Shared.Config.Products)
local Daily = require(Shared.Config.Daily)
local extra = {}
for _, item in Products.PASSES do table.insert(extra, item.name) table.insert(extra, item.description) end
for _, item in Products.PRODUCTS do table.insert(extra, item.name) table.insert(extra, item.description) end
for _, reward in Daily.REWARDS do table.insert(extra, reward.label) end
return Locale.csv(extra)
"""


def main() -> int:
    mcp = mcp_sync.Mcp()
    try:
        sid = mcp.studio_id()
        csv = mcp.tool("execute_luau", {"code": LUAU, "datamodel_type": "Edit", "studio_id": sid})
    finally:
        mcp.close()
    out = ROOT / "localization" / "meteor_heist.csv"
    out.parent.mkdir(exist_ok=True)
    out.write_text(csv + "\n", encoding="utf-8")
    rows = csv.count("\n")
    print(f"wrote {out} ({rows} entries)")

    # Creator Hub times out on big uploads: also write 30-row parts.
    import csv as csvlib
    import io

    parsed = list(csvlib.reader(io.StringIO(csv)))
    header, body = parsed[0], [r for r in parsed[1:] if any(r)]
    parts = ROOT / "localization" / "upload"
    parts.mkdir(exist_ok=True)
    for old in parts.glob("*.csv"):
        old.unlink()
    for i in range(0, len(body), 30):
        buf = io.StringIO()
        writer = csvlib.writer(buf, lineterminator="\n")
        writer.writerow(header)
        writer.writerows(body[i : i + 30])
        (parts / f"part{i // 30 + 1}.csv").write_text(buf.getvalue(), encoding="utf-8")
    print(f"wrote {len(range(0, len(body), 30))} upload parts to {parts}")
    return 0


if __name__ == "__main__":
    sys.exit(main())

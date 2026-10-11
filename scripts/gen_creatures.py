"""Generate creature meshes in Studio via the Studio MCP `generate_mesh` tool and
store them as ReplicatedStorage.Assets.Creatures.<id> (normalized size, anchored,
non-colliding). Skips creatures that already exist. Assets live in the place
file: save/publish the place afterwards.

Usage: python -I scripts/gen_creatures.py [id ...]
"""

from __future__ import annotations

import importlib.util
import sys
from pathlib import Path

sys.stdout.reconfigure(encoding="utf-8")
spec = importlib.util.spec_from_file_location("mcp_sync", Path(__file__).with_name("mcp_sync.py"))
mcp_sync = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mcp_sync)

STYLE = (
    "cute chibi Roblox pet, stylized low-poly toy look, big expressive eyes, bright saturated colors, "
    "standing pose, single character, no base, no ground"
)

# id: (rarity, description)
CREATURES = {
    "pebblit": ("Common", "a small grey pebble creature with tiny legs and sparkly eyes"),
    "dustbun": ("Common", "a fluffy beige dust bunny with long floppy ears"),
    "cindermite": ("Common", "a tiny orange ember mite with glowing lava cracks"),
    "glowgrub": ("Common", "a chubby lime green glowing grub"),
    "rockroo": ("Common", "a little stone kangaroo with a crystal in its pouch"),
    "emberfox": ("Uncommon", "a red fox with a flame-tipped tail"),
    "sparkle_snail": ("Uncommon", "a snail with a glittering purple spiral shell"),
    "crater_crab": ("Uncommon", "a crab whose shell looks like a cratered moon"),
    "moon_moth": ("Uncommon", "a pale moth with crescent-moon shaped wings"),
    "pulsar_pup": ("Uncommon", "a puppy with pulsing blue energy spots"),
    "frostfin": ("Rare", "a floating icy blue fish with frosty crystal fins"),
    "comet_cat": ("Rare", "a small round blue cat with a glowing comet tail"),
    "nebula_newt": ("Rare", "a newt with purple and pink nebula patterned skin"),
    "orbit_owl": ("Rare", "an owl with a small planetary ring orbiting its head"),
    "quartz_quokka": ("Rare", "a smiling quokka made of pink quartz crystals"),
    "void_viper": ("Epic", "a dark purple snake with a starry void pattern"),
    "solar_stag": ("Epic", "a golden deer with sun-ray antlers"),
    "plasma_panda": ("Epic", "a panda with glowing cyan plasma patches"),
    "aurora_axolotl": ("Epic", "an axolotl with aurora colored glowing frills"),
    "ion_ibex": ("Epic", "an ibex with electric blue curled horns crackling with energy"),
    "nova_drake": ("Legendary", "a small dragon with exploding star wings, orange and white"),
    "galaxy_griffin": ("Legendary", "a griffin with galaxy patterned wings"),
    "eclipse_lynx": ("Legendary", "a black lynx with a glowing eclipse corona mane"),
    "starlight_seraph": ("Legendary", "a small angelic creature with six star shaped wings"),
    "meteor_mammoth": ("Legendary", "a baby mammoth with glowing meteor-rock tusks"),
    "cosmic_leviathan": ("Mythic", "a small sea serpent with a swirling cosmic galaxy body"),
    "quasar_phoenix": ("Mythic", "a phoenix with a brilliant white-blue quasar beam tail"),
    "singularity_sprite": ("Mythic", "a tiny fairy orbiting a small black hole sphere"),
    "celestial_kirin": ("Mythic", "a kirin with a constellation patterned body and glowing mane"),
    "big_bang_bunny": ("Mythic", "a bunny with explosive rainbow energy ears"),
}

HEIGHT = {"Common": 3, "Uncommon": 3.3, "Rare": 3.6, "Epic": 4, "Legendary": 4.5, "Mythic": 5}

MARK_EXISTING = """
for _, c in workspace:GetChildren() do c:SetAttribute("GenSeen", true) end
local assets = game:GetService("ReplicatedStorage"):FindFirstChild("Assets")
local creatures = assets and assets:FindFirstChild("Creatures")
return creatures and creatures:FindFirstChild(%s) and "exists" or "missing"
"""

STORE = """
local id, height = %s, %s
local model
for _, c in workspace:GetChildren() do
	if c:IsA("Model") and not c:GetAttribute("GenSeen") then model = c end
end
if not model then return "no new model" end
local RS = game:GetService("ReplicatedStorage")
local assets = RS:FindFirstChild("Assets") or Instance.new("Folder")
assets.Name = "Assets" assets.Parent = RS
local folder = assets:FindFirstChild("Creatures") or Instance.new("Folder")
folder.Name = "Creatures" folder.Parent = assets
local biggest
for _, p in model:GetDescendants() do
	if p:IsA("BasePart") then
		p.Anchored = true p.CanCollide = false p.CanQuery = false p.CanTouch = false p.Massless = true
		if not biggest or p.Size.Magnitude > biggest.Size.Magnitude then biggest = p end
	end
end
model.PrimaryPart = biggest
local size = model:GetExtentsSize()
if size.Y > 0 then model:ScaleTo(model:GetScale() * height / size.Y) end
model:PivotTo(CFrame.new())
model.Name = id
model:SetAttribute("CreatureId", id)
model.Parent = folder
return "stored " .. id .. " " .. tostring(model:GetExtentsSize())
"""


def main() -> int:
    only = set(sys.argv[1:])
    mcp = mcp_sync.Mcp()
    try:
        sid = mcp.studio_id()
        for cid, (rarity, desc) in CREATURES.items():
            if only and cid not in only:
                continue
            state = mcp.tool("execute_luau", {"code": MARK_EXISTING % f'"{cid}"', "datamodel_type": "Edit", "studio_id": sid})
            if state == "exists":
                print(f"skip {cid}", flush=True)
                continue
            prompt = f"{desc}, {STYLE}"
            try:
                mcp.request(
                    "tools/call",
                    {"name": "generate_mesh", "arguments": {
                        "studio_id": sid, "textPrompt": prompt, "segmentation": "none", "maxTriangles": 4000,
                        "size": {"x": 4, "y": 4, "z": 4},
                    }},
                    timeout=900,
                )
            except Exception as e:  # keep going with the rest
                print(f"FAIL {cid}: {e}", flush=True)
                continue
            out = mcp.tool("execute_luau", {"code": STORE % (f'"{cid}"', HEIGHT[rarity]), "datamodel_type": "Edit", "studio_id": sid})
            print(out, flush=True)
    finally:
        mcp.close()
    return 0


if __name__ == "__main__":
    sys.exit(main())

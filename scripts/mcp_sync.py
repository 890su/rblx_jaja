"""Push src/ into the open Roblox Studio place through Studio's MCP server.

One-way sync (files are the source of truth), mirroring default.project.json:
  src/shared -> ReplicatedStorage.Shared
  src/server -> ServerScriptService.Server
  src/client -> StarterPlayer.StarterPlayerScripts.Client
  ServerPackages (Wally) -> ServerScriptService.ServerPackages
Rojo file conventions: init.server.luau / init.client.luau / init.luau turn the
folder into a Script / LocalScript / ModuleScript; *.server.luau -> Script,
*.client.luau -> LocalScript, other *.luau -> ModuleScript.

Usage: python -I scripts/mcp_sync.py [--dry-run]
"""

from __future__ import annotations

import json
import os
import queue
import re
import subprocess
import sys
import threading
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
MAPPINGS = [
    ("src/shared", 'game:GetService("ReplicatedStorage")', "Shared"),
    ("src/server", 'game:GetService("ServerScriptService")', "Server"),
    ("src/client", 'game:GetService("StarterPlayer"):WaitForChild("StarterPlayerScripts")', "Client"),
    ("ServerPackages", 'game:GetService("ServerScriptService")', "ServerPackages"),
]


def long_string(text: str) -> str:
    level = 0
    while f"]{'=' * level}]" in text:
        level += 1
    eq = "=" * level
    # A leading newline right after the opening bracket is dropped by Lua, so add one.
    return f"[{eq}[\n{text}]{eq}]"


def class_for_file(name: str) -> tuple[str, str] | None:
    for suffix, cls in (
        (".server.luau", "Script"), (".client.luau", "LocalScript"), (".luau", "ModuleScript"),
        (".server.lua", "Script"), (".client.lua", "LocalScript"), (".lua", "ModuleScript"),
    ):
        if name.endswith(suffix):
            return name[: -len(suffix)], cls
    return None


def node_for(path: Path, name: str) -> dict:
    """Build {name, class, source?, children[]} for a file or directory."""
    if path.is_file():
        info = class_for_file(path.name)
        assert info, path
        return {"name": info[0], "class": info[1], "source": path.read_text(encoding="utf-8"), "children": []}
    nested = path / "default.project.json"
    if nested.exists():  # Wally package: a nested Rojo project pointing at one file/dir
        target = json.loads(nested.read_text(encoding="utf-8"))["tree"]["$path"]
        node = node_for(path / target, name)
        node["name"] = name
        return node
    init_class, source = "Folder", None
    for init_name, cls in (
        ("init.server.luau", "Script"), ("init.client.luau", "LocalScript"), ("init.luau", "ModuleScript"),
        ("init.server.lua", "Script"), ("init.client.lua", "LocalScript"), ("init.lua", "ModuleScript"),
    ):
        init = path / init_name
        if init.exists():
            init_class, source = cls, init.read_text(encoding="utf-8")
            break
    children = []
    for child in sorted(path.iterdir()):
        if child.name.startswith("init.") or child.name.startswith("."):
            continue
        if child.is_dir():
            children.append(node_for(child, child.name))
        elif class_for_file(child.name):
            children.append(node_for(child, class_for_file(child.name)[0]))
    return {"name": name, "class": init_class, "source": source, "children": children}


def emit(node: dict, var: str, lines: list[str], counter: list[int]) -> None:
    lines.append(f'local {var} = Instance.new("{node["class"]}")')
    lines.append(f"{var}.Name = {json.dumps(node['name'])}")
    if node["source"] is not None:
        lines.append(f"{var}.Source = {long_string(node['source'])}")
    for child in node["children"]:
        counter[0] += 1
        child_var = f"n{counter[0]}"
        emit(child, child_var, lines, counter)
        lines.append(f"{child_var}.Parent = {var}")


def build_chunk(src: str, parent_expr: str, name: str) -> str | None:
    if not (ROOT / src).exists():
        return None
    node = node_for(ROOT / src, name)
    lines = ["local parent = " + parent_expr]
    lines.append(f'local old = parent:FindFirstChild({json.dumps(name)})')
    lines.append("if old then old:Destroy() end")
    emit(node, "root", lines, [0])
    lines.append('root:SetAttribute("SyncedBy", "mcp_sync")')
    lines.append("root.Parent = parent")
    lines.append(f'return "synced {name}"')
    return "\n".join(lines)


class Mcp:
    def __init__(self) -> None:
        bat = os.path.expandvars(r"%LOCALAPPDATA%\Roblox\mcp.bat")
        self.proc = subprocess.Popen(
            ["cmd.exe", "/c", bat], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL
        )
        self.q: queue.Queue[bytes] = queue.Queue()
        threading.Thread(target=self._pump, daemon=True).start()
        self.next_id = 1
        self.request("initialize", {"protocolVersion": "2025-06-18", "capabilities": {},
                                    "clientInfo": {"name": "mcp_sync", "version": "1"}})
        self._send({"jsonrpc": "2.0", "method": "notifications/initialized"})

    def _pump(self) -> None:
        for line in iter(self.proc.stdout.readline, b""):
            self.q.put(line)

    def _send(self, msg: dict) -> None:
        self.proc.stdin.write((json.dumps(msg) + "\n").encode())
        self.proc.stdin.flush()

    def request(self, method: str, params: dict, timeout: float = 120) -> dict:
        rid = self.next_id
        self.next_id += 1
        self._send({"jsonrpc": "2.0", "id": rid, "method": method, "params": params})
        end = time.time() + timeout
        while time.time() < end:
            try:
                msg = json.loads(self.q.get(timeout=max(0.1, end - time.time())))
            except queue.Empty:
                break
            except ValueError:
                continue
            if msg.get("id") == rid:
                if "error" in msg:
                    raise RuntimeError(msg["error"])
                return msg["result"]
        raise TimeoutError(method)

    def tool(self, name: str, args: dict) -> str:
        result = self.request("tools/call", {"name": name, "arguments": args})
        text = "".join(c.get("text", "") for c in result.get("content", []))
        if result.get("isError"):
            raise RuntimeError(f"{name}: {text}")
        return text

    def studio_id(self, attempts: int = 10) -> str:
        for _ in range(attempts):
            studios = json.loads(self.tool("list_roblox_studios", {})).get("studios", [])
            if studios:
                return studios[0]["id"]
            time.sleep(1.5)
        raise RuntimeError("No Roblox Studio connected to MCP (open a place, enable Studio as MCP server)")

    def close(self) -> None:
        self.proc.kill()


def main() -> int:
    chunks = [c for c in (build_chunk(*m) for m in MAPPINGS) if c]
    if "--dry-run" in sys.argv:
        for chunk in chunks:
            print(chunk[:400], "...\n")
        return 0
    mcp = Mcp()
    try:
        sid = mcp.studio_id()
        mcp.tool("execute_luau", {"code": 'workspace.StreamingEnabled = true return "ok"',
                                  "datamodel_type": "Edit", "studio_id": sid})
        for chunk in chunks:
            print(mcp.tool("execute_luau", {"code": chunk, "datamodel_type": "Edit", "studio_id": sid}))
    finally:
        mcp.close()
    return 0


if __name__ == "__main__":
    sys.exit(main())
